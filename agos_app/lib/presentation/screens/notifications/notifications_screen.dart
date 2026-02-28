import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/services/websocket_service.dart';
import '../../../data/services/firestore_service.dart'
    show firestoreAlertsProvider, linkedDeviceIdProvider;

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<String> _tabs = ['All', 'Alerts', 'Updates', 'Maintenance'];

  /// IDs dismissed locally this session (swipe-delete or Mark All Read)
  final Set<String> _dismissedIds = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Live WebSocket alerts (real-time, this session only)
    final wsAlerts = ref.watch(alertsProvider);

    // Historical alerts derived from Firestore sensor readings
    final deviceId =
        ref.watch(linkedDeviceIdProvider).valueOrNull ?? 'esp32-sim-001';
    final fsAlertsAsync = ref.watch(firestoreAlertsProvider(deviceId));
    final fsAlerts = fsAlertsAsync.valueOrNull ?? [];

    // Merge: deduplicate by id, WS alerts take precedence (they're live)
    final wsIds = wsAlerts.map((a) => a.id).toSet();
    final combined = [
      ...wsAlerts,
      ...fsAlerts.where((a) => !wsIds.contains(a.id)),
    ];
    // Sort newest-first
    combined.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    // Remove locally dismissed
    final visible = combined
        .where((a) => !_dismissedIds.contains(a.id))
        .toList();

    final isLoading = fsAlertsAsync.isLoading && fsAlerts.isEmpty;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
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
                        child: Text('Notifications',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _dismissedIds.addAll(combined.map((a) => a.id));
                          });
                        },
                        child: const Text('Mark All Read',
                            style: TextStyle(
                                fontSize: 13, color: Colors.white70)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Tab bar
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      indicator: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      labelColor: AppColors.darkBlue,
                      unselectedLabelColor: Colors.white70,
                      labelStyle: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                      unselectedLabelStyle:
                          const TextStyle(fontSize: 13, color: AppColors.neutral1),
                      dividerColor: Colors.transparent,
                      indicatorSize: TabBarIndicatorSize.tab,
                      tabs: [
                        Tab(
                            text: _tabLabel('All', visible.length),
                            height: 36),
                        Tab(
                            text: _tabLabel(
                                'Alerts',
                                visible
                                    .where((a) =>
                                        a.severity == 'critical' ||
                                        a.severity == 'warning')
                                    .length),
                            height: 36),
                        Tab(
                            text: _tabLabel(
                                'Updates',
                                visible
                                    .where((a) => a.severity == 'info')
                                    .length),
                            height: 36),
                        Tab(
                            text: _tabLabel(
                                'Maint.',
                                visible
                                    .where((a) => a.description
                                        .toLowerCase()
                                        .contains('maintenance'))
                                    .length),
                            height: 36),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  isLoading
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(48),
                            child: CircularProgressIndicator(
                                color: AppColors.primary),
                          ))
                      : _buildNotificationList(visible),
                  _buildNotificationList(visible
                      .where((a) => a.severity == 'critical' ||
                          a.severity == 'warning')
                      .toList()),
                  _buildNotificationList(visible
                      .where((a) => a.severity == 'info')
                      .toList()),
                  _buildNotificationList(visible
                      .where((a) =>
                          a.description.toLowerCase().contains('maintenance'))
                      .toList()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _tabLabel(String name, int count) =>
      count > 0 ? '$name ($count)' : name;

  Widget _buildNotificationList(List<AlertItem> items) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notifications_none,
                size: 64, color: AppColors.neutral4.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            const Text('No notifications',
                style: TextStyle(fontSize: 16, color: AppColors.neutral4)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async {
        ref.read(webSocketServiceProvider).requestState();
        await Future.delayed(const Duration(seconds: 1));
      },
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final alert = items[index];
          return Dismissible(
            key: Key(alert.id),
            direction: DismissDirection.horizontal,
            background: Container(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.only(left: 24),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.done_all, color: Colors.white),
            ),
            secondaryBackground: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 24),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: AppColors.error,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.delete_outline, color: Colors.white),
            ),
            confirmDismiss: (direction) async {
              if (direction == DismissDirection.endToStart) {
                // Delete — remove from WS notifier and mark dismissed locally
                ref.read(webSocketServiceProvider).deleteAlert(alert.id);
                setState(() => _dismissedIds.add(alert.id));
                return true;
              }
              // Swipe right → mark as read (just remove visually)
              setState(() => _dismissedIds.add(alert.id));
              return true;
            },
            child: _buildNotificationCard(alert),
          );
        },
      ),
    );
  }

  Widget _buildNotificationCard(AlertItem alert) {
    final Color severityColor;
    final IconData severityIcon;
    switch (alert.severity) {
      case 'critical':
        severityColor = AppColors.error;
        severityIcon = Icons.error;
        break;
      case 'warning':
        severityColor = AppColors.warning;
        severityIcon = Icons.warning_amber_rounded;
        break;
      default:
        severityColor = AppColors.primary;
        severityIcon = Icons.info_outline;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border(
          left: BorderSide(color: severityColor, width: 4),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: severityColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(severityIcon, color: severityColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: severityColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        alert.severity.toUpperCase(),
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: severityColor),
                      ),
                    ),
                    const Spacer(),
                    Text(_formatTimeStr(alert.timestamp),
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.neutral4)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(alert.title.isNotEmpty ? alert.title : alert.description,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppColors.neutral1)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimeStr(String timestamp) {
    if (timestamp.isEmpty) return '';
    try {
      final time = DateTime.parse(timestamp);
      final now = DateTime.now();
      final diff = now.difference(time);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) {
      return timestamp;
    }
  }
}

