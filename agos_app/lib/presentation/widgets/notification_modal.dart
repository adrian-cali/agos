import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/services/firestore_service.dart'
    show firestoreAlertsProvider, linkedDeviceIdProvider;
import '../../data/services/websocket_service.dart'
    show AlertItem, alertsProvider, completedAlertsProvider, dismissedAlertsProvider;

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
    pageBuilder: (context, anim1, anim2) => const Material(
      type: MaterialType.transparency,
      child: _NotificationModal(),
    ),
    transitionBuilder: (context, anim1, anim2, child) {
      return FadeTransition(
        opacity: anim1,
        child: child,
      );
    },
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal view-model derived from AlertItem
// ─────────────────────────────────────────────────────────────────────────────

class _NotificationData {
  final String id;
  final IconData icon;
  final Color iconBg;
  final String title;
  final String message;
  final String time;
  bool dismissed = false;
  bool completed = false;

  _NotificationData({
    required this.id,
    required this.icon,
    required this.iconBg,
    required this.title,
    required this.message,
    required this.time,
  });

  static _NotificationData fromAlert(AlertItem a) {
    // Icon/colour by type + severity
    IconData icon;
    Color bg;

    if (a.type == 'threshold_exceeded') {
      // Use the parameter-specific gradient color matching the dashboard icon
      final desc = a.description.toLowerCase();
      if (desc.contains('turbidity')) {
        icon = Icons.opacity_outlined;
        bg = const Color(0xFF00D3F2); // cyan — turbidity
      } else if (desc.contains('ph')) {
        icon = Icons.science_outlined;
        bg = const Color(0xFFC27AFF); // purple — pH
      } else if (desc.contains('tds')) {
        icon = Icons.water_outlined;
        bg = const Color(0xFF7C86FF); // blue-violet — TDS
      } else {
        icon = Icons.warning_amber_outlined;
        bg = const Color(0xFFF59E0B); // fallback amber
      }
    } else if (a.severity == 'critical') {
      icon = Icons.error_outline;
      bg = const Color(0xFFFF5252);
    } else if (a.severity == 'warning') {
      icon = Icons.warning_amber_outlined;
      bg = const Color(0xFFFFA726);
    } else if (a.type == 'water_quality') {
      icon = Icons.water_drop_outlined;
      bg = const Color(0xFF00C49A);
    } else if (a.type == 'system') {
      icon = Icons.settings_outlined;
      bg = const Color(0xFF9C27B0);
    } else {
      icon = Icons.notifications_outlined;
      bg = const Color(0xFF00B8DB);
    }

    return _NotificationData(
      id: a.id,
      icon: icon,
      iconBg: bg,
      title: a.title,
      message: a.description,
      time: _fmtAgo(DateTime.tryParse(a.timestamp) ?? DateTime.now()),
    );
  }

  static String _fmtAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Modal widget
// ─────────────────────────────────────────────────────────────────────────────

class _NotificationModal extends ConsumerStatefulWidget {
  const _NotificationModal();

  @override
  ConsumerState<_NotificationModal> createState() =>
      _NotificationModalState();
}

class _NotificationModalState extends ConsumerState<_NotificationModal>
    with SingleTickerProviderStateMixin {
  late AnimationController _entryController;
  final ScrollController _scrollController = ScrollController();
  double _dragOffset = 0.0;

  // Local completed state — keyed by alert id (not persisted, per-session)
  // NOTE: replaced by completedAlertsProvider (persisted via SharedPreferences)

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

  /// Merge Firestore + WS alerts, deduplicate by id, newest-first.
  List<_NotificationData> _buildNotifications() {
    final deviceId =
        ref.watch(linkedDeviceIdProvider).valueOrNull ?? '';
    final fsAlerts =
        ref.watch(firestoreAlertsProvider(deviceId)).valueOrNull ?? [];
    final wsAlerts = ref.watch(alertsProvider);
    final dismissed = ref.watch(dismissedAlertsProvider).ids;
    final completed = ref.watch(completedAlertsProvider);

    final seen = <String>{};
    final merged = <_NotificationData>[];
    for (final a in [...wsAlerts, ...fsAlerts]) {
      if (seen.contains(a.id)) continue;
      seen.add(a.id);
      final nd = _NotificationData.fromAlert(a)
        ..dismissed = dismissed.contains(a.id)
        ..completed = completed.contains(a.id);
      merged.add(nd);
    }
    return merged;
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
    final allNotifications = _buildNotifications();
    final visible = allNotifications.where((n) => !n.dismissed).toList();
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
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'NOTIFICATIONS',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Poppins',
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                if (visible.isNotEmpty)
                                  GestureDetector(
                                    onTap: () => ref
                                        .read(dismissedAlertsProvider.notifier)
                                        .dismissAll(visible.map((n) => n.id)),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.white
                                            .withValues(alpha: 0.12),
                                        borderRadius:
                                            BorderRadius.circular(20),
                                        border: Border.all(
                                          color: Colors.white
                                              .withValues(alpha: 0.3),
                                          width: 1,
                                        ),
                                      ),
                                      child: const Text(
                                        'Clear all',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.white,
                                          fontFamily: 'Inter',
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
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
                                      ref.read(dismissedAlertsProvider.notifier).dismiss(n.id),
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
                                    onClear: () => ref.read(dismissedAlertsProvider.notifier).dismiss(n.id),
                                    onMarkCompleted: () =>
                                        ref.read(completedAlertsProvider.notifier).markCompleted(n.id),
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
                // Red dot shown only when there are visible notifications
                if (visible.isNotEmpty)
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
      ),
    );
  }
}
