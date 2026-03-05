import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/services/firestore_service.dart';
import '../../../data/services/websocket_service.dart';

class DeviceManagementScreen extends ConsumerStatefulWidget {
  const DeviceManagementScreen({super.key});

  @override
  ConsumerState<DeviceManagementScreen> createState() =>
      _DeviceManagementScreenState();
}

class _DeviceManagementScreenState
    extends ConsumerState<DeviceManagementScreen> {
  final _emailController = TextEditingController();
  bool _submittingShare = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _inviteUser(String deviceId) async {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    setState(() => _submittingShare = true);
    final service = ref.read(firestoreServiceProvider);
    final result = await service.shareDeviceWithEmail(
      deviceId: deviceId,
      inviteeEmail: email,
      ownerUid: user.uid,
    );
    setState(() => _submittingShare = false);

    if (!mounted) return;
    _emailController.clear();

    String message;
    Color color;
    switch (result) {
      case SharingResult.success:
        message = '$email can now view this device.';
        color = AppColors.success;
        break;
      case SharingResult.notFound:
        message = 'No AGOS account found with that email.';
        color = AppColors.error;
        break;
      case SharingResult.isSelf:
        message = "You can't share with yourself.";
        color = AppColors.warning;
        break;
      case SharingResult.error:
        message = 'Something went wrong. Please try again.';
        color = AppColors.error;
        break;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message,
          style: GoogleFonts.inter(color: Colors.white)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _removeUser(String deviceId, SharedUserInfo user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove access?'),
        content: Text(
            '${user.name.isNotEmpty ? user.name : user.email} will no longer be able to see this device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child:
                const Text('Remove', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final deviceId0 = deviceId;
    await ref
        .read(firestoreServiceProvider)
        .removeSharedUser(deviceId: deviceId0, sharedUid: user.uid);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Access removed.'),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final devices = ref.watch(devicesProvider);
    final deviceId = ref.watch(linkedDeviceIdProvider).valueOrNull ?? '';
    final isOwner = ref.watch(isDeviceOwnerProvider).valueOrNull ?? false;
    final sharedUsersAsync = ref.watch(sharedUsersProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──
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
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_ios,
                        color: Colors.white),
                  ),
                  Expanded(
                    child: Text(
                      'Device Management',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // ── Connected devices ──
                  if (devices.isEmpty)
                    _emptyDevices()
                  else
                    ...devices.map(_buildDeviceCard),

                  // ── Sharing section (only for device owner) ──
                  if (isOwner && deviceId.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _sectionHeader('Share with others'),
                    const SizedBox(height: 12),
                    _inviteCard(deviceId),
                    const SizedBox(height: 16),
                    sharedUsersAsync.when(
                      data: (users) => users.isEmpty
                          ? _emptyShared()
                          : Column(
                              children: users
                                  .map((u) =>
                                      _sharedUserTile(deviceId, u))
                                  .toList(),
                            ),
                      loading: () => const Center(
                          child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(),
                      )),
                      error: (_, __) => const SizedBox.shrink(),
                    ),
                  ],

                  // ── Shared-with-me banner (non-owners) ──
                  if (!isOwner && deviceId.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _sharedWithMeBanner(),
                  ],

                  const SizedBox(height: 20),
                  // ── Add new device button ──
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.pushNamed(
                          context, '/device-setup-intro'),
                      icon: const Icon(Icons.add),
                      label: Text('Add New Device',
                          style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
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

  // ── Sub-builders ──────────────────────────────────────────────────────────

  Widget _sectionHeader(String text) {
    return Text(
      text,
      style: GoogleFonts.poppins(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: AppColors.neutral1),
    );
  }

  Widget _inviteCard(String deviceId) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Invite by email',
            style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.neutral2),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    hintText: 'friend@email.com',
                    hintStyle: GoogleFonts.inter(
                        color: AppColors.neutral4, fontSize: 14),
                    filled: true,
                    fillColor: AppColors.background,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          const BorderSide(color: AppColors.neutral5),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          const BorderSide(color: AppColors.neutral5),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _submittingShare
                  ? const SizedBox(
                      width: 44,
                      height: 44,
                      child: Padding(
                        padding: EdgeInsets.all(10),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ))
                  : SizedBox(
                      width: 44,
                      height: 44,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                              colors: [
                                Color(0xFF00B8DB),
                                Color(0xFF155DFC)
                              ]),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.send,
                              color: Colors.white, size: 20),
                          onPressed: () => _inviteUser(deviceId),
                        ),
                      ),
                    ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Shared users can view sensor data and alerts, but cannot control the pump or change settings.',
            style: GoogleFonts.inter(
                fontSize: 12, color: AppColors.neutral4),
          ),
        ],
      ),
    );
  }

  Widget _sharedUserTile(String deviceId, SharedUserInfo user) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.primary.withValues(alpha: 0.12),
            child: Text(
              (user.name.isNotEmpty ? user.name : user.email)
                      .substring(0, 1)
                      .toUpperCase(),
              style: GoogleFonts.poppins(
                  color: AppColors.primaryDark,
                  fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (user.name.isNotEmpty)
                  Text(user.name,
                      style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppColors.neutral1)),
                Text(user.email.isNotEmpty ? user.email : user.uid,
                    style: GoogleFonts.inter(
                        fontSize: 12, color: AppColors.neutral4)),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _removeUser(deviceId, user),
            icon: const Icon(Icons.person_remove_outlined,
                color: AppColors.error, size: 20),
            tooltip: 'Remove access',
          ),
        ],
      ),
    );
  }

  Widget _emptyShared() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        'No one else has access yet. Invite someone above.',
        style: GoogleFonts.inter(
            fontSize: 13, color: AppColors.neutral4),
      ),
    );
  }

  Widget _sharedWithMeBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.share, color: AppColors.primaryDark, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'This device was shared with you. Contact the owner to manage sharing settings.',
              style: GoogleFonts.inter(
                  fontSize: 13, color: AppColors.primaryDark),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyDevices() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.devices_other,
              size: 64,
              color: AppColors.neutral4.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Text('No devices connected',
              style: GoogleFonts.inter(
                  fontSize: 16, color: AppColors.neutral4)),
        ],
      ),
    );
  }

  Widget _buildDeviceCard(DeviceInfo device) {
    final isConnected = device.status == 'connected';
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: (isConnected ? AppColors.success : AppColors.neutral4)
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.sensors,
              color:
                  isConnected ? AppColors.success : AppColors.neutral4,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(device.name,
                    style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.neutral1)),
                const SizedBox(height: 4),
                Text('ID: ${device.id}',
                    style: GoogleFonts.inter(
                        fontSize: 13, color: AppColors.neutral4)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isConnected
                            ? AppColors.success
                            : AppColors.neutral4,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isConnected ? 'Connected' : 'Disconnected',
                      style: TextStyle(
                        fontSize: 13,
                        color: isConnected
                            ? AppColors.success
                            : AppColors.neutral4,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

 