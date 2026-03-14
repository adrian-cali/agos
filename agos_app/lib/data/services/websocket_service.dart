import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/painting.dart' show Color;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../core/constants/api_config.dart';
import '../../core/services/local_notification_service.dart';
import 'firestore_service.dart';

// ============= Models =============

class TankData {
  final double level;
  final double volume;
  final double capacity;
  final double flowRate;
  final String status;
  final String timestamp;

  TankData({
    this.level = 0,
    this.volume = 0,
    this.capacity = 50000,
    this.flowRate = 0,
    this.status = 'unknown',
    this.timestamp = '',
  });

  factory TankData.fromJson(Map<String, dynamic> json) {
    return TankData(
      level: (json['level'] ?? 0).toDouble(),
      volume: (json['volume'] ?? 0).toDouble(),
      capacity: (json['capacity'] ?? 50000).toDouble(),
      flowRate: (json['flow_rate'] ?? 0).toDouble(),
      status: json['status'] ?? 'unknown',
      timestamp: json['timestamp'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'level': level,
    'volume': volume,
    'capacity': capacity,
    'flow_rate': flowRate,
    'status': status,
    'timestamp': timestamp,
  };
}

class WaterQualityMetric {
  final double value;
  final String unit;
  final String status;
  final String target;

  WaterQualityMetric({
    this.value = 0,
    this.unit = '',
    this.status = 'unknown',
    this.target = '',
  });

  factory WaterQualityMetric.fromJson(Map<String, dynamic> json) {
    return WaterQualityMetric(
      value: (json['value'] ?? 0).toDouble(),
      unit: json['unit'] ?? '',
      status: json['status'] ?? 'unknown',
      target: json['target'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'value': value,
    'unit': unit,
    'status': status,
    'target': target,
  };
}

class WaterQuality {
  final WaterQualityMetric turbidity;
  final WaterQualityMetric ph;
  final WaterQualityMetric tds;
  final WaterQualityMetric temperature;

  WaterQuality({
    WaterQualityMetric? turbidity,
    WaterQualityMetric? ph,
    WaterQualityMetric? tds,
    WaterQualityMetric? temperature,
  })  : turbidity = turbidity ?? WaterQualityMetric(),
        ph = ph ?? WaterQualityMetric(),
        tds = tds ?? WaterQualityMetric(),
        temperature = temperature ?? WaterQualityMetric();

  factory WaterQuality.fromJson(Map<String, dynamic> json) {
    return WaterQuality(
      turbidity: WaterQualityMetric.fromJson(json['turbidity'] ?? {}),
      ph: WaterQualityMetric.fromJson(json['ph'] ?? {}),
      tds: WaterQualityMetric.fromJson(json['tds'] ?? {}),
      temperature: WaterQualityMetric.fromJson(json['temperature'] ?? {}),
    );
  }

  Map<String, dynamic> toJson() => {
    'turbidity': turbidity.toJson(),
    'ph': ph.toJson(),
    'tds': tds.toJson(),
    'temperature': temperature.toJson(),
  };
}

class AlertItem {
  final String id;
  final String type;
  final String title;
  final String description;
  final String timestamp;
  final bool isRead;
  final String severity;

  AlertItem({
    this.id = '',
    this.type = '',
    this.title = '',
    this.description = '',
    this.timestamp = '',
    this.isRead = false,
    this.severity = 'info',
  });

  factory AlertItem.fromJson(Map<String, dynamic> json) {
    return AlertItem(
      id: json['id'] ?? '',
      type: json['type'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      timestamp: json['timestamp'] ?? '',
      isRead: json['is_read'] ?? false,
      severity: json['severity'] ?? 'info',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'title': title,
    'description': description,
    'timestamp': timestamp,
    'is_read': isRead,
    'severity': severity,
  };
}

class DeviceInfo {
  final String id;
  final String name;
  final String status;
  final String lastSeen;

  DeviceInfo({
    this.id = '',
    this.name = '',
    this.status = 'disconnected',
    this.lastSeen = '',
  });

  factory DeviceInfo.fromJson(Map<String, dynamic> json) {
    return DeviceInfo(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      status: json['status'] ?? 'disconnected',
      lastSeen: json['last_seen'] ?? '',
    );
  }
}

class HistoricalPoint {
  final String timestamp;
  final double value;

  HistoricalPoint({this.timestamp = '', this.value = 0});

  factory HistoricalPoint.fromJson(Map<String, dynamic> json) {
    return HistoricalPoint(
      timestamp: json['timestamp'] ?? '',
      value: (json['value'] ?? 0).toDouble(),
    );
  }
}

// ============= WebSocket Service =============

class WebSocketService {
  WebSocketChannel? _channel;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  bool _isConnected = false;
  final List<Function(Map<String, dynamic>)> _listeners = [];

  /// Called whenever the connection state changes. True = connected, false = disconnected.
  Function(bool)? onConnectionChanged;

  /// Called with the message type each time any WS message is received.
  /// Only sensor-data messages (not heartbeat_ack, pump_update, etc.) should
  /// be used to mark the connection as "Live".
  Function(String type)? onMessageReceived;

  bool get isConnected => _isConnected;

  void connect() async {
    if (_isConnected) return;
    
    try {
      // Add a null check and better error handling
      if (_channel != null) {
        _channel!.sink.close();
      }
      
      _channel = WebSocketChannel.connect(
        Uri.parse(ApiConfig.wsAppUrl),
        protocols: null,
      );

      // Wait briefly to see if connection succeeds
      await Future.delayed(const Duration(milliseconds: 500));
      
      _isConnected = true;
      onConnectionChanged?.call(true);
      _reconnectDelay = 3; // reset backoff on successful connect

      _channel!.stream.listen(
        (message) {
          try {
            final data = jsonDecode(message as String) as Map<String, dynamic>;
            final type = data['type'] as String? ?? '';
            onMessageReceived?.call(type);
            for (final listener in _listeners) {
              listener(data);
            }
          } catch (e) {
            debugPrint('Error parsing WebSocket message: $e');
          }
        },
        onError: (error) {
          debugPrint('WebSocket error: $error');
          _isConnected = false;
          onConnectionChanged?.call(false);
          _scheduleReconnect();
        },
        onDone: () {
          debugPrint('WebSocket connection closed');
          _isConnected = false;
          onConnectionChanged?.call(false);
          _scheduleReconnect();
        },
      );

      _startHeartbeat();
      debugPrint('WebSocket connected to ${ApiConfig.wsAppUrl}');
    } catch (e) {
      debugPrint('Failed to connect to WebSocket: $e');
      _isConnected = false;
      onConnectionChanged?.call(false);
      _scheduleReconnect();
    }
  }

  void addListener(Function(Map<String, dynamic>) listener) {
    _listeners.add(listener);
  }

  void removeListener(Function(Map<String, dynamic>) listener) {
    _listeners.remove(listener);
  }

  void send(Map<String, dynamic> message) {
    try {
      if (_isConnected && _channel != null) {
        _channel!.sink.add(jsonEncode(message));
      }
    } catch (e) {
      debugPrint('Error sending WebSocket message: $e');
      _isConnected = false;
      _scheduleReconnect();
    }
  }

  void requestState() {
    send({'type': 'get_state'});
  }

  void deleteAlert(String alertId) {
    send({'type': 'delete_alert', 'alert_id': alertId});
  }

  void requestHistoricalData(String metric, String period) {
    send({
      'type': 'get_history',
      'metric': metric,
      'period': period,
    });
  }

  /// Send a pump command to the ESP32.
  /// [on] - true to turn pump ON, false to turn OFF.
  /// [durationSeconds] - how long to run the pump (0 = indefinite until manual OFF).
  void sendPumpCommand({required bool on, int durationSeconds = 0}) {
    send({
      'type': 'pump_command',
      'action': on ? 'on' : 'off',
      'duration_seconds': durationSeconds,
    });
  }

  /// Push user thresholds to the backend so alert generation uses saved values.
  void sendThresholds(UserThresholds t) {
    send({
      'type': 'update_thresholds',
      'turbidity_min': t.turbidityMin,
      'turbidity_max': t.turbidityMax,
      'ph_min': t.phMin,
      'ph_max': t.phMax,
      'tds_max': t.tdsMax,
    });
  }

  /// Toggle UV steriliser lamp.
  void sendUvCommand({required bool on}) {
    send({'type': 'uv_command', 'action': on ? 'on' : 'off'});
  }

  /// Manual bypass pump trigger. [durationSeconds] = 0 uses server default schedule duration.
  void sendBypassCommand({required bool on, int durationSeconds = 0}) {
    send({
      'type': 'bypass_command',
      'action': on ? 'on' : 'off',
      'duration_seconds': durationSeconds,
    });
  }

  /// Save the daily bypass schedule. [durationMinutes] = 0 leaves existing duration.
  void sendBypassSchedule({
    required int hour,
    required int minute,
    required int durationMinutes,
  }) {
    send({
      'type': 'bypass_schedule',
      'hour': hour,
      'minute': minute,
      'duration_minutes': durationMinutes,
    });
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_isConnected) {
        send({'type': 'heartbeat'});
      }
    });
  }

  int _reconnectDelay = 3; // seconds, doubles on each failure up to max

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    final delay = _reconnectDelay;
    // Cap reconnect delay at 30s
    _reconnectDelay = (_reconnectDelay * 2).clamp(3, 30);
    debugPrint('WebSocket disconnected. Reconnecting in ${delay}s...');
    _reconnectTimer = Timer(Duration(seconds: delay), () {
      if (!_isConnected) {
        debugPrint('Attempting WebSocket reconnect...');
        _reconnectDelay = 3; // reset on attempt
        connect();
      }
    });
  }

  void disconnect() {
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _isConnected = false;
    onConnectionChanged?.call(false);
    _channel?.sink.close();
  }
}

// ============= Providers =============

/// Whether the ESP32/simulator is actively sending data (received within last 15s).
/// This is "Live" in the UI — true only when fresh sensor data is arriving.
final wsConnectedProvider = StateProvider<bool>((ref) => false);

/// Timestamp of the last sensor data message received from the ESP32 via WebSocket.
/// Persisted to SharedPreferences so it survives hot restarts.
final wsLastDataProvider =
    StateNotifierProvider<_WsLastDataNotifier, DateTime?>((ref) {
  return _WsLastDataNotifier();
});

class _WsLastDataNotifier extends StateNotifier<DateTime?> {
  static const _key = 'ws_last_data_ts';

  _WsLastDataNotifier() : super(null) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ms = prefs.getInt(_key);
      if (ms != null && mounted) {
        state = DateTime.fromMillisecondsSinceEpoch(ms);
      }
    } catch (_) {}
  }

