import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../data/services/firestore_service.dart';

/// Device Information Screen (Figma 335:994)
/// Form for entering personal and contact information
class DeviceInformationScreen extends ConsumerStatefulWidget {
  const DeviceInformationScreen({super.key});

  @override
  ConsumerState<DeviceInformationScreen> createState() =>
      _DeviceInformationScreenState();
}

class _DeviceInformationScreenState
    extends ConsumerState<DeviceInformationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _locationController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _prefillFromAuth();
  }

  void _prefillFromAuth() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Pre-fill email from Firebase Auth
    if (_emailController.text.trim().isEmpty && user.email != null) {
      _emailController.text = user.email!;
    }

    // Pre-fill name from Firebase Auth displayName
    final displayName = user.displayName ?? '';
    if (displayName.isNotEmpty) {
      final parts = displayName.trim().split(' ');
      if (_firstNameController.text.trim().isEmpty) {
        _firstNameController.text = parts.first;
      }
      if (_lastNameController.text.trim().isEmpty && parts.length > 1) {
        _lastNameController.text = parts.sublist(1).join(' ');
      }
    }

    // Also load from Firestore (name, phone, location stored from prior setup or profile)
    _prefillFromFirestore(user.uid);
  }

  Future<void> _prefillFromFirestore(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      if (!mounted || doc.data() == null) return;
      final data = doc.data()!;

      // Name from Firestore (may be more complete than displayName)
      final firestoreName = (data['name'] as String? ?? '').trim();
      if (firestoreName.isNotEmpty) {
        final parts = firestoreName.split(' ');
        if (_firstNameController.text.trim().isEmpty) {
          _firstNameController.text = parts.first;
        }
        if (_lastNameController.text.trim().isEmpty && parts.length > 1) {
          _lastNameController.text = parts.sublist(1).join(' ');
        }
      }

      // Phone
      final phone = (data['phone'] as String? ?? '').trim();
      if (_phoneController.text.trim().isEmpty && phone.isNotEmpty) {
        _phoneController.text = phone;
      }

      // Location — check user doc first, then device doc
      final userLocation = (data['location'] as String? ?? '').trim();
      if (_locationController.text.trim().isEmpty && userLocation.isNotEmpty) {
        _locationController.text = userLocation;
      }

      // Also check device doc for location if not yet filled
      final deviceId = (data['device_id'] as String? ?? '').trim();
      if (deviceId.isNotEmpty && _locationController.text.trim().isEmpty) {
        final deviceDoc = await FirebaseFirestore.instance
            .collection('devices')
            .doc(deviceId)
            .get();
        if (mounted && deviceDoc.data() != null) {
          final location =
              (deviceDoc.data()!['location'] as String? ?? '').trim();
          if (_locationController.text.trim().isEmpty && location.isNotEmpty) {
            _locationController.text = location;
          }
        }
      }

      // Trigger rebuild to show pre-filled values
      if (mounted) setState(() {});
    } catch (_) {
      // Silently ignore — form fields stay with whatever was pre-filled from Auth
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

  bool _saving = false;

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      // Pre-fill email from Firebase Auth if the field was left blank
      final authEmail =
          FirebaseAuth.instance.currentUser?.email ?? '';
      final enteredEmail = _emailController.text.trim();

      // Save form data into the shared setup state
      ref.read(setupStateProvider.notifier).setDeviceInfo(
            ownerName:
                '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}'
                    .trim(),
            ownerEmail: enteredEmail.isNotEmpty ? enteredEmail : authEmail,
            ownerPhone: _phoneController.text.trim(),
            location: _locationController.text.trim(),
          );

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/setup-complete');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Email address is required';
    }
    final emailRegex = RegExp(r'^[\w.+\-]+@[a-zA-Z\d\-]+\.[a-zA-Z\d.\-]+$');
    if (!emailRegex.hasMatch(value.trim())) {
      return 'Enter a valid email address';
    }
    return null;
  }

  String? _validatePhone(String? value) {
    // Phone is optional — skip validation if empty
    if (value == null || value.trim().isEmpty) return null;
    // Accept formats: +63 9XX XXX XXXX, 09XXXXXXXXX, or +639XXXXXXXXX
    final phoneRegex = RegExp(r'^(\+63\s?|0)9\d{2}[\s\-]?\d{3}[\s\-]?\d{4}$');
    if (!phoneRegex.hasMatch(value.trim())) {
      return 'Enter a valid PH number (e.g. +63 912 345 6789)';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment(-0.2, -1),
            end: Alignment(0.2, 1),
            colors: [
              Color(0xFFF8FAFC),
              Color(0xFFEFF6FF),
              Color(0xFFECFEFF),
            ],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Progress bar (NOT overlay)
              Padding(
                padding: const EdgeInsets.fromLTRB(25, 9, 25, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: const LinearProgressIndicator(
                        value: 0.86,
                        minHeight: 8,
                        backgroundColor: Color.fromRGBO(15, 23, 42, 0.20),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Setting up your AGOS system...',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        height: 16 / 12,
                        color: const Color(0xFF45556C),
                      ),
                    ),
                  ],
                ),
              ),

              // Main content (scrolls under the progress section)
              Expanded(
                child: Form(
                  key: _formKey,
                  child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(25, 20, 25, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title
                      ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [
                            Color(0xFF1447E6),
                            Color(0xFF0092B8),
                            Color(0xFF1447E6),
                          ],
                        ).createShader(bounds),
                        child: Text(
                          'Device Information',
                          style: GoogleFonts.poppins(
                            fontSize: 24,
                            fontWeight: FontWeight.w400,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),

                      // Subtitle
                      Text(
                        'Edit personalized information for notification and real time alerts.',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                          color: const Color(0xFF45556C),
                        ),
                      ),
                      const SizedBox(height: 19),

                      // PERSONAL INFORMATION Section
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ShaderMask(
                          shaderCallback: (bounds) => const LinearGradient(
                            colors: [Color(0xFF1447E6), Color(0xFF0092B8)],
                          ).createShader(bounds),
                          child: Text(
                            'PERSONAL INFORMATION',
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 19),

                      // Personal Info Card
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: const Color(0xB3FFFFFF),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white, width: 1.18),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF5DADE2).withValues(alpha: 0.15),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(17.18),
                        child: Column(
                          children: [
                            _buildTextField(
                              controller: _firstNameController,
                              label: 'First Name',
                              icon: Icons.person_outline,
                              hint: 'Enter your first name',
                            ),
                            const SizedBox(height: 15),
                            _buildTextField(
                              controller: _lastNameController,
                              label: 'Last Name',
                              icon: Icons.person_outline,
                              hint: 'Enter your last name',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 19),

                      // CONTACT INFORMATION Section
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ShaderMask(
                          shaderCallback: (bounds) => const LinearGradient(
                            colors: [Color(0xFF1447E6), Color(0xFF0092B8)],
                          ).createShader(bounds),
                          child: Text(
                            'CONTACT INFORMATION',
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 19),

                      // Contact Info Card
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: const Color(0xB3FFFFFF),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0x2EFFFFFF),
                            width: 1.18,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF5DADE2).withValues(alpha: 0.15),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(17.18),
                        child: Column(
                          children: [
                            _buildTextField(
                              controller: _emailController,
                              label: 'Email Address',
                              icon: Icons.email_outlined,
                              hint: 'Enter your email address',
                              keyboardType: TextInputType.emailAddress,
                              validator: _validateEmail,
                            ),
                            const SizedBox(height: 16),
                            _buildTextField(
                              controller: _phoneController,
                              label: 'Phone Number',
                              icon: Icons.phone_outlined,
                              hint: 'Enter your phone number (optional)',
                              keyboardType: TextInputType.phone,
                              validator: _validatePhone,
                              isRequired: false,
                            ),
                            const SizedBox(height: 16),
                            _buildTextField(
                              controller: _locationController,
                              label: 'Location',
                              icon: Icons.location_on_outlined,
                              hint: 'Enter your location (optional)',
                              isRequired: false,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 25),

                      // Save Changes Button
                      SizedBox(
                        width: double.infinity,
                        height: 40,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF00B8DB), Color(0xFF155DFC)],
                            ),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: ElevatedButton(
                            onPressed: _saving ? null : _saveChanges,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: _saving
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.save, size: 16, color: Colors.white,),
                                const SizedBox(width: 8),
                                Text(
                                  'Save Changes',
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    bool isRequired = true,
  }) {
    String? composedValidator(String? value) {
      if (isRequired && (value == null || value.trim().isEmpty)) {
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
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF314158),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          validator: composedValidator,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          cursorColor: const Color(0xFF0A1929),
          cursorErrorColor: const Color(0xFF0A1929),
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: const Color(0xFF0A1929),
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            hintText: hint,
            hintStyle: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w400,
              color: const Color(0xFFADB5BD),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFA2F4FD), width: 1.18),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFF53EAFD), width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE53935), width: 1.18),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE53935), width: 1.5),
            ),
            errorStyle: GoogleFonts.inter(
              fontSize: 12,
              color: const Color(0xFFE53935),
            ),
          ),
        ),
      ],
    );
  }
}
