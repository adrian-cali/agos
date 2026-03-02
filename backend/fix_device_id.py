import firebase_admin
from firebase_admin import credentials, firestore

cred = credentials.Certificate(r'C:\Users\Adrian\agos\backend\serviceAccountKey.json')
firebase_admin.initialize_app(cred)
db = firestore.client()

# List all users and their device IDs
print("=== Current user documents ===")
users = list(db.collection('users').stream())
for u in users:
    d = u.to_dict()
    print(f"UID: {u.id}")
    print(f"  device_id: {d.get('device_id')}")
    print(f"  email: {d.get('email')}")
    print()

# Update the user with device_id "agos-3JGRl6wM" to "agos-zksl9QK3"
TARGET_OLD = "agos-3JGRl6wM"
TARGET_NEW = "agos-zksl9QK3"

updated = 0
for u in users:
    d = u.to_dict()
    if d.get('device_id') == TARGET_OLD:
        print(f"Updating user {u.id}: {TARGET_OLD} -> {TARGET_NEW}")
        db.collection('users').document(u.id).update({'device_id': TARGET_NEW})
        updated += 1

if updated == 0:
    print("No users found with device_id =", TARGET_OLD)
    print("No changes made.")
else:
    print(f"Updated {updated} user(s).")
