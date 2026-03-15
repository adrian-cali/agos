# AGOS TODO

## Pending: Firestore Rollup Backfill

### What
Run a one-time backfill script to populate `sensor_rollups_hourly` and `sensor_rollups_daily` from existing raw `sensor_readings`.

This enables `7D` and `30D` historical charts to show Avg/Min/Max for past data.

### Why it is blocked
Firestore Spark free-tier read quota was exhausted. The backfill script fails with:
```
google.api_core.exceptions.ResourceExhausted: 429 Quota exceeded
```

### When to retry
After Firestore daily quota resets, which happens around:
- **4:00 PM PHT** (Philippine time) during UTC-7 season
- **3:00 PM PHT** during UTC-8 season

### How to run after quota resets

**Step 1 — Probe (quota check)**
```powershell
cd c:\Users\Adrian\agos
c:\Users\Adrian\agos\.venv\Scripts\python.exe backend\backfill_rollups.py --days 1 --max-readings 1000
```

**Step 2 — Stage 1: 3-day backfill**
```powershell
c:\Users\Adrian\agos\.venv\Scripts\python.exe backend\backfill_rollups.py --days 3 --max-readings 30000
```

**Step 3 — Stage 2: 7-day backfill**
```powershell
c:\Users\Adrian\agos\.venv\Scripts\python.exe backend\backfill_rollups.py --days 7 --max-readings 60000
```

**Step 4 — Stage 3: 30-day backfill**
```powershell
c:\Users\Adrian\agos\.venv\Scripts\python.exe backend\backfill_rollups.py --days 30 --max-readings 120000
```

**Note:** If any step fails with 429 again, wait and retry the same step.

---

## Done

- [x] Home card palette alignment
- [x] Auth Google image network fix (HTTP 429 Wikimedia)
- [x] Notifications clear-all persistence fix
- [x] Dart/Python diagnostics cleanup
- [x] App icon and splash asset upgrades
- [x] Dashboard tooltip date/time fix (24H, 7D, 30D)
- [x] Bypass schedule hot-restart running state fix
- [x] Dashboard header "Waiting for data..." fallback fix
- [x] Rollup pipeline implementation (backend + Flutter + dashboard)
- [x] Firestore indexes deployed to `agos-prod`
- [x] Backfill script created and staged for retry after quota reset
