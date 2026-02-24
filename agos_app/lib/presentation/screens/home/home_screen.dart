import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:math' as math;
import '../../../data/services/websocket_service.dart';
import '../../../data/services/firestore_service.dart';
import '../../widgets/bottom_nav_bar.dart';
import '../../widgets/notification_modal.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with TickerProviderStateMixin {
  late AnimationController _waveController;
  late Animation<double> _waveAnimation;
  late AnimationController _pageController;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      duration: const Duration(seconds: 6),
      vsync: this,
    )..repeat();
    _waveAnimation = Tween<double>(begin: 0, end: 1).animate(_waveController);
    _pageController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    )..forward();

    // Connect WebSocket so tankDataProvider and waterQualityProvider get live data.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        ref.read(webSocketServiceProvider).connect();
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _waveController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning,';
    if (hour < 17) return 'Good Afternoon,';
    return 'Good Evening,';
  }

  /// Wraps [child] with a staggered slide-up + fade-in animation.
  /// [index] (0, 1, 2, …) determines the start offset of the interval.
  Widget _buildAnimated(int index, Widget child) {
    const total = 4; // number of animated sections
    final start = (index / total).clamp(0.0, 0.8);
    final animation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _pageController,
        curve: Interval(start, 1.0, curve: Curves.easeOutCubic),
      ),
    );
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) => Transform.translate(
        offset: Offset(0, 30 * (1 - animation.value)),
        child: Opacity(opacity: animation.value, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tankData = ref.watch(tankDataProvider);
    // Firestore fallback when WebSocket isn't connected
    const deviceId = 'esp32-sim-001';
    final latestAsync = ref.watch(latestReadingProvider(deviceId));
    final latest = latestAsync.valueOrNull;

    // Merge: prefer WebSocket live data, fall back to Firestore
    final effectiveTank = (tankData.level > 0 || latest == null)
        ? tankData
        : TankData(
            level: latest.level,
            volume: latest.volume,
            capacity: tankData.capacity,
            flowRate: latest.flowRate,
            status: latest.status,
            timestamp: latest.timestamp.toIso8601String(),
          );

    return Scaffold(
      backgroundColor: const Color(0xFFF4F8FB),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Header section (no animation – always visible)
              _buildHeader(),
              // Main content
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 25),
                child: Column(
                  children: [
                    const SizedBox(height: 25),
                    // You Saved card with wave animation
                    _buildAnimated(0, _buildSavingsCard()),
                    const SizedBox(height: 25),
                    // Main Water Tank card
                    _buildAnimated(1, _buildWaterTankCard(effectiveTank)),
                    const SizedBox(height: 25),
                    // AGOS logo at bottom
                    _buildAnimated(2, _buildBottomLogo()),
                    const SizedBox(height: 100), // Space for bottom nav
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const BottomNavBar(currentIndex: 0),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(25),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _greeting(),
                style: TextStyle(
                  color: const Color(0xFF90A5B4),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'Poppins',
                  letterSpacing: -0.14,
                ),
              ),
              //const SizedBox(height: 2),
              Consumer(
                builder: (context, ref, _) {
                  final profileAsync = ref.watch(userProfileProvider);
                  final name = profileAsync.valueOrNull?.name.toUpperCase() ?? '';
                  return Text(
                    name.isEmpty ? '...' : name,
                    style: TextStyle(
                      color: const Color(0xFF141A1E),
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Poppins',
                    ),
                  );
                },
              ),
            ],
          ),
          // Notification icon with red dot
          GestureDetector(
            onTap: () => showNotificationModal(context),
            child: Stack(
              children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF1BA9E1).withValues(alpha: 0.15),
                      blurRadius: 25,
                      offset: const Offset(0, 8),
                      spreadRadius: 2,
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 15,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.notifications_outlined,
                  color: Color(0xFF5DCCFC),
                  size: 20,
                ),
              ),
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFF6B6B),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
          ),
        ],
      ),
    );
  }

  Widget _buildSavingsCard() {
    return Container(
      height: 160,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF5DADE2).withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            // Sophisticated wave background using CustomPaint
            AnimatedBuilder(
              animation: _waveAnimation,
              builder: (context, child) {
                return CustomPaint(
                  size: Size(double.infinity, 160),
                  painter: WaterWavePainter(
                    animationValue: _waveAnimation.value,
                  ),
                );
              },
            ),
            // Content overlay
            Padding(
              padding: const EdgeInsets.all(28),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left side content
                  Expanded(
                    child: Container(
                      width: 100,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Top group: Date and "You Saved"
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'February 01, 2026',
                                style: TextStyle(
                                  color: const Color(0xFF90A5B4),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w400,
                                  fontFamily: 'Poppins',
                                  letterSpacing: -0.12,
                                  height: 0.83, // 10px line height / 12px font size
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'You Saved',
                                style: TextStyle(
                                  color: const Color(0xFF1C5B8D),
                                  fontSize: 17,
                                  fontWeight: FontWeight.w500,
                                  fontFamily: 'Poppins',
                                  height: 1, // leading-none
                                ),
                              ),
                            ],
                          ),
                          // Bottom group: Percentage and gallons
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '18%',
                                style: TextStyle(
                                  color: const Color(0xFF1C5B8D),
                                  fontSize: 47,
                                  fontWeight: FontWeight.w500,
                                  fontFamily: 'Poppins',
                                  letterSpacing: -1.41,
                                  height: 1, // leading-none
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '870.9 gallons',
                                style: TextStyle(
                                  color: const Color(0xFF384144),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w400,
                                  fontFamily: 'Poppins',
                                  letterSpacing: -0.24,
                                  height: 0.83, // 10px line height / 12px font size
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Right side - AGOS Blue Logo
                  Container(
                    width: 135,
                    height: 135,
                    child: SvgPicture.asset(
                      'assets/svg/agos_blue_logo.svg',
                      width: 135,
                      height: 135,
                      fit: BoxFit.contain,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWaterTankCard(TankData tankData) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF5DADE2).withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Header with title and Live indicator
          Row(
            children: [
              // Icon and title
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF00B8DB).withValues(alpha: 0.2),
                      const Color(0xFF2B7FFF).withValues(alpha: 0.2),
                    ],
                  ),
                ),
                child: const Icon(
                  Icons.water_drop_outlined,
                  color: Color(0xFF00D3F2),
                  size: 20,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Main Water Tank',
                      style: TextStyle(
                        color: const Color(0xFF2C3E50),
                        fontSize: 18,
                        fontWeight: FontWeight.w400,
                        fontFamily: 'Poppins',
                      ),
                    ),
                    Text(
                      'Real-time monitoring',
                      style: TextStyle(
                        color: const Color(0xFF7F8C8D),
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        fontFamily: 'Poppins',
                      ),
                    ),
                  ],
                ),
              ),
              // Live indicator
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(
                    color: const Color(0xFF009966),
                    width: 0.8,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF009966).withValues(alpha: 0.32),
                      blurRadius: 11,
                      offset: const Offset(0, 0),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 12,	
                      height: 12,
                      decoration: BoxDecoration(
                        color: const Color(0xFF009966),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF009966),
                          width: 1.5,
                        ),
                        boxShadow: [
                          // Outer green glow
                          BoxShadow(
                            color: const Color(0xFF009966).withValues(alpha: 0.4),
                            blurRadius: 6,
                            offset: const Offset(0, 0),
                          ),
                          // Subtle shadow for depth
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 2,
                            offset: const Offset(1, 1),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Live',
                      style: TextStyle(
                        color: const Color(0xFF009966),
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Tank visualization and data
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Tank visualization
              _buildTankVisualization(tankData),
              const SizedBox(width: 25),
              // Tank data
              Expanded(
                child: _buildTankData(tankData),
              ),
            ],
          ),
          // Divider
          Container(
            margin: const EdgeInsets.only(top: 16, bottom: 16),
            height: 0.8,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Colors.transparent,
                  const Color(0xFF00B8DB).withValues(alpha: 0.3),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          // Flow rate
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Flow Rate',
                style: TextStyle(
                  color: const Color(0xFF7F8C8D),
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  fontFamily: 'Inter',
                ),
              ),
              Row(
                children: [
                  // Flow indicator bars
                  Row(
                    children: List.generate(3, (index) {
                      return Container(
                        margin: EdgeInsets.only(left: index > 0 ? 4 : 0),
                        width: index == 2 ? 8 : 4,
                        height: 12,
                        decoration: BoxDecoration(
                          color: const Color(0xFF00D3F3),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${tankData.flowRate.toStringAsFixed(1)} L/min',
                    style: TextStyle(
                      color: const Color(0xFF00D3F2),
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      fontFamily: 'Inter',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTankVisualization(TankData tankData) {
    final waterLevel = tankData.level / 100;
    return Container(
      width: 128,
      height: 256,
      decoration: BoxDecoration(
        border: Border.all(
          color: const Color(0xFF00B8DB).withValues(alpha: 0.4),
          width: 4,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            // Water fill
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                height: (256 - 8) * waterLevel, // Account for border
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFF53EAFD),
                      Color(0xFF00D3F2),
                      Color(0xFF00B8DB),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF06B6D4).withValues(alpha: 0.6),
                      blurRadius: 30,
                      offset: const Offset(0, -8),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    // Water surface animation - only show if not at top
                    if (waterLevel < 0.95)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: AnimatedBuilder(
                          animation: _waveAnimation,
                          builder: (context, child) {
                            return Container(
                              height: 16,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment(-1 + _waveAnimation.value * 2, 0),
                                  end: Alignment(1 + _waveAnimation.value * 2, 0),
                                  colors: const [
                                    Color(0xFF00D3F2),
                                    Color(0xFF53EAFD),
                                    Color(0xFF00D3F2),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    // Bubbles
                    _buildBubble(26, 88, 4.3),
                    _buildBubble(44, 82, 4.6),
                    _buildBubble(60, 23, 7.3),
                    _buildBubble(79, -42, 5.3),
                    _buildBubble(96, 28, 7.1),
                  ],
                ),
              ),
            ),
            // Tank level indicators
            Positioned(
              left: -32,
              top: 61,
              child: _buildLevelIndicator('75%'),
            ),
            Positioned(
              left: -32,
              top: 122,
              child: _buildLevelIndicator('50%'),
            ),
            Positioned(
              left: -32,
              top: 184,
              child: _buildLevelIndicator('25%'),
            ),
            // Tank overlay with opacity
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF00B8DB).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBubble(double left, double top, double size) {
    return AnimatedBuilder(
      animation: _waveAnimation,
      builder: (context, child) {
        return Positioned(
          left: left,
          top: top + (_waveAnimation.value * 20),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.4),
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }

  Widget _buildLevelIndicator(String level) {
    return Container(
      padding: const EdgeInsets.only(top: 7.2),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: const Color(0xFF00B8DB).withValues(alpha: 0.2),
            width: 0.8,
          ),
        ),
      ),
      child: Text(
        level,
        style: TextStyle(
          color: const Color(0xFF00D3F2).withValues(alpha: 0.6),
          fontSize: 12,
          fontWeight: FontWeight.w400,
          fontFamily: 'Inter',
        ),
      ),
    );
  }

  Widget _buildTankData(TankData tankData) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Current level percentage
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [Color(0xFF00D3F2), Color(0xFF2B7FFF)],
              ).createShader(bounds),
              child: Text(
                '${tankData.level.toInt()}%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Poppins',
                  height: 1.1,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Current Level',
              style: TextStyle(
                color: const Color(0xFF7F8C8D),
                fontSize: 14,
                fontWeight: FontWeight.w400,
                fontFamily: 'Poppins',
              ),
            ),
          ],
        ),
        // Divider
        Container(
          margin: const EdgeInsets.only(top: 16, bottom: 16),
          height: 0.8,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Colors.transparent,
                const Color(0xFF00B8DB).withValues(alpha: 0.3),
                Colors.transparent,
              ],
            ),
          ),
        ),
        // Tank stats
        Column(
          children: [
            _buildStatRow('Volume:', '${tankData.volume.toStringAsFixed(0)} L'),
            const SizedBox(height: 12),
            _buildStatRow('Capacity:', '${tankData.capacity.toStringAsFixed(0)} L'),
            const SizedBox(height: 12),
            _buildStatRow('Available:', '${(tankData.capacity - tankData.volume).toStringAsFixed(0)} L'),
          ],
        ),
        const SizedBox(height: 24),
        // Status indicator
        Builder(builder: (context) {
          final Color statusColor;
          final Color dotColor;
          final String statusLabel;
          if (tankData.level >= 70) {
            statusColor = const Color(0xFF00C851);
            dotColor = const Color(0xFF00C851);
            statusLabel = 'Optimal Level';
          } else if (tankData.level >= 40) {
            statusColor = const Color(0xFFFDC700);
            dotColor = const Color(0xFFFDC700);
            statusLabel = 'Moderate Level';
          } else {
            statusColor = const Color(0xFFFF6B6B);
            dotColor = const Color(0xFFFF6B6B);
            statusLabel = 'Low Level';
          }
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              border: Border.all(
                color: statusColor.withValues(alpha: 0.3),
                width: 0.8,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    fontFamily: 'Inter',
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: const Color(0xFF7F8C8D),
            fontSize: 14,
            fontWeight: FontWeight.w400,
            fontFamily: 'Poppins',
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: const Color(0xFF00D3F2),
            fontSize: 14,
            fontWeight: FontWeight.w400,
            fontFamily: 'Poppins',
          ),
        ),
      ],
    );
  }

  Widget _buildBottomLogo() {
    return Container(
      width: 45,
      height: 23.2,
      child: SvgPicture.asset(
        'assets/svg/agos_logo.svg',
        width: 45,
        height: 23.2,
        fit: BoxFit.contain,
        colorFilter: const ColorFilter.mode(
          Color(0xFF00D3F2),
          BlendMode.srcIn,
        ),
      ),
    );
  }
}

/// Custom painter that draws animated water-like waves for the savings card
class WaterWavePainter extends CustomPainter {
  final double animationValue;

  WaterWavePainter({required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    // Use full 2π cycle so animation loops seamlessly (sin(0) == sin(2π))
    final double phase = animationValue * 2 * math.pi;

    // Wave 1 - back layer, subtle background wave
    _drawWave(
      canvas, size,
      baseY: size.height * 0.35,
      amplitudes: [22.0, 8.0],
      frequencies: [1.0, 2.0],
      phaseOffsets: [phase, phase + 1.2],
      color: const Color(0xFF00D3F2).withValues(alpha: 0.08),
    );

    // Wave 2 - front layer, more prominent
    _drawWave(
      canvas, size,
      baseY: size.height * 0.65,
      amplitudes: [15.0, 6.0],
      frequencies: [1.0, 2.0],
      phaseOffsets: [phase + 2.0, phase + 3.5],
      color: const Color(0xFF00D3F2).withValues(alpha: 0.15),
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