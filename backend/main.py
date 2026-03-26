from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from typing import List, Set, Optional
from datetime import datetime, timedelta
import asyncio
import random
import logging
import os
import time
import json
import firebase_admin
from firebase_admin import credentials, firestore, messaging as fcm_messaging

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
    logger.warning("serviceAccountKey.json not found and FIREBASE_SERVICE_ACCOUNT_JSON not set — running without Firebase persistence.")

app = FastAPI(title="AGOS WebSocket Server", version="1.0.0")

# ============= REDIS CACHE (optional) =============
# If REDIS_URL is set (Render Key Value / any Redis URL), state snapshots are persisted
# every REDIS_SNAPSHOT_INTERVAL_S seconds so restarts restore previous values.
# If Redis is unavailable or unconfigured, the app runs identically without it.

_redis_client = None
_REDIS_STATE_KEY = "agos:state_snapshot"
_REDIS_HIST_KEY  = "agos:historical_data"
REDIS_SNAPSHOT_INTERVAL_S = 30   # save state to Redis every 30 s

def _init_redis():
    """Try to connect to Redis. Returns a redis.Redis client or None."""
    redis_url = os.environ.get("REDIS_URL")
    if not redis_url:
        return None
    try:
        import redis as _redis  # type: ignore[import-not-found]
        client = _redis.from_url(redis_url, decode_responses=True, socket_connect_timeout=3)
        client.ping()  # verify connection
        logger.info("Redis connected.")
        return client
    except Exception as e:
        logger.warning(f"Redis unavailable — running without cache: {e}")
        return None

_redis_client = _init_redis()


def _rollup_doc_id(device_id: str, bucket_start: datetime) -> str:
    return f"{device_id}_{bucket_start.strftime('%Y%m%d%H%M')}"


def _update_rollup_doc(collection_name: str, device_id: str, bucket_start: datetime,
                       level: float, volume: float, flow_rate: float, pump_active: bool,
                       turbidity: float, ph: float, tds: float):
    """Upsert one aggregate bucket document for a device/time window."""
    if not FIREBASE_ENABLED or db is None:
        return

    doc_ref = db.collection(collection_name).document(
        _rollup_doc_id(device_id, bucket_start)
    )
    snapshot = doc_ref.get()
    existing = snapshot.to_dict() if snapshot.exists else None

    count = int(existing.get("count", 0)) + 1 if existing else 1

    def _next_avg(field: str, value: float) -> float:
        if not existing:
            return value
        prev_avg = float(existing.get(field, value))
        prev_count = max(int(existing.get("count", 0)), 1)
        return ((prev_avg * prev_count) + value) / count

    def _next_min(field: str, value: float) -> float:
        return min(float(existing.get(field, value)), value) if existing else value

    def _next_max(field: str, value: float) -> float:
        return max(float(existing.get(field, value)), value) if existing else value

    doc_ref.set({
        "device_id": device_id,
        "bucket_start": bucket_start,
        "count": count,
        "level_avg": _next_avg("level_avg", level),
        "level_min": _next_min("level_min", level),
        "level_max": _next_max("level_max", level),
        "volume_avg": _next_avg("volume_avg", volume),
        "volume_min": _next_min("volume_min", volume),
        "volume_max": _next_max("volume_max", volume),
        "flow_rate_avg": _next_avg("flow_rate_avg", flow_rate),
        "flow_rate_min": _next_min("flow_rate_min", flow_rate),
        "flow_rate_max": _next_max("flow_rate_max", flow_rate),
        "turbidity_avg": _next_avg("turbidity_avg", turbidity),
        "turbidity_min": _next_min("turbidity_min", turbidity),
        "turbidity_max": _next_max("turbidity_max", turbidity),
        "ph_avg": _next_avg("ph_avg", ph),
        "ph_min": _next_min("ph_min", ph),
        "ph_max": _next_max("ph_max", ph),
        "tds_avg": _next_avg("tds_avg", tds),
        "tds_min": _next_min("tds_min", tds),
        "tds_max": _next_max("tds_max", tds),
        "pump_active_count": (int(existing.get("pump_active_count", 0)) if existing else 0)
            + (1 if pump_active else 0),
        "updated_at": firestore.SERVER_TIMESTAMP,
    }, merge=True)


