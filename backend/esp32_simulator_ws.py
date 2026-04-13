import asyncio
import websockets
import json
import random
from datetime import datetime, timezone

WS_URL = "wss://agos-wchk.onrender.com/ws/sensor"
# WS_URL = "ws://localhost:8000/ws/sensor"  # uncomment for local dev
DEVICE_ID = "agos-zksl9QK3"  # Adrian Calingasin's device ID (matches Firestore)

# Firmware-aligned tank values
# agos_esp32.ino: nominal = 120 L, computed usable capacity in backend state ~= 106 L
USABLE_CAPACITY_L = 106.0
REFILL_TARGET_MAX_PCT = 94.0
REFILL_TRIGGER_PCT = 24.0

# Data window requested by user
WINDOW_START = datetime(2026, 2, 28, 7, 0, 0, tzinfo=timezone.utc)
WINDOW_END = datetime(2026, 4, 7, 18, 0, 0, tzinfo=timezone.utc)

# Daily liters inferred from 2026-02-28..2026-04-07 files
# baseline_daily.usage_liters + post_vs_expected.actual_liters
DAILY_USAGE_BY_DATE = {
    "2026-02-28": 13.482,
    "2026-03-01": 19.843,
    "2026-03-02": 7.689,
    "2026-03-03": 21.955,
    "2026-03-04": 24.934,
    "2026-03-05": 16.011,
    "2026-03-06": 20.302,
    "2026-03-07": 25.451,
    "2026-03-08": 20.784,
    "2026-03-09": 16.672,
    "2026-03-10": 10.809,
    "2026-03-11": 18.733,
    "2026-03-12": 21.855,
    "2026-03-13": 27.138,
    "2026-03-14": 16.169,
    "2026-03-15": 12.299,
    "2026-03-16": 18.105,
    "2026-03-17": 16.076,
    "2026-03-18": 19.592,
    "2026-03-19": 13.681,
    "2026-03-20": 22.016,
    "2026-03-21": 27.064,
    "2026-03-22": 9.065,
    "2026-03-23": 20.238,
    "2026-03-24": 19.372,
    "2026-03-25": 22.465,
    "2026-03-26": 11.901,
    "2026-03-27": 20.778,
    "2026-03-28": 20.816,
    "2026-03-29": 23.192,
    "2026-03-30": 24.844,
    "2026-03-31": 13.871,
    "2026-04-01": 13.142,
    "2026-04-02": 20.995,
    "2026-04-03": 25.827,
    "2026-04-04": 17.981,
    "2026-04-05": 23.936,
    "2026-04-06": 17.636,
    "2026-04-07": 15.110,
}

# Simulation state
_virtual_ts = WINDOW_START
_volume_l = 72.0
_refill_active = False

# bad-water spike state
_spike_counter = 0  # increments every reading (5 s each); spike every ~60 readings (~5 min)
_SPIKE_INTERVAL = 60

# Simulated pump state (overridden by pump_command from the backend)
_pump_manual_on = False
_pump_manual_remaining = 0  # seconds remaining in manual mode


def _current_day_usage_liters(sim_ts: datetime) -> float:
    key = sim_ts.date().isoformat()
    return DAILY_USAGE_BY_DATE.get(key, 19.2)


def _usage_activity_factor(hour_utc: int) -> float:
    # Most usage happens daytime; tiny activity overnight.
    if 0 <= hour_utc <= 4:
        return 0.05
    if 5 <= hour_utc <= 7:
        return 0.35
    if 8 <= hour_utc <= 17:
        return 1.70
    if 18 <= hour_utc <= 21:
        return 1.10
    return 0.45


def _advance_virtual_time(seconds: int = 5) -> None:
    global _virtual_ts
    _virtual_ts = _virtual_ts.fromtimestamp(_virtual_ts.timestamp() + seconds, tz=timezone.utc)
    if _virtual_ts > WINDOW_END:
        _virtual_ts = WINDOW_START


def _update_volume(sim_ts: datetime) -> float:
    global _volume_l, _refill_active

    day_usage_l = _current_day_usage_liters(sim_ts)
    base_step_use = day_usage_l / (24 * 60 * 60 / 5)
    factor = _usage_activity_factor(sim_ts.hour)
    stochastic = random.uniform(0.8, 1.25)
    use_l = base_step_use * factor * stochastic

    # Refill model to keep realistic operating range.
    level_pct = (_volume_l / USABLE_CAPACITY_L) * 100.0
    if level_pct <= REFILL_TRIGGER_PCT:
        _refill_active = True
    if level_pct >= REFILL_TARGET_MAX_PCT:
        _refill_active = False

    refill_l = 0.0
    if _refill_active and sim_ts.hour in (2, 3, 4, 5):
        refill_l = random.uniform(0.18, 0.40)

    _volume_l = max(0.0, min(USABLE_CAPACITY_L, _volume_l - use_l + refill_l))
    return _volume_l


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

    volume_l = _update_volume(_virtual_ts)
    level = max(0.0, min(100.0, (volume_l / USABLE_CAPACITY_L) * 100.0))

    # Auto pump logic — firmware offline thresholds
    auto_pump = (turbidity < 0.0 or turbidity > 50.0) or not (6.0 <= ph <= 9.5) or tds > 1000.0
    pump_active = _pump_manual_on or auto_pump

    return {
        "type": "sensor_data",
        "device_id": DEVICE_ID,
        "level": round(level, 1),
        "volume": round(volume_l, 1),
        "capacity": USABLE_CAPACITY_L,
        # Firmware sends 0.0 (no flow sensor on current build)
        "flow_rate": 0.0,
        "turbidity": round(turbidity, 2),
        "ph": round(ph, 2),
        "tds": round(tds, 1),
        "temperature": round(random.uniform(24.0, 31.5), 1),
        "pump_active": pump_active,
        "timestamp": _virtual_ts.isoformat().replace("+00:00", "Z")
    }


async def send_sensor_data():
    global _spike_counter, _pump_manual_on, _pump_manual_remaining

    while True:
        try:
            async with websockets.connect(WS_URL) as websocket:
                print(f"[{DEVICE_ID}] Connected to WebSocket server\n")

                while True:
                    _advance_virtual_time(5)
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
                                "capacity": USABLE_CAPACITY_L,
                                "flow_rate": data["flow_rate"],
                                "turbidity": data["turbidity"],
                                "ph": data["ph"],
                                "tds": data["tds"],
                                "temperature": data["temperature"],
                                "timestamp": _virtual_ts.isoformat().replace("+00:00", "Z"),
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

