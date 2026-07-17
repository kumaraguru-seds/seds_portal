import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'notification_helper.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'main.dart';

// ── Background message handler (must be top-level) ──────────────────────────
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // FCM auto-displays the notification when app is in background/killed.
  // No extra work needed here for display.
  debugPrint('[FCM] Background message: ${message.messageId}');
}

// ────────────────────────────────────────────────────────────────────────────
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  // Android notification channels
  static const AndroidNotificationChannel _meetingChannel =
      AndroidNotificationChannel(
    'seds_meeting',
    'Meeting Alerts',
    description: 'Notifications about meeting schedules and reminders',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  static const AndroidNotificationChannel _sessionChannel =
      AndroidNotificationChannel(
    'seds_session',
    'Work Sessions',
    description: 'Notifications about work session start and pause',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  static const AndroidNotificationChannel _attendanceChannel =
      AndroidNotificationChannel(
    'seds_attendance',
    'Attendance',
    description: 'Attendance submission and reminder notifications',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  static const AndroidNotificationChannel _generalChannel =
      AndroidNotificationChannel(
    'seds_general',
    'General',
    description: 'General SEDS Portal notifications',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  /// Initialize the full notification stack — call after Firebase.initializeApp()
  Future<void> init({required String userEmail}) async {
    if (kIsWeb) {
      requestWebNotificationPermission();
      return;
    }
    if (Platform.isWindows) {
      // Windows local notifications do not require FCM token registration
      try {
        const initSettings = InitializationSettings(
          macOS: DarwinInitializationSettings(),
        );
        await _localNotifications.initialize(
          initSettings,
          onDidReceiveNotificationResponse: _onNotificationTap,
        );
      } catch (e) {
        debugPrint('[Notification] Windows local init error: $e');
      }
      return;
    }
    try {
      // 1. Request permission
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      debugPrint('[FCM] Permission: ${settings.authorizationStatus}');

      // 2. Create Android notification channels
      final androidPlugin =
          _localNotifications.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(_meetingChannel);
      await androidPlugin?.createNotificationChannel(_sessionChannel);
      await androidPlugin?.createNotificationChannel(_attendanceChannel);
      await androidPlugin?.createNotificationChannel(_generalChannel);

      // 3. Initialize flutter_local_notifications (for foreground display)
      const initSettings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      );
      await _localNotifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTap,
      );

      // 4. Register background handler
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      // 5. Handle foreground messages
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // 6. Handle tap when app was in background
      FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

      // 7. Get FCM token and register with backend
      await _registerToken(userEmail);

      // 8. Token refresh listener
      _messaging.onTokenRefresh.listen((newToken) {
        _saveTokenToBackend(userEmail, newToken);
      });

      // 9. Handle tap when app was completely terminated/killed
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        debugPrint('[FCM] App launched from terminated state via notification');
        Future.delayed(const Duration(milliseconds: 1500), () {
          openNotificationsPage();
        });
      }
    } catch (e) {
      debugPrint('[FCM] Safely caught notification init error: $e');
    }
  }

  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('[FCM] Foreground message: ${message.notification?.title}');
    final notification = message.notification;
    if (notification == null) return;

    final type = message.data['type'] as String? ?? 'general';
    final channelId = _channelIdForType(type);
    final channelName = _channelNameForType(type);
    final color = _colorForType(type);

    _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          importance: Importance.max,
          priority: Priority.high,
          color: color,
          styleInformation: BigTextStyleInformation(
            notification.body ?? '',
            contentTitle: notification.title,
          ),
          largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
          playSound: true,
          enableVibration: true,
          ticker: notification.title,
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }

  void _handleMessageOpenedApp(RemoteMessage message) {
    debugPrint('[FCM] Opened from background: ${message.data}');
    openNotificationsPage();
  }

  void _onNotificationTap(NotificationResponse response) {
    debugPrint('[FCM] Notification tapped: ${response.payload}');
    openNotificationsPage();
  }

  String _channelIdForType(String type) {
    if (type.contains('meeting')) return 'seds_meeting';
    if (type.contains('session')) return 'seds_session';
    if (type.contains('attendance')) return 'seds_attendance';
    return 'seds_general';
  }

  String _channelNameForType(String type) {
    if (type.contains('meeting')) return 'Meeting Alerts';
    if (type.contains('session')) return 'Work Sessions';
    if (type.contains('attendance')) return 'Attendance';
    return 'General';
  }

  Color _colorForType(String type) {
    if (type.contains('meeting')) return const Color(0xFF4DA6FF);
    if (type.contains('session')) return const Color(0xFF00C48C);
    if (type.contains('attendance')) return const Color(0xFFFF9F43);
    return const Color(0xFF8A9CC2);
  }

  Future<void> _registerToken(String userEmail) async {
    String? token;
    if (!kIsWeb && Platform.isAndroid) {
      token = await _messaging.getToken();
    }
    if (token != null) {
      debugPrint('[FCM] Token: $token');
      await _saveTokenToBackend(userEmail, token);
    }
  }

  Future<void> _saveTokenToBackend(String email, String token) async {
    try {
      await http.post(
        Uri.parse('$apiBaseUrl/api/fcm/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'fcm_token': token,
          'platform': kIsWeb ? 'web' : (Platform.isAndroid ? 'android' : 'ios'),
        }),
      ).timeout(const Duration(seconds: 10));
      debugPrint('[FCM] Token registered successfully');
    } catch (e) {
      debugPrint('[FCM] Token registration error: $e');
    }
  }

  Future<void> showLocalNotification({required String title, required String body}) async {
    if (kIsWeb) {
      showWebNotification(title, body);
      return;
    }

    try {
      const androidDetails = AndroidNotificationDetails(
        'seds_general',
        'General Alerts',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      );
      await _localNotifications.show(
        DateTime.now().millisecond,
        title,
        body,
        const NotificationDetails(
          android: androidDetails,
          iOS: DarwinNotificationDetails(),
          macOS: DarwinNotificationDetails(),
        ),
      );
    } catch (e) {
      debugPrint('[Notification] Local show error: $e');
    }
  }
}
