import 'dart:io' show Platform;

class ApiConfig {
  ApiConfig._();

  // On Android emulator, 10.0.2.2 maps to host machine's localhost
  // On desktop/other platforms, use localhost directly
  static String get host {
    try {
      if (Platform.isAndroid) return '10.0.2.2';
    } catch (_) {}
    return 'localhost';
  }

  static const int port = 8000;

  static String get wsAppUrl => 'ws://$host:$port/ws/app';
  static String get wsSensorUrl => 'ws://$host:$port/ws/sensor';
  static String get httpBaseUrl => 'http://$host:$port';
}
