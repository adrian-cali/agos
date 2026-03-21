/**
 * AGOS Graywater Data Logger
 * 
 * Purpose: Independent ESP32 node for monitoring only the waste water tank.
 * Sensors: Turbidity (SEN0189), pH (PH-4502C), TDS (DFRobot V1.0)
 * 
 * Workflow: Connects to hardcoded WiFi -> reads sensors -> HTTP POSTs JSON payload
 * to a Google Apps Script Web App -> Google Apps Script handles spreadsheet insertions.
 * Does NOT connect to Firebase or the local FastAPI backend.
 */

#include <WiFi.h>
#include <HTTPClient.h>
#include <WiFiClientSecure.h>
#include <ArduinoJson.h>

// ==========================================
// CONFIGURATION
// ==========================================
const char* WIFI_SSID     = "HG8145V5_43963";
const char* WIFI_PASSWORD = "Nekneknyo";

// The Google Apps Script deployment URL 
// (Replace this after deploying your Apps Script Web App)
const char* GOOGLE_SCRIPT_URL = "https://script.google.com/macros/s/AKfycbzAjzTYCpbQgOg6eFbx6bphQGhX-wdV6BrRWGILxxV5fUI960rgy_NxnEnYChw3B2ns/exec";

// Telemetry interval (millis) -> default 5 seconds
const unsigned long SEND_INTERVAL_MS = 5 * 1000;

// ==========================================
// PIN CONFIGURATIONS
// Same as primary ESP32 analog pins
// ==========================================
#define PIN_TURBIDITY_ADC 34
#define PIN_PH_ADC        35
#define PIN_TDS_ADC       32

// Math Constants (Mirrored from main logic)
const int   ADC_RESOLUTION        = 4095;
const float VOLTAGE_REFERENCE     = 3.3;

struct SensorData {
  float turbidity;
  float ph;
  float tds;
};

unsigned long lastSendTime = 0;

// ==========================================
// SENSOR READING FUNCTIONS (Borrowed from main project)
// ==========================================
float mapFloat(float x, float in_min, float in_max, float out_min, float out_max) {
    return (x - in_min) * (out_max - out_min) / (in_max - in_min) + out_min;
}

float readPH() {
    int analogValue = analogRead(PIN_PH_ADC);
    float voltage = (analogValue / (float)ADC_RESOLUTION) * VOLTAGE_REFERENCE;
    
    float phValue = 3.5 * voltage; 
    
    // Bounds checking
    if (phValue < 0.0) phValue = 0.0;
    if (phValue > 14.0) phValue = 14.0;
    
    return phValue;
}

float readTurbidity() {
    int analogValue = analogRead(PIN_TURBIDITY_ADC);
    float voltage = (analogValue / (float)ADC_RESOLUTION) * VOLTAGE_REFERENCE;

    // Based on typical SEN0189 characteristics
    if (voltage < 2.5) {
        return 3000.0;
    } else if (voltage > 3.0) { // Clear water
        return 0.0;
    } else {
        float ntu = -1120.4 * (voltage * voltage) + 5742.3 * voltage - 4353.8;
        return (ntu < 0) ? 0.0 : ntu;
    }
}

float readTDS() {
    int analogValue = analogRead(PIN_TDS_ADC);
    float voltage = (analogValue / (float)ADC_RESOLUTION) * VOLTAGE_REFERENCE;
    
    // Standard DFRobot TDS formula mapping
    // Assuming water temp is ~25C for simplicity (no thermistor attached on this build)
    float compensationCoefficient = 1.0; 
    float compensationVolatge = voltage / compensationCoefficient;
    float tdsValue = (133.42 * compensationVolatge * compensationVolatge * compensationVolatge 
                      - 255.86 * compensationVolatge * compensationVolatge 
                      + 857.39 * compensationVolatge) * 0.5;

    return (tdsValue < 0) ? 0.0 : tdsValue;
}

SensorData getAveragedReadings() {
    SensorData data = {0, 0, 0};
    int samples = 20;

    for (int i = 0; i < samples; i++) {
        data.ph += readPH();
        data.turbidity += readTurbidity();
        data.tds += readTDS();
        delay(10);
    }

    data.ph /= samples;
    data.turbidity /= samples;
    data.tds /= samples;

    return data;
}

