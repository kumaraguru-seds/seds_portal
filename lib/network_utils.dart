import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'app_toast.dart';

class NetworkUtils {
  NetworkUtils._();

  /// Checks if the device has a working internet connection.
  /// Works Web-safely.
  static Future<bool> hasConnection() async {
    if (kIsWeb) return true;
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 3));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Verifies connectivity and shows an error Toast notification if the user is offline.
  /// Returns the online status.
  static Future<bool> checkConnection(BuildContext context) async {
    final hasInternet = await hasConnection();
    if (!hasInternet && context.mounted) {
      AppToast.error(
        context,
        'No Internet Connection. Please turn on your internet connection.',
      );
    }
    return hasInternet;
  }
}

class NetworkAwareWidget extends StatefulWidget {
  final Widget child;
  const NetworkAwareWidget({super.key, required this.child});

  @override
  State<NetworkAwareWidget> createState() => _NetworkAwareWidgetState();
}

class _NetworkAwareWidgetState extends State<NetworkAwareWidget> {
  late StreamSubscription<List<ConnectivityResult>> _subscription;
  bool _isConnected = true;
  bool _showBackOnline = false;
  Timer? _onlineTimer;

  @override
  void initState() {
    super.initState();
    _checkInitial();
    _subscription = Connectivity().onConnectivityChanged.listen((results) async {
      final isConnected = await NetworkUtils.hasConnection();
      _handleConnectionChange(isConnected);
    });
  }

  Future<void> _checkInitial() async {
    final isConnected = await NetworkUtils.hasConnection();
    if (mounted) {
      setState(() {
        _isConnected = isConnected;
      });
    }
  }

  void _handleConnectionChange(bool isConnected) {
    if (isConnected == _isConnected) return;

    setState(() {
      _isConnected = isConnected;
      if (isConnected) {
        _showBackOnline = true;
        _onlineTimer?.cancel();
        _onlineTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() {
              _showBackOnline = false;
            });
          }
        });
      } else {
        _showBackOnline = false;
      }
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    _onlineTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final poppins = GoogleFonts.poppins;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          widget.child,
          if (!_isConnected)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Material(
                color: const Color(0xFFE74C3C), // YouTube/Chrome-style bright red
                child: SafeArea(
                  top: false,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.wifi_off_rounded, color: Colors.white, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          'No internet connection.',
                          style: poppins(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          else if (_showBackOnline)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Material(
                color: const Color(0xFF2ECC71), // green
                child: SafeArea(
                  top: false,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.wifi_rounded, color: Colors.white, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          'Back online.',
                          style: poppins(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
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
    );
  }
}
