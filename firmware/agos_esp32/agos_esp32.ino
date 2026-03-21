/**
 * AGOS Water Monitoring System — ESP32 Firmware
 *
 * Phase 1 — BLE Provisioning:
 *   Advertises as "AGOS-<HEX_ID>" and exposes a BLE characteristic the app
 *   writes WiFi credentials + device_id to.
 *
 * Phase 2 — WebSocket Sensor Loop:
 *   After WiFi connects, opens a secure WebSocket to the backend and sends
 *   sensor_data JSON every SEND_INTERVAL_MS milliseconds.
 *   Listens for pump_command messages and drives a relay accordingly.
 *
 * ─── Required Libraries (install via Arduino Library Manager) ────────────────
 *   ArduinoJson  >= 7.x  (Benoit Blanchon)
 *   WebSockets   >= 2.4  (Markus Sattler) → "WebSockets" by Markus Sattler
 *   BLEDevice    bundled in ESP32 Arduino core — do NOT install external "ESP32 BLE Arduino"
 * ─────────────────────────────────────────────────────────────────────────────
 *
 * ─── Board Setup ─────────────────────────────────────────────────────────────
 *   Board : ESP32 Dev Module  (or NodeMCU-32S)
 *   Partition scheme : Default (or any that has BLE enabled)
 *
 * ─── Pin Map ─────────────────────────────────────────────────────────────────
 *   GPIO34  Analog in  — DFRobot Turbidity Sensor V1.0 (SEN0189, 5 V powered)
 *                        Voltage divider on output: SIG → 10 kΩ → GPIO34 → 20 kΩ → GND
 *   GPIO35  Analog in  — PH-4502C PO pin (5 V module; output ≤ 3.3 V for pH > 5.5)
 *   GPIO32  Analog in  — DFRobot TDS Meter V1.0 A pin (3.3 V powered, direct)
 *   GPIO5   Digital out — JSN-SR04T V3.0 TRIG (3.3 V signal accepted by sensor)
 *   GPIO18  Digital in  — JSN-SR04T V3.0 ECHO (5 V signal → divider: ECHO → 1 kΩ → GPIO18 → 2 kΩ → GND)
 *   GPIO26  Digital out — Relay module IN (HIGH = relay de-energised, NC-COM closed = pump ON)
 * ─────────────────────────────────────────────────────────────────────────────
 */
#include <Arduino.h>
#include <WiFi.h>
#include <Wire.h>
#include <esp_mac.h>          // esp_read_mac() for ESP32 core 3.x
#include <Preferences.h>
// BLE — use the built-in library from ESP32 Arduino core (do NOT install
// the separate "ESP32 BLE Arduino" library from Arduino Library Manager;
// that older library conflicts with ESP32 core 3.x).
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <esp_bt.h>          // esp_bt_controller_mem_release() for deep BLE heap reclaim
#include <ArduinoJson.h>
#include <WebSocketsClient.h>
#include <LiquidCrystal_I2C.h>
#include <time.h>

// ════════════════════════════════════════════════════════════════════════════
// Configuration — edit these to match your install
// ════════════════════════════════════════════════════════════════════════════

// Backend WebSocket (must match ApiConfig.wsSensorUrl)
const char* WS_HOST       = "agos-wchk.onrender.com";
const int   WS_PORT       = 443;      // 443 for wss://, 80 for ws://
const char* WS_PATH       = "/ws/sensor";
const bool  WS_USE_SSL    = true;

// Tank geometry — adjust to match your physical tank
const float TANK_HEIGHT_CM   = 200.0f;  // cm from sensor to tank floor
const float TANK_CAPACITY_L  = 50000.0f; // litres (50 m³)

// Sensor calibration
// PH-4502C: calibrate PH_V_OFFSET by dipping probe in pH-7 buffer and adjusting the trim pot.
// Standard PH-4502C outputs ~2.5 V at pH 7 (trim pot centred). If your reading at pH 7
// is off by more than ±0.3 pH, adjust the trim pot first, then update this value.
const float PH_V_OFFSET  = 2.535f;  // output voltage at pH 7 — adjusted from field logs
const float PH_V_PER_PH  = 0.1786f; // V per pH unit (typical for PH-4502C)
const float TDS_VREF     = 3.3f;    // DFRobot TDS V1.0: powered at 3.3 V
// Turbidity zero-offset calibration.
// Dip the probe in clear tap water, note the NTU reading, and set this to that value.
// This zeroes the baseline so clear water reads ~0 NTU and turbid water reads positive.
const float TURB_CLEAN_NTU = 1300.0f; // NTU shown in clear water — adjust to match your unit
// Turbidity scale factor for lab-accurate NTU values.
// How to calibrate: measure a water sample with a lab turbidimeter (known NTU), submerge the
// probe in that sample, read the raw sensor NTU (before scale), then set:
//   TURB_SCALE_FACTOR = lab_NTU / sensor_raw_NTU
// Example: lab = 55 NTU, sensor raw = 1100 NTU → TURB_SCALE_FACTOR = 55.0 / 1100.0 = 0.05
const float TURB_SCALE_FACTOR = 0.05f; // tune with an actual lab-measured sample

