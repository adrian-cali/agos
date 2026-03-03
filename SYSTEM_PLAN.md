# AGOS Full System Plan
## Firebase + Hardware-Ready ESP32 Architecture

---

## Architecture Overview

```
ESP32 Hardware
  ↓ WebSocket (ws://backend:8000/ws/sensor)
FastAPI Backend  ←→  Firestore (writes sensor data)
                 ←→  Firebase Auth (verifies tokens)
                 
Flutter App
  ↓ Firebase Auth SDK       (Login / Register / Session)
  ↓ Firestore SDK           (Real-time data, settings, alerts)
  ↓ Firebase Messaging SDK  (Push notifications)
  ↓ Firebase Storage SDK    (Exported data logs)
```

### Why Both FastAPI AND Firebase?

The ESP32 microcontroller **cannot connect to Firebase directly** — it does not have a Firebase SDK. It communicates via WebSocket only. FastAPI receives the WebSocket connection from the ESP32 and then writes the data to Firestore using the Firebase Admin SDK (Python).

The Flutter app **never calls FastAPI directly**. The app only communicates with Firebase (Auth, Firestore, FCM). This means:
- Phone can be on any internet connection (mobile data, different WiFi, abroad)
- Only the ESP32 needs to reach your PC's local IP
- Scaling the backend later doesn't affect the app at all

**Role split:**

| Component | Responsibility |
|-----------|---------------|
| **Firebase Auth** | User accounts, JWT tokens, sessions |
| **Firestore** | All database: users, sensor readings, devices, settings, alerts |
| **FCM (Firebase Messaging)** | Push alerts to phone |
| **Firebase Storage** | Exported CSV/JSON data logs |
| **FastAPI** | ESP32 WebSocket relay only → writes to Firestore via Firebase Admin SDK |

---

## Design System (All new screens must follow)

- Background gradient: `#F8FAFC → #EFF6FF → #ECFEFF`
- Primary color: `#00D3F2`, Secondary: `#2B7FFF`
- Fonts: Poppins (headings), Inter (body)
- Card style: white/semi-transparent, `border-radius: 16px`, subtle blue shadow
- Buttons: gradient (`#00D3F2 → #155DFC`), `border-radius: 12–14px`, height 40

---

## Testing Without Hardware

Since the ESP32 hardware may not be available during development, here are the recommended testing strategies:

### Option 1 — ESP32 Simulator (already built)

`backend/esp32_simulator_ws.py` is already in the project. It sends randomized sensor data every 5 seconds over WebSocket, exactly like a real ESP32 would. Use it as your fake device during all development phases.

When real hardware arrives, you simply connect the ESP32 to the same WebSocket endpoint — no changes to the backend or Flutter app needed.

### Option 2 — Real Firebase Free Tier (Spark Plan)

Firebase's free tier is sufficient for the entire development and testing phase:

| Service | Free limit |
|---------|-----------|
| Firestore reads | 50,000 / day |
| Firestore writes | 20,000 / day |
| Firebase Auth | Unlimited |
| FCM (push notifications) | Free |
| Storage | 5 GB |

No credit card required. Recommended: set up the real Firebase project early and test against it directly.

### Option 3 — Firebase Local Emulator Suite

Run Firestore, Auth, and Messaging locally — no internet required:

```bash
# Install Firebase CLI
npm install -g firebase-tools

# Start emulators
firebase emulators:start
```

Flutter connects to `localhost` instead of the cloud:

```dart
// In main.dart, before runApp()
FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
```

Useful for offline development and CI/CD pipelines.

### Option 4 — Manual WebSocket Testing (Postman or wscat)

Send fake sensor data directly to FastAPI without running the simulator:

```bash
# Using wscat (install via npm i -g wscat)
wscat -c ws://localhost:8000/ws/sensor

# Then type and send:
{"type":"sensor_data","device_id":"AGOS-A1B2","level":72.4,"turbidity":3.2,"ph":7.1,"tds":320,"volume":36200,"flow_rate":143,"temperature":25.3,"timestamp":"2025-01-01T12:00:00"}
```

Verify the data appears in Firestore and the Flutter app updates in real-time.

