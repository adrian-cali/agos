from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from typing import List, Set
from datetime import datetime, timedelta
import asyncio
import random
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="AGOS WebSocket Server", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ============= STATE =============

state = {
    "tank_data": {
        "level": 68.0,
        "volume": 33934.0,
        "capacity": 50000.0,
        "flow_rate": 145.0,
        "status": "moderate",
        "timestamp": datetime.now().isoformat()
    },
    "water_quality": {
        "turbidity": {"value": 131.0, "unit": "NTU", "status": "optimal", "target": "<5 NTU"},
        "ph": {"value": 7.4, "unit": "", "status": "optimal", "target": "6.5-8.3"},
        "tds": {"value": 347.0, "unit": "ppm", "status": "optimal", "target": "<500 ppm"}
    },
    "alerts": [
        {
            "id": "1",
            "type": "water_quality",
            "title": "Water Quality Alert",
            "description": "All parameters within acceptable range",
            "timestamp": datetime.now().isoformat(),
            "is_read": False,
            "severity": "info"
        }
    ],
    "devices": [
        {
            "id": "AGOS-A1B2",
            "name": "Main Tank Monitor",
            "status": "connected",
            "last_seen": datetime.now().isoformat()
        }
    ],
    "settings": {
        "thresholds": {
            "turbidity_max": 5.0,
            "ph_min": 6.5,
            "ph_max": 8.3,
            "tds_max": 500.0
        }
    }
}

# Historical data storage
historical_data = {
    "turbidity": [],
    "ph": [],
    "tds": []
}


def generate_historical_data():
    """Generate mock historical data for 30 days"""
    now = datetime.now()

    for metric in ["turbidity", "ph", "tds"]:
        historical_data[metric] = []
        for i in range(30 * 24):  # 30 days * 24 hours
            timestamp = now - timedelta(hours=(30 * 24 - i))

            if metric == "turbidity":
                value = random.uniform(125, 135)
            elif metric == "ph":
                value = random.uniform(7.2, 7.6)
            else:  # tds
                value = random.uniform(340, 355)

            historical_data[metric].append({
                "timestamp": timestamp.isoformat(),
                "value": round(value, 1)
            })


# Generate historical data on startup
generate_historical_data()

# ============= CONNECTION MANAGER =============


class ConnectionManager:
    def __init__(self):
        self.sensor_connections: Set[WebSocket] = set()
        self.app_connections: Set[WebSocket] = set()

    async def connect_sensor(self, websocket: WebSocket):
        await websocket.accept()
        self.sensor_connections.add(websocket)
        logger.info(f"Sensor connected. Total: {len(self.sensor_connections)}")

    async def connect_app(self, websocket: WebSocket):
        await websocket.accept()
        self.app_connections.add(websocket)
        logger.info(f"App connected. Total: {len(self.app_connections)}")

        # Send state snapshot
        await websocket.send_json({
            "type": "state_snapshot",
            "timestamp": datetime.now().isoformat(),
            "tank_data": state["tank_data"],
            "water_quality": state["water_quality"],
            "alerts": state["alerts"],
            "devices": state["devices"]
        })

    def disconnect_sensor(self, websocket: WebSocket):
        self.sensor_connections.discard(websocket)
        logger.info(f"Sensor disconnected. Total: {len(self.sensor_connections)}")

    def disconnect_app(self, websocket: WebSocket):
        self.app_connections.discard(websocket)
        logger.info(f"App disconnected. Total: {len(self.app_connections)}")

    async def broadcast_to_apps(self, message: dict):
        disconnected = set()
        for connection in self.app_connections:
            try:
                await connection.send_json(message)
            except Exception:
                disconnected.add(connection)
        for conn in disconnected:
            self.app_connections.discard(conn)


manager = ConnectionManager()

# ============= HANDLERS =============


