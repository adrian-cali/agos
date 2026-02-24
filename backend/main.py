from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from typing import List, Set, Optional
from datetime import datetime, timedelta
import asyncio
import random
import logging
import os
import firebase_admin
from firebase_admin import credentials, firestore

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ============= FIREBASE INIT =============

_SERVICE_ACCOUNT_PATH = os.path.join(os.path.dirname(__file__), "serviceAccountKey.json")

if os.path.exists(_SERVICE_ACCOUNT_PATH):
    cred = credentials.Certificate(_SERVICE_ACCOUNT_PATH)
    firebase_admin.initialize_app(cred)
    db = firestore.client()
    FIREBASE_ENABLED = True
    logger.info("Firebase Admin SDK initialized.")
else:
    db = None
    FIREBASE_ENABLED = False
    logger.warning("serviceAccountKey.json not found — running without Firebase persistence.")

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

# ============= FIRESTORE WRITE THROTTLE =============
# Only write to Firestore once every FIRESTORE_WRITE_INTERVAL_S seconds per device.
# Free-tier quota: 20,000 writes/day (~13/min). At 30 s interval we use ~2,880/day.
FIRESTORE_WRITE_INTERVAL_S = 30
_last_firestore_write: dict[str, datetime] = {}   # device_id → last write time


def _should_write_firestore(device_id: str) -> bool:
    """Return True if enough time has passed since the last Firestore write for this device."""
    last = _last_firestore_write.get(device_id)
    if last is None or (datetime.now() - last).total_seconds() >= FIRESTORE_WRITE_INTERVAL_S:
        _last_firestore_write[device_id] = datetime.now()
        return True
    return False


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
    device_id = data.get("device_id", "unknown")
    pump_active = data.get("pump_active", False)

    state["tank_data"].update({
        "level": data.get("level", state["tank_data"]["level"]),
        "volume": data.get("volume", state["tank_data"]["volume"]),
        "flow_rate": data.get("flow_rate", state["tank_data"]["flow_rate"]),
        "pump_active": pump_active,
        "timestamp": datetime.now().isoformat()
    })

    level = state["tank_data"]["level"]
    state["tank_data"]["status"] = "optimal" if level >= 75 else "moderate" if level >= 50 else "low"

    thresholds = state["settings"]["thresholds"]

    for metric in ("turbidity", "ph", "tds"):
        if metric not in data:
            continue
        value = data[metric]
        state["water_quality"][metric]["value"] = value
        historical_data[metric].append({
            "timestamp": datetime.now().isoformat(),
            "value": round(value, 1)
        })
        cutoff = datetime.now() - timedelta(days=30)
        historical_data[metric] = [
            d for d in historical_data[metric]
            if datetime.fromisoformat(d["timestamp"]) > cutoff
        ]

    # Determine water quality statuses
    turb = state["water_quality"]["turbidity"]["value"]
    ph = state["water_quality"]["ph"]["value"]
    tds = state["water_quality"]["tds"]["value"]

    state["water_quality"]["turbidity"]["status"] = (
        "optimal" if turb <= thresholds["turbidity_max"] else "critical"
    )
    state["water_quality"]["ph"]["status"] = (
        "optimal" if thresholds["ph_min"] <= ph <= thresholds["ph_max"] else "critical"
    )
    state["water_quality"]["tds"]["status"] = (
        "optimal" if tds <= thresholds["tds_max"] else "critical"
    )

    # Threshold alerts
    alert_messages = []
    if turb > thresholds["turbidity_max"]:
        alert_messages.append(f"Turbidity {turb:.1f} NTU exceeds threshold {thresholds['turbidity_max']} NTU")
    if not (thresholds["ph_min"] <= ph <= thresholds["ph_max"]):
        alert_messages.append(f"pH {ph:.1f} out of range {thresholds['ph_min']}–{thresholds['ph_max']}")
    if tds > thresholds["tds_max"]:
        alert_messages.append(f"TDS {tds:.0f} ppm exceeds threshold {thresholds['tds_max']} ppm")
    if level < 20:
        alert_messages.append(f"Water level critically low: {level:.1f}%")

    for msg in alert_messages:
        alert = {
            "id": str(len(state["alerts"]) + 1),
            "type": "threshold_exceeded",
            "title": "Water Quality Alert",
            "description": msg,
            "timestamp": datetime.now().isoformat(),
            "is_read": False,
            "severity": "warning"
        }
        state["alerts"].append(alert)
        await manager.broadcast_to_apps({
            "type": "system_alert",
            "timestamp": datetime.now().isoformat(),
            "alert": alert
        })

    # Firestore write (throttled — at most once every FIRESTORE_WRITE_INTERVAL_S seconds)
    if FIREBASE_ENABLED and db is not None and _should_write_firestore(device_id):
        try:
            reading_doc = {
                "device_id": device_id,
                "timestamp": firestore.SERVER_TIMESTAMP,
                "level": state["tank_data"]["level"],
                "volume": state["tank_data"]["volume"],
                "flow_rate": state["tank_data"]["flow_rate"],
                "pump_active": pump_active,
                "turbidity": turb,
                "ph": ph,
                "tds": tds,
                "status": state["tank_data"]["status"],
            }
            db.collection("sensor_readings").add(reading_doc)

            # Update device last_seen
            db.collection("devices").document(device_id).set({
                "last_seen": firestore.SERVER_TIMESTAMP,
                "status": "connected",
                "level": state["tank_data"]["level"],
                "pump_active": pump_active,
            }, merge=True)
        except Exception as e:
            logger.error(f"Firestore write error: {e}")

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

    logger.info(
        f"[{device_id}] Level={level:.1f}% | "
        f"Turb={turb:.1f} | pH={ph:.1f} | TDS={tds:.0f} | "
        f"Pump={'ON' if pump_active else 'OFF'}"
    )


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