  void update(DateTime dt) {
    state = dt;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setInt(_key, dt.millisecondsSinceEpoch);
    });
  }

  void clear() {
    state = null;
    SharedPreferences.getInstance().then((prefs) {
      prefs.remove(_key);
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dismissed alerts — persisted across sessions
// ─────────────────────────────────────────────────────────────────────────────

/// Holds the set of dismissed alert IDs plus a flag indicating whether the
/// persisted data has been loaded from SharedPreferences.
class DismissedAlertsState {
  final Set<String> ids;
  final bool loaded;
  const DismissedAlertsState({required this.ids, required this.loaded});
}

/// Set of alert IDs the user has dismissed in the notification modal.
/// Persisted to SharedPreferences so dismissals survive restarts.
final dismissedAlertsProvider =
    StateNotifierProvider<DismissedAlertsNotifier, DismissedAlertsState>(
        (ref) => DismissedAlertsNotifier());

// ── Completed alerts (persisted across sessions) ─────────────────────────────

final completedAlertsProvider =
    StateNotifierProvider<CompletedAlertsNotifier, Set<String>>(
        (ref) => CompletedAlertsNotifier());

class CompletedAlertsNotifier extends StateNotifier<Set<String>> {
  static const _key = 'completed_alert_ids';

  CompletedAlertsNotifier() : super(const {}) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_key) ?? [];
      if (mounted) state = Set<String>.from(list);
    } catch (_) {}
  }

  void markCompleted(String id) {
    if (state.contains(id)) return;
    state = {...state, id};
    _save();
  }

  void _save() {
    SharedPreferences.getInstance().then((prefs) {
      prefs.setStringList(_key, state.toList());
    });
  }
}

