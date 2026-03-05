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
 *   ArduinoJson        >= 7.x   (Benoit Blanchon)
 *   WebSockets         >= 2.4   (Markus Sattler)   → "WebSockets" by Markus Sattler
 *   BLEDevice          bundled in esp32 Arduino core >= 2.x
 *   OneWire            >= 2.3   (Paul Stoffregen)
 *   DallasTemperature  >= 3.9   (Miles Burton)
 * ─────────────────────────────────────────────────────────────────────────────
 *
 * ─── Board Setup ─────────────────────────────────────────────────────────────
 *   Board : ESP32 Dev Module  (or NodeMCU-32S)
 *   Partition scheme : Default (or any that has BLE enabled)
 *
 * ─── Pin Map ─────────────────────────────────────────────────────────────────
 *   PIN_TURBIDITY   GPIO34   Analog input  (0–3.3 V from turbidity sensor)
 *   PIN_PH          GPIO35   Analog input  (0–3.3 V from pH probe board)
 *   PIN_TDS         GPIO32   Analog input  (0–3.3 V from TDS/EC sensor)
 *   PIN_TRIG        GPIO5    Ultrasonic trigger (HC-SR04)
 *   PIN_ECHO        GPIO18   Ultrasonic echo   (HC-SR04)
 *   PIN_DS18B20     GPIO4    OneWire temperature sensor (DS18B20)
 *   PIN_PUMP_RELAY  GPIO26   Relay control (HIGH = pump ON)
 *   PIN_FLOW        GPIO27   Flow sensor interrupt (YF-S201 Hall sensor)
 * ─────────────────────────────────────────────────────────────────────────────
 */

#include <WiFi.h>
#include <esp_mac.h>          // esp_read_mac() for ESP32 core 3.x
#include <Preferences.h>
// BLE — use the built-in library from ESP32 Arduino core (do NOT install
// the separate "ESP32 BLE Arduino" library from Arduino Library Manager;
// that older library conflicts with ESP32 core 3.x).
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <ArduinoJson.h>
#include <WebSocketsClient.h>
#include <OneWire.h>
#include <DallasTemperature.h>

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
const float TURBIDITY_V_MAX  = 3.3f;   // voltage at max turbidity reading
const float PH_V_OFFSET      = 1.65f;  // voltage at pH 7 (midpoint)
const float PH_V_PER_PH      = 0.1786f;// voltage change per pH unit (typical)
const float TDS_VREF         = 3.3f;   // reference voltage for TDS sensor
const float TDS_TEMP_COEF    = 0.02f;  // temperature coefficient (2% / °C)

// Timing
const unsigned long SEND_INTERVAL_MS = 5000;  // 5 s between readings
const unsigned long RECONN_DELAY_MS  = 5000;  // reconnect delay on WS drop

// Pin assignments
#define PIN_TURBIDITY   34
#define PIN_PH          35
#define PIN_TDS         32
#define PIN_TRIG         5
#define PIN_ECHO        18
#define PIN_DS18B20      4
#define PIN_PUMP_RELAY  26
#define PIN_FLOW        27

// BLE UUIDs — must match ble_provisioning_service.dart
#define BLE_SERVICE_UUID       "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define BLE_CHAR_UUID          "beb5483e-36e1-4688-b7f5-ea07361b26a8"

// ════════════════════════════════════════════════════════════════════════════
// Globals
// ════════════════════════════════════════════════════════════════════════════

Preferences prefs;
WebSocketsClient ws;
OneWire oneWire(PIN_DS18B20);
DallasTemperature tempSensor(&oneWire);

// Persisted credentials / device identity
// Hardcoded fallback ID — overwritten by BLE provisioning if app sends one.
char g_deviceId[32]  = "agos-BLE01";
char g_ssid[64]      = "";
char g_password[64]  = "";

// Pump state
volatile bool g_pumpActive    = false;
volatile bool g_pumpManual    = false;
volatile int  g_pumpRemaining = 0;   // seconds remaining in manual mode

// Flow sensor
volatile uint32_t g_flowPulses = 0;
unsigned long g_flowLastMs     = 0;
float         g_flowRate       = 0.0f;  // L/min

