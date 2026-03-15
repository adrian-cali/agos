import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:ui' as ui;
import '../../widgets/bottom_nav_bar.dart';
import '../../widgets/fade_slide_in.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F8FB),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 100),
          child: Column(
            children: [
              _buildHeader(context),
              const SizedBox(height: 8),
              FadeSlideIn(
                child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 25),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildAppIdentityCard(),
                    const SizedBox(height: 24),
                    _buildSectionHeader('OUR MISSION'),
                    const SizedBox(height: 16),
                    _buildMissionCard(),
                    const SizedBox(height: 24),
                    _buildSectionHeader('DEVELOPED AT'),
                    const SizedBox(height: 16),
                    _buildUniversityCard(),
                    const SizedBox(height: 24),
                    _buildSectionHeader('DEVELOPMENT TEAM'),
                    const SizedBox(height: 16),
                    _buildTeamCard(
                      imagePath: 'assets/images/dev_team/adrian.png',
                      name: 'Adrian S. Calingasin',
                      linkedin: 'LinkedIn: Adrian Calingasin',
                      url: 'https://www.linkedin.com/in/adrian-calingasin-278350222/',
                    ),
                    const SizedBox(height: 5),
                    _buildTeamCard(
                      imagePath: 'assets/images/dev_team/seb.png',
                      name: 'Sebastian M. Dantes',
                      linkedin: 'LinkedIn: Sebastian Dantes',
                      url: 'https://www.linkedin.com/in/sebastian-dantes-74789a399/',
                    ),
                    const SizedBox(height: 5),
                    _buildTeamCard(
                      imagePath: 'assets/images/dev_team/ayish.png',
                      name: 'Irish Anne G. Jayme',
                      linkedin: 'LinkedIn: Irish Anne Jayme',
                      url: 'https://www.linkedin.com/in/irish-anne-jayme-8554182a0/',
                    ),
                    const SizedBox(height: 5),
                    _buildTeamCard(
                      imagePath: 'assets/images/dev_team/jai.png',
                      name: 'Jaichand M. Nagpal',
                      linkedin: 'LinkedIn: Jaichand Nagpal',
                      url: 'https://www.linkedin.com/in/jaichand-nagpal',
                    ),
                    const SizedBox(height: 5),
                    _buildTeamCard(
                      imagePath: 'assets/images/dev_team/racel.png',
                      name: 'Racelito C. Pascual',
                      linkedin: 'LinkedIn: Racelito Pascual',
                      url: 'https://www.linkedin.com/in/racelito-pascual-1782652a0/',
                    ),
                    const SizedBox(height: 24),
                    _buildFooter(),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const BottomNavBar(currentIndex: 2),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 16),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const SizedBox(
              width: 40,
              height: 40,
              child: Icon(Icons.arrow_back_ios,
                  size: 20, color: Color(0xFF141A1E)),
            ),
          ),
          const SizedBox(width: 4),
          const Text(
            'About AGOS',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF141A1E),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: ShaderMask(
        shaderCallback: (bounds) => const LinearGradient(
          colors: [Color(0xFF1447E6), Color(0xFF0092B8)],
        ).createShader(bounds),
        child: Text(
          title,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildAppIdentityCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: Colors.white.withOpacity(0.18), width: 1.18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF5DADE2).withOpacity(0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // AGOS App Icon
          Container(
            width: 104,
            height: 104,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF00D3F2),
                  Color(0xFF2B7FFF),
                  Color(0xFF9810FA),
                ],
                stops: [0.0, 0.5, 1.0],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF22D3EE).withOpacity(0.37),
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
          const SizedBox(height: 12),
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [
                Color(0xFF1447E6),
                Color(0xFF0092B8),
                Color(0xFF1447E6),
              ],
            ).createShader(bounds),
            child: const Text(
              'AGOS',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Version 1.0.0 • February 2026',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              color: Color(0xFF62748E),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMissionCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: Colors.white.withOpacity(0.18), width: 1.18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF5DADE2).withOpacity(0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.eco_outlined, size: 22, color: Color(0xFF314158)),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'AGOS aims to revolutionize water conservation through intelligent greywater recycling. Our mission is to provide affordable, efficient, and sustainable water management solutions that contribute to environmental preservation and resource optimization.',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 16,
                color: Color(0xFF314158),
                height: 1.625,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUniversityCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: Colors.white.withOpacity(0.18), width: 1.18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF5DADE2).withOpacity(0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Image.asset(
            'assets/images/plm_logo.png',
            height: 56,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 12),
          const Text(
            'Pamantasan ng Lungsod ng Maynila',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 16,
              color: Color(0xFF1D293D),
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'University of the City of Manila',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              color: Color(0xFF45556C),
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'College of Engineering',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              color: Color(0xFF62748E),
            ),
          ),
          const Text(
            'Computer Engineering Department',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              color: Color(0xFF62748E),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTeamCard({
    required String imagePath,
    required String name,
    required String linkedin,
    String? url,
  }) {
    final card = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: Colors.white.withOpacity(0.18), width: 1.18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF5DADE2).withOpacity(0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF00D3F2), width: 2),
            ),
            child: ClipOval(
              child: Image.asset(
                imagePath,
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    color: Color(0xFF1D293D),
                  ),
                ),
                Text(
                  linkedin,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    color: Color(0xFF62748E),
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.open_in_new,
            size: 16,
            color: url != null ? const Color(0xFF0078B4) : const Color(0xFF62748E),
          ),
        ],
      ),
    );

    if (url == null) return card;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        final uri = Uri.parse(url);
        final canLaunch = await canLaunchUrl(uri);
        debugPrint('canLaunchUrl($url) = $canLaunch');
        if (canLaunch) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          await launchUrl(uri, mode: LaunchMode.platformDefault);
        }
      },
      child: card,
    );
  }

  Widget _buildFooter() {
    return const Column(
      children: [
        Text(
          '© 2025 AGOS Project. All rights reserved.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 12,
            color: Color(0xFF62748E),
          ),
        ),
        SizedBox(height: 4),
        Text(
          'Developed as part of the Computer Engineering curriculum at PLM',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 12,
            color: Color(0xFF62748E),
          ),
        ),
      ],
    );
  }
}