class DismissedAlertsNotifier
    extends StateNotifier<DismissedAlertsState> {
  static const _key = 'dismissed_alert_ids';

  DismissedAlertsNotifier()
      : super(const DismissedAlertsState(ids: {}, loaded: false)) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_key) ?? [];
      if (mounted) {
        state = DismissedAlertsState(
            ids: Set<String>.from(list), loaded: true);
      }
    } catch (_) {
      if (mounted) {
        state = DismissedAlertsState(ids: state.ids, loaded: true);
      }
    }
  }

  void dismiss(String id) {
    if (state.ids.contains(id)) return;
    state = DismissedAlertsState(ids: {...state.ids, id}, loaded: state.loaded);
    _save();
  }

  void dismissAll(Iterable<String> ids) {
    state = DismissedAlertsState(
        ids: {...state.ids, ...ids}, loaded: state.loaded);
    _save();
  }

  void _save() {
    SharedPreferences.getInstance().then((prefs) {
      prefs.setStringList(_key, state.ids.toList());
    });
  }
}

// ── Push notifications enabled toggle (persisted) ────────────────────────────

final pushNotificationsEnabledProvider =
    StateNotifierProvider<PushNotificationsEnabledNotifier, bool>(
        (ref) => PushNotificationsEnabledNotifier());

class PushNotificationsEnabledNotifier extends StateNotifier<bool> {
  static const _key = 'push_notifications_enabled';

  PushNotificationsEnabledNotifier() : super(true) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) state = prefs.getBool(_key) ?? true;
    } catch (_) {}
  }

  void setEnabled(bool value) {
    state = value;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool(_key, value);
    });
  }
}

// ── Cached alerts (persisted, survives hot restart) ───────────────────────────

final cachedAlertsProvider =
    StateNotifierProvider<CachedAlertsNotifier, List<AlertItem>>(
        (ref) => CachedAlertsNotifier());

class CachedAlertsNotifier extends StateNotifier<List<AlertItem>> {
  static const _key = 'cached_alert_items';
  static const _maxCached = 50; // keep at most 50 alerts

  CachedAlertsNotifier() : super([]) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_key) ?? [];
      if (mounted) {
        state = raw
            .map((s) {
              try {
                return AlertItem.fromJson(
                    Map<String, dynamic>.from(jsonDecode(s) as Map));
              } catch (_) {
                return null;
              }
            })
            .whereType<AlertItem>()
            .toList();
      }
    } catch (_) {}
  }

  void addOrUpdate(AlertItem alert) {
    final existing = state.indexWhere((a) => a.id == alert.id);
    List<AlertItem> updated;
    if (existing >= 0) {
      updated = [...state];
      updated[existing] = alert;
    } else {
      updated = [alert, ...state];
      if (updated.length > _maxCached) {
        updated = updated.sublist(0, _maxCached);
      }
    }
    state = updated;
    _save();
  }

  void addOrUpdateAll(List<AlertItem> alerts) {
    final map = {for (final a in state) a.id: a};
    for (final a in alerts) {
      map[a.id] = a;
    }
    var updated = map.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    if (updated.length > _maxCached) updated = updated.sublist(0, _maxCached);
    state = updated;
    _save();
  }

  void _save() {
    SharedPreferences.getInstance().then((prefs) {
      prefs.setStringList(
          _key, state.map((a) => jsonEncode(a.toJson())).toList());
    });
  }
}