// Timing
unsigned long g_lastSendMs = 0;
bool          g_wsConnected = false;

// ─────────────────────────── BLE state ──────────────────────────────────────
BLEServer*         g_bleServer = nullptr;
BLECharacteristic* g_bleChar   = nullptr;
bool               g_bleClientConnected = false;
bool               g_provisioningDone   = false;  // true after WiFi creds received

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
  // Average 10 ADC samples to reduce noise
  long sum = 0;
  for (int i = 0; i < 10; i++) { sum += analogRead(PIN_TURBIDITY); delay(2); }
  float voltage = (sum / 10.0f) * TURBIDITY_V_MAX / 4095.0f;
  // Linear approximation: 0 V → 3000 NTU, 4.2 V → 0 NTU
  // Adjust coefficients for your specific turbidity sensor module.
  float ntu = -1120.4f * voltage * voltage + 5742.3f * voltage - 4352.9f;
  return constrain(ntu, 0.0f, 3000.0f);
}

float readPh() {
  long sum = 0;
  for (int i = 0; i < 10; i++) { sum += analogRead(PIN_PH); delay(2); }
  float voltage = (sum / 10.0f) * 3.3f / 4095.0f;
  // pH module output: higher voltage → lower pH
  float ph = 7.0f + ((PH_V_OFFSET - voltage) / PH_V_PER_PH);
  return constrain(ph, 0.0f, 14.0f);
}

float readTds(float temperatureC) {
  long sum = 0;
  for (int i = 0; i < 10; i++) { sum += analogRead(PIN_TDS); delay(2); }
  float voltage = (sum / 10.0f) * TDS_VREF / 4095.0f;
  // Temperature compensation
  float compensationCoeff = 1.0f + TDS_TEMP_COEF * (temperatureC - 25.0f);
  float compensatedVoltage = voltage / compensationCoeff;
  // TDS conversion formula (empirical — adjust for your probe)
  float tds = (133.42f * compensatedVoltage * compensatedVoltage * compensatedVoltage
               - 255.86f * compensatedVoltage * compensatedVoltage
               + 857.39f * compensatedVoltage) * 0.5f;
  return constrain(tds, 0.0f, 2000.0f);
}

float readTemperature() {
  tempSensor.requestTemperatures();
  float t = tempSensor.getTempCByIndex(0);
  return (t == DEVICE_DISCONNECTED_C) ? 25.0f : t;
}

float readTankLevel() {
  // HC-SR04: trigger a 10 µs pulse and measure echo duration
  digitalWrite(PIN_TRIG, LOW);  delayMicroseconds(2);
  digitalWrite(PIN_TRIG, HIGH); delayMicroseconds(10);
  digitalWrite(PIN_TRIG, LOW);

  long duration = pulseIn(PIN_ECHO, HIGH, 30000);  // 30 ms timeout
  if (duration == 0) return 0.0f;                   // timeout / no echo

  float distanceCm = duration * 0.0343f / 2.0f;
  // Water height = TANK_HEIGHT_CM - distance to surface
  float waterHeight = TANK_HEIGHT_CM - distanceCm;
  float levelPct    = (waterHeight / TANK_HEIGHT_CM) * 100.0f;
  return constrain(levelPct, 0.0f, 100.0f);
}

float readVolume(float levelPct) {
  return (levelPct / 100.0f) * TANK_CAPACITY_L;
}

// ════════════════════════════════════════════════════════════════════════════
// Flow sensor ISR
// ════════════════════════════════════════════════════════════════════════════

void IRAM_ATTR onFlowPulse() {
  g_flowPulses++;
}

