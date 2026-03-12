# AGOS Phase 19 — LCD + UV Light + Bypass Pump Plan

## Overview

This phase adds three new hardware components to the AGOS ESP32 greywater system:

| # | Component | Purpose |
|---|-----------|---------|
| 1 | 16x2 LCD I2C Display | Show real-time water quality and status on the device |
| 2 | UV Relay (SLA-05VDC-SL-C) | Control a UV sterilizer lamp in the holding tank |
| 3 | Bypass Pump Relay (SLA-05VDC-SL-C) | Run a second pump from the waste water tank directly to the filter (skipping the equalizer) on a user-set daily schedule |

**Rule:** No existing pins or wiring are changed. All new components use new GPIO pins.

---

## New GPIO Allocations

| Component | GPIO | Direction | Notes |
|-----------|------|-----------|-------|
| LCD SDA | GPIO21 | Output / I2C | ESP32 default I2C SDA |
| LCD SCL | GPIO22 | Output / I2C | ESP32 default I2C SCL |
| UV Relay IN | GPIO27 | Output | Default ON at boot (NC terminal wiring) |
| Bypass Pump Relay IN | GPIO25 | Output | Schedule-triggered (NC terminal wiring) |

### Existing Pins (Unchanged)

| Sensor / Device | GPIO |
|-----------------|------|
| Turbidity SEN0189 | GPIO34 |
| pH-4502C | GPIO35 |
| TDS Meter V1.0 | GPIO32 |
| JSN-SR04T TRIG | GPIO5 |
| JSN-SR04T ECHO | GPIO18 |
| Main Pump Relay | GPIO26 |

---

## Wiring Diagrams

### 1. 16x2 LCD I2C Module

```
ESP32 NodeMCU (38-pin)
                                    ┌──────────────────────┐
                                    │  LCD 16x2 I2C Module │
5V Rail (Breadboard) ───────────────┤ VCC                  │
GND Rail (Breadboard) ──────────────┤ GND                  │
GPIO21 (SDA) ───────────────────────┤ SDA                  │
GPIO22 (SCL) ───────────────────────┤ SCL                  │
                                    └──────────────────────┘
```

**Notes:**
- I2C address: `0x27` (default). Try `0x3F` if screen stays blank.
- The I2C module has a small blue potentiometer on the back — turn it to adjust contrast until text appears.
- Library: `LiquidCrystal_I2C` by Frank de Brabander (install via Arduino Library Manager)
- Power: from the **5V breadboard rail**, same supply as the rest of the system

---

### 2. UV Light Relay (SLA-05VDC-SL-C)

**UV lamp model: Sunsun UV-C 6W**
- Powered by **AC 220-240V** (built-in ballast, mains powered)
- Relay contacts rated: 10A 250VAC — sufficient to switch this load

```
ESP32 NodeMCU (38-pin)
                                    ┌────────────────────────────────┐
                                    │  Relay Module SLA-05VDC-SL-C   │
5V Rail (Breadboard) ───────────────┤ VCC                            │
GND Rail (Breadboard) ──────────────┤ GND                            │
GPIO27 ─────────────────────────────┤ IN                             │
                                    │                                │
                                    │  [COM] ──── UV lamp HOT wire   │
                                    │  [NC]  ──── UV lamp HOT wire   │
                                    │  [NO]  ──── (not connected)    │
                                    └────────────────────────────────┘

UV Lamp (Sunsun UV-C 6W, AC 220-240V):
  AC outlet LIVE  ──── Relay COM
  Relay NC ────────── UV lamp LIVE terminal
  AC outlet NEUTRAL ─────────────────────── UV lamp NEUTRAL terminal

  ⚠ HIGH VOLTAGE: The relay switches a 220V AC live wire.
    Keep AC wiring separated from the 5V breadboard.
    Use heat-shrink or insulating tape on all AC terminals.
```

**Wiring notes:**
- The relay switches the **LIVE (hot) wire** of the UV lamp power cord.
- Wire to the **NC (Normally Closed) terminal**: UV lamp is ON when relay is de-energized.
- This ensures UV sterilization runs even if ESP32 resets or hasn't booted yet.
- Relay coil is powered from the 5V breadboard rail (signal side only).
- `RELAY_UV_ACTIVE_HIGH = true` — signal HIGH = relay de-energized = NC closed = UV lamp ON.
- Confirmed boot behavior: **UV ON at boot, user can turn OFF from app.**

---

### 3. Bypass Pump Relay (SLA-05VDC-SL-C)

**Bypass pump model: DH-3500 Submersible Pump**
- AC 220-240V, 50Hz, 60W, Hmax: 3.5m, Qmax: 3500 L/H
- Same type as the main holding tank pump
- Relay contacts rated: 10A 250VAC — sufficient

