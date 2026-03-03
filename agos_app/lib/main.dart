import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'core/router/app_router.dart';
import 'core/constants/app_colors.dart';
import 'core/services/local_notification_service.dart';
import 'data/services/filter_reminder_service.dart';
import 'firebase_options.dart';
import 'presentation/screens/splash/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (!kIsWeb) {
    // flutter_local_notifications is not supported on web
    await LocalNotificationService().init();
    await LocalNotificationService().requestPermission();
    // Ensure the filter cleaning reminder is scheduled
    await _ensureFilterReminderScheduled();
  }
  runApp(const ProviderScope(child: AgosApp()));
}

/// Loads saved filter reminder settings and (re-)schedules the OS notification.
/// Safe to call every startup — already-scheduled reminders are replaced with
/// refreshed ones so the interval/day stays in sync with the user's settings.
Future<void> _ensureFilterReminderScheduled() async {
  try {
    final notifier = FilterReminderNotifier();
    // Allow a brief tick for the async SharedPreferences load in the notifier
    await Future.delayed(const Duration(milliseconds: 150));
    await FilterReminderNotifier.scheduleNotification(notifier.state);
  } catch (_) {}
}

class AgosApp extends StatelessWidget {
  const AgosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AGOS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: AppColors.background,
        useMaterial3: true,
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
            TargetPlatform.android: CupertinoPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          },
        ),
      ),
      home: const _AuthGate(),
      onGenerateRoute: AppRouter.generateRoute,
    );
  }
}

/// Always shows the splash screen on startup.
/// The splash screen itself is responsible for routing after its animation.
class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    return const SplashScreen();
  }
}
