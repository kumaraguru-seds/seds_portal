// ─────────────────────────────────────────────────────────────────────────────
// background_service.dart
//
// Persistent background location tracker for SEDS Portal.
// • Starts automatically when a work session begins (_startWork called)
// • Posts live GPS coordinates to the backend every 5 seconds
// • Survives app minimisation and "logout" (UI navigation) because it runs
//   in a separate Android foreground-service process
// • Stops automatically when the work session ends (_stopWork called)
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' as dart_io;

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ── Notification channel for the persistent foreground notification ──────────
const String _channelId   = 'seds_location_tracking';
const String _channelName = 'SEDS Location Tracking';
const int    _notifId     = 8888;

// ── API base URL — must match the HTTPS base in main.dart ───────────────────
const String _apiBase = 'https://portal.kumaraguruseds.space';

// ─────────────────────────────────────────────────────────────────────────────
// initBackgroundService  ─ call once at app launch (before runApp)
// ─────────────────────────────────────────────────────────────────────────────
Future<void> initBackgroundService() async {
  try {
    final service = FlutterBackgroundService();

    // Stop any stale service before re-configuring so that old callback handles
    // (which could point to a non-existent function) are cleared.
    if (await service.isRunning()) {
      service.invoke('stop');
      await Future.delayed(const Duration(milliseconds: 300));
    }

    // Create the Android notification channel
    final notificationsPlugin = FlutterLocalNotificationsPlugin();
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: 'Tracks your location while a SEDS work session is active.',
      importance: Importance.low,
    );
    await notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        // IMPORTANT: The function name here MUST be a top-level function
        // decorated with @pragma('vm:entry-point')
        onStart: backgroundServiceOnStart,
        autoStart: false,             // only start when we explicitly call startService()
        isForegroundMode: true,
        notificationChannelId: _channelId,
        initialNotificationTitle: 'SEDS Portal',
        initialNotificationContent: 'Session active — location tracking on',
        foregroundServiceNotificationId: _notifId,
        foregroundServiceTypes: [AndroidForegroundType.location],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: backgroundServiceOnStart,
        onBackground: onIosBackground,
      ),
    );
  } catch (e) {
    developer.log('`flutter_background_service` initialization handled/skipped in background isolate: $e');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// onIosBackground  ─ required iOS stub
// ─────────────────────────────────────────────────────────────────────────────
@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  return true;
}

// ─────────────────────────────────────────────────────────────────────────────
// backgroundServiceOnStart  ─ runs in the BACKGROUND ISOLATE (NOT the main isolate)
// ─────────────────────────────────────────────────────────────────────────────
@pragma('vm:entry-point')
void backgroundServiceOnStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  // Listen for the "stop" command from the main isolate
  service.on('stop').listen((_) {
    service.stopSelf();
  });

  // Post location every 5 seconds
  Timer.periodic(const Duration(seconds: 5), (timer) async {
    // Read the active session details from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('bg_tracking_email') ?? '';
    final isActive = prefs.getBool('bg_tracking_active') ?? false;

    if (!isActive || email.isEmpty) {
      timer.cancel();
      service.stopSelf();
      return;
    }

    try {
      // Check permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 8));

      // POST location to backend via HTTPS
      final res = await http.post(
        Uri.parse('$_apiBase/api/logs/location'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'latitude': pos.latitude,
          'longitude': pos.longitude,
        }),
      ).timeout(const Duration(seconds: 8));

      // Update the foreground notification content
      if (service is AndroidServiceInstance && res.statusCode == 200) {
        service.setForegroundNotificationInfo(
          title: 'SEDS Portal — Session Active',
          content: '📍 ${pos.latitude.toStringAsFixed(6)}, '
              '${pos.longitude.toStringAsFixed(6)}',
        );
      }
    } catch (_) {
      // Silently ignore transient errors (no network, GPS timeout, etc.)
    }
  });
}

Timer? _foregroundLocationTimer;

void _startForegroundLocationTimer(String email) {
  _foregroundLocationTimer?.cancel();
  _foregroundLocationTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
    final prefs = await SharedPreferences.getInstance();
    final isActive = prefs.getBool('bg_tracking_active') ?? false;
    if (!isActive) {
      timer.cancel();
      _foregroundLocationTimer = null;
      return;
    }

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 8));

      await http.post(
        Uri.parse('$_apiBase/api/logs/location'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'latitude': pos.latitude,
          'longitude': pos.longitude,
        }),
      ).timeout(const Duration(seconds: 8));

      developer.log('[Location] Foreground posted: ${pos.latitude}, ${pos.longitude}');
    } catch (e) {
      developer.log('[Location] Foreground tracking error: $e');
    }
  });
}

void _stopForegroundLocationTimer() {
  _foregroundLocationTimer?.cancel();
  _foregroundLocationTimer = null;
}

// ─────────────────────────────────────────────────────────────────────────────
// startBackgroundTracking  ─ call after a session starts successfully
// ─────────────────────────────────────────────────────────────────────────────
Future<void> startBackgroundTracking(String email) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('bg_tracking_email', email.trim().toLowerCase());
  await prefs.setBool('bg_tracking_active', true);

  final isWebOrWindows = kIsWeb || (!kIsWeb && dart_io.Platform.isWindows);
  if (isWebOrWindows) {
    _startForegroundLocationTimer(email.trim().toLowerCase());
    return;
  }

  final service = FlutterBackgroundService();
  if (!await service.isRunning()) {
    await service.startService();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// stopBackgroundTracking  ─ call after a session stops successfully
// ─────────────────────────────────────────────────────────────────────────────
Future<void> stopBackgroundTracking() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('bg_tracking_active', false);
  await prefs.remove('bg_tracking_email');

  _stopForegroundLocationTimer();

  final isWebOrWindows = kIsWeb || (!kIsWeb && dart_io.Platform.isWindows);
  if (isWebOrWindows) {
    return;
  }

  final service = FlutterBackgroundService();
  if (await service.isRunning()) {
    service.invoke('stop');
  }
}
