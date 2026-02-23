import 'dart:ui';
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Notification modal – blurred dark overlay with dismissible notification cards
// ─────────────────────────────────────────────────────────────────────────────

void showNotificationModal(BuildContext context) {
  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss notifications',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (context, anim1, anim2) => Material(
      type: MaterialType.transparency,
      child: const _NotificationModal(),
    ),
    transitionBuilder: (context, anim1, anim2, child) {
      return FadeTransition(
        opacity: anim1,
        child: child,
      );
    },
  );
}

class _NotificationModal extends StatefulWidget {
  const _NotificationModal();

  @override
  State<_NotificationModal> createState() => _NotificationModalState();
}

class _NotificationData {
  final String id;
  final IconData icon;
  final Color iconBg;
  final String title;
  final String message;
  final String time;
  final bool showActions;
  bool dismissed = false;
  bool completed = false;

  _NotificationData({
    required this.id,
    required this.icon,
    required this.iconBg,
    required this.title,
    required this.message,
    required this.time,
    this.showActions = true,
  });
}

class _NotificationModalState extends State<_NotificationModal>
    with SingleTickerProviderStateMixin {
  late AnimationController _entryController;
  final ScrollController _scrollController = ScrollController();
  double _dragOffset = 0.0;

  final List<_NotificationData> _notifications = [
    _NotificationData(
      id: '1',
      icon: Icons.check_circle_outline,
      iconBg: const Color(0xFF00C49A),
      title: 'Water Quality Optimal',
      message: 'All water quality parameters are within acceptable ranges.',
      time: '5h ago',
    ),
    _NotificationData(
      id: '2',
      icon: Icons.notifications_outlined,
      iconBg: const Color(0xFF00B8DB),
      title: 'Scheduled Maintenance Due',
      message: 'Monthly filter cleaning is scheduled for tomorrow.',
      time: '2d ago',
    ),
    _NotificationData(
      id: '3',
      icon: Icons.error_outline,
      iconBg: const Color(0xFFFF5252),
      title: 'Low Water Level',
      message: 'Storage tank is at 18%. System is not yet operational',
      time: '1d ago',
      showActions: false,
    ),
    _NotificationData(
      id: '4',
      icon: Icons.opacity_outlined,
      iconBg: const Color(0xFF5DCCFC),
      title: 'High Turbidity Detected',
      message:
          'Turbidity level has risen to 8.5 NTU, exceeding the safe limit of 5 NTU. Consider filtering.',
      time: '3d ago',
    ),
    _NotificationData(
      id: '5',
      icon: Icons.science_outlined,
      iconBg: const Color(0xFFFFA726),
      title: 'pH Level Warning',
      message:
          'Water pH is at 8.9, slightly above the normal range (6.5–8.5). Monitor closely.',
      time: '3d ago',
    ),
    _NotificationData(
      id: '6',
      icon: Icons.water_drop_outlined,
      iconBg: const Color(0xFF00C49A),
      title: 'Tank Refilled Successfully',
      message:
          'Storage tank has been refilled to 95% capacity. System is fully operational.',
      time: '4d ago',
      showActions: false,
    ),
    _NotificationData(
      id: '7',
      icon: Icons.sensors_outlined,
      iconBg: const Color(0xFF9C27B0),
      title: 'Sensor Calibration Needed',
      message:
          'Turbidity sensor may need recalibration. Last calibration was 30 days ago.',
      time: '5d ago',
    ),
    _NotificationData(
      id: '8',
      icon: Icons.bolt_outlined,
      iconBg: const Color(0xFFFF5252),
      title: 'Power Interruption Detected',
      message:
          'ESP32 controller experienced a brief power interruption. Data may have been lost.',
      time: '6d ago',
      showActions: false,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    )..forward();
  }

  @override
  void dispose() {
    _entryController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Widget _buildAnimatedCard(int index, Widget child) {
    const total = 3;
    final start = (index / total).clamp(0.0, 0.8);
    final animation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _entryController,
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
    final visible = _notifications.where((n) => !n.dismissed).toList();
    final topPadding = MediaQuery.of(context).padding.top;

    return Stack(
      children: [
        // ── Blurred + dark overlay ─────────────────────────────────────────
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          behavior: HitTestBehavior.opaque,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
            child: Container(
              color: Colors.black.withValues(alpha: 0.55),
            ),
          ),
        ),

        // ── Notifications sheet ────────────────────────────────────────────
        Positioned(
          top: topPadding + 25 + 40 + 12,
          left: 0,
          right: 0,
          bottom: 0,
          child: Transform.translate(
            offset: Offset(0, -_dragOffset * 0.4),
            child: Opacity(
              opacity: (1.0 - _dragOffset / 200).clamp(0.0, 1.0),
              child: Column(
                children: [
                  // ── Drag handle – swipe up here to dismiss ─────────────
                  GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () => Navigator.of(context).pop(),
                    onVerticalDragUpdate: (details) {
                      if (details.delta.dy < 0) {
                        setState(() => _dragOffset += -details.delta.dy);
                      } else {
                        setState(() => _dragOffset =
                            (_dragOffset - details.delta.dy)
                                .clamp(0.0, double.infinity));
                      }
                    },
                    onVerticalDragEnd: (details) {
                      final flingUp = (details.primaryVelocity ?? 0) < -400;
                      if (_dragOffset > 80 || flingUp) {
                        Navigator.of(context).pop();
                      } else {
                        setState(() => _dragOffset = 0.0);
                      }
                    },
                    child: const SizedBox(height: 16),
                  ),
                  // ── Scrollable notification cards ──────────────────────
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(bottom: 16),
                            child: Text(
                              'NOTIFICATIONS',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Poppins',
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          ...visible.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final n = entry.value;
                            return _buildAnimatedCard(
                              idx,
                              Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: Dismissible(
                                  key: ValueKey(n.id),
                                  direction: DismissDirection.startToEnd,
                                  onDismissed: (_) =>
                                      setState(() => n.dismissed = true),
                                  background: Container(
                                    alignment: Alignment.centerLeft,
                                    padding: const EdgeInsets.only(left: 20),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade400,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: const Icon(
                                      Icons.delete_outline,
                                      color: Colors.white,
                                      size: 28,
                                    ),
                                  ),
                                  child: _NotificationCard(
                                    data: n,
                                    onClear: () =>
                                        setState(() => n.dismissed = true),
                                    onMarkCompleted: () =>
                                        setState(() => n.completed = true),
                                  ),
                                ),
                              ),
                            );
                          }),
                          if (visible.isEmpty)
                            Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Center(
                                child: Text(
                                  'No notifications',
                                  style: TextStyle(
                                    color: Color(0xFF90A5B4),
                                    fontSize: 14,
                                    fontFamily: 'Poppins',
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // ── Fixed bell button ──────────────────────────────────────────────
        Positioned(
          top: topPadding + 25,
          right: 25,
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Notification card widget
// ─────────────────────────────────────────────────────────────────────────────

class _NotificationCard extends StatelessWidget {
  final _NotificationData data;
  final VoidCallback onClear;
  final VoidCallback onMarkCompleted;

  const _NotificationCard({
    required this.data,
    required this.onClear,
    required this.onMarkCompleted,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon bubble
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: data.iconBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  data.icon,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              // Title + message
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            data.title,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF141A1E),
                              fontFamily: 'Poppins',
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: onClear,
                          child: const Text(
                            'clear',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF90A5B4),
                              fontFamily: 'Inter',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      data.message,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6B7280),
                        fontFamily: 'Inter',
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      data.time,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF9CA3AF),
                        fontFamily: 'Inter',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // ── Mark as Completed button / Completed tag ────────────────────
          if (data.showActions) ...[
            if (!data.completed) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: GestureDetector(
                  onTap: onMarkCompleted,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF00B8DB), Color(0xFF2B7FFF)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Center(
                      child: Text(
                        'Mark as Completed',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ] else ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00C49A).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFF00C49A),
                      width: 1,
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 13,
                        color: Color(0xFF00C49A),
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Completed',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF00C49A),
                          fontFamily: 'Inter',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