// Offline auto-pump thresholds — used only when backend WebSocket is disconnected.
// Keep these consistent with the default settings in the Flutter app.
const float PUMP_TURB_MIN = 0.0f;    // NTU minimum (0 = any turbidity level is acceptable as low)
const float PUMP_TURB_MAX = 50.0f;   // NTU maximum
const float PUMP_PH_MIN   = 6.0f;    // pH minimum
const float PUMP_PH_MAX   = 9.5f;    // pH maximum
const float PUMP_TDS_MAX  = 1000.0f; // ppm maximum
const float TDS_TEMP_COEF = 0.02f;  // TDS temperature coefficient (2 %/°C)

// Timing
const unsigned long SEND_INTERVAL_MS = 5000;  // 5 s between readings
const unsigned long RECONN_DELAY_MS  = 5000;  // reconnect delay on WS drop

// Pin assignments
#define PIN_TURBIDITY   34   // DFRobot Turbidity V1.0 (via 10kΩ/20kΩ voltage divider)
#define PIN_PH          35   // PH-4502C PO analog output
#define PIN_TDS         32   // DFRobot TDS Meter V1.0 (3.3V powered, direct)
#define PIN_TRIG         5   // JSN-SR04T V3.0 TRIG
#define PIN_ECHO        18   // JSN-SR04T V3.0 ECHO (via 1kΩ/2kΩ voltage divider)
#define PIN_PUMP_RELAY    26   // Relay module IN pin
#define PIN_UV_RELAY      27   // UV lamp relay IN pin (NC terminal → UV ON by default)
#define PIN_BYPASS_RELAY  25   // Bypass pump relay IN pin (NO terminal → bypass OFF by default)
// LCD I2C uses hardware I2C: SDA = GPIO21, SCL = GPIO22 (handled by LiquidCrystal_I2C library)
#define RELAY_ACTIVE_HIGH false // false = LOW-level trigger relay module (common with
                               // optocoupler boards). ON drives IN LOW, OFF drives IN HIGH.
const bool RELAY_UV_ACTIVE_HIGH     = true;   // NC wiring: HIGH = de-energised = UV ON at boot
const bool RELAY_BYPASS_ACTIVE_HIGH = false;  // NO wiring: LOW  = energised     = bypass ON
const bool RELAY_SELF_TEST_AT_BOOT  = true;   // brief startup pulse test for pump relay

// BLE UUIDs — must match ble_provisioning_service.dart
#define BLE_SERVICE_UUID       "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define BLE_CHAR_UUID          "beb5483e-36e1-4688-b7f5-ea07361b26a8"

// ════════════════════════════════════════════════════════════════════════════
// Globals
// ════════════════════════════════════════════════════════════════════════════

Preferences prefs;
WebSocketsClient ws;

// Persisted credentials / device identity
// Hardcoded fallback ID — overwritten by BLE provisioning if app sends one.
char g_deviceId[32]  = "agos-BLE01";
char g_ssid[64]      = "";
char g_password[64]  = "";

// Pump state
volatile bool g_pumpActive    = false;
volatile bool g_pumpManual    = false;
volatile int  g_pumpRemaining = 0;   // seconds remaining in manual mode

// Set by the BLE callback when the app sends new WiFi credentials while
// the device is already connected.  The loop() picks this up and reconnects.
volatile bool g_reconnectWifi = false;

// Timing
unsigned long g_lastSendMs = 0;
bool          g_wsConnected = false;

// pH smoothing — Exponential Moving Average across sensor cycles
// alpha = 0.3: new reading has 30% weight; faster convergence without excessive noise
// set to -1.0 until first reading taken
const float PH_EMA_ALPHA = 0.3f;
float       g_phVoltageEma = -1.0f;  // -1 = uninitialized

// UV relay state — persisted to NVS; default ON (NC wiring = UV ON when relay de-energised)
bool g_uvActive = true;

// Bypass pump state
bool          g_bypassActive  = false;  // true when bypass pump is currently running
int           g_bypassHour    = 2;      // scheduled hour (0-23), -1 = disabled
int           g_bypassMin     = 0;      // scheduled minute (0-59)
int           g_bypassDurSec  = 1800;   // run duration in seconds (default 30 min)
unsigned long g_bypassEndMs   = 0;      // millis() at which to stop bypass (0 = not running)
int           g_lastBypassDay = -1;     // tm_mday when bypass last started (prevents re-trigger)

// LCD ticker string — rebuilt on every sensor send
char          g_tickerBuf[128] = "";
int           g_tickerPos      = 0;     // current scroll offset (chars)
unsigned long g_lcdScrollMs    = 0;     // last scroll step timestamp

// ─────────────────────────── BLE state ──────────────────────────────────────
BLEServer*         g_bleServer = nullptr;
BLECharacteristic* g_bleChar   = nullptr;
bool               g_bleClientConnected = false;
bool               g_provisioningDone   = false;  // true after WiFi creds received

