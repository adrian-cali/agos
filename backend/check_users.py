"""Check users and devices in Firestore to diagnose device ID linking."""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
import firebase_admin
from firebase_admin import credentials, firestore

_SA = os.path.join(os.path.dirname(__file__), 'serviceAccountKey.json')
try:
    app = firebase_admin.get_app()
except ValueError:
    cred = credentials.Certificate(_SA)
    firebase_admin.initialize_app(cred)

db = firestore.client()

# Check users collection
users = list(db.collection('users').stream())
print(f'Users in Firestore: {len(users)}')
for u in users:
    d = u.to_dict()
    device_id = d.get('device_id', 'NOT SET')
    name = d.get('name', '')
    email = d.get('email', '')
    print(f'  uid={u.id}')
    print(f'    device_id = {device_id}')
    print(f'    name = {name}, email = {email}')

# Check devices collection
print()
devices = list(db.collection('devices').stream())
print(f'Devices in Firestore: {len(devices)}')
for dev in devices:
    d = dev.to_dict()
    print(f'  id={dev.id}, name={d.get("name","")}, status={d.get("status","")}')

# Count sensor readings
readings = list(db.collection('sensor_readings').limit(500).stream())
print(f'\nSensor readings (capped at 500 check): {len(readings)}')

# Sample device IDs from readings
device_ids_found = set()
for r in readings:
    device_ids_found.add(r.to_dict().get('device_id', ''))
print(f'Device IDs in sensor_readings: {device_ids_found}')
