import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/services/websocket_service.dart';

class TankDetailsScreen extends ConsumerWidget {
  const TankDetailsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tankData = ref.watch(tankDataProvider);
    final waterQuality = ref.watch(waterQualityProvider);

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
                            heightFactor: tankData.level / 100,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    AppColors.primary.withValues(alpha: 0.6),
                                    AppColors.primary,
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(17),
                              ),
                            ),
                          ),
                          Center(
                            child: Text(
                              '${tankData.level.toInt()}%',
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
                      '${tankData.volume.toStringAsFixed(0)} L / ${tankData.capacity.toStringAsFixed(0)} L',
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
                        tankData.status.toUpperCase(),
                        Icons.water_drop,
                        _statusColor(tankData.status)),
                    const SizedBox(height: 12),
                    _buildDetailCard(
                        'Flow Rate',
                        '${tankData.flowRate.toStringAsFixed(1)} L/min',
                        Icons.speed,
                        AppColors.primary),
                    const SizedBox(height: 12),
                    _buildDetailCard(
                        'Turbidity',
                        '${waterQuality.turbidity.value} NTU',
                        Icons.water,
                        AppColors.primary),
                    const SizedBox(height: 12),
                    _buildDetailCard(
                        'pH Level',
                        '${waterQuality.ph.value}',
                        Icons.science,
                        const Color(0xFFE91E63)),
                    const SizedBox(height: 12),
                    _buildDetailCard(
                        'TDS',
                        '${waterQuality.tds.value} ppm',
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
        return AppColors.success;
      case 'moderate':
        return AppColors.warning;
      case 'low':
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
            color: Colors.black.withValues(alpha: 0.05),
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
              color: color.withValues(alpha: 0.12),
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

