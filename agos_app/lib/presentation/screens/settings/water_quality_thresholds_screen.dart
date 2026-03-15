import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../widgets/bottom_nav_bar.dart';
import '../../widgets/fade_slide_in.dart';
import '../../../data/services/firestore_service.dart';
import '../../../data/services/websocket_service.dart' show webSocketServiceProvider;

class WaterQualityThresholdsScreen extends ConsumerStatefulWidget {
  const WaterQualityThresholdsScreen({super.key});

  @override
  ConsumerState<WaterQualityThresholdsScreen> createState() =>
      _WaterQualityThresholdsScreenState();
}

class _WaterQualityThresholdsScreenState
    extends ConsumerState<WaterQualityThresholdsScreen> {
  bool _initialised = false;
  bool _saving = false;

  // Turbidity (NTU)
  double _turbidityMin = 10;
  double _turbidityWarning = 50;

  // pH Level
  double _phMin = 6.0;
  double _phMax = 9.5;

  // TDS (ppm)
  double _tdsWarning = 1000;

  // Tank level (%)
  double _levelMin = 20;
  double _levelHigh = 90;

  void _applyThresholds(UserThresholds t) {
    _turbidityMin = t.turbidityMin;
    _turbidityWarning = t.turbidityMax;
    _phMin = t.phMin;
    _phMax = t.phMax;
    _tdsWarning = t.tdsMax;
    _levelMin = t.levelMin;
    _levelHigh = t.levelHigh;
  }

  void _resetDefaults() {
    setState(() {
      _applyThresholds(const UserThresholds());
    });
  }

  Future<void> _save() async {
    final user = ref.read(currentUserProvider);
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Not signed in')));
      return;
    }
    setState(() => _saving = true);
    try {
      final thresholds = UserThresholds(
              turbidityMin: _turbidityMin,
              turbidityMax: _turbidityWarning,
              phMin: _phMin,
              phMax: _phMax,
              tdsMax: _tdsWarning,
              levelMin: _levelMin,
              levelHigh: _levelHigh,
            );
      await ref.read(firestoreServiceProvider).saveThresholds(
            user.uid,
            thresholds,
          );
      ref.read(webSocketServiceProvider).sendThresholds(thresholds);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Thresholds saved.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Load saved thresholds once when provider first emits
    final savedAsync = ref.watch(userThresholdsProvider);
    savedAsync.whenData((t) {
      if (!_initialised) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() { _applyThresholds(t); _initialised = true; });
        });
      }
    });

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
                          'Set the optimal min/max range for each parameter. Alerts trigger when readings fall outside the set range.',
                    ),
                    const SizedBox(height: 19),
                    _buildSectionHeader('TURBIDITY (NTU)'),
                    const SizedBox(height: 12),
                    _buildParameterCard(
                      iconGradient: const [Color(0xFF00D3F2), Color(0xFF155DFC)],
                      iconData: Icons.opacity,
                      title: 'Water Clarity Measurement',
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
                                '${_turbidityMin.round()} – ${_turbidityWarning.round()} NTU',
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
                        _buildLabel('Minimum NTU'),
                        _buildSlider(_turbidityMin, 0, 100,
                            (v) => setState(() => _turbidityMin = v)),
                        const SizedBox(height: 8),
                        _buildLabel('Maximum NTU'),
                        _buildSlider(_turbidityWarning, 0, 200,
                            (v) => setState(() => _turbidityWarning = v)),
                        const SizedBox(height: 12),
                        _buildHintBox(
                          'Optimal Range: 10–50 NTU',
                          'Alerts trigger when readings fall outside your min–max range.',
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
                        _buildHintBox(
                          'Optimal Range: 6.5-8.5',
                          'Alerts trigger when pH falls outside your min–max range.',
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
                          label: 'Maximum Level',
                          value: _tdsWarning,
                          badge: '${_tdsWarning.round()} ppm',
                          badgeBg: const Color(0xFFFEF3C6),
                          badgeFg: const Color(0xFFBB4D00),
                          min: 0,
                          max: 2000,
                          onChanged: (v) =>
                              setState(() => _tdsWarning = v),
                        ),
                        const SizedBox(height: 12),
                        _buildHintBox(
                          'Acceptable Range: < 1000 ppm',
                          'Alerts trigger when TDS exceeds your maximum.',
                        ),
                      ],
                    ),
                    const SizedBox(height: 19),
                    _buildSectionHeader('TANK LEVEL (%)'),
                    const SizedBox(height: 12),
                    _buildParameterCard(
                      iconGradient: const [Color(0xFF00D3F2), Color(0xFF0AA1DD)],
                      iconData: Icons.water_drop_outlined,
                      title: 'Minimum Tank Level',
                      children: [
                        _buildSliderRow(
                          label: 'Alert Below',
                          value: _levelMin,
                          badge: '${_levelMin.round()}%',
                          badgeBg: const Color(0xFFFEF3C6),
                          badgeFg: const Color(0xFFBB4D00),
                          min: 0,
                          max: 100,
                          onChanged: (v) => setState(() => _levelMin = v.clamp(0, _levelHigh - 5)),
                        ),
                        const SizedBox(height: 12),
                        _buildSliderRow(
                          label: 'Optimal Above',
                          value: _levelHigh,
                          badge: '${_levelHigh.round()}%',
                          badgeBg: const Color(0xFFD1FAE5),
                          badgeFg: const Color(0xFF065F46),
                          min: 0,
                          max: 100,
                          onChanged: (v) => setState(() => _levelHigh = v.clamp(_levelMin + 5, 100)),
                        ),
                        const SizedBox(height: 12),
                        _buildHintBox(
                          'Optimal: Keep tank above ${_levelHigh.round()}%',
                          'Alert when level drops below ${_levelMin.round()}%',
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
                            onTap: _saving ? null : _save,
                            child: Container(
                              height: 36,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                gradient: LinearGradient(
                                  colors: _saving
                                      ? [Colors.grey.shade400, Colors.grey.shade400]
                                      : const [Color(0xFF00B8DB), Color(0xFF155DFC)],
                                ),
                              ),
                              child: Center(
                                child: _saving
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white))
                                    : const Text(
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
        color: Colors.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: Colors.white.withOpacity(0.18), width: 1.18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF5DADE2).withOpacity(0.15),
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
        color: Colors.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: Colors.white.withOpacity(0.18), width: 1.18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF5DADE2).withOpacity(0.15),
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
        overlayColor: const Color(0xFF0F172A).withOpacity(0.1),
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
