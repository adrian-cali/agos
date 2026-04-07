import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:async';
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

  // Pump card local state
  Timer? _pumpCountdownTimer;
  int _pumpRemainingSeconds = 0;
  bool _pumpManualOn = false;
  int _selectedPumpDuration = 10; // default 10 minutes

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

      // Restore pump UI state after navigation back (pumpStateProvider persists)
      final pumpState = ref.read(pumpStateProvider);
      if (pumpState.isManual && pumpState.isOn && mounted) {
        setState(() {
          _pumpManualOn = true;
          _pumpRemainingSeconds = pumpState.remainingSeconds;
        });
        if (pumpState.remainingSeconds > 0 &&
            (_pumpCountdownTimer == null || !_pumpCountdownTimer!.isActive)) {
          _pumpCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
            if (!mounted) { timer.cancel(); return; }
            setState(() {
              if (_pumpRemainingSeconds > 0) {
                _pumpRemainingSeconds--;
              } else {
                _stopPump(expired: true);
                timer.cancel();
              }
            });
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _waveController.dispose();
    _pageController.dispose();
    _pumpCountdownTimer?.cancel();
    super.dispose();
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning,';
    if (hour < 17) return 'Good Afternoon,';
    return 'Good Evening,';
  }

  bool _isGuestReadOnly() => ref.read(isGuestDemoProvider);

  bool _blockIfGuestReadOnly() {
    if (!_isGuestReadOnly()) return false;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Guest demo account is view-only.'),
        ),
      );
    }
    return true;
  }

  String _formatCardDate(DateTime date) {
    const months = <String>[
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[date.month - 1]} ${date.day.toString().padLeft(2, '0')}, ${date.year}';
  }


  /// Wraps [child] with a staggered slide-up + fade-in animation.
  /// [index] (0, 1, 2, …) determines the start offset of the interval.
  Widget _buildAnimated(int index, Widget child) {
    const total = 6; // number of animated sections
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
    // Use the real device ID from Firestore; fall back to simulator ID during dev
    final deviceIdAsync = ref.watch(linkedDeviceIdProvider);
    final deviceId = deviceIdAsync.valueOrNull ?? '';
    final latestAsync = ref.watch(latestReadingProvider(deviceId));
    final latest = latestAsync.valueOrNull;
    // User threshold settings for dynamic status
    final thresholds = ref.watch(userThresholdsProvider).valueOrNull
        ?? const UserThresholds();
    // Connection state
    final isLive = ref.watch(wsConnectedProvider);
    final lastData = ref.watch(wsLastDataProvider);

    // Keep local pump UI in sync with backend state (handles timer expiry,
    // auto-pump changes, and state restoration after navigation).
    ref.listen<PumpState>(pumpStateProvider, (_, next) {
      if (!mounted) return;
      if (next.isManual && next.isOn) {
        // Backend confirmed manual pump — sync remaining time
        final drift = (_pumpRemainingSeconds - next.remainingSeconds).abs();
        if (!_pumpManualOn || drift > 2) {
          setState(() {
            _pumpManualOn = true;
            _pumpRemainingSeconds = next.remainingSeconds;
          });
        }
      } else if (!next.isOn && _pumpManualOn) {
        // Backend turned pump off (timer expired or auto-off)
        _pumpCountdownTimer?.cancel();
        setState(() {
          _pumpManualOn = false;
          _pumpRemainingSeconds = 0;
        });
      }
    });

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
                    _buildAnimated(0, _buildSavingsCard(effectiveTank)),
                    const SizedBox(height: 25),
                    // Main Water Tank card
                    _buildAnimated(1, _buildWaterTankCard(effectiveTank, thresholds, isLive: isLive, lastData: lastData)),
                    const SizedBox(height: 25),
                    // Pump Control card
                    _buildAnimated(2, _buildPumpCard()),
                    const SizedBox(height: 25),
                    // UV Steriliser card (temporarily hidden)
                    // _buildAnimated(3, _buildUvCard()),
                    // const SizedBox(height: 25),
                    // Bypass Schedule card
                    _buildAnimated(4, _buildBypassCard()),
                    const SizedBox(height: 25),
                    // AGOS logo at bottom
                    _buildAnimated(5, _buildBottomLogo()),
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
          Flexible(
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _greeting(),
                style: const TextStyle(
                  color: Color(0xFF90A5B4),
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
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF141A1E),
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Poppins',
                    ),
                  );
                },
              ),
            ],
          ),
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
                      color: const Color(0xFF1BA9E1).withOpacity(0.15),
                      blurRadius: 25,
                      offset: const Offset(0, 8),
                      spreadRadius: 2,
                    ),
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
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
        ],
      ),
    );
  }

  Widget _buildSavingsCard(TankData tankData) {
    final now = DateTime.now();
    final dateLabel = _formatCardDate(now);
    final savedPercent = tankData.capacity > 0
        ? ((tankData.volume / tankData.capacity) * 100).clamp(0.0, 100.0)
        : 0.0;
    final savedLiters = tankData.volume;

    return Container(
      height: 160,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF5DADE2).withOpacity(0.15),
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
                  size: const Size(double.infinity, 160),
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
                    child: SizedBox(
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
                                dateLabel,
                                style: TextStyle(
                                  color: Color(0xFF90A5B4),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w400,
                                  fontFamily: 'Poppins',
                                  letterSpacing: -0.12,
                                  height: 0.83, // 10px line height / 12px font size
                                ),
                              ),
                              SizedBox(height: 6),
                              Text(
                                'You Saved',
                                style: TextStyle(
                                  color: Color(0xFF1C5B8D),
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
                                '${savedPercent.round()}%',
                                style: TextStyle(
                                  color: Color(0xFF1C5B8D),
                                  fontSize: 47,
                                  fontWeight: FontWeight.w500,
                                  fontFamily: 'Poppins',
                                  letterSpacing: -1.41,
                                  height: 1, // leading-none
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                '${savedLiters.toStringAsFixed(1)} liters',
                                style: TextStyle(
                                  color: Color(0xFF384144),
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
                  SizedBox(
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

  Widget _buildWaterTankCard(TankData tankData, UserThresholds thresholds,
      {bool isLive = false, DateTime? lastData}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF5DADE2).withOpacity(0.15),
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
                      const Color(0xFF00B8DB).withOpacity(0.2),
                      const Color(0xFF2B7FFF).withOpacity(0.2),
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
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Main Water Tank',
                      style: TextStyle(
                        color: Color(0xFF2C3E50),
                        fontSize: 18,
                        fontWeight: FontWeight.w400,
                        fontFamily: 'Poppins',
                      ),
                    ),
                    Text(
                      'Real-time monitoring',
                      style: TextStyle(
                        color: Color(0xFF7F8C8D),
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
                    color: isLive ? const Color(0xFF009966) : const Color(0xFF9E9E9E),
                    width: 0.8,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: (isLive ? const Color(0xFF009966) : const Color(0xFF9E9E9E))
                          .withOpacity(0.32),
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
                        color: isLive ? const Color(0xFF009966) : const Color(0xFF9E9E9E),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isLive ? const Color(0xFF009966) : const Color(0xFF9E9E9E),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (isLive ? const Color(0xFF009966) : const Color(0xFF9E9E9E))
                                .withOpacity(0.4),
                            blurRadius: 6,
                            offset: const Offset(0, 0),
                          ),
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 2,
                            offset: const Offset(1, 1),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isLive ? 'Live' : 'Idle',
                      style: TextStyle(
                        color: isLive ? const Color(0xFF009966) : const Color(0xFF9E9E9E),
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
                child: _buildTankData(tankData, thresholds),
              ),
            ],
          ),
          // Divider
          // Container(
          //   margin: const EdgeInsets.only(top: 16, bottom: 16),
          //   height: 0.8,
          //   decoration: BoxDecoration(
          //     gradient: LinearGradient(
          //       begin: Alignment.centerLeft,
          //       end: Alignment.centerRight,
          //       colors: [
          //         Colors.transparent,
          //         const Color(0xFF00B8DB).withOpacity(0.3),
          //         Colors.transparent,
          //       ],
          //     ),
          //   ),
          // ),
          // Flow rate (temporarily hidden)
          // Row(
          //   mainAxisAlignment: MainAxisAlignment.spaceBetween,
          //   children: [
          //     const Text(
          //       'Flow Rate',
          //       style: TextStyle(
          //         color: Color(0xFF7F8C8D),
          //         fontSize: 14,
          //         fontWeight: FontWeight.w400,
          //         fontFamily: 'Inter',
          //       ),
          //     ),
          //     Row(
          //       children: [
          //         // Flow indicator bars
          //         Row(
          //           children: List.generate(3, (index) {
          //             return Container(
          //               margin: EdgeInsets.only(left: index > 0 ? 4 : 0),
          //               width: index == 2 ? 8 : 4,
          //               height: 12,
          //               decoration: BoxDecoration(
          //                 color: const Color(0xFF00D3F3),
          //                 borderRadius: BorderRadius.circular(10),
          //               ),
          //             );
          //           }),
          //         ),
          //         const SizedBox(width: 8),
          //         Text(
          //           '${tankData.flowRate.toStringAsFixed(1)} L/min',
          //           style: const TextStyle(
          //             color: Color(0xFF00D3F2),
          //             fontSize: 14,
          //             fontWeight: FontWeight.w400,
          //             fontFamily: 'Inter',
          //           ),
          //         ),
          //       ],
          //     ),
          //   ],
          // ),
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
          color: const Color(0xFF00B8DB).withOpacity(0.4),
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
                      color: const Color(0xFF06B6D4).withOpacity(0.6),
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
                  color: const Color(0xFF00B8DB).withOpacity(0.1),
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
              color: Colors.white.withOpacity(0.4),
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
            color: const Color(0xFF00B8DB).withOpacity(0.2),
            width: 0.8,
          ),
        ),
      ),
      child: Text(
        level,
        style: TextStyle(
          color: const Color(0xFF00D3F2).withOpacity(0.6),
          fontSize: 12,
          fontWeight: FontWeight.w400,
          fontFamily: 'Inter',
        ),
      ),
    );
  }

  Widget _buildTankData(TankData tankData, UserThresholds thresholds) {
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
            const Text(
              'Current Level',
              style: TextStyle(
                color: Color(0xFF7F8C8D),
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
                const Color(0xFF00B8DB).withOpacity(0.3),
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
          if (tankData.level >= thresholds.levelHigh) {
            statusColor = const Color(0xFF00C851);
            dotColor = const Color(0xFF00C851);
            statusLabel = 'Optimal Level';
          } else if (tankData.level > thresholds.levelMin) {
            statusColor = const Color(0xFFFDC700);
            dotColor = const Color(0xFFFDC700);
            statusLabel = 'Moderate Level';
          } else {
            statusColor = const Color(0xFFFF6B6B);
            dotColor = const Color(0xFFFF6B6B);
            statusLabel = 'Low Level';
          }
          return FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                border: Border.all(
                  color: statusColor.withOpacity(0.3),
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
          style: const TextStyle(
            color: Color(0xFF7F8C8D),
            fontSize: 14,
            fontWeight: FontWeight.w400,
            fontFamily: 'Poppins',
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Color(0xFF00D3F2),
            fontSize: 14,
            fontWeight: FontWeight.w400,
            fontFamily: 'Poppins',
          ),
        ),
      ],
    );
  }

  // ─── Pump Control Card ───────────────────────────────────────────────────

  void _startPumpTimer(int durationSeconds) {
    if (_blockIfGuestReadOnly()) return;
    _pumpCountdownTimer?.cancel();
    setState(() {
      _pumpManualOn = true;
      _pumpRemainingSeconds = durationSeconds;
    });
    _pumpCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_pumpRemainingSeconds > 0) {
          _pumpRemainingSeconds--;
        } else {
          // Timer expired → send off command and reset to auto mode
          _stopPump(expired: true);
          timer.cancel();
        }
      });
    });

    // Send pump ON command with duration
    try {
      ref.read(webSocketServiceProvider).sendPumpCommand(
        on: true,
        durationSeconds: durationSeconds,
      );
    } catch (_) {}
  }

  void _stopPump({bool expired = false}) {
    if (!expired && _blockIfGuestReadOnly()) return;
    _pumpCountdownTimer?.cancel();
    if (mounted) {
      setState(() {
        _pumpManualOn = false;
        _pumpRemainingSeconds = 0;
      });
    }
    // Send pump OFF command
    try {
      ref.read(webSocketServiceProvider).sendPumpCommand(on: false);
    } catch (_) {}
  }

  String _formatCountdown(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Widget _buildPumpCard() {
    final durations = [5, 10, 15, 30]; // minutes

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF5DADE2).withOpacity(0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF00B8DB).withOpacity(0.2),
                      const Color(0xFF2B7FFF).withOpacity(0.2),
                    ],
                  ),
                ),
                child: const Icon(
                  Icons.water_outlined,
                  color: Color(0xFF00D3F2),
                  size: 20,
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pump Control',
                      style: TextStyle(
                        color: Color(0xFF2C3E50),
                        fontSize: 18,
                        fontWeight: FontWeight.w400,
                        fontFamily: 'Poppins',
                      ),
                    ),
                    Text(
                      'Manual pump operation',
                      style: TextStyle(
                        color: Color(0xFF7F8C8D),
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        fontFamily: 'Poppins',
                      ),
                    ),
                  ],
                ),
              ),
              // Status badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(
                    color: _pumpManualOn
                        ? const Color(0xFF00B8DB)
                        : const Color(0xFF7F8C8D),
                    width: 0.8,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: _pumpManualOn
                      ? [
                          BoxShadow(
                            color: const Color(0xFF00B8DB).withOpacity(0.32),
                            blurRadius: 11,
                            offset: const Offset(0, 0),
                          ),
                        ]
                      : [],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _pumpManualOn
                            ? const Color(0xFF00B8DB)
                            : const Color(0xFF7F8C8D),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _pumpManualOn ? 'Manual' : 'Auto',
                      style: TextStyle(
                        color: _pumpManualOn
                            ? const Color(0xFF00B8DB)
                            : const Color(0xFF7F8C8D),
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

          // ── Divider ─────────────────────────────────────────────
          Container(
            margin: const EdgeInsets.only(top: 16, bottom: 16),
            height: 0.8,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Colors.transparent,
                  const Color(0xFF00B8DB).withOpacity(0.3),
                  Colors.transparent,
                ],
              ),
            ),
          ),

          // ── Status / Countdown area ──────────────────────────────
          if (_pumpManualOn) ...[
            Center(
              child: Column(
                children: [
                  const Text(
                    'Pump Running',
                    style: TextStyle(
                      color: Color(0xFF00B8DB),
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      fontFamily: 'Poppins',
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Countdown ring
                  SizedBox(
                    width: 90,
                    height: 90,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Arc that drains as time passes
                        TweenAnimationBuilder<double>(
                          tween: Tween(
                            begin: 1.0,
                            end: _selectedPumpDuration * 60 > 0
                                ? _pumpRemainingSeconds /
                                    (_selectedPumpDuration * 60)
                                : 0.0,
                          ),
                          duration: const Duration(seconds: 1),
                          builder: (context, value, _) {
                            return CustomPaint(
                              size: const Size(90, 90),
                              painter: _ArcPainter(value),
                            );
                          },
                        ),
                        Text(
                          _formatCountdown(_pumpRemainingSeconds),
                          style: const TextStyle(
                            color: Color(0xFF2C3E50),
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Inter',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Time remaining',
                    style: TextStyle(
                      color: Color(0xFF7F8C8D),
                      fontSize: 12,
                      fontFamily: 'Inter',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ] else ...[
            // ── Duration selector ──────────────────────────────────
            const Text(
              'Duration',
              style: TextStyle(
                color: Color(0xFF7F8C8D),
                fontSize: 13,
                fontWeight: FontWeight.w400,
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: durations.map((mins) {
                final selected = _selectedPumpDuration == mins;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedPumpDuration = mins),
                    child: Container(
                      margin: EdgeInsets.only(
                        right: mins != durations.last ? 8 : 0,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFF00B8DB).withOpacity(0.1)
                            : Colors.transparent,
                        border: Border.all(
                          color: selected
                              ? const Color(0xFF00B8DB)
                              : const Color(0xFFDDE3E9),
                          width: selected ? 1.5 : 1,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(
                          '${mins}m',
                          style: TextStyle(
                            color: selected
                                ? const Color(0xFF00B8DB)
                                : const Color(0xFF7F8C8D),
                            fontSize: 14,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.w400,
                            fontFamily: 'Inter',
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],

          // ── Action button ────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: GestureDetector(
              onTap: () {
                if (_pumpManualOn) {
                  _stopPump();
                } else {
                  _startPumpTimer(_selectedPumpDuration * 60);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  gradient: _pumpManualOn
                      ? null
                      : const LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [Color(0xFF00B8DB), Color(0xFF2B7FFF)],
                        ),
                  color: _pumpManualOn ? const Color(0xFFFFEEEE) : null,
                  border: _pumpManualOn
                      ? Border.all(
                          color: const Color(0xFFFF6B6B).withOpacity(0.5),
                          width: 1,
                        )
                      : null,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: _pumpManualOn
                      ? []
                      : [
                          BoxShadow(
                            color: const Color(0xFF00B8DB).withOpacity(0.4),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                ),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _pumpManualOn
                            ? Icons.stop_circle_outlined
                            : Icons.play_circle_outline,
                        color: _pumpManualOn
                            ? const Color(0xFFFF6B6B)
                            : Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _pumpManualOn ? 'Stop Pump' : 'Turn On Pump',
                        style: TextStyle(
                          color: _pumpManualOn
                              ? const Color(0xFFFF6B6B)
                              : Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Poppins',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Info note ────────────────────────────────────────────
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 14,
                color: const Color(0xFF7F8C8D).withOpacity(0.7),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _pumpManualOn
                      ? 'Pump will return to auto mode when timer ends.'
                      : 'Pump runs automatically based on sensor data. Use manual mode to clean the holding tank.',
                  style: TextStyle(
                    color: const Color(0xFF7F8C8D).withOpacity(0.8),
                    fontSize: 11,
                    fontFamily: 'Inter',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── UV Steriliser Card ──────────────────────────────────────────────────

  Widget _buildUvCard() {
    final uvState = ref.watch(uvStateProvider);
    final bool uvOn = uvState.isOn;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF5DADE2).withOpacity(0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF00B8DB).withOpacity(0.2),
                      const Color(0xFF2B7FFF).withOpacity(0.2),
                    ],
                  ),
                ),
                child: const Icon(
                  Icons.wb_sunny_outlined,
                  color: Color(0xFF00D3F2),
                  size: 20,
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'UV Steriliser',
                      style: TextStyle(
                        color: Color(0xFF2C3E50),
                        fontSize: 18,
                        fontWeight: FontWeight.w400,
                        fontFamily: 'Poppins',
                      ),
                    ),
                    Text(
                      'UV-C lamp in holding tank',
                      style: TextStyle(
                        color: Color(0xFF7F8C8D),
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        fontFamily: 'Poppins',
                      ),
                    ),
                  ],
                ),
              ),
              // Toggle switch
              Transform.scale(
                scale: 0.9,
                child: Switch(
                  value: uvOn,
                  thumbColor: WidgetStateProperty.resolveWith<Color?>((states) {
                    if (states.contains(WidgetState.selected)) {
                      return const Color(0xFF00B8DB);
                    }
                    return const Color(0xFF7F8C8D);
                  }),
                  activeTrackColor: const Color(0xFF00B8DB).withOpacity(0.35),
                  inactiveTrackColor: const Color(0xFFDDE3E9),
                  onChanged: (val) {
                    ref.read(webSocketServiceProvider).sendUvCommand(on: val);
                    ref.read(uvStateProvider.notifier).setOn(val);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Status row
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: uvOn ? const Color(0xFF00B8DB) : const Color(0xFF7F8C8D),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  uvOn
                      ? 'UV sterilisation active — water in holding tank is being treated'
                      : 'UV lamp is OFF — tap toggle to enable sterilisation',
                  style: TextStyle(
                    color: const Color(0xFF7F8C8D).withOpacity(0.85),
                    fontSize: 11,
                    fontFamily: 'Inter',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Bypass Schedule Card ────────────────────────────────────────────────

  Widget _buildBypassCard() {
    final bypassState = ref.watch(bypassStateProvider);
    final sched = bypassState.schedule;
    final bool pumpOn = bypassState.isPumpOn;
    final bool isPaused = bypassState.isPaused;
    final String? lastRun = bypassState.lastRun;

    String nextRunLabel() {
      final h = sched.hour.toString().padLeft(2, '0');
      final m = sched.minute.toString().padLeft(2, '0');
      return '$h:$m daily  (${sched.durationMinutes} min)';
    }

    String lastRunLabel() {
      if (lastRun == null) return 'Never';
      try {
        final dt = DateTime.parse(lastRun);
        return '${dt.month}/${dt.day} '
            '${dt.hour.toString().padLeft(2, '0')}:'
            '${dt.minute.toString().padLeft(2, '0')}';
      } catch (_) {
        return 'Unknown';
      }
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF5DADE2).withOpacity(0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF00B8DB).withOpacity(0.2),
                      const Color(0xFF2B7FFF).withOpacity(0.2),
                    ],
                  ),
                ),
                child: const Icon(
                  Icons.schedule_outlined,
                  color: Color(0xFF00D3F2),
                  size: 20,
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bypass Schedule',
                      style: TextStyle(
                        color: Color(0xFF2C3E50),
                        fontSize: 18,
                        fontWeight: FontWeight.w400,
                        fontFamily: 'Poppins',
                      ),
                    ),
                    Text(
                      'Waste tank → Filter direct',
                      style: TextStyle(
                        color: Color(0xFF7F8C8D),
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        fontFamily: 'Poppins',
                      ),
                    ),
                  ],
                ),
              ),
              // Status badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(
                    color: pumpOn ? const Color(0xFF00B8DB) : const Color(0xFF7F8C8D),
                    width: 0.8,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: pumpOn
                      ? [
                          BoxShadow(
                            color: const Color(0xFF00B8DB).withOpacity(0.3),
                            blurRadius: 10,
                          )
                        ]
                      : [],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: pumpOn ? const Color(0xFF00B8DB) : const Color(0xFF7F8C8D),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      pumpOn ? 'Running' : 'Idle',
                      style: TextStyle(
                        color: pumpOn ? const Color(0xFF00B8DB) : const Color(0xFF7F8C8D),
                        fontSize: 11,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Divider
          Container(
            margin: const EdgeInsets.only(top: 14, bottom: 14),
            height: 0.8,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Colors.transparent,
                  const Color(0xFF00B8DB).withOpacity(0.3),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          // Schedule info row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildBypassInfoTile('Next Run', nextRunLabel()),
              _buildBypassInfoTile('Last Run', lastRunLabel()),
            ],
          ),
          const SizedBox(height: 14),
          // ── Action buttons (changes based on pump state) ──────────────────
          if (!pumpOn && !isPaused) ...
            // Idle: Edit Schedule + Run Now
            [
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        _showBypassScheduleDialog(sched);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        decoration: BoxDecoration(
                          border: Border.all(
                              color: const Color(0xFF00B8DB).withOpacity(0.5)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Center(
                          child: Text(
                            'Edit Schedule',
                            style: TextStyle(
                              color: Color(0xFF00B8DB),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              fontFamily: 'Poppins',
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        if (_blockIfGuestReadOnly()) return;
                        final durSec = sched.durationMinutes * 60;
                        ref.read(webSocketServiceProvider).sendBypassCommand(
                            on: true, durationSeconds: durSec);
                        ref.read(bypassStateProvider.notifier).startRun(durSec);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                              colors: [Color(0xFF00B8DB), Color(0xFF2B7FFF)]),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  const Color(0xFF00B8DB).withOpacity(0.4),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Text(
                            'Run Now',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'Poppins',
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ]
          else if (pumpOn && !isPaused) ...
            // Running: Pause + Stop
            [
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        if (_blockIfGuestReadOnly()) return;
                        ref.read(webSocketServiceProvider)
                            .sendBypassCommand(on: false);
                        ref.read(bypassStateProvider.notifier).pauseRun();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        decoration: BoxDecoration(
                          border: Border.all(
                              color: const Color(0xFF00B8DB).withOpacity(0.7)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.pause_rounded,
                                  size: 15, color: Color(0xFF00B8DB)),
                              SizedBox(width: 4),
                              Text(
                                'Pause',
                                style: TextStyle(
                                  color: Color(0xFF00B8DB),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  fontFamily: 'Poppins',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        if (_blockIfGuestReadOnly()) return;
                        ref.read(webSocketServiceProvider)
                            .sendBypassCommand(on: false);
                        ref.read(bypassStateProvider.notifier).stopRun();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        decoration: BoxDecoration(
                          border: Border.all(
                              color: const Color(0xFFE53935).withOpacity(0.7)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.stop_rounded,
                                  size: 15, color: Color(0xFFE53935)),
                              SizedBox(width: 4),
                              Text(
                                'Stop',
                                style: TextStyle(
                                  color: Color(0xFFE53935),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  fontFamily: 'Poppins',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ]
          else ...
            // Paused: Resume + Stop
            [
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        if (_blockIfGuestReadOnly()) return;
                        final remaining = bypassState.pausedRemainingSeconds ??
                            sched.durationMinutes * 60;
                        ref.read(webSocketServiceProvider).sendBypassCommand(
                            on: true, durationSeconds: remaining);
                        ref.read(bypassStateProvider.notifier).resumeRun();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                              colors: [Color(0xFF00B8DB), Color(0xFF2B7FFF)]),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  const Color(0xFF00B8DB).withOpacity(0.4),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.play_arrow_rounded,
                                  size: 16, color: Colors.white),
                              SizedBox(width: 4),
                              Text(
                                'Resume',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'Poppins',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        if (_blockIfGuestReadOnly()) return;
                        ref.read(bypassStateProvider.notifier).stopRun();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        decoration: BoxDecoration(
                          border: Border.all(
                              color: const Color(0xFFE53935).withOpacity(0.7)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.stop_rounded,
                                  size: 15, color: Color(0xFFE53935)),
                              SizedBox(width: 4),
                              Text(
                                'Stop',
                                style: TextStyle(
                                  color: Color(0xFFE53935),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  fontFamily: 'Poppins',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.info_outline, size: 13,
                  color: const Color(0xFF7F8C8D).withOpacity(0.7)),
              const SizedBox(width: 5),
              const Expanded(
                child: Text(
                  'Moves water from waste tank directly to filter, skipping the equalizer.',
                  style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 10, fontFamily: 'Inter'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBypassInfoTile(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(color: Color(0xFF9E9E9E), fontSize: 11, fontFamily: 'Inter')),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(
                color: Color(0xFF2C3E50),
                fontSize: 13,
                fontWeight: FontWeight.w500,
                fontFamily: 'Inter')),
      ],
    );
  }

  void _showBypassScheduleDialog(BypassSchedule current) {
    int hour     = current.hour;
    int minute   = current.minute;
    int duration = current.durationMinutes;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDlgState) {
            return AlertDialog(
              title: const Text('Bypass Schedule',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 17)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Trigger time',
                      style: TextStyle(color: Color(0xFF7F8C8D), fontSize: 13)),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: ctx,
                        initialTime: TimeOfDay(hour: hour, minute: minute),
                      );
                      if (picked != null) {
                        setDlgState(() {
                          hour   = picked.hour;
                          minute = picked.minute;
                        });
                      }
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: const Color(0xFF00B8DB).withOpacity(0.5)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${hour.toString().padLeft(2, '0')}:'
                        '${minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Inter',
                          color: Color(0xFF2C3E50),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Duration (minutes)',
                      style: TextStyle(color: Color(0xFF7F8C8D), fontSize: 13)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [15, 30, 60, 90].map((d) {
                      final sel = duration == d;
                      return GestureDetector(
                        onTap: () => setDlgState(() => duration = d),
                        child: Container(
                          width: 56,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: sel
                                ? const Color(0xFF00B8DB).withOpacity(0.1)
                                : Colors.transparent,
                            border: Border.all(
                              color: sel
                                  ? const Color(0xFF00B8DB)
                                  : const Color(0xFFDDE3E9),
                              width: sel ? 1.5 : 1,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              '${d}m',
                              style: TextStyle(
                                color: sel
                                  ? const Color(0xFF00B8DB)
                                    : const Color(0xFF7F8C8D),
                                fontSize: 13,
                                fontWeight:
                                    sel ? FontWeight.w600 : FontWeight.w400,
                                fontFamily: 'Inter',
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel',
                      style: TextStyle(color: Color(0xFF7F8C8D))),
                ),
                TextButton(
                  onPressed: () {
                    if (_blockIfGuestReadOnly()) return;
                    ref.read(webSocketServiceProvider).sendBypassSchedule(
                          hour: hour,
                          minute: minute,
                          durationMinutes: duration,
                        );
                    ref.read(bypassStateProvider.notifier).updateSchedule(
                          BypassSchedule(
                              hour: hour,
                              minute: minute,
                              durationMinutes: duration),
                        );
                    Navigator.of(ctx).pop();
                  },
                  child: const Text('Save',
                      style: TextStyle(color: Color(0xFF00B8DB))),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildBottomLogo() {
    return SizedBox(
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
      color: const Color(0xFF00D3F2).withOpacity(0.08),
    );

    // Wave 2 - front layer, more prominent
    _drawWave(
      canvas, size,
      baseY: size.height * 0.65,
      amplitudes: [15.0, 6.0],
      frequencies: [1.0, 2.0],
      phaseOffsets: [phase + 2.0, phase + 3.5],
      color: const Color(0xFF00D3F2).withOpacity(0.15),
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

// ── Pump Countdown Arc Painter ─────────────────────────────────────────────

class _ArcPainter extends CustomPainter {
  final double progress; // 1.0 = full, 0.0 = empty

  _ArcPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = (size.width < size.height ? size.width : size.height) / 2 - 6;

    // Background track
    final trackPaint = Paint()
      ..color = const Color(0xFF00B8DB).withOpacity(0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(Offset(cx, cy), radius, trackPaint);

    // Progress arc
    if (progress > 0) {
      final arcPaint = Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF00B8DB), Color(0xFF2B7FFF)],
        ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: radius))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: radius),
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        arcPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_ArcPainter old) => old.progress != progress;
}