// ─────────────────────────── LCD ─────────────────────────────────────────────
// 16x2 I2C LCD at address 0x27 (try 0x3F if blank after power-on)
LiquidCrystal_I2C g_lcd(0x27, 16, 2);

// ════════════════════════════════════════════════════════════════════════════
// Helpers
// ════════════════════════════════════════════════════════════════════════════

/// Stable device ID derived from the last 8 hex digits of the ESP32 MAC.
String buildDeviceId() {
  // esp_mac.h provides esp_read_mac() on all ESP32 core versions.
  // ESP_MAC_WIFI_STA is the correct enum in core 3.x (was renamed from
  // ESP_IF_WIFI_STA in older cores).
  uint8_t mac[6] = {0};
  esp_read_mac(mac, ESP_MAC_WIFI_STA);
  char buf[20];
  snprintf(buf, sizeof(buf), "agos-%02X%02X%02X%02X",
           mac[2], mac[3], mac[4], mac[5]);
  return String(buf);
}

// ════════════════════════════════════════════════════════════════════════════
// Sensor reading functions
// ════════════════════════════════════════════════════════════════════════════

float readTurbidity() {
  // DFRobot Turbidity Sensor V1.0 (SEN0189) powered from 5 V.
  // Voltage divider (10 kΩ + 20 kΩ) scales 0-4.5 V → 0-3.0 V for the ESP32 ADC.
  // Reverse the divider to recover the true sensor voltage before applying the formula.
  const int samples = 21;
  int raw[samples];
  for (int i = 0; i < samples; i++) {
    raw[i] = analogRead(PIN_TURBIDITY);
    delay(2);
  }
  // Insertion sort for a small fixed-size buffer; median rejects short spikes.
  for (int i = 1; i < samples; i++) {
    int key = raw[i];
    int j = i - 1;
    while (j >= 0 && raw[j] > key) {
      raw[j + 1] = raw[j];
      j--;
    }
    raw[j + 1] = key;
  }
  int medianRaw = raw[samples / 2];
  float adcVoltage    = medianRaw * 3.3f / 4095.0f;
  float sensorVoltage = adcVoltage / 0.667f;  // undo divider: 20/(10+20) = 0.667
  // DFRobot SEN0189 polynomial for 5 V supply (higher V = cleaner water):
  float ntu;
  if (sensorVoltage >= 4.2f) {
    ntu = 0.0f;
  } else {
    ntu = -1120.4f * sensorVoltage * sensorVoltage
          + 5742.3f * sensorVoltage
          - 4352.9f;
  }
  // Subtract the clean-water baseline so clear water reads ~0 NTU,
  // then scale to match lab-measured NTU values using TURB_SCALE_FACTOR.
  // TURB_CLEAN_NTU: offset for your sensor's zero-point in clear water.
  // TURB_SCALE_FACTOR: multiplier to align with certified turbidimeter readings.
  ntu = (ntu - TURB_CLEAN_NTU) * TURB_SCALE_FACTOR;
  return constrain(ntu, 0.0f, 3000.0f);
}

float readPh() {
  // PH-4502C module powered from 5 V. Output ≈ 2.5 V at pH 7 (higher V → lower pH).
  // Output > ~3.3 V at pH < 5.5 will saturate the ADC — acceptable for water quality use.
  // Calibrate: dip probe into pH-7 buffer, adjust on-board trim pot until ADC reads PH_V_OFFSET.
  long sum = 0;
  for (int i = 0; i < 10; i++) { sum += analogRead(PIN_PH); delay(2); }
  float voltage = (sum / 10.0f) * 3.3f / 4095.0f;
  // EMA smoothing across cycles — reduces noise from water movement/stirring.
  // First call: seed EMA with raw reading; subsequent calls: blend in new sample.
  if (g_phVoltageEma < 0.0f) {
    g_phVoltageEma = voltage;   // first reading: no history yet
  } else {
    g_phVoltageEma = PH_EMA_ALPHA * voltage + (1.0f - PH_EMA_ALPHA) * g_phVoltageEma;
  }
  float ph = 7.0f + ((PH_V_OFFSET - g_phVoltageEma) / PH_V_PER_PH);
  return constrain(ph, 0.0f, 14.0f);
}

float readTds(float temperatureC) {
  // DFRobot TDS Meter V1.0 — power from 3.3 V (direct ADC, no voltage divider needed).
  // Uses the DFRobot official polynomial with temperature compensation.
  long sum = 0;
  for (int i = 0; i < 10; i++) { sum += analogRead(PIN_TDS); delay(2); }
  float voltage = (sum / 10.0f) * TDS_VREF / 4095.0f;
  float compensationCoeff  = 1.0f + TDS_TEMP_COEF * (temperatureC - 25.0f);
  float compensatedVoltage = voltage / compensationCoeff;
  float tds = (133.42f * compensatedVoltage * compensatedVoltage * compensatedVoltage
               - 255.86f * compensatedVoltage * compensatedVoltage
               + 857.39f * compensatedVoltage) * 0.5f;
  return constrain(tds, 0.0f, 2000.0f);
}

