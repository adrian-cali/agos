from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from typing import List, Set, Optional
from datetime import datetime, timedelta
import asyncio
import random
import logging
import os
import time
import firebase_admin
from firebase_admin import credentials, firestore

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ============= FIREBASE INIT =============

_SERVICE_ACCOUNT_PATH = os.path.join(os.path.dirname(__file__), "serviceAccountKey.json")
_SERVICE_ACCOUNT_JSON_ENV = os.environ.get("FIREBASE_SERVICE_ACCOUNT_JSON")

def _init_firebase():
    """Initialize Firebase from file (local) or environment variable (deployed)."""
    import json as _json
    if os.path.exists(_SERVICE_ACCOUNT_PATH):
        return credentials.Certificate(_SERVICE_ACCOUNT_PATH)
    if _SERVICE_ACCOUNT_JSON_ENV:
        try:
            cert_dict = _json.loads(_SERVICE_ACCOUNT_JSON_ENV)
            return credentials.Certificate(cert_dict)
        except Exception as e:
            logger.error(f"Failed to parse FIREBASE_SERVICE_ACCOUNT_JSON: {e}")
    return None

_cred = _init_firebase()
if _cred:
    firebase_admin.initialize_app(_cred)
    db = firestore.client()
    FIREBASE_ENABLED = True
    logger.info("Firebase Admin SDK initialized.")
else:
    db = None
    FIREBASE_ENABLED = False
    logger.warning("No Firebase credentials found — running without Firebase persistence.")

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
            "turbidity_min": 10.0,
            "turbidity_max": 50.0,
            "ph_min": 6.5,
            "ph_max": 8.3,
            "tds_max": 500.0
        }
    },
    # Pump runtime state — updated when pump_command is received or sensor reports back
    "pump": {
        "pump_on": False,
        "manual": False,
        "remaining_seconds": 0,
        "last_command": None,
    },
}

# Historical data storage
historical_data = {
    "turbidity": [],
    "ph": [],
    "tds": []
}


def generate_historical_data():
    """Generate mock historical data: 5-minute intervals for last 24h, hourly for older data."""
    now = datetime.now()

    for metric in ["turbidity", "ph", "tds"]:
        historical_data[metric] = []

        # Dense: 5-minute intervals for the last 24 hours (288 points)
        for i in range(288):
            timestamp = now - timedelta(minutes=(288 - i) * 5)
            if metric == "turbidity":
                value = random.uniform(1.5, 4.5)
            elif metric == "ph":
                value = random.uniform(6.8, 7.6)
            else:
                value = random.uniform(200, 450)
            historical_data[metric].append({
                "timestamp": timestamp.isoformat(),
                "value": round(value, 2)
            })

        # Sparse: hourly for days 2-30
        for i in range(1, 30 * 24):  # skip first 24h (already covered above)
            timestamp = now - timedelta(hours=(30 * 24 - i))
            if timestamp >= now - timedelta(hours=24):
                continue  # skip overlap

            if metric == "turbidity":
                value = random.uniform(1.5, 4.5)
            elif metric == "ph":
                value = random.uniform(6.8, 7.6)
            else:  # tds
                value = random.uniform(200, 450)

            historical_data[metric].append({
                "timestamp": timestamp.isoformat(),
                "value": round(value, 2)
            })


# Generate historical data on startup
generate_historical_data()

# ============= FIRESTORE WRITE THROTTLE =============
# Free-tier quota: 20,000 writes/day.
#
# Two throttle intervals:
#   FIRESTORE_WRITE_INTERVAL_S  = 15 s → sensor_readings.add()
#       1 device  : 86400/15 = 5,760/day
#       2 devices : 11,520/day  (58% of 20k) ✅
#
#   DEVICE_UPDATE_INTERVAL_S    = 60 s → devices.set() last_seen
#       1 device  : 86400/60 = 1,440/day
#       2 devices : 2,880/day  (14% of 20k) ✅
#
#   Both sensors running → total ≈ 11,520 + 2,880 = 14,400/day  (72% of 20k) ✅ safe

FIRESTORE_WRITE_INTERVAL_S = 15    # sensor_readings — every 15 s
DEVICE_UPDATE_INTERVAL_S   = 60    # devices last_seen — every 60 s

_last_firestore_write:  dict[str, datetime] = {}   # device_id → last sensor_readings write
_last_device_update:    dict[str, datetime] = {}   # device_id → last devices.set() write


def _should_write_firestore(device_id: str) -> bool:
    """Return True if enough time has passed since the last sensor_readings write for this device."""
    last = _last_firestore_write.get(device_id)
    if last is None or (datetime.now() - last).total_seconds() >= FIRESTORE_WRITE_INTERVAL_S:
        _last_firestore_write[device_id] = datetime.now()
        return True
    return False


