import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/services/firestore_service.dart';
import '../../widgets/bottom_nav_bar.dart';
import '../../widgets/fade_slide_in.dart';

class PrivacySecurityScreen extends ConsumerStatefulWidget {
  const PrivacySecurityScreen({super.key});

  @override
  ConsumerState<PrivacySecurityScreen> createState() =>
      _PrivacySecurityScreenState();
}

class _PrivacySecurityScreenState extends ConsumerState<PrivacySecurityScreen> {
  bool _downloadingData = false;
  bool _deletingAccount = false;

  // ─── helpers ─────────────────────────────────────────────────────────────

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? const Color(0xFFE74C3C) : null,
    ));
  }

  // ─── Change Password ──────────────────────────────────────────────────────

  Future<void> _showChangePasswordDialog() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final isPasswordUser =
        user.providerData.any((p) => p.providerId == 'password');

    if (!isPasswordUser) {
      _snack('Password changes are only available for email/password accounts.');
      return;
    }

    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        bool obscureCurrent = true;
        bool obscureNew = true;
        bool obscureConfirm = true;
        bool loading = false;

        return StatefulBuilder(builder: (ctx, setDialogState) {
          Future<void> doChange() async {
            if (newCtrl.text != confirmCtrl.text) {
              _snack('New passwords do not match.', error: true);
              return;
            }
            if (newCtrl.text.length < 6) {
              _snack('Password must be at least 6 characters.', error: true);
              return;
            }
            setDialogState(() => loading = true);
            try {
              final credential = EmailAuthProvider.credential(
                email: user.email!,
                password: currentCtrl.text,
              );
              await user.reauthenticateWithCredential(credential);
              await user.updatePassword(newCtrl.text);
              if (ctx.mounted) Navigator.pop(ctx);
              _snack('Password updated successfully.');
            } on FirebaseAuthException catch (e) {
              final msg = e.code == 'wrong-password'
                  ? 'Current password is incorrect.'
                  : e.message ?? 'Failed to change password.';
              _snack(msg, error: true);
            } finally {
              setDialogState(() => loading = false);
            }
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            title: const Text('Change Password',
                style: TextStyle(
                    fontFamily: 'Poppins', color: Color(0xFF141A1E))),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _dialogField(
                  controller: currentCtrl,
                  label: 'Current Password',
                  obscure: obscureCurrent,
                  onToggle: () => setDialogState(
                      () => obscureCurrent = !obscureCurrent),
                ),
                const SizedBox(height: 12),
                _dialogField(
                  controller: newCtrl,
                  label: 'New Password',
                  obscure: obscureNew,
                  onToggle: () =>
                      setDialogState(() => obscureNew = !obscureNew),
                ),
                const SizedBox(height: 12),
                _dialogField(
                  controller: confirmCtrl,
                  label: 'Confirm New Password',
                  obscure: obscureConfirm,
                  onToggle: () => setDialogState(
                      () => obscureConfirm = !obscureConfirm),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: loading ? null : () {
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('Cancel',
                    style: TextStyle(color: Color(0xFF62748E))),
              ),
              TextButton(
                onPressed: loading ? null : doChange,
                child: loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Update',
                        style: TextStyle(color: Color(0xFF1447E6))),
              ),
            ],
          );
        });
      },
    );

    currentCtrl.dispose();
    newCtrl.dispose();
    confirmCtrl.dispose();
  }

  Widget _dialogField({
    required TextEditingController controller,
    required String label,
    required bool obscure,
    required VoidCallback onToggle,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        suffixIcon: IconButton(
          icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
          onPressed: onToggle,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }

  // ─── Download My Data ─────────────────────────────────────────────────────

  Future<void> _downloadData() async {
    setState(() => _downloadingData = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _snack('Not signed in.', error: true);
        return;
      }

      final deviceId =
          ref.read(linkedDeviceIdProvider).valueOrNull ?? 'agos-zksl9QK3';

      final service = ref.read(firestoreServiceProvider);
      final readings = await service.fetchReadings(deviceId, days: 90);

      final profile = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      // Recursively convert Firestore Timestamps to ISO strings
      Object? sanitize(Object? val) {
        if (val is Timestamp) return val.toDate().toIso8601String();
        if (val is Map) {
          return val.map((k, v) => MapEntry(k, sanitize(v)));
        }
        if (val is List) return val.map(sanitize).toList();
        return val;
      }

      final export = {
        'exported_at': DateTime.now().toIso8601String(),
        'user': {
          'uid': user.uid,
          'email': user.email,
          'name': user.displayName,
        },
        'device_id': deviceId,
        'sensor_readings': readings
            .map((r) => {
                  'timestamp': r.timestamp.toIso8601String(),
                  'turbidity': r.turbidity,
                  'ph': r.ph,
                  'tds': r.tds,
                  'level': r.level,
                  'flow_rate': r.flowRate,
                  'pump_active': r.pumpActive,
                })
            .toList(),
        'profile': sanitize(profile.data()),
      };

      final json = const JsonEncoder.withIndent('  ').convert(export);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/agos_my_data.json');
      await file.writeAsString(json);
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'My AGOS Data Export',
        text: 'AGOS export — ${readings.length} readings.',
      );
    } catch (e) {
      _snack('Export failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _downloadingData = false);
    }
  }

  // ─── Delete Account ───────────────────────────────────────────────────────

  Future<void> _showDeleteDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Account',
            style: TextStyle(
                fontFamily: 'Poppins', color: Color(0xFF141A1E))),
        content: const Text(
            'This cannot be undone. Your account, device data, and all stored readings will be permanently deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(_, false),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF62748E))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(_, true),
            child: const Text('Delete',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _deleteAccount();
  }

  Future<void> _deleteAccount() async {
    setState(() => _deletingAccount = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final uid = user.uid;
      final deviceId = ref.read(linkedDeviceIdProvider).valueOrNull;

      // Delete Firestore docs
      await FirebaseFirestore.instance.collection('users').doc(uid).delete();
      if (deviceId != null && deviceId.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('devices')
            .doc(deviceId)
            .delete();
      }

      // Sign out Google cache if applicable
      final isGoogleUser =
          user.providerData.any((p) => p.providerId == 'google.com');
      if (isGoogleUser) await GoogleSignIn().signOut();

      // Delete Firebase Auth account
      await user.delete();

      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        _snack(
            'Please sign out and sign in again before deleting your account.',
            error: true);
      } else {
        _snack(e.message ?? 'Failed to delete account.', error: true);
      }
    } catch (e) {
      _snack('Failed to delete account: $e', error: true);
    } finally {
      if (mounted) setState(() => _deletingAccount = false);
    }
  }

  // ─── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F8FB),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 100),
          child: Column(
            children: [
              _buildHeader(),
              const SizedBox(height: 8),
              FadeSlideIn(child: _buildContent()),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const BottomNavBar(currentIndex: 2),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 16),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const SizedBox(
              width: 40,
              height: 40,
              child: Icon(Icons.arrow_back_ios,
                  size: 20, color: Color(0xFF141A1E)),
            ),
          ),
          const SizedBox(width: 4),
          const Text(
            'Privacy & Security',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF141A1E),
            ),
          ),
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

  Widget _buildContent() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 25),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('PRIVACY & SECURITY'),
          const SizedBox(height: 16),
          Container(
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
                ),
              ],
            ),
            padding: const EdgeInsets.all(17),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Data Privacy Notice
                Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: const Color(0xFFBEDBFF), width: 1.18),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline,
                          size: 20, color: Color(0xFF1C398E)),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Data Privacy Notice',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 14,
                                color: Color(0xFF1C398E),
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Your water quality data is stored securely on Firebase. We only collect sensor readings and account data to operate the AGOS system.',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 12,
                                color: Color(0xFF1447E6),
                                height: 1.33,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Change Password (email/password users only)
                if (FirebaseAuth.instance.currentUser?.providerData
                        .any((p) => p.providerId == 'password') ==
                    true) ...[
                  _buildActionTile(
                    icon: Icons.lock_outline,
                    iconColor: const Color(0xFF1447E6),
                    iconBg: const Color(0xFFEFF6FF),
                    title: 'Change Password',
                    subtitle: 'Update your account password',
                    onTap: _showChangePasswordDialog,
                  ),
                  const SizedBox(height: 12),
                ],

                // Download My Data
                _buildActionTile(
                  icon: Icons.download_outlined,
                  iconColor: const Color(0xFF009966),
                  iconBg: const Color(0xFFECFDF5),
                  title: 'Download My Data',
                  subtitle: 'Export all your stored sensor readings',
                  loading: _downloadingData,
                  onTap: _downloadData,
                ),
                const SizedBox(height: 12),

                // Delete Account
                _buildActionTile(
                  icon: Icons.delete_forever_outlined,
                  iconColor: const Color(0xFFE7000B),
                  iconBg: const Color(0xFFFFF0F0),
                  title: 'Delete Account',
                  subtitle: 'Permanently remove your account and data',
                  titleColor: const Color(0xFFE7000B),
                  subtitleColor: const Color(0xFFFB2C36),
                  borderColor: const Color(0xFFFFC9C9),
                  loading: _deletingAccount,
                  onTap: _showDeleteDialog,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color titleColor = const Color(0xFF314158),
    Color subtitleColor = const Color(0xFF62748E),
    Color borderColor = const Color(0xFFA2F4FD),
    bool loading = false,
  }) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: 1.18),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: loading
                  ? Padding(
                      padding: const EdgeInsets.all(10),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: iconColor,
                      ),
                    )
                  : Icon(icon, size: 20, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 16,
                      color: titleColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      color: subtitleColor,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                size: 20, color: titleColor.withValues(alpha: 0.5)),
          ],
        ),
      ),
    );
  }
}

