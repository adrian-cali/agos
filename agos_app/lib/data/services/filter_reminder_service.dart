import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/local_notification_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Filter Reminder Settings
// Persists the user's chosen reminder interval and day-of-month.
// Default: remind every 1 month, on the 20th, at 9:00 AM.
// ─────────────────────────────────────────────────────────────────────────────

class FilterReminderSettings {
  /// Day of month (1–28) on which to show the reminder.
  final int dayOfMonth;

  /// Interval in months between reminders (1 = monthly, 2 = bi-monthly, etc.).
  final int intervalMonths;

  /// Whether the reminder is enabled at all.
  final bool enabled;

  const FilterReminderSettings({
    this.dayOfMonth = 20,
    this.intervalMonths = 1,
    this.enabled = true,
  });

  FilterReminderSettings copyWith({
    int? dayOfMonth,
    int? intervalMonths,
    bool? enabled,
  }) =>
      FilterReminderSettings(
        dayOfMonth: dayOfMonth ?? this.dayOfMonth,
        intervalMonths: intervalMonths ?? this.intervalMonths,
        enabled: enabled ?? this.enabled,
      );
}

class FilterReminderNotifier extends StateNotifier<FilterReminderSettings> {
  static const _keyDay = 'filter_reminder_day';
  static const _keyInterval = 'filter_reminder_interval_months';
  static const _keyEnabled = 'filter_reminder_enabled';

  FilterReminderNotifier() : super(const FilterReminderSettings()) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        state = FilterReminderSettings(
          dayOfMonth: prefs.getInt(_keyDay) ?? 20,
          intervalMonths: prefs.getInt(_keyInterval) ?? 1,
          enabled: prefs.getBool(_keyEnabled) ?? true,
        );
      }
    } catch (_) {}
  }

  Future<void> update({
    int? dayOfMonth,
    int? intervalMonths,
    bool? enabled,
  }) async {
    state = state.copyWith(
      dayOfMonth: dayOfMonth,
      intervalMonths: intervalMonths,
      enabled: enabled,
    );
    final prefs = await SharedPreferences.getInstance();
    prefs.setInt(_keyDay, state.dayOfMonth);
    prefs.setInt(_keyInterval, state.intervalMonths);
    prefs.setBool(_keyEnabled, state.enabled);
    // Reschedule the OS notification with the new settings
    await scheduleNotification(state);
  }

  /// Schedule (or cancel) the OS reminder based on current settings.
  static Future<void> scheduleNotification(
      FilterReminderSettings settings) async {
    final svc = LocalNotificationService();
    if (!settings.enabled) {
      await svc.cancelFilterReminder();
      return;
    }
    await svc.scheduleFilterReminder(
      dayOfMonth: settings.dayOfMonth,
      intervalMonths: settings.intervalMonths,
      hour: 9, // 9:00 AM
      minute: 0,
    );
  }

  /// Loads settings from SharedPreferences and schedules the OS notification.
  /// Use this from app startup code (e.g. main.dart) where there is no
  /// access to a Riverpod container — avoids the `state` accessor restriction.
  static Future<void> scheduleFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settings = FilterReminderSettings(
        dayOfMonth: prefs.getInt(_keyDay) ?? 20,
        intervalMonths: prefs.getInt(_keyInterval) ?? 1,
        enabled: prefs.getBool(_keyEnabled) ?? true,
      );
      await scheduleNotification(settings);
    } catch (_) {}
  }
}

final filterReminderProvider =
    StateNotifierProvider<FilterReminderNotifier, FilterReminderSettings>(
        (ref) => FilterReminderNotifier());

