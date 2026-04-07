# AGOS Layered System Framework

## Visual Diagram

```mermaid
flowchart TD
  subgraph L1[Layer 1: Presentation]
    U1["Mobile App\nAndroid / iOS"]
    U2["Web App\nPWA"]
    U3["Desktop App\nWindows"]
  end

  subgraph L2[Layer 2: Device]
    BLE["BLE Provisioning\nSend WiFi Credentials"]
    ESP["ESP32 Controller"]
    SEN["Sensors\nTurbidity, pH, TDS, Ultrasonic"]
    ACT["Actuators\nPump / UV / Bypass"]
  end

  subgraph L3[Layer 3: Application]
    API["FastAPI Backend\nRender\n/ws/sensor  /ws/app"]
    VAL["Validation + Rules\nThreshold Checks"]
  end

  subgraph L4[Layer 4: Cloud Data]
    AUTH["Firebase Auth"]
    FS["Cloud Firestore\nReadings / Settings / Alerts / Rollups"]
    FCM["FCM Notifications"]
  end

  subgraph LEG[Flow Legend]
    G1["Solid Arrow: Main data/control flow"]
    G2["Labels: Purpose of each connection"]
  end

  U1 -->|Login| AUTH
  U2 -->|Login| AUTH
  U3 -->|Login| AUTH

  U1 -->|Initial setup| BLE --> ESP
  SEN -->|Raw sensor values| ESP
  ESP -->|Relay control| ACT

  ESP -->|1. Telemetry JSON (~5s)| API
  API -->|2. Validate + evaluate thresholds| VAL
  VAL -->|3. Persist| FS
  FS -->|4. Live data read| U1
  FS -->|4. Live data read| U2
  FS -->|4. Live data read| U3

  VAL -->|5. Alert event| FCM
  FCM -->|Push notification| U1
  FCM -->|Push notification| U2
  FCM -->|Push notification| U3

  style L1 fill:#eef6ff,stroke:#2f6fed,stroke-width:1px
  style L2 fill:#eefdf6,stroke:#1f9d5a,stroke-width:1px
  style L3 fill:#fff7ee,stroke:#c26a00,stroke-width:1px
  style L4 fill:#f4f0ff,stroke:#6b46c1,stroke-width:1px
  style LEG fill:#f8fafc,stroke:#7a8699,stroke-dasharray: 4 4

  style U1 fill:#dbeafe,stroke:#1d4ed8
  style U2 fill:#dbeafe,stroke:#1d4ed8
  style U3 fill:#dbeafe,stroke:#1d4ed8

  style BLE fill:#dcfce7,stroke:#15803d
  style ESP fill:#bbf7d0,stroke:#15803d
  style SEN fill:#dcfce7,stroke:#15803d
  style ACT fill:#dcfce7,stroke:#15803d

  style API fill:#ffedd5,stroke:#b45309
  style VAL fill:#fed7aa,stroke:#b45309

  style AUTH fill:#ede9fe,stroke:#6d28d9
  style FS fill:#e9d5ff,stroke:#6d28d9
  style FCM fill:#ede9fe,stroke:#6d28d9
```

## Layer Summary

1. Presentation Layer: Flutter clients for mobile, web, and desktop.
2. Device Layer: ESP32 receives setup via BLE, reads sensors, controls relays.
3. Application Layer: FastAPI backend validates and routes telemetry.
4. Cloud Data Layer: Firebase Auth, Firestore, and FCM provide identity, storage, and alerts.

## End-to-End Flow

1. User signs in through Firebase Auth.
2. App provisions device over BLE with WiFi credentials.
3. ESP32 sends telemetry to backend over WebSocket.
4. Backend validates data and stores it in Firestore.
5. App reads latest values from Firestore.
6. Backend triggers FCM alerts when thresholds are exceeded.
