# AGOS - Automated Greywater Operational System

AGOS is a cross-platform Flutter mobile application paired with a Python WebSocket backend for real-time monitoring and management of a greywater recycling system. It displays live tank levels, water quality metrics (Turbidity, pH, TDS), historical trends, alerts, and device management - all communicating with an ESP32 hardware unit via WebSocket through a deployed or local backend server.

> **Capstone Project** - Pamantasan ng Lungsod ng Maynila (PLM)

---

## Table of Contents

1. [Project Structure](#1-project-structure)
2. [Tech Stack](#2-tech-stack)
3. [First-Time Developer Setup](#3-first-time-developer-setup)
4. [Running the App](#4-running-the-app)
5. [Running the Backend](#5-running-the-backend)
6. [Running the ESP32 Simulator](#6-running-the-esp32-simulator)
7. [Architecture Overview](#7-architecture-overview)
8. [Full Data Flow](#8-full-data-flow)
9. [Key Features](#9-key-features)
10. [Navigation & Routes](#10-navigation--routes)
11. [Configuration Reference](#11-configuration-reference)
12. [Firebase Setup](#12-firebase-setup)
13. [ESP32 Hardware Integration](#13-esp32-hardware-integration)
14. [Deployment (Backend)](#14-deployment-backend)
15. [Team](#15-team)

---

## 1. Project Structure

```
agos/
+-- agos_app/                       # Flutter mobile application
|   +-- lib/
|   |   +-- main.dart               # App entry point, Firebase init, theme
|   |   +-- firebase_options.dart   # Generated Firebase config (do not edit)
|   |   +-- core/
|   |   |   +-- constants/
|   |   |   |   +-- api_config.dart             # Backend URL config (edit for deploy)
|   |   |   |   +-- app_colors.dart             # App-wide color constants
|   |   |   |   +-- connection_method_design.dart  # Setup flow design tokens
|   |   |   +-- router/
|   |   |       +-- app_router.dart             # All named routes
|   |   +-- data/
|   |   |   +-- services/
|   |   |       +-- websocket_service.dart      # WS client + all Riverpod providers
|   |   |       +-- firestore_service.dart      # Firestore queries + SetupState provider
|   |   |       +-- ble_provisioning_service.dart  # BLE scan/connect/provision
|   |   |       +-- filter_reminder_service.dart   # Local notification scheduler
|   |   +-- presentation/
|   |       +-- screens/
|   |       |   +-- splash/            # Splash + auth redirect
|   |       |   +-- welcome/           # Onboarding
|   |       |   +-- auth/              # Login, Register, Forgot Password
|   |       |   +-- home/              # Home screen (tank overview)
|   |       |   +-- dashboard/         # Live charts & particle animation
|   |       |   +-- connection/        # WiFi & Bluetooth setup screens
|   |       |   +-- pairing/           # Device scan, pairing & form screens
|   |       |   +-- notifications/     # Alert list
|   |       |   +-- settings/          # Settings hub + sub-screens
|   |       |   +-- profile/           # Edit profile
|   |       +-- widgets/
|   |           +-- bottom_nav_bar.dart
|   |           +-- notification_modal.dart
|   +-- assets/
|   |   +-- svg/                       # SVG logos and decorations
|   |   +-- images/                    # PNG images, dev team photos
|   +-- android/
|   |   +-- app/src/main/
|   |       +-- AndroidManifest.xml    # BLE + Location permissions declared here
|   +-- pubspec.yaml
+-- backend/
|   +-- main.py                        # FastAPI WebSocket server
|   +-- esp32_simulator_ws.py          # Simulates real ESP32 hardware data
|   +-- seed_firestore.py              # One-time Firestore data seeder
|   +-- check_firestore.py             # Utility to inspect Firestore
|   +-- requirements.txt               # Python dependencies
|   +-- start_server.bat               # Windows quick-start shortcut
|   +-- serviceAccountKey.json        # Firebase Admin SDK key (never commit)
+-- firestore.rules                    # Firestore security rules
+-- README.md
```

---

## 2. Tech Stack

### Flutter App

| Package | Version | Purpose |
|---------|---------|---------|
| `flutter_riverpod` | ^2.4.9 | State management (StateNotifierProvider, FutureProvider, StreamProvider) |
| `web_socket_channel` | ^2.4.0 | WebSocket client |
| `fl_chart` | ^0.66.0 | Line charts (historical data) |
| `flutter_svg` | ^2.2.3 | SVG rendering |
| `google_fonts` | ^6.1.0 | Poppins & Inter typography |
| `firebase_core` | ^3.6.0 | Firebase SDK base |
| `firebase_auth` | ^5.3.1 | Email/password + Google Sign-In |
| `cloud_firestore` | ^5.4.4 | Device records, sensor readings, alerts |
| `firebase_messaging` | ^15.1.3 | Push notifications |
| `firebase_storage` | ^12.3.0 | Profile picture storage |
| `flutter_blue_plus` | ^1.32.12 | BLE scanning and GATT connection |
| `flutter_bluetooth_classic_serial` | ^1.3.2 | Classic Bluetooth paired devices |
| `wifi_scan` | ^0.4.1 | WiFi network scanning |
| `permission_handler` | ^11.3.1 | Runtime permissions |
| `pdf` + `printing` | ^3.11.2 / ^5.14.2 | Data export to PDF |
| `shared_preferences` | ^2.3.2 | Local settings persistence |
| `flutter_local_notifications` | ^18.0.1 | Filter replacement reminders |

### Backend

| Package | Purpose |
|---------|---------|
| `fastapi >= 0.109` | ASGI web framework |
| `uvicorn[standard] >= 0.27` | ASGI server |
| `websockets >= 12.0` | WebSocket support |
| `pydantic >= 2.5` | Request/response validation |
| `firebase-admin >= 6.4` | Firestore write access from Python |
| `python-dotenv >= 1.0` | Environment variable loading |

---

## 3. First-Time Developer Setup

Follow these steps in order to get the full system running from scratch.

### 3.1 Prerequisites

| Tool | Minimum Version | Download |
|------|----------------|----------|
| Flutter SDK | >= 3.0.0 | https://docs.flutter.dev/get-started/install |
| Dart | >= 3.0.0 | Included with Flutter |
| Android Studio | Latest | https://developer.android.com/studio |
| VS Code | Latest (optional) | https://code.visualstudio.com |
| Python | >= 3.10 | https://www.python.org/downloads |
| Git | Any | https://git-scm.com |

> **Recommended VS Code extensions:** Flutter, Dart, Python, Firebase Explorer

---

### 3.2 Clone the Repository

```bash
git clone <repository-url>
cd agos
```

---

### 3.3 Firebase Project Setup

AGOS uses Firebase for authentication, database, and push notifications. You need your own Firebase project.

**Step 1 - Create a Firebase project**
1. Go to https://console.firebase.google.com
2. Click **Add Project** then name it `agos-prod` (or any name)
3. Enable Google Analytics (optional)

**Step 2 - Enable Authentication**
1. In Firebase Console - **Authentication** - **Sign-in method**
2. Enable **Email/Password**
3. Enable **Google** (requires a support email)

**Step 3 - Create Firestore Database**
1. Firebase Console - **Firestore Database** - **Create database**
2. Start in **test mode** (you'll apply security rules later)
3. Choose a region close to you (e.g. `asia-southeast1`)

**Step 4 - Add Android App**
1. Firebase Console - Project Settings - **Add app** - Android
2. Android package name: `com.agos.agos_app`
3. Download `google-services.json`
4. Place it at `agos_app/android/app/google-services.json` (replace the existing placeholder)

**Step 5 - Generate Flutter Firebase config**
```bash
# Install FlutterFire CLI
dart pub global activate flutterfire_cli

# From the agos_app directory:
cd agos_app
flutterfire configure --project=<your-firebase-project-id>
```
This regenerates `lib/firebase_options.dart` with your actual project credentials.

**Step 6 - Generate Backend Service Account Key**
1. Firebase Console - Project Settings - **Service accounts**
2. Click **Generate new private key** - Download JSON
3. Rename it to `serviceAccountKey.json`
4. Place it at `backend/serviceAccountKey.json`

> **NEVER commit `serviceAccountKey.json` or `google-services.json` to Git.** Both are in `.gitignore`.

---

### 3.4 Install Flutter Dependencies

```bash
cd agos_app
flutter pub get
```

Verify everything is working:

```bash
flutter doctor
flutter analyze
```

Both should report no critical issues.

---

### 3.5 Install Python Dependencies

```bash
cd backend
pip install -r requirements.txt
```

Or use a virtual environment (recommended):

```bash
cd backend
python -m venv .venv

# Windows
.\.venv\Scripts\activate

# macOS/Linux
source .venv/bin/activate

pip install -r requirements.txt
```

---

### 3.6 Configure the Backend URL

Open `agos_app/lib/core/constants/api_config.dart`:

```dart
class ApiConfig {
  static const int port = 8000;

  static String get host {
    if (kIsWeb) return 'localhost';
    if (Platform.isAndroid) return '10.0.2.2';   // Android emulator -> host
    return 'localhost';
  }
}
```

**For a physical device** on the same WiFi network as your development machine, replace with your machine's local IP:

```dart
static String get host => '192.168.1.100';  // your PC's local IP
```

Find your local IP:
- Windows: `ipconfig` - look for IPv4 Address under your WiFi adapter
- macOS/Linux: `ifconfig | grep inet`

---

### 3.7 Configure Android Permissions (already done)

The following permissions are already declared in `android/app/src/main/AndroidManifest.xml`:
- `BLUETOOTH_SCAN` (with `neverForLocation` flag)
- `BLUETOOTH_CONNECT`
- `ACCESS_FINE_LOCATION`
- `INTERNET`
- `ACCESS_NETWORK_STATE`

No additional steps needed unless targeting a new device.

---

### 3.8 Run Everything

Start all three components in separate terminals:

**Terminal 1 - Backend server:**
```bash
cd backend
python -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

**Terminal 2 - ESP32 simulator (optional, for development without hardware):**
```bash
cd backend
python esp32_simulator_ws.py
```

**Terminal 3 - Flutter app:**
```bash
cd agos_app
flutter run
# Or for a specific device:
flutter run -d <device-id>
```

---

## 4. Running the App

### Android (physical device)

1. Enable **Developer Options** and **USB Debugging** on your Android device.
2. Connect via USB or wireless ADB:
   ```bash
   adb connect <device-ip>:<port>
   ```
3. Run:
   ```bash
   cd agos_app
   flutter run
   ```

### Android Emulator

```bash
cd agos_app
flutter run
```

> **Note:** On Android emulator, `10.0.2.2` maps to the host machine's `localhost`. The app handles this automatically via `ApiConfig`.

### Windows Desktop

```bash
cd agos_app
flutter run -d windows
```

### List connected devices

```bash
flutter devices
flutter run -d <device-id>
```

### Release APK

```bash
flutter build apk --release
# Output: agos_app/build/app/outputs/flutter-apk/app-release.apk
```

---

## 5. Running the Backend

The backend is a **FastAPI** server providing:
- `ws://localhost:8000/ws/app` - WebSocket endpoint for the Flutter app
- `ws://localhost:8000/ws/sensor` - WebSocket endpoint for the ESP32
- Broadcasts real-time sensor data to all connected app clients
- Reads/writes device state to Firestore

```bash
cd backend
python -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

> **Windows shortcut:** Double-click `backend/start_server.bat`

| URL | Description |
|-----|-------------|
| `http://localhost:8000` | Server status + connection counts |
| `http://localhost:8000/docs` | Swagger UI - interactive API docs |
| `http://localhost:8000/redoc` | ReDoc documentation view |
| `ws://localhost:8000/ws/app` | Flutter app WebSocket |
| `ws://localhost:8000/ws/sensor` | ESP32 hardware WebSocket |

---

## 6. Running the ESP32 Simulator

The simulator mimics the ESP32 hardware unit, sending periodic sensor readings over WebSocket.

```bash
cd backend
python esp32_simulator_ws.py
```

This connects to `ws://localhost:8000/ws/sensor` and streams:
- Turbidity (NTU)
- pH level
- TDS (ppm)
- Tank water level (%)
- Volume (liters)
- Flow rate (L/min)
- Pump active status

---

## 7. Architecture Overview

```
+-----------------------------------------------+
|              Flutter App (UI)                 |
|                                               |
|  Riverpod Providers <-- WebSocketService      |
|        |                     |               |
|   Screens & Widgets      WS Client           |
+-----------------------------------------------+
                    |  WebSocket (ws://)
+-----------------------------------------------+
|         FastAPI Backend (main.py)             |
|                                               |
|  /ws/app  <------------------------+          |
|  /ws/sensor -> State Manager -> Broadcast     |
|                    |                          |
|              Firestore (Firebase)             |
+-----------------------------------------------+
                    |  WebSocket
+-----------------------------------------------+
|     ESP32 Hardware / Simulator                |
|  (Turbidity, pH, TDS, Tank Level sensors)     |
+-----------------------------------------------+
```

**State Management:** Riverpod `StateNotifierProvider`s in `websocket_service.dart`:
- `tankDataProvider` - water level, volume, flow rate, status
- `waterQualityProvider` - turbidity, pH, TDS readings
- `alertsProvider` - list of active alerts
- `devicesProvider` - registered AGOS device list
- `historicalDataProvider` - time-series data for charts

**Setup State:** `setupStateProvider` in `firestore_service.dart` tracks device provisioning:
- `deviceId` (`agos-{first 8 chars of Firebase UID}`)
- `deviceName`, `location`, `connectionMethod`
- Cleared after setup complete

---

## 8. Full Data Flow

### Sensor Reading Flow (ESP32 -> App)

```
ESP32 Hardware
  -> connects to ws://backend/ws/sensor
  -> sends: {"type":"sensor_data","device_id":"agos-abc12345","turbidity":5.2,"ph":7.1,"tds":320,"level":72,"volume":36000,"flow_rate":145,"pump_active":false}

Backend (main.py)
  -> receives sensor_data
  -> writes to Firestore: sensor_readings/{device_id}
  -> broadcasts to all /ws/app clients: {"type":"sensor_data",...}

Flutter App
  -> WebSocketService receives broadcast
  -> Updates Riverpod providers: waterQualityProvider, tankDataProvider
  -> UI rebuilds: Dashboard charts, Home screen tank level
```

### Device Provisioning Flow (First-Time Setup)

```
User opens app
  -> Splash -> Welcome -> Connection Method

If Bluetooth:
  -> bluetooth_setup1_screen  (enable Bluetooth)
  -> bluetooth_setup2_screen  (grant permissions)
  -> ready_to_scan_screen     (scan BLE devices)
  -> wifi_setup_screen        (enter WiFi credentials)
    -> BLE sends: {"ssid":"...","password":"...","device_id":"agos-abc12345"}
  -> pairing_device_screen    (progress)
  -> device_information_form  (name, location)
  -> setup_complete_screen    (saves to Firestore)

If WiFi:
  -> wifi_setup_screen
  -> ready_to_pair_screen
  -> pairing_device_screen
  -> device_information_form
  -> setup_complete_screen
```

### Firestore Collections

| Collection | Document | Key Fields |
|------------|----------|-----------|
| `users` | `{uid}` | `displayName`, `email`, `photoUrl`, `createdAt` |
| `devices` | `{deviceId}` | `name`, `location`, `ownerId`, `connectionMethod`, `createdAt` |
| `sensor_readings` | `{deviceId}` | `turbidity`, `ph`, `tds`, `level`, `volume`, `flow_rate`, `pump_active`, `timestamp` |
| `user_thresholds` | `{uid}` | `turbidityMin`, `turbidityMax`, `phMin`, `phMax`, `tdsMin`, `tdsMax` |
| `alert_settings` | `{uid}` | `criticalAlerts`, `warningAlerts`, `infoAlerts` |
| `pump_commands` | `{deviceId}` | `command` (`start`/`stop`), `duration`, `timestamp` |

---

## 9. Key Features

| Feature | Description |
|---------|-------------|
| **Live Dashboard** | Real-time turbidity, pH, TDS metrics with animated progress bars |
| **Historical Charts** | Line charts with 24H / 7D / 30D period selector (fl_chart) |
| **Tank Monitor** | Animated water fill visualization on the home screen |
| **Water Quality Thresholds** | Configurable optimal range and critical limits per parameter |
| **Alert System** | Severity-coded notifications (critical / warning / info) with swipe-to-dismiss |
| **Device Management** | Add, view, and manage connected AGOS devices |
| **WiFi & Bluetooth Setup** | Step-by-step device pairing flow with progress tracking |
| **BLE Provisioning** | Sends WiFi credentials + device ID to ESP32 via Bluetooth |
| **PDF Export** | Export sensor history to PDF for reporting |
| **Filter Reminders** | Local notifications reminding user to replace water filter |
| **Settings** | Profile edit, data logging, privacy, alert thresholds, help, about |
| **Offline-capable UI** | Default mock data displayed when backend is unreachable |

---

## 10. Navigation & Routes

| Route | Screen |
|-------|--------|
| `/` | Splash Screen |
| `/welcome` | Welcome / onboarding |
| `/login` | Login |
| `/register` | Register |
| `/forgot-password` | Forgot Password |
| `/connection-method` | Choose WiFi or Bluetooth |
| `/wifi-setup` | WiFi network selection & password |
| `/bluetooth-setup-1` | Enable Bluetooth step |
| `/bluetooth-setup-2` | Grant permissions step |
| `/ready-to-scan` | Bluetooth device scan |
| `/ready-to-pair` | WiFi device discovery |
| `/pairing-device` | Device authentication progress |
| `/device-information` | Enter device details form |
| `/setup-complete` | Setup success screen |
| `/home` | Home Screen (tank overview) |
| `/dashboard` | Dashboard (metrics + charts) |
| `/tank-details` | Tank detail view |
| `/device-management` | Manage connected devices |
| `/notifications` | Notification history |
| `/edit-profile` | Edit user profile |
| `/settings` | Settings hub |
| `/privacy-security` | Privacy & security options |
| `/alert-settings` | Alert threshold configuration |
| `/water-quality-thresholds` | pH, turbidity, TDS thresholds |
| `/data-logging` | Data logging & export options |
| `/help` | Help & FAQ |
| `/about` | About the app & team |

---

## 11. Configuration Reference

### Backend URL (`api_config.dart`)

```dart
class ApiConfig {
  static const int port = 8000;

  static String get host {
    if (kIsWeb) return 'localhost';
    if (Platform.isAndroid) return '10.0.2.2';  // emulator -> host
    return 'localhost';
  }

  static String get wsAppUrl => 'ws://$host:$port/ws/app';
  static String get httpBaseUrl => 'http://$host:$port';
}
```

### App Colors (`app_colors.dart`)

```dart
static const Color primary    = Color(0xFF00D3F2);  // Cyan
static const Color secondary  = Color(0xFF2B7FFF);  // Blue
static const Color background = Color(0xFFF4F8FB);  // Light grey
static const Color darkBlue   = Color(0xFF0A3D62);  // Dark blue
static const Color success    = Color(0xFF009966);  // Green
static const Color warning    = Color(0xFFF0B100);  // Amber
static const Color error      = Color(0xFFE74C3C);  // Red
```

### Device ID Format

```
agos-{first 8 characters of Firebase UID}
```
Example: `agos-ab12cd34`

Generated in `wifi_setup_screen.dart` and `setup_complete_screen.dart`.

---

## 12. Firebase Setup

### Firestore Security Rules

Apply the rules from `firestore.rules` in the Firebase Console:

1. Firebase Console - Firestore Database - **Rules** tab
2. Paste the contents of `firestore.rules`
3. Click **Publish**

### Seed Initial Data (Optional)

To populate Firestore with sample devices and readings for testing:

```bash
cd backend
python seed_firestore.py
```

### Verify Firestore Connectivity

```bash
cd backend
python check_firestore.py
```

---

## 13. ESP32 Hardware Integration

### Firmware Requirements

The ESP32 firmware must implement:

1. **BLE GATT Server** - Receive WiFi credentials from the app during setup
   - Service UUID: defined in `ble_provisioning_service.dart`
   - Characteristic: receives JSON: `{"ssid":"...","password":"...","device_id":"agos-abc12345"}`

2. **WiFi Client** - Connect to the home WiFi network using received credentials
   - Store credentials in NVS (Preferences library) for persistence across reboots

3. **WebSocket Client** - Connect to `ws://<backend-ip>:8000/ws/sensor`
   - Reconnect on disconnect with exponential backoff

4. **Sensor Reading** - Periodic reading and transmission (every 5 seconds recommended):
   ```json
   {
     "type": "sensor_data",
     "device_id": "agos-abc12345",
     "turbidity": 5.2,
     "ph": 7.1,
     "tds": 320.0,
     "level": 72.0,
     "volume": 36000.0,
     "flow_rate": 145.0,
     "pump_active": false
   }
   ```

5. **Pump Command Handling** - Listen for pump commands:
   ```json
   {"type": "pump_command", "command": "start", "duration": 60, "device_id": "agos-abc12345"}
   {"type": "pump_command", "command": "stop", "device_id": "agos-abc12345"}
   ```

### Recommended Arduino Libraries

| Library | Purpose |
|---------|---------|
| `ArduinoJson` | JSON parsing and serialization |
| `WebSocketsClient` (links2004/arduinoWebSockets) | WebSocket client |
| `Preferences` | NVS storage for WiFi credentials |
| `ESP32 BLE Arduino` | BLE GATT server |

---

## 14. Deployment (Backend)

### Railway (recommended free tier)

1. Push the `backend/` folder to a GitHub repository
2. Go to https://railway.app - New Project - Deploy from GitHub
3. Set the **Start Command** to:
   ```
   python -m uvicorn main:app --host 0.0.0.0 --port $PORT
   ```
4. Add environment variable: `PORT=8000` (Railway sets `$PORT` automatically)
5. Upload `serviceAccountKey.json` content as an environment variable (recommended) or use Railway's file storage
6. After deploy, copy the public URL (e.g. `https://agos-backend.up.railway.app`)
7. Set in `api_config.dart`:
   ```dart
   static const String _productionUrl = 'https://agos-backend.up.railway.app';
   ```

### Alternative: Render / Fly.io / VPS

Same process - any platform that runs Python and exposes a public HTTPS/WSS URL will work.

> **Note:** WebSocket connections over `wss://` are required for production. The app automatically upgrades `https://` to `wss://` for WebSocket URLs.

---

## 15. Team

| Name | Role | Focus | Key Deliverable |
|------|------|-------|-----------------|
| **Calingasin, Adrian** | Full-Stack Developer | End-to-end software architecture: FastAPI backend, Flutter mobile interface, and hardware communication integration layer | Functional, unified software ecosystem |
| **Dantes, Sebastian** | Fluid Architect | Physical logic of water flow - tank placement, pipe routing, and hydraulic requirements for the filtration process | Plumbing schematics and tank flow logic |
| **Jayme, Irish Anne** | Project Operations Coordinator | Project timeline and task distribution; ensures milestones are met by coordinating between software, hardware, and documentation branches | Task schedules and progress tracking |
| **Nagpal, Jaichand** | Technical Documentation Specialist | Formal record of the project - technical specifications, methodology, and results captured in the final paper | Comprehensive project manuscript and technical manuals |
| **Pascual, Racelito** | Embedded Technician | Hardware configuration - ESP32 microcontroller, sensor and actuator interfacing, firmware-to-software communication | Configured firmware and hardware-to-software communication |

**Institution:** Pamantasan ng Lungsod ng Maynila (PLM)

---

## License

Academic capstone project. All rights reserved (c) 2024 AGOS Team - PLM.

