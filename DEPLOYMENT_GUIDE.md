# AGOS Deployment Guide
## Complete Free Deployment: Frontend (Flutter) + Backend (Railway) + Hardware (ESP32)

---

## Overview

| Component | Where it runs | Cost |
|-----------|--------------|------|
| **Flutter App (Android)** | APK — sideload or Play Store | Free |
| **Flutter App (Web / iOS PWA)** | Firebase Hosting or GitHub Pages | **Free** — iOS users open URL → Add to Home Screen |
| **FastAPI Backend** | Railway cloud | **Free** (uses $5 free credit, actual cost ~$0.05/month) |
| **Firebase Auth** | Google Firebase cloud | **Free** (Spark plan, no card needed) |
| **Firestore Database** | Google Firebase cloud | **Free** (14,400 writes/day — well under 20,000 free limit) |
| **ESP32 Hardware** | Physical device (on-site) | One-time hardware cost only |

---

## Architecture (after deployment)

```
ESP32 Hardware (on-site WiFi)
  │
  │  WebSocket (wss://your-app.up.railway.app/ws/sensor)
  ▼
Railway Cloud Server  ──── Firebase Admin SDK ────► Firestore (cloud database)
  │
  │  WebSocket (wss://your-app.up.railway.app/ws/app)
  ▼
Flutter App
  ├── Android  →  APK install (sideload / Play Store)
  ├── iPhone   →  Web URL → "Add to Home Screen" → runs as PWA
  └── Browser  →  Any device, open URL directly
  │
  ├── Firebase Auth SDK (login/session)
  └── WebSocket (real-time data stream from Railway)
```

---

## Part 1 — Firebase Setup (already done, verify only)

Firebase is used for **authentication only** in the current architecture. Firestore is written to by the backend (not the app directly for sensor data).

