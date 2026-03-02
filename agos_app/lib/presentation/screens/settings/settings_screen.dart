import 'package:agos_app/core/constants/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../widgets/bottom_nav_bar.dart';
import '../../widgets/notification_modal.dart';
import '../../../data/services/firestore_service.dart'
    show hasUnreadAlertsProvider;
import '../../../data/services/websocket_service.dart'
    show pushNotificationsEnabledProvider;
import '../../../data/services/filter_reminder_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with TickerProviderStateMixin {
  bool _waterLevelAlerts = true;
  late AnimationController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    )..forward();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Widget _buildAnimated(int index, Widget child) {
    const total = 3;
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
    return Scaffold(
      backgroundColor: const Color(0xFFF4F8FB),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Header section (no animation – always visible)
              _buildHeader(context),
              // Settings content
              const SizedBox(height: 19),
              _buildAnimated(0, _buildSettingsContent()),
              const SizedBox(height: 100), // Bottom padding for navigation
            ],
          ),
        ),
      ),
      bottomNavigationBar: const BottomNavBar(currentIndex: 2),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(25),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  color: Colors.transparent,
                ),
                child: const Icon(
                  Icons.settings,
                  size: 24,
                  color: Color(0xFF141A1E),
                ),
              ),
              const SizedBox(width: 4),
              const Text(
                'SETTINGS',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF141A1E),
                  height: 32 / 20,
                ),
              ),
            ],
          ),
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
    );
  }

  Widget _buildSettingsContent() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 25),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ACCOUNT Section
          _buildSectionHeader('ACCOUNT'),
          const SizedBox(height: 16),
          _buildSettingsCard([
            _buildSettingsTile(
              icon: Icons.person_outline,
              title: 'Edit Profile',
              onTap: () => Navigator.pushNamed(context, '/edit-profile'),
            ),
            _buildDivider(),
            _buildSettingsTile(
              icon: Icons.lock_outline,
              title: 'Privacy & Security',
              onTap: () => Navigator.pushNamed(context, '/privacy-security'),
            ),
          ]),
          const SizedBox(height: 24),
          
          // NOTIFICATIONS Section
          _buildSectionHeader('NOTIFICATIONS'),
          const SizedBox(height: 16),
          _buildSettingsCard([
            _buildToggleTile(
              icon: Icons.notifications_outlined,
              title: 'Push Notifications',
              subtitle: 'Receive alerts about water quality',
              value: ref.watch(pushNotificationsEnabledProvider),
              onChanged: (v) => ref.read(pushNotificationsEnabledProvider.notifier).setEnabled(v),
            ),
            _buildDivider(),
            _buildToggleTile(
              icon: Icons.water_drop_outlined,
              title: 'Water Level Alerts',
              subtitle: 'Get notified when tank is low',
              value: _waterLevelAlerts,
              onChanged: (v) => setState(() => _waterLevelAlerts = v),
            ),
            _buildDivider(),
            _buildFilterReminderTile(),
          ]),
          const SizedBox(height: 24),
          
          // SYSTEM Section
          _buildSectionHeader('SYSTEM'),
          const SizedBox(height: 16),
          _buildSettingsCard([
            _buildSettingsTile(
              icon: Icons.tune,
              title: 'Water Quality Thresholds',
              onTap: () => Navigator.pushNamed(context, '/water-quality-thresholds'),
            ),
            _buildDivider(),
            _buildSettingsTile(
              icon: Icons.storage_outlined,
              title: 'Data Logging',
              subtitle: 'Save historical sensor data',
              onTap: () => Navigator.pushNamed(context, '/data-logging'),
            ),
          ]),
          const SizedBox(height: 24),
          
          // ABOUT Section
          _buildSectionHeader('ABOUT'),
          const SizedBox(height: 16),
          _buildSettingsCard([
            _buildSettingsTile(
              icon: Icons.help_outline,
              title: 'Help & Support',
              onTap: () => Navigator.pushNamed(context, '/help'),
            ),
            _buildDivider(),
            _buildSettingsTile(
              icon: Icons.info_outline,
              title: 'About AGOS',
              onTap: () => Navigator.pushNamed(context, '/about'),
            ),
          ]),
          const SizedBox(height: 24),
          
          // Sign Out Button
          _buildSignOutButton(),
          const SizedBox(height: 16),
          
          // Footer
          _buildFooter(),
        ],
      ),
    );
  }
  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: ShaderMask(
        shaderCallback: (bounds) => const LinearGradient(
          colors: [Color(0xFF1447E6), Color(0xFF0092B8)],
        ).createShader(bounds),
        child: Text(
          title,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x141BA9E1),
            blurRadius: 45,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: children,
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primaryAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  icon,
                  color: AppColors.primaryAccent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF141A1E),
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: Color(0xFF90A5B4),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: Color(0xFF90A5B4),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToggleTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF00D3F2).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              icon,
              color: const Color(0xFF00D3F2),
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF141A1E),
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: Color(0xFF90A5B4),
                    ),
                  ),
                ],
              ],
            ),
          ),
          GestureDetector(
            onTap: () => onChanged(!value),
            child: Container(
              width: 32,
              height: 18,
              decoration: BoxDecoration(
                color: value ? const Color(0xFF0F172A) : const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(999),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 150),
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.all(2),
                  width: 14,
                  height: 14,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      height: 1,
      color: const Color(0xFFF1F5F9),
    );
  }

  Widget _buildFilterReminderTile() {
    final settings = ref.watch(filterReminderProvider);
    final intervalLabel = settings.intervalMonths == 1
        ? 'Monthly'
        : 'Every ${settings.intervalMonths} months';
    final subtitle = settings.enabled
        ? '$intervalLabel · on the ${settings.dayOfMonth}${_ordinal(settings.dayOfMonth)}'
        : 'Disabled';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showFilterReminderDialog(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF009966).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.filter_alt_outlined,
                  color: Color(0xFF009966),
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Filter Cleaning Reminder',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF141A1E),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: Color(0xFF90A5B4),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  size: 18, color: Color(0xFF90A5B4)),
            ],
          ),
        ),
      ),
    );
  }

  String _ordinal(int n) {
    if (n >= 11 && n <= 13) return 'th';
    switch (n % 10) {
      case 1: return 'st';
      case 2: return 'nd';
      case 3: return 'rd';
      default: return 'th';
    }
  }

  Future<void> _showFilterReminderDialog() async {
    final settings = ref.read(filterReminderProvider);
    int selectedInterval = settings.intervalMonths;
    int selectedDay = settings.dayOfMonth;
    bool enabled = settings.enabled;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.filter_alt_outlined,
                  color: Color(0xFF009966), size: 22),
              SizedBox(width: 8),
              Text(
                'Filter Cleaning Reminder',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 16,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Remind me to clean the filter:',
                style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    color: Color(0xFF62748E)),
              ),
              const SizedBox(height: 12),
              // Enable toggle
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Enable reminder',
                      style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 14,
                          color: Color(0xFF1D293D))),
                  GestureDetector(
                    onTap: () => setDlgState(() => enabled = !enabled),
                    child: Container(
                      width: 32,
                      height: 18,
                      decoration: BoxDecoration(
                        color: enabled
                            ? const Color(0xFF009966)
                            : const Color(0xFFCBD5E1),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: AnimatedAlign(
                        duration: const Duration(milliseconds: 150),
                        alignment: enabled
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.all(2),
                          width: 14,
                          height: 14,
                          decoration: const BoxDecoration(
                              color: Colors.white, shape: BoxShape.circle),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Interval
              const Text('How often?',
                  style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF1D293D))),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [1, 2, 3, 6].map((months) {
                  final label =
                      months == 1 ? 'Monthly' : 'Every $months months';
                  final selected = selectedInterval == months;
                  return GestureDetector(
                    onTap: () =>
                        setDlgState(() => selectedInterval = months),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFF009966)
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(20),
                        border: selected
                            ? null
                            : Border.all(
                                color: const Color(0xFFCBD5E1)),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          color: selected
                              ? Colors.white
                              : const Color(0xFF314158),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              // Day of month
              const Text('On which day of the month?',
                  style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF1D293D))),
              const SizedBox(height: 8),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline,
                        color: Color(0xFF009966)),
                    onPressed: () {
                      if (selectedDay > 1) {
                        setDlgState(() => selectedDay--);
                      }
                    },
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        '$selectedDay${_ordinal(selectedDay)}',
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1D293D),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline,
                        color: Color(0xFF009966)),
                    onPressed: () {
                      if (selectedDay < 28) {
                        setDlgState(() => selectedDay++);
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Center(
                child: Text(
                  'Suggested: 20th — at least once a month',
                  style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 11,
                      color: Color(0xFF90A5B4)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel',
                  style: TextStyle(
                      fontFamily: 'Inter', color: Color(0xFF62748E))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF009966),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                ref.read(filterReminderProvider.notifier).update(
                      dayOfMonth: selectedDay,
                      intervalMonths: selectedInterval,
                      enabled: enabled,
                    );
                Navigator.pop(ctx);
              },
              child: const Text('Save',
                  style: TextStyle(fontFamily: 'Inter')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSignOutButton() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x141BA9E1),
            blurRadius: 45,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showSignOutDialog(context),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE74C3C).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.logout,
                    color: Color(0xFFE74C3C),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 16),
                const Text(
                  'Sign Out',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFFE74C3C),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Developed by Calingasin, Dantes, Jayme, Nagpal, Pascual',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: Color(0xFF90A5B4),
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 4),
          Text(
            '© 2026 AGOS',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: Color(0xFF90A5B4),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
  void _showSignOutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Sign Out',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFF141A1E),
          ),
        ),
        content: const Text(
          'Are you sure you want to sign out?',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: Color(0xFF90A5B4),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF90A5B4),
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              // Also sign out of Google so next sign-in shows the account picker
              await GoogleSignIn().signOut();
              await FirebaseAuth.instance.signOut();
              if (context.mounted) {
                Navigator.pushNamedAndRemoveUntil(
                    context, '/login', (r) => false);
              }
            },
            child: const Text(
              'Sign Out',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFFE74C3C),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
