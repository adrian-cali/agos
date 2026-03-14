# AGOS System Flow

## Tank Overview

| Tank | Purpose |
|------|---------|
| Raw Wastewater Tank | Collects pre-treated greywater from the handwashing station |
| Equalizer Tank | Balances and equalizes water quality before filtration |
| Filter | Removes remaining contaminants from equalized water |
| Holding Tank | Final storage + UV sterilization; sensor monitoring happens here |

---

## Water Flow (Normal Operation)

```
Handwashing Station
        │
        ▼
Mesh Strainer + Grease Trap
(removes large solids and Fats, Oils & Grease)
        │
        ▼
Raw Wastewater Tank
(collection of pre-treated greywater)
        │
        ▼
Equalizer Tank
(balances water quality)
        │
        ▼
Filter
(removes remaining contaminants)
        │
        ▼
Holding Tank ◄─────────────────────────────┐
(UV sterilization + sensor monitoring)      │
        │                                   │
        ▼                                   │
  [Quality OK?]                             │
        │                                   │
       YES → Water is clean and ready       │
        │                                   │
       NO → Pump ON: recirculate back ──────┘
              (Holding Tank → Equalizer Tank → Filter → Holding Tank)
```

---

## Recirculation (Auto-Pump Logic)

When the ESP32 sensors detect that the water in the **Holding Tank** is outside the acceptable quality range, the system automatically recirculates the water back through the filter.

### Trigger Thresholds (configurable in-app)

| Parameter | Default Range | Pump Action |
|-----------|--------------|-------------|
| Turbidity | 0 – 50 NTU | Pump ON if > 50 NTU |
| pH Level | 6.0 – 9.5 | Pump ON if outside range |
| TDS | < 1000 ppm | Pump ON if > 1000 ppm |

- Pump turns **ON** when any parameter is outside acceptable range
- Pump stays **ON** until all parameters return to optimal
- Pump turns **OFF** automatically when quality is restored

---

## Manual Pump Control

The user can manually trigger the pump from the Flutter app:
- Select a duration (5, 10, 15, or 30 minutes)
- Tap **Start Pump**
- Pump runs for the set duration, then auto-stops
- Manual mode can be cancelled early by tapping **Stop Pump**

---

## Sensor Location

All water quality sensors (turbidity, pH, TDS, water level) are installed in the **Holding Tank**. The ultrasonic level sensor (JSN-SR04T) is mounted above the water surface pointing downward.

---

## ESP32 Sensor GPIO Map

| Sensor | GPIO | Notes |
|--------|------|-------|
| Turbidity (SEN0189) | GPIO34 | 5V powered, 10kΩ/20kΩ voltage divider |
| pH (PH-4502C) | GPIO35 | 5V powered, calibrated at pH 7 = 2.5V |
| TDS (V1.0) | GPIO32 | 3.3V powered (NOT 5V) |
| Level (JSN-SR04T) TRIG | GPIO5 | 5V powered |
| Level (JSN-SR04T) ECHO | GPIO18 | 1kΩ/1kΩ voltage divider |
| Pump Relay | GPIO26 | Active-HIGH (NC contact wiring) |
