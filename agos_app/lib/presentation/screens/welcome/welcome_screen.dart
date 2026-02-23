import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:ui' as ui;
import 'package:google_fonts/google_fonts.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

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
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 25),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // AGOS App Icon with gradient background and glow
                  Container(
                    width: 104,
                    height: 104,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF00D3F2), // cyan
                          Color(0xFF2B7FFF), // blue
                          Color(0xFF9810FA), // purple
                        ],
                        stops: [0.0, 0.5, 1.0],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF22D3EE).withValues(alpha: 0.37),
                          blurRadius: 26.5,
                          spreadRadius: 0,
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(22),
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

                  // "Welcome to AGOS" gradient text
                  ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [
                        Color(0xFF1447E6), // blue
                        Color(0xFF0092B8), // teal
                        Color(0xFF1447E6), // blue
                      ],
                      stops: [0.0, 0.5, 1.0],
                    ).createShader(bounds),
                    child: Text(
                      'Welcome to AGOS',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        height: 32 / 24,
                        color: Colors.white, // masked by shader
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Subtitle
                  const Text(
                    "Let's set up your Automated Greywater Operational System and connect it to your sensors.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                      height: 24 / 16,
                      color: Color(0xFF45556C),
                    ),
                  ),
                  const SizedBox(height: 25),

                  // "What you'll need" card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24.8, vertical: 16.8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.18),
                        width: 0.8,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF5DADE2).withValues(alpha: 0.15),
                          blurRadius: 8,
                          spreadRadius: 0,
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header
                        const Text(
                          "What you'll need:",
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 16,
                            fontWeight: FontWeight.w400,
                            height: 24 / 16,
                            color: Color(0xFF1D293D),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Item 1: AGOS Hardware Unit
                        _buildRequirementItem(
                          title: 'AGOS Hardware Unit',
                          subtitle: 'With power supply connected',
                        ),
                        const SizedBox(height: 12),

                        // Item 2: WiFi Network or Bluetooth
                        _buildRequirementItem(
                          title: 'WiFi Network or Bluetooth',
                          subtitle: 'For device communication',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 25),

                  // Get Started button with gradient
                  GestureDetector(
                    onTap: () {
                      Navigator.pushReplacementNamed(
                          context, '/connection-method');
                    },
                    child: Container(
                      width: double.infinity,
                      height: 36,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFF00B8DB),
                            Color(0xFF155DFC),
                          ],
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Get Started',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              height: 20 / 14,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 8),
                          Icon(
                            Icons.arrow_forward,
                            color: Colors.white,
                            size: 16,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRequirementItem({
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Check circle icon
        Container(
          width: 20,
          height: 20,
          margin: const EdgeInsets.only(top: 2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: const Color(0xFF00B8DB),
              width: 2,
            ),
          ),
          child: const Center(
            child: Icon(
              Icons.check,
              size: 12,
              color: Color(0xFF00B8DB),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Text column
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                fontWeight: FontWeight.w400,
                height: 20 / 14,
                color: Color(0xFF314158),
              ),
            ),
            Text(
              subtitle,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                fontWeight: FontWeight.w400,
                height: 16 / 12,
                color: Color(0xFF62748E),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