float readTemperature() {
  // No temperature sensor in this build — returns 25 °C for TDS compensation.
  // To add real compensation: wire a DS18B20 to GPIO4, add OneWire + DallasTemperature
  // libraries, and replace this function with the sensor read.
  return 25.0f;
}

float readTankLevel() {
  // JSN-SR04T V3.0 — waterproof ultrasonic, same protocol as HC-SR04. Range: 20-600 cm.
  // ECHO outputs 5 V — use voltage divider (1 kΩ + 2 kΩ) on GPIO18.
  static float lastValidLevel = -1.0f;  // -1 = no reading yet

  digitalWrite(PIN_TRIG, LOW);  delayMicroseconds(2);
  digitalWrite(PIN_TRIG, HIGH); delayMicroseconds(10);
  digitalWrite(PIN_TRIG, LOW);

  long duration = pulseIn(PIN_ECHO, HIGH, 30000);  // 30 ms timeout
  if (duration == 0) {
    // No echo — return last known good value to avoid false 0% drops.
    // On very first read, fall back to 0 (no data yet).
    return (lastValidLevel >= 0.0f) ? lastValidLevel : 0.0f;
  }

  float distanceCm = duration * 0.0343f / 2.0f;
  // Water height = TANK_HEIGHT_CM - distance to surface
  float waterHeight = TANK_HEIGHT_CM - distanceCm;
  float levelPct    = constrain((waterHeight / TANK_HEIGHT_CM) * 100.0f, 0.0f, 100.0f);
  lastValidLevel = levelPct;
  return levelPct;
}

float readVolume(float levelPct) {
  return (levelPct / 100.0f) * TANK_CAPACITY_L;
}


// ════════════════════════════════════════════════════════════════════════════
// Pump control
// ════════════════════════════════════════════════════════════════════════════

void setPump(bool on) {
  g_pumpActive = on;
  bool level = RELAY_ACTIVE_HIGH ? on : !on;
  digitalWrite(PIN_PUMP_RELAY, level ? HIGH : LOW);
}

void setUvRelay(bool on) {
  g_uvActive = on;
  // RELAY_UV_ACTIVE_HIGH = true: HIGH = de-energised relay = NC closed = UV ON
  bool level = RELAY_UV_ACTIVE_HIGH ? on : !on;
  digitalWrite(PIN_UV_RELAY, level ? HIGH : LOW);
  // Persist to NVS
  prefs.begin("agos", false);
  prefs.putBool("uv_on", on);
  prefs.end();
  Serial.printf("[UV] %s\n", on ? "ON" : "OFF");
}

void setBypassRelay(bool on) {
  g_bypassActive = on;
  // RELAY_BYPASS_ACTIVE_HIGH = false: LOW = energised relay = NO closed = bypass ON
  bool level = RELAY_BYPASS_ACTIVE_HIGH ? on : !on;
  digitalWrite(PIN_BYPASS_RELAY, level ? HIGH : LOW);
  Serial.printf("[Bypass pump] %s\n", on ? "ON" : "OFF");
}

// ════════════════════════════════════════════════════════════════════════════
// LCD functions
// ════════════════════════════════════════════════════════════════════════════

// Rebuild the Row-2 scrolling ticker with latest sensor values.
// Called from sendSensorData() so the values are always fresh.
void rebuildTicker(float level, float ph, float turbidity, float tds) {
  snprintf(g_tickerBuf, sizeof(g_tickerBuf),
           "Lv:%.0f%%  pH:%.2f  Turb:%.1fNTU  TDS:%.0fppm  ",
           level, ph, turbidity, tds);
}

// Advance Row-2 scroll by one character — call from loop() every ~350 ms.
void tickLcdScroll() {
  unsigned long now = millis();
  if (now - g_lcdScrollMs < 350) return;
  g_lcdScrollMs = now;
  int len = strlen(g_tickerBuf);
  if (len == 0) return;
  g_lcd.setCursor(0, 1);
  for (int col = 0; col < 16; col++) {
    g_lcd.print((char)g_tickerBuf[(g_tickerPos + col) % len]);
  }
  g_tickerPos = (g_tickerPos + 1) % len;
}