```
ESP32 NodeMCU (38-pin)
                                    ┌────────────────────────────────┐
                                    │  Relay Module SLA-05VDC-SL-C   │
5V Rail (Breadboard) ───────────────┤ VCC                            │
GND Rail (Breadboard) ──────────────┤ GND                            │
GPIO25 ─────────────────────────────┤ IN                             │
                                    │                                │
                                    │  [COM] ──── Bypass pump LIVE   │
                                    │  [NO]  ──── Bypass pump LIVE   │
                                    │  [NC]  ──── (not connected)    │
                                    └────────────────────────────────┘

Bypass Pump (DH-3500, AC 220-240V):
  AC outlet LIVE  ──── Relay COM
  Relay NO ────────── Bypass pump LIVE terminal
  AC outlet NEUTRAL ─────────────────────────── Bypass pump NEUTRAL terminal

  ⚠ HIGH VOLTAGE: Same AC switching as UV relay.
    Keep AC wiring separated from the 5V breadboard.
```

**Wiring notes:**
- Wire to the **NO (Normally Open) terminal**: pump is OFF when relay is de-energized.
- This ensures the bypass pump does **not** accidentally run at boot.
- `RELAY_BYPASS_ACTIVE_HIGH = false` — signal LOW = relay energized = NO closes = bypass pump ON.
- Relay coil is powered from the 5V breadboard rail.
- Confirmed boot behavior: **Bypass pump OFF at boot, only runs on schedule or manual trigger.**

---

### Full System Wiring Summary (All Components)

```
┌─────────────────────────────────────────────────────────────────────┐
│                          5V Breadboard Rail                         │
│  USB or 5V/3A Adapter (+) ──────────────────────────────────────── │
└───┬──────────┬──────────┬──────────┬──────────┬──────────┬─────────┘
    │          │          │          │          │          │
  LCD VCC    UV Relay    Bypass     Main       [other     [ESP32
  (21,22)    VCC(27)     Relay      Pump       sensors]    VIN]
                         VCC(25)    VCC(26)

┌─────────────────────────────────────────────────────────────────────┐
│                           GND Breadboard Rail                       │
└─────────────────────────────────────────────────────────────────────┘

ESP32 Pins:
  GPIO21 ──── LCD SDA
  GPIO22 ──── LCD SCL
  GPIO27 ──── UV Relay IN      (NC wiring → UV ON by default)
  GPIO25 ──── Bypass Pump IN   (NO wiring → Bypass pump OFF by default)
  GPIO26 ──── Main Pump IN     (NC wiring → Main pump ON by default)  [EXISTING]
  GPIO34 ──── Turbidity ADC    [EXISTING]
  GPIO35 ──── pH ADC           [EXISTING]
  GPIO32 ──── TDS ADC          [EXISTING]
  GPIO5  ──── JSN-SR04T TRIG   [EXISTING]
  GPIO18 ──── JSN-SR04T ECHO   [EXISTING]
```

---

## LCD Display Plan

### Libraries Required
- `LiquidCrystal_I2C` (Frank de Brabander) — install in Arduino Library Manager

### Display Layout

```
┌────────────────┐
│ OPERATIONAL    │   ← Row 1: System status (static, 16 chars)
│ Lv:84% pH:7.27 │   ← Row 2: Scrolling ticker (right-to-left)
└────────────────┘
```

**Row 1 — Status (static):**

| State | Text |
|-------|------|
| Water is within thresholds | `OPERATIONAL    ` |
| Main pump is running | `FILTERING...   ` |
| Bypass pump is running | `BYPASSING...   ` |
| UV lamp OFF | `UV LAMP OFF    ` |
| WS connected | `CONNECTED       ` (briefly on connect) |

**Row 2 — Scrolling Ticker:**
- Content: `Lv:84%  pH:7.27  Turb:0.00NTU  TDS:9ppm  `
- Scrolls continuously from right to left (like a marquee)
- Updates values every sensor read cycle
- `Level` always appears first in the scroll string

---

## UV Light Feature Plan

### Behavior
- UV lamp is **ON by default** at boot
- `RELAY_UV_ACTIVE_HIGH = true` with **NC wiring** ensures UV is ON even if ESP32 hasn't booted yet
- State saved to **NVS flash** — survives power cycles
- User can toggle ON/OFF from Flutter app at any time
- UV state is included in `state_snapshot` so app always loads the current state

### New Messages (ESP32 ↔ Backend ↔ App)

| Direction | Message Type | Payload |
|-----------|-------------|---------|
| App → Backend | `uv_command` | `{"action": "on" \| "off"}` |
| Backend → ESP32 | `uv_command` | `{"action": "on" \| "off"}` |
| ESP32 → Backend | sensor data update | includes `"uv_on": true \| false` |
| Backend → App | `uv_update` | `{"uv_on": true \| false}` |

### Flutter UI — UV Card
- Card on Home Screen: "UV Sterilizer"
- Toggle switch: ON / OFF
- Shows current state (reads from `uvStateProvider`)
- State is preserved across navigation (same pattern as `pumpStateProvider`)

---

## Bypass Pump Feature Plan

### Water Flow Context

```
Normal flow:
  Waste Water Tank ──→ Equalizer ──→ Filter ──→ Holding Tank

Bypass flow (scheduled):
  Waste Water Tank ──→ (skip Equalizer) ──→ Filter ──→ Holding Tank
```

