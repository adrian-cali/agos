import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Ready to Scan Screen for Bluetooth (Figma 335:831 & 335:871)
/// Shows two states: ready to scan (335:831) and scanning with devices (335:871)
class ReadyToScanBluetoothScreen extends StatefulWidget {
  const ReadyToScanBluetoothScreen({super.key});

  @override
  State<ReadyToScanBluetoothScreen> createState() => _ReadyToScanBluetoothScreenState();
}

class BluetoothDevice {
  final String name;
  final String signalStrength;
  
  const BluetoothDevice(this.name, this.signalStrength);
}

class _ReadyToScanBluetoothScreenState extends State<ReadyToScanBluetoothScreen> 
    with SingleTickerProviderStateMixin {
  bool _isScanning = false;
  bool _showDevices = false;
  bool _isConnecting = false;
  String? _selectedDevice;
  String? _errorMessage;
  late AnimationController _pulseController;
  
  // List of available Bluetooth devices
  final List<BluetoothDevice> _devices = const [
    BluetoothDevice('AGOS-Device-A1B2', 'Strong'),
    BluetoothDevice('Smart Speaker X1', 'Medium'),
    BluetoothDevice('Wireless Headphones', 'Strong'),
    BluetoothDevice('Fitness Tracker', 'Weak'),
    BluetoothDevice('Smart Watch Pro', 'Medium'),
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _startScanning() {
    setState(() {
      _isScanning = true;
      _showDevices = false;
      _selectedDevice = null;
      _errorMessage = null;
    });
    _pulseController.repeat(reverse: true);

    // Simulate device discovery after 2 seconds
    Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _showDevices = true;
          _isScanning = false;
        });
        _pulseController.stop();
      }
    });
  }

  void _connectDevice() async {
    if (_selectedDevice == null) {
      setState(() {
        _errorMessage = 'Please select a device first.';
      });
      return;
    }
    
    // Only allow connection to AGOS-Device-A1B2
    if (_selectedDevice != 'AGOS-Device-A1B2') {
      setState(() {
        _errorMessage = 'Please make sure to select the correct device and try again.';
      });
      return;
    }
    
    // Show loading and navigate
    setState(() {
      _isConnecting = true;
      _errorMessage = null;
    });
    
    // Simulate connection delay
    await Future.delayed(const Duration(seconds: 2));
    
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/pairing-device');
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
            begin: Alignment(-0.2, -1),
            end: Alignment(0.2, 1),
            colors: [
              Color(0xFFF8FAFC), // light slate
              Color(0xFFEFF6FF), // light blue
              Color(0xFFECFEFF), // light cyan
            ],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // Main content (behind progress bar)
            Center(
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
                          _showDevices
                            ? 'Select your AGOS device from the list'
                            : (_isScanning 
                                ? 'Scanning for nearby AGOS devices...'
                                : 'Scanning for nearby AGOS devices...'),
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w400,
                            color: const Color(0xFF45556C),
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 25),
                      
                      // Main card
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: const Color(0xB3FFFFFF), // 70% white
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0x2EFFFFFF), // 18% white
                            width: 1.18,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF5DADE2).withValues(alpha: 0.15),
                              blurRadius: 8,
                              offset: const Offset(0, 0),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(17.18),
                        child: Column(
                          children: [
                            if (!_isScanning && !_showDevices) ...[
                              // Ready to scan state (335:831)
                              // Bluetooth scan icon
                              Container(
                                width: 82,
                                height: 82,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFE0F2FF),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.bluetooth_searching,
                                  size: 48,
                                  color: Color(0xFF00B8DB),
                                ),
                              ),
                              const SizedBox(height: 11),
                              Text(
                                'Ready to scan',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w400,
                                  color: const Color(0xFF314158),
                                ),
                              ),
                              const SizedBox(height: 0),
                              Text(
                                'Make sure Bluetooth is enabled on your device',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w400,
                                  color: const Color(0xFF62748E),
                                ),
                              ),
                              const SizedBox(height: 24),
                            ] else if (_isScanning) ...[
                              // Scanning state (no device yet)
                              const SizedBox(height: 16),
                              AnimatedBuilder(
                                animation: _pulseController,
                                builder: (context, child) {
                                  return Transform.scale(
                                    scale: 1.0 + (_pulseController.value * 0.15),
                                    child: Container(
                                      width: 82,
                                      height: 82,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: const Color(0xFFAD46FF).withValues(alpha: 0.2),
                                      ),
                                      child: const Icon(
                                        Icons.bluetooth_searching,
                                        size: 40,
                                        color: Color(0xFFAD46FF),
                                      ),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 11),
                              Text(
                                'Scanning for devices...',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w400,
                                  color: const Color(0xFF314158),
                                ),
                              ),
                              const SizedBox(height: 24),
                            ] else if (_showDevices) ...[
                              // Devices found state - show list
                              Text(
                                'Available Devices',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF314158),
                                ),
                              ),
                              const SizedBox(height: 16),
                              
                              // Device list
                              ...List.generate(_devices.length, (index) {
                                final device = _devices[index];
                                final isSelected = _selectedDevice == device.name;
                                final isAGOS = device.name == 'AGOS-Device-A1B2';
                                
                                return Padding(
                                  padding: EdgeInsets.only(bottom: index < _devices.length - 1 ? 8 : 0),
                                  child: GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _selectedDevice = device.name;
                                        _errorMessage = null;
                                      });
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                      decoration: BoxDecoration(
                                        color: isSelected 
                                          ? const Color(0xFFE0F7FA) 
                                          : const Color(0xFFF8F9FA),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: isSelected 
                                            ? const Color(0xFF00BCD4) 
                                            : const Color(0xFFE0E0E0),
                                          width: isSelected ? 2 : 1,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            isAGOS ? Icons.router : Icons.devices,
                                            color: isSelected 
                                              ? const Color(0xFF00B8DB) 
                                              : const Color(0xFF62748E),
                                            size: 24,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  device.name,
                                                  style: GoogleFonts.inter(
                                                    fontSize: 14,
                                                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                                                    color: const Color(0xFF314158),
                                                  ),
                                                ),
                                                Text(
                                                  'Signal strength: ${device.signalStrength}',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w400,
                                                    color: const Color(0xFF62748E),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (isSelected)
                                            Container(
                                              width: 24,
                                              height: 24,
                                              decoration: const BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: Color(0xFF00C896),
                                              ),
                                              child: const Icon(
                                                Icons.check,
                                                color: Colors.white,
                                                size: 16,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }),
                              const SizedBox(height: 16),
                            ],
                            
                            // Error message
                            if (_errorMessage != null) ...[
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF3F3),
                                  border: Border.all(
                                    color: const Color(0xFFFFCDD2),
                                    width: 1,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.error_outline,
                                      size: 20,
                                      color: Color(0xFFD32F2F),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _errorMessage!,
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w400,
                                          color: const Color(0xFFD32F2F),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                            
                            // Info banner (show when not scanning and not showing devices)
                            if (!_isScanning && !_showDevices)
                              Container(
                                padding: const EdgeInsets.all(13.17),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFAF5FF),
                                  border: Border.all(
                                    color: const Color(0xFFE9D4FF),
                                    width: 1.18,
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(
                                      Icons.info_outline,
                                      size: 16,
                                      color: Color(0xFF8200DB),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Keep your phone within 10 meters of the AGOS device during setup',
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w400,
                                          color: const Color(0xFF8200DB),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 25),
                      
                      // Buttons
                      Column(
                        children: [
                          // Main action button
                          SizedBox(
                            width: double.infinity,
                            height: 40,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: _showDevices 
                                  ? const LinearGradient(
                                      colors: [Color(0xFFAD46FF), Color(0xFFE60076)],
                                    )
                                  : const LinearGradient(
                                      colors: [Color(0xFFAD46FF), Color(0xFFE60076)],
                                    ),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: ElevatedButton(
                                onPressed: _isConnecting 
                                  ? null 
                                  : (_showDevices ? _connectDevice : (_isScanning ? null : _startScanning)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  disabledBackgroundColor: Colors.transparent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      _showDevices 
                                        ? (_isConnecting ? 'Connecting...' : 'Connect via Bluetooth')
                                        : 'Scan for Devices',
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.white,
                                      ),
                                    ),
                                    if (_isConnecting) ...[
                                      const SizedBox(width: 12),
                                      const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                        ),
                                      ),
                                    ] else ...[
                                      const SizedBox(width: 8),
                                      const Icon(Icons.arrow_forward, size: 16, color: Colors.white),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          
                          // Back button
                          SizedBox(
                            width: double.infinity,
                            height: 40,
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(context),
                              style: OutlinedButton.styleFrom(
                                backgroundColor: Colors.white,
                                side: const BorderSide(
                                  color: Color(0xFFA2F4FD),
                                  width: 1.18,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.arrow_back,
                                    size: 16,
                                    color: Color(0xFF0A1929),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Back',
                                    style: GoogleFonts.inter(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: const Color(0xFF0A1929),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
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
}

