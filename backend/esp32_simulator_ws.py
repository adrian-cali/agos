import asyncio
import websockets
import json
import random
from datetime import datetime

WS_URL = "ws://localhost:8000/ws/sensor"
DEVICE_ID = "esp32-sim-001"

# bad-water spike state
_spike_counter = 0  # increments every reading (5 s each); spike every ~60 readings (~5 min)
_SPIKE_INTERVAL = 60


def generate_sensor_data(spike: bool = False) -> dict:
    if spike:
        turbidity = random.uniform(8.0, 15.0)   # exceeds 5 NTU threshold
        ph = random.uniform(5.0, 6.0)            # below 6.5 threshold
        tds = random.uniform(520, 650)            # exceeds 500 ppm threshold
    else:
        turbidity = random.uniform(1.5, 4.5)
        ph = random.uniform(6.8, 7.8)
        tds = random.uniform(200, 450)

    pump_active = turbidity > 5 or not (6.5 <= ph <= 8.3) or tds > 500

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
    global _spike_counter

    while True:
        try:
            async with websockets.connect(WS_URL) as websocket:
                print(f"[{DEVICE_ID}] Connected to WebSocket server\n")

                while True:
                    _spike_counter += 1
                    spike = (_spike_counter % _SPIKE_INTERVAL == 0)
                    data = generate_sensor_data(spike=spike)
                    await websocket.send(json.dumps(data))

                    pump_str = "PUMP:ON " if data["pump_active"] else "PUMP:OFF"
                    spike_str = " *** BAD WATER SPIKE ***" if spike else ""
                    print(
                        f"[{datetime.now().strftime('%H:%M:%S')}] "
                        f"Level={data['level']:.1f}% | "
                        f"Turb={data['turbidity']:.2f} NTU | "
                        f"pH={data['ph']:.2f} | "
                        f"TDS={data['tds']:.0f} ppm | "
                        f"{pump_str}{spike_str}"
                    )

                    # Listen briefly for pump commands from backend
                    try:
                        msg = await asyncio.wait_for(websocket.recv(), timeout=4.5)
                        cmd = json.loads(msg)
                        if cmd.get("type") == "pump_command":
                            action = cmd.get("command", "")
                            print(f"[{DEVICE_ID}] Received pump command: {action.upper()}")
                    except asyncio.TimeoutError:
                        pass

                    await asyncio.sleep(5)  # 5 s interval → ~12 readings/min

        except Exception as e:
            print(f"[{DEVICE_ID}] Error: {e}. Reconnecting in 5 s...")
            await asyncio.sleep(5)


if __name__ == "__main__":
    asyncio.run(send_sensor_data())

