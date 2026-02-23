import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/connection_method_design.dart';
import '../../../core/constants/app_colors.dart';

class WifiSetupScreen extends StatefulWidget {
  const WifiSetupScreen({super.key});

  @override
  State<WifiSetupScreen> createState() => _WifiSetupScreenState();
}

class _WifiSetupScreenState extends State<WifiSetupScreen> {
  String? _selectedNetwork;
  final _ssidController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _showPassword = false;
  bool _isPasswordStep = false; // false => show available networks; true => show password entry
  bool _isConnecting = false;

  final List<Map<String, dynamic>> _networks = [
    {'name': 'Home_WiFi_5G', 'signal': 4, 'secured': true},
    {'name': 'AGOS_Network', 'signal': 3, 'secured': true},
    {'name': 'Office_WiFi', 'signal': 3, 'secured': true},
    {'name': 'Guest_Network', 'signal': 2, 'secured': false},
    {'name': 'IoT_Network', 'signal': 2, 'secured': true},
  ];

  @override
  void dispose() {
    _ssidController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _connect() async {
    final ssid = _ssidController.text.trim();
    // Password will be used for actual WiFi connection implementation

    if (ssid.isEmpty) return;

    setState(() => _isConnecting = true);

    // simulate connect attempt
    await Future.delayed(const Duration(seconds: 2));

    setState(() => _isConnecting = false);

    // on success navigate to Pairing Device
    if (mounted) Navigator.pushReplacementNamed(context, '/pairing-device');
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
            SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 25),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                  
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // WiFi icon
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFF53EAFD), Color(0xFF2B7FFF)],
                              ),
                            ),
                            child: const Icon(
                              Icons.wifi,
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
                                'WiFi Setup',
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
                          'Enter your WiFi credentials to connect the AGOS device to your network',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w400,
                            color: const Color(0xFF45556C),
                          ),
                        ),
                      ),
                  const SizedBox(height: 20),

                  // Card (networks list <-> password entry)
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    switchInCurve: Curves.easeOutCubic,
                    child: _isPasswordStep ? _buildPasswordCard() : _buildNetworksCard(),
                  ),
                  const SizedBox(height: 20),

                  // Action buttons (primary gradient + outlined back)
                  Column(
                  children: [
                    // Primary connect button shown only on password step
                    if (_isPasswordStep)
                      SizedBox(
                        width: double.infinity,
                        height: 40,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [AppColors.primary, AppColors.secondary],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withValues(alpha: 0.25),
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
                            onPressed: (_ssidController.text.trim().isNotEmpty &&
                                    (!_isNetworkSecured(_selectedNetwork) ||
                                        _passwordController.text.isNotEmpty) &&
                                    !_isConnecting)
                                ? _connect
                                : null,
                            child: _isConnecting
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        'Connect to WiFi',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      SizedBox(width: 8),
                                      Icon(Icons.arrow_forward, size: 18, color: Colors.white),
                                    ],
                                  ),
                          ),
                        ),
                      ),

                    const SizedBox(height: 12),

                    // Secondary back button
                    SizedBox(
                      width: double.infinity,
                      height: 40,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          if (_isPasswordStep) {
                            setState(() {
                              _isPasswordStep = false;
                              _selectedNetwork = null;
                              _passwordController.clear();
                            });
                          } else {
                            Navigator.pop(context);
                          }
                        },
                        icon: const Icon(Icons.chevron_left),
                        label: const Text('Back', style: TextStyle(color: AppColors.neutral1)),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: AppColors.darkBlue,
                          side: const BorderSide(color: ConnectionMethodDesign.backButtonBorderColor),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
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

  Widget _buildNetworksCard() {
    return Container(
      key: const ValueKey('networks-card'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Available networks',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF0B3A57),
            ),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _networks.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final network = _networks[index];
                final isSelected = _selectedNetwork == network['name'];
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedNetwork = network['name'];
                      _ssidController.text = network['name'];
                      _passwordController.clear();
                      _isPasswordStep = true;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary.withValues(alpha: 0.06)
                          : AppColors.cardBackground,
                      borderRadius: BorderRadius.circular(ConnectionMethodDesign.iconRadius),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.primary.withValues(alpha: 0.18)
                            : AppColors.neutral5.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF53EAFD), Color(0xFF2B7FFF)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(ConnectionMethodDesign.iconRadius),
                          ),
                          child: const Center(
                            child: Icon(Icons.wifi, color: Colors.white, size: 18),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                network['name'],
                                style: TextStyle(
                                  color: AppColors.neutral1,
                                  fontSize: 15,
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                network['secured'] ? 'Secured' : 'Open',
                                style: const TextStyle(
                                  color: AppColors.neutral4,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (network['secured'])
                          const Icon(Icons.lock_outline,
                              color: AppColors.neutral4, size: 18),
                        const SizedBox(width: 10),
                        Row(
                          children: List.generate(4, (i) {
                            return Container(
                              width: 4,
                              height: 6 + (i * 4.0),
                              margin: const EdgeInsets.only(left: 2),
                              decoration: BoxDecoration(
                                color: i < (network['signal'] as int)
                                    ? AppColors.primary
                                    : AppColors.neutral5.withValues(alpha: 0.45),
                                borderRadius: BorderRadius.circular(ConnectionMethodDesign.iconRadius),
                              ),
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordCard() {
    // Check if network is secured (for future use)
    // final secured = _isNetworkSecured(_selectedNetwork);
    return Container(
      key: const ValueKey('password-card'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Network Name (SSID)',
            style: TextStyle(fontSize: 13, color: Color(0xFF6D7E8B)),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _ssidController,
            readOnly: true,
            style: const TextStyle(color: Color(0xFF0B3A57), fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFFF1F5F9),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.18)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.18)),
              ),
              prefixIcon: const Icon(Icons.wifi, color: Color(0xFF53EAFD)),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Password',
            style: TextStyle(fontSize: 13, color: Color(0xFF6D7E8B)),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _passwordController,
            obscureText: !_showPassword,
            style: const TextStyle(color: Color(0xFF0B3A57)),
            decoration: InputDecoration(
              hintText: 'Enter WiFi password',
              filled: true,
              fillColor: AppColors.cardBackground,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.18)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.primary),
              ),
              suffixIcon: IconButton(
                icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility,
                    color: AppColors.neutral4),
                onPressed: () => setState(() => _showPassword = !_showPassword),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.12)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: Color(0xFF53EAFD)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Make sure your AGOS device is powered on and the WiFi indicator is blinking',
                    style: TextStyle(color: Color(0xFF6D7E8B), fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _isNetworkSecured(String? name) {
    if (name == null) return true;
    final entry = _networks.firstWhere((n) => n['name'] == name, orElse: () => {'secured': true});
    return entry['secured'] as bool;
  }
}
