# AGOS — Automated Greywater Operational System

AGOS is a cross-platform Flutter mobile application paired with a Python WebSocket backend for real-time monitoring and management of a greywater recycling system. It displays live tank levels, water quality metrics (Turbidity, pH, TDS), historical trends, alerts, and device management — all communicating with an ESP32 hardware unit.

---

## Table of Contents

1. [Project Structure](#project-structure)
2. [Prerequisites](#prerequisites)
3. [Installation](#installation)
4. [Running the App](#running-the-app)
5. [Running the Backend](#running-the-backend)
6. [Running the ESP32 Simulator](#running-the-esp32-simulator)
7. [Architecture Overview](#architecture-overview)
8. [Key Features](#key-features)
9. [Navigation & Routes](#navigation--routes)
10. [Configuration](#configuration)
11. [Tech Stack](#tech-stack)
12. [Team](#team)

---

## Project Structure

```
agos/
├── agos_app/               # Flutter mobile application
│   ├── lib/
│   │   ├── main.dart                   # App entry point
│   │   ├── core/
│   │   │   ├── constants/
│   │   │   │   ├── app_colors.dart     # Color system
│   │   │   │   ├── api_config.dart     # WebSocket / API URLs
│   │   │   │   └── connection_method_design.dart  # Design tokens
│   │   │   └── router/
│   │   │       └── app_router.dart     # Named route definitions
│   │   ├── data/
│   │   │   └── services/
│   │   │       └── websocket_service.dart  # WS connection + Riverpod providers
│   │   └── presentation/
│   │       ├── screens/                # All app screens
│   │       └── widgets/                # Shared widgets
│   ├── assets/
│   │   ├── svg/                        # SVG logos and decorations
│   │   └── images/                     # PNG images, dev team photos
│   └── pubspec.yaml
├── backend/
│   ├── main.py                         # FastAPI WebSocket server
│   ├── esp32_simulator_ws.py           # ESP32 hardware simulator
│   └── requirements.txt
└── README.md
```

---

## Prerequisites

### Flutter App

- **Flutter SDK** ≥ 3.0.0 — [Install Flutter](https://docs.flutter.dev/get-started/install)
- **Dart** ≥ 3.0.0 (included with Flutter)
- **Android Studio** or **VS Code** with the Flutter extension
- **Android SDK** (for Android target) — API level as per `flutter.minSdkVersion`
- A physical Android/iOS device or emulator

### Backend

- **Python** ≥ 3.10
- **pip** package manager

---

## Installation

### 1. Clone the repository

```bash
git clone <your-repo-url>
cd agos
```

### 2. Install Flutter dependencies

```bash
cd agos_app
flutter pub get
```

### 3. Install Python dependencies

```bash
cd ../backend
pip install -r requirements.txt
```

---

## Running the App

### Android (physical device)

1. Enable **Developer Options** and **USB Debugging** on your Android device.
2. Connect via USB or use wireless ADB:
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

> **Note:** On the Android emulator, `10.0.2.2` maps to the host machine's `localhost`. The app handles this automatically via `ApiConfig`.

### Specific device

```bash
flutter devices                    # list connected devices
flutter run -d <device-id>
```

### Release build (APK)

```bash
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

---

## Running the Backend

The backend is a **FastAPI** server that:
- Serves a WebSocket endpoint at `ws://localhost:8000/ws/app` for the mobile app
- Serves a WebSocket endpoint at `ws://localhost:8000/ws/sensor` for the ESP32
- Broadcasts real-time sensor data to all connected app clients
- Manages state: tank level, water quality, alerts, device list

```bash
cd backend
python -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

> **Windows shortcut:** Double-click `backend/start_server.bat` to start the server without typing any commands.

> **Windows note:** If you get a `uvicorn: command not found` / `not recognized` error, use `python -m uvicorn` instead of just `uvicorn`. Make sure to type the full command on a single line without line breaks.

Once the server is running:

| URL | Description |
|-----|-------------|
| `http://localhost:8000` | Server status + connection counts |
| `http://localhost:8000/docs` | **Swagger UI** — interactive API documentation |
| `http://localhost:8000/redoc` | **ReDoc** — alternative API documentation view |
| `ws://localhost:8000/ws/app` | WebSocket endpoint for the mobile app |
| `ws://localhost:8000/ws/sensor` | WebSocket endpoint for the ESP32 hardware |

> **Important:** When running the app on a physical device, replace `localhost` with your computer's local IP address (e.g., `192.168.1.x`) in `agos_app/lib/core/constants/api_config.dart`.

---

## Running the ESP32 Simulator

The simulator mimics the ESP32 hardware unit sending sensor readings over WebSocket.

```bash
cd backend
python esp32_simulator_ws.py
```

This connects to `ws://localhost:8000/ws/sensor` and streams periodic turbidity, pH, TDS, and tank level readings.

---

## Architecture Overview

```
┌─────────────────────────────────────────────┐
│              Flutter App (UI)               │
│                                             │
│  Riverpod Providers ◄── WebSocketService   │
│        │                     │             │
│   Screens & Widgets      WS Client         │
└─────────────────────────────────────────────┘
                    │  WebSocket (ws://)
┌─────────────────────────────────────────────┐
│         FastAPI Backend (main.py)           │
│                                             │
│  /ws/app  ──────────────┐                  │
│  /ws/sensor ─────────── State Manager      │
└─────────────────────────────────────────────┘
                    │  WebSocket
┌─────────────────────────────────────────────┐
│     ESP32 Hardware / Simulator              │
│  (Turbidity, pH, TDS, Tank Level sensors)   │
└─────────────────────────────────────────────┘
```

**State Management:** Riverpod `StateNotifierProvider`s in `websocket_service.dart` hold:
- `tankDataProvider` — water level, volume, flow rate, status
- `waterQualityProvider` — turbidity, pH, TDS readings
- `alertsProvider` — list of active alerts
- `devicesProvider` — registered AGOS device list
- `historicalDataProvider` — time-series data for charts

---

## Key Features

| Feature | Description |
|---------|-------------|
| **Live Dashboard** | Real-time turbidity, pH, TDS metrics with animated progress bars |
| **Historical Charts** | Line charts with 24H / 7D / 30D period selector (fl_chart) |
| **Tank Monitor** | Animated water fill visualization on the home screen |
| **Water Quality Thresholds** | Configurable optimal range and critical limits per parameter |
| **Alert System** | Severity-coded notifications (critical / warning / info) with swipe-to-dismiss |
| **Device Management** | Add, view, and manage connected AGOS devices |
| **WiFi & Bluetooth Setup** | Step-by-step device pairing flow with progress tracking |
| **Settings** | Profile edit, data logging, privacy, alert thresholds, help, about |
| **Offline-capable UI** | Default mock data displayed when backend is unreachable |

---

## Navigation & Routes

| Route | Screen |
|-------|--------|
| `/` | Splash Screen |
| `/welcome` | Welcome / onboarding |
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

## Configuration

### Backend URL

Edit `agos_app/lib/core/constants/api_config.dart`:

```dart
class ApiConfig {
  static const int port = 8000;

  static String get host {
    if (Platform.isAndroid) return '10.0.2.2';  // emulator → host
    return 'localhost';
  }

  static String get wsAppUrl => 'ws://$host:$port/ws/app';
}
```

For a **physical device** on the same WiFi network, hardcode your machine's local IP:

```dart
// Example:
static String get host => '192.168.1.100';
```

### App Colors

All colors are defined in `agos_app/lib/core/constants/app_colors.dart`:

```dart
static const Color primary    = Color(0xFF00D3F2);  // Cyan
static const Color secondary  = Color(0xFF2B7FFF);  // Blue
static const Color background = Color(0xFFF4F8FB);  // Light grey
static const Color darkBlue   = Color(0xFF0A3D62);  // Dark blue
static const Color success    = Color(0xFF009966);  // Green
static const Color warning    = Color(0xFFF0B100);  // Amber
static const Color error      = Color(0xFFE74C3C);  // Red
```

---

## Tech Stack

### Flutter App

| Package | Version | Purpose |
|---------|---------|---------|
| `flutter_riverpod` | ^2.4.9 | State management |
| `web_socket_channel` | ^2.4.0 | WebSocket client |
| `fl_chart` | ^0.66.0 | Line/bar charts |
| `flutter_svg` | ^2.2.3 | SVG asset rendering |
| `google_fonts` | ^6.1.0 | Poppins & Inter fonts |
| `url_launcher` | ^6.3.0 | Open external URLs |
| `percent_indicator` | ^4.2.3 | Circular progress indicators |

### Backend

| Package | Version | Purpose |
|---------|---------|---------|
| `fastapi` | 0.109.0 | ASGI web framework |
| `uvicorn` | 0.27.0 | ASGI server |
| `websockets` | 12.0 | WebSocket support |
| `pydantic` | 2.5.3 | Data validation |

---

## Team

| Name | Role |
|------|------|
| Adrian Calingasin | Developer |
| Sebastian Dantes | Developer |
| Irish Anne Jayme | Developer |
| Jaichand Nagpal | Developer |
| Racelito Pascual | Developer |

**Institutional Affiliation:** Pamantasan ng Lungsod ng Maynila (PLM)

---

## License

This project is developed as an academic capstone project. All rights reserved.


to run the app on phone:

cd .\agos_app
flutter devices
flutter run -d 92535e42