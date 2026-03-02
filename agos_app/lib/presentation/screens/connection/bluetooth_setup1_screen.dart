import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../../core/constants/connection_method_design.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/services/ble_provisioning_service.dart';

class BluetoothSetup1Screen extends StatefulWidget {
  const BluetoothSetup1Screen({super.key});

  @override
  State<BluetoothSetup1Screen> createState() => _BluetoothSetup1ScreenState();
}

class _BluetoothSetup1ScreenState extends State<BluetoothSetup1Screen> {
  bool _enabling = false;
  final _ble = BleProvisioningService();

  Future<void> _enableBluetooth() async {
    if (_ble.simulationMode) {
      // In simulation mode, skip the real Bluetooth dialog
      if (mounted) Navigator.pushNamed(context, '/bluetooth-setup-2');
      return;
    }
    setState(() => _enabling = true);
    try {
      await FlutterBluePlus.turnOn();
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) Navigator.pushNamed(context, '/bluetooth-setup-2');
    } catch (e) {
      if (mounted) Navigator.pushNamed(context, '/bluetooth-setup-2');
    } finally {
      if (mounted) setState(() => _enabling = false);
    }
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
                                'Bluetooth Setup',
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
                          'Enable Bluetooth on your phone so AGOS can discover the device',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w400,
                            color: const Color(0xFF45556C),
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 25),

                  // Enable Bluetooth card (matches Figma card tokens)
                  Container(
                  padding: const EdgeInsets.all(20),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Container(
                      //   width: 64,
                      //   height: 64,
                      //   decoration: BoxDecoration(
                      //     gradient: const LinearGradient(
                      //       colors: [ConnectionMethodDesign.bluetoothGradientStart, ConnectionMethodDesign.bluetoothGradientEnd],
                      //       begin: Alignment.topLeft,
                      //       end: Alignment.bottomRight,
                      //     ),
                      //     borderRadius: BorderRadius.circular(14),
                      //   ),
                      //   child: const Center(
                      //     child: Icon(Icons.bluetooth, color: Colors.white, size: 32),
                      //   ),
                      // ),
                      // const SizedBox(height: 18),
                      const Text(
                        'Enable Bluetooth',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0B3A57),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Turn on Bluetooth from your device settings or tap the button below to quickly enable it.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: ConnectionMethodDesign.cardDescriptionColor,
                          height: ConnectionMethodDesign.cardDescriptionLineHeight,
                        ),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        height: 40,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFC27AFF), Color(0xFFE60076)],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFC27AFF).withValues(alpha: 0.18),
                                blurRadius: 12,
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
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: _enabling ? null : _enableBluetooth,
                            child: _enabling
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  )
                                : const Text('Enable Bluetooth', style: TextStyle(fontWeight: FontWeight.w600, color: Color.fromARGB(255, 255, 255, 255))),
                          ),
                        ),
                      ),
                    ],
                  ),
                  ),
                  const SizedBox(height: 24),

                  // ── Simulation mode toggle (for testing without hardware) ──
                  StatefulBuilder(
                    builder: (context, setLocal) {
                      return GestureDetector(
                        onTap: () {
                          setLocal(() {
                            _ble.simulationMode = !_ble.simulationMode;
                          });
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(
                              _ble.simulationMode
                                  ? '🧪 Simulation mode ON — fake devices & WiFi networks will be shown'
                                  : '📡 Simulation mode OFF — using real hardware',
                            ),
                            duration: const Duration(seconds: 3),
                          ));
                        },
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
                      );
                    },
                  ),

                  const SizedBox(height: 20),

                  // Bottom action (Next)
                  // SizedBox(
                  //   width: double.infinity,
                  //   height: 40,
                  //   child: Container(
                  //     decoration: BoxDecoration(
                  //       gradient: const LinearGradient(colors: [Color(0xFFC27AFF), Color(0xFFE60076)]),
                  //       borderRadius: BorderRadius.circular(12),
                  //     ),
                  //     child: ElevatedButton(
                  //       style: ElevatedButton.styleFrom(
                  //         backgroundColor: Colors.transparent,
                  //         foregroundColor: Colors.white,
                  //         shadowColor: Colors.transparent,
                  //         elevation: 0,
                  //         shape: RoundedRectangleBorder(
                  //           borderRadius: BorderRadius.circular(12),
                  //         ),
                  //       ),
                  //       onPressed: () => Navigator.pushNamed(context, '/bluetooth-setup-2'),
                  //       child: const Text('Next', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  //     ),
                  //   ),
                  // ),
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
                        value: 0.25,
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

  // Widget _buildStepIndicator(int step, bool isActive) {
  //   return Container(
  //     width: 36,
  //     height: 36,
  //     decoration: BoxDecoration(
  //       color: isActive ? AppColors.primary : AppColors.neutral5.withValues(alpha: 0.3),
  //       shape: BoxShape.circle,
  //     ),
  //     child: Center(
  //       child: Text(
  //         '$step',
  //         style: const TextStyle(
  //           color: Colors.white,
  //           fontWeight: FontWeight.bold,
  //           fontSize: 16,
  //         ),
  //       ),
  //     ),
  //   );
  // }
}
