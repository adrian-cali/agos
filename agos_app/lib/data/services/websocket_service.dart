import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../core/constants/api_config.dart';

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

      _channel!.stream.listen(
        (message) {
          try {
            final data = jsonDecode(message as String) as Map<String, dynamic>;
            for (final listener in _listeners) {
              listener(data);
            }
          } catch (e) {
            print('Error parsing WebSocket message: $e');
          }
        },
        onError: (error) {
          print('WebSocket error: $error');
          _isConnected = false;
          _scheduleReconnect();
        },
        onDone: () {
          print('WebSocket connection closed');
          _isConnected = false;
          _scheduleReconnect();
        },
      );

      _startHeartbeat();
      print('WebSocket connected to ${ApiConfig.wsAppUrl}');
    } catch (e) {
      print('Failed to connect to WebSocket: $e');
      _isConnected = false;
      // Don't schedule reconnect to prevent endless loops
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
      print('Error sending WebSocket message: $e');
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

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_isConnected) {
        send({'type': 'heartbeat'});
      }
    });
  }

  void _scheduleReconnect() {
    // Disable automatic reconnection to prevent endless failure loops
    // Users can manually refresh/reconnect when backend is available
    _reconnectTimer?.cancel();
    print('WebSocket disconnected. Auto-reconnection disabled to prevent crashes.');
  }

  void disconnect() {
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _isConnected = false;
    _channel?.sink.close();
  }
}

// ============= Providers =============

final webSocketServiceProvider = Provider<WebSocketService>((ref) {
  final service = WebSocketService();
  
  // Don't auto-connect immediately - let the app start without WebSocket issues
  // Connect can be called manually when needed
  
  ref.onDispose(() => service.disconnect());
  return service;
});

final tankDataProvider = StateNotifierProvider<TankDataNotifier, TankData>((ref) {
  final notifier = TankDataNotifier();
  final ws = ref.watch(webSocketServiceProvider);
  ws.addListener((data) {
    final type = data['type'];
    if (type == 'state_snapshot') {
      notifier.update(TankData.fromJson(data['tank_data'] ?? {}));
    } else if (type == 'tank_update') {
      notifier.update(TankData.fromJson(data['data'] ?? {}));
    }
  });
  return notifier;
});

class TankDataNotifier extends StateNotifier<TankData> {
  TankDataNotifier() : super(TankData(
    level: 67,
    volume: 33500,
    capacity: 50000,
    flowRate: 2.4,
    status: 'optimal',
    timestamp: '',
  ));
  void update(TankData data) => state = data;
}

final waterQualityProvider =
    StateNotifierProvider<WaterQualityNotifier, WaterQuality>((ref) {
  final notifier = WaterQualityNotifier();
  final ws = ref.watch(webSocketServiceProvider);
  ws.addListener((data) {
    final type = data['type'];
    if (type == 'state_snapshot') {
      notifier.update(WaterQuality.fromJson(data['water_quality'] ?? {}));
    } else if (type == 'quality_update') {
      notifier.update(WaterQuality.fromJson(data['data'] ?? {}));
    }
  });
  return notifier;
});

class WaterQualityNotifier extends StateNotifier<WaterQuality> {
  WaterQualityNotifier() : super(WaterQuality());
  void update(WaterQuality data) => state = data;
}

final alertsProvider =
    StateNotifierProvider<AlertsNotifier, List<AlertItem>>((ref) {
  final notifier = AlertsNotifier();
  final ws = ref.watch(webSocketServiceProvider);
  ws.addListener((data) {
    final type = data['type'];
    if (type == 'state_snapshot') {
      final alerts = (data['alerts'] as List?)
              ?.map((a) => AlertItem.fromJson(a))
              .toList() ??
          [];
      notifier.setAlerts(alerts);
    } else if (type == 'system_alert') {
      notifier.addAlert(AlertItem.fromJson(data['alert'] ?? {}));
    } else if (type == 'alerts_updated') {
      final alerts = (data['alerts'] as List?)
              ?.map((a) => AlertItem.fromJson(a))
              .toList() ??
          [];
      notifier.setAlerts(alerts);
    }
  });
  return notifier;
});

class AlertsNotifier extends StateNotifier<List<AlertItem>> {
  AlertsNotifier() : super([]);
  void setAlerts(List<AlertItem> alerts) => state = alerts;
  void addAlert(AlertItem alert) => state = [...state, alert];
  void removeAlert(String id) =>
      state = state.where((a) => a.id != id).toList();
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
