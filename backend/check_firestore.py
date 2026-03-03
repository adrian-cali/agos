"""
Quick Firestore table viewer for sensor_readings.
Run with the same Python that runs main.py.
"""
import sys
import os

# Add backend dir to path so we can reuse firebase init
sys.path.insert(0, os.path.dirname(__file__))

import firebase_admin
from firebase_admin import credentials, firestore

_SA = os.path.join(os.path.dirname(__file__), 'serviceAccountKey.json')
try:
    app = firebase_admin.get_app()
except ValueError:
    if os.path.exists(_SA):
        cred = credentials.Certificate(_SA)
    else:
        cred = None
    firebase_admin.initialize_app(cred)

db = firestore.client()

LIMIT = int(sys.argv[1]) if len(sys.argv) > 1 else 20

docs = list(
    db.collection('sensor_readings')
    .order_by('timestamp', direction=firestore.Query.DESCENDING)
    .limit(LIMIT)
    .stream()
)

if not docs:
    print('No documents found in sensor_readings. Check Firebase connection.')
    sys.exit(0)

# Print table header
print(f"\n{'#':<4} {'timestamp':<26} {'device':<18} {'level':>6} {'volume':>8} {'turb':>7} {'ph':>6} {'tds':>7} {'pump':>5} {'status':<10}")
print('-' * 105)

for i, doc in enumerate(docs, 1):
    d = doc.to_dict()
    ts = d.get('timestamp', '')
    if hasattr(ts, 'strftime'):
        ts = ts.strftime('%Y-%m-%d %H:%M:%S')
    else:
        ts = str(ts)[:25]
    dev = str(d.get('device_id', ''))[:16]
    level = f"{d.get('level', 0):.1f}"
    vol   = f"{d.get('volume', 0):.1f}"
    turb  = f"{d.get('turbidity', 0):.2f}"
    ph    = f"{d.get('ph', 0):.2f}"
    tds   = f"{d.get('tds', 0):.1f}"
    pump  = 'ON' if d.get('pump_active') else 'off'
    status = str(d.get('status', ''))[:10]
    print(f"{i:<4} {ts:<26} {dev:<18} {level:>6} {vol:>8} {turb:>7} {ph:>6} {tds:>7} {pump:>5} {status:<10}")

print(f"\nTotal rows shown: {len(docs)}  (pass a number as arg to show more, e.g. python check_firestore.py 50)\n")
