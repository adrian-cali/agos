import 'package:flutter/cupertino.dart';
import '../../presentation/screens/splash/splash_screen.dart';
import '../../presentation/screens/welcome/welcome_screen.dart';
import '../../presentation/screens/auth/login_screen.dart';
import '../../presentation/screens/auth/register_screen.dart';
import '../../presentation/screens/auth/forgot_password_screen.dart';
import '../../presentation/screens/connection/device_setup_intro_screen.dart';
import '../../presentation/screens/connection/wifi_setup_screen.dart';
import '../../presentation/screens/connection/bluetooth_setup1_screen.dart';
import '../../presentation/screens/connection/bluetooth_setup2_screen.dart';
import '../../presentation/screens/pairing/ready_to_pair_screen.dart';
import '../../presentation/screens/pairing/ready_to_scan_bluetooth_screen.dart';
import '../../presentation/screens/pairing/pairing_device_screen.dart';
import '../../presentation/screens/pairing/device_information_screen.dart';
import '../../presentation/screens/pairing/setup_complete_screen.dart';
import '../../presentation/screens/home/home_screen.dart';
import '../../presentation/screens/dashboard/dashboard_screen.dart';
import '../../presentation/screens/tank/tank_details_screen.dart';
import '../../presentation/screens/profile/edit_profile_screen.dart';
import '../../presentation/screens/settings/settings_screen.dart';
import '../../presentation/screens/settings/privacy_security_screen.dart';
import '../../presentation/screens/settings/alert_settings_screen.dart';
import '../../presentation/screens/settings/water_quality_thresholds_screen.dart';
import '../../presentation/screens/settings/data_logging_screen.dart';
import '../../presentation/screens/settings/help_screen.dart';
import '../../presentation/screens/settings/about_screen.dart';
import '../../presentation/screens/device/device_management_screen.dart';
import '../../presentation/screens/notifications/notifications_screen.dart';

class AppRouter {
  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/':
        return _buildRoute(const SplashScreen());
      case '/welcome':
        return _buildRoute(const WelcomeScreen());
      case '/login':
        return _buildRoute(const LoginScreen());
      case '/register':
        return _buildRoute(const RegisterScreen());
      case '/forgot-password':
        return _buildRoute(const ForgotPasswordScreen());
      case '/connection-method':
      case '/device-setup-intro':
        return _buildRouteNoTransition(const DeviceSetupIntroScreen());
      case '/wifi-setup':
        return _buildRouteNoTransition(const WifiSetupScreen());
      case '/bluetooth-setup-1':
        return _buildRouteNoTransition(const BluetoothSetup1Screen());
      case '/bluetooth-setup-2':
        return _buildRouteNoTransition(const BluetoothSetup2Screen());
      case '/ready-to-scan':
        return _buildRouteNoTransition(const ReadyToScanBluetoothScreen());
      case '/ready-to-pair':
        return _buildRouteNoTransition(const ReadyToPairScreen());
      case '/pairing-device':
        return _buildRouteNoTransition(const PairingDeviceScreen());
      case '/device-information':
        return _buildRouteNoTransition(const DeviceInformationScreen());
      case '/setup-complete':
        return _buildRouteNoTransition(const SetupCompleteScreen());
      case '/home':
        return _buildRouteNoTransition(const HomeScreen());
      case '/dashboard':
        return _buildRouteNoTransition(const DashboardScreen());
      case '/tank-details':
        return _buildRoute(const TankDetailsScreen());
      case '/edit-profile':
        return _buildRouteNoTransition(const EditProfileScreen());
      case '/settings':
        return _buildRouteNoTransition(const SettingsScreen());
      case '/privacy-security':
        return _buildRouteNoTransition(const PrivacySecurityScreen());
      case '/alert-settings':
        return _buildRouteNoTransition(const AlertSettingsScreen());
      case '/water-quality-thresholds':
        return _buildRouteNoTransition(const WaterQualityThresholdsScreen());
      case '/data-logging':
        return _buildRouteNoTransition(const DataLoggingScreen());
      case '/help':
        return _buildRouteNoTransition(const HelpScreen());
      case '/about':
        return _buildRouteNoTransition(const AboutScreen());
      case '/device-management':
        return _buildRoute(const DeviceManagementScreen());
      case '/notifications':
        return _buildRoute(const NotificationsScreen());
      default:
        return _buildRoute(const SplashScreen());
    }
  }

  static CupertinoPageRoute _buildRoute(Widget page) {
    return CupertinoPageRoute(builder: (_) => page);
  }

  static PageRouteBuilder _buildRouteNoTransition(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
    );
  }
}
