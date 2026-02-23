import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/connection_method_design.dart';
import '../../../core/constants/app_colors.dart';

// ---------- Ready to Pair (WiFi flow) ----------
class ReadyToPairScreen extends StatefulWidget {
  const ReadyToPairScreen({super.key});

  @override
  State<ReadyToPairScreen> createState() => _ReadyToPairScreenState();
}

class _ReadyToPairScreenState extends State<ReadyToPairScreen> {
  bool _isScanning = true;
  String? _selectedDevice;
  List<Map<String, dynamic>> _devices = [];

  @override
  void initState() {
    super.initState();
    _startScan(); // auto-start for WiFi ready-to-pair per Figma
  }

  void _startScan() {
    setState(() {
      _isScanning = true;
      _devices = [];
      _selectedDevice = null;
    });
    Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        _isScanning = false;
        _devices = [
          {'id': 'AGOS-WIFI-01', 'name': 'AGOS Device (WiFi)', 'rssi': -40},
        ];
      });
    });
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
              child: Column(
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pushReplacementNamed(context, '/connection-method'),
                      icon: const Icon(Icons.arrow_back_ios, color: Color(0xFF0B3A57)),
                    ),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            'Ready to Pair',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0B3A57),
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Preparing to pair your AGOS device',
                            style: TextStyle(
                              fontSize: 14,
                              color: Color(0xFF6D7E8B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _startScan,
                      icon: const Icon(Icons.refresh, color: AppColors.primary),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              if (_isScanning) ...[
                const SizedBox(height: 40),
                SizedBox(
                  width: 72,
                  height: 72,
                  child: CircularProgressIndicator(
                    strokeWidth: 4,
                    color: AppColors.primary.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Scanning for devices...',
                  style: TextStyle(color: ConnectionMethodDesign.cardDescriptionColor, fontSize: 16),
                ),
              ] else ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    '${_devices.length} device(s) found',
                    style: const TextStyle(color: ConnectionMethodDesign.cardDescriptionColor, fontSize: 14),
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    itemCount: _devices.length,
                    itemBuilder: (context, index) {
                      final device = _devices[index];
                      final isSelected = _selectedDevice == device['id'];
                      return GestureDetector(
                        onTap: () => setState(() => _selectedDevice = device['id']),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.primary.withValues(alpha: 0.06)
                                : Colors.white.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isSelected
                                  ? AppColors.primary.withValues(alpha: 0.18)
                                  : Colors.white.withValues(alpha: 0.08),
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.devices,
                                  color: isSelected
                                      ? AppColors.primary
                                      : Colors.white70,
                                  size: 28),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(device['name'],
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 4),
                                    Text('ID: ${device['id']}',
                                        style: TextStyle(
                                            color: Colors.white.withValues(alpha: 0.6),
                                            fontSize: 12)),
                                  ],
                                ),
                              ),
                              _buildSignalIcon(device['rssi'] as int),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],

              // Bottom action
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [AppColors.primary, AppColors.secondary]),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ElevatedButton(
                      onPressed: _selectedDevice != null
                          ? () => Navigator.pushReplacementNamed(context, '/pairing-device')
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        shadowColor: Colors.transparent,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Start Pairing', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.neutral1)),
                    ),
                  ),
                ),
              ),
            ],
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
                      value: 0.5,
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
          )
          ],
        ),
      ),
    );
  }

  Widget _buildSignalIcon(int rssi) {
    int bars = rssi.abs() < 50
        ? 4
        : rssi.abs() < 65
            ? 3
            : rssi.abs() < 80
                ? 2
                : 1;
    return Row(
      children: List.generate(4, (i) {
        return Container(
          width: 4,
          height: 6 + (i * 4.0),
          margin: const EdgeInsets.only(left: 2),
          decoration: BoxDecoration(
            color: i < bars ? AppColors.primary : Colors.white24,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }

}

// ---------- Ready to Scan (Bluetooth flow) ----------
class ReadyToScanScreen extends StatefulWidget {
  const ReadyToScanScreen({super.key});

  @override
  State<ReadyToScanScreen> createState() => _ReadyToScanScreenState();
}

class _ReadyToScanScreenState extends State<ReadyToScanScreen> {
  // start idle; user will tap "Scan for device"
  bool _isScanning = false;
  String? _selectedDevice;
  List<Map<String, dynamic>> _devices = [];

  @override
  void initState() {
    super.initState();
    // do not auto-scan on load — scanning starts when user taps the CTA
  }

  void _startScan() {
    setState(() {
      _isScanning = true;
      _devices = [];
    });
    Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _isScanning = false;
          _devices = [
            {'id': 'AGOS-A1B2', 'name': 'AGOS Tank Monitor', 'rssi': -45},
            {'id': 'AGOS-C3D4', 'name': 'AGOS Flow Sensor', 'rssi': -62},
            {'id': 'AGOS-E5F6', 'name': 'AGOS Quality Probe', 'rssi': -78},
          ];
        });
      }
    });
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
              child: Column(
                children: [
                  // Header row
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 52, 24, 12),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pushReplacementNamed(context, '/connection-method'),
                      icon: const Icon(Icons.arrow_back_ios, color: Color(0xFF0B3A57)),
                    ),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            'Ready to Scan',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0B3A57),
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Scan nearby AGOS devices and select one to connect',
                            style: TextStyle(
                              fontSize: 14,
                              color: Color(0xFF6D7E8B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _startScan,
                      icon: const Icon(Icons.refresh, color: AppColors.primary),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // Idle (no scan started) — show prominent "Scan for device" card (Figma)
              if (!_isScanning && _devices.isEmpty) ...[
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Container(
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
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [ConnectionMethodDesign.bluetoothGradientStart, ConnectionMethodDesign.bluetoothGradientEnd],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Center(
                            child: Icon(Icons.bluetooth_searching, color: Colors.white, size: 36),
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'Ready to Scan',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0B3A57),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Make sure your AGOS device is powered on and nearby, then tap Scan for device.',
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
                              gradient: const LinearGradient(colors: [AppColors.primary, AppColors.secondary]),
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
                              onPressed: _startScan,
                              child: const Text('Scan for device', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.neutral1)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ] else if (_isScanning) ...[
                const SizedBox(height: 40),
                SizedBox(
                  width: 72,
                  height: 72,
                  child: CircularProgressIndicator(
                    strokeWidth: 4,
                    color: AppColors.primary.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Scanning for devices...',
                  style: TextStyle(color: ConnectionMethodDesign.cardDescriptionColor, fontSize: 16),
                ),
              ] else ...[    
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    '${_devices.length} devices found',
                    style: const TextStyle(color: ConnectionMethodDesign.cardDescriptionColor, fontSize: 14),
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    itemCount: _devices.length,
                    itemBuilder: (context, index) {
                      final device = _devices[index];
                      final isSelected = _selectedDevice == device['id'];
                      return GestureDetector(
                        onTap: () {
                          setState(() => _selectedDevice = device['id']);
                          // immediately proceed to pairing (matches Figma flow)
                          Navigator.pushReplacementNamed(context, '/pairing-device');
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.primary.withValues(alpha: 0.06)
                                : ConnectionMethodDesign.cardBackground,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isSelected
                                  ? AppColors.primary.withValues(alpha: 0.18)
                                  : AppColors.neutral5.withValues(alpha: 0.35),
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.bluetooth,
                                  color: isSelected
                                      ? AppColors.primary
                                      : AppColors.neutral4,
                                  size: 28),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(device['name'],
                                        style: const TextStyle(
                                            color: ConnectionMethodDesign.cardTitleColor,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 4),
                                    Text('ID: ${device['id']}',
                                        style: const TextStyle(
                                            color: ConnectionMethodDesign.cardDescriptionColor,
                                            fontSize: 12)),
                                  ],
                                ),
                              ),
                              _buildSignalIcon(device['rssi'] as int),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [AppColors.primary, AppColors.secondary]),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ElevatedButton(
                      onPressed: _isScanning
                          ? null
                          : (_devices.isEmpty
                              ? _startScan
                              : (_selectedDevice != null
                                  ? () => Navigator.pushReplacementNamed(context, '/pairing-device')
                                  : null)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        shadowColor: Colors.transparent,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        _devices.isEmpty ? 'Scan for device' : 'Start Pairing',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.neutral1),
                      ),
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
          ],
        ),
      ),
    );
  }

  Widget _buildSignalIcon(int rssi) {
    int bars = rssi.abs() < 50
        ? 4
        : rssi.abs() < 65
            ? 3
            : rssi.abs() < 80
                ? 2
                : 1;
    return Row(
      children: List.generate(4, (i) {
        return Container(
          width: 4,
          height: 6 + (i * 4.0),
          margin: const EdgeInsets.only(left: 2),
          decoration: BoxDecoration(
            color: i < bars ? AppColors.primary : AppColors.neutral5.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }
}

