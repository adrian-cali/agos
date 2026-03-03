import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../data/services/firestore_service.dart';

/// Setup Complete Screen (Figma 335:1059)
/// Final screen showing setup completion with checklist
class SetupCompleteScreen extends ConsumerStatefulWidget {
  const SetupCompleteScreen({super.key});

  @override
  ConsumerState<SetupCompleteScreen> createState() =>
      _SetupCompleteScreenState();
}

class _SetupCompleteScreenState extends ConsumerState<SetupCompleteScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _saving = false;

  Future<void> _startMonitoring() async {
    setState(() => _saving = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        Navigator.pushReplacementNamed(context, '/login');
        return;
      }

      final setup = ref.read(setupStateProvider);

      // Generate a device ID if none was set during pairing
      final deviceId = setup.deviceId.isNotEmpty
          ? setup.deviceId
          : 'agos-${user.uid.substring(0, 8)}';

      await FirestoreService().saveDeviceSetup(
        uid: user.uid,
        deviceId: deviceId,
        deviceName: setup.deviceName,
        location: setup.location,
        connectionType: setup.connectionType,
        ownerName: setup.ownerName,
        ownerPhone: setup.ownerPhone,
      );

      // Reset setup state
      ref.read(setupStateProvider.notifier).reset();
      // Invalidate cached providers so home screen loads fresh data
      ref.invalidate(hasLinkedDeviceProvider);
      ref.invalidate(linkedDeviceIdProvider);

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/home');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save device: $e'),
          backgroundColor: const Color(0xFFE74C3C),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scaleAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
              Color(0xFFF8FAFC),
              Color(0xFFEFF6FF),
              Color(0xFFECFEFF),
            ],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // Main content (starts from top, behind progress bar)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 25),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                  
                  // Success icon
                  ScaleTransition(
                    scale: _scaleAnimation,
                    child: Container(
                      width: 128,
                      height: 128,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF00D492), Color(0xFF009689)],
                        ),
                      ),
                      child: const Icon(
                        Icons.check_circle,
                        color: Colors.white,
                        size: 80,
                      ),
                    ),
                  ),
                      const SizedBox(height: 8),

                      // Title
                      ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [Color(0xFF009966), Color(0xFF009689)],
                        ).createShader(bounds),
                        child: Text(
                          'Setup Complete!',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            fontSize: 30,
                            fontWeight: FontWeight.w400,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Subtitle
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: Text(
                          'Your AGOS system is now ready to monitor water quality',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w400,
                            color: const Color(0xFF45556C),
                          ),
                        ),
                      ),
                      const SizedBox(height: 27),

                      // Checklist Card
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0x2EFFFFFF),
                            width: 1.18,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF5DADE2).withValues(alpha: 0.15),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(17.18),
                        child: Column(
                          children: [
                            _buildChecklistItem(
                              'Device Connected',
                              'AGOS-A1B2',
                            ),
                            const SizedBox(height: 15),
                            _buildChecklistItem(
                              'Sensors Calibrated',
                              null,
                            ),
                            const SizedBox(height: 15),
                            _buildChecklistItem(
                              'Baseline Established',
                              'All parameters nominal',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 27),

                      // Start Monitoring Button
                      SizedBox(
                        width: double.infinity,
                        height: 40,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF00BC7D), Color(0xFF009689)],
                            ),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 15,
                                offset: const Offset(0, 10),
                              ),
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 6,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: _saving ? null : _startMonitoring,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: _saving
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Start Monitoring',
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(Icons.arrow_forward, size: 18, color: Colors.white),
                              ],
                            ),
                          ),
                        ),
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
                        value: 1.0,
                        minHeight: 8,
                        backgroundColor: Color.fromRGBO(15, 23, 42, 0.20),
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF009966)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Complete',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: const Color(0xFF009966),
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

  Widget _buildChecklistItem(String title, String? subtitle) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF00D492), Color(0xFF009689)],
            ),
          ),
          child: const Icon(
            Icons.check,
            color: Colors.white,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: const Color(0xFF314158),
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 12,
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