final webSocketServiceProvider = Provider<WebSocketService>((ref) {

  final service = WebSocketService();

  // Watchdog: if no sensor data arrives for 15 s, mark sensor as offline.
  // This lets the UI show "Idle" within 15 s of the ESP32 going silent,
  // rather than waiting 40+ s for the backend's TCP keepalive timeout.
  Timer? sensorWatchdog;
  void resetWatchdog() {
    sensorWatchdog?.cancel();
    sensorWatchdog = Timer(const Duration(seconds: 15), () {
      ref.read(wsConnectedProvider.notifier).state = false;
    });
  }

  // ── Live/Idle is driven by the BACKEND’s sensor_status broadcasts ────────────
  // The backend tracks whether the ESP32 is connected and writes that into:
  //   • state_snapshot.sensor_connected  (sent on every fresh app connect)
  //   • sensor_status.connected          (broadcast on ESP32 connect/disconnect)
  // This means Live/Idle reflects the physical device, not the app’s own WS.

  service.addListener((data) {
    final type = data['type'] as String? ?? '';

    switch (type) {
      case 'state_snapshot':
        // Initialise Live/Idle from server-side sensor state on (re)connect.
        final sensorConnected = data['sensor_connected'] as bool? ?? false;
        ref.read(wsConnectedProvider.notifier).state = sensorConnected;

        if (sensorConnected) {
          // Sensor is live — restore timestamp and start watchdog.
          final lastSeenRaw = data['sensor_last_seen'] as String?;
          if (lastSeenRaw != null) {
            try {
              ref.read(wsLastDataProvider.notifier).update(DateTime.parse(lastSeenRaw));
            } catch (_) {}
          }
          resetWatchdog();
        }
        break;

      case 'sensor_status':
        // Real-time broadcast from backend whenever ESP32 connects or drops.
        final connected = data['connected'] as bool? ?? false;
        ref.read(wsConnectedProvider.notifier).state = connected;

        if (connected) {
          // Sensor reconnected — stamp the time and start watchdog.
          final sensorLastSeenRaw = data['last_seen'] as String?;
          if (sensorLastSeenRaw != null) {
            try {
              ref.read(wsLastDataProvider.notifier).update(DateTime.parse(sensorLastSeenRaw));
            } catch (_) {
              ref.read(wsLastDataProvider.notifier).update(DateTime.now());
            }
          } else {
            ref.read(wsLastDataProvider.notifier).update(DateTime.now());
          }
          resetWatchdog();
        } else {
          // Backend confirmed sensor offline — cancel the watchdog.
          sensorWatchdog?.cancel();
          sensorWatchdog = null;
        }
        break;

      case 'tank_update':
      case 'quality_update':
        // Fresh sensor data arrived — reset the watchdog and stamp the time.
        resetWatchdog();
        ref.read(wsLastDataProvider.notifier).update(DateTime.now());
        break;
    }
  });

  // When the app WS reconnects, push saved thresholds immediately.
  service.onConnectionChanged = (connected) {
    if (connected) {
      final thresholds = ref.read(userThresholdsProvider).valueOrNull;
      if (thresholds != null) service.sendThresholds(thresholds);
    }
    // Do NOT alter wsConnectedProvider here — that’s the ESP32 sensor status,
    // not the app-to-backend connection status.
  };

  // Auto-push user thresholds to backend whenever they change
  // (covers initial load after login and any saves from settings).
  ref.listen<AsyncValue<UserThresholds>>(userThresholdsProvider, (_, next) {
    next.whenData((t) => service.sendThresholds(t));
  });

  ref.onDispose(() {
    sensorWatchdog?.cancel();
    service.disconnect();
  });
  return service;
});

final tankDataProvider = StateNotifierProvider<TankDataNotifier, TankData>((ref) {
  final notifier = TankDataNotifier();
  final ws = ref.watch(webSocketServiceProvider);
  ws.addListener((data) {
    final type = data['type'];
    if (type == 'state_snapshot') {
      // When sensor is offline the backend sends tank_data: null to prevent
      // stale Redis-cached spike values from appearing on first app open.
      // Mirror that on the Flutter side by clearing any locally cached data.
      if (data['tank_data'] == null) {
        notifier.clear();
      } else {
        notifier.update(TankData.fromJson(data['tank_data'] as Map<String, dynamic>));
      }
    } else if (type == 'tank_update') {
      notifier.update(TankData.fromJson(data['data'] ?? {}));
    }
  });
  return notifier;
});

class TankDataNotifier extends StateNotifier<TankData> {
  static const _key = 'cached_tank_data';

  TankDataNotifier() : super(TankData(
    level: 0,
    volume: 0,
    capacity: 50000,
    flowRate: 0,
    status: 'unknown',
    timestamp: '',
  )) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null && mounted) {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        state = TankData.fromJson(json);
      }
    } catch (_) {}
  }

  void update(TankData data) {
    if (!mounted) return;
    state = data;
    SharedPreferences.getInstance().then((prefs) {
      try {
        prefs.setString(_key, jsonEncode(data.toJson()));
      } catch (_) {}
    });
  }

  /// Reset to zero-state and remove the local cache so stale data is never
  /// shown when the sensor is offline.
  void clear() {
    if (!mounted) return;
    state = TankData(level: 0, volume: 0, capacity: 50000, flowRate: 0, status: 'unknown', timestamp: '');
    SharedPreferences.getInstance().then((prefs) {
      try { prefs.remove(_key); } catch (_) {}
    });
  }
}

