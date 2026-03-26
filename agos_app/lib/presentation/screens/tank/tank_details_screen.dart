import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/services/websocket_service.dart';
import '../../../data/services/firestore_service.dart'
    show latestReadingProvider, linkedDeviceIdProvider, userThresholdsProvider, UserThresholds;

class TankDetailsScreen extends ConsumerWidget {
  const TankDetailsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tankData = ref.watch(tankDataProvider);
    final waterQuality = ref.watch(waterQualityProvider);
    final thresholds = ref.watch(userThresholdsProvider).valueOrNull
        ?? const UserThresholds();

    // Firestore fallback when WebSocket hasn't delivered data yet
    final deviceId =
        ref.watch(linkedDeviceIdProvider).valueOrNull ?? 'agos-zksl9QK3';
    final latestAsync = ref.watch(latestReadingProvider(deviceId));
    final latest = latestAsync.valueOrNull;

    // Effective tank values: prefer WS if it has live data
    final wsHasTank = tankData.level > 0;
    final level = wsHasTank ? tankData.level : (latest?.level ?? 0.0);
    final volume = wsHasTank ? tankData.volume : (latest?.volume ?? 0.0);
    final capacity = tankData.capacity > 0 ? tankData.capacity : 106.0;
    final flowRate =
        wsHasTank ? tankData.flowRate : (latest?.flowRate ?? 0.0);

    // Compute level status dynamically from threshold settings
    final String status;
    if (level <= 0) {
      status = 'unknown';
    } else if (level <= thresholds.levelMin / 2) {
      status = 'critical';
    } else if (level <= thresholds.levelMin) {
      status = 'warning';
    } else if (level >= thresholds.levelHigh) {
      status = 'high';
    } else {
      status = 'optimal';
    }

    // Effective quality values: prefer WS if it has live data
    final wsHasQuality = waterQuality.turbidity.value > 0 ||
        waterQuality.ph.value > 0 ||
        waterQuality.tds.value > 0;
    final turbidity = wsHasQuality
        ? waterQuality.turbidity.value
        : (latest?.turbidity ?? 0.0);
    final ph =
        wsHasQuality ? waterQuality.ph.value : (latest?.ph ?? 0.0);
    final tds =
        wsHasQuality ? waterQuality.tds.value : (latest?.tds ?? 0.0);

    final turbidityStr =
        latest != null || wsHasQuality ? '${turbidity.toStringAsFixed(1)} NTU' : '-- NTU';
    final phStr =
        latest != null || wsHasQuality ? ph.toStringAsFixed(1) : '--';
    final tdsStr =
        latest != null || wsHasQuality ? '${tds.toStringAsFixed(0)} ppm' : '-- ppm';
    final flowStr = '${flowRate.toStringAsFixed(1)} L/min';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Header
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
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_back_ios,
                              color: Colors.white),
                        ),
                        const Expanded(
                          child: Text('Tank Details',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white)),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
                    const SizedBox(height: 24),
                    // Tank visual
                    Container(
                      width: 120,
                      height: 160,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border:
                            Border.all(color: AppColors.primary, width: 3),
                      ),
                      child: Stack(
                        alignment: Alignment.bottomCenter,
                        children: [
                          FractionallySizedBox(
                            heightFactor: (level / 100).clamp(0.0, 1.0),
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    AppColors.primary.withOpacity(0.6),
                                    AppColors.primary,
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(17),
                              ),
                            ),
                          ),
                          Center(
                            child: Text(
                              '${level.toInt()}%',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '${volume.toStringAsFixed(0)} L / ${capacity.toStringAsFixed(0)} L',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 16),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // Details cards
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    _buildDetailCard(
                        'Tank Status',
                        status.toUpperCase(),
                        Icons.water_drop,
                        _statusColor(status)),
                    const SizedBox(height: 12),
                    _buildDetailCard(
                        'Flow Rate',
                        flowStr,
                        Icons.speed,
                        AppColors.primary),
                    const SizedBox(height: 12),
                    _buildDetailCard(
                        'Turbidity',
                        turbidityStr,
                        Icons.water,
                        AppColors.primary),
                    const SizedBox(height: 12),
                    _buildDetailCard(
                        'pH Level',
                        phStr,
                        Icons.science,
                        const Color(0xFFE91E63)),
                    const SizedBox(height: 12),
                    _buildDetailCard(
                        'TDS',
                        tdsStr,
                        Icons.analytics,
                        AppColors.secondary),
                  ],
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'optimal':
      case 'high':
        return AppColors.success;
      case 'warning':
      case 'moderate':
      case 'low':
        return AppColors.warning;
      case 'critical':
        return AppColors.error;
      default:
        return AppColors.neutral4;
    }
  }

  Widget _buildDetailCard(
      String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(width: 16),
          Text(label,
              style: const TextStyle(
                  fontSize: 15, color: AppColors.neutral3)),
          const Spacer(),
          Text(value,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: color)),
        ],
      ),
    );
  }
}

