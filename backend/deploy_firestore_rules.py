"""
deploy_firestore_rules.py
=========================
Uploads the local firestore.rules file directly to Firestore using
the Firebase Management REST API + a service account access token.

Run:  python backend/deploy_firestore_rules.py
"""

import os, json, urllib.request, urllib.error

# ── Load service account ──────────────────────────────────────────────────
SA_PATH = os.path.join(os.path.dirname(__file__), "serviceAccountKey.json")
with open(SA_PATH) as f:
    sa = json.load(f)

PROJECT_ID = sa["project_id"]
RULES_PATH = os.path.join(os.path.dirname(__file__), "..", "firestore.rules")

# ── Read rules ────────────────────────────────────────────────────────────
with open(RULES_PATH) as f:
    rules_content = f.read()

print(f"Project: {PROJECT_ID}")
print(f"Rules file: {os.path.abspath(RULES_PATH)}")

# ── Get access token via google-auth ─────────────────────────────────────
try:
    import google.auth
    import google.oauth2.service_account
    import google.auth.transport.requests

    credentials = google.oauth2.service_account.Credentials.from_service_account_file(
        SA_PATH,
        scopes=["https://www.googleapis.com/auth/cloud-platform"]
    )
    credentials.refresh(google.auth.transport.requests.Request())
    token = credentials.token
except ImportError:
    print("ERROR: google-auth not installed. Run: pip install google-auth")
    raise

# ── Upload rules via Firebase Rules REST API ─────────────────────────────
RULES_API = f"https://firebaserules.googleapis.com/v1/projects/{PROJECT_ID}/rulesets"

payload = {
    "source": {
        "files": [
            {
                "name": "firestore.rules",
                "content": rules_content
            }
        ]
    }
}

data = json.dumps(payload).encode("utf-8")
req = urllib.request.Request(
    RULES_API,
    data=data,
    headers={
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json"
    },
    method="POST"
)

try:
    with urllib.request.urlopen(req) as resp:
        result = json.loads(resp.read())
    ruleset_name = result["name"]
    print(f"\n[1] Created ruleset: {ruleset_name}")
except urllib.error.HTTPError as e:
    print(f"ERROR creating ruleset: {e.code} {e.read().decode()}")
    raise

# ── Get existing Firestore release name ──────────────────────────────────
RELEASE_API = f"https://firebaserules.googleapis.com/v1/projects/{PROJECT_ID}/releases"
req2 = urllib.request.Request(
    RELEASE_API,
    headers={"Authorization": f"Bearer {token}"},
    method="GET"
)
with urllib.request.urlopen(req2) as resp:
    releases = json.loads(resp.read())

# Find the Firestore release
fs_release = None
for rel in releases.get("releases", []):
    if "cloud.firestore" in rel["name"]:
        fs_release = rel["name"]
        break

if not fs_release:
    # Create the release
    fs_release = f"projects/{PROJECT_ID}/releases/cloud.firestore"
    print(f"[2] Creating new release: {fs_release}")
    create_payload = json.dumps({
        "name": fs_release,
        "rulesetName": ruleset_name
    }).encode("utf-8")
    req3 = urllib.request.Request(
        RELEASE_API,
        data=create_payload,
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        method="POST"
    )
    with urllib.request.urlopen(req3) as resp:
        print(f"  Created: {json.loads(resp.read())['name']}")
else:
    print(f"[2] Updating release: {fs_release}")
    update_url = f"https://firebaserules.googleapis.com/v1/{fs_release}"
    update_payload = json.dumps({
        "release": {"name": fs_release, "rulesetName": ruleset_name}
    }).encode("utf-8")
    req3 = urllib.request.Request(
        update_url,
        data=update_payload,
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        method="PATCH"
    )
    with urllib.request.urlopen(req3) as resp:
        result = json.loads(resp.read())
        print(f"  Now using ruleset: {result.get('rulesetName', ruleset_name)}")

print("\n=== Firestore rules deployed successfully! ===")
