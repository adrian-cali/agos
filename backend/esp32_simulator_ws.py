import asyncio
import websockets
import json
import random
from datetime import datetime

WS_URL = "ws://localhost:8000/ws/sensor"


def generate_sensor_data():
    return {
        "type": "sensor_data",
        "level": random.uniform(65, 72),
        "volume": random.uniform(32000, 36000),
        "capacity": 50000,
        "flow_rate": random.uniform(140, 150),
        "turbidity": random.uniform(125, 135),
        "ph": random.uniform(7.2, 7.6),
        "tds": random.uniform(340, 355),
        "temperature": random.uniform(20, 30),
        "timestamp": datetime.now().isoformat()
    }


async def send_sensor_data():
    while True:
        try:
            async with websockets.connect(WS_URL) as websocket:
                print("Connected to WebSocket server\n")

                while True:
                    data = generate_sensor_data()
                    await websocket.send(json.dumps(data))
                    print(f"Sent: Level={data['level']:.1f}%, Flow={data['flow_rate']:.1f}L/min")

                    await asyncio.sleep(5)

        except Exception as e:
            print(f"Error: {e}. Reconnecting...")
            await asyncio.sleep(5)


if __name__ == "__main__":
    asyncio.run(send_sensor_data())