final waterQualityProvider =
    StateNotifierProvider<WaterQualityNotifier, WaterQuality>((ref) {
  final notifier = WaterQualityNotifier();
  final ws = ref.watch(webSocketServiceProvider);
  ws.addListener((data) {
    final type = data['type'];
    if (type == 'state_snapshot') {
      // When sensor is offline the backend sends water_quality: null to prevent
      // stale Redis-cached spike values from appearing on first app open.
      if (data['water_quality'] == null) {
        notifier.clear();
      } else {
        notifier.update(WaterQuality.fromJson(data['water_quality'] as Map<String, dynamic>));
      }
    } else if (type == 'quality_update') {
      notifier.update(WaterQuality.fromJson(data['data'] ?? {}));
    }
  });
  return notifier;
});

class WaterQualityNotifier extends StateNotifier<WaterQuality> {
  static const _key = 'cached_water_quality';

  WaterQualityNotifier() : super(WaterQuality()) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null && mounted) {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        state = WaterQuality.fromJson(json);
      }
    } catch (_) {}
  }

  void update(WaterQuality data) {
    if (!mounted) return;
    state = data;
    SharedPreferences.getInstance().then((prefs) {
      try {
        prefs.setString(_key, jsonEncode(data.toJson()));
      } catch (_) {}
    });
  }

  /// Reset to zero-state and remove the local cache so stale data is never
  /// shown when the sensor is offline.
  void clear() {
    if (!mounted) return;
    state = WaterQuality();
    SharedPreferences.getInstance().then((prefs) {
      try { prefs.remove(_key); } catch (_) {}
    });
  }
}

final alertsProvider =
    StateNotifierProvider<AlertsNotifier, List<AlertItem>>((ref) {
  final notifier = AlertsNotifier();
  final ws = ref.watch(webSocketServiceProvider);

  // Seed from cache so alerts survive hot restarts
  // (only if push notifications are enabled)
  final cached = ref.read(cachedAlertsProvider);
  if (cached.isNotEmpty && ref.read(pushNotificationsEnabledProvider)) {
    notifier.setAlerts(cached);
  }

  /// Fire an OS notification for an alert if not yet shown.
  void maybeNotify(AlertItem alert) {
    if (notifier.wasNotified(alert.id)) return;
    notifier.markNotified(alert.id);

    // Check if push notifications are enabled
    if (!ref.read(pushNotificationsEnabledProvider)) return;

    // Pick icon accent color matching the dashboard parameter icon gradient
    Color notifColor;
    final desc = alert.description.toLowerCase();
    if (desc.contains('turbidity')) {
      notifColor = const Color(0xFF00D3F2); // cyan — turbidity
    } else if (desc.contains('ph') || desc.contains('ph ')) {
      notifColor = const Color(0xFFC27AFF); // purple — pH
    } else if (desc.contains('tds')) {
      notifColor = const Color(0xFF7C86FF); // blue-violet — TDS
    } else {
      notifColor = const Color(0xFF00D3F2); // fallback cyan
    }

    LocalNotificationService().showThresholdAlert(
      alertId: alert.id,
      title: alert.title,
      body: alert.description,
      color: notifColor,
    );
  }

  ws.addListener((data) {
    final type = data['type'];
    // When push notifications are disabled, suppress all alert display
    final notificationsEnabled = ref.read(pushNotificationsEnabledProvider);
    if (type == 'state_snapshot') {
      if (!notificationsEnabled) return; // don't populate modal when disabled
      final serverAlerts = (data['alerts'] as List?)
              ?.map((a) => AlertItem.fromJson(a))
              .toList() ??
          [];
      // Preserve locally-injected system alerts (e.g. offline alert) not on server
      final localSystem = notifier.currentAlerts
          .where((a) => a.type == 'system')
          .toList();
      final serverIds = serverAlerts.map((a) => a.id).toSet();
      final merged = [
        ...serverAlerts,
        ...localSystem.where((a) => !serverIds.contains(a.id)),
      ];
      notifier.setAlerts(merged);
      // Cache server alerts so they survive hot restarts
      ref.read(cachedAlertsProvider.notifier).addOrUpdateAll(serverAlerts);
      // Do NOT call maybeNotify here — state_snapshot is a historical sync,
      // not a real-time event. Notifications fire only for live system_alert messages.
    } else if (type == 'system_alert') {
      final alert = AlertItem.fromJson(data['alert'] ?? {});
      // If push notifications are disabled, suppress new in-app alerts as well
      if (!ref.read(pushNotificationsEnabledProvider)) return;
      notifier.addAlert(alert);
      // Cache this alert
      ref.read(cachedAlertsProvider.notifier).addOrUpdate(alert);
      maybeNotify(alert);
    } else if (type == 'alerts_updated') {
      if (!notificationsEnabled) return; // don't sync alerts when disabled
      final serverAlerts = (data['alerts'] as List?)
              ?.map((a) => AlertItem.fromJson(a))
              .toList() ??
          [];
      // Same merge: keep local system alerts
      final localSystem = notifier.currentAlerts
          .where((a) => a.type == 'system')
          .toList();
      final serverIds = serverAlerts.map((a) => a.id).toSet();
      final merged = [
        ...serverAlerts,
        ...localSystem.where((a) => !serverIds.contains(a.id)),
      ];
      notifier.setAlerts(merged);
      // Cache
      ref.read(cachedAlertsProvider.notifier).addOrUpdateAll(serverAlerts);
      // alerts_updated is a list sync (triggered by delete), not a new event—skip notification.
    }
  });

  // When the connection transitions Live → Idle, add a "connection lost" alert.
  ref.listen<bool>(wsConnectedProvider, (prev, next) {
    final wasLive = prev ?? false;
    if (wasLive && !next) {
      final now = DateTime.now();
      final minuteKey =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_'
          '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
      final alertId = 'esp32_offline_$minuteKey';
      // Avoid duplicate if already in list
      if (!notifier.currentAlerts.any((a) => a.id == alertId)) {
        final offlineAlert = AlertItem(
          id: alertId,
          type: 'system',
          title: 'ESP32 Connection Lost',
          description:
              'No data received from the sensor. Check your network or device power.',
          timestamp: now.toIso8601String(),
          severity: 'warning',
        );
        notifier.addAlert(offlineAlert);
        // Cache so it survives hot restart
        ref.read(cachedAlertsProvider.notifier).addOrUpdate(offlineAlert);
        // Also show a native OS notification (if push notifications are enabled)
        if (ref.read(pushNotificationsEnabledProvider)) {
          LocalNotificationService().showEsp32Offline();
        }
      }
    }
  });

  return notifier;
});

