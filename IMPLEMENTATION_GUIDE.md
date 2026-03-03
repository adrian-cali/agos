# AGOS — Implementation Guide

> **Purpose**: Step-by-step reference for implementing the system described in `SYSTEM_PLAN.md`.
> This guide describes **what to build, where to put it, and how it connects** — not the full source code.
> Follow the steps in order. Each step has a verification checkpoint before moving on.

---

## Architecture: Why Both FastAPI AND Firebase?

A common question: *"If we're using Firebase, why do we still need FastAPI?"*

**Short answer**: Firebase cannot receive a WebSocket connection from an ESP32 microcontroller. FastAPI acts as the bridge.

```
ESP32 Hardware
  ↓  WebSocket (ESP32 can do this, but NOT Firebase SDK)
FastAPI Backend  ←— runs on your PC / server
  ↓  Firebase Admin SDK (writes to cloud)
Firestore (Firebase Cloud)
  ↓  Real-time stream
Flutter App on phone
```

| Component | Role | Why |
|-----------|------|-----|
| **FastAPI** | ESP32 WebSocket relay, REST API for device registration | ESP32 can't connect to Firestore directly |
| **Firebase Auth** | User login / register / sessions | Handles tokens and JWTs automatically |
| **Firestore** | All data storage: sensor readings, alerts, settings, devices | Real-time streams, offline sync, scales automatically |
| **FCM** | Push notifications to phone | Triggered by FastAPI when thresholds are breached |
| **Flutter Firebase SDK** | App reads from Firestore, Auth, FCM | App never calls FastAPI directly |

**The Flutter app NEVER calls FastAPI directly.** Only the ESP32 (or the simulator) calls FastAPI. The app talks exclusively to Firebase.

---

## Prerequisites

| Tool | Purpose | Install |
|------|---------|---------|
| Flutter SDK (≥ 3.x) | Build the app | flutter.dev |
| Android Studio / VS Code | IDE | — |
| Python 3.10+ | Backend server | python.org |
| Firebase CLI | Deploy rules, manage project | `npm install -g firebase-tools` |
| Node.js (LTS) | Required by Firebase CLI | nodejs.org |
| Git | Version control | git-scm.com |
| ADB (Android Debug Bridge) | Push APK to real device | bundled with Android SDK |

---

## Step 0 — Firebase Project Setup (Console)

Do this in the **Firebase Console** (console.firebase.google.com) before touching any code.

### 0a — Create the Project
1. Click **Add project** → name it `agos-prod` (or any name)
2. Enable **Google Analytics** (optional)
3. Project is created — take note of the **Project ID**

### 0b — Enable Services
| Service | Location in Console | Setting |
|---------|-------------------|---------|
| Authentication | Build → Authentication → Sign-in method | Enable Email/Password |
| Cloud Firestore | Build → Firestore Database | Create in **test mode** for now |
| Cloud Messaging (FCM) | Project Settings → Cloud Messaging | Already enabled by default |
| Storage | Build → Storage | Initialize (optional, for profile photos) |

### 0c — Register the Android App
1. In Project Overview → click the **Android icon**
2. Package name: `com.example.agos_app`
3. Download the generated **`google-services.json`** file
4. Place it at: `agos_app/android/app/google-services.json`

### 0d — Register the iOS App (optional)
1. Click the **iOS icon**
2. Bundle ID: `com.example.agosApp`
3. Download **`GoogleService-Info.plist`**
4. Place it at: `agos_app/ios/Runner/GoogleService-Info.plist`

### 0e — Firebase Admin SDK Key (for backend)
1. Project Settings → **Service accounts**
2. Click **Generate new private key**
3. Download and save as `backend/serviceAccountKey.json`
4. **Never commit this file to Git** — add it to `.gitignore`

---

## Step 1 — Add Flutter Packages

Edit `agos_app/pubspec.yaml` — add these under `dependencies`:

| Package | Version | Purpose |
|---------|---------|---------|
| `firebase_core` | `^2.27.0` | Firebase initialization |
| `firebase_auth` | `^4.17.8` | Login / register / sign out |
| `cloud_firestore` | `^4.15.8` | Real-time sensor data streams |
| `firebase_messaging` | `^14.7.19` | Push notifications |
| `firebase_storage` | `^11.6.8` | Profile photo uploads |

Then run:
```
cd agos_app
flutter pub get
```

**Verify**: No errors in terminal output. Run `flutter doctor` and check no critical issues.

---

## Step 2 — Initialize Firebase in main.dart

**File**: `agos_app/lib/main.dart`

### What changes:
- Import `firebase_core` and `firebase_auth`
- `main()` becomes `async` and calls `Firebase.initializeApp()` before `runApp()`
- The `ProviderScope → MaterialApp` widget tree is wrapped in a `StreamBuilder<User?>` that listens to `FirebaseAuth.instance.authStateChanges()`
- If `User` is **null** → navigate to `/login`
- If `User` is **authenticated** → navigate to `/` (dashboard)

