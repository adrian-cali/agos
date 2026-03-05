"""Quick check: does the device have owner_uid, and do users have fcm_token?"""
import firebase_admin
from firebase_admin import credentials, firestore

cred = credentials.Certificate('serviceAccountKey.json')
firebase_admin.initialize_app(cred)
db = firestore.client()

# --- Check device agos-zksl9QK3 for owner_uid ---
DEVICE_ID = 'agos-zksl9QK3'
device_doc = db.collection('devices').document(DEVICE_ID).get()
d = device_doc.to_dict() or {}
print(f'=== devices/{DEVICE_ID} ===')
print(f'  owner_uid : {d.get("owner_uid", "(MISSING — FCM cannot look up token)")}')
print(f'  status    : {d.get("status")}')
print(f'  last_seen : {d.get("last_seen")}')

# --- Check all users with this device for fcm_token ---
print()
print(f'=== Users linked to {DEVICE_ID} ===')
users = db.collection('users').where('device_id', '==', DEVICE_ID).stream()
found = False
for u in users:
    found = True
    data = u.to_dict() or {}
    raw_token = data.get('fcm_token')
    token_display = (raw_token[:30] + '...') if raw_token else '(NOT SET — login on device first)'
    print(f'  uid       : {u.id}')
    print(f'  name      : {data.get("name")}')
    print(f'  fcm_token : {token_display}')
if not found:
    print('  (no users found with this device_id)')

# --- Summary ---
print()
owner_uid = d.get('owner_uid')
print('=== FCM Readiness ===')
if not owner_uid:
    print('  ❌ owner_uid missing on device document.')
    print('     Fix: go through the BLE pairing flow in the app (this sets owner_uid).')
    print('     Or run:  python fix_device_id.py  if that script handles this.')
else:
    print(f'  ✅ owner_uid is set: {owner_uid}')
    # Check that user has fcm_token
    user_doc = db.collection('users').document(owner_uid).get()
    user_data = (user_doc.to_dict() or {}) if user_doc.exists else {}
    if user_data.get('fcm_token'):
        print('  ✅ fcm_token is saved on user document.')
        print('  🟢 FCM should work — next bad-water spike will trigger a push.')
    else:
        print('  ❌ fcm_token missing on user document.')
        print('     Fix: log in on a real Android device with the updated app.')