### How Data Reaches the Phone APK (No Hardware)

This is how data flows from the simulator on your PC all the way to the app on your phone:

```
[Your PC]
  esp32_simulator_ws.py
    ↓  WebSocket JSON every 5s
  FastAPI backend (localhost:8000)
    ↓  Firebase Admin SDK write
  Firestore (Firebase cloud ☁️)
    ↓  Real-time snapshot stream
  Flutter App on your phone (APK)
    ↓
  Home screen + Dashboard update live
```

**Key insight — the phone never connects to your PC:**
- The APK connects to **Firebase directly** (cloud)
- Firestore is in the cloud, so the phone just needs internet access
- No IP address or port forwarding to your PC required
- The only machine that connects to your laptop's IP is the simulator itself

**What to run on your PC during testing:**

| Terminal | Command |
|----------|---------|
| Terminal 1 | `cd backend` then `python -m uvicorn main:app --host 0.0.0.0 --port 8000` |
| Terminal 2 | `cd backend` then `python esp32_simulator_ws.py` |

Then install the APK on your phone — it reads from Firebase cloud and updates every 5 seconds in real-time without any further configuration.

### Recommended Development Workflow

```
Phase 1–2  →  Firebase Emulator (local) or real Firebase free tier
Phase 3    →  esp32_simulator_ws.py as fake ESP32
Phase 4    →  Mock BLE device in Flutter (skip real scan, use hardcoded device ID)
Phase 5–7  →  All testable with simulator + Firebase free tier
Hardware   →  Drop in real ESP32 when ready — no code changes needed
```

---

### Real Hardware Flow — ESP32 → APK over WiFi

When the ESP32 hardware is available, this is how data flows wirelessly in real-time to the phone:

```
[ESP32 Hardware]
  Connected to your WiFi network
  Reads sensors every 5 seconds
  Sends WebSocket JSON to → ws://YOUR_PC_IP:8000/ws/sensor
       ↓
[Your PC on the same WiFi]
  FastAPI backend running (--host 0.0.0.0)
  Receives sensor data from ESP32
  Writes to Firestore via Firebase Admin SDK
       ↓
[Firebase Cloud ☁️]
  Stores data in Firestore collections
       ↓
[Phone / APK — anywhere with internet]
  Listens to Firestore real-time snapshots
  Home screen + Dashboard update instantly
```

**Requirements:**

