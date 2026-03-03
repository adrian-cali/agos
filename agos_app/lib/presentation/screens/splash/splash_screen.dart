import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../data/services/firestore_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late AnimationController _dotsController;
  late AnimationController _waveController;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeIn),
    );
    _fadeController.forward();

    // Dots bouncing animation
    _dotsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();

    // Wave moving animation
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();

    // Auto-navigate after 2.5 seconds based on Firebase auth state
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (!mounted) return;
      _navigateBasedOnAuth();
    });
  }

  void _navigateBasedOnAuth() async {
    User? user;
    if (kIsWeb) {
      // On web, currentUser can be null while Firebase restores the session.
      // Wait up to 5s for the first authStateChanges event before giving up.
      try {
        user = await FirebaseAuth.instance
            .authStateChanges()
            .first
            .timeout(const Duration(seconds: 5));
      } catch (_) {
        user = FirebaseAuth.instance.currentUser;
      }
    } else {
      user = FirebaseAuth.instance.currentUser;
    }

    if (user == null) {
      if (mounted) Navigator.pushReplacementNamed(context, '/login');
      return;
    }
    // Check if the user has already set up a device
    final hasDevice = await FirestoreService().hasLinkedDevice(user.uid);
    if (!mounted) return;
    Navigator.pushReplacementNamed(
      context,
      hasDevice ? '/home' : '/welcome',
    );
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _dotsController.dispose();
    _waveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _navigateBasedOnAuth(),
      child: Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Color(0xFF00B8DB), // Cyan
                Color(0xFF155DFC), // Blue
              ],
            ),
          ),
          child: Stack(
            children: [
              // Animated water waves at bottom
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                height: 300,
                child: AnimatedBuilder(
                  animation: _waveController,
                  builder: (context, child) {
                    return CustomPaint(
                      size: Size(MediaQuery.of(context).size.width, 300),
                      painter: WaterWavePainter(
                        animationValue: _waveController.value,
                      ),
                    );
                  },
                ),
              ),

              // Center content: Logo + loading dots
              Center(
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // AGOS Logo
                      SizedBox(
                        width: double.infinity,
                        height: 100,
                        child: SvgPicture.asset(
                          'assets/svg/agos_logo.svg',
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(height: 15),
                      // Loading dots with jumping animation
                      SizedBox(
                        width: 80,
                        height: 45,
                        child: AnimatedBuilder(
                          animation: _dotsController,
                          builder: (context, child) {
                            return Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: List.generate(4, (index) {
                                // Stagger each dot's bounce
                                final delay = index * 0.15;
                                final t = ((_dotsController.value - delay) % 1.0).clamp(0.0, 1.0);
                                // Bounce: jump up then fall back down
                                double bounce = 0;
                                if (t < 0.4) {
                                  // Rising phase
                                  bounce = math.sin(t / 0.4 * math.pi) * 10;
                                }
                                return Transform.translate(
                                  offset: Offset(0, -bounce),
                                  child: Container(
                                    width: 13,
                                    height: 13,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.white.withValues(alpha: 0.4),
                                          blurRadius: 8,
                                          spreadRadius: 1,
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Bottom home indicator bar
              // Positioned(
              //   bottom: 8,
              //   left: 0,
              //   right: 0,
              //   child: Center(
              //     child: Container(
              //       width: 134,
              //       height: 5,
              //       decoration: BoxDecoration(
              //         color: Colors.white,
              //         borderRadius: BorderRadius.circular(2.5),
              //       ),
              //     ),
              //   ),
              // ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Custom painter that draws animated water-like waves
class WaterWavePainter extends CustomPainter {
  final double animationValue;

  WaterWavePainter({required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    // Use full 2π cycle so animation loops seamlessly (sin(0) == sin(2π))
    final double phase = animationValue * 2 * math.pi;

    // Wave 1 - back layer, gentle sway
    _drawWave(
      canvas, size,
      baseY: size.height * 0.20,
      amplitudes: [28.0, 12.0],
      frequencies: [1.0, 2.0],
      phaseOffsets: [phase, phase + 1.2],
      color: Colors.white.withValues(alpha: 0.14),
    );

    // Wave 2 - front layer, most visible
    _drawWave(
      canvas, size,
      baseY: size.height * 0.45,
      amplitudes: [18.0, 7.0],
      frequencies: [1.0, 2.0],
      phaseOffsets: [phase + 2.0, phase + 3.5],
      color: Colors.white.withValues(alpha: 0.30),
    );
  }

  void _drawWave(
    Canvas canvas,
    Size size, {
    required double baseY,
    required List<double> amplitudes,
    required List<double> frequencies,
    required List<double> phaseOffsets,
    required Color color,
  }) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(0, size.height);

    for (double x = 0; x <= size.width; x += 1) {
      final ratio = x / size.width;
      double y = baseY;
      for (int i = 0; i < amplitudes.length; i++) {
        y += math.sin(ratio * frequencies[i] * 2 * math.pi + phaseOffsets[i]) *
            amplitudes[i];
      }
      path.lineTo(x, y);
    }

    path.lineTo(size.width, size.height);
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant WaterWavePainter oldDelegate) {
    return oldDelegate.animationValue != animationValue;
  }
}
