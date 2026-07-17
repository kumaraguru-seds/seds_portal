import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Toast Type
// ─────────────────────────────────────────────────────────────────────────────
enum ToastType { success, error, warning, info }

// ─────────────────────────────────────────────────────────────────────────────
// AppToast – global singleton service
// ─────────────────────────────────────────────────────────────────────────────
class AppToast {
  AppToast._();

  static OverlayEntry? _currentEntry;
  static Timer? _timer;

  /// Show a toast.  navigatorKey.currentContext must be non-null.
  static void show(
    BuildContext context,
    String message, {
    ToastType type = ToastType.info,
    Duration duration = const Duration(seconds: 3),
  }) {
    _timer?.cancel();
    _currentEntry?.remove();
    _currentEntry = null;

    final overlay = Overlay.of(context, rootOverlay: true);

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ToastWidget(
        message: message,
        type: type,
        onDismiss: () {
          entry.remove();
          if (_currentEntry == entry) _currentEntry = null;
        },
      ),
    );

    _currentEntry = entry;
    overlay.insert(entry);

    _timer = Timer(duration, () {
      if (_currentEntry == entry) {
        _currentEntry?.remove();
        _currentEntry = null;
      }
    });
  }

  static void success(BuildContext context, String message, {Duration duration = const Duration(seconds: 3)}) =>
      show(context, message, type: ToastType.success, duration: duration);

  static void error(BuildContext context, String message, {Duration duration = const Duration(seconds: 4)}) =>
      show(context, message, type: ToastType.error, duration: duration);

  static void warning(BuildContext context, String message, {Duration duration = const Duration(seconds: 3)}) =>
      show(context, message, type: ToastType.warning, duration: duration);

  static void info(BuildContext context, String message, {Duration duration = const Duration(seconds: 3)}) =>
      show(context, message, type: ToastType.info, duration: duration);
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal animated widget
// ─────────────────────────────────────────────────────────────────────────────
class _ToastWidget extends StatefulWidget {
  final String message;
  final ToastType type;
  final VoidCallback onDismiss;

  const _ToastWidget({
    required this.message,
    required this.type,
    required this.onDismiss,
  });

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _slideAnim = Tween<Offset>(begin: const Offset(0, -1.2), end: Offset.zero)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _fadeAnim = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeIn));
    _controller.forward();
  }

  Future<void> _dismiss() async {
    await _controller.reverse();
    widget.onDismiss();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // ── colour & icon per type ──
  Color get _accent {
    switch (widget.type) {
      case ToastType.success: return const Color(0xFF00C48C);
      case ToastType.error:   return const Color(0xFFFF5A5A);
      case ToastType.warning: return const Color(0xFFFFB347);
      case ToastType.info:    return const Color(0xFF4DA6FF);
    }
  }

  IconData get _icon {
    switch (widget.type) {
      case ToastType.success: return Icons.check_circle_rounded;
      case ToastType.error:   return Icons.error_rounded;
      case ToastType.warning: return Icons.warning_amber_rounded;
      case ToastType.info:    return Icons.info_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final poppins = GoogleFonts.poppins;
    final topPad = MediaQuery.of(context).padding.top;

    final isWindows = Platform.isWindows;
    return Positioned(
      top: topPad + 12,
      left: 16,
      right: 16,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: isWindows ? 450 : 0,
            maxWidth: isWindows ? 450 : double.infinity,
          ),
          child: SlideTransition(
            position: _slideAnim,
            child: FadeTransition(
              opacity: _fadeAnim,
              child: GestureDetector(
                onTap: _dismiss,
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF162544).withValues(alpha: 0.97),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: _accent.withValues(alpha: 0.55), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: _accent.withValues(alpha: 0.22),
                          blurRadius: 28,
                          spreadRadius: 2,
                          offset: const Offset(0, 8),
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Glowing icon
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: _accent.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(_icon, color: _accent, size: 22),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                widget.message,
                                style: poppins(
                                  fontSize: 13.5,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.1,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: _dismiss,
                              child: Icon(Icons.close_rounded, color: Colors.white38, size: 18),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        // Progress bar draining left → right
                        _DrainBar(accent: _accent),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Animated drain bar
// ─────────────────────────────────────────────────────────────────────────────
class _DrainBar extends StatefulWidget {
  final Color accent;
  const _DrainBar({required this.accent});

  @override
  State<_DrainBar> createState() => _DrainBarState();
}

class _DrainBarState extends State<_DrainBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) => ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: 1 - _ctrl.value,
          minHeight: 3,
          backgroundColor: Colors.white10,
          valueColor: AlwaysStoppedAnimation<Color>(
            widget.accent.withValues(alpha: 0.8),
          ),
        ),
      ),
    );
  }
}
