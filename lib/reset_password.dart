import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'main.dart';
import 'app_toast.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ForgotPasswordPage — 2-step animated OTP reset flow
// ─────────────────────────────────────────────────────────────────────────────
class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage>
    with TickerProviderStateMixin {
  // ── Step control ──
  int _step = 1; // 1 = email, 2 = OTP + new password
  String _resetPurpose = 'password_reset'; // 'password_reset' or 'biometrics_reset'

  // ── Controllers ──
  final _emailCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();

  // ── State ──
  bool _isLoading = false;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  String _sentEmail = '';

  // ── Countdown timer (2 min = 120 s) ──
  Timer? _countdownTimer;
  int _secondsLeft = 120;
  bool get _canResend => _secondsLeft <= 0;

  // ── Animations ──
  late AnimationController _enterCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _enterCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(parent: _enterCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(parent: _enterCtrl, curve: Curves.easeOut));
    _enterCtrl.forward();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _otpCtrl.dispose();
    _newPassCtrl.dispose();
    _confirmPassCtrl.dispose();
    _countdownTimer?.cancel();
    _enterCtrl.dispose();
    super.dispose();
  }

  // ── Countdown start ──
  void _startCountdown() {
    _secondsLeft = 120;
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) t.cancel();
    });
  }

  // ── Animate transition to step 2 ──
  Future<void> _goToStep2(String email) async {
    await _enterCtrl.reverse();
    setState(() {
      _step = 2;
      _sentEmail = email;
    });
    _enterCtrl.forward();
    _startCountdown();
  }

  // ── Step 1: Request OTP ──
  Future<void> _requestOtp() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      AppToast.warning(context, 'Please enter a valid email address.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final res = await http.post(
        Uri.parse('$apiBaseUrl/api/reset-password/request'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'purpose': _resetPurpose,
        }),
      ).timeout(const Duration(seconds: 20));

      if (!mounted) return;
      setState(() => _isLoading = false);

      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['success'] == true) {
        AppToast.success(context, 'OTP sent! Check your email inbox.');
        await _goToStep2(email);
      } else {
        AppToast.error(context, data['message'] ?? 'Failed to send OTP.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      AppToast.error(context, 'Connection error. Please try again.');
    }
  }

  // ── Step 1 resend (reuse same fn) ──
  Future<void> _resendOtp() async {
    if (!_canResend) return;
    await _requestOtp();
    _startCountdown();
  }

  // ── Step 2: Verify OTP + Set new password OR Reset Biometrics ──
  Future<void> _verifyAndReset() async {
    final otp = _otpCtrl.text.trim();
    final newPass = _newPassCtrl.text.trim();
    final confirmPass = _confirmPassCtrl.text.trim();

    if (otp.length != 6) {
      AppToast.warning(context, 'Please enter the 6-digit OTP.');
      return;
    }

    if (_resetPurpose == 'password_reset') {
      if (newPass.length < 4) {
        AppToast.warning(context, 'Password must be at least 4 characters.');
        return;
      }
      if (newPass != confirmPass) {
        AppToast.error(context, 'Passwords do not match.');
        return;
      }
    }

    setState(() => _isLoading = true);
    try {
      final payload = {
        'email': _sentEmail,
        'otp': otp,
        'actionType': _resetPurpose,
      };
      if (_resetPurpose == 'password_reset') {
        payload['newPassword'] = newPass;
      }

      final res = await http.post(
        Uri.parse('$apiBaseUrl/api/reset-password/verify'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 20));

      if (!mounted) return;
      setState(() => _isLoading = false);

      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['success'] == true) {
        final successMsg = _resetPurpose == 'biometrics_reset'
            ? 'Biometrics login settings reset successfully!'
            : 'Password reset successfully! You can now log in.';
        AppToast.success(
          context,
          successMsg,
          duration: const Duration(seconds: 4),
        );
        await Future.delayed(const Duration(milliseconds: 800));
        if (mounted) Navigator.pop(context);
      } else {
        AppToast.error(context, data['message'] ?? 'Verification failed.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      AppToast.error(context, 'Connection error. Please try again.');
    }
  }

  // ── Countdown label ──
  String get _countdownLabel {
    if (_secondsLeft <= 0) return 'OTP expired';
    final m = _secondsLeft ~/ 60;
    final s = _secondsLeft % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Color get _countdownColor {
    if (_secondsLeft <= 0) return const Color(0xFFFF6B6B);
    if (_secondsLeft <= 30) return const Color(0xFFFFB347);
    return const Color(0xFF00C48C);
  }

  @override
  Widget build(BuildContext context) {
    final poppins = GoogleFonts.poppins;
    final topPad = MediaQuery.of(context).padding.top;
    final bool isWindows = Platform.isWindows;

    return Scaffold(
      backgroundColor: isWindows ? const Color(0xFFF1F5F9) : const Color(0xFF0D1E3A),
      resizeToAvoidBottomInset: true,
      body: Stack(
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
                : Container(color: Colors.black.withValues(alpha: 0.55)),
          ),

          SafeArea(
            bottom: false,
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: isWindows ? 500 : 460),
                child: DesktopFormWrapper(
                  isWindows: isWindows,
                  child: SingleChildScrollView(
                    padding: EdgeInsets.only(
                      left: 24,
                      right: 24,
                      top: topPad > 20 ? 8 : 20,
                      bottom: MediaQuery.of(context).padding.bottom + 32,
                    ),
                    child: FadeTransition(
                      opacity: _fadeAnim,
                child: SlideTransition(
                  position: _slideAnim,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Back Button ──
                      IconButton(
                        onPressed: () {
                          if (_step == 2) {
                            _countdownTimer?.cancel();
                            _enterCtrl.reverse().then((_) {
                              if (mounted) {
                                setState(() => _step = 1);
                                _enterCtrl.forward();
                              }
                            });
                          } else {
                            Navigator.pop(context);
                          }
                        },
                        icon: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: Colors.white,
                        ),
                        padding: EdgeInsets.zero,
                      ),
                      const SizedBox(height: 20),

                      // ── Header ──
                      _buildHeader(poppins),
                      const SizedBox(height: 32),

                      // ── Step Indicator ──
                      _buildStepIndicator(poppins),
                      const SizedBox(height: 32),

                      // ── Card ──
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF4B6EF5).withValues(alpha: 0.12),
                              blurRadius: 32,
                              spreadRadius: 2,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(24),
                        child: _step == 1
                            ? _buildStep1(poppins)
                            : _buildStep2(poppins),
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
      ],
    ),
  );
}

  Widget _buildHeader(TextStyle Function({Color? color, double? fontSize, FontWeight? fontWeight, double? letterSpacing}) poppins) {
    final title = _resetPurpose == 'biometrics_reset' ? 'Reset Biometrics' : 'Reset Password';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Lock icon with glow
        Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF4B6EF5), Color(0xFF00C8FF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF4B6EF5).withValues(alpha: 0.5),
                blurRadius: 20,
                spreadRadius: 2,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Icon(
            _resetPurpose == 'biometrics_reset' ? Icons.fingerprint_rounded : Icons.lock_reset_rounded,
            color: Colors.white,
            size: 30,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          title,
          style: poppins(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _step == 1
              ? 'Enter your registered email to receive a\n6-digit OTP code.'
              : 'Enter the OTP sent to\n$_sentEmail',
          style: poppins(
            fontSize: 13.5,
            color: const Color(0xFF8A9CC2),
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }

  Widget _buildStepIndicator(TextStyle Function({Color? color, double? fontSize, FontWeight? fontWeight, double? letterSpacing}) poppins) {
    return Row(
      children: [
        _stepDot(1, 'Email', poppins),
        Expanded(
          child: Container(
            height: 2,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _step >= 2
                    ? [const Color(0xFF4B6EF5), const Color(0xFF00C8FF)]
                    : [Colors.white12, Colors.white12],
              ),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ),
        _stepDot(2, _resetPurpose == 'biometrics_reset' ? 'OTP Verification' : 'OTP & Password', poppins),
      ],
    );
  }

  Widget _stepDot(int num, String label,
      TextStyle Function({Color? color, double? fontSize, FontWeight? fontWeight, double? letterSpacing}) poppins) {
    final isActive = _step >= num;
    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut,
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            gradient: isActive
                ? const LinearGradient(
                    colors: [Color(0xFF4B6EF5), Color(0xFF00C8FF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: isActive ? null : Colors.white12,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: const Color(0xFF4B6EF5).withValues(alpha: 0.4),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              '$num',
              style: poppins(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isActive ? Colors.white : Colors.white38,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: poppins(
            fontSize: 10.5,
            color: isActive ? const Color(0xFF4DA6FF) : Colors.white38,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // ── STEP 1 — Email form ──
  Widget _buildStep1(TextStyle Function({Color? color, double? fontSize, FontWeight? fontWeight, double? letterSpacing}) poppins) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Purpose Segment Control ──
        Text(
          'RESET PURPOSE',
          style: poppins(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF8A9CC2),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _resetPurpose = 'password_reset'),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: _resetPurpose == 'password_reset'
                        ? const Color(0xFF4B6EF5).withValues(alpha: 0.15)
                        : Colors.white.withValues(alpha: 0.03),
                    border: Border.all(
                      color: _resetPurpose == 'password_reset'
                          ? const Color(0xFF4DA6FF)
                          : Colors.white.withValues(alpha: 0.08),
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      'Password',
                      style: poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: _resetPurpose == 'password_reset' ? Colors.white : Colors.white38,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _resetPurpose = 'biometrics_reset'),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: _resetPurpose == 'biometrics_reset'
                        ? const Color(0xFF4B6EF5).withValues(alpha: 0.15)
                        : Colors.white.withValues(alpha: 0.03),
                    border: Border.all(
                      color: _resetPurpose == 'biometrics_reset'
                          ? const Color(0xFF4DA6FF)
                          : Colors.white.withValues(alpha: 0.08),
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      'Biometrics',
                      style: poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: _resetPurpose == 'biometrics_reset' ? Colors.white : Colors.white38,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        Text(
          'Email Address',
          style: poppins(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF4DA6FF),
          ),
        ),
        const SizedBox(height: 10),
        _buildTextField(
          controller: _emailCtrl,
          hint: 'Enter your registered email',
          icon: Icons.email_outlined,
          inputType: TextInputType.emailAddress,
          poppins: poppins,
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF4B6EF5), Color(0xFF00C8FF)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF4B6EF5).withValues(alpha: 0.45),
                  blurRadius: 18,
                  spreadRadius: 1,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: ElevatedButton(
              onPressed: _isLoading ? null : _requestOtp,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
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
                          'Send OTP',
                          style: poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.send_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }

  // ── STEP 2 — OTP + new password form ──
  Widget _buildStep2(TextStyle Function({Color? color, double? fontSize, FontWeight? fontWeight, double? letterSpacing}) poppins) {
    final btnText = _resetPurpose == 'biometrics_reset' ? 'Reset Biometrics' : 'Reset Password';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Countdown ──
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: BoxDecoration(
            color: _countdownColor.withValues(alpha: 0.08),
            border: Border.all(color: _countdownColor.withValues(alpha: 0.35), width: 1.3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                _secondsLeft <= 0
                    ? Icons.timer_off_rounded
                    : Icons.timer_rounded,
                color: _countdownColor,
                size: 20,
              ),
              const SizedBox(width: 10),
              Text(
                _secondsLeft <= 0
                    ? 'OTP expired — please resend'
                    : 'OTP expires in $_countdownLabel',
                style: poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _countdownColor,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // ── OTP Field ──
        Text('6-Digit OTP',
            style: poppins(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF4DA6FF))),
        const SizedBox(height: 10),
        TextFormField(
          controller: _otpCtrl,
          keyboardType: TextInputType.number,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          textAlign: TextAlign.center,
          style: poppins(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: 10,
          ),
          decoration: InputDecoration(
            counterText: '',
            hintText: '• • • • • •',
            hintStyle: poppins(fontSize: 22, color: Colors.white24, letterSpacing: 8),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.07),
            contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF4DA6FF), width: 1.8),
            ),
          ),
        ),
        const SizedBox(height: 22),

        if (_resetPurpose == 'password_reset') ...[
          // ── New Password ──
          Text('New Password',
              style: poppins(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF4DA6FF))),
          const SizedBox(height: 10),
          _buildTextField(
            controller: _newPassCtrl,
            hint: 'Enter new password',
            icon: Icons.lock_outline_rounded,
            obscure: _obscureNew,
            poppins: poppins,
            suffix: IconButton(
              icon: Icon(
                _obscureNew ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                color: Colors.white38,
                size: 20,
              ),
              onPressed: () => setState(() => _obscureNew = !_obscureNew),
            ),
          ),
          const SizedBox(height: 18),

          // ── Confirm Password ──
          Text('Confirm New Password',
              style: poppins(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF4DA6FF))),
          const SizedBox(height: 10),
          _buildTextField(
            controller: _confirmPassCtrl,
            hint: 'Re-enter new password',
            icon: Icons.lock_outline_rounded,
            obscure: _obscureConfirm,
            poppins: poppins,
            suffix: IconButton(
              icon: Icon(
                _obscureConfirm ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                color: Colors.white38,
                size: 20,
              ),
              onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
            ),
          ),
          const SizedBox(height: 28),
        ],

        // ── Reset Button ──
        SizedBox(
          width: double.infinity,
          height: 52,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF00C48C), Color(0xFF00E5C7)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00C48C).withValues(alpha: 0.4),
                  blurRadius: 18,
                  spreadRadius: 1,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: ElevatedButton(
              onPressed: _isLoading ? null : _verifyAndReset,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
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
                          btnText,
                          style: poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.check_circle_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ],
                    ),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ── Resend ──
        Center(
          child: TextButton(
            onPressed: _canResend ? _resendOtp : null,
            child: Text(
              _canResend ? 'Resend OTP' : 'Resend OTP in $_countdownLabel',
              style: poppins(
                fontSize: 13,
                color: _canResend ? const Color(0xFF4DA6FF) : Colors.white30,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Reusable text field ──
  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required TextStyle Function({Color? color, double? fontSize, FontWeight? fontWeight, double? letterSpacing}) poppins,
    bool obscure = false,
    Widget? suffix,
    TextInputType inputType = TextInputType.text,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: inputType,
      style: poppins(fontSize: 14, color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: poppins(fontSize: 13, color: Colors.white30, fontWeight: FontWeight.w400),
        prefixIcon: Icon(icon, color: const Color(0xFFC9D1E6), size: 20),
        suffixIcon: suffix,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.07),
        contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF4DA6FF), width: 1.6),
        ),
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
