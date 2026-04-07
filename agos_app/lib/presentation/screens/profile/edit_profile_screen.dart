import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../widgets/bottom_nav_bar.dart';
import '../../widgets/fade_slide_in.dart';
import '../../../data/services/firestore_service.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _locationController = TextEditingController();

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    // Pre-populate immediately from currentUser (no spinner)
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _emailController.text = user.email ?? '';
      final displayName = user.displayName ?? '';
      final spaceIdx = displayName.indexOf(' ');
      if (spaceIdx >= 0) {
        _firstNameController.text = displayName.substring(0, spaceIdx);
        _lastNameController.text = displayName.substring(spaceIdx + 1);
      } else {
        _firstNameController.text = displayName;
      }
    }
    // Then silently update from Firestore in background
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadProfile());
  }

  Future<void> _loadProfile() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      _emailController.text = user.email ?? '';
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (!mounted) return;
      if (doc.exists) {
        final data = doc.data()!;
        final name = (data['name'] as String?) ?? '';
        final spaceIdx = name.indexOf(' ');
        if (spaceIdx >= 0) {
          _firstNameController.text = name.substring(0, spaceIdx);
          _lastNameController.text = name.substring(spaceIdx + 1);
        } else {
          _firstNameController.text = name;
        }
        _phoneController.text = (data['phone'] as String?) ?? '';
        _locationController.text = (data['location'] as String?) ?? '';
        setState(() {});
      }
    } catch (e) {
      debugPrint('EditProfile load error: $e');
    }
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) return null; // read-only, skip
    final emailRegex = RegExp(r'^[\w.+\-]+@[a-zA-Z\d\-]+\.[a-zA-Z\d.\-]+$');
    if (!emailRegex.hasMatch(value.trim())) return 'Enter a valid email address';
    return null;
  }

  String? _validatePhone(String? value) {
    if (value == null || value.trim().isEmpty) return null; // optional
    final phoneRegex = RegExp(r'^(\+63\s?|0)9\d{2}[\s\-]?\d{3}[\s\-]?\d{4}$');
    if (!phoneRegex.hasMatch(value.trim())) {
      return 'Enter a valid PH number (e.g. 0912 345 6789)';
    }
    return null;
  }

  Future<void> _saveProfile() async {    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not signed in');
      final name =
          '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}'.trim();
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({
        'name': name,
        'phone': _phoneController.text.trim(),
        'location': _locationController.text.trim(),
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Profile updated!'),
          backgroundColor: const Color(0xFF00D3F2),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save: $e'),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isGuestDemo = ref.watch(isGuestDemoProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F8FB),
      body: SafeArea(
        child: Column(
          children: [
            // -- Header ------------------------------------------------------
            Container(
              color: const Color(0xFFF4F8FB),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF4F8FB),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios_new,
                        size: 18,
                        color: Color(0xFF141A1E),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Edit Profile',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF141A1E),
                    ),
                  ),
                ],
              ),
            ),

            // -- Scrollable body ---------------------------------------------
            Expanded(
              child: FadeSlideIn(
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(25, 16, 25, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // PERSONAL INFORMATION
                    _buildSectionTitle('PERSONAL INFORMATION'),
                    const SizedBox(height: 16),
                    _buildCard([
                      _buildField(
                        icon: Icons.person_outline,
                        label: 'First Name',
                        hint: 'Enter your first name',
                        controller: _firstNameController,
                      ),
                      const SizedBox(height: 16),
                      _buildField(
                        icon: Icons.person_outline,
                        label: 'Last Name',
                        hint: 'Enter your last name',
                        controller: _lastNameController,
                      ),
                    ]),
                    const SizedBox(height: 24),

                    // CONTACT INFORMATION
                    _buildSectionTitle('CONTACT INFORMATION'),
                    const SizedBox(height: 16),
                    _buildCard([
                      _buildField(
                        icon: Icons.email_outlined,
                        label: 'Email Address',
                        hint: 'Enter your email address',
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        validator: _validateEmail,
                        readOnly: true,
                        subtitle: 'To change your email, contact support.',
                      ),
                      const SizedBox(height: 16),
                      _buildField(
                        icon: Icons.phone_outlined,
                        label: 'Phone Number',
                        hint: 'Enter your phone number',
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        validator: _validatePhone,
                      ),
                      const SizedBox(height: 16),
                      _buildField(
                        icon: Icons.location_on_outlined,
                        label: 'Location',
                        hint: 'Enter your location',
                        controller: _locationController,
                      ),
                    ]),
                    const SizedBox(height: 32),

                    // Save Changes button
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: GestureDetector(
                        onTap: _isSaving
                            ? null
                            : () {
                                if (isGuestDemo) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Guest demo account is view-only.'),
                                    ),
                                  );
                                  return;
                                }
                                _saveProfile();
                              },
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: _isSaving
                                  ? [const Color(0xFF90CAF9), const Color(0xFF90CAF9)]
                                  : [const Color(0xFF00B8DB), const Color(0xFF155DFC)],
                            ),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.save_outlined,
                                  color: Colors.white, size: 16),
                              const SizedBox(width: 8),
                              Text(
                                _isSaving ? 'Saving…' : 'Save Changes',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'Inter',
                                ),
                              ),
                            ],
                          ),
                        ),
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
      ),
      bottomNavigationBar: const BottomNavBar(currentIndex: 2),
    );
  }

  Widget _buildSectionTitle(String title) {
    return ShaderMask(
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
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white, width: 1.18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF5DADE2).withOpacity(0.15),
            blurRadius: 8,
            offset: const Offset(0, 0),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _buildField({
    required IconData icon,
    required String label,
    required TextEditingController controller,
    String? hint,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    bool readOnly = false,
    String? subtitle,
  }) {
    String? composedValidator(String? value) {
      if (readOnly) return null;
      if (value == null || value.trim().isEmpty) {
        return '$label is required';
      }
      return validator?.call(value);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: const Color(0xFF314158)),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF314158),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          validator: composedValidator,
          readOnly: readOnly,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          cursorColor: const Color(0xFF0A1929),
          cursorErrorColor: const Color(0xFF0A1929),
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 16,
            color: Color(0xFF0A1929),
          ),
          decoration: InputDecoration(
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            filled: true,
            fillColor: readOnly ? const Color(0xFFF1F5F9) : Colors.white,
            hintText: hint,
            hintStyle: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 16,
              color: Color(0xFFADB5BD),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                  color: Color(0xFFA2F4FD), width: 1.18),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                  color: Color(0xFF53EAFD), width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                  color: Color(0xFFE53935), width: 1.18),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                  color: Color(0xFFE53935), width: 1.5),
            ),
            errorStyle: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              color: Color(0xFFE53935),
            ),
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 11,
              color: Color(0xFF90A1B9),
            ),
          ),
        ],
      ],
    );
  }
}
