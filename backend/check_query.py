"""Verify Firestore queries match what Flutter SDK does."""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
import firebase_admin
from firebase_admin import credentials, firestore
from datetime import datetime, timedelta

_SA = os.path.join(os.path.dirname(__file__), 'serviceAccountKey.json')
try:
    app = firebase_admin.get_app()
except ValueError:
    cred = credentials.Certificate(_SA)
    firebase_admin.initialize_app(cred)

db = firestore.client()

device_id = 'agos-zksl9QK3'
cutoff30 = datetime.now() - timedelta(days=30)
cutoff1h = datetime.now() - timedelta(hours=1)

print('=== 30-day window (no orderBy) ===')
snap = db.collection('sensor_readings') \
    .where('device_id', '==', device_id) \
    .where('timestamp', '>', cutoff30) \
    .get()
print(f'30-day results: {len(snap)}')

print()
print('=== 1-hour window (no orderBy) ===')
snap2 = db.collection('sensor_readings') \
    .where('device_id', '==', device_id) \
    .where('timestamp', '>', cutoff1h) \
    .get()
print(f'1-hour results: {len(snap2)}')

print()
print('=== device_id only (no time filter) ===')
snap3 = db.collection('sensor_readings') \
    .where('device_id', '==', device_id) \
    .limit(3) \
    .get()
print(f'Any docs: {len(snap3)}')
for doc in snap3:
    d = doc.to_dict()
    ts = d.get('timestamp')
    ts_type = type(ts).__name__
    print(f'  ts_type={ts_type}, ts={ts}')
