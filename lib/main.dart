import 'dart:async';
import 'dart:io' as dart_io;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'login.dart';
import 'attendance.dart';
import 'attendance_members.dart';
import 'attendance_admin.dart';
import 'logs_members.dart';
import 'logs_leads.dart';
import 'logs_admin.dart';
import 'notification_service.dart';
import 'notifications_page.dart';
import 'documents_section.dart';
import 'background_service.dart';
import 'app_toast.dart';
import 'analyse_users_page.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as latlong;
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:local_auth/local_auth.dart';
import 'dart:math';
import 'statistics_page.dart';
import 'update_coordinates_page.dart';
import 'user_profile_details_form_page.dart';
import 'apply_leave_page.dart';
import 'update_checker.dart';
import 'crypto_helper.dart';
import 'package:file_picker/file_picker.dart';
import 'chat_tab.dart';
import 'package:url_launcher/url_launcher.dart';

class Platform {
  static bool get isWindows => kIsWeb || (!kIsWeb && dart_io.Platform.isWindows);
  static bool get isAndroid => !kIsWeb && dart_io.Platform.isAndroid;
  static bool get isIOS => !kIsWeb && dart_io.Platform.isIOS;
}

const String apiBaseUrl = 'https://portal.kumaraguruseds.space';

Future<List<String>> fetchUniqueTeams() async {
  try {
    final response = await http
        .get(Uri.parse('$apiBaseUrl/api/teams'))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['success'] == true && data['teams'] != null) {
        return List<String>.from(data['teams']);
      }
    }
  } catch (e) {
    debugPrint('Error fetching unique teams: $e');
  }
  return ['PR', 'Media', 'Events', 'Web Dev', 'Admin'];
}

String? currentSessionId;
String? currentJwtToken;
UserData? currentUserData;
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void openNotificationsPage() {
  final context = navigatorKey.currentContext;
  if (context != null && currentUserData != null) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DesktopPageWrapper(
          child: Scaffold(
            backgroundColor: const Color(0xFF0D1E3A),
            body: Stack(
              children: [
                if (!Platform.isWindows) ...[
                  Positioned.fill(
                    child: Image.asset(
                      'assets/background.png',
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          Container(color: const Color(0xFF0D1E3A)),
                    ),
                  ),
                  Positioned.fill(
                    child: Container(color: Colors.black.withValues(alpha: 0.45)),
                  ),
                ],
                NotificationsPage(userData: currentUserData),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> saveUserSession(
  String token,
  String sessionId,
  Map<String, dynamic> userMap,
) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('jwt_token', token);
  await prefs.setString('session_id', sessionId);
  await prefs.setString('user_data', jsonEncode(userMap));
  currentSessionId = sessionId;
  currentJwtToken = token;
  currentUserData = UserData.fromJson(userMap);
}

Future<void> clearUserSession() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove('jwt_token');
  await prefs.remove('session_id');
  await prefs.remove('user_data');
  currentUserData = null;
  if (currentSessionId != null) {
    try {
      await http
          .post(
            Uri.parse('$apiBaseUrl/api/logout'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'session_id': currentSessionId}),
          )
          .timeout(const Duration(seconds: 4));
    } catch (_) {}
  }
  currentSessionId = null;
  currentJwtToken = null;
}

Future<void> trackPageVisit(String pageName) async {
  if (currentSessionId == null) return;
  try {
    await http
        .post(
          Uri.parse('$apiBaseUrl/api/sessions/page-visit'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'session_id': currentSessionId,
            'page_name': pageName,
          }),
        )
        .timeout(const Duration(seconds: 4));
  } catch (e) {
    debugPrint('Track page visit error: $e');
  }
}

Future<void> trackUserAction(String actionDescription) async {
  if (currentSessionId == null) return;
  try {
    await http
        .post(
          Uri.parse('$apiBaseUrl/api/sessions/action'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'session_id': currentSessionId,
            'action': actionDescription,
          }),
        )
        .timeout(const Duration(seconds: 4));
  } catch (e) {
    debugPrint('Track action error: $e');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize Firebase
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  }
  // Register background message handler — Android/iOS only
  if (Platform.isAndroid || Platform.isIOS) {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  final prefs = await SharedPreferences.getInstance();
  final String? token = prefs.getString('jwt_token');
  final String? sessionId = prefs.getString('session_id');
  final String? userDataStr = prefs.getString('user_data');

  UserData? userData;
  if (token != null && sessionId != null && userDataStr != null) {
    try {
      final Map<String, dynamic> userMap = jsonDecode(userDataStr);
      userData = UserData.fromJson(userMap);
      currentUserData = userData;
      currentJwtToken = token;
      currentSessionId = sessionId;
    } catch (e) {
      debugPrint('Error parsing auto-login details: $e');
    }
  }

  // Initialize notifications if user is already logged in
  if (userData != null) {
    await NotificationService().init(userEmail: userData.email);
  }

  // Initialize background location service (Android foreground service only)
  if (Platform.isAndroid) {
    await initBackgroundService();
  }

  runApp(SEDSApp(initialUserData: userData));
}

class AccessibilitySettings {
  final double textScaleFactor;
  final bool highContrast;
  final bool grayscale;

  AccessibilitySettings({
    this.textScaleFactor = 0.8,
    this.highContrast = false,
    this.grayscale = false,
  });

  AccessibilitySettings copyWith({
    double? textScaleFactor,
    bool? highContrast,
    bool? grayscale,
  }) {
    return AccessibilitySettings(
      textScaleFactor: textScaleFactor ?? this.textScaleFactor,
      highContrast: highContrast ?? this.highContrast,
      grayscale: grayscale ?? this.grayscale,
    );
  }
}

final ValueNotifier<AccessibilitySettings> accessibilityNotifier =
    ValueNotifier<AccessibilitySettings>(AccessibilitySettings());

double? _globalX;
double? _globalY;

final ValueNotifier<bool> accessibilityMenuOpenNotifier = ValueNotifier<bool>(
  false,
);

class SEDSApp extends StatelessWidget {
  final UserData? initialUserData;
  const SEDSApp({super.key, this.initialUserData});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AccessibilitySettings>(
      valueListenable: accessibilityNotifier,
      builder: (context, settings, _) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          title: 'Kumaraguru SEDS Portal',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF4DA6FF),
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
            fontFamily: GoogleFonts.poppins().fontFamily,
            textTheme: GoogleFonts.poppinsTextTheme(
              ThemeData.dark().textTheme,
            ).apply(bodyColor: Colors.white, displayColor: Colors.white),
          ),
          builder: (context, child) {
            final mediaQuery = MediaQuery.of(context);
            final double factor = Platform.isWindows ? (settings.textScaleFactor * 1.15) : settings.textScaleFactor;
            MediaQueryData newData;
            try {
              newData = mediaQuery.copyWith(
                textScaler: TextScaler.linear(factor),
              );
            } catch (_) {
              newData = mediaQuery.copyWith(
                // ignore: deprecated_member_use
                textScaleFactor: factor,
              );
            }
            return MediaQuery(
              data: newData,
              child: AccessibilityWrapper(settings: settings, child: child!),
            );
          },
          home: initialUserData != null
              ? MainPage(userData: initialUserData)
              : const LoginPage(),
        );
      },
    );
  }
}

class AccessibilityWrapper extends StatefulWidget {
  final Widget child;
  final AccessibilitySettings settings;

  const AccessibilityWrapper({
    super.key,
    required this.child,
    required this.settings,
  });

  @override
  State<AccessibilityWrapper> createState() => _AccessibilityWrapperState();
}

class _AccessibilityWrapperState extends State<AccessibilityWrapper> {
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final double maxBoxWidth = 1000.0;
    final double leftLimit = Platform.isWindows && size.width > maxBoxWidth
        ? (size.width - maxBoxWidth) / 2 + 36
        : 10.0;
    final double rightLimit = Platform.isWindows && size.width > maxBoxWidth
        ? (size.width + maxBoxWidth) / 2 - 80
        : size.width - 70.0;

    final double posX = _globalX ?? rightLimit;
    final double posY = _globalY ?? (size.height - 180.0);
    Widget content = widget.child;

