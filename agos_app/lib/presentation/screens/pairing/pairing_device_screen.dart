import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

/// Pairing Device Screen (Figma 335:963)
/// Shows authentication progress with loading indicator
class PairingDeviceScreen extends StatefulWidget {
  const PairingDeviceScreen({super.key});

  @override
  State<PairingDeviceScreen> createState() => _PairingDeviceScreenState();
}

class _PairingDeviceScreenState extends State<PairingDeviceScreen>
    with TickerProviderStateMixin {
  late AnimationController _rotationController;
  late AnimationController _progressController;
  late Animation<double> _progressAnimation;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _progressController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    );

    _progressAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(_progressController);

    _progressAnimation.addListener(() {
      setState(() {});
    });

    _progressController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        Navigator.pushReplacementNamed(context, '/device-information');
      }
    });

    _progressController.forward();
  }

  @override
  void dispose() {
    _rotationController.dispose();
    _progressController.dispose();
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
                        // AGOS Logo
                        Container(
                          width: 104,
                          height: 104,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(24),
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFF00D3F2), Color(0xFF2B7FFF), Color(0xFF9810FA)],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF22D3EE).withValues(alpha: 0.37),
                                blurRadius: 26.47,
                                offset: const Offset(0, 0),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                              // larger, soft white glow
                              ImageFiltered(
                                imageFilter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                                child: Opacity(
                                  opacity: 0.85,
                                  child: SvgPicture.asset(
                                    'assets/svg/agos_square_logo.svg',
                                    fit: BoxFit.contain,
                                    colorFilter: const ColorFilter.mode(
                                      Colors.white,
                                      BlendMode.srcIn,
                                    ),
                                  ),
                                ),
                              ),

                              // smaller, subtle halo for depth
                              ImageFiltered(
                                imageFilter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                                child: Opacity(
                                  opacity: 0.35,
                                  child: SvgPicture.asset(
                                    'assets/svg/agos_square_logo.svg',
                                    fit: BoxFit.contain,
                                    colorFilter: const ColorFilter.mode(
                                      Colors.white,
                                      BlendMode.srcIn,
                                    ),
                                  ),
                                ),
                              ),

                              // crisp foreground logo
                              SvgPicture.asset(
                                'assets/svg/agos_square_logo.svg',
                                fit: BoxFit.contain,
                                colorFilter: const ColorFilter.mode(
                                  Colors.white,
                                  BlendMode.srcIn,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 8),
                      
                      // Title
                      ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [Color(0xFF1447E6), Color(0xFF0092B8), Color(0xFF1447E6)],
                        ).createShader(bounds),
                        child: Text(
                          'Pairing Device',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 8),
                      
                      // Subtitle
                      Text(
                        'Connect your smartphone to the AGOS control unit',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                          color: const Color(0xFF45556C),
                        ),
                      ),
                      
                      const SizedBox(height: 27),
                      
                      // Status Card
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0x2EFFFFFF), // 18% white
                            width:  1.18,
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
                            // Status row
                            Row(
                              children: [
                                // Loading animation
                                RotationTransition(
                                  turns: _rotationController,
                                  child: Container(
                                    width: 26,
                                    height: 26,
                                    padding: const EdgeInsets.all(4),
                                    child: const CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Color(0xFF00B8DB),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8.5),
                                Text(
                                  'Authenticating Device',
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w400,
                                    color: const Color(0xFF314158),
                                  ),
                                ),
                              ],
                            ),
                            
                            const SizedBox(height: 15),
                            
                            // Progress bar
                            ClipRRect(
                              borderRadius: BorderRadius.circular(40),
                              child: LinearProgressIndicator(
                                value: _progressAnimation.value,
                                minHeight: 8,
                                backgroundColor: const Color(0xFFE2E8F0),
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  Color(0xFF00B8DB),
                                ),
                              ),
                            ),
                          ],
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
            ),
          ],
        ),
      ),
    );
  }
}

