

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';
import 'main.dart';
import 'notification_service.dart';
import 'app_toast.dart';
import 'reset_password.dart';
import 'user_profile_details_form_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _rememberMe = false;
  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMessage;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));
    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLoginSuccess(UserData userData, Map<String, dynamic> data) async {
    await saveUserSession(data['token'], data['session_id'], data['user']);
    // Initialize FCM and register device token with backend
    await NotificationService().init(userEmail: userData.email);

    if (!mounted) return;
    AppToast.success(context, 'Welcome back, ${userData.name}! 👋');
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;

    setState(() => _isLoading = true); // show progress during db check
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('profile_completed_${userData.email}') ?? false) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => MainPage(userData: userData)),
        );
        return;
      }
    } catch (e) {
      debugPrint('SharedPreferences read error: $e');
    }

    bool shouldRedirect = false;
    try {
      final res = await http.get(
        Uri.parse('$apiBaseUrl/api/user/details?email=${Uri.encodeComponent(userData.email)}'),
      ).timeout(const Duration(seconds: 7));
      if (res.statusCode == 200) {
        final detailData = jsonDecode(res.body);
        if (detailData['success'] == true && detailData['details'] != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('profile_completed_${userData.email}', true);
          if (!mounted) return;
          setState(() => _isLoading = false);
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => MainPage(userData: userData)),
          );
          return;
        } else {
          shouldRedirect = true;
        }
      }
    } catch (e) {
      debugPrint('Error checking user details: $e');
    }

    if (!mounted) return;
    setState(() => _isLoading = false);
    if (shouldRedirect) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => DesktopPageWrapper(child: UserProfileDetailsFormPage(userData: userData)),
        ),
      );
    } else {
      // Fallback: server/connection issue, let them enter MainPage
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => MainPage(userData: userData)),
      );
    }
  }

  Future<void> _handleLogin() async {
    setState(() => _errorMessage = null);
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final String email = _identifierController.text.trim();
    final String password = _passwordController.text.trim();

    try {
      // Connect to the remote AWS PostgreSQL backend
      final response = await http.post(
        Uri.parse('$apiBaseUrl/api/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      ).timeout(const Duration(seconds: 30));

      if (!mounted) return;
      setState(() => _isLoading = false);

      final Map<String, dynamic> data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        final userData = UserData.fromJson(data['user']);
        await _handleLoginSuccess(userData, data);
      } else {
        setState(() {
          _errorMessage = data['message'] ?? 'Invalid email or password.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Could not connect to SEDS backend. Please try again.';
      });
      debugPrint('Login Connection Error: $e');
    }
  }

  Future<void> _handleBiometrics() async {
    final LocalAuthentication auth = LocalAuthentication();
    try {
      final isSupported = await auth.isDeviceSupported() || await auth.canCheckBiometrics;
      if (!isSupported) {
        if (!mounted) return;
        AppToast.warning(context, 'Biometrics not supported or not set up on this device.');
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final hasToken = prefs.getBool('biometric_enabled') ?? false;
      final savedEmail = prefs.getString('biometric_email') ?? '';
      final savedToken = prefs.getString('biometric_key') ?? '';

      if (!hasToken || savedEmail.isEmpty || savedToken.isEmpty) {
        if (!mounted) return;
        AppToast.warning(
          context,
          'No registered Face / Fingerprint login found. Please sign in with your email/password first and enable Face / Fingerprint Login in your Profile settings.',
          duration: const Duration(seconds: 5),
        );
        return;
      }

      final authenticated = await auth.authenticate(
        localizedReason: 'Scan Face or Fingerprint to log in to SEDS Portal',
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );

      if (authenticated) {
        if (!mounted) return;
        setState(() {
          _isLoading = true;
          _errorMessage = null;
        });

        final res = await http.post(
          Uri.parse('$apiBaseUrl/api/biometric/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': savedEmail,
            'biometricToken': savedToken,
          }),
        ).timeout(const Duration(seconds: 20));

        if (!mounted) return;
        setState(() => _isLoading = false);

        final data = jsonDecode(res.body);
        if (res.statusCode == 200 && data['success'] == true) {
          final userData = UserData.fromJson(data['user']);
          await _handleLoginSuccess(userData, data);
        } else {
          setState(() {
            _errorMessage = data['message'] ?? 'Biometric login verification failed.';
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Biometric login error. Please try again.';
      });
      debugPrint('Biometric Login Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final poppins = GoogleFonts.poppins;

    final bool isWindows = Platform.isWindows;
    return Scaffold(
      backgroundColor: isWindows ? const Color(0xFFF1F5F9) : const Color(0xFF0D1E3A),
      resizeToAvoidBottomInset: false,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.opaque,
        child: Stack(
          children: [
            // ── Fixed Background Image ──
            Positioned.fill(
              child: isWindows
                  ? Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFFF8FAFC), Color(0xFFE2E8F0)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                    )
                  : Image.asset(
                      'assets/background.png',
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(color: const Color(0xFF0D1E3A));
                      },
                    ),
            ),
            // ── Dim overlay ──
            Positioned.fill(
              child: isWindows
                  ? const SizedBox.shrink()
                  : Container(color: Colors.black.withValues(alpha: 0.45)),
            ),

            // ── Content ──
            Positioned.fill(
              child: SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: isWindows ? 500 : 460),
                    child: DesktopFormWrapper(
                      isWindows: isWindows,
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: EdgeInsets.only(
                          left: 24,
                          right: 24,
                          top: 32,
                          bottom: MediaQuery.of(context).viewInsets.bottom + 32,
                        ),
                        child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: SlideTransition(
                        position: _slideAnimation,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // ── Logo (plain) ──
                            Image.asset(
                              'assets/logo.png',
                              height: 90,
                            ),
                            const SizedBox(height: 18),

                            // ── Title ──
                            Text(
                              'Kumaraguru SEDS',
                              style: poppins(
                                fontSize: 26,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF4DA6FF),
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Sign in to your portal',
                              style: poppins(
                                fontSize: 13.5,
                                color: const Color(0xFFC9D1E6),
                                fontWeight: FontWeight.w300,
                              ),
                            ),
                            const SizedBox(height: 30),

                            // ── Glass Card ──
                            Container(
                              constraints: const BoxConstraints(maxWidth: 420),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.18),
                                  width: 1.2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.5),
                                    blurRadius: 30,
                                    spreadRadius: 4,
                                  ),
                                ],
                              ),
                              padding: const EdgeInsets.all(28),
                              child: Form(
                                key: _formKey,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // ── Hint row ──
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.06),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: const Color(0xFF4DA6FF).withValues(alpha: 0.35),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.info_outline_rounded,
                                            color: Color(0xFF4DA6FF),
                                            size: 16,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              'Login with email, roll number, or username',
                                              style: poppins(
                                                fontSize: 11.5,
                                                color: const Color(0xFF4DA6FF),
                                                fontWeight: FontWeight.w400,
                                              ),
                                              overflow: TextOverflow.visible,
                                              softWrap: true,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 16),

                                    // ── Identifier field ──
                                    _buildInputField(
                                      controller: _identifierController,
                                      hint: 'Email / Roll Number / Username',
                                      prefixIcon: Icons.person_outline_rounded,
                                      poppins: poppins,
                                      validator: (v) =>
                                          (v == null || v.trim().isEmpty)
                                              ? 'Please enter your identifier'
                                              : null,
                                    ),
                                    const SizedBox(height: 14),

                                    // ── Password field ──
                                    _buildInputField(
                                      controller: _passwordController,
                                      hint: 'Password',
                                      prefixIcon: Icons.lock_outline_rounded,
                                      poppins: poppins,
                                      obscure: _obscurePassword,
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          _obscurePassword
                                              ? Icons.visibility_off_outlined
                                              : Icons.visibility_outlined,
                                          color: const Color(0xFFC9D1E6),
                                          size: 20,
                                        ),
                                        onPressed: () => setState(
                                          () => _obscurePassword = !_obscurePassword,
                                        ),
                                      ),
                                      validator: (v) => (v == null || v.isEmpty)
                                          ? 'Please enter your password'
                                          : null,
                                    ),
                                    const SizedBox(height: 14),

                                    // ── Remember me + Forgot password ──
                                    Row(
                                      children: [
                                        SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: Checkbox(
                                            value: _rememberMe,
                                            onChanged: (v) =>
                                                setState(() => _rememberMe = v!),
                                            activeColor: const Color(0xFF4DA6FF),
                                            checkColor: Colors.black,
                                            side: const BorderSide(
                                              color: Color(0xFF4DA6FF),
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Remember me',
                                          style: poppins(
                                            fontSize: 12.5,
                                            color: const Color(0xFFC9D1E6),
                                          ),
                                        ),
                                        const Spacer(),
                                        GestureDetector(
                                          onTap: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => const ForgotPasswordPage(),
                                              ),
                                            );
                                          },
                                          child: Text(
                                            'Forgot Password?',
                                            style: poppins(
                                              fontSize: 12.5,
                                              color: const Color(0xFF4DA6FF),
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 22),

                                    // ── Error message ──
                                    if (_errorMessage != null) ...[
                                      Text(
                                        _errorMessage!,
                                        style: poppins(
                                          fontSize: 12,
                                          color: const Color(0xFFFF6B6B),
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                    ],

                                    // ── Sign In button ──
                                    SizedBox(
                                      width: double.infinity,
                                      height: 52,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(
                                            colors: [
                                              Color(0xFF4B6EF5),
                                              Color(0xFF00C8FF),
                                            ],
                                            begin: Alignment.centerLeft,
                                            end: Alignment.centerRight,
                                          ),
                                          borderRadius: BorderRadius.circular(12),
                                          boxShadow: [
                                            BoxShadow(
                                              color: const Color(0xFF4B6EF5).withValues(alpha: 0.45),
                                              blurRadius: 16,
                                              spreadRadius: 1,
                                              offset: const Offset(0, 4),
                                            ),
                                          ],
                                        ),
                                        child: ElevatedButton(
                                          onPressed: _isLoading ? null : _handleLogin,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.transparent,
                                            shadowColor: Colors.transparent,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                          ),
                                          child: _isLoading
                                              ? const SizedBox(
                                                  width: 22,
                                                  height: 22,
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2.5,
                                                    color: Colors.white,
                                                  ),
                                                )
                                              : Row(
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    Text(
                                                      'Sign In',
                                                      style: poppins(
                                                        fontSize: 16,
                                                        fontWeight: FontWeight.w700,
                                                        color: Colors.white,
                                                        letterSpacing: 0.5,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    const Icon(
                                                      Icons.arrow_forward_rounded,
                                                      color: Colors.white,
                                                      size: 20,
                                                    ),
                                                  ],
                                                ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 14),

                                    // ── Biometrics button ──
                                    SizedBox(
                                      width: double.infinity,
                                      height: 50,
                                      child: OutlinedButton(
                                        onPressed: _handleBiometrics,
                                        style: OutlinedButton.styleFrom(
                                          side: BorderSide(
                                            color: const Color(0xFF4DA6FF).withValues(alpha: 0.55),
                                            width: 1.3,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            const Icon(
                                              Icons.fingerprint_rounded,
                                              color: Color(0xFF4DA6FF),
                                              size: 22,
                                            ),
                                            const SizedBox(width: 10),
                                            Text(
                                              'Login with Biometrics',
                                              style: poppins(
                                                fontSize: 14,
                                                color: const Color(0xFF4DA6FF),
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 14),

                                    // ── Continue as Guest Button ──
                                    SizedBox(
                                      width: double.infinity,
                                      child: TextButton(
                                        onPressed: () {
                                          Navigator.pushReplacement(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) => const MainPage(userData: null),
                                            ),
                                          );
                                        },
                                        child: Text(
                                          'Continue as Guest',
                                          style: poppins(
                                            fontSize: 14,
                                            color: const Color(0xFF4DA6FF),
                                            fontWeight: FontWeight.w600,
                                            decoration: TextDecoration.underline,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 28),

                            // ── Footer ──
                            Text(
                              'Kumaraguru SEDS • Enterprise Portal v1.0',
                              style: poppins(
                                fontSize: 11,
                                color: Colors.white.withValues(alpha: 0.35),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String hint,
    required IconData prefixIcon,
    required TextStyle Function({
      Color? color,
      double? fontSize,
      FontWeight? fontWeight,
      double? letterSpacing,
    }) poppins,
    bool obscure = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      style: poppins(fontSize: 14, color: Colors.white),
      validator: validator,
      decoration: InputDecoration(
        labelText: hint,
        labelStyle: poppins(
          fontSize: 14,
          color: const Color(0xFFC9D1E6),
          fontWeight: FontWeight.w300,
        ),
        floatingLabelStyle: poppins(
          fontSize: 12,
          color: const Color(0xFF4DA6FF),
          fontWeight: FontWeight.w500,
        ),
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        prefixIcon: Icon(prefixIcon, color: const Color(0xFFC9D1E6), size: 20),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.10),
        contentPadding: const EdgeInsets.symmetric(
          vertical: 16,
          horizontal: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: Colors.white.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: Colors.white.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF4DA6FF), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFFF6B6B), width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFFF6B6B), width: 1.5),
        ),
        errorStyle: poppins(fontSize: 11, color: const Color(0xFFFF6B6B)),
      ),
    );
  }
}

class DesktopFormWrapper extends StatelessWidget {
  final Widget child;
  final bool isWindows;
  const DesktopFormWrapper({super.key, required this.child, required this.isWindows});

  @override
  Widget build(BuildContext context) {
    if (!isWindows) {
      return child;
    }
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1E3A),
          borderRadius: BorderRadius.circular(20),
          image: const DecorationImage(
            image: AssetImage('assets/background.png'),
            fit: BoxFit.cover,
            opacity: 0.55,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 24,
              spreadRadius: 4,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}