### Verify your Firebase project is on Spark (free) plan:
1. Go to [Firebase Console](https://console.firebase.google.com)
2. Select your AGOS project
3. Click the gear icon → **Usage and billing**
4. Confirm plan is **Spark (free)**

### Free tier limits you care about:
| Service | Free limit | Your expected usage |
|---------|-----------|-------------------|
| Firestore writes | 20,000/day | ~14,420/day ✅ |
| Firestore reads | 50,000/day | ~500/day ✅ |
| Firebase Auth | 10,000 users/month | <100 users ✅ |
| FCM Push notifications | Free | ✅ |

### Get your serviceAccountKey.json (needed for Railway):
1. Firebase Console → Project Settings → **Service Accounts** tab
2. Click **Generate new private key**
3. Save the JSON file — **keep it secret, never commit to git**
4. Open it in a text editor — you'll need the full contents in Step 2

---

## Part 2 — Backend Deployment to Railway

### Step 1: Prepare the backend files

**A. Update `backend/main.py` to load credentials from environment variable:**

Replace the Firebase init block (lines 17–29) with this:

```python
import json
import tempfile

_SERVICE_ACCOUNT_PATH = os.path.join(os.path.dirname(__file__), "serviceAccountKey.json")
_SERVICE_ACCOUNT_ENV = os.environ.get("FIREBASE_SERVICE_ACCOUNT_JSON")

if _SERVICE_ACCOUNT_ENV:
    # Railway/production: credentials from environment variable
    try:
        sa_info = json.loads(_SERVICE_ACCOUNT_ENV)
        cred = credentials.Certificate(sa_info)
        firebase_admin.initialize_app(cred)
        db = firestore.client()
        FIREBASE_ENABLED = True
        logger.info("Firebase initialized from environment variable.")
    except Exception as e:
        db = None
        FIREBASE_ENABLED = False
        logger.error(f"Firebase env init failed: {e}")
elif os.path.exists(_SERVICE_ACCOUNT_PATH):
    # Local development: credentials from file
    cred = credentials.Certificate(_SERVICE_ACCOUNT_PATH)
    firebase_admin.initialize_app(cred)
    db = firestore.client()
    FIREBASE_ENABLED = True
    logger.info("Firebase Admin SDK initialized from file.")
else:
    db = None
    FIREBASE_ENABLED = False
    logger.warning("No Firebase credentials found — running without persistence.")
```

**B. Add `backend/Procfile`:**
```
web: uvicorn main:app --host 0.0.0.0 --port $PORT
```

**C. Add `backend/runtime.txt`:**
```
python-3.11.0
```

**D. Verify `backend/requirements.txt`** contains all dependencies:
```
fastapi>=0.109.0
uvicorn[standard]>=0.27.0
websockets>=12.0
pydantic>=2.5.0
python-dotenv>=1.0.0
firebase-admin>=6.4.0
```

### Step 2: Push backend to GitHub

```bash
# From your agos/ directory
git add backend/
git commit -m "feat: prepare backend for Railway deployment"
git push origin main
```

> **Important:** Make sure `backend/serviceAccountKey.json` is in your `.gitignore`. Never push the key file to GitHub.

Check your `.gitignore` includes:
```
backend/serviceAccountKey.json
agos-prod-firebase-adminsdk-*.json
*.json  # (if you have this already)
```

### Step 3: Deploy to Railway

1. Go to [railway.app](https://railway.app) → **Login with GitHub**
2. Click **New Project** → **Deploy from GitHub repo**
3. Select your `agos` repository
4. Railway will detect the code — when asked for the root directory, set it to **`backend`**
5. Railway auto-detects Python with the `Procfile`

### Step 4: Set environment variables on Railway

In your Railway project dashboard:
1. Click your service → **Variables** tab
2. Add variable:
   - **Name:** `FIREBASE_SERVICE_ACCOUNT_JSON`
   - **Value:** Paste the **entire contents** of your `serviceAccountKey.json` file (the whole JSON)
3. Click **Save** — Railway will redeploy automatically

### Step 5: Get your Railway domain

1. In Railway dashboard → your service → **Settings** tab
2. Under **Domains** → click **Generate Domain**
3. You'll get something like: `agos-backend-production.up.railway.app`
4. **Copy this domain — you need it for the Flutter app**

### Step 6: Verify backend is running

Open in browser:
```
https://your-app.up.railway.app/
```

You should see:
```json
{
  "message": "AGOS WebSocket Server",
  "version": "1.0.0",
  "status": "running",
  "firebase": true,
  "connections": { "sensors": 0, "apps": 0 }
}
```

---

## Part 3 — Flutter App Update (Production WebSocket URL)

### Update `agos_app/lib/core/constants/api_config.dart`

Replace the current file with this:

```dart
class ApiConfig {
  ApiConfig._();

  // ── Toggle this flag for local vs production ──────────────────────────────
  static const bool _useProduction = true; // ← set false for local development

  // ── Production (Railway) ──────────────────────────────────────────────────
  static const String _productionHost = 'your-app.up.railway.app'; // ← replace with your Railway domain
  static const bool _productionSecure = true; // uses wss:// and https://

  // ── Local development ─────────────────────────────────────────────────────
  // Use 'localhost' with `adb reverse tcp:8000 tcp:8000`
  static const String _localHost = 'localhost';
  static const int _localPort = 8000;

  // ── Computed URLs ─────────────────────────────────────────────────────────
  static String get wsAppUrl {
    if (_useProduction) {
      return 'wss://$_productionHost/ws/app';
    }
    return 'ws://$_localHost:$_localPort/ws/app';
  }

  static String get wsSensorUrl {
    if (_useProduction) {
      return 'wss://$_productionHost/ws/sensor';
    }
    return 'ws://$_localHost:$_localPort/ws/sensor';
  }

  static String get httpBaseUrl {
    if (_useProduction) {
      return 'https://$_productionHost';
    }
    return 'http://$_localHost:$_localPort';
  }
}
```

> Replace `your-app.up.railway.app` with your actual Railway domain from Step 5 above.

### Build release APK (Android)

```bash
cd agos_app
flutter build apk --release
```

Output: `agos_app/build/app/outputs/flutter-apk/app-release.apk`

### Install on Android device

```bash
adb install build/app/outputs/flutter-apk/app-release.apk
```

Or transfer the APK file to the phone and install manually (enable "Install from unknown sources" in Android settings).

---

## Part 3.5 — Web Deployment + iOS "Add to Home Screen" (PWA)

Since there's no App Store build for iOS, iPhone users access AGOS through a browser and install it as a **Progressive Web App (PWA)**. This makes it behave exactly like a native app — full screen, home screen icon, no browser chrome.

### Step 1: Add PWA install prompt for iOS users

The app already has a `manifest.json` in `web/`. Add a small in-app banner that appears on iOS Safari to guide users to add it to their home screen.

In `agos_app/lib/main.dart`, add this after `runApp(...)` (web only):

```dart
// Already handled by the browser on Chrome/Edge (automatic install prompt).
// For iOS Safari, we show a custom in-app banner — see IosInstallBanner widget.
```

Create `agos_app/lib/presentation/widgets/ios_install_banner.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Shows a one-time banner on iOS Safari: "Add to Home Screen for the best experience"
class IosInstallBanner extends StatefulWidget {
  final Widget child;
  const IosInstallBanner({super.key, required this.child});

  @override
  State<IosInstallBanner> createState() => _IosInstallBannerState();
}

class _IosInstallBannerState extends State<IosInstallBanner> {
  bool _show = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      // Show banner only on iOS Safari (not already installed as PWA)
      final ua = Uri.base.toString();
      final isIos = ua.contains('iPhone') || ua.contains('iPad');
      final isStandalone = Uri.base.queryParameters.containsKey('standalone');
      if (isIos && !isStandalone) {
        _show = true;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return widget.child;
    return Column(
      children: [
        Material(
          color: const Color(0xFF00D3F2),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Install AGOS: tap  ⎙  then "Add to Home Screen"',
                      style: TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 18),
                    onPressed: () => setState(() => _show = false),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(child: widget.child),
      ],
    );
  }
}
```

Wrap your `MaterialApp` in `main.dart` with this widget:

```dart
runApp(const IosInstallBanner(child: ProviderScope(child: AgosApp())));
```

### Step 2: Update web/manifest.json for PWA

Open `agos_app/web/manifest.json` and make sure it has:

```json
{
  "name": "AGOS",
  "short_name": "AGOS",
  "start_url": ".",
  "display": "standalone",
  "background_color": "#00B8DB",
  "theme_color": "#00D3F2",
  "description": "AGOS Water Monitoring System",
  "orientation": "portrait-primary",
  "prefer_related_applications": false,
  "icons": [
    { "src": "icons/Icon-192.png", "sizes": "192x192", "type": "image/png" },
    { "src": "icons/Icon-512.png", "sizes": "512x512", "type": "image/png" },
    { "src": "icons/Icon-maskable-192.png", "sizes": "192x192", "type": "image/png", "purpose": "maskable" },
    { "src": "icons/Icon-maskable-512.png", "sizes": "512x512", "type": "image/png", "purpose": "maskable" }
  ]
}
```

Key fields:
- `"display": "standalone"` — hides browser UI when launched from home screen
- `"prefer_related_applications": false` — suppresses Play Store banner on Android

### Step 3: Build Flutter web

```bash
cd agos_app
flutter build web --release
```

Output folder: `agos_app/build/web/`

### Step 4: Deploy to Firebase Hosting (free)

Firebase Hosting is free on the Spark plan (10 GB storage, 360 MB/day transfer).

```bash
# Install Firebase CLI (once)
npm install -g firebase-tools

# Login
firebase login

# Init (from agos_app/ folder)
cd agos_app
firebase init hosting
# → Select your agos-prod project
# → Public directory: build/web
# → Single-page app: Yes
# → Overwrite index.html: No

# Deploy
firebase deploy --only hosting
```

You'll get a URL like: `https://agos-prod.web.app`

### Step 5: Add domain to Firebase Authorized Domains

For Google Sign-In to work on the web build:
1. Firebase Console → Authentication → **Sign-in method** tab
2. Scroll to **Authorized domains**
3. Add `agos-prod.web.app` (and any custom domain if you set one)

### How iPhone users install AGOS

1. Send the URL (`https://agos-prod.web.app`) to iPhone users via message/email
2. They open it in **Safari** (must be Safari, not Chrome, for Add to Home Screen to work)
3. Tap the **Share button** (⎙ box with arrow)
4. Tap **"Add to Home Screen"**
5. The app icon (your AGOS icon) appears on their iPhone home screen
6. Tapping it opens the app **full screen**, no Safari address bar — looks and feels native

> **Note:** iOS PWAs have some limitations vs native apps: no push notifications on iOS <16.4, no background sync. For AGOS, the real-time WebSocket data and all core features work fully.

### Alternative: GitHub Pages (also free)

If you don't want to use Firebase Hosting:

```bash
# Build
flutter build web --release --base-href "/agos/"

# Copy build/web contents to a gh-pages branch and push
# Your app will be at: https://yourusername.github.io/agos/
```

---

## Part 4 — ESP32 Hardware Deployment

### What the ESP32 needs to do

Connect to WiFi → establish a WebSocket connection to your Railway backend → send sensor data every 5 seconds.

### Arduino/ESP32 code WebSocket connection

Update your ESP32 firmware to point to the Railway URL:

```cpp
// In your ESP32 WebSocket connection code
const char* ws_host = "your-app.up.railway.app";  // ← your Railway domain
const int ws_port = 443;                            // HTTPS/WSS port
const char* ws_path = "/ws/sensor";
const char* device_id = "agos-zksl9QK3";           // ← your device ID

// Use wss:// (secure WebSocket) since Railway requires HTTPS
// Arduino WebSocket library: use WebSocketsClient with SSL
client.beginSSL(ws_host, ws_port, ws_path);
```

**Required ESP32 libraries (Arduino IDE):**
- `WebSocketsClient` by Markus Sattler (search "arduinowebsockets" in Library Manager)
- `ArduinoJson` by Benoit Blanchon
- `WiFi.h` (built-in with ESP32 board package)

### Sensor data format to send (JSON)

```json
{
  "type": "sensor_data",
  "device_id": "agos-zksl9QK3",
  "level": 68.5,
  "volume": 34250.0,
  "capacity": 50000,
  "flow_rate": 145.2,
  "turbidity": 3.45,
  "ph": 7.2,
  "tds": 320.0,
  "temperature": 25.1,
  "pump_active": false,
  "timestamp": "2025-01-01T12:00:00.000"
}
```

### Handling pump commands from server

The server will send pump commands to the ESP32 over the same WebSocket connection:

```json
{
  "type": "pump_command",
  "action": "on",
  "duration_seconds": 300
}
```

Your ESP32 code must listen for incoming messages and activate/deactivate the pump relay accordingly.

### Testing without hardware (ESP32 simulator)

During development when you don't have the physical device:

```bash
# Update WS_URL in esp32_simulator_ws.py first:
WS_URL = "wss://your-app.up.railway.app/ws/sensor"

# Then run:
cd backend
python esp32_simulator_ws.py
```

> Note: For the simulator to connect to Railway over WSS, install the `websockets` Python package with SSL support (already in requirements.txt).

---

## Part 5 — Updating Your Deployment

### Updating the backend

Any time you change backend code:

```bash
git add backend/
git commit -m "fix: description of change"
git push origin main
# Railway auto-deploys in ~90 seconds. No other steps needed.
```

### Updating the Flutter app

**Android (APK):**
```bash
# 1. Make your changes in VS Code
# 2. Build new APK
cd agos_app
flutter build apk --release

# 3. Install on device
adb install build/app/outputs/flutter-apk/app-release.apk
# or transfer APK file manually
```

**Web + iOS PWA:**
```bash
cd agos_app
flutter build web --release
firebase deploy --only hosting
# Changes are live immediately — iOS users who added to Home Screen just reload the app
```

### Checking Railway logs

In Railway dashboard → your service → **Deployments** tab → click latest deployment → **View Logs**

You'll see real-time FastAPI output including WebSocket connections and Firestore writes.

---

## Part 6 — Daily Usage Monitoring

### Firestore usage (stay within free limits)

Go to Firebase Console → Firestore → **Usage** tab to monitor daily reads/writes.

**Your throttle settings (in `main.py`):**
```python
FIRESTORE_WRITE_INTERVAL_S = 15   # 1 write per 15s per device
DEVICE_UPDATE_INTERVAL_S = 60     # 1 device update per 60s
```

**Calculation per device per day:**
- Sensor readings: 86,400 ÷ 15 = 5,760 writes
- Device updates: 86,400 ÷ 60 = 1,440 writes
- 2 devices × (5,760 + 1,440) = **14,400 writes/day**
- Free limit: **20,000/day** → **31% headroom** ✅

**If you add more devices**, increase `FIRESTORE_WRITE_INTERVAL_S` accordingly:
- 3 devices: use `FIRESTORE_WRITE_INTERVAL_S = 20` (stays under 20k)
- 4 devices: use `FIRESTORE_WRITE_INTERVAL_S = 25`

---

## Part 7 — Troubleshooting

### App can't connect to backend
- Verify Railway deployment is live: `https://your-app.up.railway.app/`
- Check `api_config.dart` has `_useProduction = true` and correct Railway domain
- Rebuild and reinstall APK after changing `api_config.dart`

### Backend shows `firebase: false`
- Check Railway environment variables — `FIREBASE_SERVICE_ACCOUNT_JSON` must be set
- Make sure you pasted the full JSON content (including `{ }`)
- Check Railway deployment logs for Firebase initialization errors

### ESP32 can't connect to Railway
- Railway uses WSS (secure WebSocket on port 443) — make sure ESP32 uses SSL WebSocket client
- Some ESP32 boards need the Railway server's SSL certificate — use `client.setInsecure()` for testing

### Firestore writes failing
- Check Firebase Console → Firestore → Rules tab
- Ensure rules allow backend writes (backend uses Admin SDK so it bypasses client rules by default)
- Check Railway logs for `[Firestore]` error lines

### Railway deployment failing
- Check the build log in Railway dashboard
- Most common issue: missing `Procfile` or wrong root directory setting
- Make sure `requirements.txt` is in the `backend/` folder

---

## Quick Reference

| Task | Command / Location |
|------|--------------------|
| View backend logs | Railway dashboard → your service → Deployments → View Logs |
| Check Firestore usage | Firebase Console → Firestore → Usage |
| Check Railway credits | Railway dashboard → Account → Billing |
| Update backend | `git push origin main` (auto-deploys) |
| Build flutter **APK** (Android) | `cd agos_app && flutter build apk --release` |
| Build flutter **Web** | `cd agos_app && flutter build web --release` |
| Deploy web to Firebase Hosting | `cd agos_app && firebase deploy --only hosting` |
| iOS users — install as PWA | Send URL → Safari → Share ⌘ → "Add to Home Screen" |
| Switch to local dev | Set `_useProduction = false` in `api_config.dart` |
| Run ESP32 simulator locally | `cd backend && python esp32_simulator_ws.py` |
| Inspect Firestore data | `cd backend && python check_firestore.py 50` |
| Seed test data | `cd backend && python seed_firestore.py` |

---

## Summary Checklist

### One-time setup
- [ ] Firebase project created and on Spark free plan
- [ ] `serviceAccountKey.json` downloaded from Firebase Console
- [ ] `serviceAccountKey.json` added to `.gitignore`
- [ ] `backend/main.py` updated to read credentials from environment variable
- [ ] `backend/Procfile` created
- [ ] Code pushed to GitHub
- [ ] Railway account created (login with GitHub)
- [ ] Railway project created from GitHub repo, root directory set to `backend/`
- [ ] `FIREBASE_SERVICE_ACCOUNT_JSON` environment variable set on Railway
- [ ] Railway domain noted (e.g. `agos-backend-production.up.railway.app`)
- [ ] `api_config.dart` updated with Railway domain and `_useProduction = true`
- [ ] Firebase Hosting initialized (`firebase init hosting` in `agos_app/`)
- [ ] Firebase Hosting authorized domain added (e.g. `agos-prod.web.app`) in Firebase Console → Auth → Sign-in method

### Android distribution
- [ ] Flutter release APK built: `flutter build apk --release`
- [ ] APK installed via ADB or transferred manually to device
- [ ] Backend health check verified: `https://your-app.up.railway.app/`

### Web + iOS PWA distribution
- [ ] Flutter web built: `flutter build web --release`
- [ ] Deployed to Firebase Hosting: `firebase deploy --only hosting`
- [ ] Web URL works in browser: `https://agos-prod.web.app`
- [ ] iOS users: open URL in Safari → Share ⌘ → "Add to Home Screen" → launches full-screen

### For each ESP32 device
- [ ] WiFi credentials configured in firmware
- [ ] WebSocket URL updated to Railway WSS address
- [ ] Pump relay wired and tested
- [ ] All sensors (turbidity, pH, TDS, flow, level) calibrated
- [ ] Device registered via `POST /devices/register`