// Update Row-1 status string — called from sendSensorData().
void updateLcdStatus() {
  g_lcd.setCursor(0, 0);
  if (!g_wsConnected) {
    g_lcd.print("OFFLINE...      ");
  } else if (g_bypassActive) {
    g_lcd.print("BYPASSING...    ");
  } else if (g_pumpActive) {
    g_lcd.print("FILTERING...    ");
  } else if (!g_uvActive) {
    g_lcd.print("UV LAMP OFF     ");
  } else {
    g_lcd.print("OPERATIONAL     ");
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Bypass schedule
// ════════════════════════════════════════════════════════════════════════════

// Check whether it's time to start the daily bypass. Call from loop().
// Also stops the bypass when its duration elapses.
void checkBypassSchedule() {
  // Stop running bypass if duration has elapsed
  if (g_bypassActive && g_bypassEndMs > 0 && millis() >= g_bypassEndMs) {
    setBypassRelay(false);
    g_bypassEndMs = 0;
    Serial.println("[Bypass] Duration elapsed → OFF");
  }

  // Only schedule-trigger when NTP is available and we're online
  if (g_bypassHour < 0 || g_bypassHour > 23) return;

  struct tm t;
  if (!getLocalTime(&t)) return;  // NTP not yet synced

  if (t.tm_hour == g_bypassHour && t.tm_min == g_bypassMin
      && t.tm_mday != g_lastBypassDay && !g_bypassActive) {
    g_lastBypassDay = t.tm_mday;
    g_bypassEndMs   = millis() + (unsigned long)g_bypassDurSec * 1000UL;
    setBypassRelay(true);
    Serial.printf("[Bypass] Scheduled trigger %02d:%02d, dur=%ds\n",
                  g_bypassHour, g_bypassMin, g_bypassDurSec);
  }
}

// Call every second (from loop) to count down manual mode
void tickPumpCountdown() {
  static unsigned long lastTickMs = 0;
  if (!g_pumpManual) return;
  if (g_pumpRemaining <= 0) return;  // duration=0 → indefinite; no auto-expiry
  if (millis() - lastTickMs < 1000) return;
  lastTickMs = millis();

  g_pumpRemaining--;
  if (g_pumpRemaining == 0) {
    g_pumpManual  = false;
    setPump(false);
    Serial.println("[Pump] Manual timer expired → OFF");
  }
}

// ════════════════════════════════════════════════════════════════════════════
// WebSocket callbacks
// ════════════════════════════════════════════════════════════════════════════

void onWsEvent(WStype_t type, uint8_t* payload, size_t length) {
  switch (type) {
    case WStype_CONNECTED:
      g_wsConnected = true;
      Serial.printf("[WS] Connected to %s\n", WS_HOST);
      break;

    case WStype_DISCONNECTED:
      g_wsConnected = false;
      Serial.printf("[WS] Disconnected — will reconnect... (heap: %u)\n", ESP.getFreeHeap());
      break;

    case WStype_ERROR:
      Serial.printf("[WS] SSL/Socket error (len=%u)\n", length);
      break;

    case WStype_TEXT: {
      // Parse incoming message from backend (pump_command, etc.)
      JsonDocument doc;
      DeserializationError err = deserializeJson(doc, payload, length);
      if (err) break;

      const char* msgType = doc["type"] | "";
      if (strcmp(msgType, "pump_command") == 0) {
        const char* action         = doc["action"]           | "off";
        int         durationSeconds = doc["duration_seconds"] | 0;
        bool        turnOn          = strcmp(action, "on") == 0;
        setPump(turnOn);
        g_pumpManual    = turnOn;
        g_pumpRemaining = turnOn ? durationSeconds : 0;
        Serial.printf("[Pump] Command: %s, duration=%ds\n", action, durationSeconds);
      } else if (strcmp(msgType, "uv_command") == 0) {
        const char* action = doc["action"] | "on";
        bool uvOn = strcmp(action, "on") == 0;
        setUvRelay(uvOn);
      } else if (strcmp(msgType, "bypass_command") == 0) {
        const char* action  = doc["action"] | "off";
        int         durSec  = doc["duration_seconds"] | g_bypassDurSec;
        bool        turnOn  = strcmp(action, "on") == 0;
        if (turnOn) {
          g_bypassEndMs = millis() + (unsigned long)durSec * 1000UL;
          setBypassRelay(true);
        } else {
          setBypassRelay(false);
          g_bypassEndMs = 0;
        }
        Serial.printf("[Bypass] Command: %s, duration=%ds\n", action, durSec);
      } else if (strcmp(msgType, "bypass_schedule") == 0) {
        g_bypassHour   = doc["hour"]             | g_bypassHour;
        g_bypassMin    = doc["minute"]            | g_bypassMin;
        g_bypassDurSec = doc["duration_seconds"]  | g_bypassDurSec;
        // Persist to NVS
        prefs.begin("agos", false);
        prefs.putInt("bypass_hour", g_bypassHour);
        prefs.putInt("bypass_min",  g_bypassMin);
        prefs.putInt("bypass_dur",  g_bypassDurSec);
        prefs.end();
        Serial.printf("[Bypass] Schedule set: %02d:%02d, dur=%ds\n",
                      g_bypassHour, g_bypassMin, g_bypassDurSec);
      }
      break;
    }

    default:
      break;
  }
}

// ════════════════════════════════════════════════════════════════════════════
// BLE callbacks
// ════════════════════════════════════════════════════════════════════════════

class ProvisioningCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* chr) override {
    // getValue() returns Arduino String in ESP32 core 3.x — must not assign to std::string directly
    String rawArduino = chr->getValue();
    if (rawArduino.length() == 0) return;
    std::string raw = rawArduino.c_str();  // convert to std::string for ArduinoJson

    Serial.printf("[BLE] Received %d bytes\n", raw.length());

    JsonDocument doc;
    DeserializationError err = deserializeJson(doc, raw.c_str());
    if (err) {
      Serial.println("[BLE] JSON parse error — ignoring");
      return;
    }

    const char* ssid     = doc["ssid"]      | "";
    const char* password = doc["password"]  | "";
    // device_id is HARDCODED — ignore whatever the app sends
    // const char* deviceId = doc["device_id"] | "";

    if (strlen(ssid) == 0) {
      Serial.println("[BLE] No SSID in payload — ignoring");
      return;
    }

    strncpy(g_ssid,     ssid,     sizeof(g_ssid)     - 1);
    strncpy(g_password, password, sizeof(g_password) - 1);
    // g_deviceId stays as hardcoded "agos-BLE01"

    Serial.printf("[BLE] Provisioning: SSID=%s, deviceId=%s\n", g_ssid, g_deviceId);

    // Persist to NVS flash so device remembers credentials after reboot
    prefs.begin("agos", false);
    prefs.putString("ssid",      g_ssid);
    prefs.putString("password",  g_password);
    prefs.putString("device_id", g_deviceId);
    prefs.end();

    // Notify app that credentials were received (echo back device_id)
    char ack[64];
    snprintf(ack, sizeof(ack), "{\"ok\":true,\"device_id\":\"%s\"}", g_deviceId);
    chr->setValue(ack);
    chr->notify();

    // If WiFi was already running, signal the loop to reconnect with new creds.
    if (g_provisioningDone) {
      g_reconnectWifi = true;
      Serial.println("[BLE] New WiFi credentials received — will reconnect");
    }
    g_provisioningDone = true;
  }
};