class AlertsNotifier extends StateNotifier<List<AlertItem>> {
  AlertsNotifier() : super([]);
  final Set<String> _notifiedIds = {};

  /// Public read-only view of the current alerts list (avoids accessing
  /// `state` from outside the notifier, which state_notifier restricts).
  List<AlertItem> get currentAlerts => state;

  void setAlerts(List<AlertItem> alerts) => state = alerts;
  void addAlert(AlertItem alert) => state = [...state, alert];
  void removeAlert(String id) =>
      state = state.where((a) => a.id != id).toList();

  bool wasNotified(String id) => _notifiedIds.contains(id);
  void markNotified(String id) => _notifiedIds.add(id);
}

final devicesProvider =
    StateNotifierProvider<DevicesNotifier, List<DeviceInfo>>((ref) {
  final notifier = DevicesNotifier();
  final ws = ref.watch(webSocketServiceProvider);
  ws.addListener((data) {
    final type = data['type'];
    if (type == 'state_snapshot') {
      final devices = (data['devices'] as List?)
              ?.map((d) => DeviceInfo.fromJson(d))
              .toList() ??
          [];
      notifier.setDevices(devices);
    }
  });
  return notifier;
});

class DevicesNotifier extends StateNotifier<List<DeviceInfo>> {
  DevicesNotifier() : super([]);
  void setDevices(List<DeviceInfo> devices) => state = devices;
}

final historicalDataProvider =
    StateNotifierProvider<HistoricalDataNotifier, List<HistoricalPoint>>((ref) {
  final notifier = HistoricalDataNotifier();
  final ws = ref.watch(webSocketServiceProvider);
  ws.addListener((data) {
    final type = data['type'];
    if (type == 'historical_data') {
      final points = (data['data'] as List?)
              ?.map((d) => HistoricalPoint.fromJson(d))
              .toList() ??
          [];
      notifier.setData(points);
    }
  });
  return notifier;
});

class HistoricalDataNotifier extends StateNotifier<List<HistoricalPoint>> {
  HistoricalDataNotifier() : super([]);
  void setData(List<HistoricalPoint> data) => state = data;
}

// ============= Live Chart Data (real-time rolling waveform) =============

/// A single timestamped reading used for the live chart waveform.
class LiveChartPoint {
  final DateTime timestamp;
  final double turbidity;
  final double ph;
  final double tds;

  const LiveChartPoint({
    required this.timestamp,
    required this.turbidity,
    required this.ph,
    required this.tds,
  });
}

/// Keeps a rolling 1-hour buffer of live sensor readings.
/// Pre-seeded from Firestore history on first use, then appended to via WebSocket.
class LiveChartNotifier extends StateNotifier<List<LiveChartPoint>> {
  static const _maxAge = Duration(hours: 1);

  LiveChartNotifier() : super([]);

  /// Seed with historical readings. Called once on startup.
  void seed(List<LiveChartPoint> points) {
    final cutoff = DateTime.now().subtract(_maxAge);
    state = points.where((p) => p.timestamp.isAfter(cutoff)).toList();
  }

  /// Append a new live reading and drop anything older than 1 hour.
  void addPoint(LiveChartPoint point) {
    final cutoff = DateTime.now().subtract(_maxAge);
    final trimmed = state.where((p) => p.timestamp.isAfter(cutoff)).toList();
    state = [...trimmed, point];
  }
}

// ============= Pump State =============

