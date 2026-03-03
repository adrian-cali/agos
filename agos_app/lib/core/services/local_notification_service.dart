import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/painting.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

// ─────────────────────────────────────────────────────────────────────────────
// Local Notification Service
// Wraps flutter_local_notifications for in-device OS-level notifications.
// ─────────────────────────────────────────────────────────────────────────────

class LocalNotificationService {
  static final LocalNotificationService _instance =
      LocalNotificationService._internal();
  factory LocalNotificationService() => _instance;
  LocalNotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  static const _channelId = 'agos_alerts';
  static const _channelName = 'AGOS Alerts';
  static const _channelDesc = 'Water monitoring system alerts and warnings';

  Future<void> init() async {
    if (kIsWeb) return; // flutter_local_notifications not supported on web
    if (_initialized) return;

    // Initialise timezone database
    tz_data.initializeTimeZones();

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    await _plugin.initialize(initSettings);

    // Create the Android notification channel
    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.high,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    _initialized = true;
  }

  /// Request notification permission (Android 13+ / iOS).
  Future<void> requestPermission() async {
    if (kIsWeb) return; // not supported on web
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  Future<void> showAlert({
    required int id,
    required String title,
    required String body,
  }) async {
    if (kIsWeb) return;
    if (!_initialized) await init();

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    await _plugin.show(id, title, body, details);
  }

  /// Convenience: show an ESP32 offline notification.
  Future<void> showEsp32Offline() async {
    if (kIsWeb) return;
    if (!_initialized) await init();

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.high,
      priority: Priority.high,
      icon: '@drawable/ic_notif_connection',
      color: Color(0xFFF59E0B), // amber — connection/offline warning
    );
    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    await _plugin.show(
      1001,
      'ESP32 Connection Lost',
      'No data received from the sensor. Check your network or device power.',
      details,
    );
  }

  /// Show a threshold-exceeded OS notification from an alert.
  /// [color] is the accent color shown on the notification icon (matches the
  /// parameter's icon gradient color in the dashboard).
  /// Uses a stable numeric ID derived from the alertId string hash so the same
  /// alert never fires twice, even if the method is called again.
  Future<void> showThresholdAlert({
    required String alertId,
    required String title,
    required String body,
    Color color = const Color(0xFF00D3F2), // default: turbidity cyan
  }) async {
    if (kIsWeb) return;
    if (!_initialized) await init();

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      color: color,
    );
    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    final details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    final notifId = alertId.hashCode.abs() % 100000 + 2000;
    await _plugin.show(notifId, title, body, details);
  }

  /// Show a filter cleaning reminder notification.
  Future<void> showFilterReminder() async {
    if (kIsWeb) return;
    if (!_initialized) await init();

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: '@mipmap/ic_launcher',
      color: Color(0xFF009966), // green — maintenance/health
    );
    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: false,
      presentSound: true,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    await _plugin.show(
      3001,
      'Filter Cleaning Reminder',
      'It\'s time to clean your water filter. Regular cleaning keeps your water quality optimal.',
      details,
    );
  }

  /// Schedule a recurring filter cleaning reminder.
  /// [dayOfMonth] — day (1–28) of month to fire the notification.
  /// [intervalMonths] — repeat every N months.
  /// [hour] / [minute] — time of day to fire (default 9:00 AM).
  /// [localTimeZone] — IANA timezone name (e.g. "Asia/Manila"). If null,
  ///   falls back to the device local timezone.
  Future<void> scheduleFilterReminder({
    required int dayOfMonth,
    required int intervalMonths,
    int hour = 9,
    int minute = 0,
    String? localTimeZone,
  }) async {
    if (kIsWeb) return;
    if (!_initialized) await init();

    // Cancel any existing filter reminder first
    await cancelFilterReminder();

    final tz.Location location = localTimeZone != null
        ? tz.getLocation(localTimeZone)
        : tz.local;

    // Find the next scheduled date
    final now = tz.TZDateTime.now(location);
    tz.TZDateTime scheduled = tz.TZDateTime(
      location,
      now.year,
      now.month,
      dayOfMonth,
      hour,
      minute,
    );

    // If that date/time is already in the past this month, move to next month
    if (scheduled.isBefore(now)) {
      scheduled = tz.TZDateTime(
        location,
        now.year,
        now.month + 1,
        dayOfMonth,
        hour,
        minute,
      );
    }

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: '@mipmap/ic_launcher',
      color: Color(0xFF009966),
    );
    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: false,
      presentSound: true,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    // Use monthly repeat (DateTimeComponents.dayOfMonthAndTime) when
    // intervalMonths == 1; otherwise schedule a one-shot and reschedule on
    // app open for longer intervals.
    if (intervalMonths == 1) {
      await _plugin.zonedSchedule(
        3001,
        'Filter Cleaning Reminder',
        'It\'s time to clean your water filter. Regular cleaning keeps your water quality optimal.',
        scheduled,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.dayOfMonthAndTime,
      );
    } else {
      // For multi-month intervals, schedule a one-shot notification.
      // The app will reschedule it on next open after it fires.
      await _plugin.zonedSchedule(
        3001,
        'Filter Cleaning Reminder',
        'It\'s time to clean your water filter. Regular cleaning keeps your water quality optimal.',
        scheduled,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  /// Cancel any pending filter cleaning reminder.
  Future<void> cancelFilterReminder() async {
    if (kIsWeb) return;
    if (!_initialized) await init();
    await _plugin.cancel(3001);
  }
}