class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* server) override {
    g_bleClientConnected = true;
    Serial.println("[BLE] App connected");
  }
  void onDisconnect(BLEServer* server) override {
    g_bleClientConnected = false;
    Serial.println("[BLE] App disconnected — restarting advertising");
    if (!g_provisioningDone) {
      BLEDevice::startAdvertising();
    }
  }
};

// ════════════════════════════════════════════════════════════════════════════
// BLE setup
// ════════════════════════════════════════════════════════════════════════════

void startBleProvisioning() {
  String deviceName = String("AGOS-") + String(g_deviceId).substring(5); // "AGOS-zksl9QK3"

  BLEDevice::init(deviceName.c_str());
  g_bleServer = BLEDevice::createServer();
  g_bleServer->setCallbacks(new ServerCallbacks());

  BLEService* service = g_bleServer->createService(BLE_SERVICE_UUID);

  g_bleChar = service->createCharacteristic(
      BLE_CHAR_UUID,
      BLECharacteristic::PROPERTY_WRITE |
      BLECharacteristic::PROPERTY_NOTIFY
  );
  g_bleChar->addDescriptor(new BLE2902());
  g_bleChar->setCallbacks(new ProvisioningCallbacks());

  service->start();

  BLEAdvertising* adv = BLEDevice::getAdvertising();
  adv->addServiceUUID(BLE_SERVICE_UUID);
  adv->setScanResponse(true);
  adv->setMinPreferred(0x06);
  BLEDevice::startAdvertising();

  Serial.printf("[BLE] Advertising as '%s'\n", deviceName.c_str());
}

// ════════════════════════════════════════════════════════════════════════════
// WiFi + WebSocket setup
// ════════════════════════════════════════════════════════════════════════════

bool connectWifi(const char* ssid, const char* password, int timeoutSec = 20) {
  Serial.printf("[WiFi] Connecting to '%s'...\n", ssid);
  // Reset WiFi state completely before connecting — prevents "sta is
  // connecting, cannot set config" errors when called after BLE provisioning.
  WiFi.disconnect(true);
  WiFi.mode(WIFI_OFF);
  delay(300);
  WiFi.mode(WIFI_STA);
  delay(100);
  WiFi.begin(ssid, password);
  int elapsed = 0;
  while (WiFi.status() != WL_CONNECTED && elapsed < timeoutSec) {
    delay(1000);
    elapsed++;
    Serial.print(".");
  }
  Serial.println();
  if (WiFi.status() == WL_CONNECTED) {
    Serial.printf("[WiFi] Connected — IP: %s\n", WiFi.localIP().toString().c_str());
    // Sync NTP time for bypass pump schedule (UTC+8 = Philippine Standard Time)
    configTime(8 * 3600, 0, "pool.ntp.org", "time.cloudflare.com");
    Serial.println("[NTP] Time sync started (UTC+8)");
    return true;
  }
  Serial.println("[WiFi] Failed to connect");
  return false;
}

void startWebSocket() {
  if (WS_USE_SSL) {
    ws.beginSSL(WS_HOST, WS_PORT, WS_PATH);
  } else {
    ws.begin(WS_HOST, WS_PORT, WS_PATH);
  }
  ws.onEvent(onWsEvent);
  ws.setReconnectInterval(RECONN_DELAY_MS);
  ws.enableHeartbeat(25000, 3000, 2);  // ping every 25 s
  Serial.printf("[WS] Configured → wss://%s:%d%s\n", WS_HOST, WS_PORT, WS_PATH);
}