/// Represents the current state of the pump.
class PumpState {
  /// Whether the pump is currently running.
  final bool isOn;

  /// Whether the pump was manually turned on (vs. automated sensor-based).
  final bool isManual;

  /// Remaining seconds of the manual timer. 0 means no timer / automated mode.
  final int remainingSeconds;

  const PumpState({
    this.isOn = false,
    this.isManual = false,
    this.remainingSeconds = 0,
  });

  PumpState copyWith({bool? isOn, bool? isManual, int? remainingSeconds}) {
    return PumpState(
      isOn: isOn ?? this.isOn,
      isManual: isManual ?? this.isManual,
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
    );
  }
}

class PumpStateNotifier extends StateNotifier<PumpState> {
  PumpStateNotifier() : super(const PumpState());

  void update(PumpState newState) => state = newState;

  void setOn({required bool manual, int durationSeconds = 0}) {
    state = PumpState(isOn: true, isManual: manual, remainingSeconds: durationSeconds);
  }

  void setOff() {
    state = const PumpState(isOn: false, isManual: false, remainingSeconds: 0);
  }

  void tick() {
    if (state.remainingSeconds > 0) {
      state = state.copyWith(remainingSeconds: state.remainingSeconds - 1);
    }
  }
}

final pumpStateProvider =
    StateNotifierProvider<PumpStateNotifier, PumpState>((ref) {
  final notifier = PumpStateNotifier();
  final ws = ref.watch(webSocketServiceProvider);
  // Listen for pump_update messages from the ESP32 / backend
  ws.addListener((data) {
    final type = data['type'];
    if (type == 'pump_update') {
      final bool on = data['pump_on'] == true;
      final bool manual = data['manual'] == true;
      final int remaining = (data['remaining_seconds'] ?? 0) as int;
      notifier.update(PumpState(isOn: on, isManual: manual, remainingSeconds: remaining));
    } else if (type == 'state_snapshot') {
      final pumpData = data['pump'] as Map<String, dynamic>?;
      if (pumpData != null) {
        final bool on = pumpData['pump_on'] == true;
        final bool manual = pumpData['manual'] == true;
        final int remaining = (pumpData['remaining_seconds'] ?? 0) as int;
        notifier.update(PumpState(isOn: on, isManual: manual, remainingSeconds: remaining));
      }
    }
  });
  return notifier;
});

// ============= UV State =============

class UvState {
  final bool isOn;
  const UvState({this.isOn = true});  // default UV ON
  UvState copyWith({bool? isOn}) => UvState(isOn: isOn ?? this.isOn);
}

class UvStateNotifier extends StateNotifier<UvState> {
  UvStateNotifier() : super(const UvState());
  void setOn(bool on) => state = UvState(isOn: on);
}

final uvStateProvider = StateNotifierProvider<UvStateNotifier, UvState>((ref) {
  final notifier = UvStateNotifier();
  final ws = ref.watch(webSocketServiceProvider);
  ws.addListener((data) {
    final type = data['type'];
    if (type == 'uv_update') {
      notifier.setOn(data['uv_on'] == true);
    } else if (type == 'state_snapshot') {
      final uvData = data['uv'] as Map<String, dynamic>?;
      if (uvData != null) {
        notifier.setOn(uvData['on'] == true);
      }
    }
  });
  return notifier;
});

// ============= Bypass State =============

class BypassSchedule {
  final int hour;          // 0-23
  final int minute;        // 0-59
  final int durationMinutes;

  const BypassSchedule({
    this.hour = 2,
    this.minute = 0,
    this.durationMinutes = 30,
  });

  BypassSchedule copyWith({int? hour, int? minute, int? durationMinutes}) {
    return BypassSchedule(
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      durationMinutes: durationMinutes ?? this.durationMinutes,
    );
  }
}

class BypassState {
  final bool isPumpOn;
  final bool isPaused;
  final int? pausedRemainingSeconds;
  final DateTime? runStartedAt;
  final int runDurationSeconds;
  final BypassSchedule schedule;
  final String? lastRun;

  const BypassState({
    this.isPumpOn = false,
    this.isPaused = false,
    this.pausedRemainingSeconds,
    this.runStartedAt,
    this.runDurationSeconds = 0,
    this.schedule = const BypassSchedule(),
    this.lastRun,
  });

  int get remainingSeconds {
    if (isPaused && pausedRemainingSeconds != null) return pausedRemainingSeconds!;
    if (isPumpOn && runStartedAt != null && runDurationSeconds > 0) {
      final elapsed = DateTime.now().difference(runStartedAt!).inSeconds;
      return (runDurationSeconds - elapsed).clamp(0, runDurationSeconds);
    }
    return 0;
  }

  BypassState copyWith({
    bool? isPumpOn,
    BypassSchedule? schedule,
    String? lastRun,
  }) {
    return BypassState(
      isPumpOn: isPumpOn ?? this.isPumpOn,
      isPaused: isPaused,
      pausedRemainingSeconds: pausedRemainingSeconds,
      runStartedAt: runStartedAt,
      runDurationSeconds: runDurationSeconds,
      schedule: schedule ?? this.schedule,
      lastRun: lastRun ?? this.lastRun,
    );
  }
}

