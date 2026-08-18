// ─────────────────────────────────────────────────────────────────────────────
// background_service.dart
//
// Persistent background location tracker for SEDS Portal.
// • Starts automatically when a work session begins (_startWork called)
// • Uses position STREAM (not getCurrentPosition) for reliable tracking on Samsung/Xiaomi
// • Posts live GPS coordinates to the backend every 5 seconds
// • Updates the foreground notification with live session duration (HH:MM:SS)
// • Shows a high-priority warning notification if GPS signal is lost
// • Survives app minimisation, screen-off, and swipe-away (Android foreground service)
// • Stops automatically when the work session ends (_stopWork called)
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ui';
import 'dart:io' as dart_io;
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ── Notification channel IDs ──────────────────────────────────────────────────
const String _channelId       = 'seds_location_tracking';
const String _channelName     = 'SEDS Location Tracking';
const String _warnChannelId   = 'seds_location_warning';
const String _warnChannelName = 'SEDS Location Warning';
const int    _notifId         = 8888;   // Foreground service sticky notification
const int    _warnNotifId     = 8889;   // GPS-lost warning notification

// ── API base URL — must match the HTTPS base in main.dart ───────────────────
const String _apiBase = 'https://portal.kumaraguruseds.space';

// ── Location settings optimised for background use ───────────────────────────
const LocationSettings _locationSettings = LocationSettings(
  accuracy: LocationAccuracy.high,      // "high" is more reliable than "best" when screen is off
  distanceFilter: 0,                    // receive ALL updates regardless of movement
);

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
      await Future.delayed(const Duration(milliseconds: 400));
    }

    // Create both Android notification channels
    final notificationsPlugin = FlutterLocalNotificationsPlugin();

    // 1. Persistent foreground tracking channel (low priority — silent)
    const AndroidNotificationChannel trackChannel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: 'Tracks your location while a SEDS work session is active.',
      importance: Importance.low,
      playSound: false,
      enableVibration: false,
    );
    // 2. Location warning channel (high priority — makes noise when GPS is lost)
    const AndroidNotificationChannel warnChannel = AndroidNotificationChannel(
      _warnChannelId,
      _warnChannelName,
      description: 'Alerts when your GPS signal is lost during a SEDS work session.',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );

    final androidPlugin = notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(trackChannel);
    await androidPlugin?.createNotificationChannel(warnChannel);

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        // IMPORTANT: The function name here MUST be a top-level function
        // decorated with @pragma('vm:entry-point')
        onStart: backgroundServiceOnStart,
        // autoStart = true so that if the phone reboots while a session is
        // active, the service restarts and re-checks SharedPreferences.
        autoStart: true,
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
    developer.log(
      '`flutter_background_service` initialization handled/skipped in background isolate: $e',
    );
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

  // ── Initialise local notifications in this isolate ──────────────────────
  final localNotifications = FlutterLocalNotificationsPlugin();
  const AndroidInitializationSettings initSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  await localNotifications.initialize(
    const InitializationSettings(android: initSettings),
  );

  // ── Listen for the "stop" command from the main isolate ──────────────────
  service.on('stop').listen((_) {
    service.stopSelf();
  });

  // ── Check if there is actually an active session (reboot-recovery guard) ─
  final prefs = await SharedPreferences.getInstance();
  bool isActive = prefs.getBool('bg_tracking_active') ?? false;
  String email  = prefs.getString('bg_tracking_email') ?? '';

  if (!isActive || email.isEmpty) {
    // Service was auto-started but there is no active session — stop self
    service.stopSelf();
    return;
  }

  // ── Session start time (for computing duration in the notification) ───────
  DateTime sessionStartTime;
  final startTimeStr = prefs.getString('bg_session_start_time');
  sessionStartTime = (startTimeStr != null)
      ? (DateTime.tryParse(startTimeStr) ?? DateTime.now())
      : DateTime.now();

  // ── State variables ───────────────────────────────────────────────────────
  DateTime lastSuccessfulPost   = DateTime.now();
  bool locationLostNotifSent    = false;
  bool gpsSvcNotifSent          = false;
  int  consecutiveWatchdogFails = 0;
  Timer? notifUpdateTimer;

  // ── Helper: format elapsed seconds as HH:MM:SS ───────────────────────────
  String formatDuration(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  // ── Update the foreground notification every 10 seconds with session time ─
  notifUpdateTimer = Timer.periodic(const Duration(seconds: 10), (_) {
    final elapsed = DateTime.now().difference(sessionStartTime);
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: 'SEDS Portal — Session Active',
        content: '⏱ ${formatDuration(elapsed)}  |  📍 Location tracking on',
      );
    }
  });

  // ── Helper: dismiss GPS-lost warning ─────────────────────────────────────
  Future<void> dismissWarning() async {
    await localNotifications.cancel(_warnNotifId);
    locationLostNotifSent     = false;
    gpsSvcNotifSent           = false;
    consecutiveWatchdogFails  = 0;
  }

  // ── Helper: show GPS-lost warning notification ───────────────────────────
  Future<void> showLocationLostWarning(String title, String body) async {
    await localNotifications.show(
      _warnNotifId,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _warnChannelId,
          _warnChannelName,
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          ongoing: true,
          autoCancel: false,
          ticker: 'Location signal lost',
        ),
      ),
    );
  }

  // ── Helper: post location to backend ─────────────────────────────────────
  Future<bool> postLocation(double lat, double lng, double acc) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_apiBase/api/logs/location'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email'    : email,
              'latitude' : lat,
              'longitude': lng,
              'accuracy' : acc,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['session_stopped'] == true) {
          notifUpdateTimer?.cancel();
          service.stopSelf();
          return false;
        }
        return true;
      }
    } catch (_) {}
    return false;
  }

  // ── Main GPS tracking using position STREAM ───────────────────────────────
  // getPositionStream is far more reliable than periodic getCurrentPosition on
  // Samsung / Xiaomi / Oppo devices with aggressive battery optimizers because:
  // 1. The OS GPS engine keeps the fix alive between callbacks
  // 2. No repeated cold-start penalty from getCurrentPosition
  StreamSubscription<Position>? posStream;

  Future<void> startStream() async {
    await posStream?.cancel();
    posStream = null;
    try {
      posStream = Geolocator.getPositionStream(
        locationSettings: _locationSettings,
      ).listen(
        (Position pos) async {
          // Re-read prefs each update in case session was stopped externally
          final prefsNow = await SharedPreferences.getInstance();
          if (!(prefsNow.getBool('bg_tracking_active') ?? false)) {
            await posStream?.cancel();
            notifUpdateTimer?.cancel();
            service.stopSelf();
            return;
          }

          lastSuccessfulPost       = DateTime.now();
          consecutiveWatchdogFails = 0;

          // Dismiss any warning if location is back
          if (locationLostNotifSent || gpsSvcNotifSent) {
            await dismissWarning();
          }

          // Post to backend
          final ok = await postLocation(pos.latitude, pos.longitude, pos.accuracy);
          if (!ok) return; // session_stopped

          // Update foreground notification content
          final elapsed = DateTime.now().difference(sessionStartTime);
          if (service is AndroidServiceInstance) {
            service.setForegroundNotificationInfo(
              title: 'SEDS Portal — Session Active',
              content: '⏱ ${formatDuration(elapsed)}  |  '
                  '📍 ${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}',
            );
          }
        },
        onError: (dynamic err) {
          developer.log('[BGService] Stream error: $err');
          consecutiveWatchdogFails++;
        },
        cancelOnError: false, // Keep stream alive through transient errors
      );
    } catch (e) {
      developer.log('[BGService] Failed to start GPS stream: $e');
    }
  }

  await startStream();

  // ── Watchdog timer — runs every 15 seconds ────────────────────────────────
  // Monitors GPS health and restarts the stream if it appears stalled.
  Timer.periodic(const Duration(seconds: 15), (timer) async {
    // Re-read SharedPreferences to detect externally stopped sessions
    final prefsNow     = await SharedPreferences.getInstance();
    final stillActive  = prefsNow.getBool('bg_tracking_active') ?? false;
    final currentEmail = prefsNow.getString('bg_tracking_email') ?? '';

    if (!stillActive || currentEmail.isEmpty) {
      timer.cancel();
      await posStream?.cancel();
      notifUpdateTimer?.cancel();
      service.stopSelf();
      return;
    }

    // Check if the GPS service (device toggle) is enabled
    final gpsEnabled = await Geolocator.isLocationServiceEnabled();
    if (!gpsEnabled) {
      if (!gpsSvcNotifSent) {
        gpsSvcNotifSent = true;
        await showLocationLostWarning(
          '⚠️ SEDS Portal — GPS Disabled',
          'Your GPS was turned off. Work session may pause. Tap to re-enable.',
        );
        // Signal backend so it can start the 40s timeout countdown
        try {
          await http
              .post(
                Uri.parse('$_apiBase/api/logs/location'),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({'email': email, 'signal_lost': true}),
              )
              .timeout(const Duration(seconds: 8));
        } catch (_) {}
      }
      return;
    }

    // GPS service is on — check how long since we got a fix
    final secondsSinceLastFix =
        DateTime.now().difference(lastSuccessfulPost).inSeconds;

    if (secondsSinceLastFix > 25) {
      consecutiveWatchdogFails++;

      if (!locationLostNotifSent) {
        locationLostNotifSent = true;
        await showLocationLostWarning(
          '⚠️ SEDS Portal — Location Signal Weak',
          'Cannot get your location. Check GPS & mobile data. Session may pause soon.',
        );
        // Signal backend
        try {
          await http
              .post(
                Uri.parse('$_apiBase/api/logs/location'),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({'email': email, 'signal_lost': true}),
              )
              .timeout(const Duration(seconds: 8));
        } catch (_) {}
      }

      // After 3 consecutive watchdog failures (~45 seconds of no fix),
      // restart the stream — it may have silently stalled (common on Samsung OneUI)
      if (consecutiveWatchdogFails >= 3) {
        developer.log(
            '[BGService] GPS stream stalled — restarting (failure #$consecutiveWatchdogFails)');
        consecutiveWatchdogFails = 0;
        await startStream();
      }
    } else if (locationLostNotifSent || gpsSvcNotifSent) {
      // Location signal recovered — dismiss warning
      await dismissWarning();
    }
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Foreground location timer (for Windows/Web — no background service)
// ─────────────────────────────────────────────────────────────────────────────
Timer? _foregroundLocationTimer;

void _startForegroundLocationTimer(String email) {
  _foregroundLocationTimer?.cancel();
  _foregroundLocationTimer = Timer.periodic(
    const Duration(seconds: 5),
    (timer) async {
      final prefs    = await SharedPreferences.getInstance();
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
        ).timeout(const Duration(seconds: 10));

        await http
            .post(
              Uri.parse('$_apiBase/api/logs/location'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'email'    : email,
                'latitude' : pos.latitude,
                'longitude': pos.longitude,
                'accuracy' : pos.accuracy,
              }),
            )
            .timeout(const Duration(seconds: 10));
      } catch (e) {
        developer.log('[Location] Foreground tracking error: $e');
      }
    },
  );
}

void _stopForegroundLocationTimer() {
  _foregroundLocationTimer?.cancel();
  _foregroundLocationTimer = null;
}

// ─────────────────────────────────────────────────────────────────────────────
// startBackgroundTracking  ─ call after a session starts successfully
// ─────────────────────────────────────────────────────────────────────────────
Future<void> startBackgroundTracking(String email,
    {DateTime? sessionStart}) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('bg_tracking_email', email.trim().toLowerCase());
  await prefs.setBool('bg_tracking_active', true);
  // Persist session start time so the live notification timer is accurate
  await prefs.setString(
    'bg_session_start_time',
    (sessionStart ?? DateTime.now()).toIso8601String(),
  );

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
  await prefs.remove('bg_session_start_time');

  _stopForegroundLocationTimer();

  final isWebOrWindows = kIsWeb || (!kIsWeb && dart_io.Platform.isWindows);
  if (isWebOrWindows) return;

  final service = FlutterBackgroundService();
  if (await service.isRunning()) {
    service.invoke('stop');
  }
}