### Result:
The app automatically redirects based on whether the user is logged in. No manual token management needed.

---

## Step 3 — Auth Screens

### 3a — Login Screen

**File**: `agos_app/lib/presentation/screens/auth/login_screen.dart`

**What it looks like**:
- AGOS logo/icon at top center
- Title: "Welcome Back"
- Subtitle: "Sign in to your account"
- **Email** text field (keyboard type: email, prefix icon: envelope)
- **Password** text field (obscured, toggle visibility icon, prefix icon: lock)
- **Forgot Password?** link (right-aligned, navigates to `/forgot-password`)
- **Sign In** button (full-width, gradient: `#00B8DB → #155DFC`)
- "Don't have an account? **Register**" link at bottom (navigates to `/register`)
- Loading spinner shown while sign-in is in progress
- Error snackbar shown if credentials are wrong

**State**:
- Uses a `StateNotifier` or simple `ValueNotifier` to track `isLoading` and `errorMessage`
- Calls `FirebaseAuth.signInWithEmailAndPassword`

---

### 3b — Register Screen

**File**: `agos_app/lib/presentation/screens/auth/register_screen.dart`

**What it looks like**:
- Title: "Create Account"
- Subtitle: "Join AGOS to monitor your water"
- **Full Name** text field
- **Email** text field
- **Password** text field (obscured)
- **Confirm Password** text field (obscured, validates match)
- **Register** button (full-width gradient)
- "Already have an account? **Sign In**" link

**Logic**:
- Validates all fields before submitting
- Calls `FirebaseAuth.createUserWithEmailAndPassword`
- After success: calls `user.updateDisplayName(name)` and writes a user document to Firestore at `/users/{uid}`
- Shows error snackbar on failure

---

### 3c — Forgot Password Screen

**File**: `agos_app/lib/presentation/screens/auth/forgot_password_screen.dart`

**What it looks like**:
- Back arrow at top left
- Title: "Reset Password"
- Subtitle: "Enter your email to receive a reset link"
- **Email** text field
- **Send Reset Link** button
- On success: shows a confirmation card — "Check your inbox at {email}"
- On failure: shows snackbar with error

**Logic**:
- Calls `FirebaseAuth.sendPasswordResetEmail(email)`

---

## Step 4 — Update App Router

**File**: `agos_app/lib/core/router/app_router.dart`

### New Routes to Add

| Route Name | Screen Class | Transition Type |
|-----------|-------------|----------------|
| `/login` | `LoginScreen` | `_buildRoute` (Cupertino slide) |
| `/register` | `RegisterScreen` | `_buildRoute` (Cupertino slide) |
| `/forgot-password` | `ForgotPasswordScreen` | `_buildRoute` (Cupertino slide) |

These three routes need to be added to the existing `switch` block in `generateRoute()`.

---

## Step 5 — Update Backend

**File**: `backend/main.py`

### What changes (description only):

1. **Import Firebase Admin SDK** — import `firebase_admin`, initialize it using `serviceAccountKey.json`
2. **Get Firestore client** — `db = firestore.client()`
3. **`handle_sensor_data()` changes**:
   - Still updates the in-memory `state` dict (for WebSocket broadcast)
   - Now **also writes** sensor reading to Firestore at `/devices/{device_id}/readings/{timestamp}`
   - Checks thresholds — if any metric exceeds limit, writes an alert to `/devices/{device_id}/alerts/{alert_id}`
   - Checks `pump_active` flag — writes pump state to `/devices/{device_id}/status`
4. **New `POST /devices/register` endpoint** — receives `device_id + user_uid + name`, creates the device document in Firestore `/devices/{device_id}`
5. **Firestore command listener** — starts a background thread that watches `/devices/{device_id}/commands/pump` for changes; when a command arrives, sends it to the ESP32 via WebSocket

---

### Backend Endpoint Reference

| Method | Endpoint | Description | Request Body | Response |
|--------|----------|-------------|--------------|----------|
| `GET` | `/` | Health check — returns server status + connection counts | — | `{status, esp32_connected, app_connections, uptime}` |
| `POST` | `/devices/register` | Register an ESP32 device and link it to a user | `{device_id, user_uid, name}` | `{success: true, device_id}` |
| `GET` | `/state` | Return current in-memory sensor state | — | Full sensor state dict |
| `GET` | `/history` | Return historical sensor readings (last N entries) | `?n=100` | Array of reading objects |
| `GET` | `/alerts` | Get all active alerts | — | Array of alert objects |
| `DELETE` | `/alerts/{alert_id}` | Delete / dismiss an alert | — | `{success: true}` |
| `WS` | `/ws/sensor` | ESP32 WebSocket connection — receives sensor data | Sensor JSON (see below) | `heartbeat_ack` |
| `WS` | `/ws/app` | Flutter app WebSocket connection — receives broadcasts | `{type: "heartbeat"}` | `sensor_update`, `alert`, `historical_data` |

