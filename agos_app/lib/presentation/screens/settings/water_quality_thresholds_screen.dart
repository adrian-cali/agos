import 'package:flutter/material.dart';
import '../../widgets/bottom_nav_bar.dart';
import '../../widgets/fade_slide_in.dart';

class WaterQualityThresholdsScreen extends StatefulWidget {
  const WaterQualityThresholdsScreen({super.key});

  @override
  State<WaterQualityThresholdsScreen> createState() =>
      _WaterQualityThresholdsScreenState();
}

class _WaterQualityThresholdsScreenState
    extends State<WaterQualityThresholdsScreen> {
  // Turbidity (NTU)
  double _turbidityWarning = 20;
  double _turbidityCritical = 30;

  // pH Level
  double _phMin = 6.5;
  double _phMax = 8.5;
  double _phCriticalMin = 6.0;
  double _phCriticalMax = 9.0;

  // TDS (ppm)
  double _tdsWarning = 500;
  double _tdsCritical = 700;

  void _resetDefaults() {
    setState(() {
      _turbidityWarning = 20;
      _turbidityCritical = 30;
      _phMin = 6.5;
      _phMax = 8.5;
      _phCriticalMin = 6.0;
      _phCriticalMax = 9.0;
      _tdsWarning = 500;
      _tdsCritical = 700;
    });
  }

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
                    // Info card
                    _buildInfoCard(
                      icon: Icons.lightbulb_outline,
                      title: 'Threshold Guidelines',
                      body:
                          'Warning thresholds trigger caution alerts. Critical thresholds trigger immediate action alerts.',
                    ),
                    const SizedBox(height: 19),
                    _buildSectionHeader('TURBIDITY (NTU)'),
                    const SizedBox(height: 12),
                    _buildParameterCard(
                      iconGradient: const [Color(0xFF00D3F2), Color(0xFF155DFC)],
                      iconData: Icons.opacity,
                      title: 'Water Clarity Measurement',
                      children: [
                        _buildSliderRow(
                          label: 'Warning Level',
                          value: _turbidityWarning,
                          badge: '${_turbidityWarning.round()} NTU',
                          badgeBg: const Color(0xFFFEF3C6),
                          badgeFg: const Color(0xFFBB4D00),
                          min: 0,
                          max: 100,
                          onChanged: (v) =>
                              setState(() => _turbidityWarning = v),
                        ),
                        const SizedBox(height: 12),
                        _buildSliderRow(
                          label: 'Critical Level',
                          value: _turbidityCritical,
                          badge: '${_turbidityCritical.round()} NTU',
                          badgeBg: const Color(0xFFFFE2E2),
                          badgeFg: const Color(0xFFC10007),
                          min: 0,
                          max: 100,
                          onChanged: (v) =>
                              setState(() => _turbidityCritical = v),
                        ),
                        const SizedBox(height: 12),
                        _buildHintBox(
                          'Optimal Range: 0-20 NTU',
                          'Recommended: Warning at 20 NTU, Critical at 30 NTU',
                        ),
                      ],
                    ),
                    const SizedBox(height: 19),
                    _buildSectionHeader('pH LEVEL'),
                    const SizedBox(height: 12),
                    _buildParameterCard(
                      iconGradient: const [Color(0xFFC27AFF), Color(0xFFE60076)],
                      iconData: Icons.science_outlined,
                      title: 'Acidity/Alkalinity Level',
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Optimal Range',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 14,
                                color: Color(0xFF45556C),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFD0FAE5),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '${_phMin.toStringAsFixed(1)} - ${_phMax.toStringAsFixed(1)}',
                                style: const TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 14,
                                  color: Color(0xFF007A55),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _buildLabel('Minimum pH'),
                        _buildSlider(
                            _phMin, 0, 14, (v) => setState(() => _phMin = v)),
                        const SizedBox(height: 8),
                        _buildLabel('Maximum pH'),
                        _buildSlider(
                            _phMax, 0, 14, (v) => setState(() => _phMax = v)),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Critical Limits',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 14,
                                color: Color(0xFF45556C),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFE2E2),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '< ${_phCriticalMin.toStringAsFixed(1)} or > ${_phCriticalMax.toStringAsFixed(1)}',
                                style: const TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 14,
                                  color: Color(0xFFC10007),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _buildLabel('Critical Minimum'),
                        _buildSlider(_phCriticalMin, 0, 14,
                            (v) => setState(() => _phCriticalMin = v)),
                        const SizedBox(height: 8),
                        _buildLabel('Critical Maximum'),
                        _buildSlider(_phCriticalMax, 0, 14,
                            (v) => setState(() => _phCriticalMax = v)),
                        const SizedBox(height: 12),
                        _buildHintBox(
                          'Optimal Range: 6.5-8.5',
                          'Recommended: 6.5-8.5 (neutral to slightly alkaline)',
                        ),
                      ],
                    ),
                    const SizedBox(height: 19),
                    _buildSectionHeader('TOTAL DISSOLVED SOLIDS (PPM)'),
                    const SizedBox(height: 12),
                    _buildParameterCard(
                      iconGradient: const [Color(0xFF7C86FF), Color(0xFF155DFC)],
                      iconData: Icons.water_outlined,
                      title: 'Dissolved Mineral Content',
                      children: [
                        _buildSliderRow(
                          label: 'Warning Level',
                          value: _tdsWarning,
                          badge: '${_tdsWarning.round()} ppm',
                          badgeBg: const Color(0xFFFEF3C6),
                          badgeFg: const Color(0xFFBB4D00),
                          min: 0,
                          max: 1000,
                          onChanged: (v) =>
                              setState(() => _tdsWarning = v),
                        ),
                        const SizedBox(height: 12),
                        _buildSliderRow(
                          label: 'Critical Level',
                          value: _tdsCritical,
                          badge: '${_tdsCritical.round()} ppm',
                          badgeBg: const Color(0xFFFFE2E2),
                          badgeFg: const Color(0xFFC10007),
                          min: 0,
                          max: 1000,
                          onChanged: (v) =>
                              setState(() => _tdsCritical = v),
                        ),
                        const SizedBox(height: 12),
                        _buildHintBox(
                          'Optimal Range: 0-500 ppm',
                          'Recommended: Warning at 500 ppm, Critical at 700 ppm',
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    // Action buttons
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: _resetDefaults,
                            child: Container(
                              height: 36,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                    color: const Color(0xFFA2F4FD),
                                    width: 1.18),
                              ),
                              child: const Center(
                                child: Text(
                                  'Reset Defaults',
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontWeight: FontWeight.w500,
                                    fontSize: 14,
                                    color: Color(0xFF007595),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 19),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content:
                                        Text('Thresholds saved.')),
                              );
                            },
                            child: Container(
                              height: 36,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF00B8DB),
                                    Color(0xFF155DFC)
                                  ],
                                ),
                              ),
                              child: const Center(
                                child: Text(
                                  'Save Changes',
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontWeight: FontWeight.w500,
                                    fontSize: 14,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
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
          const Expanded(
            child: Text(
              'Water Quality Thresholds',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF141A1E),
              ),
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

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String body,
  }) {
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: const Color(0xFF1C398E)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    color: Color(0xFF1C398E),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    color: Color(0xFF1447E6),
                    height: 1.33,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParameterCard({
    required List<Color> iconGradient,
    required IconData iconData,
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(20),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(colors: iconGradient,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight),
                ),
                child: Icon(iconData, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 16,
                    color: Color(0xFF314158),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          ...children,
        ],
      ),
    );
  }

  Widget _buildSliderRow({
    required String label,
    required double value,
    required String badge,
    required Color badgeBg,
    required Color badgeFg,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                color: Color(0xFF45556C),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: badgeBg,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                badge,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  color: badgeFg,
                ),
              ),
            ),
          ],
        ),
        _buildSlider(value, min, max, onChanged),
      ],
    );
  }

  Widget _buildSlider(
      double value, double min, double max, ValueChanged<double> onChanged) {
    return SliderTheme(
      data: SliderThemeData(
        thumbColor: Colors.white,
        overlayColor: const Color(0xFF0F172A).withValues(alpha: 0.1),
        activeTrackColor: const Color(0xFF0F172A),
        inactiveTrackColor: const Color(0xFFF8FAFC),
        thumbShape: const RoundSliderThumbShape(
            enabledThumbRadius: 8, elevation: 2),
        trackHeight: 8,
      ),
      child: Slider(
        value: value,
        min: min,
        max: max,
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: 'Inter',
        fontSize: 12,
        color: Color(0xFF62748E),
      ),
    );
  }

  Widget _buildHintBox(String line1, String line2) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            line1,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              color: Color(0xFF62748E),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            line2,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              color: Color(0xFF62748E),
              height: 1.33,
            ),
          ),
        ],
      ),
    );
  }
}
