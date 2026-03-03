"""
Seed Firestore with 30 days of mock sensor readings for esp32-sim-001.
Run once after placing serviceAccountKey.json in the backend/ folder:

    python seed_firestore.py

This gives the dashboard charts instant data across all time periods (1H, 24H, 7D, 30D).
"""

import os
import random
from datetime import datetime, timedelta, timezone

import firebase_admin
from firebase_admin import credentials, firestore

_SERVICE_ACCOUNT_PATH = os.path.join(os.path.dirname(__file__), "serviceAccountKey.json")

if not os.path.exists(_SERVICE_ACCOUNT_PATH):
    raise FileNotFoundError(
        "serviceAccountKey.json not found in backend/. "
        "Download it from Firebase Console → Project Settings → Service Accounts."
    )

cred = credentials.Certificate(_SERVICE_ACCOUNT_PATH)
firebase_admin.initialize_app(cred)
db = firestore.client()

print(f"Seeding Firestore with 30 days of sensor readings (UTC timestamps)...")


def random_reading(timestamp: datetime, spike: bool = False) -> dict:
    if spike:
        turbidity = random.uniform(8.0, 15.0)
        ph = random.uniform(5.0, 6.0)
        tds = random.uniform(520, 650)
    else:
        turbidity = random.uniform(1.5, 4.5)
        ph = random.uniform(6.8, 7.6)
        tds = random.uniform(200, 450)

    level = random.uniform(55, 85)
    pump_active = turbidity > 5 or not (6.5 <= ph <= 8.3) or tds > 500

    return {
        "device_id": "placeholder",  # overridden by caller
        "timestamp": timestamp,
        "level": round(level, 1),
        "volume": round(level / 100 * 50000, 0),
        "flow_rate": round(random.uniform(130, 160), 1),
        "pump_active": pump_active,
        "turbidity": round(turbidity, 2),
        "ph": round(ph, 2),
        "tds": round(tds, 1),
        "temperature": round(random.uniform(20, 30), 1),
        "status": "optimal" if level >= 75 else "moderate" if level >= 50 else "low",
    }



DEVICE_IDS = ["agos-zksl9QK3", "agos-3JGRl6wM"]

now = datetime.now(timezone.utc)  # Use UTC to match SERVER_TIMESTAMP
batch_size = 400  # Firestore batch limit is 500
total_written = 0

for DEVICE_ID in DEVICE_IDS:
    print(f"\nSeeding {DEVICE_ID}...")
    batch = db.batch()
    count_in_batch = 0

    # ── Dense: 5-minute intervals for the last 24 hours (288 points) ──────────
    for i in range(288):
        ts = now - timedelta(minutes=(287 - i) * 5)
        spike = (i % 60 == 0)  # periodic spike
        doc = random_reading(ts, spike=spike)
        doc["device_id"] = DEVICE_ID
        ref = db.collection("sensor_readings").document()
        batch.set(ref, doc)
        count_in_batch += 1
        total_written += 1

        if count_in_batch >= batch_size:
            batch.commit()
            batch = db.batch()
            count_in_batch = 0
            print(f"  Written {total_written} docs...")

    # ── Sparse: 30-minute intervals from day 2 to day 30 ────────────────────
    # (24h at 30-min = 48 per day × 29 days = 1392 more points)
    for day in range(1, 30):
        for half_hour in range(48):
            ts = now - timedelta(days=day) + timedelta(minutes=half_hour * 30)
            spike = (day % 7 == 0 and half_hour == 10)  # weekly spike
            doc = random_reading(ts, spike=spike)
            doc["device_id"] = DEVICE_ID
            ref = db.collection("sensor_readings").document()
            batch.set(ref, doc)
            count_in_batch += 1
            total_written += 1

            if count_in_batch >= batch_size:
                batch.commit()
                batch = db.batch()
                count_in_batch = 0
                print(f"  Written {total_written} docs...")

    # Commit remaining
    if count_in_batch > 0:
        batch.commit()
    print(f"  Done {DEVICE_ID}: 1680 docs")

print(f"\nDone! Total sensor readings written to Firestore: {total_written}")
print(f"Devices: {DEVICE_IDS}")
print(f"Timespan (UTC): {now - timedelta(days=30)} → {now}")
print("\nAll chart periods (1H, 24H, 7D, 30D) now have data.")