---

### WebSocket Message Formats

#### `/ws/sensor` — Incoming from ESP32 (or simulator)
```
{
  "device_id": "esp32-001",
  "turbidity": 3.2,
  "pH": 7.1,
  "TDS": 180.5,
  "temperature": 26.3,
  "water_level": 75.0,
  "flow_rate": 1.8,
  "pump_active": false,
  "timestamp": "2024-01-15T10:30:00Z"
}
```

#### `/ws/app` — Outgoing to Flutter app
```
{
  "type": "sensor_update",
  "data": { ...same fields as above... }
}
```
```
{
  "type": "alert",
  "data": { "alert_id": "...", "metric": "pH", "value": 9.5, "message": "pH too high" }
}
```

---

## Step 6 — Update ESP32 Simulator

**File**: `backend/esp32_simulator_ws.py`

### What changes (description only):

1. **Add `device_id` field** to every message — value: `"esp32-sim-001"`
2. **Add `pump_active` field** — calculated based on current simulated values:
   - `pump_active = True` if turbidity > 5.0 OR pH < 6.5 OR pH > 8.5 OR TDS > 500
3. **Simulate a "bad water" cycle** — every ~5 minutes, temporarily spike turbidity to 8.0 and TDS to 600 to test alert triggering
4. **Reconnect logic** — if connection drops, retry every 5 seconds
5. **Print output** — log each message sent in a readable format

---

## Step 7 — Firestore Service (Flutter)

**File**: `agos_app/lib/data/services/firestore_service.dart`

This service is the Flutter app's interface to Firestore. It does NOT contain UI logic.

### Functions it provides:

| Function | Description |
|----------|-------------|
| `watchLatestReading(deviceId)` | Returns `Stream<SensorReading>` — listens to latest doc in `/devices/{id}/readings` ordered by timestamp desc |
| `watchAlerts(deviceId)` | Returns `Stream<List<Alert>>` — listens to `/devices/{id}/alerts` collection |
| `dismissAlert(deviceId, alertId)` | Deletes the alert document from Firestore |
| `sendPumpCommand(deviceId, activate)` | Writes `{action: "activate"/"deactivate", timestamp}` to `/devices/{id}/commands/pump` |
| `getUserSettings(uid)` | Returns `Future<UserSettings>` — reads `/user_settings/{uid}` |
| `saveUserSettings(uid, settings)` | Writes `UserSettings` object to `/user_settings/{uid}` |
| `getUserProfile(uid)` | Reads `/users/{uid}` document |
| `updateUserProfile(uid, data)` | Updates `/users/{uid}` with new display name / photo URL |
| `getReadingHistory(deviceId, limit)` | Returns `Future<List<SensorReading>>` — last N readings |

### Riverpod Providers to expose:

| Provider | Type | Description |
|----------|------|-------------|
| `latestReadingProvider` | `StreamProvider<SensorReading>` | Powers the dashboard |
| `alertsProvider` | `StreamProvider<List<Alert>>` | Powers the alerts screen |
| `userSettingsProvider` | `FutureProvider<UserSettings>` | Powers the settings screen |

---

## Step 8 — Register a Test Device in Firestore

You can do this via the Firebase Console OR a curl/PowerShell command once the backend is running.

**Via Console**: Navigate to Firestore → Create document manually:
- Collection: `devices`
- Document ID: `esp32-sim-001`
- Fields: `device_id (string)`, `name (string)`, `user_uid (string)`, `created_at (timestamp)`

**Via Backend endpoint** (once server is running):

```powershell
Invoke-RestMethod -Uri "http://localhost:8000/devices/register" `
  -Method POST `
  -ContentType "application/json" `
  -Body '{"device_id":"esp32-sim-001","user_uid":"YOUR_UID","name":"Simulator"}'
```

---

## Step 9 — Running the Full System

Open **3 terminals**:

**Terminal 1 — Start Backend:**
```bash
cd backend
python -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

**Terminal 2 — Start ESP32 Simulator:**
```bash
cd backend
python esp32_simulator_ws.py
```

**Terminal 3 — Run Flutter App:**
```bash
cd agos_app
flutter run
```

**Expected behavior:**
- Simulator connects → you see "ESP32 connected" in Terminal 1
- Backend writes sensor data to Firestore every 5 seconds
- Flutter app reads from Firestore → dashboard updates in real time
- If a metric crosses threshold → alert appears in Firestore + app alerts screen

---

