import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../../data/services/firestore_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  bool _googleLoading = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  /// Navigate to home or setup wizard depending on whether the user has a device.
  Future<void> _navigateAfterLogin(String uid) async {
    if (!mounted) return;
    final hasDevice = await FirestoreService().hasLinkedDevice(uid);
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(
      hasDevice ? '/home' : '/welcome',
      (_) => false,
    );
  }

  /// Returns true if Google Sign-In is supported on the current platform.
  bool get _googleSignInSupported =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> _signInWithGoogle() async {
    if (!_googleSignInSupported) return;
    setState(() => _googleLoading = true);
    try {
      if (kIsWeb) {
        // Web: use Firebase popup flow
        final provider = GoogleAuthProvider();
        await FirebaseAuth.instance.signInWithPopup(provider);
      } else {
        // Mobile: use google_sign_in package
        await GoogleSignIn().signOut();
        final googleUser = await GoogleSignIn().signIn();
        if (googleUser == null) {
          setState(() => _googleLoading = false);
          return; // user cancelled
        }
        final googleAuth = await googleUser.authentication;
        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        await FirebaseAuth.instance.signInWithCredential(credential);
      }
      if (!mounted) return;
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      await _navigateAfterLogin(uid);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message ?? 'Google sign in failed.'),
          backgroundColor: const Color(0xFFE74C3C),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Google sign in failed: $e'),
          backgroundColor: const Color(0xFFE74C3C),
        ),
      );
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );
      if (!mounted) return;
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      await _navigateAfterLogin(uid);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      final msg = switch (e.code) {
        'user-not-found' => 'No account found for that email.',
        'wrong-password' => 'Incorrect password.',
        'invalid-email' => 'Invalid email address.',
        'user-disabled' => 'This account has been disabled.',
        'too-many-requests' => 'Too many attempts. Try again later.',
        _ => e.message ?? 'Sign in failed.',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: const Color(0xFFE74C3C)),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment(-0.5, -1),
            end: Alignment(0.5, 1),
            colors: [
              Color(0xFFF8FAFC),
              Color(0xFFEFF6FF),
              Color(0xFFECFEFF),
            ],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Logo
                    Center(
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFF00D3F2),
                              Color(0xFF2B7FFF),
                              Color(0xFF9810FA),
                            ],
                            stops: [0.0, 0.5, 1.0],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  const Color(0xFF22D3EE).withValues(alpha: 0.37),
                              blurRadius: 24,
                              spreadRadius: 0,
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // large soft glow
                              ImageFiltered(
                                imageFilter:
                                    ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                                child: Opacity(
                                  opacity: 0.85,
                                  child: SvgPicture.asset(
                                    'assets/svg/agos_square_logo.svg',
                                    fit: BoxFit.contain,
                                    colorFilter: const ColorFilter.mode(
                                        Colors.white, BlendMode.srcIn),
                                  ),
                                ),
                              ),
                              // subtle inner halo
                              ImageFiltered(
                                imageFilter:
                                    ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                                child: Opacity(
                                  opacity: 0.35,
                                  child: SvgPicture.asset(
                                    'assets/svg/agos_square_logo.svg',
                                    fit: BoxFit.contain,
                                    colorFilter: const ColorFilter.mode(
                                        Colors.white, BlendMode.srcIn),
                                  ),
                                ),
                              ),
                              // crisp foreground logo
                              SvgPicture.asset(
                                'assets/svg/agos_square_logo.svg',
                                fit: BoxFit.contain,
                                colorFilter: const ColorFilter.mode(
                                    Colors.white, BlendMode.srcIn),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Title
                    ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [Color(0xFF1447E6), Color(0xFF0092B8)],
                      ).createShader(bounds),
                      child: Text(
                        'Welcome Back',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          fontSize: 28,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Sign in to your AGOS account',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                        color: const Color(0xFF45556C),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Card
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.7),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color:
                                const Color(0xFF5DADE2).withValues(alpha: 0.12),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Email
                          _buildLabel('Email'),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            decoration: _inputDecoration(
                              'Enter your email',
                              Icons.email_outlined,
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Email is required';
                              }
                              if (!v.contains('@')) return 'Enter a valid email';
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          // Password
                          _buildLabel('Password'),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _passwordCtrl,
                            obscureText: _obscure,
                            decoration: _inputDecoration(
                              'Enter your password',
                              Icons.lock_outline,
                            ).copyWith(
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  color: const Color(0xFF9CB3C9),
                                  size: 20,
                                ),
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                              ),
                            ),
                            validator: (v) {
                              if (v == null || v.isEmpty) {
                                return 'Password is required';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 8),

                          // Forgot password
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () =>
                                  Navigator.pushNamed(context, '/forgot-password'),
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text(
                                'Forgot Password?',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: const Color(0xFF155DFC),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Sign In button
                          _buildGradientButton(
                            label: 'Sign In',
                            loading: _loading,
                            onPressed: _signIn,
                          ),
                          const SizedBox(height: 20),

                          // OR divider + Google Sign-In (mobile only)
                          if (_googleSignInSupported) ...[
                            Row(
                              children: [
                                const Expanded(child: Divider(color: Color(0xFFE2EBF3))),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  child: Text('or',
                                      style: GoogleFonts.inter(
                                          fontSize: 13,
                                          color: const Color(0xFF9CB3C9))),
                                ),
                                const Expanded(child: Divider(color: Color(0xFFE2EBF3))),
                              ],
                            ),
                            const SizedBox(height: 14),

                            // Google Sign-In button
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: OutlinedButton.icon(
                                onPressed: _googleLoading ? null : _signInWithGoogle,
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  side: const BorderSide(color: Color(0xFFE2EBF3)),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14)),
                                  elevation: 0,
                                ),
                                icon: _googleLoading
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Color(0xFF4285F4)),
                                      )
                                    : Image.network(
                                        'https://upload.wikimedia.org/wikipedia/commons/thumb/c/c1/Google_%22G%22_logo.svg/240px-Google_%22G%22_logo.svg.png',
                                        width: 22,
                                        height: 22,
                                      ),
                                label: Text(
                                  'Continue with Google',
                                  style: GoogleFonts.inter(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF1D293D),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Register link
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "Don't have an account? ",
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: const Color(0xFF45556C),
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              Navigator.pushNamed(context, '/register'),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            'Register',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF155DFC),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: const Color(0xFF1D293D),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.inter(
        fontSize: 14,
        color: const Color(0xFF9CB3C9),
      ),
      prefixIcon: Icon(icon, color: const Color(0xFF9CB3C9), size: 20),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2EBF3)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2EBF3)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF00B8DB), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE74C3C)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE74C3C), width: 1.5),
      ),
    );
  }

  Widget _buildGradientButton({
    required String label,
    required bool loading,
    required VoidCallback onPressed,
  }) {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF00B8DB), Color(0xFF155DFC)],
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00B8DB).withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          shadowColor: Colors.transparent,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
      ),
    );
  }
}
