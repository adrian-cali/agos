# Device Setup Flow — Redesign Plan

**Status:** Planning (not yet implemented)  
**Author:** GitHub Copilot  
**Date:** 2025

---

## 1. Problem Statement

The current `/connection-method` screen asks the user to choose between:
- **WiFi Connection** → goes to `/wifi-setup` (direct WiFi provisioning)
- **Bluetooth Connection** → goes to `/bluetooth-setup-1` (BLE provisioning)

**This is wrong.** The AGOS system only supports one real provisioning path:
1. Connect to the ESP32 via **Bluetooth** (BLE)
2. Send WiFi credentials to the ESP32 through that Bluetooth connection
3. The ESP32 then connects to WiFi autonomously

Giving users a "WiFi only" option implies the phone can set up the ESP32 without Bluetooth — which is not how the system works. The `/wifi-setup` screen in that path also uses `BleProvisioningService`, so it's already broken as a standalone WiFi-only path.

Furthermore, all setup screens currently show `value: 0.25` in the progress bar — meaning progress never changes until `/device-information` (0.75). This makes the progress bar feel broken.

---

## 2. Proposed New Flow

### Before (Current):
```
/ (Splash)
  └── /welcome
        ├── /login
        └── /register
              └── /connection-method  ⚠️ (misleading choice between WiFi and BT)
                    ├── /wifi-setup           ← broken: implies no BT needed
                    └── /bluetooth-setup-1
                          └── /bluetooth-setup-2
                                └── /ready-to-scan
                                      └── /wifi-setup  ← correct BT path
                                            └── /pairing-device
                                                  └── /device-information
                                                        └── /setup-complete
                                                              └── /home
```

### After (Proposed):
```
/ (Splash)
  └── /welcome
        ├── /login
        └── /register
              └── /device-setup-intro  ✨ NEW — replaces /connection-method
                    └── /bluetooth-setup-1
                          └── /bluetooth-setup-2
                                └── /ready-to-scan
                                      └── /wifi-setup
                                            └── /pairing-device
                                                  └── /device-information
                                                        └── /setup-complete
                                                              └── /home
```

---

## 3. Changes Required

### 3.1 Remove the WiFi-only path

The standalone `/wifi-setup` entry point from `/connection-method` will be removed. WiFi setup is now only accessible after a successful BLE connection (`/ready-to-scan` → `/wifi-setup`).

### 3.2 Replace `/connection-method` with `/device-setup-intro`

**New screen: `DeviceSetupIntroScreen`**
- File: `lib/presentation/screens/connection/device_setup_intro_screen.dart`
- Route: `/device-setup-intro`

**Purpose:** Explain to the user *how* the setup works before entering the technical steps. No choices — just one "Start Setup" button.

**UI Design (wireframe):**

```
┌─────────────────────────────────────┐
│  ░░░░░░░░░ Progress Bar (0%) ░░░░░  │
│  Setting up your AGOS system...     │
├─────────────────────────────────────┤
│                                     │
│  [BT icon]  AGOS Device Setup       │
│  Connect and configure your AGOS    │
│  water monitoring system.           │
│                                     │
│  ┌───────────────────────────────┐  │
│  │  How setup works:             │  │
│  │                               │  │
│  │  ① [purple] Enable Bluetooth  │  │
│  │     Allow the app to scan     │  │
│  │     nearby devices            │  │
│  │                               │  │
│  │  ② [blue]  Find Your Device   │  │
│  │     Select your AGOS hardware │  │
│  │     from the scan results     │  │
│  │                               │  │
│  │  ③ [green] Configure WiFi     │  │
│  │     Enter your home WiFi so   │  │
│  │     the device connects auto  │  │
│  └───────────────────────────────┘  │
│                                     │
│  [    Start Setup    ]  ← gradient  │
│  [        Back       ]  ← outlined  │
└─────────────────────────────────────┘
```

**Color palette:** Reuses existing `ConnectionMethodDesign` constants (gradient, card containers, fonts).

