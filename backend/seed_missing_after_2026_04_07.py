import os
import random
import sys
from datetime import datetime, timedelta, timezone

import firebase_admin
from firebase_admin import credentials, firestore

SERVICE_ACCOUNT_PATH = os.path.join(os.path.dirname(__file__), "serviceAccountKey.json")
if not os.path.exists(SERVICE_ACCOUNT_PATH):
    raise FileNotFoundError("serviceAccountKey.json not found in backend/")

try:
    firebase_admin.get_app()
except ValueError:
    cred = credentials.Certificate(SERVICE_ACCOUNT_PATH)
    firebase_admin.initialize_app(cred)

db = firestore.client()

DEVICE_ID = sys.argv[1] if len(sys.argv) > 1 else "agos-zksl9QK3"
START_UTC = datetime(2026, 4, 7, 18, 0, 0, tzinfo=timezone.utc)
STEP_MINUTES = 30
USABLE_CAPACITY_L = 106.0

# Weekday profile from 2026-02-28..2026-04-07 data window (liters/day)
# Monday=0 .. Sunday=6
WEEKDAY_USAGE_L = {
    0: 17.53,
    1: 17.28,
    2: 19.77,
    3: 16.89,
    4: 23.21,
    5: 20.16,
    6: 18.19,
}


def activity_factor(hour_utc: int) -> float:
    if 0 <= hour_utc <= 4:
        return 0.05
    if 5 <= hour_utc <= 7:
        return 0.35
    if 8 <= hour_utc <= 17:
        return 1.70
    if 18 <= hour_utc <= 21:
        return 1.10
    return 0.45


def quality_values(spike: bool) -> tuple[float, float, float]:
    if spike:
        return (
            round(random.uniform(110.0, 140.0), 2),
            round(random.uniform(5.0, 5.8), 2),
            round(random.uniform(1100.0, 1400.0), 1),
        )
    return (
        round(random.uniform(12.0, 45.0), 2),
        round(random.uniform(6.5, 8.5), 2),
        round(random.uniform(200.0, 750.0), 1),
    )


def status_from_level(level: float) -> str:
    if level >= 75.0:
        return "optimal"
    if level >= 50.0:
        return "moderate"
    return "low"


def floor_to_half_hour(dt: datetime) -> datetime:
    minute = 0 if dt.minute < 30 else 30
    return dt.replace(minute=minute, second=0, microsecond=0)


now_utc = floor_to_half_hour(datetime.now(timezone.utc))
if now_utc <= START_UTC:
    print("No gap to seed.")
    raise SystemExit(0)

print(f"Preparing backfill for {DEVICE_ID}")
print(f"Range: {START_UTC.isoformat()} -> {now_utc.isoformat()} (UTC)")

existing = set()
query = (
    db.collection("sensor_readings")
    .where("device_id", "==", DEVICE_ID)
    .where("timestamp", ">=", START_UTC)
    .where("timestamp", "<=", now_utc)
)

for doc in query.stream():
    row = doc.to_dict()
    ts = row.get("timestamp")
    if isinstance(ts, datetime):
        ts = ts.astimezone(timezone.utc)
        existing.add(ts.strftime("%Y-%m-%dT%H:%M"))

print(f"Existing points in range: {len(existing)}")

batch = db.batch()
batch_count = 0
written = 0

# Start around current backend baseline so charts stay consistent.
volume_l = 72.0
refill_active = False

cursor = START_UTC
point_index = 0
while cursor <= now_utc:
    key = cursor.strftime("%Y-%m-%dT%H:%M")
    if key not in existing:
        weekday_daily_l = WEEKDAY_USAGE_L[cursor.weekday()]
        steps_per_day = int((24 * 60) / STEP_MINUTES)
        base_use = weekday_daily_l / steps_per_day
        use = base_use * activity_factor(cursor.hour) * random.uniform(0.8, 1.25)

        level_pct = (volume_l / USABLE_CAPACITY_L) * 100.0
        if level_pct <= 24.0:
            refill_active = True
        if level_pct >= 94.0:
            refill_active = False

        refill = 0.0
        if refill_active and cursor.hour in (2, 3, 4, 5):
            refill = random.uniform(1.2, 2.8)

        volume_l = max(0.0, min(USABLE_CAPACITY_L, volume_l - use + refill))
        level = round((volume_l / USABLE_CAPACITY_L) * 100.0, 1)

        spike = (point_index % 120) == 0  # occasional anomaly
        turbidity, ph, tds = quality_values(spike=spike)

        pump_active = (turbidity > 50.0) or not (6.0 <= ph <= 9.5) or (tds > 1000.0)

        payload = {
            "device_id": DEVICE_ID,
            "timestamp": cursor,
            "level": level,
            "volume": round(volume_l, 1),
            "capacity": USABLE_CAPACITY_L,
            "flow_rate": 0.0,
            "pump_active": pump_active,
            "turbidity": turbidity,
            "ph": ph,
            "tds": tds,
            "temperature": round(random.uniform(24.0, 31.5), 1),
            "status": status_from_level(level),
        }

        batch.set(db.collection("sensor_readings").document(), payload)
        batch_count += 1
        written += 1

        if batch_count >= 450:
            batch.commit()
            batch = db.batch()
            batch_count = 0

    cursor += timedelta(minutes=STEP_MINUTES)
    point_index += 1

if batch_count > 0:
    batch.commit()

print(f"Inserted missing points: {written}")
print(f"Done. Coverage up to: {now_utc.isoformat()} UTC")
