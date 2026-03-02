import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import '../../../data/services/websocket_service.dart';
import '../../../data/services/firestore_service.dart';
import '../../widgets/notification_modal.dart';
import '../../widgets/bottom_nav_bar.dart';

enum TimePeriod { oneHour, twentyFourHours, sevenDays, thirtyDays }
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

  // Clock for "Updated X ago"
  Timer? _clockTimer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _generateParticles();
    _loadHistoricalData();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
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
    String period = selectedPeriod == TimePeriod.oneHour
        ? '1h'
        : selectedPeriod == TimePeriod.twentyFourHours
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
    _clockTimer?.cancel();
    _particleController.dispose();
    _cardController.dispose();
    super.dispose();
  }

  String _formatAgo(DateTime last) {
    final diff = _now.difference(last);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }

  // ── helpers ──────────────────────────────────────────────────────────────
  String _qualityStatus(double value, String metric, UserThresholds t) {
    switch (metric) {
      case 'turbidity':
        if (value >= t.turbidityMin && value <= t.turbidityMax) return '● Optimal';
        return '● Warning';
      case 'ph':
        if (value >= t.phMin && value <= t.phMax) return '● Optimal';
        return '● Warning';
      case 'tds':
        if (value <= t.tdsMax) return '● Optimal';
        return '● Warning';
      default:
        return '● Unknown';
    }
  }

  Color _statusColor(String status) {
    if (status.contains('Warning')) return const Color(0xFFF59E0B);
    if (status == '● --') return const Color(0xFFB0BEC5); // no data → grey
    return const Color(0xFF009966);
  }

  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // ── Real device ID from Firestore ──────────────────────────────────────
    final deviceId = ref.watch(linkedDeviceIdProvider).valueOrNull ?? 'agos-zksl9QK3';
    // ── User profile (for location display) ───────────────────────────────
    final userProfile = ref.watch(userProfileProvider).valueOrNull;
    final deviceLocation = userProfile?.location ?? '';
    // ── Live Firestore sensor data ─────────────────────────────────────────
    final latestAsync = ref.watch(latestReadingProvider(deviceId));
    final reading = latestAsync.valueOrNull;
    // ── User thresholds ────────────────────────────────────────────────────
    final thresholds = ref.watch(userThresholdsProvider).valueOrNull
        ?? const UserThresholds();
    // ── Connection state ───────────────────────────────────────────────────
    final isLive = ref.watch(wsConnectedProvider);
    final lastData = ref.watch(wsLastDataProvider);

    // ── WebSocket fallback (for Windows where Firestore threading may drop data)
    final waterQuality = ref.watch(waterQualityProvider);
    final wsHasQuality = waterQuality.turbidity.value > 0 ||
        waterQuality.ph.value > 0 ||
        waterQuality.tds.value > 0;

    // Prefer WebSocket (live, every 5s); fall back to Firestore if WS is offline
    final hasData = wsHasQuality || reading != null;
    final turbidityVal = wsHasQuality
        ? waterQuality.turbidity.value
        : (reading?.turbidity ?? 0.0);
    final phVal = wsHasQuality
        ? waterQuality.ph.value
        : (reading?.ph ?? 0.0);
    final tdsVal = wsHasQuality
        ? waterQuality.tds.value
        : (reading?.tds ?? 0.0);

    final turbidityStr  = hasData ? '${turbidityVal.toStringAsFixed(1)} NTU' : '-- NTU';
    final phStr         = hasData ? phVal.toStringAsFixed(1) : '--';
    final tdsStr        = hasData ? '${tdsVal.toStringAsFixed(0)} ppm' : '-- ppm';

    final turbidityStatus = hasData ? _qualityStatus(turbidityVal, 'turbidity', thresholds) : '● --';
    final phStatus        = hasData ? _qualityStatus(phVal, 'ph', thresholds) : '● --';
    final tdsStatus       = hasData ? _qualityStatus(tdsVal, 'tds', thresholds) : '● --';

    final turbidityProgress = (turbidityVal / thresholds.turbidityMax).clamp(0.0, 1.0);
    final phProgress        = (phVal / 14.0).clamp(0.0, 1.0);
    final tdsProgress       = (tdsVal / thresholds.tdsMax).clamp(0.0, 1.0);
    // ──────────────────────────────────────────────────────────────────────

    return Scaffold(
      backgroundColor: const Color(0xFFF4F8FB),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Header with blue gradient and particles (no animation)
              _buildHeader(deviceLocation, isLive: isLive, lastData: lastData),
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
                              'Target: ${thresholds.turbidityMin.toStringAsFixed(0)}–${thresholds.turbidityMax.toStringAsFixed(0)} NTU',
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
                              'Target: ${thresholds.phMin.toStringAsFixed(1)} - ${thresholds.phMax.toStringAsFixed(1)}',
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
                              'Target: < ${thresholds.tdsMax.toStringAsFixed(0)} ppm',
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

  Widget _buildHeader(String deviceLocation, {bool isLive = false, DateTime? lastData}) {
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
                        if (ref.watch(hasUnreadAlertsProvider))
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
                      // University / location name
                      Text(
                        deviceLocation.isNotEmpty
                            ? deviceLocation
                            : 'No location set',
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
                          // Live/Idle indicator
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.0),
                              border: Border.all(
                                color: isLive ? const Color(0xFF53EAFD) : Colors.white.withValues(alpha: 0.6),
                                width: 0.8,
                              ),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: (isLive ? const Color(0xFF53EAFD) : Colors.white)
                                      .withValues(alpha: 0.20),
                                  blurRadius: 8,
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
                                    color: isLive ? const Color(0xFF53EAFD) : Colors.white.withValues(alpha: 0.7),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  isLive ? 'Live' : 'Idle',
                                  style: TextStyle(
                                    color: isLive ? const Color(0xFF53EAFD) : Colors.white.withValues(alpha: 0.85),
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
                            lastData != null
                                ? '• Updated ${_formatAgo(lastData)}'
                                : '• Waiting for data...',
                            style: TextStyle(
                              color: isLive
                                  ? const Color(0xFF53EAFD)
                                  : Colors.white.withValues(alpha: 0.7),
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
  TimePeriod _selectedPeriod = TimePeriod.oneHour;
  Timer? _refreshTimer;
  int _refreshTick = 0; // increments every minute to force stream re-subscription

  // X-axis zoom/pan state
  double _xZoom = 1.0;   // 1.0 = full period; >1 = zoomed in
  double _xPanOffset = 0.0; // pan offset in X units (minutes or hours)
  double _scaleStartZoom = 1.0;
  double _scaleStartOffset = 0.0;
  double _effectiveMaxX = 60.0; // updated each frame from _buildChartData
  bool _isZooming = false; // true during pinch — disables chart touch to allow pinch

  @override
  void initState() {
    super.initState();
    // Re-subscribe Firestore stream every 60s so the cutoff window stays fresh.
    // Incrementing _refreshTick changes the provider family key, forcing a new
    // stream subscription with an updated cutoff = DateTime.now() - hours.
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) {
        setState(() => _refreshTick++);
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  // Per-metric fallback ranges (used when no data is available)
  double get _yMinFallback {
    switch (widget.label) {
      case 'pH': return 0;
      case 'TDS': return 0;
      default: return 0; // Turbidity
    }
  }

  double get _yMaxFallback {
    switch (widget.label) {
      case 'pH': return 14;
      case 'TDS': return 1000;
      default: return 60; // Turbidity NTU
    }
  }

  /// Compute Y range dynamically from spot data with 10% padding.
  /// Falls back to metric defaults when no data.
  ({double min, double max, double interval}) _computeYRange(List<FlSpot> spots) {
    if (spots.isEmpty) {
      final fallbackInterval = widget.label == 'pH'
          ? 2.0
          : widget.label == 'TDS'
              ? 200.0
              : 10.0;
      return (min: _yMinFallback, max: _yMaxFallback, interval: fallbackInterval);
    }
    final values = spots.map((s) => s.y).toList();
    final dataMin = values.reduce((a, b) => a < b ? a : b);
    final dataMax = values.reduce((a, b) => a > b ? a : b);
    final range = (dataMax - dataMin).abs().clamp(0.001, double.infinity);
    final padding = range * 0.15;
    final yMin = (dataMin - padding).floorToDouble().clamp(0.0, double.infinity);
    final yMax = (dataMax + padding).ceilToDouble();
    // Auto-interval: aim for ~5 lines
    final rawInterval = (yMax - yMin) / 5;
    double interval;
    if (rawInterval <= 0.5) {
      interval = 0.5;
    } else if (rawInterval <= 1) {
      interval = 1;
    } else if (rawInterval <= 2) {
      interval = 2;
    } else if (rawInterval <= 5) {
      interval = 5;
    } else if (rawInterval <= 10) {
      interval = 10;
    } else if (rawInterval <= 25) {
      interval = 25;
    } else if (rawInterval <= 50) {
      interval = 50;
    } else if (rawInterval <= 100) {
      interval = 100;
    } else if (rawInterval <= 200) {
      interval = 200;
    } else {
      interval = (rawInterval / 100).ceil() * 100;
    }
    return (min: yMin, max: yMax, interval: interval);
  }

  String _formatY(double v) {
    switch (widget.label) {
      case 'pH': return v.toStringAsFixed(1);
      case 'TDS': return '${v.toInt()}';
      default: return '${v.toInt()}';
    }
  }

  // ── Firestore integration ─────────────────────────────────────────────────
  String get _deviceId =>
      ref.watch(linkedDeviceIdProvider).valueOrNull ?? 'agos-zksl9QK3';

  String get _firestoreField {
    switch (widget.label) {
      case 'Turbidity': return 'turbidity';
      case 'pH': return 'ph';
      default: return 'tds';
    }
  }

  int get _periodHours {
    switch (_selectedPeriod) {
      case TimePeriod.oneHour: return 1;
      case TimePeriod.twentyFourHours: return 24;
      case TimePeriod.sevenDays: return 168;
      case TimePeriod.thirtyDays: return 720;
    }
  }

  // Maps x-value → actual timestamp for tooltips
  final Map<int, DateTime> _timestampMap = {};

  /// X coordinate helpers:
  ///  24H → x = minutes since start of the 24-hour window (0 = 24h ago, 1440 = now)
  ///  7D  → x = hours since start of the 7-day window   (0 = 7d ago, 168 = now)
  /// 30D  → x = hours since start of the 30-day window  (0 = 30d ago, 720 = now)
  double _toX(DateTime dt) {
    final now = DateTime.now();
    final diffMs = dt.difference(now.subtract(Duration(hours: _periodHours))).inMilliseconds;
    if (_selectedPeriod == TimePeriod.oneHour) {
      return (diffMs / 60000.0).clamp(0, 60); // minutes within the last hour
    }
    if (_selectedPeriod == TimePeriod.twentyFourHours) {
      return (diffMs / 60000.0).clamp(0, 1440); // minutes within 24h
    }
    return (diffMs / 3600000.0).clamp(0, _periodHours.toDouble()); // hours
  }

  bool _hasLiveData = false;
  String? _dataError;

  /// Returns live Firestore spots. Sets _hasLiveData and _dataError as side effects.
  List<FlSpot> _buildSpots(AsyncValue<List<SensorReading>> historyAsync) {
    if (historyAsync.hasError) {
      _timestampMap.clear();
      _hasLiveData = false;
      _dataError = historyAsync.error.toString();
      return [];
    }
    _dataError = null;
    final readings = historyAsync.valueOrNull ?? [];
    if (readings.isEmpty) {
      _timestampMap.clear();
      _hasLiveData = false;
      return []; // return empty — chart will show empty state
    }
    _hasLiveData = true;
    _timestampMap.clear();
    final List<FlSpot> result = [];
    for (final r in readings) {
      final dt = r.timestamp;
      final double x = _toX(dt);
      final double value = switch (_firestoreField) {
        'turbidity' => r.turbidity,
        'ph' => r.ph,
        _ => r.tds,
      };
      final xInt = x.round();
      _timestampMap[xInt] = dt;
      result.add(FlSpot(x, value));
    }
    result.sort((a, b) => a.x.compareTo(b.x)); // oldest first (left edge)
    return result;
  }

  /// Build spots from the live real-time rolling chart buffer (1H waveform).
  List<FlSpot> _buildLiveSpots(List<LiveChartPoint> points) {
    if (points.isEmpty) {
      _timestampMap.clear();
      _hasLiveData = false;
      return [];
    }
    _hasLiveData = true;
    _timestampMap.clear();
    final List<FlSpot> result = [];
    for (final p in points) {
      final double x = _toX(p.timestamp);
      final double value = switch (_firestoreField) {
        'turbidity' => p.turbidity,
        'ph' => p.ph,
        _ => p.tds,
      };
      final xInt = x.round();
      _timestampMap[xInt] = p.timestamp;
      result.add(FlSpot(x, value));
    }
    result.sort((a, b) => a.x.compareTo(b.x));
    return result;
  }

  /// Full period window in the X coordinate unit.
  double get _maxX {
    switch (_selectedPeriod) {
      case TimePeriod.oneHour: return 60;       // 60 minutes
      case TimePeriod.twentyFourHours: return 1440; // 24*60 minutes
      case TimePeriod.sevenDays: return 168;         // 7*24 hours
      case TimePeriod.thirtyDays: return 720;        // 30*24 hours
    }
  }

  String _getBottomLabel(double value) {
    final now = DateTime.now();
    switch (_selectedPeriod) {
      case TimePeriod.oneHour: {
        // x = minutes from 1h ago → show every 15 min
        if (value % 15 > 1) return '';
        final dt = now.subtract(Duration(minutes: (60 - value).round()));
        final h = dt.hour.toString().padLeft(2, '0');
        final m = dt.minute.toString().padLeft(2, '0');
        return '$h:$m';
      }
      case TimePeriod.twentyFourHours: {
        // x = minutes from 24h ago → show every 4 hours (every 240 min)
        if (value % 240 > 12) return '';
        final dt = now.subtract(Duration(minutes: (1440 - value).round()));
        final h = dt.hour.toString().padLeft(2, '0');
        final m = dt.minute.toString().padLeft(2, '0');
        return '$h:$m';
      }
      case TimePeriod.sevenDays: {
        // x = hours from 7d ago → show every 24h
        if (value % 24 > 1) return '';
        final dt = now.subtract(Duration(hours: (168 - value).round()));
        return '${dt.month}/${dt.day}';
      }
      case TimePeriod.thirtyDays: {
        // x = hours from 30d ago → show every 5 days (every 120h)
        if (value % 120 > 4) return '';
        final dt = now.subtract(Duration(hours: (720 - value).round()));
        return '${dt.month}/${dt.day}';
      }
    }
  }

  String _getTooltipX(double value) {
    // Look up actual timestamp by nearest integer x
    final xInt = value.round();
    final ts = _timestampMap[xInt];
    if (ts != null) {
      final h = ts.hour.toString().padLeft(2, '0');
      final m = ts.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }
    // Fallback: reconstruct approximate time
    final now = DateTime.now();
    switch (_selectedPeriod) {
      case TimePeriod.oneHour: {
        final dt = now.subtract(Duration(minutes: (60 - value).round()));
        return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
      case TimePeriod.twentyFourHours: {
        final dt = now.subtract(Duration(minutes: (1440 - value).round()));
        return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
      case TimePeriod.sevenDays: {
        final dt = now.subtract(Duration(hours: (168 - value).round()));
        return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:00';
      }
      case TimePeriod.thirtyDays: {
        final dt = now.subtract(Duration(hours: (720 - value).round()));
        return '${dt.month}/${dt.day}';
      }
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
                  _buildPeriodBtn('1H', TimePeriod.oneHour),
                  const SizedBox(width: 6),
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
          Builder(builder: (_) {
            // 1H → use live rolling WebSocket buffer (real-time waveform, no cutoff lag)
            // 24H/7D/30D → use Firestore history stream
            final List<FlSpot> spots;
            if (_selectedPeriod == TimePeriod.oneHour) {
              final livePoints = ref.watch(liveChartPointsProvider);
              _dataError = null;
              spots = _buildLiveSpots(livePoints);
            } else {
              final historyAsync = ref.watch(
                readingHistoryProvider((_deviceId, _periodHours, _refreshTick)),
              );
              if (historyAsync.isLoading) {
                return const SizedBox(
                  height: 200,
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }
              spots = _buildSpots(historyAsync);
            }
            if (_dataError != null) {
              return SizedBox(
                height: 200,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          size: 36, color: Color(0xFFEF9A9A)),
                      const SizedBox(height: 8),
                      const Text(
                        'Could not load data',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFFB0BEC5),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _dataError!,
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 10,
                          color: Color(0xFFCFD8DC),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
            if (!_hasLiveData) {
              return SizedBox(
                height: 200,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.show_chart_rounded,
                          size: 40, color: const Color(0xFFCFD8DC)),
                      const SizedBox(height: 12),
                      Text(
                        _selectedPeriod == TimePeriod.oneHour
                            ? 'Waiting for live data...'
                            : 'No historical data yet',
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF90A4AE),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _selectedPeriod == TimePeriod.oneHour
                            ? 'Chart updates every 5 seconds from live sensor'
                            : 'Data will appear as readings accumulate',
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          color: Color(0xFFB0BEC5),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onScaleStart: (details) {
                _scaleStartZoom = _xZoom;
                _scaleStartOffset = _xPanOffset;
                if (details.pointerCount >= 2) {
                  setState(() => _isZooming = true);
                }
              },
              onScaleEnd: (_) {
                if (_isZooming) setState(() => _isZooming = false);
              },
              onScaleUpdate: (details) {
                setState(() {
                  if (details.pointerCount >= 2) {
                    _isZooming = true;
                    // Pinch zoom: scale X axis only
                    final newZoom = (_scaleStartZoom * details.horizontalScale).clamp(1.0, 10.0);
                    // Keep the view centered when zooming
                    final oldWindow = _effectiveMaxX / _xZoom;
                    final newWindow = _effectiveMaxX / newZoom;
                    final chartWidth = 300.0;
                    final focalRatio = details.localFocalPoint.dx / chartWidth;
                    _xZoom = newZoom;
                    _xPanOffset = (_xPanOffset + focalRatio * (oldWindow - newWindow))
                        .clamp(0.0, (_effectiveMaxX - newWindow).clamp(0.0, double.infinity));
                  } else {
                    // Single-finger pan
                    final window = _effectiveMaxX / _xZoom;
                    final panDelta = -details.focalPointDelta.dx * (window / 300.0);
                    _xPanOffset = (_xPanOffset + panDelta)
                        .clamp(0.0, (_effectiveMaxX - window).clamp(0.0, double.infinity));
                  }
                });
              },
              onDoubleTap: () => setState(() {
                _xZoom = 1.0;
                _xPanOffset = 0.0;
              }),
              child: SizedBox(
                height: 200,
                child: ClipRect(
                  child: LineChart(
                    _buildChartData(spots),
                    duration: const Duration(milliseconds: 300),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildPeriodBtn(String label, TimePeriod period) {
    final isSelected = _selectedPeriod == period;
    return GestureDetector(
      onTap: () => setState(() {
        _selectedPeriod = period;
        _xZoom = 1.0;
        _xPanOffset = 0.0;
      }),
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

  /// Split spots into contiguous segments, breaking where consecutive points
  /// are more than [gapThreshold] X-units apart (e.g., minutes for 1H/24H).
  /// This prevents the chart from drawing a line through periods of no data.
  List<List<FlSpot>> _splitIntoSegments(List<FlSpot> spots) {
    if (spots.isEmpty) return [];
    // Gap threshold in X units:
    //  1H view  → minutes, threshold = 2 min (readings every ~5s, 2 min = big gap)
    // 24H view  → minutes, threshold = 30 min
    //  7D view  → hours,   threshold = 2 h
    // 30D view  → hours,   threshold = 6 h
    final double gapThreshold;
    switch (_selectedPeriod) {
      case TimePeriod.oneHour: gapThreshold = 2.0; break;
      case TimePeriod.twentyFourHours: gapThreshold = 30.0; break;
      case TimePeriod.sevenDays: gapThreshold = 2.0; break;
      case TimePeriod.thirtyDays: gapThreshold = 6.0; break;
    }

    final segments = <List<FlSpot>>[];
    var current = <FlSpot>[spots.first];
    for (int i = 1; i < spots.length; i++) {
      final gap = spots[i].x - spots[i - 1].x;
      if (gap > gapThreshold) {
        if (current.isNotEmpty) segments.add(current);
        current = [];
      }
      current.add(spots[i]);
    }
    if (current.isNotEmpty) segments.add(current);
    return segments;
  }

  LineChartData _buildChartData(List<FlSpot> spots) {
    // For 1H live view: always show the full 60-min window so the waveform
    // grows from left to right and the right edge stays at "now".
    // For history views: shrink to fit the actual data range.
    final effectiveMaxX = _selectedPeriod == TimePeriod.oneHour
        ? _maxX
        : (spots.isNotEmpty
            ? (spots.last.x).ceilToDouble().clamp(spots.last.x, _maxX)
            : _maxX);
    _effectiveMaxX = effectiveMaxX; // save for gesture handler

    // Dynamic Y range based on actual data
    final yRange = _computeYRange(spots);
    final yMin = yRange.min;
    final yMax = yRange.max;
    final yInterval = yRange.interval;

    // X-axis zoom/pan: compute the visible window
    final windowSize = effectiveMaxX / _xZoom;
    final visMinX = _xPanOffset.clamp(0.0, (effectiveMaxX - windowSize).clamp(0.0, double.infinity));
    final visMaxX = (visMinX + windowSize).clamp(visMinX, effectiveMaxX);

    final segments = _splitIntoSegments(spots);

    return LineChartData(
      lineBarsData: segments.map((segSpots) => LineChartBarData(
          spots: segSpots,
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
        )).toList(),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 36,
            interval: yInterval,
            getTitlesWidget: (value, meta) {
              if (value < yMin || value > yMax) return const SizedBox.shrink();
              return Text(
                _formatY(value),
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 9, fontFamily: 'Inter'),
              );
            },
          ),
        ),
        bottomTitles: AxisTitles(
          axisNameWidget: Text(
            (_selectedPeriod == TimePeriod.thirtyDays || _selectedPeriod == TimePeriod.sevenDays)
                ? 'Date'
                : 'Time of Day',
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontFamily: 'Inter'),
          ),
          axisNameSize: 18,
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 38,
          interval: _selectedPeriod == TimePeriod.oneHour
              ? 15  // every 15 min
              : _selectedPeriod == TimePeriod.twentyFourHours
                  ? 240   // every 4h (240min)
                  : 24,   // every day (24h)
            getTitlesWidget: (value, meta) {
              final label = _getBottomLabel(value);
              if (label.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  label,
                  style: const TextStyle(color: Color(0xFF64748B), fontSize: 9, fontFamily: 'Inter'),
                ),
              );
            },
          ),
        ),
      ),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: yInterval,
        getDrawingHorizontalLine: (value) => const FlLine(color: Color(0xFFE8F0F7), strokeWidth: 1),
      ),
      borderData: FlBorderData(show: false),
      clipData: const FlClipData.all(),
      minX: visMinX,
      maxX: visMaxX,
      minY: yMin,
      maxY: yMax,
      lineTouchData: LineTouchData(
        enabled: !_isZooming,  // disable touch during pinch so gesture detector can work
        touchTooltipData: LineTouchTooltipData(
          tooltipBgColor: Colors.white,
          tooltipBorder: const BorderSide(color: Color(0xFFE2E8F0)),
          tooltipRoundedRadius: 8.0,
          fitInsideHorizontally: true,
          fitInsideVertically: true,
          getTooltipItems: (touchedSpots) {
            final String unit;
            switch (widget.label) {
              case 'pH': unit = ''; break;
              case 'TDS': unit = ' ppm'; break;
              default: unit = ' NTU'; // Turbidity
            }
            return touchedSpots.map((spot) {
              return LineTooltipItem(
                '${_getTooltipX(spot.x)}\n${spot.y.toStringAsFixed(2)}$unit',
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