The bypass pump moves water directly from the waste tank to the filter, skipping the equalizer. This is triggered once per day at a user-set time, or manually.

### Behavior
- User sets a **daily trigger time** in the app (e.g., "02:00 AM")
- User sets a **run duration** — **default: 30 minutes**, user-configurable from app (range: 1–120 min)
- ESP32 syncs time via **NTP** after WiFi connects
- At the scheduled time:
  1. Backend sends `bypass_command: on` to ESP32 with `duration_seconds`
  2. ESP32 activates GPIO25 for the set duration
  3. After duration, ESP32 stops relay and notifies backend
- If backend is unreachable, ESP32 has NTP-based local time and runs bypass independently
- Last bypass time displayed in app card
- **Pump specs**: DH-3500, AC 220-240V 60W, Qmax 3500 L/H

### New Messages

| Direction | Message Type | Payload |
|-----------|-------------|---------|
| App → Backend | `bypass_schedule` | `{"hour": 2, "minute": 0, "duration_minutes": 30}` |
| Backend → ESP32 | `bypass_command` | `{"action": "on", "duration_seconds": 1800}` |
| ESP32 → Backend | sensor data update | includes `"bypass_pump_on": true \| false` |
| Backend → App | `bypass_update` | `{"bypass_pump_on": true, "last_run": "2025-01-01T02:00:00"}` |

### Flutter UI — Bypass Schedule Card
- Card on Home Screen: "Bypass Schedule"
- Time picker for daily trigger time
- Duration picker (minutes)
- Shows: last bypass time, next scheduled bypass
- "Run Now" manual trigger button

### NVS Storage on ESP32
- Key `bypass_hour` — stored hour (0–23)
- Key `bypass_min` — stored minute (0–59)
- Key `bypass_dur_sec` — stored duration in seconds
- Key `uv_on` — UV lamp state (bool, 1 or 0)

---

## Firmware (`.ino`) Changes Summary

| Addition | Code Change |
|----------|------------|
| LCD | `#include <LiquidCrystal_I2C.h>`, `setup()` init, `updateLcd()` ticker + status |
| UV relay | New pin define, `setUvRelay()`, NVS load/save, handle `uv_command` in `onWsText()` |
| Bypass relay | New pin define, `setBypassRelay()`, NVS scheduling, NTP `configTime()`, `checkBypassSchedule()` in loop |

**New pin defines:**
```cpp
#define PIN_LCD_SDA    21
#define PIN_LCD_SCL    22
#define PIN_UV_RELAY   27
#define PIN_BYPASS_RELAY 25
const bool RELAY_UV_ACTIVE_HIGH     = true;   // NC wiring
const bool RELAY_BYPASS_ACTIVE_HIGH = false;  // NO wiring
```

---

## Backend (`main.py`) Changes Summary

| Addition | Code Change |
|----------|------------|
| UV state | `state["uv"]["on"] = True` (default), handle `uv_command`, broadcast `uv_update` |
| Bypass state | `state["bypass"]["pump_on"] = False`, `bypass_schedule` storage, `bypass_command` on schedule, `bypass_update` broadcast |
| Scheduler | FastAPI `BackgroundTask` or `asyncio` periodic task checking bypass schedule daily |

---

## Flutter App Changes Summary

| File | Change |
|------|--------|
| `home_screen.dart` | Add UV card + Bypass Schedule card |
| `providers/uv_state_provider.dart` | New Riverpod `StateNotifierProvider` |
| `providers/bypass_state_provider.dart` | New Riverpod `StateNotifierProvider` |
| `websocket_service.dart` | Handle `uv_update`, `bypass_update` message types |

---

## Implementation Phases

### Phase 19a — LCD Display
1. Add `LiquidCrystal_I2C` to firmware
2. Wire LCD to GPIO21/22
3. Implement `updateLcd()` with scrolling Row 2 and dynamic Row 1

### Phase 19b — UV Relay
1. Wire UV relay to GPIO27 (NC terminal)
2. Add UV relay logic to firmware (NVS, `uv_command` handler)
3. Add `uv_on` field to backend state
4. Add UV card to Flutter home screen

### Phase 19c — Bypass Pump
1. Wire bypass pump relay to GPIO25 (NO terminal)
2. Add NTP time sync to firmware
3. Add bypass schedule logic to firmware
4. Add `bypass_command` and schedule storage to backend
5. Add Bypass Schedule card to Flutter home screen

---

## Confirmed Specs

| Item | Confirmed Value |
|------|----------------|
| UV lamp | Sunsun UV-C 6W, AC 220-240V (relay switches LIVE wire) |
| Bypass pump | DH-3500, AC 220-240V 50Hz 60W, Qmax 3500 L/H |
| Bypass duration default | 30 minutes (user-configurable, range 1–120 min) |
| UV boot behavior | UV ON at boot (NC wiring), user can turn OFF from app |
| Bypass pump boot behavior | OFF at boot (NO wiring), only via schedule or manual trigger |
| Relay rating | SLA-05VDC-SL-C: 10A 250VAC contacts — sufficient for both loads |
