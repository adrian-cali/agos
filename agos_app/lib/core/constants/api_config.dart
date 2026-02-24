class ApiConfig {
  ApiConfig._();

  // For physical Android devices connected via ADB, use 'adb reverse tcp:8000 tcp:8000'
  // then the device can reach the host machine via localhost/127.0.0.1.
  // For Android emulators, 10.0.2.2 maps to host localhost — change back if needed.
  static String get host {
    return 'localhost';
  }

  static const int port = 8000;

  static String get wsAppUrl => 'ws://$host:$port/ws/app';
  static String get wsSensorUrl => 'ws://$host:$port/ws/sensor';
  static String get httpBaseUrl => 'http://$host:$port';
}
