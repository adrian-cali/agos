# AGOS ESP32 Hardware Protocol Specification

> **Purpose:** This document is the complete technical spec for the AGOS ESP32 firmware.  
> Hand this to any developer (human or AI) to write firmware for ANY language or framework  
> (Arduino C++, ESP-IDF, MicroPython, Rust, etc.).

---

## 1. Device Identity

- The ESP32 device ID is derived from its MAC address:  
  `agos-` + last 8 hex characters of the MAC (uppercase), e.g. `agos-A1B2C3D4`
- This same ID is used in BLE advertising, WebSocket messages, and Firestore.

---

## 2. Phase 1 — BLE Provisioning (first boot only)

On first boot (no saved WiFi credentials), the ESP32 enters BLE provisioning mode.

### BLE Advertising
- Device name: `AGOS-A1B2C3D4` (derived from MAC, same suffix as device ID)
- One GATT service with one writable characteristic.

### GATT Profile
| Field | Value |
|-------|-------|
| Service UUID | `4fafc201-1fb5-459e-8fcc-c5c9c331914b` |
| Characteristic UUID | `beb5483e-36e1-4688-b7f5-ea07361b26a8` |
| Properties | WRITE + NOTIFY |

### Provisioning Message (mobile app → ESP32)
The mobile app writes a UTF-8 JSON string to the characteristic:

```json
{
  "ssid": "YourWiFiNetwork",
  "password": "YourWiFiPassword",
  "device_id": "agos-A1B2C3D4"
}
```

### ESP32 Response
1. Parse the JSON.
2. Save `ssid`, `password`, and `device_id` to non-volatile storage (NVS / flash).
3. Optionally notify the characteristic with `{"status":"ok"}`.
4. Reboot into WiFi mode (Phase 2).

### Subsequent Boots
If NVS has valid `ssid` and `password`, skip BLE entirely and go straight to Phase 2.

### Factory Reset
Erase NVS and reboot → re-enters BLE provisioning mode.

---

## 3. Phase 2 — WiFi + WebSocket Sensor Loop

### WebSocket Connection
| Field | Value |
|-------|-------|
| Protocol | WSS (TLS WebSocket) |
| URL | `wss://agos-wchk.onrender.com/ws/sensor` |
| Reconnect on disconnect | Yes — retry every 5 seconds |

> **Note:** The server may take 30–60 seconds to wake up on first connect (free-tier cold start). The firmware must retry indefinitely.

---

## 4. Message Protocol (ESP32 ↔ Server)

All messages are UTF-8 JSON strings sent over the WebSocket.

### 4.1 Sensor Data Message (ESP32 → Server)
Send every **5 seconds**.

```json
{
  "type": "sensor_data",
  "device_id": "agos-A1B2C3D4",
  "turbidity": 85.5,
  "ph": 7.2,
  "tds": 320.0,
  "temperature": 28.5,
  "water_level": 75.0,
  "flow_rate": 2.3,
  "pump_status": false
}
```

**Field reference:**

| Field | Type | Unit | Notes |
|-------|------|------|-------|
| `type` | string | — | Always `"sensor_data"` |
| `device_id` | string | — | e.g. `"agos-A1B2C3D4"` |
| `turbidity` | float | NTU | 0–100, higher = cloudier |
| `ph` | float | pH | 0–14 |
| `tds` | float | ppm | Total Dissolved Solids |
| `temperature` | float | °C | Water temperature |
| `water_level` | float | % | 0 = empty, 100 = full |
| `flow_rate` | float | L/min | Water flow rate |
| `pump_status` | boolean | — | `true` = pump ON |

### 4.2 Heartbeat Message (ESP32 → Server)
Send every **25 seconds** to keep the connection alive.

```json
{
  "type": "heartbeat",
  "device_id": "agos-A1B2C3D4"
}
```

### 4.3 Pump Command Message (Server → ESP32)
The server sends this to control the pump remotely.

```json
{
  "type": "pump_command",
  "action": "on",
  "duration": 30
}
```

**Fields:**

| Field | Value | Notes |
|-------|-------|-------|
| `type` | `"pump_command"` | — |
| `action` | `"on"` or `"off"` | — |
| `duration` | integer (seconds) | Only relevant when `action = "on"`. Auto-turn-off after N seconds. 0 = no auto-off. |

**ESP32 behavior on receiving `pump_command`:**
- `action = "on"`, `duration = 30` → turn relay ON, start a 30-second countdown, turn relay OFF after 30 seconds.
- `action = "off"` → turn relay OFF immediately, cancel any countdown.
- The next `sensor_data` message should reflect the new `pump_status`.

---

## 5. Sensor Hardware Reference

### Recommended Components
| Sensor | Measurement | Type | Interface |
|--------|------------|------|-----------|
| Turbidity sensor | Water clarity (NTU) | Analog | ADC pin |
| pH sensor + probe | Acidity/alkalinity | Analog | ADC pin |
| TDS sensor | Dissolved solids (ppm) | Analog | ADC pin |
| DS18B20 | Water temperature | Digital | OneWire |
| HC-SR04 | Tank water level | Digital | 2x GPIO (Trigger + Echo) |
| YF-S201 (or similar) | Flow rate | Digital pulse | 1x GPIO interrupt |
| 5V relay module | Pump control | Digital | 1x GPIO output |

### Suggested GPIO Pin Map (NodeMCU 38-pin ESP32)
> These are suggestions — adjust to your PCB layout.

