import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/connection_method_design.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/services/ble_provisioning_service.dart';
import '../../../data/services/firestore_service.dart';

class DeviceSetupIntroScreen extends StatefulWidget {
  const DeviceSetupIntroScreen({super.key});

  @override
  State<DeviceSetupIntroScreen> createState() => _DeviceSetupIntroScreenState();
}

class _DeviceSetupIntroScreenState extends State<DeviceSetupIntroScreen> {
  final _ble = BleProvisioningService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || !mounted) return;
      final hasDevice = await FirestoreService().hasLinkedDevice(user.uid);
      if (!mounted || !hasDevice) return;
      Navigator.pushReplacementNamed(context, '/home');
    });
  }

  void _toggleSimulation() {
    setState(() {
      _ble.simulationMode = !_ble.simulationMode;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        _ble.simulationMode
            ? 'Simulation mode ON — fake devices & WiFi networks will be shown'
            : 'Simulation mode OFF — using real hardware',
      ),
      duration: const Duration(seconds: 3),
    ));
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
            // ── Main scrollable content ──
            SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(25, 60, 25, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Back button ──
                    GestureDetector(
                      onTap: () {
                        if (Navigator.canPop(context)) {
                          Navigator.pop(context);
                        } else {
                          Navigator.pushReplacementNamed(context, '/welcome');
                        }
                      },
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.8),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.neutral5.withOpacity(0.4),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.arrow_back_ios,
                          size: 18,
                          color: Color(0xFF141A1E),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ── Title ──
                    ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [Color(0xFF1447E6), Color(0xFF0092B8), Color(0xFF1447E6)],
                      ).createShader(bounds),
                      child: Text(
                        'AGOS Device Setup',
                        style: GoogleFonts.poppins(
                          fontSize: 24,
                          fontWeight: FontWeight.w400,
                          color: Colors.white,
                        ),
                      ),
                    ),

                    const SizedBox(height: 6),

                    // ── Subtitle ──
                    Text(
                      'Connect and configure your AGOS water monitoring system.',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w400,
                        color: const Color(0xFF45556C),
                      ),
                    ),

                    const SizedBox(height: 25),

                    // ── How setup works card ──
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: ConnectionMethodDesign.cardBackground,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.neutral5.withOpacity(0.6)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.03),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'How setup works:',
                            style: GoogleFonts.poppins(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFF1D293D),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // ── Step 1 ──
                          _buildStepRow(
                            stepNumber: 1,
                            gradientColors: const [Color(0xFFC27AFF), Color(0xFFE60076)],
                            icon: Icons.bluetooth,
                            title: 'Enable Bluetooth',
                            description: 'Allow the app to scan nearby AGOS devices.',
                          ),

                          const SizedBox(height: 14),

                          // ── Step 2 ──
                          _buildStepRow(
                            stepNumber: 2,
                            gradientColors: const [Color(0xFF1447E6), Color(0xFF0092B8)],
                            icon: Icons.radar,
                            title: 'Find Your Device',
                            description: 'Select your AGOS hardware from the scan results.',
                          ),

                          const SizedBox(height: 14),

                          // ── Step 3 ──
                          _buildStepRow(
                            stepNumber: 3,
                            gradientColors: const [Color(0xFF00B894), Color(0xFF00CEC9)],
                            icon: Icons.wifi,
                            title: 'Configure WiFi',
                            description: 'Enter your home WiFi so the device connects automatically.',
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ── Start Setup button ──
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF00B8DB), Color(0xFF155DFC)],
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF1447E6).withOpacity(0.22),
                              blurRadius: 14,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            foregroundColor: Colors.white,
                            shadowColor: Colors.transparent,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: () => Navigator.pushNamed(context, '/bluetooth-setup-1'),
                          child: Text(
                            'Start Setup',
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── Simulation mode toggle ──
                    Center(
                      child: GestureDetector(
                        onTap: _toggleSimulation,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: _ble.simulationMode
                                ? const Color(0xFFDCFCE7)
                                : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _ble.simulationMode
                                  ? const Color(0xFF16A34A)
                                  : const Color(0xFFCBD5E1),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _ble.simulationMode
                                    ? Icons.science
                                    : Icons.science_outlined,
                                size: 16,
                                color: _ble.simulationMode
                                    ? const Color(0xFF16A34A)
                                    : const Color(0xFF64748B),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _ble.simulationMode
                                    ? 'Simulation Mode: ON'
                                    : 'Simulation Mode: OFF',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: _ble.simulationMode
                                      ? const Color(0xFF16A34A)
                                      : const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Progress bar overlay (top) ──
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
                        value: 0.00,
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

  Widget _buildStepRow({
    required int stepNumber,
    required List<Color> gradientColors,
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Step number circle with gradient
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: gradientColors,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(
            icon,
            color: Colors.white,
            size: 24,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: gradientColors,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '$stepNumber',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: const Color(0xFF1D293D),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                description,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: const Color(0xFF62748E),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
