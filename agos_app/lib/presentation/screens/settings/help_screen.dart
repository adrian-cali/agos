import 'package:flutter/material.dart';
import '../../widgets/bottom_nav_bar.dart';
import '../../widgets/fade_slide_in.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

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
                    _buildSectionHeader('CONTACT US'),
                    const SizedBox(height: 16),
                    _buildContactCard(
                      iconGradient: const [
                        Color(0xFF51A2FF),
                        Color(0xFF0092B8)
                      ],
                      iconData: Icons.email_outlined,
                      title: 'Email Support',
                      value: 'agos.support@plm.edu.ph',
                      note: 'Response within 24 hours',
                    ),
                    const SizedBox(height: 5),
                    _buildContactCard(
                      iconGradient: const [
                        Color(0xFF00D492),
                        Color(0xFF009689)
                      ],
                      iconData: Icons.phone_outlined,
                      title: 'Phone Support',
                      value: '+63 (2) 8643-2500',
                      note: 'Mon-Fri, 8:00 AM - 5:00 PM',
                    ),
                    const SizedBox(height: 24),
                    _buildSectionHeader('FREQUENTLY ASKED QUESTIONS'),
                    const SizedBox(height: 16),
                    _buildFaqCard(context),
                    const SizedBox(height: 24),
                    _buildSectionHeader('RESOURCES'),
                    const SizedBox(height: 16),
                    _buildResourceCard(
                      iconData: Icons.menu_book_outlined,
                      title: 'User Guide',
                      subtitle: 'Complete documentation and tutorials',
                    ),
                    const SizedBox(height: 5),
                    _buildResourceCard(
                      iconData: Icons.description_outlined,
                      title: 'Technical Specs',
                      subtitle: 'System specifications and requirements',
                    ),
                    const SizedBox(height: 5),
                    _buildResourceCard(
                      iconData: Icons.play_circle_outline,
                      title: 'Video Tutorials',
                      subtitle: 'Step-by-step video instructions',
                    ),
                    const SizedBox(height: 16),
                    _buildFeedbackCard(),
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
            'Help & Support',
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

  Widget _buildContactCard({
    required List<Color> iconGradient,
    required IconData iconData,
    required String title,
    required String value,
    required String note,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: Colors.white.withValues(alpha: 0.18), width: 1.18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF5DADE2).withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                colors: iconGradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Icon(iconData, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 16,
                    color: Color(0xFF1D293D),
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    color: Color(0xFF0092B8),
                  ),
                ),
                Text(
                  note,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    color: Color(0xFF62748E),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFaqCard(BuildContext context) {
    final faqs = [
      'How do I interpret the water quality readings?',
      'What should I do if I receive a critical alert?',
      'How often should I calibrate the sensors?',
      'Can I export my water usage data?',
      'Why is my tank showing low water level?',
      'How do I change notification settings?',
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: Colors.white.withValues(alpha: 0.18), width: 1.18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF5DADE2).withValues(alpha: 0.15),
            blurRadius: 8,
          ),
        ],
      ),
      child: Column(
        children: List.generate(faqs.length, (i) {
          final isLast = i == faqs.length - 1;
          return Column(
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(faqs[i])),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 16),
                    child: Row(
                      children: [
                        const Icon(Icons.help_outline,
                            size: 16, color: Color(0xFF314158)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            faqs[i],
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w500,
                              fontSize: 14,
                              color: Color(0xFF314158),
                              height: 1.43,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.chevron_right,
                            size: 16, color: Color(0xFF62748E)),
                      ],
                    ),
                  ),
                ),
              ),
              if (!isLast)
                Container(
                  height: 1.18,
                  margin: const EdgeInsets.symmetric(horizontal: 0),
                  color: const Color(0xFFA2F4FD).withValues(alpha: 0.3),
                ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildResourceCard({
    required IconData iconData,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: Colors.white.withValues(alpha: 0.18), width: 1.18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF5DADE2).withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(iconData, size: 20, color: const Color(0xFF314158)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 16,
                    color: Color(0xFF314158),
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    color: Color(0xFF62748E),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedbackCard() {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: Colors.white.withValues(alpha: 0.18), width: 1.18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF5DADE2).withValues(alpha: 0.15),
            blurRadius: 8,
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFF00D3F2), Color(0xFF155DFC)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: const Icon(Icons.feedback_outlined,
                color: Colors.white, size: 22),
          ),
          const SizedBox(height: 12),
          const Text(
            'Send Us Feedback',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 16,
              color: Color(0xFF1D293D),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Help us improve AGOS by sharing your thoughts and suggestions',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              color: Color(0xFF45556C),
              height: 1.43,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            height: 36,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(
                colors: [Color(0xFF00B8DB), Color(0xFF155DFC)],
              ),
            ),
            child: const Center(
              child: Text(
                'Submit Feedback',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
