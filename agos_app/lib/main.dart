import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'core/router/app_router.dart';
import 'core/constants/app_colors.dart';
import 'core/services/local_notification_service.dart';
import 'data/services/filter_reminder_service.dart';
import 'data/services/firestore_service.dart';
import 'data/services/websocket_service.dart'
  show AlertItem, alertsProvider, cachedAlertsProvider, pushNotificationsEnabledProvider;
import 'firebase_options.dart';
import 'presentation/screens/splash/splash_screen.dart';

/// Top-level handler required by firebase_messaging for background/terminated state.
/// Must be a top-level (non-anonymous) function annotated with @pragma('vm:entry-point').
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Firebase must be initialised in the background isolate before any usage.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // The FCM plugin shows the notification automatically in background/terminated state.
  // Nothing else to do here.
}

void main() async {
  // Forcing clean rebuild - iOS native splash disabled
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (!kIsWeb) {
    // Register background FCM handler before anything else.
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

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
  await FilterReminderNotifier.scheduleFromPrefs();
}

class AgosApp extends ConsumerStatefulWidget {
  const AgosApp({super.key});

  @override
  ConsumerState<AgosApp> createState() => _AgosAppState();
}

class _AgosAppState extends ConsumerState<AgosApp> {
  /// Tracks the UID we last saved an FCM token for, to avoid repeated saves on
  /// every rebuild. Null means we haven't saved for any user yet this session.
  String? _tokenSavedForUid;

  @override
  void initState() {
    super.initState();
    _setupFcmHandlers();
  }

  /// Set up FCM foreground + token-refresh listeners.
  /// Called once in initState — safe because these are persistent subscriptions
  /// that live for the app lifetime.
  void _setupFcmHandlers() {
    if (kIsWeb) return;

    // Show a local notification when a push arrives while the app is in foreground.
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final n = message.notification;
      if (n != null) {
        LocalNotificationService().showAlert(
          id: message.hashCode,
          title: n.title ?? 'AGOS Alert',
          body: n.body ?? '',
        );
      }
      _ingestRemoteMessageAsAlert(message);
    });

    // If user taps a notification and opens/resumes the app, add it in-app too.
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _ingestRemoteMessageAsAlert(message);
    });

    // Cold-start from notification tap.
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) {
        _ingestRemoteMessageAsAlert(message);
      }
    });

    // Re-save token whenever FCM rotates it (typically every few weeks).
    FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      final user = ref.read(currentUserProvider);
      if (user != null) {
        ref.read(firestoreServiceProvider).saveFcmToken(user.uid, token);
      }
    });
  }

  void _ingestRemoteMessageAsAlert(RemoteMessage message) {
    if (!ref.read(pushNotificationsEnabledProvider)) return;

    final now = DateTime.now().toIso8601String();
    final data = message.data;
    final metric = (data['metric'] ?? 'system').toString();
    final title = message.notification?.title ??
        data['title']?.toString() ??
        'AGOS Alert';
    final body = message.notification?.body ??
        data['body']?.toString() ??
        'A new AGOS notification was received.';
    final id = (message.messageId != null && message.messageId!.isNotEmpty)
        ? 'fcm_${message.messageId}'
        : 'fcm_${DateTime.now().millisecondsSinceEpoch}';

    final notifier = ref.read(alertsProvider.notifier);
    if (ref.read(alertsProvider).any((a) => a.id == id)) {
      return;
    }

    final alert = AlertItem(
      id: id,
      type: metric,
      title: title,
      description: body,
      timestamp: now,
      severity: metric == 'level' ? 'warning' : 'warning',
    );
    notifier.addAlert(alert);
    ref.read(cachedAlertsProvider.notifier).addOrUpdate(alert);
  }

  @override
  Widget build(BuildContext context) {
    // Save/refresh the FCM token whenever the signed-in user changes.
    ref.listen<AsyncValue<User?>>(authStateProvider, (_, next) {
      next.whenData((user) {
        if (user != null && user.uid != _tokenSavedForUid) {
          _tokenSavedForUid = user.uid;
          _saveFcmToken(user.uid);
        } else if (user == null) {
          _tokenSavedForUid = null; // allow re-save on next login
        }
      });
    });

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

  /// Requests the FCM token and persists it to Firestore under the user's document.
  Future<void> _saveFcmToken(String uid) async {
    if (kIsWeb) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && mounted) {
        await ref.read(firestoreServiceProvider).saveFcmToken(uid, token);
        debugPrint('[FCM] Token saved for user $uid');
      }
    } catch (e) {
      debugPrint('[FCM] Failed to save token: $e');
    }
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
