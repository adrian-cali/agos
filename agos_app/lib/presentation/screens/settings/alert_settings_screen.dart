import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/services/firestore_service.dart';
import '../../widgets/fade_slide_in.dart';

class AlertSettingsScreen extends ConsumerStatefulWidget {
  const AlertSettingsScreen({super.key});

  @override
  ConsumerState<AlertSettingsScreen> createState() =>
      _AlertSettingsScreenState();
}

class _AlertSettingsScreenState extends ConsumerState<AlertSettingsScreen> {
  double _turbidityMax = 5.0;
  RangeValues _phRange = const RangeValues(6.5, 8.3);
  double _tdsMax = 500.0;
  double _waterLevelLow = 20.0;
  double _waterLevelHigh = 90.0;

  bool _initialised = false;
  bool _saving = false;

  void _applyThresholds(UserThresholds t) {
    setState(() {
      _turbidityMax = t.turbidityMax;
      _phRange = RangeValues(t.phMin, t.phMax);
      _tdsMax = t.tdsMax;
      _waterLevelLow = t.levelMin;
      _waterLevelHigh = t.levelHigh;
    });
  }

  Future<void> _save() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(firestoreServiceProvider).saveThresholds(
            user.uid,
            UserThresholds(
              turbidityMax: _turbidityMax,
              phMin: _phRange.start,
              phMax: _phRange.end,
              tdsMax: _tdsMax,
              levelMin: _waterLevelLow,
              levelHigh: _waterLevelHigh,
            ),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Alert thresholds saved!'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Load from Firestore once
    final thresholdsAsync = ref.watch(userThresholdsProvider);
    thresholdsAsync.whenData((t) {
      if (!_initialised) {
        _initialised = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => _applyThresholds(t));
      }
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.darkBlue, Color(0xFF0E5A8A)],
                  ),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(24),
                    bottomRight: Radius.circular(24),
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_ios,
                          color: Colors.white),
                    ),
                    const Expanded(
                      child: Text('Alert Settings',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              FadeSlideIn(
                child: Column(
                  children: [
              // Turbidity
              _buildSliderCard(
                title: 'Turbidity (NTU)',
                description: 'Maximum turbidity threshold',
                value: _turbidityMax,
                min: 0,
                max: 50,
                divisions: 50,
                valueLabel: '${_turbidityMax.toStringAsFixed(1)} NTU',
                color: AppColors.primary,
                onChanged: (v) => setState(() => _turbidityMax = v),
              ),
              const SizedBox(height: 16),
              // pH range
              _buildRangeSliderCard(
                title: 'pH Range',
                description: 'Acceptable pH range',
                values: _phRange,
                min: 0,
                max: 14,
                divisions: 140,
                valueLabel:
                    '${_phRange.start.toStringAsFixed(1)} - ${_phRange.end.toStringAsFixed(1)}',
                color: const Color(0xFFE91E63),
                onChanged: (v) => setState(() => _phRange = v),
              ),
              const SizedBox(height: 16),
              // TDS
              _buildSliderCard(
                title: 'TDS (ppm)',
                description: 'Maximum TDS threshold',
                value: _tdsMax,
                min: 0,
                max: 1000,
                divisions: 100,
                valueLabel: '${_tdsMax.toStringAsFixed(0)} ppm',
                color: AppColors.secondary,
                onChanged: (v) => setState(() => _tdsMax = v),
              ),
              const SizedBox(height: 16),
              // Water level
              _buildDualSliderCard(
                title: 'Water Level (%)',
                description: 'Low and high level alerts',
                lowValue: _waterLevelLow,
                highValue: _waterLevelHigh,
                min: 0,
                max: 100,
                onLowChanged: (v) => setState(() => _waterLevelLow = v),
                onHighChanged: (v) =>
                    setState(() => _waterLevelHigh = v),
              ),
              const SizedBox(height: 32),
              // Buttons row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving
                            ? null
                            : () => _applyThresholds(const UserThresholds()),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: const BorderSide(color: AppColors.primary),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          minimumSize: const Size(0, 56),
                        ),
                        child: const Text('Reset',
                            style: TextStyle(fontSize: 16)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: _saving ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          minimumSize: const Size(0, 56),
                        ),
                        child: _saving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white),
                              )
                            : const Text('Save',
                                style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSliderCard({
    required String title,
    required String description,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String valueLabel,
    required Color color,
    required ValueChanged<double> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.neutral1)),
              Text(valueLabel,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: color)),
            ],
          ),
          const SizedBox(height: 4),
          Text(description,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.neutral4)),
          const SizedBox(height: 12),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: color,
              thumbColor: color,
              inactiveTrackColor: color.withValues(alpha: 0.15),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRangeSliderCard({
    required String title,
    required String description,
    required RangeValues values,
    required double min,
    required double max,
    required int divisions,
    required String valueLabel,
    required Color color,
    required ValueChanged<RangeValues> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.neutral1)),
              Text(valueLabel,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: color)),
            ],
          ),
          const SizedBox(height: 4),
          Text(description,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.neutral4)),
          const SizedBox(height: 12),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: color,
              thumbColor: color,
              inactiveTrackColor: color.withValues(alpha: 0.15),
            ),
            child: RangeSlider(
              values: values,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDualSliderCard({
    required String title,
    required String description,
    required double lowValue,
    required double highValue,
    required double min,
    required double max,
    required ValueChanged<double> onLowChanged,
    required ValueChanged<double> onHighChanged,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.neutral1)),
          const SizedBox(height: 4),
          Text(description,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.neutral4)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Low: ${lowValue.toInt()}%',
                  style: const TextStyle(
                      color: AppColors.error,
                      fontWeight: FontWeight.w600)),
              Text('High: ${highValue.toInt()}%',
                  style: const TextStyle(
                      color: AppColors.success,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          SliderTheme(
            data: const SliderThemeData(
              activeTrackColor: AppColors.error,
              thumbColor: AppColors.error,
              inactiveTrackColor: Color(0xFFFFE0E0),
            ),
            child: Slider(
              value: lowValue,
              min: min,
              max: max,
              divisions: 100,
              onChanged: onLowChanged,
            ),
          ),
          SliderTheme(
            data: const SliderThemeData(
              activeTrackColor: AppColors.success,
              thumbColor: AppColors.success,
              inactiveTrackColor: Color(0xFFE0FFE0),
            ),
            child: Slider(
              value: highValue,
              min: min,
              max: max,
              divisions: 100,
              onChanged: onHighChanged,
            ),
          ),
        ],
      ),
    );
  }
}