    if (widget.settings.grayscale) {
      content = ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          0.2126,
          0.7152,
          0.0722,
          0,
          0,
          0.2126,
          0.7152,
          0.0722,
          0,
          0,
          0.2126,
          0.7152,
          0.0722,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
        ]),
        child: content,
      );
    }

    if (widget.settings.highContrast) {
      content = Theme(
        data: ThemeData(
          brightness: Brightness.dark,
          textTheme: const TextTheme(
            bodyLarge: TextStyle(fontWeight: FontWeight.w900),
            bodyMedium: TextStyle(fontWeight: FontWeight.w900),
            titleLarge: TextStyle(fontWeight: FontWeight.w900),
            titleMedium: TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
        child: content,
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          content,
          ValueListenableBuilder<bool>(
            valueListenable: accessibilityMenuOpenNotifier,
            builder: (context, isMenuOpen, _) {
              if (isMenuOpen) {
                return const SizedBox.shrink();
              }
              return Positioned(
                left: posX,
                top: posY,
                child: GestureDetector(
                  onPanUpdate: (details) {
                    setState(() {
                      _isDragging = true;
                      _globalX = posX + details.delta.dx;
                      _globalY = posY + details.delta.dy;
                      final size = MediaQuery.of(context).size;
                      _globalX = _globalX!.clamp(leftLimit, rightLimit);
                      _globalY = _globalY!.clamp(50.0, size.height - 180.0);
                    });
                  },
                  onPanEnd: (_) {
                    setState(() => _isDragging = false);
                  },
                  onTap: () {
                    if (!_isDragging) {
                      _showAccessibilitySheet(context);
                    }
                  },
                  child: Opacity(
                    opacity: _isDragging ? 0.6 : 0.85,
                    child: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF00C48C), Color(0xFF4DA6FF)],
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.accessibility_new_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _showAccessibilitySheet(BuildContext context) async {
    final navContext = navigatorKey.currentContext;
    if (navContext == null) return;

    // Hide the accessibility floating button before opening
    accessibilityMenuOpenNotifier.value = true;

    await showModalBottomSheet(
      context: navContext,
      backgroundColor: const Color(0xFF1A2B4A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      builder: (ctx) {
        return ValueListenableBuilder<AccessibilitySettings>(
          valueListenable: accessibilityNotifier,
          builder: (context, settings, _) {
            final poppins = GoogleFonts.poppins;
            return Container(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.settings_accessibility_rounded,
                        color: Color(0xFF4DA6FF),
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Accessibility Settings',
                        style: poppins(
                          color: Colors.white,
                          fontSize: 16.0,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white54,
                        ),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white10),
                  const SizedBox(height: 14),
                  Text(
                    'Font Size Scale: ${settings.textScaleFactor.toStringAsFixed(1)}x',
                    style: poppins(
                      color: Colors.white70,
                      fontSize: 12.0,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Row(
                    children: [
                      const Icon(
                        Icons.format_size_rounded,
                        color: Colors.white38,
                        size: 16,
                      ),
                      Expanded(
                        child: Slider(
                          value: settings.textScaleFactor,
                          min: 0.8,
                          max: 1.8,
                          divisions: 10,
                          activeColor: const Color(0xFF4DA6FF),
                          inactiveColor: Colors.white10,
                          onChanged: (v) {
                            accessibilityNotifier.value = settings.copyWith(
                              textScaleFactor: v,
                            );
                          },
                        ),
                      ),
                      const Icon(
                        Icons.format_size_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile(
                    title: Text(
                      'High Contrast Text',
                      style: poppins(color: Colors.white, fontSize: 13.0),
                    ),
                    subtitle: Text(
                      'Bolds all system texts',
                      style: poppins(color: Colors.white38, fontSize: 10.0),
                    ),
                    value: settings.highContrast,
                    activeThumbColor: const Color(0xFF00C48C),
                    onChanged: (v) {
                      accessibilityNotifier.value = settings.copyWith(
                        highContrast: v,
                      );
                    },
                  ),
                  SwitchListTile(
                    title: Text(
                      'Grayscale Filter',
                      style: poppins(color: Colors.white, fontSize: 13.0),
                    ),
                    subtitle: Text(
                      'Removes color for easier reading',
                      style: poppins(color: Colors.white38, fontSize: 10.0),
                    ),
                    value: settings.grayscale,
                    activeThumbColor: const Color(0xFF00C48C),
                    onChanged: (v) {
                      accessibilityNotifier.value = settings.copyWith(
                        grayscale: v,
                      );
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    // Show the accessibility floating button again after it closes
    accessibilityMenuOpenNotifier.value = false;
  }
}

class DesktopPageWrapper extends StatelessWidget {
  final Widget child;
  const DesktopPageWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!Platform.isWindows) {
      return Scaffold(
        backgroundColor: const Color(0xFF0D1E3A),
        body: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                'assets/background.png',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(color: const Color(0xFF0D1E3A));
                },
              ),
            ),
            Positioned.fill(
              child: Container(color: Colors.black.withValues(alpha: 0.45)),
            ),
            Positioned.fill(
              child: child,
            ),
          ],
        ),
      );
    }
    // Windows desktop and web browser: centered container layout
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            decoration: BoxDecoration(
              color: const Color(0xFF0D1E3A),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 24,
                  spreadRadius: 4,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Image.asset(
                      'assets/background.png',
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(color: const Color(0xFF0D1E3A));
                      },
                    ),
                  ),
                  Positioned.fill(
                    child: Container(color: Colors.black.withValues(alpha: 0.45)),
                  ),
                  Positioned.fill(
                    child: child,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}


// ─────────────── User Data Model ───────────────
class UserData {
  final int id;
  final String name;
  final String email;
  final String role;
  final String? team;
  final String? leadershipRole;
  final String rollNumber;
  final String? imageUrl;
  final List<String> teams;

  UserData({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.team,
    this.leadershipRole,
    required this.rollNumber,
    this.imageUrl,
    required this.teams,
  });

  factory UserData.fromJson(Map<String, dynamic> json) {
    var rawTeams = json['teams'];
    List<String> parsedTeams = [];
    if (rawTeams is List) {
      parsedTeams = rawTeams.map((e) => e.toString()).toList();
    } else if (json['team'] != null) {
      parsedTeams = [json['team'].toString()];
    }
    return UserData(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      email: json['email'] ?? '',
      role: json['role'] ?? 'Member',
      team: json['team'],
      leadershipRole: json['leadershipRole'],
      rollNumber: json['roll_number'] ?? json['rollNumber'] ?? '',
      imageUrl: json['imageUrl'] ?? json['image_url'],
      teams: parsedTeams,
    );
  }
}

// ─────────────── Reusable Scrollable Notification Bell ───────────────
class AppNotificationBell extends StatefulWidget {
  final UserData? userData;
  const AppNotificationBell({super.key, this.userData});

  @override
  State<AppNotificationBell> createState() => _AppNotificationBellState();
}

class _AppNotificationBellState extends State<AppNotificationBell> {
  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();
    _fetchUnreadCount();
  }

  Future<void> _fetchUnreadCount() async {
    try {
      final email = widget.userData?.email ?? '';
      final res = await http
          .get(
            Uri.parse(
              '$apiBaseUrl/api/notifications/unread-count?email=${Uri.encodeComponent(email)}',
            ),
          )
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        setState(() => _unreadCount = data['count'] as int? ?? 0);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          onPressed: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => Scaffold(
                  backgroundColor: const Color(0xFF0D1E3A),
                  body: Stack(
                    children: [
                      Positioned.fill(
                        child: Image.asset(
                          'assets/background.png',
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              Container(color: const Color(0xFF0D1E3A)),
                        ),
                      ),
                      Positioned.fill(
                        child: Container(
                          color: Colors.black.withValues(alpha: 0.45),
                        ),
                      ),
                      NotificationsPage(userData: widget.userData),
                    ],
                  ),
                ),
              ),
            );
            _fetchUnreadCount();
          },
          icon: const Icon(
            Icons.notifications_outlined,
            color: Colors.white,
            size: 26,
          ),
        ),
        if (_unreadCount > 0)
          Positioned(
            right: 4,
            top: 4,
            child: Container(
              width: 17,
              height: 17,
              decoration: const BoxDecoration(
                color: Color(0xFFFF6B6B),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  _unreadCount > 99 ? '99+' : '$_unreadCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────── Main Navigation Page ───────────────
class MainPage extends StatefulWidget {
  final UserData? userData;
  const MainPage({super.key, this.userData});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _currentIndex = 0;
  late List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    final isLead = widget.userData?.role == 'Lead';
    final isAdmin =
        widget.userData?.role == 'Admin' ||
        widget.userData?.role == 'SuperAdmin';
    if (isAdmin) {
      _pages = <Widget>[
        HomeTab(userData: widget.userData),
        ChatTab(userData: widget.userData),
        AttendanceAdminTab(userData: widget.userData),
        DailyLogsTab(userData: widget.userData),
        StatisticsPage(userData: widget.userData),
        ProfileTab(userData: widget.userData),
      ];
    } else {
      _pages = <Widget>[
        HomeTab(userData: widget.userData),
        ChatTab(userData: widget.userData),
        isLead
            ? AttendanceTab(userData: widget.userData)
            : AttendanceMembersTab(userData: widget.userData),
        DailyLogsTab(userData: widget.userData),
        StatisticsPage(userData: widget.userData),
        ProfileTab(userData: widget.userData),
      ];
    }
    trackPageVisit('Home');

    // Guard: always check profile completion on app entry
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _checkProfileCompletion(),
    );

    // Check for app updates from GitHub Releases (non-blocking, silent on failure)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) UpdateChecker.checkForUpdates(context);
      });
    });

    // Auto-initialize E2EE Keys so they are always configured immediately upon login/startup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initE2EEKeys();
    });
  }

  Future<void> _initE2EEKeys() async {
    final email = widget.userData?.email.toLowerCase().trim();
    if (email == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      String? localPriv = prefs.getString('e2ee_private_key');
      String? localPub = prefs.getString('e2ee_public_key');

      if (localPriv == null || localPub == null) {
        // 1. Check if server has bootstrapped keys for this user
        final bootstrapUrl = Uri.parse('$apiBaseUrl/api/chat/bootstrap-private-key?email=$email');
        final response = await http.get(bootstrapUrl);
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['success'] == true && data['private_key'] != null) {
            localPriv = data['private_key'];
            // Since we know the private key, we must also fetch the public key
            final pubKeyUrl = Uri.parse('$apiBaseUrl/api/chat/public-keys?emails=$email');
            final pubRes = await http.get(pubKeyUrl);
            if (pubRes.statusCode == 200) {
              final pubData = jsonDecode(pubRes.body);
              final keysList = pubData['keys'] as List;
              if (keysList.isNotEmpty) {
                localPub = keysList[0]['public_key'];
                // Save to local preferences
                await prefs.setString('e2ee_private_key', localPriv!);
                await prefs.setString('e2ee_public_key', localPub!);
                debugPrint('[E2EE] Downloaded and restored bootstrapped keypair.');
              }
            }
          }
        }
      }

      // 2. If we still don't have local keys, generate new ones locally
      if (localPriv == null || localPub == null) {
        final keys = await CryptoHelper.getOrGenerateKeys();
        localPriv = keys['private']!;
        localPub = keys['public']!;
      }

      // 3. Upload/Refresh public key on the server
      final url = Uri.parse('$apiBaseUrl/api/chat/public-key');
      await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'public_key': localPub,
        }),
      );
      debugPrint('[E2EE] Keys successfully auto-initialized and uploaded.');
    } catch (e) {
      debugPrint('[E2EE] Error auto-initializing keys: $e');
    }
  }

  Future<void> _checkProfileCompletion() async {
    final email = widget.userData?.email;
    if (email == null) return;

    // Check SharedPreferences first
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('profile_completed_$email') ?? false) {
        return; // Already completed, skip DB check entirely
      }
    } catch (e) {
      debugPrint('SharedPreferences read error: $e');
    }

    bool shouldRedirect = false;
    try {
      final res = await http
          .get(
            Uri.parse(
              '$apiBaseUrl/api/user/details?email=${Uri.encodeComponent(email)}',
            ),
          )
          .timeout(const Duration(seconds: 7));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && data['details'] != null) {
          // Store locally so we don't query next time
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('profile_completed_$email', true);
          return; // all good
        } else {
          shouldRedirect = true;
        }
      }
    } catch (_) {
      // Network/server error -> do NOT redirect, just let them use the app
    }

    // Details not found → redirect to profile form
    if (shouldRedirect && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => DesktopPageWrapper(
            child: UserProfileDetailsFormPage(userData: widget.userData!),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDesktop = Platform.isWindows; // true for web + Windows desktop
    return Scaffold(
      backgroundColor: isDesktop ? const Color(0xFFF1F5F9) : const Color(0xFF0D1E3A),
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // ── Fixed Background Image ──
          Positioned.fill(
            child: isDesktop
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
            child: isDesktop
                ? const SizedBox.shrink()
                : Container(color: Colors.black.withValues(alpha: 0.45)),
          ),
          // ── App Page Content ──
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.only(bottom: isDesktop ? 116.0 : 96.0),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: isDesktop ? 1000.0 : double.infinity,
                  ),
                  child: isDesktop
                      ? Container(
                          margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0D1E3A),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.25),
                                blurRadius: 24,
                                spreadRadius: 4,
                                offset: const Offset(0, 12),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: Image.asset(
                                    'assets/background.png',
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Container(color: const Color(0xFF0D1E3A));
                                    },
                                  ),
                                ),
                                Positioned.fill(
                                  child: Container(color: Colors.black.withValues(alpha: 0.45)),
                                ),
                                Positioned.fill(
                                  child: IndexedStack(index: _currentIndex, children: _pages),
                                ),
                              ],
                            ),
                          ),
                        )
                      : IndexedStack(index: _currentIndex, children: _pages),
                ),
              ),
            ),
          ),
          // ── Custom Floating Navigation Bar ──
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SEDSFloatingNavigationBar(
              currentIndex: _currentIndex,
              userData: widget.userData,
              onTap: (index) {
                setState(() {
                  _currentIndex = index;
                });
                final pages = [
                  'Home',
                  'Chat',
                  'Attendance',
                  'Daily Logs',
                  'Statistics',
                  'Profile',
                ];
                if (index < pages.length) {
                  trackPageVisit(pages[index]);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────── Nav Item Config ───────────────
class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}

// ─────────────── Custom Bottom Navigation Bar ───────────────
class TrianglePainter extends CustomPainter {
  final Color color;
  TrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path();
    path.moveTo(0, 0);
    path.lineTo(size.width, 0);
    path.lineTo(size.width / 2, size.height);
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class SEDSFloatingNavigationBar extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;
  final UserData? userData;

  const SEDSFloatingNavigationBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.userData,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      const _NavItem(
        icon: Icons.home_outlined,
        activeIcon: Icons.home,
        label: 'Home',
      ),
      const _NavItem(
        icon: Icons.chat_bubble_outline_rounded,
        activeIcon: Icons.chat_bubble_rounded,
        label: 'Chat',
      ),
      const _NavItem(
        icon: Icons.calendar_today_outlined,
        activeIcon: Icons.calendar_today,
        label: 'Attendance',
      ),
      const _NavItem(
        icon: Icons.assignment_outlined,
        activeIcon: Icons.assignment,
        label: 'Logs',
      ),
      const _NavItem(
        icon: Icons.bar_chart_outlined,
        activeIcon: Icons.bar_chart,
        label: 'Stats',
      ),
      const _NavItem(
        icon: Icons.person_outline,
        activeIcon: Icons.person,
        label: 'Profile',
      ),
    ];

    final String? imageUrl = userData?.imageUrl;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Container(
          padding: EdgeInsets.symmetric(
            vertical: Platform.isWindows ? 10 : 6,
            horizontal: Platform.isWindows ? 14 : 8,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(Platform.isWindows ? 40 : 32),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 20,
                spreadRadius: 2,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            bottom: false,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(items.length, (index) {
                final isSelected = index == currentIndex;
                final item = items[index];

                return GestureDetector(
                  onTap: () => onTap(index),
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    padding: EdgeInsets.symmetric(
                      horizontal: Platform.isWindows ? 22 : 10,
                      vertical: Platform.isWindows ? 14 : 8,
                    ),
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF0084FF).withValues(alpha: 0.12)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(Platform.isWindows ? 30 : 24),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // The Icon (or Profile Picture)
                        item.label == 'Profile'
                            ? Container(
                                width: Platform.isWindows ? 32 : 26,
                                height: Platform.isWindows ? 32 : 26,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0084FF),
                                  shape: BoxShape.circle,
                                  border: isSelected
                                      ? Border.all(
                                          color: const Color(0xFF0084FF),
                                          width: 1.5,
                                        )
                                      : null,
                                ),
                                child: ClipOval(
                                  child: imageUrl != null && imageUrl.isNotEmpty
                                      ? Image.network(
                                          imageUrl,
                                          fit: BoxFit.cover,
                                          width: Platform.isWindows ? 32 : 26,
                                          height: Platform.isWindows ? 32 : 26,
                                          errorBuilder: (ctx, err, st) =>
                                              Center(
                                                child: Icon(
                                                  Icons.person_rounded,
                                                  color: Colors.white,
                                                  size: Platform.isWindows ? 20 : 16,
                                                ),
                                              ),
                                        )
                                      : Center(
                                          child: Icon(
                                            Icons.person_rounded,
                                            color: Colors.white,
                                            size: Platform.isWindows ? 20 : 16,
                                          ),
                                        ),
                                ),
                              )
                            : Icon(
                                isSelected ? item.activeIcon : item.icon,
                                color: isSelected
                                    ? const Color(0xFF0084FF)
                                    : const Color(0xFF5F6368),
                                size: Platform.isWindows ? 32 : 26,
                              ),

                        // Animated text next to it
                        AnimatedSize(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeInOut,
                          child: isSelected
                              ? Row(
                                  children: [
                                    const SizedBox(width: 6),
                                    Text(
                                      item.label,
                                      style: GoogleFonts.poppins(
                                        color: const Color(0xFF0084FF),
                                        fontSize: Platform.isWindows ? 15 : 10.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────── Home Tab ───────────────
class HomeTab extends StatefulWidget {
  final UserData? userData;
  const HomeTab({super.key, this.userData});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  Map<String, dynamic>? _userDetails;
  bool _loadingDetails = false;
  String _slogan = "The sky is not the limit — it is just the beginning.";

  @override
  void initState() {
    super.initState();
    _fetchUserDetails();
    _fetchRandomSlogan();
  }

  Future<void> _fetchRandomSlogan() async {
    try {
      final res = await http
          .get(Uri.parse('$apiBaseUrl/api/slogan/random'))
          .timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && data['slogan'] != null) {
          if (mounted) {
            setState(() {
              _slogan = data['slogan'];
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching slogan: $e');
    }
  }

  Future<void> _fetchUserDetails() async {
    final email = widget.userData?.email;
    if (email == null) return;
    if (mounted) setState(() => _loadingDetails = true);
    try {
      final res = await http
          .get(
            Uri.parse(
              '$apiBaseUrl/api/user/details?email=${Uri.encodeComponent(email)}',
            ),
          )
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true) {
          if (mounted) {
            setState(() {
              _userDetails = data['details'];
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching user details: $e');
    } finally {
      if (mounted) setState(() => _loadingDetails = false);
    }
  }

  Future<void> _onRefresh() async {
    await Future.wait([_fetchUserDetails(), _fetchRandomSlogan()]);
  }

  Widget _buildDetailRow(
    IconData icon,
    String label,
    String value, {
    bool isLink = false,
  }) {
    final poppins = GoogleFonts.poppins;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          color: const Color(0xFF4DA6FF).withValues(alpha: 0.9),
          size: 19,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: poppins(
                  fontSize: 12,
                  color: const Color(0xFF8A9CC2),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: poppins(
                  fontSize: 15.5,
                  color: isLink ? const Color(0xFF4DA6FF) : Colors.white,
                  decoration: isLink ? TextDecoration.underline : null,
                  fontWeight: FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final poppins = GoogleFonts.poppins;
    final displayName = widget.userData?.name ?? 'SEDSian';
    final role = widget.userData?.role ?? 'Guest';
    final team = widget.userData?.team;

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _onRefresh,
        color: const Color(0xFF4DA6FF),
        backgroundColor: const Color(0xFF1A2B4A),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome back,',
                          style: poppins(
                            fontSize: 15,
                            color: const Color(0xFFC9D1E6),
                          ),
                        ),
                        Text(
                          displayName,
                          style: poppins(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppNotificationBell(userData: widget.userData),
                      if (widget.userData?.imageUrl != null &&
                          widget.userData!.imageUrl!.isNotEmpty) ...[
                        const SizedBox(width: 12),
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFF4DA6FF),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(
                                  0xFF4DA6FF,
                                ).withValues(alpha: 0.25),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: CircleAvatar(
                            radius: 18,
                            backgroundImage: NetworkImage(
                              widget.userData!.imageUrl!,
                            ),
                            backgroundColor: Colors.transparent,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4DA6FF).withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFF4DA6FF).withValues(alpha: 0.35),
                      ),
                    ),
                    child: Text(
                      role,
                      style: poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF4DA6FF),
                      ),
                    ),
                  ),
                  if (team != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        team,
                        style: poppins(
                          fontSize: 11,
                          color: const Color(0xFFC9D1E6),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 28),
              // Cosmic Slogan Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 22,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF0D1E3D).withValues(alpha: 0.8),
                      const Color(0xFF0F172A).withValues(alpha: 0.9),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFF00C48C).withValues(alpha: 0.25),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00C48C).withValues(alpha: 0.08),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00C48C).withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF00C48C).withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: const Icon(
                        Icons.rocket_launch_rounded,
                        color: Color(0xFF00C48C),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'COSMIC INSPIRATION',
                                style: GoogleFonts.spaceGrotesk(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF00C48C),
                                  letterSpacing: 1.5,
                                ),
                              ),
                              const Icon(
                                Icons.auto_awesome_rounded,
                                color: Color(0xFFFFB800),
                                size: 14,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '"$_slogan"',
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 14,
                              fontStyle: FontStyle.italic,
                              color: Colors.white.withValues(alpha: 0.95),
                              height: 1.4,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (_userDetails != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFF4DA6FF).withValues(alpha: 0.15),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.contact_page_rounded,
                            color: Color(0xFF4DA6FF),
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'My Profile Details',
                            style: poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          if (_loadingDetails) ...[
                            const SizedBox(width: 8),
                            const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: Color(0xFF4DA6FF),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const Divider(color: Colors.white10, height: 24),
                      _buildDetailRow(
                        Icons.phone_rounded,
                        'Phone Number',
                        _userDetails!['phone_number'] ?? 'N/A',
                      ),
                      const SizedBox(height: 14),
                      _buildDetailRow(
                        Icons.calendar_today_rounded,
                        'Date of Birth',
                        _userDetails!['dob'] ?? 'N/A',
                      ),
                      const SizedBox(height: 14),
                      _buildDetailRow(
                        Icons.school_rounded,
                        'Year of Study',
                        _userDetails!['year_of_study'] ?? 'N/A',
                      ),
                      const SizedBox(height: 14),
                      _buildDetailRow(
                        Icons.lan_rounded,
                        'Department',
                        _userDetails!['department'] ?? 'N/A',
                      ),
                      const SizedBox(height: 14),
                      _buildDetailRow(
                        Icons.link_rounded,
                        'LinkedIn',
                        _userDetails!['linkedin_url'] ?? 'N/A',
                        isLink: true,
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'About Myself',
                        style: poppins(
                          fontSize: 13,
                          color: const Color(0xFF8A9CC2),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _userDetails!['summary'] ?? 'No summary provided.',
                        style: poppins(
                          fontSize: 15,
                          color: Colors.white70,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFF4DA6FF).withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.rocket_launch_rounded,
                          color: Color(0xFF4DA6FF),
                          size: 28,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'SEDS Club Hub',
                          style: poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Stay tuned for upcoming space challenges, stargazing sessions, and workshops!',
                      style: poppins(
                        fontSize: 13,
                        color: const Color(0xFFC9D1E6),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      color: Color(0xFF4DA6FF),
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Pull down to refresh. Check the Schedule tab for upcoming meetings.',
                        style: poppins(
                          fontSize: 12,
                          color: const Color(0xFFC9D1E6),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────── Daily Logs Tab ───────────────
class DailyLogsTab extends StatelessWidget {
  final UserData? userData;
  const DailyLogsTab({super.key, this.userData});

  @override
  Widget build(BuildContext context) {
    final role = userData?.role;
    if (role == 'Admin' || role == 'SuperAdmin') {
      return LogsAdminPage(userData: userData);
    } else if (role == 'Lead') {
      return LogsLeadsPage(userData: userData);
    } else {
      return LogsMembersPage(userData: userData);
    }
  }
}

// ─────────────── Profile Tab ───────────────
class ProfileTab extends StatefulWidget {
  final UserData? userData;
  const ProfileTab({super.key, this.userData});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  final LocalAuthentication _auth = LocalAuthentication();
  bool _biometricsAvailable = false;
  bool _biometricsEnabled = false;
  bool _isLoadingBiometrics = true;

  @override
  void initState() {
    super.initState();
    _checkBiometricStatus();
  }

  Future<void> _checkBiometricStatus() async {
    try {
      final isSupported =
          await _auth.isDeviceSupported() || await _auth.canCheckBiometrics;
      final prefs = await SharedPreferences.getInstance();
      final isEnabled = prefs.getBool('biometric_enabled') ?? false;

      setState(() {
        _biometricsAvailable = isSupported;
        _biometricsEnabled = isEnabled;
        _isLoadingBiometrics = false;
      });
    } catch (_) {
      setState(() => _isLoadingBiometrics = false);
    }
  }

  Future<void> _toggleBiometrics() async {
    if (_biometricsEnabled) {
      // Prompt confirm to disable
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A2B4A),
          title: Text(
            'Disable Face / Fingerprint?',
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            'Are you sure you want to disable biometric Face or Fingerprint login on this device?',
            style: GoogleFonts.poppins(color: const Color(0xFFC9D1E6)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'Cancel',
                style: GoogleFonts.poppins(color: Colors.white54),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                'Disable',
                style: GoogleFonts.poppins(
                  color: const Color(0xFFFF6B6B),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );

      if (confirmed == true) {
        setState(() => _isLoadingBiometrics = true);
        try {
          final prefs = await SharedPreferences.getInstance();
          final email = widget.userData?.email ?? '';

          final res = await http
              .post(
                Uri.parse('$apiBaseUrl/api/biometric/register'),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({'email': email, 'biometricToken': null}),
              )
              .timeout(const Duration(seconds: 15));

          if (res.statusCode == 200) {
            await prefs.remove('biometric_enabled');
            await prefs.remove('biometric_key');
            await prefs.remove('biometric_email');
            setState(() {
              _biometricsEnabled = false;
            });
            if (mounted) AppToast.success(context, 'Biometric login disabled.');
          } else {
            if (mounted) {
              AppToast.error(
                context,
                'Failed to disable biometrics on server.',
              );
            }
          }
        } catch (_) {
          if (mounted) {
            AppToast.error(context, 'Connection error. Please try again.');
          }
        } finally {
          setState(() => _isLoadingBiometrics = false);
        }
      }
    } else {
      // Enable biometrics
      if (!_biometricsAvailable) {
        AppToast.warning(
          context,
          'Biometrics (fingerprint/face) not supported or set up on this device.',
        );
        return;
      }

      try {
        final authenticated = await _auth.authenticate(
          localizedReason:
              'Authenticate using Face or Fingerprint to enable Biometric Login',
          biometricOnly: false,
          persistAcrossBackgrounding: true,
        );

        if (authenticated) {
          if (!mounted) return;
          setState(() => _isLoadingBiometrics = true);
          final email = widget.userData?.email ?? '';
          if (email.isEmpty) {
            AppToast.error(
              context,
              'Cannot register biometrics for guest user.',
            );
            setState(() => _isLoadingBiometrics = false);
            return;
          }

          // Generate unique 64-char key
          final random = Random.secure();
          final values = List<int>.generate(32, (i) => random.nextInt(256));
          final token = base64Url.encode(values);

          final res = await http
              .post(
                Uri.parse('$apiBaseUrl/api/biometric/register'),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({'email': email, 'biometricToken': token}),
              )
              .timeout(const Duration(seconds: 15));

          if (res.statusCode == 200) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('biometric_enabled', true);
            await prefs.setString('biometric_key', token);
            await prefs.setString('biometric_email', email);
            setState(() {
              _biometricsEnabled = true;
            });
            if (mounted) {
              AppToast.success(
                context,
                'Fingerprint biometric login enabled successfully!',
              );
            }
          } else {
            final data = jsonDecode(res.body);
            if (mounted) {
              AppToast.error(
                context,
                data['message'] ?? 'Failed to register biometrics.',
              );
            }
          }
        }
      } catch (e) {
        if (mounted) {
          AppToast.error(
            context,
            'Biometric authentication failed or cancelled.',
          );
        }
      } finally {
        setState(() => _isLoadingBiometrics = false);
      }
    }
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final poppins = GoogleFonts.poppins;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF1A2B4A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 450),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B6B).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.logout_rounded,
                  color: Color(0xFFFF6B6B),
                  size: 30,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Logout?',
                style: poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Are you sure you want to logout from SEDS Portal?',
                textAlign: TextAlign.center,
                style: poppins(fontSize: 13, color: const Color(0xFFC9D1E6)),
              ),
              const SizedBox(height: 26),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.2),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: poppins(
                          color: const Color(0xFFC9D1E6),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF6B6B),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        'Logout',
                        style: poppins(fontWeight: FontWeight.w700),
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
    );
    if (confirmed == true && context.mounted) {
      await clearUserSession();
      if (context.mounted) {
        AppToast.success(context, 'Logged out successfully. See you! 👋');
        await Future.delayed(const Duration(milliseconds: 500));
        if (context.mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const LoginPage()),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final poppins = GoogleFonts.poppins;

    final String name = widget.userData?.name ?? 'Guest User';
    final String email = widget.userData?.email ?? 'guest@kumaraguruseds.space';
    final String role = widget.userData?.role ?? 'Guest';
    final String rollNumber = widget.userData?.rollNumber ?? '';
    final String? team = widget.userData?.team;
    final String? leadershipRole = widget.userData?.leadershipRole;
    final String? imageUrl = widget.userData?.imageUrl;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              // Avatar with profile image
              GestureDetector(
                onTap: () {
                  if (imageUrl != null && imageUrl.isNotEmpty) {
                    showDialog(
                      context: context,
                      barrierDismissible: true,
                      builder: (ctx) => Dialog(
                        backgroundColor: Colors.transparent,
                        insetPadding: const EdgeInsets.all(16),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            InteractiveViewer(
                              minScale: 0.5,
                              maxScale: 4.0,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: Image.network(
                                  imageUrl,
                                  fit: BoxFit.contain,
                                  loadingBuilder:
                                      (context, child, loadingProgress) {
                                        if (loadingProgress == null) {
                                          return child;
                                        }
                                        return const Center(
                                          child: CircularProgressIndicator(
                                            color: Color(0xFF4DA6FF),
                                          ),
                                        );
                                      },
                                  errorBuilder: (ctx, err, st) => Container(
                                    color: const Color(0xFF0D1E3A),
                                    padding: const EdgeInsets.all(24),
                                    child: const Icon(
                                      Icons.broken_image_outlined,
                                      color: Colors.white,
                                      size: 64,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 10,
                              right: 10,
                              child: CircleAvatar(
                                backgroundColor: Colors.black54,
                                radius: 20,
                                child: IconButton(
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                  onPressed: () => Navigator.pop(ctx),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                },
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF4DA6FF).withValues(alpha: 0.4),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                    border: Border.all(
                      color: const Color(0xFF4DA6FF).withValues(alpha: 0.5),
                      width: 2.5,
                    ),
                  ),
                  child: ClipOval(
                    child: imageUrl != null && imageUrl.isNotEmpty
                        ? Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            width: 100,
                            height: 100,
                            errorBuilder: (ctx, err, st) => Container(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Color(0xFF4B6EF5),
                                    Color(0xFF00C8FF),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.person_rounded,
                                  size: 48,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          )
                        : Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Color(0xFF4B6EF5), Color(0xFF00C8FF)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.person_rounded,
                                size: 48,
                                color: Colors.white,
                              ),
                            ),
                          ),
                  ),
                ),
              ),

              const SizedBox(height: 20),
              Text(
                name,
                style: poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                email,
                style: poppins(fontSize: 13, color: const Color(0xFFC9D1E6)),
              ),
              const SizedBox(height: 16),

              // Info Cards
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _profileRow(
                      poppins,
                      Icons.badge_outlined,
                      'Roll Number',
                      rollNumber.isNotEmpty ? rollNumber : 'N/A',
                    ),
                    const SizedBox(height: 14),
                    _profileRow(
                      poppins,
                      Icons.verified_user_outlined,
                      'Role',
                      role,
                    ),
                    if (team != null) ...[
                      const SizedBox(height: 14),
                      _profileRow(poppins, Icons.group_outlined, 'Team', team),
                    ],
                    if (leadershipRole != null) ...[
                      const SizedBox(height: 14),
                      _profileRow(
                        poppins,
                        Icons.star_outline_rounded,
                        'Position',
                        leadershipRole,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ── Meeting Schedule Navigation Row (All Users) ──
              ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFF4DA6FF).withValues(alpha: 0.25),
                      width: 1.5,
                    ),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => DesktopPageWrapper(
                              child: MemberMeetingSchedulePage(
                                userData: widget.userData,
                              ),
                            ),
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF4DA6FF,
                                ).withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.event_note_rounded,
                                color: Color(0xFF4DA6FF),
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Meeting Schedule',
                                    style: poppins(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'View and filter upcoming team meetings',
                                    style: poppins(
                                      fontSize: 11,
                                      color: const Color(0xFF8A9CC2),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.arrow_forward_ios_rounded,
                              color: Colors.white54,
                              size: 16,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],

              // Admin Custom Push Notification Button (For Admin/SuperAdmin only)
              if (role == 'Admin' || role == 'SuperAdmin') ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFF4DA6FF).withValues(alpha: 0.25),
                      width: 1.5,
                    ),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => DesktopPageWrapper(
                              child: AdminCustomNotificationPage(
                                userData: widget.userData,
                              ),
                            ),
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF4DA6FF,
                                ).withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.campaign_rounded,
                                color: Color(0xFF4DA6FF),
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Send Custom Notification',
                                    style: poppins(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Broadcast alerts to specific members or leads',
                                    style: poppins(
                                      fontSize: 11,
                                      color: const Color(0xFF8A9CC2),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.arrow_forward_ios_rounded,
                              color: Colors.white54,
                              size: 16,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              // ── Add New User Button (For Admin and Lead only) ──
              if (role == 'Admin' ||
                  role == 'SuperAdmin' ||
                  role == 'Lead') ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFF00C48C).withValues(alpha: 0.25),
                      width: 1.5,
                    ),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => DesktopPageWrapper(
                              child: AdminAddUserPage(
                                userData: widget.userData,
                                currentUserRole: role,
                              ),
                            ),
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF00C48C,
                                ).withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.person_add_alt_1_rounded,
                                color: Color(0xFF00C48C),
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Add New User',
                                    style: poppins(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w900,
                                      color: const Color(0xFF00C48C),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Register new Admin, Lead, or Member to a team',
                                    style: poppins(
                                      fontSize: 11,
                                      color: const Color(0xFF8A9CC2),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.arrow_forward_ios_rounded,
                              color: Colors.white54,
                              size: 16,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              // ── Analyse Users Button (For Admin only) ──
              if (role == 'Admin' || role == 'SuperAdmin') ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFFFFD93D).withValues(alpha: 0.25),
                      width: 1.5,
                    ),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const DesktopPageWrapper(
                              child: AnalyseUsersPage(),
                            ),
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFFFFD93D,
                                ).withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.analytics_rounded,
                                color: Color(0xFFFFD93D),
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Analyse Users',
                                    style: poppins(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'View all stored database logs, attendance and activity trail',
                                    style: poppins(
                                      fontSize: 11,
                                      color: const Color(0xFF8A9CC2),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.arrow_forward_ios_rounded,
                              color: Colors.white54,
                              size: 16,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],

              // ── Delete User Button (For Admin only) ──
              if (role == 'Admin' || role == 'SuperAdmin') ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFFFF6B6B).withValues(alpha: 0.25),
                      width: 1.5,
                    ),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => DesktopPageWrapper(
                              child: AdminDeleteUserPage(userData: widget.userData),
                            ),
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFFFF6B6B,
                                ).withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.person_remove_rounded,
                                color: Color(0xFFFF6B6B),
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Delete User Panel',
                                    style: poppins(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w900,
                                      color: const Color(0xFFFF6B6B),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Remove existing Admin, Lead, or Member from DB',
                                    style: poppins(
                                      fontSize: 11,
                                      color: const Color(0xFF8A9CC2),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.arrow_forward_ios_rounded,
                              color: Colors.white54,
                              size: 16,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFF4DA6FF).withValues(alpha: 0.25),
                    width: 1.5,
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => DesktopPageWrapper(
                            child: DocumentsPage(userData: widget.userData),
                          ),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF4DA6FF,
                              ).withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.folder_shared_rounded,
                              color: Color(0xFF4DA6FF),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Documents & Files',
                                  style: poppins(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Upload and view restricted team/personal files',
                                  style: poppins(
                                    fontSize: 11,
                                    color: const Color(0xFF8A9CC2),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.arrow_forward_ios_rounded,
                            color: Colors.white54,
                            size: 16,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ── Biometric fingerprint Login Setup Card ──
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _biometricsEnabled
                        ? const Color(0xFF00C48C).withValues(alpha: 0.25)
                        : Colors.white.withValues(alpha: 0.1),
                    width: 1.5,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color:
                              (_biometricsEnabled
                                      ? const Color(0xFF00C48C)
                                      : const Color(0xFF4DA6FF))
                                  .withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.fingerprint_rounded,
                          color: _biometricsEnabled
                              ? const Color(0xFF00C48C)
                              : const Color(0xFF4DA6FF),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Face / Fingerprint Login',
                              style: poppins(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _biometricsEnabled
                                  ? 'Biometrics active (Face / Fingerprint)'
                                  : 'Enable Face or Fingerprint login',
                              style: poppins(
                                fontSize: 11,
                                color: _biometricsEnabled
                                    ? const Color(0xFF00C48C)
                                    : const Color(0xFF8A9CC2),
                                fontWeight: _biometricsEnabled
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_isLoadingBiometrics)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF4DA6FF),
                          ),
                        )
                      else
                        Switch(
                          value: _biometricsEnabled,
                          onChanged: (_) => _toggleBiometrics(),
                          activeThumbColor: const Color(0xFF00C48C),
                          activeTrackColor: const Color(
                            0xFF00C48C,
                          ).withValues(alpha: 0.3),
                          inactiveThumbColor: Colors.white30,
                          inactiveTrackColor: Colors.white10,
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // ── New Feature Buttons ───────────────────────────────────

              // Apply Leave (all roles)
              _buildProfileNavButton(
                icon: Icons.event_available_rounded,
                label: 'Apply Leave',
                subtitle: (role == 'Admin' || role == 'Lead')
                    ? 'Apply leave & manage team requests'
                    : 'Apply for leave',
                color: const Color(0xFF9B59B6),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DesktopPageWrapper(
                      child: ApplyLeavePage(userData: widget.userData!),
                    ),
                  ),
                ),
                poppins: poppins,
              ),
              const SizedBox(height: 10),

              // Update Coordinates (Admin only)
              if (role == 'Admin') ...[
                _buildProfileNavButton(
                  icon: Icons.map_rounded,
                  label: 'Update Geofence',
                  subtitle: 'Upload KML or enter coordinates',
                  color: const Color(0xFF00C48C),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DesktopPageWrapper(
                        child: UpdateCoordinatesPage(userData: widget.userData!),
                      ),
                    ),
                  ),
                  poppins: poppins,
                ),
                const SizedBox(height: 10),
              ],

              const SizedBox(height: 14),

              // Logout Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _confirmLogout(context),
                  icon: const Icon(Icons.logout_rounded),
                  label: Text(
                    'Logout',
                    style: poppins(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6B6B),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _profileRow(
    TextStyle Function({
      Color? color,
      double? fontSize,
      FontWeight? fontWeight,
      double? letterSpacing,
    })
    poppins,
    IconData icon,
    String label,
    String value,
  ) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF4DA6FF), size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: poppins(fontSize: 11, color: const Color(0xFF8A9CC2)),
              ),
              Text(
                value,
                style: poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProfileNavButton({
    required IconData icon,
    required String label,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
    required TextStyle Function({
      Color? color,
      double? fontSize,
      FontWeight? fontWeight,
      double? letterSpacing,
    })
    poppins,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1.5),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: color,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: poppins(
                          fontSize: 11,
                          color: const Color(0xFF8A9CC2),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Colors.white54,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AdminCustomNotificationPage extends StatefulWidget {
  final UserData? userData;
  const AdminCustomNotificationPage({super.key, this.userData});

  @override
  State<AdminCustomNotificationPage> createState() =>
      _AdminCustomNotificationPageState();
}

class _AdminCustomNotificationPageState
    extends State<AdminCustomNotificationPage> {
  String _selectedType = 'Member'; // 'Member' or 'Leads'
  List<Map<String, dynamic>> _searchResults = [];
  final List<Map<String, dynamic>> _selectedUsers = [];
  String _selectedTeam = '';
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  bool _isSearching = false;
  bool _isSending = false;

  List<String> _teamOptions = [];

  @override
  void initState() {
    super.initState();
    _loadTeams();
  }

  Future<void> _loadTeams() async {
    final teams = await fetchUniqueTeams();
    if (mounted) {
      setState(() {
        _teamOptions = teams;
        if (teams.isNotEmpty) {
          _selectedTeam = teams.first;
        }
      });
    }
  }

  Future<void> _fetchUsers(String q) async {
    if (q.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }
    setState(() {
      _isSearching = true;
    });
    try {
      final response = await http
          .get(
            Uri.parse(
              '$apiBaseUrl/api/users/search?q=${Uri.encodeComponent(q)}',
            ),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _searchResults = List<Map<String, dynamic>>.from(data);
          });
        }
      }
    } catch (e) {
      debugPrint('Error searching users: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
      }
    }
  }

  Future<void> _sendCustomNotification() async {
    if (_selectedType == 'Member' && _selectedUsers.isEmpty) {
      AppToast.warning(context, 'Please select at least one recipient user.');
      return;
    }

    final message = _messageController.text.trim();
    if (message.isEmpty) {
      AppToast.warning(context, 'Please type the custom message.');
      return;
    }

    setState(() {
      _isSending = true;
    });

    try {
      final List<String> targetEmails = _selectedUsers
          .map((u) => u['email'] as String)
          .toList();
      final body = {
        'targetType': _selectedType == 'Member' ? 'Selected' : 'Leads',
        'targetTeam': _selectedTeam,
        'targetEmails': targetEmails,
        'message': message,
      };

      final response = await http
          .post(
            Uri.parse('$apiBaseUrl/api/notifications/custom'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final resData = jsonDecode(response.body);
        final count = resData['recipientCount'] ?? 0;
        if (mounted) {
          AppToast.success(context, 'Notification sent to $count recipients!');
          Navigator.pop(context); // Go back to profile tab
        }
      } else {
        final err =
            jsonDecode(response.body)['error'] ??
            'Failed to send notification.';
        throw Exception(err);
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(
          context,
          'Error: ${e.toString().replaceAll('Exception: ', '')}',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    TextStyle poppins({
      Color? color,
      double? fontSize,
      FontWeight? fontWeight,
      double? letterSpacing,
    }) {
      return GoogleFonts.poppins(
        color: color,
        fontSize: fontSize,
        fontWeight: fontWeight,
        letterSpacing: letterSpacing,
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF080F1F),
      extendBodyBehindAppBar: true,
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Send Custom Alert',
          style: poppins(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          // Background assets
          Positioned(
            left: 0,
            top: 0,
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.height,
            child: Image.asset(
              'assets/background.png',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  Container(color: const Color(0xFF080F1F)),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.height,
            child: Container(color: Colors.black.withValues(alpha: 0.45)),
          ),

          SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 10,
                bottom: MediaQuery.of(context).viewInsets.bottom + 32,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 56),
                  // Card Wrapper for Target Selection
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CHOOSE TARGET TYPE',
                          style: poppins(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF8A9CC2),
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: ChoiceChip(
                                label: Center(
                                  child: Text(
                                    'Specific Members',
                                    style: poppins(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: _selectedType == 'Member'
                                          ? Colors.white
                                          : const Color(0xFF8A9CC2),
                                    ),
                                  ),
                                ),
                                selected: _selectedType == 'Member',
                                selectedColor: const Color(0xFF4DA6FF),
                                backgroundColor: Colors.white.withValues(
                                  alpha: 0.04,
                                ),
                                onSelected: (val) {
                                  if (val) {
                                    setState(() {
                                      _selectedType = 'Member';
                                    });
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ChoiceChip(
                                label: Center(
                                  child: Text(
                                    'Team Leads',
                                    style: poppins(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: _selectedType == 'Leads'
                                          ? Colors.white
                                          : const Color(0xFF8A9CC2),
                                    ),
                                  ),
                                ),
                                selected: _selectedType == 'Leads',
                                selectedColor: const Color(0xFF4DA6FF),
                                backgroundColor: Colors.white.withValues(
                                  alpha: 0.04,
                                ),
                                onSelected: (val) {
                                  if (val) {
                                    setState(() {
                                      _selectedType = 'Leads';
                                    });
                                  }
                                },
                              ),
                            ),
                          ],
                        ),

                        if (_selectedType == 'Leads' &&
                            _selectedTeam.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          Text(
                            'SELECT TARGET TEAM',
                            style: poppins(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF8A9CC2),
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.1),
                              ),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _selectedTeam,
                                dropdownColor: const Color(0xFF162544),
                                isExpanded: true,
                                icon: const Icon(
                                  Icons.keyboard_arrow_down,
                                  color: Color(0xFF4DA6FF),
                                ),
                                items: _teamOptions.map((String val) {
                                  return DropdownMenuItem<String>(
                                    value: val,
                                    child: Text(
                                      val,
                                      style: poppins(
                                        fontSize: 13,
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() => _selectedTeam = val);
                                  }
                                },
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  if (_selectedType == 'Member') ...[
                    const SizedBox(height: 20),
                    // Selected Recipients Wrap
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'SELECTED RECIPIENTS (${_selectedUsers.length})',
                                style: poppins(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF8A9CC2),
                                  letterSpacing: 0.8,
                                ),
                              ),
                              if (_selectedUsers.isNotEmpty)
                                InkWell(
                                  onTap: () {
                                    setState(() {
                                      _selectedUsers.clear();
                                    });
                                  },
                                  child: Text(
                                    'Clear All',
                                    style: poppins(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: const Color(0xFFFF6B6B),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          if (_selectedUsers.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                'Search and tap users below to add them to this push notification.',
                                style: poppins(
                                  fontSize: 12,
                                  color: Colors.white38,
                                ),
                              ),
                            )
                          else
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _selectedUsers.map((user) {
                                return InputChip(
                                  label: Text(
                                    user['name'] ?? '',
                                    style: poppins(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                  backgroundColor: const Color(
                                    0xFF4DA6FF,
                                  ).withValues(alpha: 0.2),
                                  deleteIcon: const Icon(
                                    Icons.close,
                                    size: 14,
                                    color: Colors.white,
                                  ),
                                  onDeleted: () {
                                    setState(() {
                                      _selectedUsers.removeWhere(
                                        (u) => u['email'] == user['email'],
                                      );
                                    });
                                  },
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(30),
                                    side: const BorderSide(
                                      color: Color(0xFF4DA6FF),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),
                    // Search & Results Section
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'SEARCH USERS BY NAME / ROLL NUMBER',
                            style: poppins(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF8A9CC2),
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Search Input Field
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.1),
                              ),
                            ),
                            child: TextField(
                              controller: _searchController,
                              style: poppins(
                                fontSize: 13,
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Type to filter users...',
                                hintStyle: poppins(
                                  fontSize: 12,
                                  color: Colors.white38,
                                ),
                                prefixIcon: const Icon(
                                  Icons.search,
                                  color: Colors.white38,
                                ),
                                suffixIcon: _searchController.text.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(
                                          Icons.clear,
                                          color: Colors.white38,
                                        ),
                                        onPressed: () {
                                          _searchController.clear();
                                          _fetchUsers('');
                                        },
                                      )
                                    : null,
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                              ),
                              onChanged: (val) {
                                _fetchUsers(val);
                              },
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Results List
                          () {
                            if (_searchController.text.trim().isEmpty) {
                              return Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 20,
                                  ),
                                  child: Text(
                                    'Type a name or roll number to search.',
                                    style: poppins(
                                      fontSize: 12,
                                      color: Colors.white38,
                                    ),
                                  ),
                                ),
                              );
                            }

                            final filteredResults = _searchResults.where((
                              user,
                            ) {
                              final String email = user['email'] ?? '';
                              return !_selectedUsers.any(
                                (u) => u['email'] == email,
                              );
                            }).toList();

                            if (_isSearching) {
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.symmetric(vertical: 20),
                                  child: CircularProgressIndicator(
                                    color: Color(0xFF4DA6FF),
                                  ),
                                ),
                              );
                            } else if (filteredResults.isEmpty) {
                              return Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 20,
                                  ),
                                  child: Text(
                                    'No matching users found.',
                                    style: poppins(
                                      fontSize: 12,
                                      color: Colors.white38,
                                    ),
                                  ),
                                ),
                              );
                            } else {
                              return ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: filteredResults.length,
                                separatorBuilder: (context, index) => Divider(
                                  color: Colors.white.withValues(alpha: 0.05),
                                  height: 1,
                                ),
                                itemBuilder: (context, index) {
                                  final user = filteredResults[index];
                                  final String email = user['email'] ?? '';
                                  final String name = user['name'] ?? '';
                                  final String roll = user['roll_number'] ?? '';
                                  final String team = user['team'] ?? 'No Team';
                                  final String role = user['role'] ?? 'Member';

                                  final isAlreadySelected = _selectedUsers.any(
                                    (u) => u['email'] == email,
                                  );

                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: CircleAvatar(
                                      backgroundColor:
                                          (isAlreadySelected
                                                  ? Colors.green
                                                  : const Color(0xFF4DA6FF))
                                              .withValues(alpha: 0.15),
                                      child: Icon(
                                        isAlreadySelected
                                            ? Icons.check_circle_rounded
                                            : Icons.person_rounded,
                                        color: isAlreadySelected
                                            ? Colors.green
                                            : const Color(0xFF4DA6FF),
                                      ),
                                    ),
                                    title: Text(
                                      name,
                                      style: poppins(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    subtitle: Text(
                                      '$roll • $team ($role)',
                                      style: poppins(
                                        fontSize: 11,
                                        color: const Color(0xFF8A9CC2),
                                      ),
                                    ),
                                    trailing: IconButton(
                                      icon: Icon(
                                        isAlreadySelected
                                            ? Icons.remove_circle_outline
                                            : Icons.add_circle_rounded,
                                        color: isAlreadySelected
                                            ? const Color(0xFFFF6B6B)
                                            : const Color(0xFF00E676),
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          if (isAlreadySelected) {
                                            _selectedUsers.removeWhere(
                                              (u) => u['email'] == email,
                                            );
                                          } else {
                                            _selectedUsers.add({
                                              'email': email,
                                              'name': name,
                                              'roll_number': roll,
                                            });
                                          }
                                        });
                                      },
                                    ),
                                  );
                                },
                              );
                            }
                          }(),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),
                  // Message Area
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'MESSAGE CONTENT',
                          style: poppins(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF8A9CC2),
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.1),
                            ),
                          ),
                          child: TextField(
                            controller: _messageController,
                            maxLines: 5,
                            style: poppins(
                              fontSize: 13,
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                            decoration: InputDecoration(
                              hintText:
                                  'Type your custom push notification message here...',
                              hintStyle: poppins(
                                fontSize: 12,
                                color: Colors.white38,
                              ),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.all(12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 30),
                  // Action buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isSending
                              ? null
                              : () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: Text(
                            'Cancel',
                            style: poppins(
                              color: const Color(0xFF8A9CC2),
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _isSending
                              ? null
                              : _sendCustomNotification,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4DA6FF),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: _isSending
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : Text(
                                  'Send Push Notification',
                                  style: poppins(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────── Member Meeting Schedule Page ───────────────
class MemberMeetingSchedulePage extends StatelessWidget {
  final UserData? userData;
  const MemberMeetingSchedulePage({super.key, this.userData});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1E3A),
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Meeting Schedule',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          // Background image
          Positioned.fill(
            child: Image.asset(
              'assets/background.png',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(color: const Color(0xFF0D1E3A));
              },
            ),
          ),
          Positioned.fill(
            child: Container(color: Colors.black.withValues(alpha: 0.45)),
          ),
          Positioned.fill(child: MeetingScheduleTab(userData: userData)),
        ],
      ),
    );
  }
}

// ─────────────── Meeting Schedule Tab ───────────────
class MeetingScheduleTab extends StatefulWidget {
  final UserData? userData;
  const MeetingScheduleTab({super.key, this.userData});

  @override
  State<MeetingScheduleTab> createState() => _MeetingScheduleTabState();
}

class _MeetingScheduleTabState extends State<MeetingScheduleTab> {
  bool _isLoading = false;
  List<Map<String, dynamic>> _meetings = [];
  List<Map<String, dynamic>> _filteredMeetings = [];
  String? _errorMessage;
  late String _selectedTeamFilter;
  List<String> _teamOptions = ['All'];
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final isAdmin =
        widget.userData?.role == 'Admin' ||
        widget.userData?.role == 'SuperAdmin';
    final initialTeam = isAdmin ? 'All' : (widget.userData?.team ?? '');
    _selectedTeamFilter = initialTeam;
    _teamOptions = ['All'];
    if (initialTeam.isNotEmpty && initialTeam != 'All') {
      _teamOptions.add(initialTeam);
    }
    _fetchMeetings();
    _searchController.addListener(_applySearch);
    _loadTeams();
  }

  Future<void> _loadTeams() async {
    final teams = await fetchUniqueTeams();
    if (mounted) {
      setState(() {
        _teamOptions = ['All', ...teams];
      });
    }
  }

  @override
  void dispose() {
    _searchController.removeListener(_applySearch);
    _searchController.dispose();
    super.dispose();
  }

  void _applySearch() {
    final q = _searchController.text.trim().toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _filteredMeetings = List.from(_meetings);
      } else {
        _filteredMeetings = _meetings.where((m) {
          final date = (m['meeting_date'] ?? '').toString().toLowerCase();
          final venue = (m['venue'] ?? '').toString().toLowerCase();
          final status = (m['status'] ?? '').toString().toLowerCase();
          final team = (m['team_name'] ?? '').toString().toLowerCase();
          final agenda = (m['agenda'] ?? '').toString().toLowerCase();
          return date.contains(q) ||
              venue.contains(q) ||
              status.contains(q) ||
              team.contains(q) ||
              agenda.contains(q);
        }).toList();
      }
    });
  }

  Future<void> _fetchMeetings() async {
    if (_selectedTeamFilter.isEmpty) {
      setState(() {
        _errorMessage = 'No team assigned. Cannot load meetings.';
        _isLoading = false;
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final response = await http
          .get(
            Uri.parse(
              '$apiBaseUrl/api/meetings?team_name=${Uri.encodeComponent(_selectedTeamFilter)}',
            ),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          _meetings = data.map((e) => Map<String, dynamic>.from(e)).toList();
          _filteredMeetings = List.from(_meetings);
          _isLoading = false;
        });
        _applySearch();
      } else {
        setState(() {
          _errorMessage = 'Failed to load meetings.';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Connection error. Pull down to retry.';
        _isLoading = false;
      });
    }
  }

  Color _statusColor(String status) {
    switch (status.toUpperCase()) {
      case 'SCHEDULED':
        return const Color(0xFF4DA6FF);
      case 'COMPLETED':
        return const Color(0xFF00C48C);
      case 'CANCELLED':
        return const Color(0xFFFF6B6B);
      default:
        return const Color(0xFFC9D1E6);
    }
  }

  IconData _statusIcon(String status) {
    switch (status.toUpperCase()) {
      case 'SCHEDULED':
        return Icons.schedule_rounded;
      case 'COMPLETED':
        return Icons.check_circle_outline_rounded;
      case 'CANCELLED':
        return Icons.cancel_outlined;
      default:
        return Icons.help_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final poppins = GoogleFonts.poppins;
    final isAdmin =
        widget.userData?.role == 'Admin' ||
        widget.userData?.role == 'SuperAdmin';
    final team = widget.userData?.team ?? 'Your Team';

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _fetchMeetings,
        color: const Color(0xFF4DA6FF),
        backgroundColor: const Color(0xFF1A2B4A),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Meeting Schedule',
                              style: poppins(
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              isAdmin ? 'Admin Console' : team,
                              style: poppins(
                                fontSize: 13,
                                color: const Color(0xFF4DA6FF),
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          onPressed: _fetchMeetings,
                          icon: const Icon(
                            Icons.refresh_rounded,
                            color: Color(0xFF4DA6FF),
                            size: 26,
                          ),
                          tooltip: 'Refresh',
                        ),
                      ],
                    ),
                    if (isAdmin) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Text(
                            'Filter Team: ',
                            style: poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF8A9CC2),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.12),
                                ),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _selectedTeamFilter,
                                  dropdownColor: const Color(0xFF1A2B4A),
                                  icon: const Icon(
                                    Icons.keyboard_arrow_down,
                                    color: Color(0xFF4DA6FF),
                                  ),
                                  items: _teamOptions.map((String val) {
                                    return DropdownMenuItem<String>(
                                      value: val,
                                      child: Text(
                                        val,
                                        style: poppins(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (newValue) {
                                    if (newValue != null) {
                                      setState(() {
                                        _selectedTeamFilter = newValue;
                                      });
                                      _fetchMeetings();
                                    }
                                  },
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    // ── Search Bar ──
                    const SizedBox(height: 14),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                        ),
                      ),
                      child: TextField(
                        controller: _searchController,
                        style: poppins(
                          fontSize: 14,
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search by date, venue, team…',
                          hintStyle: poppins(
                            fontSize: 13,
                            color: const Color(0xFF8A9CC2),
                          ),
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            color: Color(0xFF4DA6FF),
                            size: 20,
                          ),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    color: Color(0xFF8A9CC2),
                                    size: 18,
                                  ),
                                  onPressed: () {
                                    _searchController.clear();
                                    _applySearch();
                                  },
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_isLoading)
              const SliverFillRemaining(
                child: Center(
                  child: CircularProgressIndicator(color: Color(0xFF4DA6FF)),
                ),
              )
            else if (_errorMessage != null)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.cloud_off_rounded,
                        color: Color(0xFF8A9CC2),
                        size: 48,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: poppins(
                          fontSize: 14,
                          color: const Color(0xFF8A9CC2),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else if (_filteredMeetings.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.event_busy_rounded,
                        color: Color(0xFF8A9CC2),
                        size: 56,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _searchController.text.isNotEmpty
                            ? 'No meetings match your search.'
                            : 'No meetings scheduled.',
                        style: poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Pull down to refresh.',
                        style: poppins(
                          fontSize: 13,
                          color: const Color(0xFF8A9CC2),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((ctx, i) {
                    final m = _filteredMeetings[i];
                    final status = (m['status'] ?? 'SCHEDULED')
                        .toString()
                        .toUpperCase();
                    final statusColor = _statusColor(status);
                    final agenda = (m['agenda']?.toString() ?? '').trim();

                    // Split agenda into lines for table view
                    final agendaLines = agenda.isNotEmpty
                        ? agenda
                              .split('\n')
                              .where((l) => l.trim().isNotEmpty)
                              .toList()
                        : <String>[];

                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: statusColor.withValues(alpha: 0.25),
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Status Banner (Glassy) ──
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.12),
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(14),
                              ),
                              border: Border(
                                bottom: BorderSide(
                                  color: statusColor.withValues(alpha: 0.20),
                                  width: 1,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _statusIcon(status),
                                  color: statusColor,
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  status,
                                  style: poppins(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: statusColor,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    m['meeting_mode']?.toString() ?? '',
                                    style: poppins(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: statusColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // ── Details Table ──
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (isAdmin && m['team_name'] != null) ...[
                                  _meetingTableRow(
                                    poppins,
                                    Icons.group_work_rounded,
                                    'Team Name',
                                    m['team_name'].toString(),
                                    color: const Color(0xFF4DA6FF),
                                  ),
                                  const SizedBox(height: 10),
                                ],
                                _meetingTableRow(
                                  poppins,
                                  Icons.calendar_today_rounded,
                                  'Date',
                                  m['meeting_date']?.toString() ?? '',
                                  color: const Color(0xFFF0A500),
                                ),
                                const SizedBox(height: 10),
                                _meetingTableRow(
                                  poppins,
                                  Icons.access_time_rounded,
                                  'Time',
                                  '${m['start_time']} – ${m['end_time']}',
                                  color: const Color(0xFF00C8C8),
                                ),
                                const SizedBox(height: 10),
                                _meetingTableRow(
                                  poppins,
                                  Icons.location_on_rounded,
                                  'Venue',
                                  m['venue']?.toString() ?? '',
                                  color: const Color(0xFFFF6B6B),
                                ),

                                if (agendaLines.isNotEmpty) ...[
                                  const SizedBox(height: 14),
                                  // ── Agenda Table (Glassy style) ──
                                  Container(
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.03,
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: Colors.white.withValues(
                                          alpha: 0.08,
                                        ),
                                        width: 1,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // Agenda header
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(
                                              alpha: 0.05,
                                            ),
                                            borderRadius:
                                                const BorderRadius.vertical(
                                                  top: Radius.circular(10),
                                                ),
                                            border: Border(
                                              bottom: BorderSide(
                                                color: Colors.white.withValues(
                                                  alpha: 0.08,
                                                ),
                                                width: 1,
                                              ),
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              const Icon(
                                                Icons.list_alt_rounded,
                                                color: Color(0xFF4DA6FF),
                                                size: 15,
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                'AGENDA',
                                                style: poppins(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w800,
                                                  color: const Color(
                                                    0xFF4DA6FF,
                                                  ),
                                                  letterSpacing: 1.0,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        // Agenda rows
                                        ...agendaLines.asMap().entries.map((
                                          entry,
                                        ) {
                                          final idx = entry.key;
                                          final line = entry.value.trim();
                                          final isLast =
                                              idx == agendaLines.length - 1;
                                          return Container(
                                            decoration: BoxDecoration(
                                              border: isLast
                                                  ? null
                                                  : Border(
                                                      bottom: BorderSide(
                                                        color: Colors.white
                                                            .withValues(
                                                              alpha: 0.08,
                                                            ),
                                                        width: 0.8,
                                                      ),
                                                    ),
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 9,
                                            ),
                                            child: Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                // Row number
                                                Container(
                                                  width: 22,
                                                  height: 22,
                                                  decoration: BoxDecoration(
                                                    color: const Color(
                                                      0xFF4DA6FF,
                                                    ).withValues(alpha: 0.15),
                                                    shape: BoxShape.circle,
                                                  ),
                                                  alignment: Alignment.center,
                                                  child: Text(
                                                    '${idx + 1}',
                                                    style: poppins(
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: const Color(
                                                        0xFF4DA6FF,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: Text(
                                                    line,
                                                    style: poppins(
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        }),
                                      ],
                                    ),
                                  ),
                                ] else if (agenda.isNotEmpty) ...[
                                  // Single-line agenda (no newlines)
                                  const SizedBox(height: 14),
                                  Container(
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.03,
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: Colors.white.withValues(
                                          alpha: 0.08,
                                        ),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(
                                              alpha: 0.05,
                                            ),
                                            borderRadius:
                                                const BorderRadius.vertical(
                                                  top: Radius.circular(10),
                                                ),
                                            border: Border(
                                              bottom: BorderSide(
                                                color: Colors.white.withValues(
                                                  alpha: 0.08,
                                                ),
                                              ),
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              const Icon(
                                                Icons.list_alt_rounded,
                                                color: Color(0xFF4DA6FF),
                                                size: 15,
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                'AGENDA',
                                                style: poppins(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w800,
                                                  color: const Color(
                                                    0xFF4DA6FF,
                                                  ),
                                                  letterSpacing: 1.0,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.all(14),
                                          child: Text(
                                            agenda,
                                            style: poppins(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }, childCount: _filteredMeetings.length),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _meetingTableRow(
    TextStyle Function({
      Color? color,
      double? fontSize,
      FontWeight? fontWeight,
      double? letterSpacing,
    })
    poppins,
    IconData icon,
    String label,
    String value, {
    Color color = const Color(0xFF4DA6FF),
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: poppins(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF8A9CC2),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ── AdminAddUserPage — Admin Option to Add new Admins, Leads, or Members ──
// ─────────────────────────────────────────────────────────────────────────────
class AdminAddUserPage extends StatefulWidget {
  final UserData? userData;
  final String currentUserRole;
  const AdminAddUserPage({
    super.key,
    this.userData,
    required this.currentUserRole,
  });

  @override
  State<AdminAddUserPage> createState() => _AdminAddUserPageState();
}

class _AdminAddUserPageState extends State<AdminAddUserPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _rollController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _newTeamController = TextEditingController();
  final _imageUrlController = TextEditingController();

  String _selectedRole = 'Member';
  String _selectedTeam = '';
  bool _isSaving = false;

  late final List<String> _roles;
  List<String> _teamOptions = ['Add New Team...'];

  @override
  void initState() {
    super.initState();
    if (widget.currentUserRole == 'Admin' ||
        widget.currentUserRole == 'SuperAdmin') {
      _roles = ['Member', 'Lead', 'Admin'];
    } else {
      _roles = ['Member', 'Lead'];
    }
    _selectedRole = _roles.first;
    _loadTeams();
  }

  Future<void> _loadTeams() async {
    final teams = await fetchUniqueTeams();
    if (mounted) {
      setState(() {
        _teamOptions = [...teams, 'Add New Team...'];
        if (teams.isNotEmpty) {
          _selectedTeam = teams.first;
        } else {
          _selectedTeam = 'Add New Team...';
        }
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _rollController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _newTeamController.dispose();
    _imageUrlController.dispose();
    super.dispose();
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    final String finalTeam = (_selectedRole == 'Admin')
        ? ''
        : (_selectedTeam == 'Add New Team...'
              ? _newTeamController.text.trim()
              : _selectedTeam);

    if (_selectedRole != 'Admin' && finalTeam.isEmpty) {
      AppToast.warning(context, 'Please select or enter a valid team name.');
      return;
    }

    setState(() => _isSaving = true);

    try {
      final response = await http
          .post(
            Uri.parse('$apiBaseUrl/api/admin/add-user'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'name': _nameController.text.trim(),
              'roll_number': _rollController.text.trim(),
              'email': _emailController.text.trim(),
              'password': _passwordController.text.trim(),
              'role': _selectedRole,
              'team': finalTeam,
              'image_url': _imageUrlController.text.trim(),
            }),
          )
          .timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);

      if (mounted) {
        if (response.statusCode == 200 && data['success'] == true) {
          AppToast.success(
            context,
            data['message'] ?? 'Successfully added user.',
          );
          Navigator.pop(context);
        } else {
          AppToast.error(context, data['message'] ?? 'Error occurred.');
        }
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'Connection error: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    TextStyle poppins({
      Color? color,
      double? fontSize,
      FontWeight? fontWeight,
      double? letterSpacing,
    }) {
      FontWeight finalWeight = fontWeight ?? FontWeight.bold;
      if (finalWeight == FontWeight.normal) {
        finalWeight = FontWeight.bold;
      }
      Color? finalColor = color;
      if (color == Colors.white30 ||
          color == Colors.white38 ||
          color == Colors.white24 ||
          color == const Color(0xFF8A9CC2)) {
        finalColor = Colors.white70;
      } else if (color == const Color(0xFFC9D1E6)) {
        finalColor = Colors.white;
      }
      return GoogleFonts.poppins(
        color: finalColor ?? Colors.white,
        fontSize: fontSize,
        fontWeight: finalWeight,
        letterSpacing: letterSpacing,
      );
    }

    return Stack(
      children: [
        // Background assets
        Positioned.fill(
          child: Image.asset(
            'assets/background.png',
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                Container(color: const Color(0xFF080F1F)),
          ),
        ),
        Positioned.fill(
          child: Container(color: Colors.black.withValues(alpha: 0.45)),
        ),

        Scaffold(
          backgroundColor: Colors.transparent,
          extendBodyBehindAppBar: true,
          resizeToAvoidBottomInset: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Colors.white,
              ),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              'Add New User',
              style: poppins(
                fontWeight: FontWeight.bold,
                color: Colors.white,
                fontSize: 18,
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(
                  Icons.drive_folder_upload_rounded,
                  color: Colors.white,
                ),
                tooltip: 'Bulk Import from Excel',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          AdminBulkImportPage(userData: widget.userData),
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
            ],
            centerTitle: true,
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 10,
                bottom: MediaQuery.of(context).viewInsets.bottom + 32,
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Register User Details',
                      style: poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF00C48C),
                      ),
                    ),
                    Text(
                      'Fill in details to add a new admin, lead or team member.',
                      style: poppins(
                        fontSize: 12,
                        color: const Color(0xFF8A9CC2),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Card Form Container
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 15,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Name Field ──
                          Text(
                            'Full Name',
                            style: poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF4DA6FF),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _nameController,
                            style: poppins(fontSize: 14, color: Colors.white),
                            decoration: InputDecoration(
                              hintText: 'Enter full name',
                              hintStyle: poppins(
                                fontSize: 13,
                                color: Colors.white30,
                              ),
                              filled: true,
                              fillColor: Colors.white.withValues(alpha: 0.05),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: Color(0xFF4DA6FF),
                                  width: 1.5,
                                ),
                              ),
                            ),
                            validator: (val) =>
                                (val == null || val.trim().isEmpty)
                                ? 'Please enter a name'
                                : null,
                          ),
                          const SizedBox(height: 18),

                          // ── Roll Number Field ──
                          Text(
                            'Roll Number',
                            style: poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF4DA6FF),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _rollController,
                            style: poppins(fontSize: 14, color: Colors.white),
                            decoration: InputDecoration(
                              hintText: 'Enter roll number (e.g. 23BAE003)',
                              hintStyle: poppins(
                                fontSize: 13,
                                color: Colors.white30,
                              ),
                              filled: true,
                              fillColor: Colors.white.withValues(alpha: 0.05),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: Color(0xFF4DA6FF),
                                  width: 1.5,
                                ),
                              ),
                            ),
                            validator: (val) =>
                                (val == null || val.trim().isEmpty)
                                ? 'Please enter roll number'
                                : null,
                          ),
                          const SizedBox(height: 18),

                          // ── Email Field ──
                          Text(
                            'Email Address',
                            style: poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF4DA6FF),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            style: poppins(fontSize: 14, color: Colors.white),
                            decoration: InputDecoration(
                              hintText: 'Enter email address',
                              hintStyle: poppins(
                                fontSize: 13,
                                color: Colors.white30,
                              ),
                              filled: true,
                              fillColor: Colors.white.withValues(alpha: 0.05),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: Color(0xFF4DA6FF),
                                  width: 1.5,
                                ),
                              ),
                            ),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) {
                                return 'Please enter an email';
                              }
                              if (!val.contains('@')) {
                                return 'Please enter a valid email address';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 18),

                          // ── Password Field ──
                          Text(
                            'Password',
                            style: poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF4DA6FF),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: true,
                            style: poppins(fontSize: 14, color: Colors.white),
                            decoration: InputDecoration(
                              hintText: 'Enter password',
                              hintStyle: poppins(
                                fontSize: 13,
                                color: Colors.white30,
                              ),
                              filled: true,
                              fillColor: Colors.white.withValues(alpha: 0.05),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: Color(0xFF4DA6FF),
                                  width: 1.5,
                                ),
                              ),
                            ),
                            validator: (val) {
                              if (val == null || val.isEmpty) {
                                return 'Please enter a password';
                              }
                              if (val.length < 4) {
                                return 'Password must be at least 4 characters';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 18),

                          // ── Image URL Field ──
                          Text(
                            'Profile Image URL',
                            style: poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF4DA6FF),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _imageUrlController,
                            style: poppins(fontSize: 14, color: Colors.white),
                            decoration: InputDecoration(
                              hintText: 'Enter profile image URL',
                              hintStyle: poppins(
                                fontSize: 13,
                                color: Colors.white30,
                              ),
                              filled: true,
                              fillColor: Colors.white.withValues(alpha: 0.05),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: Color(0xFF4DA6FF),
                                  width: 1.5,
                                ),
                              ),
                            ),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) {
                                return 'Please enter profile image URL';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 18),

                          // ── Role Selector ──
                          Text(
                            'Role',
                            style: poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF4DA6FF),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.1),
                              ),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _selectedRole,
                                dropdownColor: const Color(0xFF162544),
                                isExpanded: true,
                                icon: const Icon(
                                  Icons.keyboard_arrow_down,
                                  color: Color(0xFF4DA6FF),
                                ),
                                items: _roles.map((String val) {
                                  return DropdownMenuItem<String>(
                                    value: val,
                                    child: Text(
                                      val,
                                      style: poppins(
                                        fontSize: 13,
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() => _selectedRole = val);
                                  }
                                },
                              ),
                            ),
                          ),

                          // ── Team Selector (Only if role is NOT Admin) ──
                          if (_selectedRole != 'Admin' &&
                              _selectedTeam.isNotEmpty) ...[
                            const SizedBox(height: 18),
                            Text(
                              'Team Assignment',
                              style: poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF4DA6FF),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.1),
                                ),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _selectedTeam,
                                  dropdownColor: const Color(0xFF162544),
                                  isExpanded: true,
                                  icon: const Icon(
                                    Icons.keyboard_arrow_down,
                                    color: Color(0xFF4DA6FF),
                                  ),
                                  items: _teamOptions.map((String val) {
                                    return DropdownMenuItem<String>(
                                      value: val,
                                      child: Text(
                                        val,
                                        style: poppins(
                                          fontSize: 13,
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (val) {
                                    if (val != null) {
                                      setState(() => _selectedTeam = val);
                                    }
                                  },
                                ),
                              ),
                            ),

                            // ── Add New Team Input Field (Only if selected "Add New Team...") ──
                            if (_selectedTeam == 'Add New Team...') ...[
                              const SizedBox(height: 18),
                              Text(
                                'New Team Name',
                                style: poppins(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF4DA6FF),
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _newTeamController,
                                style: poppins(
                                  fontSize: 14,
                                  color: Colors.white,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Enter new team name',
                                  hintStyle: poppins(
                                    fontSize: 13,
                                    color: Colors.white30,
                                  ),
                                  filled: true,
                                  fillColor: Colors.white.withValues(
                                    alpha: 0.05,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 14,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(
                                      color: Color(0xFF4DA6FF),
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                                validator: (val) =>
                                    (val == null || val.trim().isEmpty)
                                    ? 'Please enter new team name'
                                    : null,
                              ),
                            ],
                          ],

                          const SizedBox(height: 28),

                          // ── Submit Button ──
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _isSaving ? null : _submitForm,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF00C48C),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                elevation: 0,
                              ),
                              child: _isSaving
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(
                                      'Add User',
                                      style: poppins(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          const Divider(color: Colors.white10),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => AdminBulkImportPage(
                                      userData: widget.userData,
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(
                                Icons.drive_folder_upload_rounded,
                                color: Color(0xFF00FF87),
                                size: 18,
                              ),
                              label: Text(
                                'Bulk Import via Excel (.xlsx)',
                                style: poppins(
                                  fontSize: 14,
                                  color: const Color(0xFF00FF87),
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(
                                  color: Color(0xFF00FF87),
                                  width: 1.5,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class AdminBulkImportPage extends StatefulWidget {
  final UserData? userData;
  const AdminBulkImportPage({super.key, this.userData});

  @override
  State<AdminBulkImportPage> createState() => _AdminBulkImportPageState();
}

class _AdminBulkImportPageState extends State<AdminBulkImportPage> {
  PlatformFile? _selectedFile;
  bool _isUploading = false;
  String? _uploadSummary;
  List<Map<String, dynamic>> _errors = [];
  List<String> _terminalLogs = [];
  final ScrollController _terminalScrollController = ScrollController();

  TextStyle poppins({
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
    double? letterSpacing,
  }) {
    FontWeight finalWeight = fontWeight ?? FontWeight.bold;
    if (finalWeight == FontWeight.normal) {
      finalWeight = FontWeight.bold;
    }
    Color? finalColor = color;
    if (color == Colors.white30 ||
        color == Colors.white38 ||
        color == Colors.white24 ||
        color == const Color(0xFF8A9CC2)) {
      finalColor = Colors.white70;
    } else if (color == const Color(0xFFC9D1E6)) {
      finalColor = Colors.white;
    }
    return GoogleFonts.poppins(
      color: finalColor ?? Colors.white,
      fontSize: fontSize,
      fontWeight: finalWeight,
      letterSpacing: letterSpacing,
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_terminalScrollController.hasClients) {
        _terminalScrollController.animateTo(
          _terminalScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        withData: true,
      );

      if (result != null) {
        setState(() {
          _selectedFile = result.files.first;
          _uploadSummary = null;
          _errors = [];
          _terminalLogs = [];
        });
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'Error picking file: $e');
      }
    }
  }

  Future<void> _downloadTemplate() async {
    try {
      final url = Uri.parse('$apiBaseUrl/api/admin/sample-template');
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          AppToast.error(
            context,
            'Could not open browser to download template.',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'Error: $e');
      }
    }
  }

  Future<void> _uploadFile() async {
    if (_selectedFile == null) return;

    setState(() {
      _isUploading = true;
      _uploadSummary = null;
      _errors = [];
      _terminalLogs = [
        '[SYSTEM] Initializing bulk user import module...',
        '[SYSTEM] Handshake check with SEDS AWS server on port 443...',
        '[FILE] Loaded Excel spreadsheet target successfully.',
        '[FILE] Name: ${_selectedFile!.name}',
        '[FILE] Size: ${(_selectedFile!.size / 1024).toStringAsFixed(2)} KB',
        '[HTTP] Uploading payload to /api/admin/bulk-add-users...',
      ];
    });
    _scrollToBottom();

    try {
      final uri = Uri.parse('$apiBaseUrl/api/admin/bulk-add-users');
      final request = http.MultipartRequest('POST', uri);

      if (_selectedFile!.bytes != null) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'file',
            _selectedFile!.bytes!,
            filename: _selectedFile!.name,
          ),
        );
      } else if (_selectedFile!.path != null) {
        request.files.add(
          await http.MultipartFile.fromPath('file', _selectedFile!.path!),
        );
      } else {
        throw Exception("File contains no readable bytes.");
      }

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 30),
      );
      final response = await http.Response.fromStream(streamedResponse);
      final data = jsonDecode(response.body);

      if (mounted) {
        if (response.statusCode == 200 && data['success'] == true) {
          setState(() {
            _terminalLogs.add(
              '[HTTP] 200 OK. Backend parsed XLSX successfully.',
            );
            _terminalLogs.add(
              '[SYSTEM] Starting write validation to PostgreSQL DB...',
            );
          });
          _scrollToBottom();

          final details = data['details'] ?? {};
          final List successes = details['success'] ?? [];
          final List errors = details['errors'] ?? [];

          // Print success logs line-by-line to UI terminal
          for (var item in successes) {
            await Future.delayed(const Duration(milliseconds: 120));
            if (!mounted) return;
            setState(() {
              _terminalLogs.add(
                '[DB SUCCESS] Created ${item['role']} "${item['name']}" (${item['emailLc']})',
              );
            });
            _scrollToBottom();
          }

          // Print error logs line-by-line to UI terminal
          for (var item in errors) {
            await Future.delayed(const Duration(milliseconds: 120));
            if (!mounted) return;
            setState(() {
              _terminalLogs.add(
                '[DB ERROR] Row ${item['row']}: ${item['message']}',
              );
            });
            _scrollToBottom();
          }

          setState(() {
            _uploadSummary = data['summary'];
            _terminalLogs.add('[SYSTEM] Import task completed.');
            _terminalLogs.add(
              '[SYSTEM] Successes: ${successes.length} | Errors: ${errors.length}',
            );
            if (errors.isNotEmpty) {
              _errors = List<Map<String, dynamic>>.from(
                errors.map((e) => Map<String, dynamic>.from(e)),
              );
            }
          });
          _scrollToBottom();

          // Trigger Local Notification response
          try {
            await NotificationService().showLocalNotification(
              title: 'SEDS Bulk Import Completed',
              body:
                  'Successfully added ${successes.length} users (${errors.length} errors).',
            );
          } catch (ne) {
            debugPrint('Failed to show local notification: $ne');
          }

          if (mounted) {
            AppToast.success(context, 'Import complete!');
          }
        } else {
          setState(() {
            _terminalLogs.add(
              '[HTTP ERROR] Remote parsing failed: ${data['message']}',
            );
          });
          _scrollToBottom();
          if (mounted) {
            AppToast.error(context, data['message'] ?? 'Import failed');
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _terminalLogs.add('[FATAL ERROR] Upload process failed: $e');
        });
        _scrollToBottom();
        AppToast.error(context, 'Upload error: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            'assets/background.png',
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                Container(color: const Color(0xFF080F1F)),
          ),
        ),
        Positioned.fill(
          child: Container(color: Colors.black.withValues(alpha: 0.45)),
        ),
        Scaffold(
          backgroundColor: Colors.transparent,
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Colors.white,
              ),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              'Bulk Import Users',
              style: poppins(
                fontWeight: FontWeight.bold,
                color: Colors.white,
                fontSize: 18,
              ),
            ),
            centerTitle: true,
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Import users in bulk via Excel',
                    style: poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF00C48C),
                    ),
                  ),
                  Text(
                    'Upload a spreadsheet containing user details. Support adding Admins, Leads, or Members.',
                    style: poppins(
                      fontSize: 12,
                      color: const Color(0xFF8A9CC2),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Download template card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Excel File Requirements:',
                          style: poppins(
                            fontSize: 13,
                            color: const Color(0xFF4DA6FF),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '• Headers must match: name, roll_number, email, password_hash, team, role, image_url',
                          style: poppins(fontSize: 11, color: Colors.white70),
                        ),
                        Text(
                          '• Roles allowed: Admin, Lead, Member (case-insensitive)',
                          style: poppins(fontSize: 11, color: Colors.white70),
                        ),
                        Text(
                          '• Team is required for Lead and Member roles',
                          style: poppins(fontSize: 11, color: Colors.white70),
                        ),
                        Text(
                          '• Passwords will be automatically encrypted and hashed',
                          style: poppins(fontSize: 11, color: Colors.white70),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _downloadTemplate,
                            icon: const Icon(Icons.download_rounded, size: 18),
                            label: const Text('Download Sample Template'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1E2B4A),
                              foregroundColor: const Color(0xFF4DA6FF),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // File selection section
                  Text(
                    'Select Excel File (.xlsx)',
                    style: poppins(fontSize: 14, color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: _isUploading ? null : _pickFile,
                    child: Container(
                      width: double.infinity,
                      height: 120,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _selectedFile != null
                              ? const Color(0xFF00FF87)
                              : Colors.white12,
                          style: BorderStyle.solid,
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _selectedFile != null
                                ? Icons.file_present_rounded
                                : Icons.drive_folder_upload_rounded,
                            size: 36,
                            color: _selectedFile != null
                                ? const Color(0xFF00FF87)
                                : Colors.white30,
                          ),
                          const SizedBox(height: 10),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16.0,
                            ),
                            child: Text(
                              _selectedFile != null
                                  ? _selectedFile!.name
                                  : 'Tap to select Excel file',
                              style: poppins(
                                fontSize: 13,
                                color: _selectedFile != null
                                    ? Colors.white
                                    : Colors.white30,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_selectedFile != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              '${(_selectedFile!.size / 1024).toStringAsFixed(1)} KB',
                              style: poppins(
                                fontSize: 10,
                                color: Colors.white38,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Upload button
                  if (_selectedFile != null) ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isUploading ? null : _uploadFile,
                        icon: _isUploading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.cloud_upload_rounded),
                        label: Text(
                          _isUploading
                              ? 'Uploading & Parsing...'
                              : 'Import Users',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00C48C),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Terminal Process Log
                  if (_terminalLogs.isNotEmpty) ...[
                    Text(
                      'Terminal Process Log',
                      style: poppins(fontSize: 14, color: Colors.white70),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      height: 220,
                      decoration: BoxDecoration(
                        color: const Color(0xFF070B19),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFF4DA6FF).withValues(alpha: 0.3),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFF4DA6FF,
                            ).withValues(alpha: 0.1),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Scrollbar(
                        controller: _terminalScrollController,
                        thumbVisibility: true,
                        child: ListView.builder(
                          controller: _terminalScrollController,
                          itemCount: _terminalLogs.length,
                          itemBuilder: (context, idx) {
                            final log = _terminalLogs[idx];
                            Color textColor = Colors.white;
                            if (log.startsWith('[DB SUCCESS]')) {
                              textColor = const Color(0xFF00FF87);
                            } else if (log.startsWith('[DB ERROR]') ||
                                log.startsWith('[FATAL ERROR]') ||
                                log.startsWith('[HTTP ERROR]')) {
                              textColor = const Color(0xFFFF4D4D);
                            } else if (log.startsWith('[SYSTEM]')) {
                              textColor = const Color(0xFF4DA6FF);
                            } else if (log.startsWith('[FILE]')) {
                              textColor = const Color(0xFFFFC048);
                            }
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 6.0),
                              child: Text(
                                log,
                                style: GoogleFonts.firaMono(
                                  color: textColor,
                                  fontSize: 11,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Import results summary
                  if (_uploadSummary != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00C48C).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF00C48C).withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.check_circle_rounded,
                            color: Color(0xFF00FF87),
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _uploadSummary!,
                              style: poppins(fontSize: 12, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Detailed parsing errors
                  if (_errors.isNotEmpty) ...[
                    Text(
                      'Encountered Errors (${_errors.length})',
                      style: poppins(
                        fontSize: 14,
                        color: const Color(0xFFFF6B6B),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _errors.length,
                      itemBuilder: (context, index) {
                        final err = _errors[index];
                        return Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFFFF6B6B,
                            ).withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: const Color(
                                0xFFFF6B6B,
                              ).withValues(alpha: 0.25),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Row ${err['row'] ?? 'N/A'}',
                                style: poppins(
                                  fontSize: 11,
                                  color: const Color(0xFFFF6B6B),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                err['message'] ?? 'Unknown error',
                                style: poppins(
                                  fontSize: 12,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ── AdminDeleteUserPage — Admin User Deletion Dashboard ──
// ─────────────────────────────────────────────────────────────────────────────
class AdminDeleteUserPage extends StatefulWidget {
  final UserData? userData;
  const AdminDeleteUserPage({super.key, this.userData});

  @override
  State<AdminDeleteUserPage> createState() => _AdminDeleteUserPageState();
}

class _AdminDeleteUserPageState extends State<AdminDeleteUserPage> {
  List<dynamic> _allUsers = [];
  List<dynamic> _filteredUsers = [];
  bool _isLoading = true;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchUsers() async {
    setState(() => _isLoading = true);
    try {
      final response = await http
          .get(Uri.parse('$apiBaseUrl/api/admin/users'))
          .timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        setState(() {
          _allUsers = data['users'] ?? [];
          _filterUsers(_searchQuery);
        });
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'Error loading users: $e');
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _filterUsers(String query) {
    _searchQuery = query.toLowerCase();
    setState(() {
      _filteredUsers = _allUsers.where((u) {
        final name = (u['name'] ?? '').toString().toLowerCase();
        final email = (u['email'] ?? '').toString().toLowerCase();
        final roll = (u['roll_number'] ?? '').toString().toLowerCase();
        final role = (u['role'] ?? '').toString().toLowerCase();
        final team = (u['team'] ?? '').toString().toLowerCase();
        return name.contains(_searchQuery) ||
            email.contains(_searchQuery) ||
            roll.contains(_searchQuery) ||
            role.contains(_searchQuery) ||
            team.contains(_searchQuery);
      }).toList();
    });
  }

  Future<void> _deleteUser(String email, String role) async {
    final poppins = GoogleFonts.poppins;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF1A2B4A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B6B).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.delete_forever_rounded,
                  color: Color(0xFFFF6B6B),
                  size: 30,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Delete User?',
                style: poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Are you sure you want to delete user: $email? This action is permanent and cannot be undone.',
                textAlign: TextAlign.center,
                style: poppins(fontSize: 13, color: const Color(0xFF8A9CC2)),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text(
                        'Cancel',
                        style: poppins(
                          color: Colors.white70,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF6B6B),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(
                        'Delete',
                        style: poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true) return;

    try {
      final response = await http
          .delete(
            Uri.parse('$apiBaseUrl/api/admin/user'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'role': role}),
          )
          .timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);
      if (mounted) {
        if (response.statusCode == 200 && data['success'] == true) {
          AppToast.success(
            context,
            data['message'] ?? 'Successfully deleted user.',
          );
          _fetchUsers();
        } else {
          AppToast.error(context, data['message'] ?? 'Failed to delete user.');
        }
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'Error deleting user: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    TextStyle poppins({
      Color? color,
      double? fontSize,
      FontWeight? fontWeight,
      double? letterSpacing,
    }) {
      FontWeight finalWeight = fontWeight ?? FontWeight.bold;
      if (finalWeight == FontWeight.normal) {
        finalWeight = FontWeight.bold;
      }
      Color? finalColor = color;
      if (color == Colors.white30 ||
          color == Colors.white38 ||
          color == Colors.white24 ||
          color == const Color(0xFF8A9CC2)) {
        finalColor = Colors.white70;
      } else if (color == const Color(0xFFC9D1E6)) {
        finalColor = Colors.white;
      }
      return GoogleFonts.poppins(
        color: finalColor ?? Colors.white,
        fontSize: fontSize,
        fontWeight: finalWeight,
        letterSpacing: letterSpacing,
      );
    }

    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            'assets/background.png',
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                Container(color: const Color(0xFF080F1F)),
          ),
        ),
        Positioned.fill(
          child: Container(color: Colors.black.withValues(alpha: 0.45)),
        ),

        Scaffold(
          backgroundColor: Colors.transparent,
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Colors.white,
              ),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              'Delete User Panel',
              style: poppins(
                fontWeight: FontWeight.w900,
                color: const Color(0xFFFF6B6B),
                fontSize: 18,
              ),
            ),
            centerTitle: true,
          ),
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  child: TextFormField(
                    controller: _searchController,
                    onChanged: _filterUsers,
                    style: poppins(fontSize: 14, color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Search by name, email, roll or team...',
                      hintStyle: poppins(fontSize: 13, color: Colors.white30),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: Color(0xFF4DA6FF),
                      ),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(
                                Icons.clear_rounded,
                                color: Colors.white54,
                              ),
                              onPressed: () {
                                _searchController.clear();
                                _filterUsers('');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.05),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFF4DA6FF),
                          ),
                        )
                      : _filteredUsers.isEmpty
                      ? Center(
                          child: Text(
                            'No users matched your search.',
                            style: poppins(
                              color: const Color(0xFF8A9CC2),
                              fontSize: 14,
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                          itemCount: _filteredUsers.length,
                          itemBuilder: (context, idx) {
                            final user = _filteredUsers[idx];
                            final String email = user['email'] ?? '';
                            final String name = user['name'] ?? '';
                            final String roll = user['roll_number'] ?? '';
                            final String role = user['role'] ?? 'Member';
                            final String team = user['team'] ?? '';
                            final String imgUrl =
                                user['image_url'] ??
                                'https://kumaraguruseds.space/mani.jpeg';

                            final isSelf =
                                email.toLowerCase() ==
                                widget.userData?.email.toLowerCase();

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.03),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.05),
                                ),
                              ),
                              child: Row(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(20),
                                    child: Image.network(
                                      imgUrl,
                                      width: 40,
                                      height: 40,
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (context, error, stackTrace) =>
                                              Container(
                                                width: 40,
                                                height: 40,
                                                color: Colors.white.withValues(
                                                  alpha: 0.1,
                                                ),
                                                child: const Icon(
                                                  Icons.person_rounded,
                                                  color: Colors.white70,
                                                ),
                                              ),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          style: poppins(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w900,
                                            color: Colors.white,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '$role • $roll',
                                          style: poppins(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            color: const Color(0xFF00E5FF),
                                          ),
                                        ),
                                        if (team.isNotEmpty &&
                                            team != 'Admin') ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            'Team: $team',
                                            style: poppins(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                              color: const Color(0xFFFFB800),
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 2),
                                        Text(
                                          email,
                                          style: poppins(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (!isSelf)
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete_outline_rounded,
                                        color: Color(0xFFFF6B6B),
                                      ),
                                      onPressed: () => _deleteUser(email, role),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ── LiveUserMapPage — Admin / Lead Real-time 2D Tracking Map ──
// ─────────────────────────────────────────────────────────────────────────────
class LiveUserMapPage extends StatefulWidget {
  final String userEmail;
  final String userName;
  final String userRole;
  final bool isLiveUser;
  final int? sessionId;

  const LiveUserMapPage({
    super.key,
    required this.userEmail,
    required this.userName,
    required this.userRole,
    this.isLiveUser = true,
    this.sessionId,
  });

  @override
  State<LiveUserMapPage> createState() => _LiveUserMapPageState();
}

class _LiveUserMapPageState extends State<LiveUserMapPage> {
  double? _userLat; // Last/current location
  double? _userLng;
  double? _startLat; // Start location
  double? _startLng;
  String? _lastReason;
  String? _ipAddress;
  bool _isInside = false;
  String _lastUpdated = 'Connecting...';
  bool _isLoading = true;
  io.Socket? _socket;
  Timer? _locationRefreshTimer;
  final MapController _mapController = MapController();

  List<latlong.LatLng> _geofencePoints = [];

  latlong.LatLng _getGeofenceCenter() {
    if (_geofencePoints.isEmpty) {
      return const latlong.LatLng(11.0790, 76.9859);
    }
    double sumLat = 0;
    double sumLng = 0;
    for (final pt in _geofencePoints) {
      sumLat += pt.latitude;
      sumLng += pt.longitude;
    }
    return latlong.LatLng(
      sumLat / _geofencePoints.length,
      sumLng / _geofencePoints.length,
    );
  }

  Future<void> _fetchGeofence() async {
    try {
      final emailParam = widget.userEmail;
      final res = await http
          .get(
            Uri.parse(
              '$apiBaseUrl/api/admin/coordinates?email=${Uri.encodeComponent(emailParam)}',
            ),
          )
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && data['polygon'] != null) {
          final List pts = data['polygon'];
          if (mounted) {
            setState(() {
              _geofencePoints = pts
                  .map(
                    (p) => latlong.LatLng(
                      double.parse(p['lat'].toString()),
                      double.parse(p['lng'].toString()),
                    ),
                  )
                  .toList();
            });
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_geofencePoints.isNotEmpty && mounted) {
                _mapController.move(_getGeofenceCenter(), 18.2);
              }
            });
            return;
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading geofence: $e');
    }
    if (mounted) {
      setState(() {
        _geofencePoints = const [
          latlong.LatLng(11.0792128940296, 76.98580078295689),
          latlong.LatLng(11.07885145073529, 76.98583989919051),
          latlong.LatLng(11.07886881237344, 76.98606582309627),
          latlong.LatLng(11.07923407016065, 76.98601002872422),
          latlong.LatLng(11.0792128940296, 76.98580078295689),
        ];
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchGeofence();
    _fetchInitialLocation();
    if (widget.isLiveUser) _initSocket();
    // Poll for location updates every 4 seconds as primary live-refresh
    _locationRefreshTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _pollLocation();
    });
  }

  @override
  void dispose() {
    _locationRefreshTimer?.cancel();
    _socket?.disconnect();
    _socket?.dispose();
    super.dispose();
  }

  // ── Shared helper: apply a location update to the map ──
  void _applyLocation(double lat, double lng, bool isInside, String label) {
    if (!mounted) return;
    setState(() {
      _userLat = lat;
      _userLng = lng;
      _isInside = isInside;
      _lastUpdated = label;
    });
    try {
      _mapController.move(
        latlong.LatLng(lat, lng),
        _mapController.camera.zoom < 16 ? 18.2 : _mapController.camera.zoom,
      );
    } catch (_) {}
  }

  // ── Periodic poll: fetch latest position from backend ──
  Future<void> _pollLocation() async {
    if (!mounted) return;
    try {
      if (widget.sessionId != null) {
        final res = await http
            .get(Uri.parse('$apiBaseUrl/api/logs/location-log?session_id=${widget.sessionId}'))
            .timeout(const Duration(seconds: 5));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          if (data['success'] == true && data['log'] != null) {
            final log = data['log'];
            final startLat = log['start_latitude'] != null ? double.tryParse(log['start_latitude'].toString()) : null;
            final startLng = log['start_longitude'] != null ? double.tryParse(log['start_longitude'].toString()) : null;
            final lastLat = log['last_latitude'] != null ? double.tryParse(log['last_latitude'].toString()) : null;
            final lastLng = log['last_longitude'] != null ? double.tryParse(log['last_longitude'].toString()) : null;
            final lastReason = log['last_reason'] as String?;
            final ip = log['ip_address'] as String?;

            if (mounted) {
              setState(() {
                _startLat = startLat;
                _startLng = startLng;
                _userLat = lastLat;
                _userLng = lastLng;
                _lastReason = lastReason;
                _ipAddress = ip;
                _lastUpdated = lastReason ?? 'Session Ended';
              });
              if (lastLat != null && lastLng != null) {
                try {
                  _mapController.move(latlong.LatLng(lastLat, lastLng), 18.2);
                } catch (_) {}
              }
            }
          }
        }
        return;
      }

      if (widget.isLiveUser) {
        final res = await http
            .get(Uri.parse('$apiBaseUrl/api/admin/live-locations'))
            .timeout(const Duration(seconds: 5));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          if (data['success'] == true) {
            final List<dynamic> locs = data['locations'] ?? [];
            final match = locs.firstWhere(
              (l) =>
                  l['email'].toString().toLowerCase() ==
                  widget.userEmail.toLowerCase(),
              orElse: () => null,
            );
            if (match != null &&
                match['latitude'] != null &&
                match['longitude'] != null) {
              _applyLocation(
                double.parse(match['latitude'].toString()),
                double.parse(match['longitude'].toString()),
                match['isInside'] == true,
                'Live',
              );
            } else if (mounted) {
              setState(() => _lastUpdated = 'Waiting for signal…');
            }
          }
        }
      } else {
        final res = await http
            .get(
              Uri.parse(
                '$apiBaseUrl/api/admin/last-location?email=${Uri.encodeComponent(widget.userEmail)}',
              ),
            )
            .timeout(const Duration(seconds: 5));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          if (data['success'] == true && data['location'] != null) {
            final loc = data['location'];
            _applyLocation(
              double.parse(loc['latitude'].toString()),
              double.parse(loc['longitude'].toString()),
              loc['isInside'] == true,
              'Last known location',
            );
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _fetchInitialLocation() async {
    await _pollLocation();
    if (mounted) setState(() => _isLoading = false);
  }

  void _initSocket() {
    _socket = io.io(
      apiBaseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .enableAutoConnect()
          .build(),
    );

    _socket!.onConnect((_) {
      debugPrint('[Map Socket] Connected successfully.');
    });

    _socket!.on('live_location_update', (data) {
      if (data == null) return;
      final String email = data['email'] ?? '';
      if (email.toLowerCase() == widget.userEmail.toLowerCase()) {
        final lat = double.tryParse(data['latitude'].toString());
        final lng = double.tryParse(data['longitude'].toString());
        final isInside = data['isInside'] == true;

        if (lat != null && lng != null && mounted) {
          _applyLocation(lat, lng, isInside, 'Just now');
        }
      }
    });

    _socket!.on('live_location_removed', (data) {
      if (data == null) return;
      final String email = data['email'] ?? '';
      if (email.toLowerCase() == widget.userEmail.toLowerCase() && mounted) {
        setState(() {
          _userLat = null;
          _userLng = null;
          _lastUpdated = 'Offline (Logged Out)';
        });
      }
    });

    _socket!.on('geofence_updated', (data) {
      if (mounted) {
        _fetchGeofence();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final poppins = GoogleFonts.poppins;
    final isOfflineView = !widget.isLiveUser;
    return Stack(
      children: [
        Scaffold(
          backgroundColor: const Color(0xFF080F1F),
          appBar: AppBar(
            backgroundColor: const Color(0xFF080F1F).withValues(alpha: 0.85),
            elevation: 0,
            leading: IconButton(
              icon: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Colors.white,
              ),
              onPressed: () => Navigator.pop(context),
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isOfflineView
                          ? 'Last Known Location'
                          : 'Live Map Tracker',
                      style: poppins(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        fontSize: 16,
                      ),
                    ),
                    if (isOfflineView) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFB800).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'OFFLINE',
                          style: poppins(
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFFFFB800),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  widget.userName,
                  style: poppins(
                    color: isOfflineView
                        ? const Color(0xFFFFB800)
                        : const Color(0xFF4DA6FF),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            centerTitle: true,
          ),
          body: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFF4DA6FF)),
                )
              : Stack(
                  children: [
                    FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: _userLat != null && _userLng != null
                            ? latlong.LatLng(_userLat!, _userLng!)
                            : _getGeofenceCenter(),
                        initialZoom: 18.2,
                        minZoom: 14,
                        maxZoom: 21,
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
                          subdomains: const ['a', 'b', 'c', 'd'],
                          userAgentPackageName:
                              'com.example.frontend_fluttter_app',
                        ),
                        PolylineLayer(
                          polylines: [
                            if (_startLat != null && _startLng != null && _userLat != null && _userLng != null)
                              Polyline(
                                points: [
                                  latlong.LatLng(_startLat!, _startLng!),
                                  latlong.LatLng(_userLat!, _userLng!),
                                ],
                                color: const Color(0xFF00FF87),
                                strokeWidth: 4.0,
                              )
                            else if (_userLat != null && _userLng != null)
                              Polyline(
                                points: [
                                  latlong.LatLng(_userLat!, _userLng!),
                                  _getGeofenceCenter(),
                                ],
                                color: const Color(0xFFFF2D55),
                                strokeWidth: 4.0,
                              ),
                          ],
                        ),
                        PolygonLayer(
                          polygons: [
                            if (_geofencePoints.isNotEmpty)
                              Polygon(
                                points: _geofencePoints,
                                color: const Color(
                                  0xFF00C48C,
                                ).withValues(alpha: 0.15),
                                borderColor: const Color(0xFF00C48C),
                                borderStrokeWidth: 2,
                              ),
                          ],
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: _getGeofenceCenter(),
                              width: 36,
                              height: 36,
                              child: const Icon(
                                Icons.location_on_rounded,
                                color: Color(0xFFFF2D55),
                                size: 32,
                              ),
                            ),
                            if (_startLat != null && _startLng != null)
                              Marker(
                                point: latlong.LatLng(_startLat!, _startLng!),
                                width: 36,
                                height: 36,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF00FF87).withValues(alpha: 0.25),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: const Color(0xFF00FF87),
                                      width: 1.5,
                                    ),
                                  ),
                                  alignment: Alignment.center,
                                  child: Container(
                                    width: 14,
                                    height: 14,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF00FF87),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                              ),
                            if (_userLat != null && _userLng != null)
                              Marker(
                                point: latlong.LatLng(_userLat!, _userLng!),
                                width: 36,
                                height: 36,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: (_startLat != null ? const Color(0xFF00E5FF) : const Color(0xFF00E5FF)).withValues(alpha: 0.25),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: _startLat != null ? const Color(0xFF00E5FF) : const Color(0xFF00E5FF),
                                      width: 1.5,
                                    ),
                                  ),
                                  alignment: Alignment.center,
                                  child: Container(
                                    width: 14,
                                    height: 14,
                                    decoration: BoxDecoration(
                                      color: _startLat != null ? const Color(0xFF00E5FF) : const Color(0xFF00E5FF),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                    Positioned(
                      left: 20,
                      right: 20,
                      bottom: 24,
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFF080F1F).withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isOfflineView
                                ? const Color(0xFFFFB800).withValues(alpha: 0.3)
                                : Colors.white.withValues(alpha: 0.1),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.4),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Offline notice bar
                            if (isOfflineView) ...[
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                margin: const EdgeInsets.only(bottom: 14),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFFFFB800,
                                  ).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: const Color(
                                      0xFFFFB800,
                                    ).withValues(alpha: 0.4),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.history_toggle_off_rounded,
                                      size: 14,
                                      color: Color(0xFFFFB800),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        'This is the last recorded location before logout',
                                        style: poppins(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: const Color(0xFFFFB800),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFF4DA6FF,
                                    ).withValues(alpha: 0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    isOfflineView
                                        ? Icons.person_off_rounded
                                        : Icons.person_pin_circle_rounded,
                                    color: isOfflineView
                                        ? const Color(0xFFFFB800)
                                        : const Color(0xFF4DA6FF),
                                    size: 26,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        widget.userName,
                                        style: poppins(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                      Text(
                                        '${widget.userRole} • ${widget.userEmail}',
                                        style: poppins(
                                          fontSize: 11,
                                          color: const Color(0xFF8A9CC2),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                             const SizedBox(height: 16),
                            Container(
                              height: 1.5,
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                            if (_userLat != null && _userLng != null) ...[
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _startLat != null ? 'START LOCATION' : 'COORDINATES',
                                        style: poppins(fontSize: 9, fontWeight: FontWeight.bold, color: const Color(0xFF8A9CC2)),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _startLat != null
                                            ? '${_startLat!.toStringAsFixed(6)}, ${_startLng!.toStringAsFixed(6)}'
                                            : '${_userLat!.toStringAsFixed(6)}, ${_userLng!.toStringAsFixed(6)}',
                                        style: poppins(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                                      ),
                                    ],
                                  ),
                                  if (_startLat != null)
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          'END LOCATION',
                                          style: poppins(fontSize: 9, fontWeight: FontWeight.bold, color: const Color(0xFF8A9CC2)),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${_userLat!.toStringAsFixed(6)}, ${_userLng!.toStringAsFixed(6)}',
                                          style: poppins(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ],
                            if (_ipAddress != null && _ipAddress!.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'IP ADDRESS',
                                    style: poppins(fontSize: 9, fontWeight: FontWeight.bold, color: const Color(0xFF8A9CC2)),
                                  ),
                                  Text(
                                    _ipAddress!,
                                    style: poppins(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white70),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 12),
                            Container(
                              height: 1.5,
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      isOfflineView
                                          ? 'Last Location'
                                          : 'Geofence Status',
                                      style: poppins(
                                        fontSize: 10,
                                        color: const Color(0xFF8A9CC2),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            color: _userLat == null
                                                ? Colors.white30
                                                : (isOfflineView
                                                      ? const Color(0xFFFFB800)
                                                      : (_isInside
                                                            ? const Color(
                                                                0xFF00FF87,
                                                              )
                                                            : const Color(
                                                                0xFFFF2D55,
                                                              ))),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          _userLat == null
                                              ? 'No data'
                                              : (isOfflineView
                                                    ? (_isInside
                                                          ? 'Was inside SEDS Lab'
                                                          : 'Was outside boundary')
                                                    : (_isInside
                                                          ? 'Inside SEDS Lab'
                                                          : 'Outside Boundary')),
                                          style: poppins(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: _userLat == null
                                                ? Colors.white54
                                                : (isOfflineView
                                                      ? const Color(0xFFFFB800)
                                                      : (_isInside
                                                            ? const Color(
                                                                0xFF00FF87,
                                                              )
                                                            : const Color(
                                                                0xFFFF2D55,
                                                              ))),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      isOfflineView
                                          ? 'Status'
                                          : 'Tracking Signal',
                                      style: poppins(
                                        fontSize: 10,
                                        color: const Color(0xFF8A9CC2),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      isOfflineView ? (_lastReason ?? 'Offline') : _lastUpdated,
                                      style: poppins(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: isOfflineView
                                            ? const Color(0xFFFFB800)
                                            : (_userLat == null
                                                  ? Colors.white54
                                                  : const Color(0xFF4DA6FF)),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Background isolate entry points
// Expose both entry point names to resolve any cached OS callback handles.
// ─────────────────────────────────────────────────────────────────────────────
@pragma('vm:entry-point')
void onServiceStart(ServiceInstance service) {
  backgroundServiceOnStart(service);
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) {
  backgroundServiceOnStart(service);
}