**Step icon gradient colors:**
- Step 1 (Bluetooth): Purple → Pink (`#C27AFF` → `#E60076`)
- Step 2 (Scan/Connect): Blue gradient (`#1447E6` → `#0092B8`)
- Step 3 (WiFi): Green gradient (`#00B894` → `#00CEC9`)

**Also:** Move the **Simulation Mode toggle** from `bluetooth_setup1_screen.dart` to this intro screen — it's more logical to enable simulation at the start of the flow.

---

### 3.3 Update Router

**File:** `lib/core/router/app_router.dart`

```dart
// REMOVE:
case '/connection-method':
  return _buildRouteNoTransition(const ConnectionMethodScreen());

// ADD:
case '/device-setup-intro':
  return _buildRouteNoTransition(const DeviceSetupIntroScreen());
```

Also remove the `ConnectionMethodScreen` import and add the `DeviceSetupIntroScreen` import.

---

### 3.4 Update Navigation Targets

Every place that navigates to `/connection-method` must be changed to `/device-setup-intro`:

| File | Location | Change |
|------|----------|--------|
| `login_screen.dart` | After successful login (first-time user path) | `/connection-method` → `/device-setup-intro` |
| `register_screen.dart` | After successful register | `/connection-method` → `/device-setup-intro` |
| `welcome_screen.dart` | "Get Started" button (if linked to connection method) | Same |
| `home_screen.dart` | "Add Device" button | Same |
| `device_management_screen.dart` | "Add New Device" button | Same |

> **Note:** Currently `main.dart` redirects authenticated users directly to `/home`. First-time device setup is entered from the home or device management screen. The intro screen is the new entry for both.

---

### 3.5 Keep `/wifi-setup` Route — Restrict Access

The `/wifi-setup` route stays in the router (needed after BLE scanning). It is no longer an option from the intro screen.

Valid path: `/ready-to-scan` → (after BLE connect) → `/wifi-setup`

---

### 3.6 Update Progress Bar Values (see Section 8)

After removing `/connection-method` and adding `/device-setup-intro`, all progress bar `value:` constants must be recalculated to reflect 7 real steps.

---

## 4. Files Affected

| File | Action |
|------|--------|
| `lib/presentation/screens/connection/connection_method_screen.dart` | **ORPHAN** — keep but stop routing to it (safe to delete later) |
| `lib/presentation/screens/connection/device_setup_intro_screen.dart` | **CREATE** — new screen |
| `lib/core/router/app_router.dart` | **UPDATE** — add `/device-setup-intro`, keep `/connection-method` as dead route |
| `lib/presentation/screens/auth/login_screen.dart` | **CHECK/UPDATE** — navigation target |
| `lib/presentation/screens/auth/register_screen.dart` | **CHECK/UPDATE** — navigation target |
| `lib/presentation/screens/welcome/welcome_screen.dart` | **CHECK/UPDATE** — navigation target |
| `lib/presentation/screens/device/device_management_screen.dart` | **CHECK/UPDATE** — navigation target |
| `lib/presentation/screens/connection/bluetooth_setup1_screen.dart` | **UPDATE** — remove simulation toggle (moved to intro screen) + update progress value |
| `lib/presentation/screens/connection/bluetooth_setup2_screen.dart` | **UPDATE** — progress bar value only |
| `lib/presentation/screens/pairing/ready_to_scan_bluetooth_screen.dart` | **UPDATE** — progress bar value only |
| `lib/presentation/screens/connection/wifi_setup_screen.dart` | **UPDATE** — progress bar value only |
| `lib/presentation/screens/pairing/pairing_device_screen.dart` | **UPDATE** — progress bar value only |
| `lib/presentation/screens/pairing/device_information_screen.dart` | **UPDATE** — progress bar value only |
| `lib/presentation/screens/pairing/setup_complete_screen.dart` | **NO CHANGE** — already at `1.0` |

---

## 5. Implementation Order

