"""
setup_ble01_device.py
=====================
Registers agos-BLE01 in Firestore for the hardware developer account
(agos.team@gmail.com) and unlinks the old agos-8W9K3FJR device.

Run from the project root:
    python backend/setup_ble01_device.py

Requirements: firebase-admin (already in requirements.txt)
Credentials: backend/serviceAccountKey.json
"""

import sys
import os

# ---------------------------------------------------------------------------
# Bootstrap Firebase Admin
# ---------------------------------------------------------------------------
import firebase_admin
from firebase_admin import credentials, firestore
from google.cloud.firestore_v1 import SERVER_TIMESTAMP

SERVICE_ACCOUNT_PATH = os.path.join(os.path.dirname(__file__), "serviceAccountKey.json")

if not firebase_admin._apps:
    cred = credentials.Certificate(SERVICE_ACCOUNT_PATH)
    firebase_admin.initialize_app(cred)

db = firestore.client()

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
HARDWARE_DEV_EMAIL  = "agos.team@gmail.com"
HARDWARE_DEV_UID    = "8W9K3FJR0tQtEzw9GHnMWCi5WLs2"   # looked up from Firestore
OLD_DEVICE_ID       = "agos-8W9K3FJR"
NEW_DEVICE_ID       = "agos-BLE01"
DEVICE_DISPLAY_NAME = "AGOS BLE01"

# ---------------------------------------------------------------------------
# Step 1: Verify the hardware developer's user document
# ---------------------------------------------------------------------------
print(f"\n[1] Fetching user document for uid={HARDWARE_DEV_UID}")

users_ref = db.collection("users")
dev_doc = users_ref.document(HARDWARE_DEV_UID).get()

if not dev_doc.exists:
    print(f"ERROR: No user document found for uid={HARDWARE_DEV_UID}")
    sys.exit(1)

dev_uid  = dev_doc.id
dev_data = dev_doc.to_dict()

print(f"  Found: uid={dev_uid}, name={dev_data.get('name')}, device_id={dev_data.get('device_id')}")

# ---------------------------------------------------------------------------
# Step 2: Create devices/agos-BLE01 document
# ---------------------------------------------------------------------------
print(f"\n[2] Creating devices/{NEW_DEVICE_ID} ...")

new_device_ref = db.collection("devices").document(NEW_DEVICE_ID)
existing = new_device_ref.get()

if existing.exists:
    print(f"  devices/{NEW_DEVICE_ID} already exists — updating owner_uid and fields.")
    new_device_ref.set({
        "device_id":  NEW_DEVICE_ID,
        "owner_uid":  dev_uid,
        "name":       DEVICE_DISPLAY_NAME,
        "shared_uids": existing.to_dict().get("shared_uids", []),
        "updated_at": SERVER_TIMESTAMP,
    }, merge=True)
else:
    new_device_ref.set({
        "device_id":  NEW_DEVICE_ID,
        "owner_uid":  dev_uid,
        "name":       DEVICE_DISPLAY_NAME,
        "shared_uids": [],
        "created_at": SERVER_TIMESTAMP,
    })
    print(f"  Created devices/{NEW_DEVICE_ID}  owner_uid={dev_uid}")

# ---------------------------------------------------------------------------
# Step 3: Update hardware developer's user document
# ---------------------------------------------------------------------------
print(f"\n[3] Updating users/{dev_uid}.device_id → {NEW_DEVICE_ID}")

users_ref.document(dev_uid).update({
    "device_id": NEW_DEVICE_ID,
})
print("  Done.")

# ---------------------------------------------------------------------------
# Step 4: Handle old device document
# ---------------------------------------------------------------------------
print(f"\n[4] Checking old device doc devices/{OLD_DEVICE_ID} ...")

old_device_ref = db.collection("devices").document(OLD_DEVICE_ID)
old_existing = old_device_ref.get()

if old_existing.exists:
    old_data = old_existing.to_dict()
    old_owner = old_data.get("owner_uid", "unknown")
    if old_owner == dev_uid:
        old_device_ref.delete()
        print(f"  Deleted devices/{OLD_DEVICE_ID} (was owned by dev account)")
    else:
        print(f"  devices/{OLD_DEVICE_ID} is owned by a different user ({old_owner}) — leaving it alone.")
else:
    print(f"  devices/{OLD_DEVICE_ID} not found — nothing to delete.")

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
print(f"""
==============================================
  Setup complete!
  Device ID : {NEW_DEVICE_ID}
  Owner UID : {dev_uid}
  Email     : {HARDWARE_DEV_EMAIL}
==============================================

Next steps for the hardware developer:
 1. Re-flash the ESP32 with the latest firmware (device ID is hardcoded as agos-BLE01)
 2. Open the AGOS app → the account is now linked to agos-BLE01
 3. Provision the ESP32 via BLE — log will show:
      [BLE] Provisioning: SSID=..., deviceId=agos-BLE01
 4. Sensor data will appear under devices/{NEW_DEVICE_ID} in Firestore
""")