# ============= HTTP ENDPOINTS =============

@app.get("/")
async def root():
    return {
        "message": "AGOS WebSocket Server",
        "version": "1.0.0",
        "status": "running",
        "firebase": FIREBASE_ENABLED,
        "connections": {
            "sensors": len(manager.sensor_connections),
            "apps": len(manager.app_connections)
        }
    }


@app.post("/devices/register")
async def register_device(payload: dict):
    """Register a new AGOS device (called from Flutter after pairing)."""
    device_id = payload.get("device_id")
    if not device_id:
        raise HTTPException(status_code=400, detail="device_id is required")

    device_doc = {
        "device_id": device_id,
        "name": payload.get("name", f"AGOS Device {device_id[-4:]}"),
        "owner_uid": payload.get("owner_uid"),
        "registered_at": datetime.now().isoformat(),
        "status": "registered",
    }

    # Add to in-memory state
    existing_ids = {d["id"] for d in state["devices"]}
    if device_id not in existing_ids:
        state["devices"].append({
            "id": device_id,
            "name": device_doc["name"],
            "status": "registered",
            "last_seen": datetime.now().isoformat()
        })

    # Persist to Firestore
    if FIREBASE_ENABLED and db is not None:
        try:
            db.collection("devices").document(device_id).set(device_doc, merge=True)
        except Exception as e:
            logger.error(f"Firestore device register error: {e}")

    logger.info(f"Device registered: {device_id}")
    return {"status": "ok", "device_id": device_id}


@app.post("/pump/control")
async def pump_control(payload: dict):
    """Send a pump on/off command to the connected sensor."""
    device_id = payload.get("device_id")
    command = payload.get("command")  # "on" or "off"

    if command not in ("on", "off"):
        raise HTTPException(status_code=400, detail="command must be 'on' or 'off'")

    msg = {
        "type": "pump_command",
        "device_id": device_id,
        "command": command,
        "timestamp": datetime.now().isoformat()
    }

    # Log to Firestore
    if FIREBASE_ENABLED and db is not None:
        try:
            db.collection("pump_commands").add({
                **msg,
                "timestamp": firestore.SERVER_TIMESTAMP,
            })
        except Exception as e:
            logger.error(f"Firestore pump command error: {e}")

    # Broadcast to sensor connections so ESP32 simulator can pick it up
    disconnected = set()
    for conn in manager.sensor_connections:
        try:
            await conn.send_json(msg)
        except Exception:
            disconnected.add(conn)
    for c in disconnected:
        manager.sensor_connections.discard(c)

    await manager.broadcast_to_apps(msg)
    logger.info(f"Pump command sent: {command} → {device_id}")
    return {"status": "ok", "command": command}


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
