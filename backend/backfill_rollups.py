import argparse
from datetime import datetime, timedelta, timezone
import json
import os
import sys

import firebase_admin
from firebase_admin import credentials, firestore

SERVICE_ACCOUNT_PATH = os.path.join(os.path.dirname(__file__), "serviceAccountKey.json")
SERVICE_ACCOUNT_JSON_ENV = os.environ.get("FIREBASE_SERVICE_ACCOUNT_JSON")
PAGE_SIZE = 500


def init_firebase():
    if firebase_admin._apps:
        return firestore.client()

    if os.path.exists(SERVICE_ACCOUNT_PATH):
        cred = credentials.Certificate(SERVICE_ACCOUNT_PATH)
        firebase_admin.initialize_app(cred)
        return firestore.client()

    if SERVICE_ACCOUNT_JSON_ENV:
        cred = credentials.Certificate(json.loads(SERVICE_ACCOUNT_JSON_ENV))
        firebase_admin.initialize_app(cred)
        return firestore.client()

    raise RuntimeError(
        "Missing Firebase credentials. Provide backend/serviceAccountKey.json or FIREBASE_SERVICE_ACCOUNT_JSON."
    )


def bucket_hour(dt: datetime) -> datetime:
    return dt.replace(minute=0, second=0, microsecond=0)


def bucket_day(dt: datetime) -> datetime:
    return dt.replace(hour=0, minute=0, second=0, microsecond=0)


def rollup_doc_id(device_id: str, bucket_start: datetime) -> str:
    return f"{device_id}_{bucket_start.strftime('%Y%m%d%H%M')}"


def update_agg(agg: dict, reading: dict):
    agg["count"] += 1
    agg["pump_active_count"] += 1 if reading["pump_active"] else 0

    for metric in ("level", "volume", "flow_rate", "turbidity", "ph", "tds"):
        value = float(reading[metric])
        agg[f"{metric}_sum"] += value
        agg[f"{metric}_min"] = min(agg[f"{metric}_min"], value)
        agg[f"{metric}_max"] = max(agg[f"{metric}_max"], value)


def new_agg(device_id: str, bucket_start: datetime) -> dict:
    inf = float("inf")
    return {
        "device_id": device_id,
        "bucket_start": bucket_start,
        "count": 0,
        "pump_active_count": 0,
        "level_sum": 0.0,
        "level_min": inf,
        "level_max": -inf,
        "volume_sum": 0.0,
        "volume_min": inf,
        "volume_max": -inf,
        "flow_rate_sum": 0.0,
        "flow_rate_min": inf,
        "flow_rate_max": -inf,
        "turbidity_sum": 0.0,
        "turbidity_min": inf,
        "turbidity_max": -inf,
        "ph_sum": 0.0,
        "ph_min": inf,
        "ph_max": -inf,
        "tds_sum": 0.0,
        "tds_min": inf,
        "tds_max": -inf,
    }


def finalize_agg(agg: dict) -> dict:
    count = max(int(agg["count"]), 1)
    return {
        "device_id": agg["device_id"],
        "bucket_start": agg["bucket_start"],
        "count": agg["count"],
        "pump_active_count": agg["pump_active_count"],
        "level_avg": agg["level_sum"] / count,
        "level_min": agg["level_min"],
        "level_max": agg["level_max"],
        "volume_avg": agg["volume_sum"] / count,
        "volume_min": agg["volume_min"],
        "volume_max": agg["volume_max"],
        "flow_rate_avg": agg["flow_rate_sum"] / count,
        "flow_rate_min": agg["flow_rate_min"],
        "flow_rate_max": agg["flow_rate_max"],
        "turbidity_avg": agg["turbidity_sum"] / count,
        "turbidity_min": agg["turbidity_min"],
        "turbidity_max": agg["turbidity_max"],
        "ph_avg": agg["ph_sum"] / count,
        "ph_min": agg["ph_min"],
        "ph_max": agg["ph_max"],
        "tds_avg": agg["tds_sum"] / count,
        "tds_min": agg["tds_min"],
        "tds_max": agg["tds_max"],
        "updated_at": firestore.SERVER_TIMESTAMP,
    }


