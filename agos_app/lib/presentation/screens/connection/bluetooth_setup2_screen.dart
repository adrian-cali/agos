import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/constants/connection_method_design.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/services/ble_provisioning_service.dart';

class BluetoothSetup2Screen extends StatefulWidget {
  const BluetoothSetup2Screen({super.key});

  @override
  State<BluetoothSetup2Screen> createState() => _BluetoothSetup2ScreenState();
}

class _BluetoothSetup2ScreenState extends State<BluetoothSetup2Screen>
    with WidgetsBindingObserver {
  bool _locationPermission = false;
  bool _bluetoothPermission = false;
  bool _isRequesting = false;
  final _ble = BleProvisioningService();

  bool get _allPermissionsGranted =>
      _locationPermission && _bluetoothPermission;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // In simulation mode, pre-grant both permissions and auto-advance
    if (_ble.simulationMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          _locationPermission = true;
          _bluetoothPermission = true;
        });
        Future.delayed(const Duration(milliseconds: 400), () {
          if (mounted) Navigator.pushNamed(context, '/ready-to-scan');
        });
      });
    } else {
      // Check if permissions were already granted (e.g. returning to this screen)
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkCurrentStatus());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Re-check permission status when the app resumes (e.g. after going to Settings)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkCurrentStatus();
    }
  }

  Future<void> _checkCurrentStatus() async {
    final locGranted = (await Permission.locationWhenInUse.status).isGranted;
    final bleGranted = (await Permission.bluetoothScan.status).isGranted &&
        (await Permission.bluetoothConnect.status).isGranted;
    if (!mounted) return;
    setState(() {
      _locationPermission = locGranted;
      _bluetoothPermission = bleGranted;
    });
    if (locGranted && bleGranted) {
      Future.delayed(const Duration(milliseconds: 250), () {
        if (mounted) Navigator.pushNamed(context, '/ready-to-scan');
      });
    }
  }

  Future<void> _grantPermission(String which) async {
    if (_isRequesting) return;

    // In simulation mode, just mark as granted and advance
    if (_ble.simulationMode) {
      setState(() {
        if (which == 'location') _locationPermission = true;
        if (which == 'bluetooth') _bluetoothPermission = true;
      });
      if (_locationPermission && _bluetoothPermission) {
        Future.delayed(const Duration(milliseconds: 250), () {
          if (mounted) Navigator.pushNamed(context, '/ready-to-scan');
        });
      }
      return;
    }

    setState(() => _isRequesting = true);

    try {
      if (which == 'location') {
        final status = await Permission.locationWhenInUse.request();
        setState(() => _locationPermission = status.isGranted);
        if (!status.isGranted && mounted) {
          _showDeniedSnack('Location permission is required for Bluetooth scanning.');
        }
      } else if (which == 'bluetooth') {
        // On Android 12+ request SCAN + CONNECT; on older versions they are
        // automatically granted together with BLUETOOTH.
        final statuses = await [
          Permission.bluetoothScan,
          Permission.bluetoothConnect,
        ].request();
        final granted = statuses.values.every((s) => s.isGranted);
        setState(() => _bluetoothPermission = granted);
        if (!granted && mounted) {
          _showDeniedSnack('Bluetooth permission is required to connect to your device.');
        }
      }
    } finally {
      if (mounted) setState(() => _isRequesting = false);
    }

    // Auto-advance when both are granted
    if (_locationPermission && _bluetoothPermission) {
      Future.delayed(const Duration(milliseconds: 250), () {
        if (mounted) Navigator.pushNamed(context, '/ready-to-scan');
      });
    }
  }

  void _showDeniedSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: const SnackBarAction(
          label: 'Settings',
          onPressed: openAppSettings,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment(-0.5, -1),
            end: Alignment(0.5, 1),
            colors: ConnectionMethodDesign.backgroundGradient,
            stops: ConnectionMethodDesign.backgroundGradientStops,
          ),
        ),
        child: Stack(
          children: [
            // Main content (behind progress bar)
            SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 25),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                  
                  // Header with icon and title
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Bluetooth icon
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFFC27AFF), Color(0xFFE60076)],
                              ),
                            ),
                            child: const Icon(
                              Icons.bluetooth,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 10),
                          // Title
                          Expanded(
                            child: ShaderMask(
                              shaderCallback: (bounds) => const LinearGradient(
                                colors: [Color(0xFF1447E6), Color(0xFF0092B8), Color(0xFF1447E6)],
                              ).createShader(bounds),
                              child: Text(
                                'Grant Permissions',
                                style: GoogleFonts.poppins(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w400,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      
                      // Subtitle
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'AGOS needs a few permissions to discover and connect to your device',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w400,
                            color: const Color(0xFF45556C),
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 25),

                  // Permission cards (use MCP tokens / card styling)
                  Column(
                    children: [
                      _buildPermissionCard(
                        icon: Icons.location_on,
                        title: 'Location Access',
                      subtitle: 'Required for Bluetooth scanning',
                      granted: _locationPermission,
                      onGrant: () => _grantPermission('location'),
                    ),
                    const SizedBox(height: 12),
                    _buildPermissionCard(
                      icon: Icons.bluetooth,
                      title: 'Bluetooth Access',
                      subtitle: 'Required to connect to device',
                      granted: _bluetoothPermission,
                      onGrant: () => _grantPermission('bluetooth'),
                    ),
                  ],
                  ),
                  const SizedBox(height: 24),

                  // Step indicator
                  // Row(
                  //   mainAxisAlignment: MainAxisAlignment.center,
                  //   children: [
                  //     _buildStepIndicator(1, false),
                  //     Container(width: 40, height: 2, color: AppColors.neutral5.withValues(alpha: 0.45)),
                  //     _buildStepIndicator(2, true),
                  //   ],
                  // ),
                  const SizedBox(height: 20),

                  // Bottom primary action (Next) — gradient, matches other connection screens
                  SizedBox(
                    width: double.infinity,
                    height: 40,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFFAD46FF), Color(0xFFE60076)]),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          shadowColor: Colors.transparent,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _allPermissionsGranted
                            ? () => Navigator.pushNamed(context, '/ready-to-scan')
                            : null,
                        child: const Text('Next', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color.fromARGB(255, 255, 255, 255))),
                      ),
                    ),
                  ),
                    ],
                  ),
                ),
              ),
            ),

            // Progress bar overlay (on top, in SafeArea)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(25, 9, 25, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: const LinearProgressIndicator(
                        value: 0.29,
                        minHeight: 8,
                        backgroundColor: Color.fromRGBO(15, 23, 42, 0.20),
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0F172A)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Setting up your AGOS system...',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        height: 16 / 12,
                        color: const Color(0xFF45556C),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool granted,
    required VoidCallback onGrant,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ConnectionMethodDesign.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.neutral5.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: granted
                  ? const LinearGradient(colors: [Color(0xFF9BE7D7), Color(0xFF6CE2A0)])
                  : const LinearGradient(colors: [ConnectionMethodDesign.bluetoothGradientStart, ConnectionMethodDesign.bluetoothGradientEnd]),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: ConnectionMethodDesign.cardTitleColor,
                        fontSize: ConnectionMethodDesign.cardTitleFontSize,
                        fontWeight: ConnectionMethodDesign.cardTitleFontWeight)),
                const SizedBox(height: 6),
                Text(subtitle,
                    style: const TextStyle(
                        color: ConnectionMethodDesign.cardDescriptionColor,
                        fontSize: ConnectionMethodDesign.cardDescriptionFontSize,
                        height: ConnectionMethodDesign.cardDescriptionLineHeight)),
              ],
            ),
          ),
          if (granted)
            const Icon(Icons.check_circle, color: AppColors.success, size: 28)
          else
            SizedBox(
              width: 88,
              height: 36,
              child: OutlinedButton(
                onPressed: onGrant,
                style: OutlinedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.primary,
                  side: BorderSide(color: AppColors.primary.withValues(alpha: 0.12)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Grant', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.neutral1)),
              ),
            ),
        ],
      ),
    );
  }

  // Widget _buildStepIndicator(int step, bool isActive) {
  //   return Container(
  //     width: 36,
  //     height: 36,
  //     decoration: BoxDecoration(
  //       color: isActive ? AppColors.primary : AppColors.neutral5.withValues(alpha: 0.3),
  //       shape: BoxShape.circle,
  //     ),
  //     child: Center(
  //       child: Text('$step',
  //           style: const TextStyle(
  //               color: Colors.white,
  //               fontWeight: FontWeight.bold,
  //               fontSize: 16)),
  //     ),
  //   );
  // }
}
