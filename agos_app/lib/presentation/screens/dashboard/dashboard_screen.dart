import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import '../../../data/services/websocket_service.dart';
import '../../../data/services/firestore_service.dart';
import '../../widgets/notification_modal.dart';
import '../../widgets/bottom_nav_bar.dart';

enum TimePeriod { twentyFourHours, sevenDays, thirtyDays }
enum MetricType { turbidity, ph, tds }

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen>
    with TickerProviderStateMixin {
  MetricType selectedMetric = MetricType.turbidity;
  TimePeriod selectedPeriod = TimePeriod.twentyFourHours;
  
  late AnimationController _particleController;
  late AnimationController _cardController;
  late List<Particle> _particles;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _generateParticles();
    _loadHistoricalData();
  }

  void _initializeAnimations() {
    _particleController = AnimationController(
      duration: const Duration(seconds: 20),
      vsync: this,
    )..repeat();

    _cardController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    )..forward();
  }

  void _generateParticles() {
    final random = math.Random();
    _particles = List.generate(25, (index) {
      return Particle(
        x: random.nextDouble() * 400,
        y: random.nextDouble() * 200,
        size: random.nextDouble() * 3.5 + 0.5,
        opacity: random.nextDouble() * 0.8 + 0.1,
        speed: random.nextDouble() * 0.5 + 0.2,
        direction: random.nextDouble() * 2 * math.pi,
      );
    });
  }

  void _loadHistoricalData() {
    String period = selectedPeriod == TimePeriod.twentyFourHours
        ? '24h'
        : selectedPeriod == TimePeriod.sevenDays
            ? '7d'
            : '30d';

    String metric = selectedMetric == MetricType.turbidity
        ? 'turbidity'
        : selectedMetric == MetricType.ph
            ? 'ph'
            : 'tds';

    try {
      final wsService = ref.read(webSocketServiceProvider);
      if (wsService.isConnected) {
        wsService.requestHistoricalData(metric, period);
      }
    } catch (e) {
      print('Failed to load historical data: $e');
    }
  }

  @override
  void dispose() {
    _particleController.dispose();
    _cardController.dispose();
    super.dispose();
  }

  // ── helpers ──────────────────────────────────────────────────────────────
  static const _kDeviceId = 'esp32-sim-001';

  String _qualityStatus(double value, String metric) {
    switch (metric) {
      case 'turbidity':
        if (value < 20) return '● Optimal';
        if (value < 50) return '● Warning';
        return '● Critical';
      case 'ph':
        if (value >= 6.5 && value <= 8.5) return '● Optimal';
        if (value >= 5.5 && value <= 9.5) return '● Warning';
        return '● Critical';
      case 'tds':
        if (value < 500) return '● Optimal';
        if (value < 1000) return '● Warning';
        return '● Critical';
      default:
        return '● Unknown';
    }
  }

  Color _statusColor(String status) {
    if (status.contains('Warning')) return const Color(0xFFF59E0B);
    if (status.contains('Critical')) return const Color(0xFFEF4444);
    if (status == '● --') return const Color(0xFFB0BEC5); // no data → grey
    return const Color(0xFF009966);
  }

  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // ── Live Firestore sensor data ─────────────────────────────────────────
    final latestAsync = ref.watch(latestReadingProvider(_kDeviceId));
    final reading = latestAsync.valueOrNull;

    // ── WebSocket fallback (for Windows where Firestore threading may drop data)
    final waterQuality = ref.watch(waterQualityProvider);
    final wsHasQuality = waterQuality.turbidity.value > 0 ||
        waterQuality.ph.value > 0 ||
        waterQuality.tds.value > 0;

    // Prefer Firestore reading; fall back to WebSocket if Firestore is null
    final hasData = reading != null || wsHasQuality;
    final turbidityVal = reading?.turbidity ??
        (wsHasQuality ? waterQuality.turbidity.value : 0.0);
    final phVal =
        reading?.ph ?? (wsHasQuality ? waterQuality.ph.value : 0.0);
    final tdsVal =
        reading?.tds ?? (wsHasQuality ? waterQuality.tds.value : 0.0);

    final turbidityStr  = hasData ? '${turbidityVal.toStringAsFixed(1)} NTU' : '-- NTU';
    final phStr         = hasData ? phVal.toStringAsFixed(1) : '--';
    final tdsStr        = hasData ? '${tdsVal.toStringAsFixed(0)} ppm' : '-- ppm';

    final turbidityStatus = hasData ? _qualityStatus(turbidityVal, 'turbidity') : '● --';
    final phStatus        = hasData ? _qualityStatus(phVal, 'ph') : '● --';
    final tdsStatus       = hasData ? _qualityStatus(tdsVal, 'tds') : '● --';

    final turbidityProgress = (turbidityVal / 20.0).clamp(0.0, 1.0);
    final phProgress        = (phVal / 14.0).clamp(0.0, 1.0);
    final tdsProgress       = (tdsVal / 500.0).clamp(0.0, 1.0);
    // ──────────────────────────────────────────────────────────────────────

    return Scaffold(
      backgroundColor: const Color(0xFFF4F8FB),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Header with blue gradient and particles (no animation)
              _buildHeader(),
              // Scrollable content
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 25),
                child: Column(
                  children: [
                    const SizedBox(height: 25),
                    // System Status Card (no animation)
                    _buildSystemStatusCard(),
                    const SizedBox(height: 25),
                    // Water Quality Metrics Title
                    _buildSectionTitle('Water Quality Metrics'),
                    const SizedBox(height: 25),
                    // Water Quality Metrics Cards
                    AnimatedBuilder(
                      animation: _cardController,
                      builder: (context, child) {
                        return Column(
                          children: [
                            _buildMetricCard(
                              'Turbidity',
                              turbidityStr,
                              turbidityStatus,
                              turbidityProgress,
                              'Target: < 20 NTU',
                              const LinearGradient(
                                colors: [Color(0xFF00D3F2), Color(0xFF2B7FFF)],
                              ),
                              0.0,
                              statusColor: _statusColor(turbidityStatus),
                            ),
                            const SizedBox(height: 16),
                            _buildMetricCard(
                              'pH Level',
                              phStr,
                              phStatus,
                              phProgress,
                              'Target: 6.5 - 8.5',
                              const LinearGradient(
                                colors: [Color(0xFFC27AFF), Color(0xFFF6339A)],
                              ),
                              0.3,
                              statusColor: _statusColor(phStatus),
                            ),
                            const SizedBox(height: 16),
                            _buildMetricCard(
                              'Total Dissolved Solids',
                              tdsStr,
                              tdsStatus,
                              tdsProgress,
                              'Target: < 500 ppm',
                              const LinearGradient(
                                colors: [Color(0xFF7C86FF), Color(0xFF2B7FFF)],
                              ),
                              0.6,
                              statusColor: _statusColor(tdsStatus),
                            ),
                            const SizedBox(height: 25),
                            _buildSectionTitle('Historical Trends'),
                            const SizedBox(height: 25),
                            _buildChartsSection(),
                            const SizedBox(height: 32),
                            Center(
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
                            ),
                            const SizedBox(height: 100), // Bottom padding for navigation
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const BottomNavBar(currentIndex: 1),
    );
  }

  Widget _buildHeader() {
    return Container(
      // height: 278,
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF1447E6),
            Color(0xFF0092B8),
          ],
        ),
      ),
      child: Stack(
        children: [
          // Floating particles animation
          AnimatedBuilder(
            animation: _particleController,
            builder: (context, child) {
              return CustomPaint(
                size: Size(double.infinity, 150),
                painter: ParticlesPainter(_particles, _particleController.value),
              );
            },
          ),
          // Header content
          Padding(
            padding: EdgeInsets.fromLTRB(25, 25 + MediaQuery.of(context).padding.top, 25, 25),
            child: Column(
              children: [
                // Top row with notification
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const SizedBox(width: 40), // Space equivalent to notification icon
                    // Notification icon (same style as home/settings)
                    GestureDetector(
                      onTap: () => showNotificationModal(context),
                      child: SizedBox(
                      width: 40,
                      height: 40,
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
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Logo and title section
                Container(
                  // height: 104,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // AGOS Logo and title
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // AGOS Logo
                          SvgPicture.asset(
                            'assets/svg/agos_logo.svg',
                            width: 50,
                            height: 54,
                            colorFilter: const ColorFilter.mode(
                              Colors.white,
                              BlendMode.srcIn,
                            ),
                          ),
                          const SizedBox(width: 7),
                          // AGOS text
                          // SvgPicture.asset(
                          //   'assets/svg/agos_square_logo.svg',
                          //   width: 122,
                          //   height: 32,
                          //   colorFilter: const ColorFilter.mode(
                          //     Colors.white,
                          //     BlendMode.srcIn,
                          //   ),
                          // ),
                        ],
                      ),
                      // const SizedBox(height: 16),
                      // University name
                      Text(
                        'Pamantasan ng Lungsod ng Maynila',
                        style: TextStyle(
                          color: const Color(0xFFBEDBFF),
                          fontSize: 12,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 5),
                      // Live indicator and last updated
                      Row(
                        children: [
                          // Live indicator (same style as home page)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.0),
                              border: Border.all(
                                color: const Color(0xFF53EAFD),
                                width: 0.8,
                              ),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF53EAFD).withValues(alpha: 0.32),
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
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF53EAFD),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Live',
                                  style: TextStyle(
                                    color: const Color(0xFF53EAFD),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w400,
                                    fontFamily: 'Inter',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 7),
                          // Updated text
                          Text(
                            '• Updated 0s ago',
                            style: TextStyle(
                              color: const Color(0xFF53EAFD),
                              fontSize: 12,
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemStatusCard() {
    return Container(
      width: double.infinity,
      height: 80,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.18),
          width: 1.18,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF5DADE2).withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            // Status icon container
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Center(
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.check,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            // Status text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'System Status',
                    style: TextStyle(
                      color: const Color(0xFF62748E),
                      fontSize: 14,
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  // const SizedBox(height: 4),
                  ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [Color(0xFF1447E6), Color(0xFF0092B8)],
                    ).createShader(bounds),
                    child: Text(
                      'Operational',
                      style: TextStyle(
                        fontSize: 16,
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Operational badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 5),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF00D492), Color(0xFF00BBA7)],
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 15,
                    offset: const Offset(0, 10),
                    spreadRadius: -3,
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 6,
                    offset: const Offset(0, 4),
                    spreadRadius: -4,
                  ),
                ],
              ),
              child: Text(
                'Operational',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Container(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.only(left: 4),
        child: ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Color(0xFF1447E6), Color(0xFF0092B8)],
          ).createShader(bounds),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMetricCard(
    String title,
    String value,
    String status,
    double progress,
    String target,
    LinearGradient iconGradient,
    double animationDelay, {
    Color statusColor = const Color(0xFF009966),
  }) {
    final animation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _cardController,
        curve: Interval(animationDelay, 1.0, curve: Curves.easeOutCubic),
      ),
    );

    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, 50 * (1 - animation.value)),
          child: Opacity(
            opacity: animation.value,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.18),
                  width: 1.18,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF5DADE2).withValues(alpha: 0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Top row with icon, title, value, and status
                    Row(
                      children: [
                        // Gradient icon container
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            gradient: iconGradient,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: iconGradient.colors.first.withValues(alpha: 0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.water_drop_outlined,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Title and value
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: TextStyle(
                                  color: const Color(0xFF62748E),
                                  fontSize: 14,
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                              const SizedBox(height: 4),
                              ShaderMask(
                                shaderCallback: (bounds) => const LinearGradient(
                                  colors: [Color(0xFF1447E6), Color(0xFF0092B8)],
                                ).createShader(bounds),
                                child: Text(
                                  value,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontFamily: 'Inter',
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Status
                        Text(
                          status,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 12,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 9),
                    // Progress bar
                    Container(
                      height: 8,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFF1F5F9), Color(0xFFE2E8F0)],
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: progress,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF00D492), Color(0xFF00BBA7)],
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 9),
                    // Target text
                    Text(
                      target,
                      style: TextStyle(
                        color: const Color(0xFF90A1B9),
                        fontSize: 12,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildChartsSection() {
    return Column(
      children: [
        _HistoricalChartCard(
          label: 'Turbidity',
          gradient: const LinearGradient(
            colors: [Color(0xFF00B8DB), Color(0xFF155DFC)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          primaryColor: const Color(0xFF00B8DB),
        ),
        const SizedBox(height: 20),
        _HistoricalChartCard(
          label: 'pH',
          gradient: const LinearGradient(
            colors: [Color(0xFFC27AFF), Color(0xFFF6339A)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          primaryColor: const Color(0xFFC27AFF),
        ),
        const SizedBox(height: 20),
        _HistoricalChartCard(
          label: 'TDS',
          gradient: const LinearGradient(
            colors: [Color(0xFF7C86FF), Color(0xFF2B7FFF)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          primaryColor: const Color(0xFF7C86FF),
        ),
      ],
    );
  }
}

// Particle class for floating animation
class Particle {
  double x;
  double y;
  final double size;
  final double opacity;
  final double speed;
  final double direction;

  Particle({
    required this.x,
    required this.y,
    required this.size,
    required this.opacity,
    required this.speed,
    required this.direction,
  });

  void update(double width, double height, double time) {
    x += math.cos(direction + time * 0.5) * speed;
    y += math.sin(direction + time * 0.3) * speed * 0.5;

    // Wrap around screen
    if (x > width) x = 0;
    if (x < 0) x = width;
    if (y > height) y = 0;
    if (y < 0) y = height;
  }
}

// Custom painter for floating particles
class ParticlesPainter extends CustomPainter {
  final List<Particle> particles;
  final double animationValue;

  ParticlesPainter(this.particles, this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF53EAFD).withValues(alpha: 0.3);

    for (final particle in particles) {
      particle.update(size.width, size.height, animationValue * 20);
      
      paint.color = Color(0xFF53EAFD).withValues(alpha: particle.opacity * 0.3);
      canvas.drawCircle(
        Offset(particle.x, particle.y),
        particle.size,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant ParticlesPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Historical Chart Card – self-contained card with real fl_chart line chart
// ─────────────────────────────────────────────────────────────────────────────

class _HistoricalChartCard extends ConsumerStatefulWidget {
  final String label;
  final LinearGradient gradient;
  final Color primaryColor;

  const _HistoricalChartCard({
    required this.label,
    required this.gradient,
    required this.primaryColor,
  });

  @override
  ConsumerState<_HistoricalChartCard> createState() => _HistoricalChartCardState();
}

class _HistoricalChartCardState extends ConsumerState<_HistoricalChartCard> {
  TimePeriod _selectedPeriod = TimePeriod.twentyFourHours;

  // Per-metric ranges
  double get _yMin {
    switch (widget.label) {
      case 'pH': return 0;
      case 'TDS': return 0;
      default: return 0; // Turbidity
    }
  }

  double get _yMax {
    switch (widget.label) {
      case 'pH': return 14;
      case 'TDS': return 1000;
      default: return 30; // Turbidity NTU
    }
  }

  double get _yInterval {
    switch (widget.label) {
      case 'pH': return 2;
      case 'TDS': return 200;
      default: return 10; // Turbidity
    }
  }

  String _formatY(double v) {
    switch (widget.label) {
      case 'pH': return v.toStringAsFixed(1);
      case 'TDS': return '${v.toInt()}';
      default: return '${v.toInt()}';
    }
  }

  static final Map<String, Map<TimePeriod, List<FlSpot>>> _dummyData = {
    'Turbidity': {
      TimePeriod.twentyFourHours: List.generate(25, (i) =>
          FlSpot(i.toDouble(), (2.0 + 3.0 * math.sin(i * 0.4) + 1.0).clamp(0, 30))),
      TimePeriod.sevenDays: List.generate(8, (i) =>
          FlSpot(i.toDouble(), (3.0 + 2.0 * math.sin(i * 0.9)).clamp(0, 30))),
      TimePeriod.thirtyDays: List.generate(31, (i) =>
          FlSpot(i.toDouble(), (2.5 + 4.0 * math.sin(i * 0.35)).clamp(0, 30))),
    },
    'pH': {
      TimePeriod.twentyFourHours: List.generate(25, (i) =>
          FlSpot(i.toDouble(), (7.0 + 0.8 * math.sin(i * 0.4)).clamp(0, 14))),
      TimePeriod.sevenDays: List.generate(8, (i) =>
          FlSpot(i.toDouble(), (7.2 + 0.5 * math.sin(i * 0.9)).clamp(0, 14))),
      TimePeriod.thirtyDays: List.generate(31, (i) =>
          FlSpot(i.toDouble(), (7.0 + 0.7 * math.sin(i * 0.35)).clamp(0, 14))),
    },
    'TDS': {
      TimePeriod.twentyFourHours: List.generate(25, (i) =>
          FlSpot(i.toDouble(), (320.0 + 60.0 * math.sin(i * 0.4)).clamp(0, 1000))),
      TimePeriod.sevenDays: List.generate(8, (i) =>
          FlSpot(i.toDouble(), (300.0 + 80.0 * math.sin(i * 0.9)).clamp(0, 1000))),
      TimePeriod.thirtyDays: List.generate(31, (i) =>
          FlSpot(i.toDouble(), (310.0 + 70.0 * math.sin(i * 0.35)).clamp(0, 1000))),
    },
  };

  // ── Firestore integration ─────────────────────────────────────────────────
  static const _kDeviceId = 'esp32-sim-001';

  String get _firestoreField {
    switch (widget.label) {
      case 'Turbidity': return 'turbidity';
      case 'pH': return 'ph';
      default: return 'tds';
    }
  }

  int get _periodHours {
    switch (_selectedPeriod) {
      case TimePeriod.twentyFourHours: return 24;
      case TimePeriod.sevenDays: return 168;
      case TimePeriod.thirtyDays: return 720;
    }
  }

  // Maps x-value → actual timestamp for live-data tooltips
  final Map<double, DateTime> _timestampMap = {};

  /// Returns live Firestore spots with X = hours-ago (24H) or days-ago (7D/30D).
  /// Falls back to dummy data when no readings exist.
  List<FlSpot> get _spots {
    final historyAsync = ref.watch(
      readingHistoryProvider((_kDeviceId, _periodHours)),
    );
    final readings = historyAsync.valueOrNull ?? [];
    if (readings.isEmpty) {
      _timestampMap.clear();
      return _dummyData[widget.label]?[_selectedPeriod] ?? [];
    }
    final now = DateTime.now();
    _timestampMap.clear();
    final List<FlSpot> result = [];
    for (final r in readings) {
      final dt = r.timestamp;
      final diffMinutes = now.difference(dt).inMinutes;
      if (diffMinutes < 0) continue;
      // X = hours ago for 24H; days ago for 7D/30D (as fraction)
      final double x = _selectedPeriod == TimePeriod.twentyFourHours
          ? diffMinutes / 60.0
          : diffMinutes / (60.0 * 24.0);
      final double value = switch (_firestoreField) {
        'turbidity' => r.turbidity,
        'ph' => r.ph,
        _ => r.tds,
      };
      // Round key to 2 decimal places for map lookup
      final xKey = double.parse(x.toStringAsFixed(2));
      _timestampMap[xKey] = dt;
      result.add(FlSpot(xKey, value));
    }
    // Sort oldest-first (largest x = furthest in past → put last on chart, so reverse: smallest x = most recent)
    // For line chart oldest-first means largest x first → reverse
    result.sort((a, b) => b.x.compareTo(a.x)); // oldest first (largest hours-ago at left edge)
    // Re-index x so oldest = 0 for cleaner axis, while keeping timestamp map
    if (result.isEmpty) return _dummyData[widget.label]?[_selectedPeriod] ?? [];
    return result;
  }

  /// Fallback axis maximum when no live data is available.
  double get _maxX {
    switch (_selectedPeriod) {
      case TimePeriod.twentyFourHours: return 24;
      case TimePeriod.sevenDays: return 7;
      case TimePeriod.thirtyDays: return 30;
    }
  }

  String _getBottomLabel(double value) {
    switch (_selectedPeriod) {
      case TimePeriod.twentyFourHours:
        // value = hours ago; show at 0, 6, 12, 18, 24
        final hoursLabels = {0.0: 'Now', 6.0: '-6h', 12.0: '-12h', 18.0: '-18h', 24.0: '-24h'};
        for (final entry in hoursLabels.entries) {
          if ((value - entry.key).abs() < 0.4) return entry.value;
        }
        return '';
      case TimePeriod.sevenDays:
        // value = days ago
        if ((value - value.roundToDouble()).abs() > 0.05) return '';
        final d = value.round();
        if (d == 0) return 'Today';
        if (d == 1) return '-1d';
        if (d == 7) return '-7d';
        return d % 2 == 0 ? '-${d}d' : '';
      case TimePeriod.thirtyDays:
        if ((value - value.roundToDouble()).abs() > 0.5) return '';
        final d = value.round();
        if (d == 0) return 'Today';
        if ([5, 10, 15, 20, 25, 30].contains(d)) return '-${d}d';
        return '';
    }
  }

  String _getTooltipX(double value) {
    // If we have a real timestamp for this x value, show it
    final xKey = double.parse(value.toStringAsFixed(2));
    final ts = _timestampMap[xKey];
    if (ts != null) {
      final h = ts.hour.toString().padLeft(2, '0');
      final m = ts.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }
    // Dummy data fallback: value = hours-ago or days-ago
    switch (_selectedPeriod) {
      case TimePeriod.twentyFourHours:
        return '-${value.toStringAsFixed(1)}h';
      case TimePeriod.sevenDays:
        return '-${value.toStringAsFixed(1)}d';
      case TimePeriod.thirtyDays:
        return '-${value.toStringAsFixed(0)}d';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18), width: 1.18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF5DADE2).withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  gradient: widget.gradient,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: widget.primaryColor.withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Text(
                  widget.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Row(
                children: [
                  _buildPeriodBtn('24H', TimePeriod.twentyFourHours),
                  const SizedBox(width: 6),
                  _buildPeriodBtn('7D', TimePeriod.sevenDays),
                  const SizedBox(width: 6),
                  _buildPeriodBtn('30D', TimePeriod.thirtyDays),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: LineChart(
              _buildChartData(),
              duration: const Duration(milliseconds: 300),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodBtn(String label, TimePeriod period) {
    final isSelected = _selectedPeriod == period;
    return GestureDetector(
      onTap: () => setState(() => _selectedPeriod = period),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: isSelected ? widget.primaryColor : const Color(0xFFB0BEC5),
              fontSize: 13,
              fontFamily: 'Inter',
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          const SizedBox(height: 3),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 2,
            width: isSelected ? 24 : 0,
            decoration: BoxDecoration(
              color: widget.primaryColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }

  LineChartData _buildChartData() {
    final spots = _spots;
    // maxX = full period window; minX = 0 (most recent)
    final effectiveMaxX = spots.isNotEmpty
        ? (spots.last.x).ceilToDouble().clamp(spots.last.x, _maxX)
        : _maxX;
    return LineChartData(
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          curveSmoothness: 0.35,
          gradient: widget.gradient,
          barWidth: 2.5,
          isStrokeCapRound: true,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              colors: [
                widget.primaryColor.withValues(alpha: 0.15),
                Colors.transparent,
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
      ],
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 36,
            interval: _yInterval,
            getTitlesWidget: (value, meta) {
              if (value < _yMin || value > _yMax) return const SizedBox.shrink();
              return Text(
                _formatY(value),
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 9, fontFamily: 'Inter'),
              );
            },
          ),
        ),
        bottomTitles: AxisTitles(
          axisNameWidget: Text(
            _selectedPeriod == TimePeriod.thirtyDays || _selectedPeriod == TimePeriod.sevenDays
                ? '← days ago'
                : '← hours ago',
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontFamily: 'Inter'),
          ),
          axisNameSize: 18,
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 22,
            interval: 1,
            getTitlesWidget: (value, meta) {
              final label = _getBottomLabel(value);
              if (label.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  label,
                  style: const TextStyle(color: Color(0xFF64748B), fontSize: 10, fontFamily: 'Inter'),
                ),
              );
            },
          ),
        ),
      ),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: _yInterval,
        getDrawingHorizontalLine: (value) => const FlLine(color: Color(0xFFE8F0F7), strokeWidth: 1),
      ),
      borderData: FlBorderData(show: false),
      minX: 0,
      maxX: effectiveMaxX,
      minY: _yMin,
      maxY: _yMax,
      lineTouchData: LineTouchData(
        enabled: true,
        touchTooltipData: LineTouchTooltipData(
          tooltipBgColor: Colors.white,
          tooltipBorder: const BorderSide(color: Color(0xFFE2E8F0)),
          tooltipRoundedRadius: 8.0,
          getTooltipItems: (touchedSpots) {
            return touchedSpots.map((spot) {
              return LineTooltipItem(
                '${_getTooltipX(spot.x)}\n${spot.y.toStringAsFixed(1)}',
                TextStyle(
                  color: widget.primaryColor,
                  fontSize: 12,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w500,
                ),
              );
            }).toList();
          },
        ),
        getTouchedSpotIndicator: (barData, spotIndexes) {
          return spotIndexes.map((index) {
            return TouchedSpotIndicatorData(
              FlLine(
                color: widget.primaryColor.withValues(alpha: 0.5),
                strokeWidth: 1.5,
                dashArray: [4, 4],
              ),
              FlDotData(
                getDotPainter: (spot, percent, bar, idx) => FlDotCirclePainter(
                  radius: 5,
                  color: widget.primaryColor,
                  strokeWidth: 2,
                  strokeColor: Colors.white,
                ),
              ),
            );
          }).toList();
        },
      ),
    );
  }
}