class BypassStateNotifier extends StateNotifier<BypassState> {
  BypassStateNotifier() : super(const BypassState());

  /// Read-only state accessor for use outside the notifier class.
  BypassState get currentState => state;

  void setPumpOn(bool on) => state = state.copyWith(isPumpOn: on);

  void updateSchedule(BypassSchedule s) => state = state.copyWith(schedule: s);

  void update(BypassState newState) => state = newState;

  void startRun(int durationSeconds) {
    state = BypassState(
      isPumpOn: true,
      isPaused: false,
      runStartedAt: DateTime.now(),
      runDurationSeconds: durationSeconds,
      schedule: state.schedule,
      lastRun: state.lastRun,
    );
  }

  void pauseRun() {
    final remaining = state.remainingSeconds;
    state = BypassState(
      isPumpOn: false,
      isPaused: true,
      pausedRemainingSeconds: remaining > 0 ? remaining : state.runDurationSeconds,
      runStartedAt: state.runStartedAt,
      runDurationSeconds: state.runDurationSeconds,
      schedule: state.schedule,
      lastRun: state.lastRun,
    );
  }

  void resumeRun() {
    final resumeDuration = state.pausedRemainingSeconds ?? state.runDurationSeconds;
    state = BypassState(
      isPumpOn: true,
      isPaused: false,
      runStartedAt: DateTime.now(),
      runDurationSeconds: resumeDuration,
      schedule: state.schedule,
      lastRun: state.lastRun,
    );
  }

  void stopRun() {
    state = BypassState(
      isPumpOn: false,
      isPaused: false,
      schedule: state.schedule,
      lastRun: state.lastRun,
    );
  }
}

final bypassStateProvider =
    StateNotifierProvider<BypassStateNotifier, BypassState>((ref) {
  final notifier = BypassStateNotifier();
  final ws = ref.watch(webSocketServiceProvider);
  ws.addListener((data) {
    final type = data['type'];
    if (type == 'bypass_update') {
      final bool on = data['bypass_pump_on'] == true;
      final String? lastRun = data['last_run'] as String?;
      // Don't overwrite paused state with a server-echo of pump_on=false
      if (!notifier.currentState.isPaused || on) {
        notifier.update(
            notifier.currentState.copyWith(isPumpOn: on, lastRun: lastRun));
      }
    } else if (type == 'bypass_schedule_update') {
      final sched = data['schedule'] as Map<String, dynamic>?;
      if (sched != null) {
        notifier.updateSchedule(BypassSchedule(
          hour: (sched['hour'] ?? 2) as int,
          minute: (sched['minute'] ?? 0) as int,
          durationMinutes: ((sched['duration_seconds'] ?? 1800) as int) ~/ 60,
        ));
      }
    } else if (type == 'state_snapshot') {
      final bypassData = data['bypass'] as Map<String, dynamic>?;
      if (bypassData != null) {
        final sched = bypassData['schedule'] as Map<String, dynamic>?;
        final schedule = sched != null
            ? BypassSchedule(
                hour: (sched['hour'] ?? 2) as int,
                minute: (sched['minute'] ?? 0) as int,
                durationMinutes: ((sched['duration_seconds'] ?? 1800) as int) ~/ 60,
              )
            : const BypassSchedule();
        notifier.update(BypassState(
          isPumpOn: bypassData['pump_on'] == true,
          schedule: schedule,
          lastRun: bypassData['last_run'] as String?,
        ));
      }
    }
  });
  return notifier;
});
/// Global rolling 1-hour live chart buffer.
/// Pre-seeded from Firestore on startup, then updated live via WebSocket.
/// No device filter needed — the backend only streams data for the connected sensor.
final liveChartPointsProvider =
    StateNotifierProvider<LiveChartNotifier, List<LiveChartPoint>>((ref) {
  final notifier = LiveChartNotifier();

  // Pre-seed from Firestore: load the last 60 minutes of sensor_readings on startup.
  ref.listen<AsyncValue<String?>>(linkedDeviceIdProvider, (_, next) {
    if (next.isLoading) return; // Wait until async resolves
    final deviceId = next.valueOrNull ?? 'agos-zksl9QK3';
    if (deviceId.isEmpty) return;
    final service = ref.read(firestoreServiceProvider);
    service.fetchReadings(deviceId, days: 0, hours: 1).then((readings) {
      final points = readings.map((r) => LiveChartPoint(
        timestamp: r.timestamp,
        turbidity: r.turbidity,
        ph: r.ph,
        tds: r.tds,
      )).toList();
      notifier.seed(points);
    }).catchError((_) {/* silently ignore seed errors */});
  }, fireImmediately: true);

  // Append new points whenever waterQualityProvider updates.
  // waterQualityProvider is already receiving quality_update WS events correctly,
  // so piggybacking on it is more reliable than a separate ws.addListener.
  ref.listen<WaterQuality>(waterQualityProvider, (prev, next) {
    // Skip no-data readings (all zeros = not yet populated)
    if (next.turbidity.value == 0 && next.ph.value == 0 && next.tds.value == 0) return;
    notifier.addPoint(LiveChartPoint(
      timestamp: DateTime.now(),
      turbidity: next.turbidity.value,
      ph: next.ph.value,
      tds: next.tds.value,
    ));
  });

  return notifier;
});