| Component | GPIO |
|-----------|------|
| Turbidity sensor (analog out) | GPIO 34 |
| pH sensor (analog out) | GPIO 35 |
| TDS sensor (analog out) | GPIO 32 |
| DS18B20 (data) | GPIO 4 |
| HC-SR04 Trigger | GPIO 5 |
| HC-SR04 Echo | GPIO 18 |
| Flow sensor (pulse out) | GPIO 19 |
| Relay IN (pump control) | GPIO 23 |

### Water Level Calculation (HC-SR04)
```
distance_cm = (echo_duration_us * 0.0343) / 2
water_level_percent = ((tank_height_cm - distance_cm) / tank_height_cm) * 100
```
Set `tank_height_cm` to match your tank dimensions.

### Flow Rate Calculation (YF-S201)
```
flow_rate_lpm = (pulse_count_per_second / 7.5)
// 7.5 pulses per second = 1 L/min for YF-S201
// Adjust the divisor for your specific flow sensor model
```

### TDS Temperature Compensation
```
compensation_coefficient = 1.0 + 0.02 * (temperature_c - 25.0)
compensated_voltage = raw_voltage / compensation_coefficient
tds_ppm = (133.42 * compensated_voltage^3
         - 255.86 * compensated_voltage^2
         + 857.39 * compensated_voltage) * 0.5
```

---

## 6. Server Alert Thresholds

The server will push a Firebase FCM notification to the owner's phone when these thresholds are crossed:

| Parameter | Alert condition |
|-----------|----------------|
| Turbidity | > 50 NTU |
| pH | < 6.5 or > 8.5 |
| TDS | > 500 ppm |
| Water level | < 20% |
| Device offline | WebSocket disconnects unexpectedly |

> The firmware does not need to implement threshold logic — the server handles it.

---

## 7. State Machine Summary

```
[First Boot]
     │
     ▼
[BLE: Advertise AGOS-XXXXXXXX]
     │
     │ App writes {"ssid","password","device_id"}
     ▼
[Save to NVS → Reboot]
     │
     ▼
[Connect WiFi]
     │
     │ Success
     ▼
[Connect WSS: wss://agos-wchk.onrender.com/ws/sensor]
     │
     │ ┌─────────────────────────────────┐
     │ │  Every 5s: send sensor_data     │
     │ │  Every 25s: send heartbeat      │
     │ │  On pump_command: drive relay   │
     │ └─────────────────────────────────┘
     │
     │ Disconnect / error
     ▼
[Wait 5s → Reconnect WSS]
```

---

## 8. AI Prompt Template

If you are using an AI coding assistant to write this firmware, paste the following prompt:

---

> **Prompt:**
>
> Write complete ESP32 Arduino firmware for a water quality monitoring device called AGOS.
>
> **Requirements:**
>
> 1. On first boot, advertise a BLE GATT server:
>    - Device name: `AGOS-` + last 8 hex chars of MAC address
>    - Service UUID: `4fafc201-1fb5-459e-8fcc-c5c9c331914b`
>    - Characteristic UUID: `beb5483e-36e1-4688-b7f5-ea07361b26a8` (WRITE + NOTIFY)
>    - Wait for a JSON write: `{"ssid":"...","password":"...","device_id":"agos-XXXXXXXX"}`
>    - Save credentials to NVS (Preferences library) and reboot.
>
> 2. On subsequent boots, connect to saved WiFi, then open a secure WebSocket to:
>    `wss://agos-wchk.onrender.com/ws/sensor`
>
> 3. Every 5 seconds, send:
>    ```json
>    {"type":"sensor_data","device_id":"agos-XXXXXXXX","turbidity":0.0,"ph":0.0,"tds":0.0,"temperature":0.0,"water_level":0.0,"flow_rate":0.0,"pump_status":false}
>    ```
>
> 4. Every 25 seconds, send:
>    ```json
>    {"type":"heartbeat","device_id":"agos-XXXXXXXX"}
>    ```
>
> 5. Handle incoming pump_command:
>    ```json
>    {"type":"pump_command","action":"on","duration":30}
>    ```
>    Turn GPIO relay on for `duration` seconds then off. If `action` is `"off"`, turn off immediately.
>
> 6. Sensors:
>    - Turbidity: analog on GPIO 34
>    - pH: analog on GPIO 35
>    - TDS: analog on GPIO 32 (apply temperature compensation)
>    - Temperature: DS18B20 OneWire on GPIO 4
>    - Water level: HC-SR04 Trigger=GPIO5, Echo=GPIO18 (output as percent of a 100cm tank)
>    - Flow rate: YF-S201 pulse interrupt on GPIO 19 (output L/min)
>    - Pump relay: GPIO 23 (HIGH = ON)
>
> 7. Auto-reconnect WebSocket on disconnect. Retry every 5 seconds.
>
> Use ArduinoJson ≥7, WebSockets by Markus Sattler ≥2.4, OneWire, DallasTemperature libraries.  
For BLE, use the built-in BLE library from the ESP32 Arduino core (do NOT install "ESP32 BLE Arduino" from Library Manager — it conflicts with core 3.x).  
For MAC address, use `WiFi.macAddress()` (string format "AA:BB:CC:DD:EE:FF"), do NOT use `esp_read_mac()`.

---

*End of AGOS Hardware Protocol Specification*