def _update_sensor_rollups(device_id: str, observed_at: datetime,
                           level: float, volume: float, flow_rate: float, pump_active: bool,
                           turbidity: float, ph: float, tds: float):
    hour_bucket = observed_at.replace(minute=0, second=0, microsecond=0)
    day_bucket = observed_at.replace(hour=0, minute=0, second=0, microsecond=0)

    _update_rollup_doc(
        "sensor_rollups_hourly",
        device_id,
        hour_bucket,
        level,
        volume,
        flow_rate,
        pump_active,
        turbidity,
        ph,
        tds,
    )
    _update_rollup_doc(
        "sensor_rollups_daily",
        device_id,
        day_bucket,
        level,
        volume,
        flow_rate,
        pump_active,
        turbidity,
        ph,
        tds,
    )


def _state_to_json(s: dict, h: dict) -> str:
    """Serialise state + historical_data to a JSON string (convert datetimes)."""
    def _default(obj):
        if isinstance(obj, datetime):
            return obj.isoformat()
        raise TypeError(f"Object of type {type(obj)} is not JSON serializable")
    return json.dumps({"state": s, "historical_data": h}, default=_default)


def _restore_from_redis():
    """Load state + historical_data from Redis if available. Mutates globals in place."""
    if _redis_client is None:
        return
    try:
        raw = _redis_client.get(_REDIS_STATE_KEY)
        if not raw:
            return
        payload = json.loads(raw)
        # Restore state fields that are safe to overwrite from cache
        cached_state = payload.get("state", {})
        cached_hist  = payload.get("historical_data", {})

        # Only restore non-connectivity fields — don't restore sensor_connected
        # because the sensor isn't connected at startup
        for key in ("tank_data", "water_quality", "alerts", "devices", "pump", "settings", "uv", "bypass"):
            if key in cached_state:
                state[key] = cached_state[key]
        # Never restore sensor_connected / sensor_last_seen from cache
        # (those are set when the ESP32 actually connects)

        # Restore historical data
        for metric in ("turbidity", "ph", "tds"):
            if metric in cached_hist and cached_hist[metric]:
                historical_data[metric] = cached_hist[metric]

        logger.info("State restored from Redis cache.")
    except Exception as e:
        logger.warning(f"Failed to restore state from Redis: {e}")


async def _redis_snapshot_loop():
    """Background task: persist state to Redis every REDIS_SNAPSHOT_INTERVAL_S seconds."""
    if _redis_client is None:
        return
    while True:
        await asyncio.sleep(REDIS_SNAPSHOT_INTERVAL_S)
        try:
            payload = _state_to_json(state, historical_data)
            _redis_client.set(_REDIS_STATE_KEY, payload, ex=86400 * 2)  # expire after 2 days
        except Exception as e:
            logger.warning(f"Redis snapshot failed: {e}")

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
        "volume": 72.1,
        "capacity": 106.0,
        "flow_rate": 0.0,
        "status": "moderate",
        "timestamp": datetime.now().isoformat()
    },
    "water_quality": {
        "turbidity": {"value": 131.0, "unit": "NTU", "status": "optimal", "target": "<5 NTU"},
        "ph": {"value": 7.4, "unit": "", "status": "optimal", "target": "6.5-8.3"},
        "tds": {"value": 347.0, "unit": "ppm", "status": "optimal", "target": "<500 ppm"}
    },
    "alerts": [],
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
            "turbidity_min": 0.0,    # 0 = accept any turbidity from 0 NTU upward
            "turbidity_max": 50.0,
            "ph_min": 6.0,
            "ph_max": 9.5,
            "tds_max": 1000.0
        }
    },
    # Pump runtime state — updated when pump_command is received or sensor reports back
    "pump": {
        "pump_on": False,
        "manual": False,
        "remaining_seconds": 0,
        "last_command": None,
        "auto_pump_active": None,  # None = not yet determined; True/False = last auto decision
    },
    # UV lamp state — on by default (NC wiring: lamp runs unless user turns it off)
    "uv": {
        "on": True,
    },
    # Bypass pump state and schedule
    "bypass": {
        "pump_on": False,
        "schedule": {"hour": 2, "minute": 0, "duration_seconds": 1800},  # 02:00 AM, 30 min
        "last_run": None,
    },
    # ESP32/sensor connectivity — true when at least one sensor WS is connected
    "sensor_connected": False,
    "sensor_last_seen": None,
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


# Generate historical data on startup, then attempt to overwrite with Redis cache.
# If Redis has a recent snapshot the mock data is replaced with real persisted values.
generate_historical_data()
_restore_from_redis()

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


