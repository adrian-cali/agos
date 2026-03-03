class ApiConfig {
  ApiConfig._();

  // ─── PRODUCTION URL ───────────────────────────────────────────────────────
  // Set this to your deployed backend URL for production / demo builds.
  // Example: 'https://agos-backend.up.railway.app'
  // Leave empty ('') to fall back to the local dev server (localhost:8000).
  static const String _productionUrl = 'https://agos-production.up.railway.app';
  // ──────────────────────────────────────────────────────────────────────────

  static const int port = 8000;

  static bool get _useProduction => _productionUrl.isNotEmpty;

  /// HTTP base URL — used for REST calls.
  static String get httpBaseUrl {
    if (_useProduction) return _productionUrl;
    // Local dev: ADB reverse (adb reverse tcp:8000 tcp:8000) lets real
    // Android devices reach the host machine via localhost.
    return 'http://localhost:$port';
  }

  /// WebSocket URL for the Flutter app to receive live sensor data.
  static String get wsAppUrl {
    if (_useProduction) {
      final base = _productionUrl
          .replaceFirst('https://', 'wss://')
          .replaceFirst('http://', 'ws://');
      return '$base/ws/app';
    }
    return 'ws://localhost:$port/ws/app';
  }

  /// WebSocket URL for the ESP32 sensor to push data.
  static String get wsSensorUrl {
    if (_useProduction) {
      final base = _productionUrl
          .replaceFirst('https://', 'wss://')
          .replaceFirst('http://', 'ws://');
      return '$base/ws/sensor';
    }
    return 'ws://localhost:$port/ws/sensor';
  }
}