void updateFlowRate() {
  unsigned long now = millis();
  unsigned long elapsed = now - g_flowLastMs;
  if (elapsed >= 1000) {
    // YF-S201: 7.5 pulses per second = 1 L/min
    g_flowRate = (g_flowPulses / 7.5f) * (1000.0f / elapsed) * 60.0f;
    g_flowPulses = 0;
    g_flowLastMs = now;
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Pump control
// ════════════════════════════════════════════════════════════════════════════

void setPump(bool on) {
  g_pumpActive = on;
  digitalWrite(PIN_PUMP_RELAY, on ? HIGH : LOW);
}

// Call every second (from loop) to count down manual mode
void tickPumpCountdown() {
  static unsigned long lastTickMs = 0;
  if (!g_pumpManual) return;
  if (millis() - lastTickMs < 1000) return;
  lastTickMs = millis();

  if (g_pumpRemaining > 0) {
    g_pumpRemaining--;
  }
  if (g_pumpRemaining <= 0) {
    g_pumpManual  = false;
    g_pumpRemaining = 0;
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
      Serial.println("[WS] Disconnected — will reconnect...");
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
    // getValue() returns Arduino String in ESP32 core 3.x
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

  // Auto-pump logic (mirrors backend default thresholds)
  bool autoPump = (turbidity < 10.0f || turbidity > 50.0f)
               || (ph < 6.0f || ph > 9.5f)
               || (tds > 1000.0f);

  if (!g_pumpManual) {
    setPump(autoPump);
  }

  JsonDocument doc;
  doc["type"]       = "sensor_data";
  doc["device_id"]  = g_deviceId;
  doc["level"]      = round(level   * 10.0f) / 10.0f;
  doc["volume"]     = round(volume  * 10.0f) / 10.0f;
  doc["capacity"]   = TANK_CAPACITY_L;
  doc["flow_rate"]  = round(g_flowRate * 10.0f) / 10.0f;
  doc["turbidity"]  = round(turbidity  * 100.0f) / 100.0f;
  doc["ph"]         = round(ph         * 100.0f) / 100.0f;
  doc["tds"]        = round(tds        * 10.0f)  / 10.0f;
  doc["temperature"]= round(temperature * 10.0f) / 10.0f;
  doc["pump_active"]= g_pumpActive;

  String payload;
  serializeJson(doc, payload);
  ws.sendTXT(payload);

  Serial.printf("[%lu] Level=%.1f%% Turb=%.2f pH=%.2f TDS=%.0f Pump=%s\n",
                millis() / 1000,
                level, turbidity, ph, tds,
                g_pumpActive ? "ON" : "OFF");
}

// ════════════════════════════════════════════════════════════════════════════
// Setup
// ════════════════════════════════════════════════════════════════════════════

void setup() {
  Serial.begin(115200);
  delay(500);
  Serial.println("\n=== AGOS ESP32 Firmware ===");

  // Pin modes
  pinMode(PIN_TRIG,       OUTPUT);
  pinMode(PIN_ECHO,       INPUT);
  pinMode(PIN_PUMP_RELAY, OUTPUT);
  digitalWrite(PIN_PUMP_RELAY, LOW);  // pump off at boot

  attachInterrupt(digitalPinToInterrupt(PIN_FLOW), onFlowPulse, RISING);

  // Temperature sensor
  tempSensor.begin();

  // Load stored credentials from NVS flash
  prefs.begin("agos", true);
  prefs.getString("ssid",      g_ssid,     sizeof(g_ssid));
  prefs.getString("password",  g_password, sizeof(g_password));
  // Note: device_id is hardcoded above; do not overwrite from NVS.
  prefs.end();

  // (device_id is hardcoded — no dynamic generation needed)

  Serial.printf("[Init] Device ID: %s\n", g_deviceId);

  // If we already have stored WiFi credentials, skip BLE and connect directly
  if (strlen(g_ssid) > 0) {
    Serial.println("[Init] Stored WiFi credentials found — skipping BLE provisioning");
    g_provisioningDone = true;
    connectWifi(g_ssid, g_password);
    startWebSocket();
  } else {
    Serial.println("[Init] No WiFi credentials — starting BLE provisioning");
    startBleProvisioning();
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

  // Provisioning just completed → connect WiFi
  if (WiFi.status() != WL_CONNECTED) {
    bool ok = connectWifi(g_ssid, g_password);
    if (ok) {
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

  // ── Flow rate calculation ────────────────────────────────────────────────
  updateFlowRate();

  // ── Send sensor data every SEND_INTERVAL_MS ─────────────────────────────
  unsigned long now = millis();
  if (g_wsConnected && (now - g_lastSendMs >= SEND_INTERVAL_MS)) {
    g_lastSendMs = now;
    sendSensorData();
  }
}