# ============= FCM PUSH NOTIFICATIONS =============
# Sends a push notification to the device owner when a water-quality or system
# alert threshold is crossed.  Uses per-(device, metric) cooldowns to prevent
# notification spam.
#
# Token lookup flow:
#   1. Check in-memory cache (_fcm_token_cache).
#   2. On a cache miss (or TTL expired) → look up Firestore:
#        devices/{device_id}.owner_uid  →  users/{uid}.fcm_token
#   Token is then cached for _FCM_TOKEN_CACHE_TTL_S seconds.

_FCM_TOKEN_CACHE_TTL_S = 300       # refresh owner token lookup every 5 min
_FCM_ALERT_COOLDOWN_S  = 300       # max 1 push per metric per device per 5 min

# Cache: device_id → (fcm_token, cached_at)
_fcm_token_cache: dict[str, tuple[str, datetime]] = {}

# Cooldown: (device_id, metric) → last push timestamp
_fcm_alert_sent: dict[tuple[str, str], datetime] = {}


def _fcm_should_alert(device_id: str, metric: str) -> bool:
    """Return True if the cooldown has expired and a push may be sent."""
    key = (device_id, metric)
    last = _fcm_alert_sent.get(key)
    if last is None or (datetime.now() - last).total_seconds() >= _FCM_ALERT_COOLDOWN_S:
        _fcm_alert_sent[key] = datetime.now()
        return True
    return False


def _fcm_get_tokens_sync(device_id: str) -> list[str]:
    """
    Blocking helper — looks up ALL FCM tokens for the device:
      1. The owner  (devices/{device_id}.owner_uid → users/{uid}.fcm_token)
      2. Any shared users (devices/{device_id}.shared_uids → each user's fcm_token)

    Called from a thread pool (via asyncio.to_thread) so it doesn't block the
    event loop.  Returns an empty list if Firebase is disabled or no tokens found.
    """
    if not FIREBASE_ENABLED or db is None:
        return []

    # Check cache (cache stores a single "primary" token for quick path)
    cached = _fcm_token_cache.get(device_id)
    if cached:
        token, cached_at = cached
        if (datetime.now() - cached_at).total_seconds() < _FCM_TOKEN_CACHE_TTL_S:
            return [token]

    try:
        device_doc = db.collection("devices").document(device_id).get()
        if not device_doc.exists:
            return []
        device_data = device_doc.to_dict() or {}

        # Collect all UIDs that should receive alerts
        uids: set[str] = set()
        owner_uid: Optional[str] = device_data.get("owner_uid")
        if owner_uid:
            uids.add(owner_uid)
        for uid in device_data.get("shared_uids", []):
            uids.add(uid)

        if not uids:
            return []

        tokens: list[str] = []
        for uid in uids:
            try:
                user_doc = db.collection("users").document(uid).get()
                if user_doc.exists:
                    token = (user_doc.to_dict() or {}).get("fcm_token")
                    if token:
                        tokens.append(token)
            except Exception as e:
                logger.warning(f"[FCM] Token lookup for uid={uid}: {e}")

        # Cache the owner token for the quick-path next time
        if owner_uid and tokens:
            _fcm_token_cache[device_id] = (tokens[0], datetime.now())

        return tokens
    except Exception as e:
        logger.warning(f"[FCM] Token lookup failed for {device_id}: {e}")
        return []


def _fcm_send_sync(token: str, title: str, body: str, data: dict) -> None:
    """Blocking helper — sends an FCM message to a single token.  Called via asyncio.to_thread."""
    try:
        message = fcm_messaging.Message(
            notification=fcm_messaging.Notification(title=title, body=body),
            data={k: str(v) for k, v in data.items()},  # FCM data values must be strings
            token=token,
            android=fcm_messaging.AndroidConfig(
                priority="high",
                notification=fcm_messaging.AndroidNotification(
                    channel_id="agos_alerts",
                    icon="ic_launcher",
                ),
            ),
        )
        fcm_messaging.send(message)
        logger.info(f"[FCM] Sent '{title}' → token ...{token[-8:]}")
    except Exception as e:
        logger.warning(f"[FCM] Send failed (token ...{token[-8:]}): {e}")
        # Invalidate cached token so the next attempt re-fetches.
        for dev_id, (t, _) in list(_fcm_token_cache.items()):
            if t == token:
                _fcm_token_cache.pop(dev_id, None)