| Component | Requirement |
|---|---|
| ESP32 | Connected to your home/office WiFi |
| Your PC (backend) | On the **same WiFi** as the ESP32 |
| FastAPI | Must run with `--host 0.0.0.0` (not `localhost`) so ESP32 can reach it |
| Phone | Any internet connection (same WiFi, or mobile data — doesn't matter) |

**Finding your PC's local IP (needed for ESP32 firmware):**

```powershell
# Run in PowerShell
ipconfig
# Look for: IPv4 Address under your WiFi adapter → e.g. 192.168.1.105
```

**ESP32 Arduino firmware config:**

```cpp
// Set these in your ESP32 sketch
const char* wifi_ssid     = "YourWiFiName";
const char* wifi_password = "YourWiFiPassword";
const char* ws_host       = "192.168.1.105";  // ← your PC's local IP from ipconfig
const int   ws_port       = 8000;
const char* ws_path       = "/ws/sensor";
```

**Key point — phone does not need to be on the same WiFi as the ESP32.** The phone reads from Firebase cloud, not from your PC. It works anywhere with internet — mobile data, a different network, etc. Only the ESP32 needs to reach your PC.

---

## System Overview — Automated Water Filtration Loop

The core purpose of AGOS is automated water quality management. Here is the physical and software flow:

```
┌─────────────────────────────────────────────────────────────────┐
│                     AGOS Water System                           │
│                                                                 │
│   [Holding Tank]  ←──── [Filter Unit]                          │
│        │                      ↑                                │
│     Sensors                   │ filtered water                 │
│   (Turbidity,pH,TDS,Level)    │                                │
│        │                      │                                │
│    ESP32 detects bad water     │                                │
│        │                  [Equalizer Tank]                      │
│        └──→ Pump ON ──→ pushes water ──────────────────────────┘
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Automation Logic (ESP32 Firmware)

```
Every 5 seconds:
  Read: turbidity, pH, TDS, water level

  IF (turbidity > max_turbidity)
  OR (pH < min_ph OR pH > max_ph)
  OR (tds > max_tds):
    → Set pump relay pin HIGH (pump ON)
    → Send pump_active: true in WebSocket message
    → Record cycle start time

  ELSE IF all values are within thresholds:
    → Set pump relay pin LOW (pump OFF)
    → Send pump_active: false in WebSocket message
    → Record cycle end time
```

### What the App Shows

| When | App Behavior |
|---|---|
| Pump turns ON | Blue/orange indicator on Home screen: "Filtration Active" |
| Pump is running | Dashboard shows pump status card |
| Pump turns OFF | Notification: "Filtration cycle complete — water quality restored" |
| Quality stays bad | Alert: "Extended filtration — check filter unit" |

### Additional Firestore Fields (on device document)

```
/devices/{device_id}
  + pump_active:        bool       (current pump state)
  + last_cycle_start:   timestamp  (when last filtration started)
  + last_cycle_end:     timestamp  (when last filtration ended)
  + total_cycles:       number     (total filtration cycles run)
```

---

| Phase | Feature | Priority |
|-------|---------|---------|
| 1 | Firebase Project Setup | 🔴 High |
| 2 | Authentication (Login / Register / Session) | 🔴 High |
| 3 | Real ESP32 Data Flow + Pump Control → Firestore | 🔴 High |
| 4 | Real BLE Device Pairing | 🟡 Medium |
| 5 | Settings Persistence (Thresholds, Alerts) | 🟡 Medium |
| 6 | Real-Time Alert System (FCM) | 🟡 Medium |
| 7 | Profile Sync + Data Export | 🟢 Low |

---

## Phase 1 — Firebase Project Setup

### Firebase Console Steps

1. Go to [https://console.firebase.google.com](https://console.firebase.google.com)
2. Create a new project named **AGOS**
3. Enable the following services:
   - **Authentication** → Email/Password provider
   - **Firestore Database** → Start in production mode
   - **Cloud Messaging** (for push alerts)
   - **Storage** (for data log exports)

### Android App Registration

1. Firebase Console → Project Settings → Add app → Android
2. Android package name: `com.example.agos_app`
3. Download `google-services.json` → place at `agos_app/android/app/google-services.json`
4. Add to `agos_app/android/build.gradle.kts`:
   ```kotlin
   id("com.google.gms.google-services") version "4.4.0" apply false
   ```
5. Add to `agos_app/android/app/build.gradle.kts`:
   ```kotlin
   id("com.google.gms.google-services")
   ```

### Backend: Firebase Admin Setup

1. Firebase Console → Project Settings → Service Accounts → Generate New Private Key
2. Download `serviceAccountKey.json` → place at `backend/serviceAccountKey.json`
3. Add to `.gitignore`: `serviceAccountKey.json`
4. Add to `backend/requirements.txt`:
   ```
   firebase-admin==6.4.0
   ```
5. Initialize in `backend/main.py`:
   ```python
   import firebase_admin
   from firebase_admin import credentials, firestore, messaging

   cred = credentials.Certificate("serviceAccountKey.json")
   firebase_admin.initialize_app(cred)
   db_firestore = firestore.client()
   ```

---

## Phase 2 — Authentication & User Management

### New Flutter Packages

```yaml
firebase_core: ^3.6.0
firebase_auth: ^5.3.1
cloud_firestore: ^5.4.4
```

### Firestore: `users` Collection

```
/users/{uid}
  first_name:   string
  last_name:    string
  email:        string
  phone:        string
  location:     string
  fcm_token:    string    ← set in Phase 6
  created_at:   timestamp
```

### New Screens

**Login Screen** (`/login`)
- Light gradient background: `#F8FAFC → #EFF6FF → #ECFEFF`
- AGOS logo icon (104×104, white card with gradient glow)
- "Welcome Back" gradient heading (Poppins Bold 24, `#1447E6 → #0092B8 → #1447E6`)
- Email + Password text fields (white bg, `#1D293D` text, `#45556C` hint, `#00D3F2` focus border)
- "Sign In" full-width gradient button (`#00D3F2 → #155DFC`, BR 14, height 40)
- "Forgot password?" link (small, `#00D3F2`)
- "Don't have an account? Sign Up" link at bottom
- Uses `FirebaseAuth.instance.signInWithEmailAndPassword()`

**Register Screen** (`/register`)
- Same design as Login
- Fields: First Name, Last Name, Email, Password, Confirm Password
- "Create Account" gradient button
- After creation, writes user data to `/users/{uid}` in Firestore
- Uses `FirebaseAuth.instance.createUserWithEmailAndPassword()`

**Forgot Password Screen** (`/forgot-password`)
- Email field only
- "Send Reset Link" gradient button
- Uses `FirebaseAuth.instance.sendPasswordResetEmail()`

### `main.dart` Auth State Check

```dart
StreamBuilder<User?>(
  stream: FirebaseAuth.instance.authStateChanges(),
  builder: (context, snapshot) {
    if (snapshot.connectionState == ConnectionState.waiting)
      return SplashScreen();
    if (snapshot.hasData)
      return HomeScreen();
    return WelcomeScreen();
  },
)
```

### Settings Screen

- "Sign Out": `await FirebaseAuth.instance.signOut()` → navigate to `/login`

### Privacy & Security Screen

- "Delete Account": `await FirebaseAuth.instance.currentUser!.delete()` → navigate to `/login`

---

## Phase 3 — Real-Time ESP32 Data Flow + Pump Automation

### ESP32 Firmware

**Required hardware:**

| Component | Model | Interface |
|-----------|-------|-----------|
| Turbidity Sensor | DFRobot SEN0189 | Analog (ADC) |
| pH Sensor | DFRobot Gravity pH | Analog (ADC) |
| TDS Sensor | DFRobot Gravity TDS | Analog (ADC) |
| Water Level | HC-SR04 Ultrasonic | Digital (GPIO) |
| Flow Rate | YF-S201 | Interrupt (GPIO) |
| Temperature | DS18B20 | OneWire |
| Pump Relay | 5V Relay Module | Digital OUTPUT (GPIO) |

**Automation logic in firmware:**

```cpp
// Every 5 seconds
bool shouldPump = (turbidity > TURBIDITY_MAX)
               || (ph < PH_MIN || ph > PH_MAX)
               || (tds > TDS_MAX);

digitalWrite(PUMP_RELAY_PIN, shouldPump ? HIGH : LOW);

// Send data + pump state to backend
sendWebSocket({
  "type": "sensor_data",
  "device_id": DEVICE_ID,
  "turbidity": turbidity,
  "ph": ph,
  "tds": tds,
  "level": level,
  "volume": volume,
  "flow_rate": flow_rate,
  "temperature": temperature,
  "pump_active": shouldPump,
  "timestamp": getISOTimestamp()
});
```

**Heartbeat interval:** Every 5 seconds, send to `ws://<backend>:8000/ws/sensor`:

```json
{
  "type": "sensor_data",
  "device_id": "AGOS-A1B2",
  "level": 72.4,
  "volume": 36200.0,
  "flow_rate": 143.5,
  "turbidity": 3.2,
  "ph": 7.4,
  "tds": 320.0,
  "temperature": 25.3,
  "pump_active": false,
  "timestamp": "2025-01-01T12:00:00"
}
```

### Backend Changes

FastAPI receives the sensor message, checks pump state change, writes to Firestore:

```python
async def handle_sensor_data(device_id: str, data: dict):
    pump_active = data.get("pump_active", False)

    # Update latest reading + pump state on device document
    update_data = {
        "latest": data,
        "status": "connected",
        "last_seen": firestore.SERVER_TIMESTAMP,
        "pump_active": pump_active,
    }

    # Track filtration cycle times
    prev = db_firestore.collection("devices").document(device_id).get().to_dict() or {}
    was_pumping = prev.get("pump_active", False)

    if pump_active and not was_pumping:
        update_data["last_cycle_start"] = firestore.SERVER_TIMESTAMP
        update_data["total_cycles"] = firestore.Increment(1)

    if not pump_active and was_pumping:
        update_data["last_cycle_end"] = firestore.SERVER_TIMESTAMP

    db_firestore.collection("devices").document(device_id).set(update_data, merge=True)

    # Write to history collection for charts
    db_firestore.collection("sensor_readings").add({
        "device_id": device_id,
        **data,
    })
```

### Firestore Collections

```
/devices/{device_id}
  name:               string
  user_uid:           string
  status:             "connected" | "disconnected"
  last_seen:          timestamp
  pump_active:        bool
  last_cycle_start:   timestamp
  last_cycle_end:     timestamp
  total_cycles:       number
  latest:             map  (latest sensor values including pump_active)

/sensor_readings/{auto_id}
  device_id:     string
  level:         number
  volume:        number
  flow_rate:     number
  turbidity:     number
  ph:            number
  tds:           number
  temperature:   number
  pump_active:   bool
  timestamp:     timestamp
```

### Flutter: Real-Time Data Streams

Replace WebSocket state providers with Firestore `snapshots()`:

```dart
// Real-time latest sensor values
FirebaseFirestore.instance
  .collection('devices')
  .doc(deviceId)
  .snapshots()
  .map((doc) => doc.data()!['latest']);

// Historical chart data (24H / 7D / 30D)
final since = DateTime.now().subtract(Duration(hours: 24));
FirebaseFirestore.instance
  .collection('sensor_readings')
  .where('device_id', isEqualTo: deviceId)
  .where('timestamp', isGreaterThan: Timestamp.fromDate(since))
  .orderBy('timestamp')
  .snapshots();
```

- Home screen wave level → real Firestore stream
- Dashboard cards → live from device's `latest` map
- Historical charts → filtered Firestore query by period

### Flutter: Pump Status UI

**Home Screen**
- Add a status indicator card below the tank visualization:
  - When `pump_active == true`: pulsing blue/cyan badge — "Filtration Active"
  - When `pump_active == false`: grey badge — "System Normal"
  - Badge reads `pump_active` from the Firestore device document stream

**Dashboard Screen**
- Add a Pump Status card alongside the water quality cards:
  - Shows pump ON/OFF state
  - Shows `total_cycles` count
  - Shows `last_cycle_start` formatted as "Last run: X minutes ago"

**Historical Chart**
- Overlay pump activation periods as shaded bands on the chart (optional, Phase 7+)

---

## Phase 3B — App → ESP32 Command Flow (Remote Pump Control)

This allows the user to manually activate or deactivate the pump from the app, from anywhere with internet access.

### Architecture (Backend Bridge — Recommended)

```
Flutter App (anywhere with internet)
  │
  │  1. User taps "Activate Pump" button in app
  │  ↓
  │  writes to Firestore:
  │  /devices/{device_id}/commands/pump
  │    → { action: "pump_on", issued_by: uid, timestamp: ... }
  │
FastAPI Backend (PC running on local network)
  │
  │  2. Backend has a Firestore watch listener on /devices/*/commands/pump
  │  ↓
  │  detects the write → reads the command
  │
  │  3. Backend forwards via the open WebSocket to the ESP32:
  │    { "type": "command", "action": "pump_on" }
  │
ESP32 (on local WiFi)
  │
  │  4. ESP32 receives command → activates relay → pump turns ON
  │
  │  5. Next sensor reading (within 5s) reports back:
  │    { ..., "pump_active": true }
  │
  │  6. Firestore + App update in real-time → button reflects new state
  │
  └──────────────────────────────────────────────────────────────────
```

**Why this approach:**
- App can control the pump from **any network** (mobile data, different WiFi, etc.)
- No direct connection between phone and ESP32 needed
- Command latency: 1–3 seconds
- Reuses the existing WebSocket connection between FastAPI and ESP32
- No extra auth complexity on the ESP32 side

### Firestore: Command Document

```
/devices/{device_id}/commands/pump
  action:     "pump_on" | "pump_off" | "auto"
  issued_by:  string (user UID)
  timestamp:  timestamp
```

The `"auto"` action returns control back to the ESP32's own automation logic.

### Backend Changes

Add a Firestore listener in FastAPI at startup:

```python
from firebase_admin import firestore

def watch_pump_commands(device_id: str, ws_connection):
    """Watch Firestore for pump commands and forward to ESP32."""
    doc_ref = db_firestore.collection("devices").document(device_id) \
                          .collection("commands").document("pump")

    def on_snapshot(doc_snapshot, changes, read_time):
        for doc in doc_snapshot:
            command = doc.to_dict()
            action = command.get("action")
            if action in ("pump_on", "pump_off", "auto"):
                # Forward command to ESP32 via WebSocket
                import asyncio
                asyncio.run(ws_connection.send_json({
                    "type": "command",
                    "action": action,
                }))

    doc_ref.on_snapshot(on_snapshot)
```

### ESP32 Firmware Changes

Add a command handler in the WebSocket `onMessage` callback:

```cpp
void onWebSocketMessage(String payload) {
    DynamicJsonDocument doc(256);
    deserializeJson(doc, payload);

    if (doc["type"] == "command") {
        String action = doc["action"];
        if (action == "pump_on") {
            manualPumpOverride = true;
            pumpState = HIGH;
            digitalWrite(PUMP_RELAY_PIN, HIGH);
        }
        else if (action == "pump_off") {
            manualPumpOverride = true;
            pumpState = LOW;
            digitalWrite(PUMP_RELAY_PIN, LOW);
        }
        else if (action == "auto") {
            manualPumpOverride = false;
            // Resume automatic threshold-based control
        }
    }
}
```

The `manualPumpOverride` flag prevents the automatic logic from overriding a manual command.

### Flutter: Manual Pump Control UI

**Home Screen or Dashboard**
- Add a "Manual Control" toggle card (3 buttons: "Force On" / "Auto" / "Force Off")
- On tap, write to Firestore: `/devices/{device_id}/commands/pump`
- Buttons are disabled with a loading indicator while waiting for `pump_active` to confirm

```dart
Future<void> sendPumpCommand(String deviceId, String action) async {
  await FirebaseFirestore.instance
    .collection('devices')
    .doc(deviceId)
    .collection('commands')
    .doc('pump')
    .set({
      'action': action,
      'issued_by': FirebaseAuth.instance.currentUser!.uid,
      'timestamp': FieldValue.serverTimestamp(),
    });
}
```

---

## Phase 4 — Real BLE Device Pairing

### New Flutter Packages

```yaml
flutter_blue_plus: ^1.35.5
permission_handler: ^11.3.1
```

### ESP32 BLE Setup

- Advertise BLE GATT service with fixed AGOS service UUID
- **WiFi Config Characteristic** (writable): accepts `"SSID|PASSWORD"` string
- **Status Characteristic** (notifiable): returns `"connected"` once WiFi + WebSocket established

### Flutter Changes

**Bluetooth Setup 2** — Replace mock Grant buttons with real permission requests via `permission_handler` + `FlutterBluePlus.adapterState`

**Ready to Scan Screen** — Replace mock list with `FlutterBluePlus.startScan()` filtered by AGOS service UUID

**Ready to Pair Screen (WiFi flow)**
1. Write WiFi credentials to BLE characteristic:
   ```dart
   await characteristic.write(utf8.encode("$ssid|$password"));
   ```
2. Subscribe to Status Characteristic until `"connected"` received (30s timeout)
3. On success, write device to Firestore `/devices/{device_id}` with `user_uid`
4. Navigate to `/pairing-device`

### Backend: Device Registration

```
POST /devices/register
Body: { "device_id": "AGOS-A1B2", "user_uid": "...", "name": "My Tank" }
→ Writes to Firestore /devices/{device_id}
```

---

## Phase 5 — Settings Persistence

### Firestore: User Settings Document

```
/user_settings/{uid}
  turbidity_max:       number  (default: 5.0)
  ph_min:              number  (default: 6.5)
  ph_max:              number  (default: 8.3)
  tds_max:             number  (default: 500.0)
  water_level_min:     number  (default: 20.0)
  alert_turbidity:     bool    (default: true)
  alert_ph:            bool    (default: true)
  alert_tds:           bool    (default: true)
  alert_water_level:   bool    (default: true)
  data_retention_days: number  (default: 30)
```

### Flutter Changes

**Water Quality Thresholds Screen**
- On open: `FirebaseFirestore.instance.collection('user_settings').doc(uid).get()`
- On save: `.set({...}, SetOptions(merge: true))`

**Alert Settings Screen** — Same Firestore read/write pattern

**Data Logging Screen**

```yaml
# New Flutter packages needed
share_plus: ^10.1.4
path_provider: ^2.1.4
```

- "Export CSV": query `sensor_readings`, build CSV string, save to device, share via `share_plus`

---

## Phase 6 — Real-Time Alert System (FCM)

### New Flutter Packages

```yaml
firebase_messaging: ^15.1.3
flutter_local_notifications: ^17.2.3
```

### How It Works

1. On app launch, get FCM token and save to Firestore:
   ```dart
   final token = await FirebaseMessaging.instance.getToken();
   FirebaseFirestore.instance.collection('users').doc(uid).update({'fcm_token': token});
   ```
2. FastAPI reads FCM token when a threshold is exceeded → sends push notification
3. Alert is also written to Firestore `/alerts/{auto_id}`

### Firestore: Alerts Collection

```
/alerts/{auto_id}
  user_uid:    string
  device_id:   string
  type:        "water_quality" | "water_level" | "maintenance"
  title:       string
  description: string
  severity:    "info" | "warning" | "critical"
  is_read:     bool
  timestamp:   timestamp
```

### Backend: Threshold Checking in `handle_sensor_data()`

```python
# Get device → user UID
device_doc = db_firestore.collection("devices").document(device_id).get()
user_uid = device_doc.get("user_uid")

# Get user thresholds
settings = db_firestore.collection("user_settings").document(user_uid).get().to_dict() or {}
fcm_token = db_firestore.collection("users").document(user_uid).get().get("fcm_token")

def send_alert(user_uid, device_id, alert_type, title, description, severity):
    alert = {
        "user_uid": user_uid,
        "device_id": device_id,
        "type": alert_type,
        "title": title,
        "description": description,
        "severity": severity,
        "is_read": False,
        "timestamp": firestore.SERVER_TIMESTAMP,
    }
    db_firestore.collection("alerts").add(alert)
    if fcm_token:
        messaging.send(messaging.Message(
            notification=messaging.Notification(title=title, body=description),
            token=fcm_token,
        ))

# Turbidity check
if data["turbidity"] > settings.get("turbidity_max", 5.0):
    send_alert(user_uid, device_id, "water_quality", "High Turbidity",
               f"Turbidity is {data['turbidity']:.1f} NTU — filtration started", "warning")

# pH check
ph = data["ph"]
if ph < settings.get("ph_min", 6.5) or ph > settings.get("ph_max", 8.3):
    send_alert(user_uid, device_id, "water_quality", "pH Out of Range",
               f"pH is {ph:.1f} — acceptable range: {settings.get('ph_min',6.5)}–{settings.get('ph_max',8.3)}", "warning")

# TDS check
if data["tds"] > settings.get("tds_max", 500.0):
    send_alert(user_uid, device_id, "water_quality", "High TDS Level",
               f"TDS is {data['tds']:.0f} ppm — filtration started", "warning")

# Water level check
if data["level"] < settings.get("water_level_min", 20.0):
    send_alert(user_uid, device_id, "water_level", "Low Water Level",
               f"Tank level is {data['level']:.1f}% — please refill", "critical")

# Pump cycle tracking alerts
was_pumping = device_doc.to_dict().get("pump_active", False)
pump_now = data.get("pump_active", False)

if pump_now and not was_pumping:
    send_alert(user_uid, device_id, "system", "Filtration Started",
               "Water quality below threshold — automatic filtration activated", "info")

if not pump_now and was_pumping:
    send_alert(user_uid, device_id, "system", "Filtration Complete",
               "Water has been filtered and quality restored", "info")
```

### Flutter: Notifications Screen

Replace static `alertsProvider` list with Firestore real-time stream:

```dart
FirebaseFirestore.instance
  .collection('alerts')
  .where('user_uid', isEqualTo: uid)
  .orderBy('timestamp', descending: true)
  .snapshots();
```

**Notification badge (Home/Dashboard bell icon)**

```dart
// Count unread alerts
.where('is_read', isEqualTo: false)
// Show red badge with count
```

---

## Phase 7 — Profile Sync & Data Export

### Flutter Changes

**Home Screen Greeting**
- Read `first_name` from Firestore `/users/{uid}` once on login
- Store in a Riverpod `StateProvider<String>` (`userNameProvider`)
- Replace hardcoded `"Adrian"` with the provider value

**Edit Profile Screen**
- On open: `FirebaseFirestore.instance.collection('users').doc(uid).get()`
- On save: `.set({...}, SetOptions(merge: true))`

**Profile Photo Upload (optional)**

```yaml
image_picker: ^1.1.2
cached_network_image: ^3.4.1
```

- Upload to Firebase Storage: `/profile_photos/{uid}.jpg`
- Display via `CachedNetworkImage(imageUrl: downloadUrl)`

---

## New Packages Summary

### Flutter (`pubspec.yaml`)

```yaml
# Firebase
firebase_core: ^3.6.0
firebase_auth: ^5.3.1
cloud_firestore: ^5.4.4
firebase_messaging: ^15.1.3
firebase_storage: ^12.3.4

# Notifications
flutter_local_notifications: ^17.2.3

# BLE Pairing
flutter_blue_plus: ^1.35.5
permission_handler: ^11.3.1

# Data Export
share_plus: ^10.1.4
path_provider: ^2.1.4

# Profile Photo (optional)
image_picker: ^1.1.2
cached_network_image: ^3.4.1
```

### Backend (`requirements.txt`)

```
firebase-admin==6.4.0
```

> All other backend dependencies remain (fastapi, uvicorn, websockets, pydantic, httpx, python-dotenv)

---

## Firestore Collections Reference

| Collection | Document ID | Purpose |
|---|---|---|
| `/users` | `{uid}` | User profile |
| `/user_settings` | `{uid}` | Thresholds, alert preferences |
| `/devices` | `{device_id}` | Device info + latest sensor values |
| `/sensor_readings` | `{auto_id}` | Historical sensor data (time-series) |
| `/alerts` | `{auto_id}` | Generated alerts / notifications |

---

## Final File Structure

```
agos/
├── agos_app/
│   ├── android/app/
│   │   └── google-services.json          ← NEW (from Firebase Console)
│   └── lib/
│       ├── core/
│       │   └── router/app_router.dart    ← + /login, /register, /forgot-password
│       ├── data/
│       │   └── services/
│       │       ├── websocket_service.dart     ← kept for ESP32 relay
│       │       ├── auth_service.dart           ← NEW (Firebase Auth wrapper)
│       │       ├── firestore_service.dart      ← NEW (Firestore read/write helpers)
│       │       └── notification_service.dart   ← NEW (FCM + local notifications)
│       └── presentation/
│           └── screens/
│               ├── auth/
│               │   ├── login_screen.dart             ← NEW
│               │   ├── register_screen.dart          ← NEW
│               │   └── forgot_password_screen.dart   ← NEW
│               └── ... (existing screens updated per phase)
├── backend/
│   ├── main.py                     ← Updated: Firebase Admin + threshold checking + FCM
│   ├── serviceAccountKey.json      ← NEW (from Firebase Console — in .gitignore)
│   ├── esp32_simulator_ws.py
│   ├── requirements.txt            ← + firebase-admin
│   └── start_server.bat
├── .gitignore                      ← + serviceAccountKey.json
└── README.md
```

> **Security note:** Add `serviceAccountKey.json` to `.gitignore` immediately — never commit this file to version control.

---

*All new Flutter screens follow the AGOS design system: light gradient backgrounds, Poppins headings, Inter body text, cyan–blue gradient buttons, 16px rounded cards, and the existing `AppColors` constants.*