def fetch_all_readings(db, device_id: str | None, since_days: int | None, max_readings: int | None):
    query = db.collection("sensor_readings").order_by("timestamp")
    if device_id:
        query = query.where("device_id", "==", device_id)
    if since_days is not None and since_days > 0:
        cutoff = datetime.now(timezone.utc) - timedelta(days=since_days)
        query = query.where("timestamp", ">=", cutoff)

    last_doc = None
    yielded = 0
    while True:
        page = query.limit(PAGE_SIZE)
        if last_doc is not None:
            page = page.start_after(last_doc)
        snap = page.get()
        if not snap:
            break
        for doc in snap:
            data = doc.to_dict() or {}
            ts = data.get("timestamp")
            if not ts:
                continue
            if max_readings is not None and yielded >= max_readings:
                return
            yielded += 1
            yield {
                "device_id": data.get("device_id", ""),
                "timestamp": ts.to_datetime() if hasattr(ts, "to_datetime") else ts,
                "level": float(data.get("level", 0.0)),
                "volume": float(data.get("volume", 0.0)),
                "flow_rate": float(data.get("flow_rate", 0.0)),
                "pump_active": bool(data.get("pump_active", False)),
                "turbidity": float(data.get("turbidity", 0.0)),
                "ph": float(data.get("ph", 0.0)),
                "tds": float(data.get("tds", 0.0)),
            }
        if len(snap) < PAGE_SIZE:
            break
        last_doc = snap[-1]


def build_rollups(readings):
    hourly = {}
    daily = {}

    for reading in readings:
        device_id = reading["device_id"]
        ts = reading["timestamp"]

        hour_key = (device_id, bucket_hour(ts))
        day_key = (device_id, bucket_day(ts))

        if hour_key not in hourly:
            hourly[hour_key] = new_agg(device_id, hour_key[1])
        if day_key not in daily:
            daily[day_key] = new_agg(device_id, day_key[1])

        update_agg(hourly[hour_key], reading)
        update_agg(daily[day_key], reading)

    return hourly, daily


def write_rollups(db, collection_name: str, rollups: dict):
    items = list(rollups.values())
    total = 0
    for start in range(0, len(items), 400):
        batch = db.batch()
        chunk = items[start:start + 400]
        for agg in chunk:
            doc = finalize_agg(agg)
            doc_ref = db.collection(collection_name).document(
                rollup_doc_id(doc["device_id"], doc["bucket_start"])
            )
            batch.set(doc_ref, doc)
        batch.commit()
        total += len(chunk)
        print(f"Wrote {total}/{len(items)} docs to {collection_name}")


def main():
    parser = argparse.ArgumentParser(
        description="Backfill Firestore hourly/daily rollups from sensor_readings."
    )
    parser.add_argument(
        "--device-id",
        dest="device_id",
        default=None,
        help="Optional device_id filter.",
    )
    parser.add_argument(
        "--days",
        type=int,
        default=None,
        help="Only backfill data from the last N days.",
    )
    parser.add_argument(
        "--max-readings",
        type=int,
        default=None,
        help="Optional safety cap on raw readings to process.",
    )
    args = parser.parse_args()

    db = init_firebase()

    print("Fetching sensor readings...")
    readings = list(fetch_all_readings(db, args.device_id, args.days, args.max_readings))
    print(f"Fetched {len(readings)} raw readings")

    print("Building rollups...")
    hourly, daily = build_rollups(readings)
    print(f"Hourly buckets: {len(hourly)}")
    print(f"Daily buckets: {len(daily)}")

    print("Writing hourly rollups...")
    write_rollups(db, "sensor_rollups_hourly", hourly)

    print("Writing daily rollups...")
    write_rollups(db, "sensor_rollups_daily", daily)

    print("Done.")


if __name__ == "__main__":
    main()