async def _fcm_alert(device_id: str, title: str, body: str, metric: str) -> None:
    """
    Fire-and-forget coroutine: look up ALL owner+shared FCM tokens and send
    a push to each.  Runs the blocking Firestore/FCM calls in a thread pool
    so the event loop stays free.
    """
    if not FIREBASE_ENABLED:
        return
    tokens: list[str] = await asyncio.to_thread(_fcm_get_tokens_sync, device_id)
    if not tokens:
        return
    data = {"type": "water_quality_alert", "device_id": device_id, "metric": metric}
    for token in tokens:
        await asyncio.to_thread(_fcm_send_sync, token, title, body, data)


class ConnectionManager:
    def __init__(self):
        self.sensor_connections: Set[WebSocket] = set()
        self.app_connections: Set[WebSocket] = set()
        # Maps each sensor WebSocket → its device_id (set once the first
        # sensor_data message is received for that connection).
        self._sensor_device_ids: dict[WebSocket, str] = {}

    async def connect_sensor(self, websocket: WebSocket):
        await websocket.accept()
        self.sensor_connections.add(websocket)
        now = datetime.now().isoformat()
        state["sensor_connected"] = True
        state["sensor_last_seen"] = now
        logger.info(f"Sensor connected. Total: {len(self.sensor_connections)}")
        await self.broadcast_to_apps({
            "type": "sensor_status",
            "connected": True,
            "last_seen": now,
        })

        # If a manual pump command is active, resend it to the newly connected
        # sensor so the relay is immediately in sync (handles firmware restarts
        # while the pump was running).
        if state["pump"]["manual"] and state["pump"]["pump_on"]:
            await websocket.send_json({
                "type": "pump_command",
                "action": "on",
                "duration_seconds": state["pump"]["remaining_seconds"],
                "source": "manual",
                "reason": "reconnect_sync",
            })

    async def connect_app(self, websocket: WebSocket):
        await websocket.accept()
        self.app_connections.add(websocket)
        logger.info(f"App connected. Total: {len(self.app_connections)}")

        # Send state snapshot (includes current pump state and sensor connectivity)
        # Only include alerts from the last 24 h to avoid stale entries from old sessions
        cutoff = (datetime.now() - timedelta(hours=24)).isoformat()
        recent_alerts = [a for a in state["alerts"] if a.get("timestamp", "") >= cutoff]
        # Only send sensor readings if a sensor is currently connected.
        # When sensor_connected is False, stale Redis-cached values would appear
        # as a false spike reading on first app open, so we send nulls instead.
        sensor_live = state["sensor_connected"]
        await websocket.send_json({
            "type": "state_snapshot",
            "timestamp": datetime.now().isoformat(),
            "tank_data": state["tank_data"] if sensor_live else None,
            "water_quality": state["water_quality"] if sensor_live else None,
            "alerts": recent_alerts,
            "devices": state["devices"],
            "pump": state["pump"],
            "uv": state["uv"],
            "bypass": state["bypass"],
            "sensor_connected": sensor_live,
            "sensor_last_seen": state["sensor_last_seen"],
        })

    def register_sensor_device(self, websocket: WebSocket, device_id: str) -> None:
        """Associate a device_id with a sensor WebSocket (called on first data message)."""
        self._sensor_device_ids[websocket] = device_id

    async def disconnect_sensor(self, websocket: WebSocket):
        device_id = self._sensor_device_ids.pop(websocket, None)
        self.sensor_connections.discard(websocket)
        still_connected = len(self.sensor_connections) > 0
        now = datetime.now().isoformat()
        state["sensor_connected"] = still_connected
        state["sensor_last_seen"] = now  # always stamp the last-seen time
        # Reset auto-pump decision so the first data point after reconnect
        # always triggers a fresh pump command (ON or OFF as required).
        if not still_connected:
            state["pump"]["auto_pump_active"] = None
        logger.info(f"Sensor disconnected. Total: {len(self.sensor_connections)}")
        await self.broadcast_to_apps({
            "type": "sensor_status",
            "connected": still_connected,
            "last_seen": state["sensor_last_seen"],
        })
        # Send a push notification if the last sensor for this device went offline.
        if not still_connected and device_id and _fcm_should_alert(device_id, "offline"):
            asyncio.create_task(_fcm_alert(
                device_id,
                "📡 AGOS Device Offline",
                "Your AGOS water sensor has disconnected. Check power and internet.",
                "offline",
            ))

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

    # Update UV and bypass states reported by firmware
    if "uv_on" in data:
        state["uv"]["on"] = bool(data["uv_on"])
    if "bypass_pump_on" in data:
        state["bypass"]["pump_on"] = bool(data["bypass_pump_on"])

    state["tank_data"].update({
        "level": data.get("level", state["tank_data"]["level"]),
        "volume": data.get("volume", state["tank_data"]["volume"]),
        "capacity": data.get("capacity", state["tank_data"]["capacity"]),
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

    # ── FCM push notifications for threshold violations ───────────────────────
    # Fire-and-forget tasks so alerting never blocks the sensor pipeline.
    # Each metric has an independent 5-minute cooldown per device to prevent spam.
    level = state["tank_data"]["level"]

    if state["water_quality"]["turbidity"]["status"] == "warning" and _fcm_should_alert(device_id, "turbidity"):
        asyncio.create_task(_fcm_alert(
            device_id,
            "⚠️ High Turbidity Detected",
            f"Water turbidity is {turb:.1f} NTU — above the {thresholds['turbidity_max']:.0f} NTU limit.",
            "turbidity",
        ))

    if state["water_quality"]["ph"]["status"] == "warning" and _fcm_should_alert(device_id, "ph"):
        asyncio.create_task(_fcm_alert(
            device_id,
            "⚠️ pH Level Out of Range",
            f"Water pH is {ph:.1f} — outside safe range {thresholds['ph_min']:.1f}–{thresholds['ph_max']:.1f}.",
            "ph",
        ))

    if state["water_quality"]["tds"]["status"] == "warning" and _fcm_should_alert(device_id, "tds"):
        asyncio.create_task(_fcm_alert(
            device_id,
            "⚠️ High TDS Detected",
            f"Water TDS is {tds:.0f} ppm — above the {thresholds['tds_max']:.0f} ppm limit.",
            "tds",
        ))

    if level < 20.0 and _fcm_should_alert(device_id, "level"):
        asyncio.create_task(_fcm_alert(
            device_id,
            "⚠️ Low Water Level",
            f"Tank level is {level:.0f}% — consider refilling.",
            "level",
        ))
    # ──────────────────────────────────────────────────────────────────────────

    # ── Auto-pump control based on water quality thresholds ──────────────────
    # When the backend is connected it takes over pump decisions from the firmware.
    # Pump ON when any metric is outside the configured threshold range.
    # Only fires when the user is NOT in manual mode and only when desired state changes.
    if not state["pump"]["manual"]:
        water_ok = (
            state["water_quality"]["turbidity"]["status"] == "optimal"
            and state["water_quality"]["ph"]["status"] == "optimal"
            and state["water_quality"]["tds"]["status"] == "optimal"
        )
        desired_pump = not water_ok
        last_auto = state["pump"].get("auto_pump_active")  # .get() safe if key absent
        if desired_pump != last_auto:  # only send when decision changes
            state["pump"]["auto_pump_active"] = desired_pump
            state["pump"]["pump_on"] = desired_pump
            pump_msg = {
                "type": "pump_command",
                "action": "on" if desired_pump else "off",
                "duration_seconds": 0,
                "source": "auto",
                "timestamp": datetime.now().isoformat(),
            }
            disconnected = set()
            for conn in list(manager.sensor_connections):  # snapshot to avoid mid-iteration mutation
                try:
                    await conn.send_json(pump_msg)
                except Exception:
                    disconnected.add(conn)
            for c in disconnected:
                manager.sensor_connections.discard(c)
            await manager.broadcast_to_apps({
                "type": "pump_update",
                "pump_on": desired_pump,
                "manual": False,
                "remaining_seconds": 0,
                "timestamp": datetime.now().isoformat(),
            })
            logger.info(
                f"[Auto-pump] Quality={'OK' if water_ok else 'POOR'} → pump {'ON' if desired_pump else 'OFF'}"
            )
    # ──────────────────────────────────────────────────────────────────────────

    # Firestore write (throttled — at most once every FIRESTORE_WRITE_INTERVAL_S seconds)
    if FIREBASE_ENABLED and db is not None and _should_write_firestore(device_id):
        try:
            observed_at = datetime.now()
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
            _update_sensor_rollups(
                device_id,
                observed_at,
                state["tank_data"]["level"],
                state["tank_data"]["volume"],
                state["tank_data"]["flow_rate"],
                pump_active,
                turb,
                ph,
                tds,
            )
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
_bypass_auto_off_task: Optional[asyncio.Task] = None


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
    # Reset auto-pump decision so next sensor read re-evaluates cleanly.
    state["pump"]["auto_pump_active"] = None
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


async def handle_uv_command(data: dict):
    """Received from Flutter: toggle UV lamp ON/OFF. Stores state and relays to ESP32."""
    action = data.get("action", "on")
    uv_on = action == "on"
    state["uv"]["on"] = uv_on

    forward_msg = {
        "type": "uv_command",
        "action": action,
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

    await manager.broadcast_to_apps({
        "type": "uv_update",
        "uv_on": uv_on,
        "timestamp": datetime.now().isoformat(),
    })
    logger.info(f"UV command: {action}")


async def _bypass_auto_off_loop(duration_seconds: int, expected_last_run: str):
    """Turn bypass pump off after duration, unless a newer run has started."""
    await asyncio.sleep(max(0, duration_seconds))

    # Ignore stale timer from an older run.
    if state["bypass"].get("last_run") != expected_last_run:
        return

    state["bypass"]["pump_on"] = False

    off_msg = {
        "type": "bypass_command",
        "action": "off",
        "duration_seconds": 0,
        "source": "timer_expired",
        "timestamp": datetime.now().isoformat(),
    }
    disconnected = set()
    for conn in list(manager.sensor_connections):
        try:
            await conn.send_json(off_msg)
        except Exception:
            disconnected.add(conn)
    for c in disconnected:
        manager.sensor_connections.discard(c)

    await manager.broadcast_to_apps({
        "type": "bypass_update",
        "bypass_pump_on": False,
        "last_run": state["bypass"].get("last_run"),
        "timestamp": datetime.now().isoformat(),
    })
    logger.info(f"Bypass auto-off: timer expired after {duration_seconds}s")


async def handle_bypass_command(data: dict):
    """Received from Flutter: manual bypass pump trigger."""
    global _bypass_auto_off_task

    action = data.get("action", "off")
    duration_seconds = int(data.get("duration_seconds",
                                     state["bypass"]["schedule"].get("duration_seconds", 1800)))
    is_on = action == "on"

    # Cancel any previous auto-off task when a new manual bypass command arrives.
    if _bypass_auto_off_task and not _bypass_auto_off_task.done():
        _bypass_auto_off_task.cancel()
        _bypass_auto_off_task = None

    state["bypass"]["pump_on"] = is_on

    if is_on:
        state["bypass"]["last_run"] = datetime.now().isoformat()

    forward_msg = {
        "type": "bypass_command",
        "action": action,
        "duration_seconds": duration_seconds,
        "source": "manual",
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

    await manager.broadcast_to_apps({
        "type": "bypass_update",
        "bypass_pump_on": is_on,
        "last_run": state["bypass"]["last_run"],
        "timestamp": datetime.now().isoformat(),
    })

    # Manual ON with finite duration should auto-off server-side even if ESP32
    # doesn't report a final state update.
    if is_on and duration_seconds > 0:
        _bypass_auto_off_task = asyncio.create_task(
            _bypass_auto_off_loop(duration_seconds, state["bypass"]["last_run"])
        )

    logger.info(f"Bypass command: {action}, duration={duration_seconds}s")


async def handle_bypass_schedule(data: dict):
    """Received from Flutter: set or update the bypass pump daily schedule."""
    sched = state["bypass"]["schedule"]
    if "hour" in data:
        sched["hour"] = int(data["hour"])
    if "minute" in data:
        sched["minute"] = int(data["minute"])
    if "duration_minutes" in data:
        sched["duration_seconds"] = int(data["duration_minutes"]) * 60
    elif "duration_seconds" in data:
        sched["duration_seconds"] = int(data["duration_seconds"])

    # Forward updated schedule to ESP32 so it can also run offline
    forward_msg = {
        "type": "bypass_schedule",
        "hour": sched["hour"],
        "minute": sched["minute"],
        "duration_seconds": sched["duration_seconds"],
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

    # Echo the new schedule back to all apps
    await manager.broadcast_to_apps({
        "type": "bypass_schedule_update",
        "schedule": sched,
        "timestamp": datetime.now().isoformat(),
    })
    logger.info(f"Bypass schedule updated: {sched['hour']:02d}:{sched['minute']:02d}, "
                f"dur={sched['duration_seconds']}s")


async def _bypass_schedule_loop():
    """Background task: fire bypass_command to ESP32 at the configured daily time."""
    global _bypass_auto_off_task

    last_trigger_date = None
    while True:
        await asyncio.sleep(30)  # check every 30 s
        try:
            sched = state["bypass"]["schedule"]
            hour   = sched.get("hour", -1)
            minute = sched.get("minute", 0)
            dur_sec = sched.get("duration_seconds", 1800)
            if hour < 0:
                continue
            now = datetime.now()
            today = now.date()
            if now.hour == hour and now.minute == minute and last_trigger_date != today:
                last_trigger_date = today
                state["bypass"]["pump_on"] = True
                state["bypass"]["last_run"] = now.isoformat()

                if _bypass_auto_off_task and not _bypass_auto_off_task.done():
                    _bypass_auto_off_task.cancel()
                    _bypass_auto_off_task = None

                bypass_msg = {
                    "type": "bypass_command",
                    "action": "on",
                    "duration_seconds": dur_sec,
                    "source": "schedule",
                    "timestamp": now.isoformat(),
                }
                disconnected = set()
                for conn in list(manager.sensor_connections):
                    try:
                        await conn.send_json(bypass_msg)
                    except Exception:
                        disconnected.add(conn)
                for c in disconnected:
                    manager.sensor_connections.discard(c)
                await manager.broadcast_to_apps({
                    "type": "bypass_update",
                    "bypass_pump_on": True,
                    "last_run": now.isoformat(),
                    "timestamp": now.isoformat(),
                })

                if dur_sec > 0:
                    _bypass_auto_off_task = asyncio.create_task(
                        _bypass_auto_off_loop(dur_sec, state["bypass"]["last_run"])
                    )

                logger.info(f"[Bypass] Scheduled trigger at {hour:02d}:{minute:02d}, dur={dur_sec}s")
        except Exception as e:
            logger.warning(f"Bypass schedule loop error: {e}")


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
    # When manual mode ends, reset the auto-pump decision so the next sensor
    # reading re-evaluates and re-triggers if water quality still requires it.
    if not is_on:
        state["pump"]["auto_pump_active"] = None

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

@app.on_event("startup")
async def _on_startup():
    """Start background tasks when the ASGI server starts."""
    asyncio.create_task(_redis_snapshot_loop())
    asyncio.create_task(_bypass_schedule_loop())


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


@app.get("/health")
async def health():
    # Redis check
    redis_status = "disabled"
    if _redis_client is not None:
        try:
            _redis_client.ping()
            redis_status = "ok"
        except Exception:
            redis_status = "error"

    # Firebase check
    firebase_status = "ok" if FIREBASE_ENABLED else "disabled"

    return {
        "status": "ok",
        "sensor_connected": state["sensor_connected"],
        "sensor_connections": len(manager.sensor_connections),
        "app_connections": len(manager.app_connections),
        "firebase": firebase_status,
        "redis": redis_status,
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
                # Register device_id → websocket mapping on first data message
                # so disconnect_sensor knows which device went offline.
                device_id = data.get("device_id", "")
                if device_id:
                    manager.register_sensor_device(websocket, device_id)
                await handle_sensor_data(data)
            elif msg_type == "alert":
                await handle_alert(data)
            elif msg_type == "heartbeat":
                await websocket.send_json({
                    "type": "heartbeat_ack",
                    "timestamp": datetime.now().isoformat()
                })
    except Exception as exc:
        logger.error(f"[WS] Sensor handler error — connection will close: {exc!r}")
    finally:
        await manager.disconnect_sensor(websocket)


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
                    "uv": state["uv"],
                    "bypass": state["bypass"],
                })
            elif msg_type == "get_history":
                await handle_get_history(data, websocket)
            elif msg_type == "pump_command":
                await handle_pump_command(data)
            elif msg_type == "uv_command":
                await handle_uv_command(data)
            elif msg_type == "bypass_command":
                await handle_bypass_command(data)
            elif msg_type == "bypass_schedule":
                await handle_bypass_schedule(data)
            elif msg_type == "heartbeat":
                await websocket.send_json({
                    "type": "heartbeat_ack",
                    "timestamp": datetime.now().isoformat()
                })
    except Exception:
        pass
    finally:
        manager.disconnect_app(websocket)


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000, log_level="info")