1. **Create** `device_setup_intro_screen.dart` with the 3-step explainer UI
2. **Update** `app_router.dart` — add `/device-setup-intro` route
3. **Update** all navigation targets that point to `/connection-method`
4. **Move** Simulation Mode toggle from `bluetooth_setup1_screen.dart` to the new intro screen
5. **Update** all 6 progress bar values across the setup screens (see table in Section 8)
6. **Test** full simulation mode flow end-to-end

---

## 6. What Stays the Same (No Code Changes)

These screens are **not being redesigned** in this plan:
- `/bluetooth-setup-1` — Enable Bluetooth (progress bar update only)
- `/bluetooth-setup-2` — Grant Permissions (progress bar update only)
- `/ready-to-scan` — BLE Scan + Device List (progress bar update only)
- `/wifi-setup` — WiFi Scan + Credentials (progress bar update only)
- `/pairing-device` — Pairing animation (progress bar update only)
- `/device-information` — Device name/location form (progress bar update only)
- `/setup-complete` — Completion screen (no change at all)

---

## 7. Open Questions (Confirm Before Implementation)

1. **Where does setup flow start?** After login for first-time users only, OR also from Settings → "Add Device"?
2. **Should `/connection-method` be deleted** or just orphaned?
   - Recommendation: Keep file, stop routing to it — delete in a later cleanup.
3. **Back button destination** on the new intro screen — go to `/welcome` or `/login`?
   - Recommendation: `/welcome` (same as current `/connection-method` behavior).
4. **Should the "Back" button on `/bluetooth-setup-1`** after removing sim toggle still go to `/device-setup-intro`?

---

## 8. Progress Bar Values — Current vs Proposed

The **top progress bar** (`LinearProgressIndicator`, value 0.0–1.0) appears on every screen in the setup flow. Currently, the values are inconsistent — most screens stuck at `0.25`. With a clean 7-step flow, progress should advance meaningfully on every screen.

### New Setup Flow — 7 Steps

| # | Screen | Route | Progress Value |
|---|--------|-------|----------------|
| 0 | Device Setup Intro *(new)* | `/device-setup-intro` | `0.00` |
| 1 | Enable Bluetooth | `/bluetooth-setup-1` | `0.14` (1/7) |
| 2 | Grant Permissions | `/bluetooth-setup-2` | `0.29` (2/7) |
| 3 | Scan & Connect | `/ready-to-scan` | `0.43` (3/7) |
| 4 | WiFi Credentials | `/wifi-setup` | `0.57` (4/7) |
| 5 | Pairing | `/pairing-device` | `0.71` (5/7) |
| 6 | Device Info | `/device-information` | `0.86` (6/7) |
| 7 | Setup Complete | `/setup-complete` | `1.00` ✓ |

### Current Values vs Proposed

| File | Current `value:` | Proposed `value:` | Change? |
|------|-----------------|-------------------|---------|
| `connection_method_screen.dart` | `0.25` | *(removed from flow)* | N/A |
| `device_setup_intro_screen.dart` | *(new)* | `0.00` | NEW |
| `bluetooth_setup1_screen.dart` | `0.25` | `0.14` | ✏️ Update |
| `bluetooth_setup2_screen.dart` | `0.25` | `0.29` | ✏️ Update |
| `ready_to_scan_bluetooth_screen.dart` | `0.25` | `0.43` | ✏️ Update |
| `wifi_setup_screen.dart` | `0.25` | `0.57` | ✏️ Update |
| `pairing_device_screen.dart` | `0.50` | `0.71` | ✏️ Update |
| `device_information_screen.dart` | `0.75` | `0.86` | ✏️ Update |
| `setup_complete_screen.dart` | `1.00` | `1.00` | ✅ No change |

> **Note:** `ready_to_pair_screen.dart` (lines 232 and 601) has two progress bars for the WiFi-only path. Since that path is being removed, it becomes an unused/dead screen.

### Number of Changes for Progress Bars Only
- **6** existing `value:` constants to update
- **1** new `value:` to set (intro screen at `0.00`)
- **1** screen unchanged (`setup_complete` at `1.00`)