// Free BLE stack memory once WiFi is established.
// BLE only needs to run while credentials are missing/wrong.
// After a successful WiFi connect, we don't need BLE until the user
// power-cycles the device with incorrect credentials again.
static bool g_bleDeinited = false;
void deinitBle() {
  if (!g_bleDeinited) {
    Serial.println("[BLE] WiFi up — freeing BLE heap for SSL WebSocket");
    Serial.flush();
    BLEDevice::deinit(true);
    // Release Bluetooth controller memory back to the general heap
    esp_bt_controller_mem_release(ESP_BT_MODE_BLE);
    g_bleDeinited = true;
    delay(500);  // let BLE RTOS tasks fully stop before starting SSL
    Serial.printf("[Heap] Free after BLE deinit: %u bytes\n", ESP.getFreeHeap());
    Serial.flush();
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Build and send sensor_data JSON
// ════════════════════════════════════════════════════════════════════════════

void sendSensorData() {
  float temperature = readTemperature();
  float turbidity   = readTurbidity();
  float ph          = readPh();
  float tds         = readTds(temperature);
  float level       = readTankLevel();
  float volume      = readVolume(level);

  // Auto-pump logic — OFFLINE FALLBACK ONLY.
  // When the backend WebSocket is connected, the backend controls the pump using the
  // user-configured thresholds from the app settings. The firmware only makes pump
  // decisions locally when there is no backend connection (e.g. internet outage).
  //
  // Offline threshold constants (should loosely match app defaults):
  //   Turbidity: PUMP_TURB_MIN – PUMP_TURB_MAX NTU
  //   pH:        PUMP_PH_MIN – PUMP_PH_MAX
  //   TDS:       < PUMP_TDS_MAX ppm
  //
  // Guard: ph clamped to exactly 0.00 or 14.00 usually means probe is in air / not wired.
  // turbidity=0 is valid (clear water) so it is NOT used as a validity gate.
  bool sensorsValid = (ph >= 0.5f && ph <= 13.5f);

  bool autoPump = sensorsValid
               && ((turbidity < PUMP_TURB_MIN || turbidity > PUMP_TURB_MAX)
                || (ph < PUMP_PH_MIN || ph > PUMP_PH_MAX)
                || (tds > PUMP_TDS_MAX));

  // Only apply local auto-pump when backend is not connected.
  // When connected, backend sends pump_command based on app-configured thresholds.
  if (!g_pumpManual && !g_wsConnected) {
    setPump(autoPump);
  }

  JsonDocument doc;
  doc["type"]       = "sensor_data";
  doc["device_id"]  = g_deviceId;
  doc["level"]      = round(level   * 10.0f) / 10.0f;
  doc["volume"]     = round(volume  * 10.0f) / 10.0f;
  doc["capacity"]   = TANK_CAPACITY_L;
  doc["flow_rate"]  = 0.0f;  // no flow sensor
  doc["turbidity"]  = round(turbidity  * 100.0f) / 100.0f;
  doc["ph"]         = round(ph         * 100.0f) / 100.0f;
  doc["tds"]        = round(tds        * 10.0f)  / 10.0f;
  doc["temperature"]= round(temperature * 10.0f) / 10.0f;
  doc["pump_active"]     = g_pumpActive;
  doc["uv_on"]           = g_uvActive;
  doc["bypass_pump_on"]  = g_bypassActive;

  String payload;
  serializeJson(doc, payload);
  ws.sendTXT(payload);

  // Update LCD with fresh sensor values
  rebuildTicker(level, ph, turbidity, tds);
  updateLcdStatus();

  // Debug: raw ADC voltages — helpful for wiring/calibration checks.
  // Expected when probes are in water: Turb ≈ 2.0-3.0V, pH ≈ 2.0-3.0V, TDS ≈ 0.3-1.5V
  float dbgTurbV = analogRead(PIN_TURBIDITY) * 3.3f / 4095.0f;
  float dbgPhV   = analogRead(PIN_PH)        * 3.3f / 4095.0f;
  float dbgTdsV  = analogRead(PIN_TDS)       * 3.3f / 4095.0f;
  Serial.printf("[ADC] Turb=%.3fV  pH=%.3fV  TDS=%.3fV\n", dbgTurbV, dbgPhV, dbgTdsV);

  Serial.printf("[%lu] Level=%.1f%% Turb=%.2f pH=%.2f TDS=%.0f Pump=%s\n",
                millis() / 1000,
                level, turbidity, ph, tds,
                g_pumpActive ? "ON" : "OFF");
}

// ════════════════════════════════════════════════════════════════════════════
// Setup
// ════════════════════════════════════════════════════════════════════════════

void setup() {
  // ── Relay-off first — must happen before delay() or Serial init.
  //    The relay module's onboard pull-down can activate the coil while
  //    GPIO26 is still floating (input mode), drawing ~70 mA and triggering
  //    a brownout that corrupts the flash read on subsequent boots.
  pinMode(PIN_PUMP_RELAY, OUTPUT);
  digitalWrite(PIN_PUMP_RELAY, RELAY_ACTIVE_HIGH ? LOW : HIGH);  // pump relay off

  // UV lamp relay — NC wiring. HIGH = de-energised = NC closed = UV ON at boot.
  pinMode(PIN_UV_RELAY, OUTPUT);
  digitalWrite(PIN_UV_RELAY, RELAY_UV_ACTIVE_HIGH ? HIGH : LOW);  // UV ON at boot

  // Bypass pump relay — NO wiring. HIGH = de-energised = NO open = bypass OFF at boot.
  pinMode(PIN_BYPASS_RELAY, OUTPUT);
  digitalWrite(PIN_BYPASS_RELAY, RELAY_BYPASS_ACTIVE_HIGH ? LOW : HIGH);  // bypass OFF at boot

  Serial.begin(115200);
  delay(300);
  Serial.println("\n=== AGOS ESP32 Firmware ===");

  if (RELAY_SELF_TEST_AT_BOOT) {
    Serial.println("[RelayTest] Pump relay pulse test...");
    bool onLevel = RELAY_ACTIVE_HIGH ? HIGH : LOW;
    bool offLevel = RELAY_ACTIVE_HIGH ? LOW : HIGH;
    for (int i = 0; i < 2; i++) {
      digitalWrite(PIN_PUMP_RELAY, onLevel ? HIGH : LOW);
      delay(250);  // audible click pulse
      digitalWrite(PIN_PUMP_RELAY, offLevel ? HIGH : LOW);
      delay(300);
    }
    Serial.println("[RelayTest] Done.");
  }

  // Pin modes for sensors
  pinMode(PIN_TRIG, OUTPUT);
  pinMode(PIN_ECHO, INPUT);

  // LCD init — I2C on GPIO21 (SDA) / GPIO22 (SCL)
  Wire.begin(21, 22);
  g_lcd.init();
  g_lcd.backlight();
  g_lcd.setCursor(0, 0);
  g_lcd.print("AGOS Starting...");
  g_lcd.setCursor(0, 1);
  g_lcd.print("Please wait...  ");

  // Load stored credentials from NVS flash
  prefs.begin("agos", true);
  prefs.getString("ssid",      g_ssid,     sizeof(g_ssid));
  prefs.getString("password",  g_password, sizeof(g_password));
  // Note: device_id is hardcoded above; do not overwrite from NVS.
  // Load UV state (default ON if not yet stored)
  g_uvActive     = prefs.getBool("uv_on",    true);
  // Load bypass schedule
  g_bypassHour   = prefs.getInt("bypass_hour", 2);
  g_bypassMin    = prefs.getInt("bypass_min",  0);
  g_bypassDurSec = prefs.getInt("bypass_dur",  1800);
  prefs.end();

  // Apply loaded UV state to relay (overrides the boot-safe HIGH set above)
  setUvRelay(g_uvActive);  // also calls prefs.begin/end — safe because it's separate transaction

  // (device_id is hardcoded — no dynamic generation needed)

  Serial.printf("[Init] Device ID: %s\n", g_deviceId);

  // Always start BLE — the app can send new WiFi credentials at any time,
  // even while the device is already connected to the network.
  startBleProvisioning();

  if (strlen(g_ssid) > 0) {
    Serial.println("[Init] Stored WiFi credentials found — connecting");
    g_provisioningDone = true;
    connectWifi(g_ssid, g_password);
    deinitBle();
    startWebSocket();
  } else {
    Serial.println("[Init] No WiFi credentials — waiting for BLE provisioning");
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Loop
// ════════════════════════════════════════════════════════════════════════════

void loop() {
  // ── BLE provisioning phase ──────────────────────────────────────────────
  if (!g_provisioningDone) {
    // Nothing to do — wait for the BLE callback to fire
    delay(100);
    return;
  }

  // ── WiFi credential update (new SSID/password sent via BLE) ────────────
  if (g_reconnectWifi) {
    g_reconnectWifi = false;
    ws.disconnect();
    g_wsConnected = false;
    WiFi.disconnect(true);
    delay(500);
    bool ok = connectWifi(g_ssid, g_password);
    if (ok) {
      deinitBle();
      startWebSocket();
    }
  }

  // Connect WiFi if not already connected
  if (WiFi.status() != WL_CONNECTED) {
    bool ok = connectWifi(g_ssid, g_password);
    if (ok) {
      deinitBle();
      startWebSocket();
    } else {
      delay(RECONN_DELAY_MS);
      return;
    }
  }

  // ── WebSocket loop ───────────────────────────────────────────────────────
  ws.loop();

  // ── Pump countdown ───────────────────────────────────────────────────────
  tickPumpCountdown();

  // ── Bypass schedule check + duration expiry ──────────────────────────────
  checkBypassSchedule();

  // ── LCD Row-2 scrolling ticker ───────────────────────────────────────────
  tickLcdScroll();

  // ── Send sensor data every SEND_INTERVAL_MS ─────────────────────────────
  unsigned long now = millis();
  if (g_wsConnected && (now - g_lastSendMs >= SEND_INTERVAL_MS)) {
    g_lastSendMs = now;
    sendSensorData();
  }
}