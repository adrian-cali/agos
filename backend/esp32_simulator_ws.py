import asyncio
import websockets
import json
import random
from datetime import datetime

WS_URL = "ws://localhost:8000/ws/sensor"
DEVICE_ID = "agos-zksl9QK3"  # Adrian Calingasin's device ID (matches Firestore)

# bad-water spike state
_spike_counter = 0  # increments every reading (5 s each); spike every ~60 readings (~5 min)
_SPIKE_INTERVAL = 60

# Simulated pump state (overridden by pump_command from the backend)
_pump_manual_on = False
_pump_manual_remaining = 0  # seconds remaining in manual mode


def generate_sensor_data(spike: bool = False) -> dict:
    if spike:
        # Bad-water spike: push turbidity outside optimal range (critical territory)
        turbidity = random.uniform(110.0, 140.0)  # above critical max of 100 NTU
        ph = random.uniform(5.0, 5.8)             # below critical min of 6.0
        tds = random.uniform(1100, 1400)           # above warning max of 1000 ppm
    else:
        # Normal readings: stay within optimal ranges
        # Turbidity optimal: 10–50 NTU
        turbidity = random.uniform(12.0, 45.0)
        # pH optimal: 6.0–9.5
        ph = random.uniform(6.5, 8.5)
        # TDS optimal: < 1000 ppm
        tds = random.uniform(200, 750)

    # Auto pump logic — using updated default thresholds
    auto_pump = not (10 <= turbidity <= 50) or not (6.0 <= ph <= 9.5) or tds > 1000
    pump_active = _pump_manual_on or auto_pump

    return {
        "type": "sensor_data",
        "device_id": DEVICE_ID,
        "level": random.uniform(65, 72),
        "volume": random.uniform(32000, 36000),
        "capacity": 50000,
        "flow_rate": random.uniform(140, 150),
        "turbidity": round(turbidity, 2),
        "ph": round(ph, 2),
        "tds": round(tds, 1),
        "temperature": round(random.uniform(20, 30), 1),
        "pump_active": pump_active,
        "timestamp": datetime.now().isoformat()
    }


async def send_sensor_data():
    global _spike_counter, _pump_manual_on, _pump_manual_remaining

    while True:
        try:
            async with websockets.connect(WS_URL) as websocket:
                print(f"[{DEVICE_ID}] Connected to WebSocket server\n")

                while True:
                    _spike_counter += 1
                    spike = (_spike_counter % _SPIKE_INTERVAL == 0)

                    # Decrement manual pump countdown
                    if _pump_manual_on and _pump_manual_remaining > 0:
                        _pump_manual_remaining -= 5  # 5 s per loop
                        if _pump_manual_remaining <= 0:
                            _pump_manual_remaining = 0
                            _pump_manual_on = False
                            print(f"[{DEVICE_ID}] Manual pump timer expired → auto mode")

                    data = generate_sensor_data(spike=spike)
                    await websocket.send(json.dumps(data))

                    pump_str = "PUMP:ON (manual)" if _pump_manual_on else \
                               ("PUMP:ON (auto)" if data["pump_active"] else "PUMP:OFF")
                    spike_str = " *** BAD WATER SPIKE ***" if spike else ""
                    print(
                        f"[{datetime.now().strftime('%H:%M:%S')}] "
                        f"Level={data['level']:.1f}% | "
                        f"Turb={data['turbidity']:.2f} NTU | "
                        f"pH={data['ph']:.2f} | "
                        f"TDS={data['tds']:.0f} ppm | "
                        f"{pump_str}{spike_str}"
                    )

                    # Listen briefly for commands forwarded from backend (pump_command, etc.)
                    try:
                        msg = await asyncio.wait_for(websocket.recv(), timeout=4.5)
                        cmd = json.loads(msg)
                        if cmd.get("type") == "pump_command":
                            action = cmd.get("action", "off")  # "on" or "off"
                            duration = int(cmd.get("duration_seconds", 0))
                            if action == "on":
                                _pump_manual_on = True
                                _pump_manual_remaining = duration
                                print(
                                    f"[{DEVICE_ID}] ▶ PUMP ON (manual, {duration}s)"
                                )
                            else:
                                _pump_manual_on = False
                                _pump_manual_remaining = 0
                                print(f"[{DEVICE_ID}] ■ PUMP OFF (manual command)")

                            # Echo back pump_update so the app can confirm
                            ack = {
                                "type": "sensor_data",
                                "device_id": DEVICE_ID,
                                "pump_active": _pump_manual_on,
                                "pump_manual": _pump_manual_on,
                                "pump_remaining": _pump_manual_remaining,
                                # Re-send last known values so state doesn't reset
                                "level": data["level"],
                                "volume": data["volume"],
                                "capacity": 50000,
                                "flow_rate": data["flow_rate"],
                                "turbidity": data["turbidity"],
                                "ph": data["ph"],
                                "tds": data["tds"],
                                "temperature": data["temperature"],
                                "timestamp": datetime.now().isoformat(),
                            }
                            await websocket.send(json.dumps(ack))
                    except asyncio.TimeoutError:
                        pass

                    await asyncio.sleep(5)  # 5 s interval → ~12 readings/min

        except Exception as e:
            print(f"[{DEVICE_ID}] Error: {e}. Reconnecting in 5 s...")
            await asyncio.sleep(5)


if __name__ == "__main__":
    asyncio.run(send_sensor_data())