## Step 10 — Firestore Collections Reference

| Collection Path | Document ID | Key Fields | Updated By |
|----------------|-------------|-----------|-----------|
| `/users/{uid}` | Firebase Auth UID | `name`, `email`, `created_at` | App (on register) |
| `/user_settings/{uid}` | Firebase Auth UID | `turbidity_max`, `pH_min`, `pH_max`, `TDS_max`, `notifications_enabled` | App (settings screen) |
| `/devices/{device_id}` | device ID string | `name`, `user_uid`, `created_at` | Backend `/register` endpoint |
| `/devices/{id}/readings/{timestamp}` | ISO timestamp | all sensor fields | Backend (on each sensor message) |
| `/devices/{id}/alerts/{alert_id}` | UUID | `metric`, `value`, `message`, `resolved` | Backend (on threshold breach) |
| `/devices/{id}/status` | `current` (single doc) | `pump_active`, `last_seen` | Backend (on each sensor message) |
| `/devices/{id}/commands/pump` | `pump` (single doc) | `action`, `timestamp`, `issued_by` | App (pump toggle button) |

---

## Step 11 — Verification Checklist

### Auth Flow
- [ ] App opens to `/login` when not signed in
- [ ] Login with wrong password shows error snackbar
- [ ] Login with correct credentials navigates to dashboard
- [ ] Register creates user in Firebase Auth console
- [ ] Register creates `/users/{uid}` document in Firestore
- [ ] Forgot password sends email (check inbox)
- [ ] Sign out from settings returns to `/login`

### Real-time Data
- [ ] Simulator connects and backend logs "ESP32 connected"
- [ ] Firestore console shows new docs appearing in `/devices/esp32-sim-001/readings/`
- [ ] Dashboard in app reflects live values
- [ ] Values update every ~5 seconds

### Alerts
- [ ] When turbidity spikes (simulate > 5.0), alert doc appears in Firestore
- [ ] Alert appears in app's alerts screen
- [ ] Dismissing alert in app deletes it from Firestore

### Pump Control
- [ ] Manual pump toggle in app → doc written to `/devices/{id}/commands/pump`
- [ ] Backend listener picks up command → sends to simulator via WebSocket
- [ ] Simulator logs received command

### Settings
- [ ] Settings screen reads from `/user_settings/{uid}`
- [ ] Saving settings writes to Firestore
- [ ] Thresholds from settings are used for alert checks in backend

---

## Troubleshooting

| Problem | Likely Cause | Fix |
|---------|-------------|-----|
| `google-services.json not found` | File missing or wrong path | Place in `agos_app/android/app/` |
| `PlatformException: no firebase app` | `Firebase.initializeApp()` not called | Confirm `main()` calls it before `runApp()` |
| Simulator connects but no Firestore writes | `serviceAccountKey.json` missing or wrong path | Check `backend/serviceAccountKey.json` exists |
| `firebase_admin.exceptions.NotFoundError` | Firestore not initialized in project | Go to Firebase Console → Build → Firestore → Create database |
| Auth works but `/users/{uid}` doc not created | Register logic incomplete | Ensure Firestore write happens after `createUserWithEmailAndPassword` |
| Dashboard stuck on old data | Still using WebSocket instead of Firestore stream | Confirm `latestReadingProvider` uses `cloud_firestore` not `web_socket_channel` |
| Pump command not reaching simulator | Firestore listener not started in backend | Check that Firestore `on_snapshot` watcher is launched on startup |
| `flutter: FirebaseException [permission-denied]` | Firestore security rules blocking access | Temporarily use test mode rules; tighten rules later |
| App works on emulator but not real device | Firebase SHA-1 fingerprint not registered | Add debug SHA-1 to Firebase Console → Project Settings → Android App |

---

## File Structure Summary

```
agos_app/lib/
├── main.dart                          ← Add Firebase.initializeApp() + auth gate
├── core/
│   └── router/
│       └── app_router.dart            ← Add /login, /register, /forgot-password routes
├── data/
│   └── services/
│       ├── firestore_service.dart     ← NEW: Firestore CRUD + stream functions
│       └── websocket_service.dart     ← Keep for legacy/simulator WebSocket
└── presentation/
    └── screens/
        └── auth/                      ← NEW folder
            ├── login_screen.dart
            ├── register_screen.dart
            └── forgot_password_screen.dart

backend/
├── main.py                             ← Add Firebase Admin, Firestore writes, endpoint table above
├── esp32_simulator_ws.py               ← Add device_id, pump_active, reconnect logic
├── serviceAccountKey.json              ← Download from Firebase Console (DO NOT COMMIT)
└── requirements.txt                    ← Add firebase-admin
```

---

*Next step after this guide: implement Phase 4 (BLE device pairing) from `SYSTEM_PLAN.md`.*