// ==========================================
// HTTP POST TO GOOGLE APPS SCRIPT
// ==========================================
void sendDataToGoogleSheets(SensorData data) {
    if (WiFi.status() != WL_CONNECTED) {
        Serial.println("[WIFI] Not connected. Skipping upload.");
        return;
    }

    // Instead of POST, we will use GET and embed the data in the URL 
    // to completely bypass Google's strict CORS/POST restrictions.
    String fullUrl = String(GOOGLE_SCRIPT_URL) + 
                     "?turbidity=" + String(data.turbidity, 2) + 
                     "&ph=" + String(data.ph, 2) + 
                     "&tds=" + String(data.tds, 2);

    // Setup HTTP Secure Client (Google APIs require HTTPS)
    HTTPClient http;
    WiFiClientSecure *client = new WiFiClientSecure;
    
    // Skip TLS certificate validation
    client->setInsecure();

    http.begin(*client, fullUrl);
    
    // IMPORTANT: Tell the HTTP client to automatically follow 301/302 redirects 
    // because Google Apps Script always issues a redirect to a script.googleusercontent.com URL.
    http.setFollowRedirects(HTTPC_STRICT_FOLLOW_REDIRECTS);
    
    // Perform GET request
    int httpResponseCode = http.GET();

    if (httpResponseCode > 0) {
        if (httpResponseCode == 200 || httpResponseCode == 302) {
            Serial.println("[Google Sheets] OK: Data Saved");
        } else {
            Serial.printf("[Google Sheets] HTTP Code: %d\n", httpResponseCode);
        }
    } else {
        Serial.print("[Google Sheets] POST Error: ");
        Serial.println(http.errorToString(httpResponseCode));
    }

    http.end();
    delete client;
}

// ==========================================
// SETUP & LOOP
// ==========================================
void setup() {
    Serial.begin(115200);
    delay(1000);
    
    Serial.println("\n--- AGOS Graywater Data Logger Booting ---");

    // Connect to WiFi
    Serial.print("Connecting to WiFi: ");
    Serial.println(WIFI_SSID);
    
    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
    
    int attempts = 0;
    while (WiFi.status() != WL_CONNECTED && attempts < 20) {
        delay(500);
        Serial.print(".");
        attempts++;
    }

    if (WiFi.status() == WL_CONNECTED) {
        Serial.println("\nWiFi connected.");
        Serial.print("IP address: ");
        Serial.println(WiFi.localIP());
    } else {
        Serial.println("\nWiFi connection failed! Will keep trying in background.");
    }
}

void loop() {
    // Reconnect logic if WiFi drops
    if (WiFi.status() != WL_CONNECTED) {
        Serial.println("WiFi dropped. Reconnecting...");
        WiFi.disconnect();
        WiFi.reconnect();
        delay(5000);
    }

    // Timer check
    unsigned long currentMillis = millis();
    if (currentMillis - lastSendTime >= SEND_INTERVAL_MS || lastSendTime == 0) {
        lastSendTime = currentMillis;

        // Serial.println("\n--- Taking Readings ---"); // Removed extra spacing
        SensorData currentData = getAveragedReadings();
        
        // Print raw ADC voltages mimicking agos_esp32 formatting
        float rawTurbV = (analogRead(PIN_TURBIDITY_ADC) / (float)ADC_RESOLUTION) * VOLTAGE_REFERENCE;
        float rawPhV = (analogRead(PIN_PH_ADC) / (float)ADC_RESOLUTION) * VOLTAGE_REFERENCE;
        float rawTdsV = (analogRead(PIN_TDS_ADC) / (float)ADC_RESOLUTION) * VOLTAGE_REFERENCE;
        
        Serial.printf("[ADC] Turb=%.3fV  pH=%.3fV  TDS=%.3fV\n", rawTurbV, rawPhV, rawTdsV);
        Serial.printf("[%lu] Turb=%.2f NTU  pH=%.2f  TDS=%.0f ppm\n", 
                      currentMillis, currentData.turbidity, currentData.ph, currentData.tds);

        sendDataToGoogleSheets(currentData);
    }

    delay(100);
}
