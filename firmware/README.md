# AGOS ESP32 Firmware

Arduino sketch for the AGOS Water Monitoring System hardware.

## Libraries to install (Arduino Library Manager)

| Library | Author | Version |
|---|---|---|
| `ArduinoJson` | Benoit Blanchon | >= 7.x |
| `WebSockets` | Markus Sattler | >= 2.4 |
| `OneWire` | Paul Stoffregen | >= 2.3 |
| `DallasTemperature` | Miles Burton | >= 3.9 |

> **IMPORTANT — BLE:** Do **NOT** install "ESP32 BLE Arduino" from Arduino Library Manager.  
> It conflicts with ESP32 core 3.x. BLE (`BLEDevice.h`, `BLEServer.h`, etc.) is already  
> built into the ESP32 Arduino core — just install the board support and the BLE headers  
> will be available automatically.

## Board Setup (Arduino IDE)
- Board: **ESP32 Dev Module**
- Partition Scheme: **Default 4MB with spiffs** (or any scheme with BLE enabled)
- CPU Frequency: 240 MHz
- Flash Mode: DIO

## Pin Map

| GPIO | Connection |
|---|---|
| 34 | Turbidity sensor (analog out) |
| 35 | pH probe board (analog out) |
| 32 | TDS/EC sensor (analog out) |
| 5  | HC-SR04 Trigger |
| 18 | HC-SR04 Echo |
| 4  | DS18B20 Temperature (OneWire) |
| 26 | Pump relay (HIGH = ON) |
| 27 | Flow sensor (Hall pulse interrupt) |

## First-time Setup Flow

1. Flash the firmware to the ESP32.
2. Open the AGOS app on Android → **Device Setup**.
3. The app scans for BLE devices — select the one named `AGOS-xxxxxxxx`.
4. Enter your WiFi SSID + password → **Send** (app automatically includes device_id).
5. The ESP32 stores the credentials in NVS flash and reboots into WebSocket mode.
6. From now on the ESP32 connects to WiFi automatically on power-up (no BLE needed).

## Resetting WiFi credentials

Power-cycle while holding **BOOT** button (GPIO0) → add a check in `setup()` to wipe NVS:
```cpp
if (digitalRead(0) == LOW) {
  prefs.begin("agos", false);
  prefs.clear();
  prefs.end();
  Serial.println("Credentials cleared — restarting in BLE mode");
  ESP.restart();
}
```

## Sensor Calibration Notes

- **Turbidity**: Uses a polynomial approximation. Calibrate by measuring NTU values against a reference standard and adjusting the coefficients in `readTurbidity()`.
- **pH**: Uses the midpoint voltage (pH 7 = 1.65 V typical). Calibrate with pH buffer solutions and adjust `PH_V_OFFSET` and `PH_V_PER_PH` in `agos_esp32.ino`.
- **TDS**: Uses the standard DFRobot formula. Calibrate with a 1382 ppm standard solution if needed.
- **Tank Level**: Set `TANK_HEIGHT_CM` to the distance from the ultrasonic sensor down to the floor of the empty tank. Set `TANK_CAPACITY_L` to the tank's full volume in litres.

## WebSocket Protocol

### Sent → backend (every 5 seconds)
```json
{
  "type": "sensor_data",
  "device_id": "agos-zksl9QK3",
  "level": 68.5,
  "volume": 34250.0,
  "capacity": 50000,
  "flow_rate": 145.0,
  "turbidity": 28.4,
  "ph": 7.2,
  "tds": 380.0,
  "temperature": 25.1,
  "pump_active": false
}
```

### Received ← backend (pump command)
```json
{
  "type": "pump_command",
  "action": "on",
  "duration_seconds": 60
}
```
Turn the relay on for 60 seconds, then auto-off. If `action = "off"` turn off immediately.