def _should_update_device(device_id: str) -> bool:
    """Return True if enough time has passed since the last devices.set() write for this device."""
    last = _last_device_update.get(device_id)
    if last is None or (datetime.now() - last).total_seconds() >= DEVICE_UPDATE_INTERVAL_S:
        _last_device_update[device_id] = datetime.now()
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

        # Send state snapshot (includes current pump state)
        await websocket.send_json({
            "type": "state_snapshot",
            "timestamp": datetime.now().isoformat(),
            "tank_data": state["tank_data"],
            "water_quality": state["water_quality"],
            "alerts": state["alerts"],
            "devices": state["devices"],
            "pump": state["pump"],
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

    turb_min = thresholds.get("turbidity_min", 0.0)
    state["water_quality"]["turbidity"]["status"] = (
        "optimal" if turb_min <= turb <= thresholds["turbidity_max"] else "warning"
    )
    state["water_quality"]["ph"]["status"] = (
        "optimal" if thresholds["ph_min"] <= ph <= thresholds["ph_max"] else "warning"
    )
    state["water_quality"]["tds"]["status"] = (
        "optimal" if tds <= thresholds["tds_max"] else "warning"
    )

    # Threshold alerts
    alert_messages = []
    turb_min = thresholds.get("turbidity_min", 0.0)
    if not (turb_min <= turb <= thresholds["turbidity_max"]):
        alert_messages.append(f"Turbidity {round(turb)} NTU out of range {round(turb_min)}–{round(thresholds['turbidity_max'])} NTU")
    if not (thresholds["ph_min"] <= ph <= thresholds["ph_max"]):
        alert_messages.append(f"pH {ph:.1f} out of range {thresholds['ph_min']:.1f}–{thresholds['ph_max']:.1f}")
    if tds > thresholds["tds_max"]:
        alert_messages.append(f"TDS {round(tds)} ppm exceeds threshold {round(thresholds['tds_max'])} ppm")
    if level < 20:
        alert_messages.append(f"Water level critically low: {level:.1f}%")

    for msg in alert_messages:
        alert = {
            "id": f"thresh_{int(time.time()*1000)}_{len(state['alerts'])}",
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
            logger.info(f"[Firestore] Wrote sensor reading for {device_id}: turb={turb:.2f}")
        except Exception as e:
            logger.error(f"Firestore sensor_readings write error: {e}")

    # Device last_seen update (throttled separately — once every DEVICE_UPDATE_INTERVAL_S seconds)
    if FIREBASE_ENABLED and db is not None and _should_update_device(device_id):
        try:
            db.collection("devices").document(device_id).set({
                "last_seen": firestore.SERVER_TIMESTAMP,
                "status": "connected",
                "level": state["tank_data"]["level"],
                "pump_active": pump_active,
            }, merge=True)
            logger.info(f"[Firestore] Updated device last_seen for {device_id}")
        except Exception as e:
            logger.error(f"Firestore devices.set error: {e}")

    await manager.broadcast_to_apps({
        "type": "tank_update",
        "timestamp": datetime.now().isoformat(),
        "data": state["tank_data"]
    })

    await manager.broadcast_to_apps({
        "type": "quality_update",
        "timestamp": datetime.now().isoformat(),
        "device_id": device_id,
        "data": state["water_quality"]
    })

    logger.info(
        f"[{device_id}] Level={level:.1f}% | "
        f"Turb={turb:.1f} | pH={ph:.1f} | TDS={tds:.0f} | "
        f"Pump={'ON' if pump_active else 'OFF'}"
    )


async def handle_alert(data: dict):
    alert = {
        "id": f"alert_{int(time.time()*1000)}_{len(state['alerts'])}",
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


async def handle_update_thresholds(data: dict):
    """Update the in-memory thresholds used for alert generation."""
    t = state["settings"]["thresholds"]
    if "turbidity_min" in data:
        t["turbidity_min"] = float(data["turbidity_min"])
    if "turbidity_max" in data:
        t["turbidity_max"] = float(data["turbidity_max"])
    if "ph_min" in data:
        t["ph_min"] = float(data["ph_min"])
    if "ph_max" in data:
        t["ph_max"] = float(data["ph_max"])
    if "tds_max" in data:
        t["tds_max"] = float(data["tds_max"])
    # Update target strings so state_snapshot reflects user thresholds
    turb_min = t.get("turbidity_min", 0.0)
    state["water_quality"]["turbidity"]["target"] = f"{turb_min:.0f}–{t['turbidity_max']:.0f} NTU"
    state["water_quality"]["ph"]["target"] = f"{t['ph_min']:.1f}–{t['ph_max']:.1f}"
    state["water_quality"]["tds"]["target"] = f"<{t['tds_max']:.0f} ppm"
    logger.info(f"Thresholds updated: {t}")


async def handle_get_history(data: dict, websocket: WebSocket):
    """Handle historical data request with period filtering"""
    metric = data.get("metric", "turbidity")
    period = data.get("period", "24h")

    now = datetime.now()

    if period == "1h":
        cutoff = now - timedelta(hours=1)
    elif period == "24h":
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


# active pump countdown task handle
_pump_countdown_task: Optional[asyncio.Task] = None


async def _pump_countdown_loop(duration_seconds: int):
    """Server-side countdown that broadcasts pump_update every second."""
    remaining = duration_seconds
    while remaining > 0:
        await asyncio.sleep(1)
        remaining -= 1
        state["pump"]["remaining_seconds"] = remaining
        await manager.broadcast_to_apps({
            "type": "pump_update",
            "pump_on": True,
            "manual": True,
            "remaining_seconds": remaining,
            "timestamp": datetime.now().isoformat(),
        })

    # Timer expired → auto-off
    state["pump"].update({"pump_on": False, "manual": False, "remaining_seconds": 0})
    # Forward off command to sensors
    off_msg = {
        "type": "pump_command",
        "action": "off",
        "duration_seconds": 0,
        "source": "timer_expired",
        "timestamp": datetime.now().isoformat(),
    }
    disconnected = set()
    for conn in manager.sensor_connections:
        try:
            await conn.send_json(off_msg)
        except Exception:
            disconnected.add(conn)
    for c in disconnected:
        manager.sensor_connections.discard(c)

    await manager.broadcast_to_apps({
        "type": "pump_update",
        "pump_on": False,
        "manual": False,
        "remaining_seconds": 0,
        "timestamp": datetime.now().isoformat(),
    })
    logger.info("Pump auto-off: timer expired")


async def handle_pump_command(data: dict):
    """
    Received from the Flutter app over /ws/app.
    Forwards the command to all connected ESP32 sensors and
    broadcasts a pump_update back to all apps.
    """
    global _pump_countdown_task

    action = data.get("action", "off")  # "on" or "off"
    duration_seconds = int(data.get("duration_seconds", 0))
    is_on = action == "on"

    # Cancel any running countdown
    if _pump_countdown_task and not _pump_countdown_task.done():
        _pump_countdown_task.cancel()
        _pump_countdown_task = None

    # Update server pump state
    state["pump"].update({
        "pump_on": is_on,
        "manual": is_on,
        "remaining_seconds": duration_seconds if is_on else 0,
        "last_command": datetime.now().isoformat(),
    })

    # Forward to every connected sensor (ESP32)
    forward_msg = {
        "type": "pump_command",
        "action": action,
        "duration_seconds": duration_seconds,
        "timestamp": datetime.now().isoformat(),
    }
    disconnected = set()
    for conn in manager.sensor_connections:
        try:
            await conn.send_json(forward_msg)
        except Exception:
            disconnected.add(conn)
    for c in disconnected:
        manager.sensor_connections.discard(c)

    # Log to Firestore (optional)
    if FIREBASE_ENABLED and db is not None:
        try:
            db.collection("pump_commands").add({
                "action": action,
                "duration_seconds": duration_seconds,
                "source": "app",
                "timestamp": firestore.SERVER_TIMESTAMP,
            })
        except Exception as e:
            logger.error(f"Firestore pump log error: {e}")

    # Broadcast pump_update to all app clients
    await manager.broadcast_to_apps({
        "type": "pump_update",
        "pump_on": is_on,
        "manual": is_on,
        "remaining_seconds": duration_seconds if is_on else 0,
        "timestamp": datetime.now().isoformat(),
    })

    # Start server-side countdown if turning on with a duration
    if is_on and duration_seconds > 0:
        _pump_countdown_task = asyncio.create_task(
            _pump_countdown_loop(duration_seconds)
        )

    logger.info(
        f"Pump command: action={action}, duration={duration_seconds}s, "
        f"sensors_forwarded={len(manager.sensor_connections)}"
    )


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
            elif msg_type == "update_thresholds":
                await handle_update_thresholds(data)
            elif msg_type == "get_state":
                await websocket.send_json({
                    "type": "state_snapshot",
                    "timestamp": datetime.now().isoformat(),
                    "tank_data": state["tank_data"],
                    "water_quality": state["water_quality"],
                    "alerts": state["alerts"],
                    "devices": state["devices"],
                    "pump": state["pump"],
                })
            elif msg_type == "get_history":
                await handle_get_history(data, websocket)
            elif msg_type == "pump_command":
                await handle_pump_command(data)
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