async def handle_sensor_data(data: dict):
    state["tank_data"].update({
        "level": data.get("level", state["tank_data"]["level"]),
        "volume": data.get("volume", state["tank_data"]["volume"]),
        "flow_rate": data.get("flow_rate", state["tank_data"]["flow_rate"]),
        "timestamp": datetime.now().isoformat()
    })

    level = state["tank_data"]["level"]
    state["tank_data"]["status"] = "optimal" if level >= 75 else "moderate" if level >= 50 else "low"

    if "turbidity" in data:
        state["water_quality"]["turbidity"]["value"] = data["turbidity"]
        historical_data["turbidity"].append({
            "timestamp": datetime.now().isoformat(),
            "value": round(data["turbidity"], 1)
        })
        cutoff = datetime.now() - timedelta(days=30)
        historical_data["turbidity"] = [
            d for d in historical_data["turbidity"]
            if datetime.fromisoformat(d["timestamp"]) > cutoff
        ]

    if "ph" in data:
        state["water_quality"]["ph"]["value"] = data["ph"]
        historical_data["ph"].append({
            "timestamp": datetime.now().isoformat(),
            "value": round(data["ph"], 1)
        })
        cutoff = datetime.now() - timedelta(days=30)
        historical_data["ph"] = [
            d for d in historical_data["ph"]
            if datetime.fromisoformat(d["timestamp"]) > cutoff
        ]

    if "tds" in data:
        state["water_quality"]["tds"]["value"] = data["tds"]
        historical_data["tds"].append({
            "timestamp": datetime.now().isoformat(),
            "value": round(data["tds"], 1)
        })
        cutoff = datetime.now() - timedelta(days=30)
        historical_data["tds"] = [
            d for d in historical_data["tds"]
            if datetime.fromisoformat(d["timestamp"]) > cutoff
        ]

    await manager.broadcast_to_apps({
        "type": "tank_update",
        "timestamp": datetime.now().isoformat(),
        "data": state["tank_data"]
    })

    await manager.broadcast_to_apps({
        "type": "quality_update",
        "timestamp": datetime.now().isoformat(),
        "data": state["water_quality"]
    })

    logger.info(f"Data: Level={level:.1f}%, Flow={state['tank_data']['flow_rate']:.1f}")


async def handle_alert(data: dict):
    alert = {
        "id": str(len(state["alerts"]) + 1),
        "type": data.get("alert_type", "unknown"),
        "title": data.get("title", "Alert"),
        "description": data.get("description", ""),
        "timestamp": datetime.now().isoformat(),
        "is_read": False,
        "severity": data.get("severity", "info")
    }
    state["alerts"].append(alert)

    await manager.broadcast_to_apps({
        "type": "system_alert",
        "timestamp": datetime.now().isoformat(),
        "alert": alert
    })


async def handle_delete_alert(data: dict):
    alert_id = data.get("alert_id")
    state["alerts"] = [a for a in state["alerts"] if a["id"] != alert_id]

    await manager.broadcast_to_apps({
        "type": "alerts_updated",
        "timestamp": datetime.now().isoformat(),
        "alerts": state["alerts"]
    })


async def handle_get_history(data: dict, websocket: WebSocket):
    """Handle historical data request with period filtering"""
    metric = data.get("metric", "turbidity")
    period = data.get("period", "24h")

    now = datetime.now()

    if period == "24h":
        cutoff = now - timedelta(hours=24)
    elif period == "7d":
        cutoff = now - timedelta(days=7)
    else:  # 30d
        cutoff = now - timedelta(days=30)

    filtered_data = [
        d for d in historical_data.get(metric, [])
        if datetime.fromisoformat(d["timestamp"]) > cutoff
    ]

    await websocket.send_json({
        "type": "historical_data",
        "metric": metric,
        "period": period,
        "data": filtered_data,
        "timestamp": datetime.now().isoformat()
    })

    logger.info(f"Historical data sent: {metric} - {period} ({len(filtered_data)} points)")


# ============= WEBSOCKET ENDPOINTS =============

@app.get("/")
async def root():
    return {
        "message": "AGOS WebSocket Server",
        "version": "1.0.0",
        "status": "running",
        "connections": {
            "sensors": len(manager.sensor_connections),
            "apps": len(manager.app_connections)
        }
    }


@app.websocket("/ws/sensor")
async def websocket_sensor(websocket: WebSocket):
    await manager.connect_sensor(websocket)
    try:
        while True:
            data = await websocket.receive_json()
            msg_type = data.get("type")

            if msg_type == "sensor_data":
                await handle_sensor_data(data)
            elif msg_type == "alert":
                await handle_alert(data)
            elif msg_type == "heartbeat":
                await websocket.send_json({
                    "type": "heartbeat_ack",
                    "timestamp": datetime.now().isoformat()
                })
    except WebSocketDisconnect:
        manager.disconnect_sensor(websocket)


@app.websocket("/ws/app")
async def websocket_app(websocket: WebSocket):
    await manager.connect_app(websocket)
    try:
        while True:
            data = await websocket.receive_json()
            msg_type = data.get("type")

            if msg_type == "delete_alert":
                await handle_delete_alert(data)
            elif msg_type == "get_state":
                await websocket.send_json({
                    "type": "state_snapshot",
                    "timestamp": datetime.now().isoformat(),
                    "tank_data": state["tank_data"],
                    "water_quality": state["water_quality"],
                    "alerts": state["alerts"],
                    "devices": state["devices"]
                })
            elif msg_type == "get_history":
                await handle_get_history(data, websocket)
            elif msg_type == "heartbeat":
                await websocket.send_json({
                    "type": "heartbeat_ack",
                    "timestamp": datetime.now().isoformat()
                })
    except WebSocketDisconnect:
        manager.disconnect_app(websocket)


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000, log_level="info")
