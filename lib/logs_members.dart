import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as latlong;
import 'notifications_page.dart';
import 'background_service.dart';
import 'main.dart';
import 'app_toast.dart';

// ─────────────── Member Logs Page ───────────────
class LogsMembersPage extends StatefulWidget {
  final UserData? userData;
  const LogsMembersPage({super.key, this.userData});
  @override
  State<LogsMembersPage> createState() => _LogsMembersPageState();
}

class _LogsMembersPageState extends State<LogsMembersPage>
    with WidgetsBindingObserver {
  // Timer state
  bool _isWorking = false;
  DateTime? _startTime;
  int _sessionId = -1;
  String? _logSessionId;
  Duration _elapsed = Duration.zero;
  Timer? _ticker;
  bool _isPaused = false;
  io.Socket? _socket;
  Timer? _locationTimer;
  // ignore: unused_field
  String _locationLog = '';

  // Data
  List<Map<String, dynamic>> _history = [];
  int _completedSecondsThisWeek = 0;
  bool _loadingHistory = true;

  // Weekly target for members
  static const int _weeklyTargetSeconds = 12 * 3600; // 12 hrs

  Position? _currentPosition;
  final MapController _mapController = MapController();
  StreamSubscription<Position>? _positionStreamSubscription;
  DateTime? _lastPostTime;
  Position? _lastPos;

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
    return latlong.LatLng(sumLat / _geofencePoints.length, sumLng / _geofencePoints.length);
  }

  Future<void> _fetchGeofence() async {
    try {
      final emailParam = widget.userData?.email ?? '';
      final res = await http.get(Uri.parse('$apiBaseUrl/api/admin/coordinates?email=${Uri.encodeComponent(emailParam)}')).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && data['polygon'] != null) {
          final List pts = data['polygon'];
          if (mounted) {
            setState(() {
              _geofencePoints = pts.map((p) => latlong.LatLng(
                double.parse(p['lat'].toString()),
                double.parse(p['lng'].toString())
              )).toList();
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

  bool _isPointInPolygon(latlong.LatLng point, List<latlong.LatLng> polygon) {
    if (polygon.length < 3) return true;
    bool isInside = false;
    int j = polygon.length - 1;

    for (int i = 0; i < polygon.length; i++) {
      final xi = polygon[i].latitude;
      final yi = polygon[i].longitude;
      final xj = polygon[j].latitude;
      final yj = polygon[j].longitude;

      final intersect = ((yi > point.longitude) != (yj > point.longitude)) &&
          (point.latitude < (xj - xi) * (point.longitude - yi) / (yj - yi) + xi);

      if (intersect) isInside = !isInside;
      j = i;
    }
    return isInside;
  }

  double _getDistanceToPolygon(latlong.LatLng pt, List<latlong.LatLng> polygon) {
    if (polygon.isEmpty) return 0.0;
    double minDistance = double.infinity;
    const latlong.Distance distance = latlong.Distance();

    for (int i = 0; i < polygon.length; i++) {
      final p1 = polygon[i];
      final p2 = polygon[(i + 1) % polygon.length];
      final d = _getDistanceToSegment(pt, p1, p2, distance);
      if (d < minDistance) {
        minDistance = d;
      }
    }
    return minDistance;
  }

  double _getDistanceToSegment(latlong.LatLng p, latlong.LatLng a, latlong.LatLng b, latlong.Distance distance) {
    final double l2 = _distSq(a, b);
    if (l2 == 0) return distance.as(latlong.LengthUnit.Meter, p, a);
    double t = ((p.latitude - a.latitude) * (b.latitude - a.latitude) +
                (p.longitude - a.longitude) * (b.longitude - a.longitude)) / l2;
    t = t.clamp(0.0, 1.0);
    final latlong.LatLng projection = latlong.LatLng(
      a.latitude + t * (b.latitude - a.latitude),
      a.longitude + t * (b.longitude - a.longitude),
    );
    return distance.as(latlong.LengthUnit.Meter, p, projection);
  }

  double _distSq(latlong.LatLng a, latlong.LatLng b) {
    final dLat = a.latitude - b.latitude;
    final dLng = a.longitude - b.longitude;
    return dLat * dLat + dLng * dLng;
  }

  bool _checkGeofenceStatus(Position pos) {
    if (_geofencePoints.isEmpty) return true;
    final pt = latlong.LatLng(pos.latitude, pos.longitude);
    final isInsideRaw = _isPointInPolygon(pt, _geofencePoints);
    if (isInsideRaw) return true;

    final accuracyBuffer = pos.accuracy.clamp(5.0, 15.0);
    final dist = _getDistanceToPolygon(pt, _geofencePoints);
    return dist <= accuracyBuffer;
  }

  void _checkLocalGeofence(Position pos) {
    if (!_isWorking) return;
    final bool isInside = _checkGeofenceStatus(pos);
    if (!isInside && !_isPaused) {
      setState(() => _isPaused = true);
      _showSnack('Work Session Paused: You went outside the coordinates.', type: ToastType.warning);
    } else if (isInside && _isPaused) {
      setState(() => _isPaused = false);
      _showSnack('Work Session Resumed: You returned inside the coordinates.', type: ToastType.success);
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchGeofence();
    WidgetsBinding.instance.addObserver(this);
    // Defer all heavy work until after first frame to avoid skipped frames
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestLocationPermission();
      _restoreSession();
      _loadHistory();
      _loadWeekStats();
      _startTrackingLocationForMap();
    });
  }

  void _startTrackingLocationForMap() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best);
        if (mounted) {
          setState(() {
            _currentPosition = pos;
            _lastPos = pos;
          });
          try {
            _mapController.move(latlong.LatLng(pos.latitude, pos.longitude), 18.2);
          } catch (_) {}
        }
        _positionStreamSubscription = Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.best,
            distanceFilter: 1, // trigger on 1 meter movement for precision
          ),
        ).listen((Position pos) {
          if (mounted) {
            setState(() {
              _currentPosition = pos;
              _lastPos = pos;
            });
            // If session is active, check geofence locally & post stream location update
            if (_isWorking) {
              _checkLocalGeofence(pos);
              _postStreamLocation(pos);
            }
            try {
              _mapController.move(latlong.LatLng(pos.latitude, pos.longitude), _mapController.camera.zoom);
            } catch (_) {}
          }
        });
      }
    } catch (e) {
      debugPrint('Error starting map location tracking: $e');
    }
  }

  Future<void> _postStreamLocation(Position pos) async {
    final email = widget.userData?.email ?? '';
    if (email.isEmpty) return;

    final now = DateTime.now();
    // Rate limit stream posts to once every 4 seconds to prevent server overload
    if (_lastPostTime != null && now.difference(_lastPostTime!) < const Duration(seconds: 4)) {
      return;
    }
    _lastPostTime = now;

    try {
      final res = await http.post(
        Uri.parse('$apiBaseUrl/api/logs/location'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'latitude': pos.latitude,
          'longitude': pos.longitude,
          'accuracy': pos.accuracy,
        }),
      ).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        _handleLocationResponse(data, email);
      }
    } catch (e) {
      debugPrint('Stream post location error: $e');
    }
  }

  void _handleLocationResponse(Map<String, dynamic> data, String email) {
    if (data['session_stopped'] == true) {
      setState(() {
        _isWorking = false;
        _startTime = null;
      });
      _locationTimer?.cancel();
      _showSnack('Your work session has been ended by Admin.', type: ToastType.warning);
      return;
    }

    if (data['status_changed'] == true) {
      final isPaused = data['is_paused'] == true;
      final locLog = data['location_log'] as String? ?? '';
      DateTime? st;
      if (data['start_time'] != null) {
        st = DateTime.tryParse(data['start_time'] as String)?.toLocal();
      }
      DateTime? lastPausedAt;
      if (data['last_paused_at'] != null) {
        lastPausedAt = DateTime.tryParse(data['last_paused_at'] as String)?.toLocal();
      }
      setState(() {
        _isPaused = isPaused;
        _locationLog = locLog;
        if (st != null) {
          _startTime = st;
          SharedPreferences.getInstance().then((prefs) {
            prefs.setString('log_start_time_$email', st!.toIso8601String());
          });
          if (isPaused && lastPausedAt != null) {
            _elapsed = lastPausedAt.difference(st);
          } else {
            _elapsed = DateTime.now().difference(st);
          }
        }
      });
      if (isPaused) {
        _showSnack('Work Session Paused: You went outside the coordinates.');
      } else {
        _showSnack('Work Session Resumed: You returned inside the coordinates.');
      }
    } else if (data.containsKey('is_paused')) {
      final serverIsPaused = data['is_paused'] == true;
      if (serverIsPaused != _isPaused) {
        DateTime? st;
        if (data['start_time'] != null) {
          st = DateTime.tryParse(data['start_time'] as String)?.toLocal();
        }
        DateTime? lastPausedAt;
        if (data['last_paused_at'] != null) {
          lastPausedAt = DateTime.tryParse(data['last_paused_at'] as String)?.toLocal();
        }
        setState(() {
          _isPaused = serverIsPaused;
          if (st != null) {
            _startTime = st;
            if (serverIsPaused && lastPausedAt != null) {
              _elapsed = lastPausedAt.difference(st);
            } else {
              _elapsed = DateTime.now().difference(st);
            }
          }
        });
      }
    }
  }

  /// Request location permission on startup so the dialog appears immediately.
  Future<void> _requestLocationPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      await Geolocator.requestPermission();
    } else if (permission == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _positionStreamSubscription?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _notifyAppClosed();
    } else if (state == AppLifecycleState.resumed) {
      // Re-init socket when app comes back to foreground
      if (_isWorking) {
        _initSocket();
      }
    }
  }

  Future<void> _notifyAppClosed() async {
    final email = widget.userData?.email;
    if (email == null || !_isWorking) return;
    try {
      await http.patch(
        Uri.parse('$apiBaseUrl/api/logs/app-closed'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_email': email}),
      );
    } catch (_) {}
  }

  void _initSocket() {
    _disposeSocket();
    final email = widget.userData?.email ?? '';
    if (email.isEmpty) return;

    _socket = io.io(apiBaseUrl, io.OptionBuilder()
      .setTransports(['websocket'])
      .enableAutoConnect()
      .enableReconnection()
      .setReconnectionAttempts(99999)
      .setReconnectionDelay(2000)
      .build());

    _socket!.onConnect((_) {
      debugPrint('Socket connected. Registering $email');
      _socket!.emit('register', email);
    });

    _socket!.on('session_status', (data) {
      debugPrint('Received session_status event: $data');
      if (data is Map && mounted) {
        final isPaused = data['is_paused'] == true;
        final locLog = data['location_log'] as String? ?? '';
        
        DateTime? st;
        if (data['start_time'] != null) {
          st = DateTime.tryParse(data['start_time'] as String)?.toLocal();
        }
        
        DateTime? lastPausedAt;
        if (data['last_paused_at'] != null) {
          lastPausedAt = DateTime.tryParse(data['last_paused_at'] as String)?.toLocal();
        }

        final email = widget.userData?.email ?? '';

        setState(() {
          _isPaused = isPaused;
          _locationLog = locLog;
          if (st != null) {
            _startTime = st;
            SharedPreferences.getInstance().then((prefs) {
              prefs.setString('log_start_time_$email', st!.toIso8601String());
            });
            if (isPaused && lastPausedAt != null) {
              _elapsed = lastPausedAt.difference(st);
            } else {
              _elapsed = DateTime.now().difference(st);
            }
          }
        });

        if (isPaused) {
          _showSnack('Work Session Paused: You went outside the coordinates.');
        } else {
          _showSnack('Work Session Resumed: You returned inside the coordinates.');
        }
      }
    });

    _socket!.on('geofence_updated', (data) {
      if (data == null) return;
      final String targetType = data['targetType'] ?? 'global';
      final String targetValue = (data['targetValue'] ?? '').toString().trim().toLowerCase();
      final List? polygon = data['polygon'];

      if (polygon == null) return;

      bool applies = false;
      if (targetType == 'global') {
        applies = true;
      } else if (targetType == 'team') {
        final userTeam = (widget.userData?.team ?? '').trim().toLowerCase();
        if (userTeam == targetValue) {
          applies = true;
        }
      } else if (targetType == 'user') {
        final userEmail = (widget.userData?.email ?? '').trim().toLowerCase();
        if (userEmail == targetValue) {
          applies = true;
        }
      }

      if (applies && mounted) {
        setState(() {
          _geofencePoints = polygon.map((p) => latlong.LatLng(
            double.parse(p['lat'].toString()),
            double.parse(p['lng'].toString())
          )).toList();
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_geofencePoints.isNotEmpty && mounted) {
            _mapController.move(_getGeofenceCenter(), 18.2);
          }
        });
      }
    });

    // 10-second timer serves as a stationary fallback heartbeat
    _locationTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      if (!_isWorking) {
        timer.cancel();
        return;
      }
      try {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
          // Attempt best accuracy check (use cached fallback to prevent lock contention)
          Position? pos;
          try {
            pos = await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.best,
              timeLimit: const Duration(seconds: 4),
            );
          } catch (_) {
            pos = _lastPos ?? await Geolocator.getLastKnownPosition();
          }

          if (pos == null) return;
          debugPrint('Timer Location update: lat=${pos.latitude}, lng=${pos.longitude}');
          
          try {
            final res = await http.post(
              Uri.parse('$apiBaseUrl/api/logs/location'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'email': email,
                'latitude': pos.latitude,
                'longitude': pos.longitude,
                'accuracy': pos.accuracy,
              }),
            ).timeout(const Duration(seconds: 5));

            if (res.statusCode == 200 && mounted) {
              final data = jsonDecode(res.body);
              _handleLocationResponse(data, email);
            }
          } catch (httpErr) {
            debugPrint('HTTP location_update error: $httpErr');
          }
        }
      } catch (err) {
        debugPrint('Geolocator error: $err');
      }
    });
  }



  /// Full teardown — kills timer AND socket (used on stop/dispose)
  void _disposeSocket() {
    _locationTimer?.cancel();
    _locationTimer = null;
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }



  Future<void> _restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final email = widget.userData?.email ?? '';
    if (email.isEmpty) return;

    // Show local cached state first if exists to there is zero UI delay
    final startStr = prefs.getString('log_start_time_$email');
    final sid = prefs.getInt('log_session_id_$email') ?? -1;
    final uuid = prefs.getString('log_session_uuid_$email');
    if (startStr != null) {
      final st = DateTime.tryParse(startStr);
      if (st != null) {
        setState(() {
          _startTime = st;
          _sessionId = sid;
          _logSessionId = uuid;
          _isWorking = true;
          _elapsed = DateTime.now().difference(st);
        });
        _startTicker();
        _initSocket();
      }
    }

    // Now, query server to verify status and sync accurate is_paused, last_paused_at, etc.
    try {
      final res = await http.get(
        Uri.parse('$apiBaseUrl/api/logs/active?email=${Uri.encodeComponent(email)}'),
      );
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        if (data['session'] != null) {
          final session = data['session'];
          final st = DateTime.parse(session['start_time']).toLocal();
          final id = session['id'] as int;
          final logSessionId = session['log_session_id'] as String?;
          final bool isPaused = session['is_paused'] == true;
          final String locLog = session['location_log'] as String? ?? '';
          
          DateTime? lastPausedAt;
          if (session['last_paused_at'] != null) {
            lastPausedAt = DateTime.parse(session['last_paused_at']).toLocal();
          }

          await prefs.setString('log_start_time_$email', st.toIso8601String());
          await prefs.setInt('log_session_id_$email', id);
          if (logSessionId != null) {
            await prefs.setString('log_session_uuid_$email', logSessionId);
          }

          Duration elapsed;
          if (isPaused && lastPausedAt != null) {
            elapsed = lastPausedAt.difference(st);
          } else {
            elapsed = DateTime.now().difference(st);
          }

          setState(() {
            _startTime = st;
            _sessionId = id;
            _logSessionId = logSessionId;
            _isWorking = true;
            _isPaused = isPaused;
            _locationLog = locLog;
            _elapsed = elapsed;
          });
          _startTicker();
          _initSocket();
        } else {
          // Server says no active session, but we thought we had one!
          // Sync with server by clearing local active session.
          await prefs.remove('log_start_time_$email');
          await prefs.remove('log_session_id_$email');
          await prefs.remove('log_session_uuid_$email');
          setState(() {
            _isWorking = false;
            _startTime = null;
            _elapsed = Duration.zero;
            _sessionId = -1;
            _logSessionId = null;
            _isPaused = false;
            _locationLog = '';
          });
          _disposeSocket();
          _ticker?.cancel();
        }
      }
    } catch (_) {
      // Offline or server down. Keep using the local cached state.
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_startTime != null && !_isPaused) {
        setState(() => _elapsed = DateTime.now().difference(_startTime!));
      }
    });
  }

  Future<void> _startWork() async {
    final u = widget.userData;
    if (u == null) return;
    try {
      // Validate attendance status for today
      final statusRes = await http.get(
        Uri.parse('$apiBaseUrl/api/attendance/today-status?email=${Uri.encodeComponent(u.email)}'),
      ).timeout(const Duration(seconds: 10));

      if (statusRes.statusCode == 200) {
        final statusData = jsonDecode(statusRes.body);
        if (statusData['allowed'] != true) {
          final String msg = statusData['message'] ?? 'Attendance validation failed.';
          _showSnack(msg, type: ToastType.error);
          return;
        }
      } else {
        _showSnack('Attendance validation failed. Server error.', type: ToastType.error);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        _showSnack('Location permission is required to start a work session.');
        return;
      }

      final currentPos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best);
      _currentPosition = currentPos;
      if (!_checkGeofenceStatus(currentPos)) {
        _showSnack('You must be inside the SEDS Lab fence area to start a work session.', type: ToastType.error);
        return;
      }

      final newUuid = _generateUuid();
      final res = await http.post(
        Uri.parse('$apiBaseUrl/api/logs/start'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_name': u.name,
          'user_email': u.email,
          'roll_number': u.rollNumber,
          'role': u.role,
          'team': u.team ?? '',
          'session_id': currentSessionId,
          'log_session_id': newUuid,
        }),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true) {
          final st = DateTime.parse(data['start_time']).toLocal();
          final id = data['session_id'] as int;
          final email = u.email;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('log_start_time_$email', st.toIso8601String());
          await prefs.setInt('log_session_id_$email', id);
          await prefs.setString('log_session_uuid_$email', newUuid);
          setState(() {
            _startTime = st;
            _sessionId = id;
            _logSessionId = newUuid;
            _isWorking = true;
            _isPaused = false;
            _elapsed = Duration.zero;
          });
          _startTicker();
          _initSocket();
          // ── Start background location tracking (survives app minimise/logout)
          await startBackgroundTracking(email);
        }
      }
    } catch (e) {
      _showSnack('Connection error. Try again.');
    }
  }

  Future<void> _stopWork() async {
    _ticker?.cancel();
    _disposeSocket();
    final elapsed = _elapsed;
    final summary = await _showSummaryDialog(elapsed);
    if (summary == null) {
      _initSocket();
      _startTicker();
      return;
    }
    final u = widget.userData;
    if (u == null) return;
    try {
      final res = await http.post(
        Uri.parse('$apiBaseUrl/api/logs/stop'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_email': u.email,
          'summary': summary,
          'session_id': _sessionId > 0 ? _sessionId : null,
          'log_session_id': _logSessionId,
        }),
      );
      final email = u.email;
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('log_start_time_$email');
      await prefs.remove('log_session_id_$email');
      await prefs.remove('log_session_uuid_$email');
      // ── Stop background location tracking
      await stopBackgroundTracking();
      setState(() {
        _isWorking = false;
        _startTime = null;
        _elapsed = Duration.zero;
        _sessionId = -1;
        _logSessionId = null;
        _isPaused = false;
        _locationLog = '';
      });
      if (res.statusCode == 200) {
        _showSnack('Work session saved! 🎉');
      }
      _loadHistory();
      _loadWeekStats();
    } catch (e) {
      _showSnack('Error saving session.');
      _initSocket();
      _startTicker();
    }
  }

  Future<String?> _showSummaryDialog(Duration elapsed) async {
    final ctrl = TextEditingController();
    final poppins = GoogleFonts.poppins;
    String? errorText;
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final isButtonEnabled = ctrl.text.trim().isNotEmpty;
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFF1A2B4A),
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40, height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00C48C).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.stop_circle_outlined, color: Color(0xFF00C48C), size: 24),
                      ),
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Stop Work Session', style: poppins(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18)),
                          Text(_formatDuration(elapsed), style: poppins(color: const Color(0xFF4DA6FF), fontSize: 14, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text('What did you work on? * (Mandatory)', style: poppins(color: const Color(0xFFC9D1E6), fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: errorText != null ? Colors.redAccent : Colors.white.withValues(alpha: 0.12)),
                    ),
                    child: TextField(
                      controller: ctrl,
                      maxLines: 4,
                      onChanged: (val) {
                        setModalState(() {
                          errorText = val.trim().isEmpty ? 'Summary cannot be empty' : null;
                        });
                      },
                      style: poppins(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Describe your work for this session…',
                        hintStyle: poppins(color: Colors.white38, fontSize: 13),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.all(16),
                      ),
                    ),
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 6),
                    Text(errorText!, style: poppins(color: Colors.redAccent, fontSize: 12)),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx, null),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: Text('Cancel', style: poppins(color: const Color(0xFFC9D1E6))),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: isButtonEnabled
                              ? () => Navigator.pop(ctx, ctrl.text.trim())
                              : () {
                                  setModalState(() {
                                    errorText = 'Summary is mandatory to save your log.';
                                  });
                                },
                          icon: const Icon(Icons.save_rounded, size: 18),
                          label: Text('Save Log', style: poppins(fontWeight: FontWeight.bold, fontSize: 15)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isButtonEnabled ? const Color(0xFF00C48C) : Colors.grey,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }
      ),
    );
  }

  Future<void> _loadHistory() async {
    final email = widget.userData?.email;
    if (email == null) return;
    try {
      final res = await http.get(
        Uri.parse('$apiBaseUrl/api/logs/history?email=${Uri.encodeComponent(email)}&limit=30'),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) {
          setState(() {
            _history = List<Map<String, dynamic>>.from(data['sessions'] ?? []);
            _loadingHistory = false;
          });
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  Future<void> _loadWeekStats() async {
    final email = widget.userData?.email;
    if (email == null) return;
    try {
      final res = await http.get(
        Uri.parse('$apiBaseUrl/api/logs/week-stats?email=${Uri.encodeComponent(email)}'),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) {
          setState(() {
            _completedSecondsThisWeek = (data['completed_seconds'] as num?)?.toInt() ?? 0;
          });
        }
      }
    } catch (_) {}
  }

  String _getCurrentWeekDateRange() {
    final now = DateTime.now();
    final int daysSinceSunday = now.weekday == 7 ? 0 : now.weekday;
    final DateTime sunday = now.subtract(Duration(days: daysSinceSunday));
    final DateTime saturday = sunday.add(const Duration(days: 6));
    final sDay = sunday.day.toString().padLeft(2, '0');
    final sMonth = sunday.month.toString().padLeft(2, '0');
    final eDay = saturday.day.toString().padLeft(2, '0');
    final eMonth = saturday.month.toString().padLeft(2, '0');
    return '(Sun $sDay/$sMonth to Sat $eDay/$eMonth)';
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    return '${h}h ${m}m ${s}s';
  }

  String _formatDurationShort(int? seconds) {
    if (seconds == null || seconds <= 0) return '0h 0m 0s';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    return '${h}h ${m}m ${s}s';
  }

  String _formatWeeklyProgress(int totalSeconds) {
    final int hours = totalSeconds ~/ 3600;
    final int minutes = (totalSeconds % 3600) ~/ 60;
    if (hours == 0 && minutes == 0) {
      return '0h 0m';
    } else if (hours == 0) {
      return '${minutes}m';
    } else if (minutes == 0) {
      return '${hours}h';
    }
    return '${hours}h ${minutes}m';
  }

  String _generateUuid() {
    final random = Random.secure();
    final values = List<int>.generate(16, (i) => random.nextInt(256));
    values[6] = (values[6] & 0x0f) | 0x40;
    values[8] = (values[8] & 0x3f) | 0x80;
    final buffer = StringBuffer();
    for (var i = 0; i < 16; i++) {
      if (i == 4 || i == 6 || i == 8 || i == 10) {
        buffer.write('-');
      }
      buffer.write(values[i].toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  String _formatDateTime(String? isoStr) {
    if (isoStr == null) return '—';
    final dt = DateTime.tryParse(isoStr)?.toLocal();
    if (dt == null) return '—';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return 'Today ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
    if (diff.inDays == 1) return 'Yesterday ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  void _showSnack(String msg, {ToastType type = ToastType.info}) {
    if (!mounted) return;
    AppToast.show(context, msg, type: type);
  }

  @override
  Widget build(BuildContext context) {
    final poppins = GoogleFonts.poppins;
    final totalWeekSecs = _completedSecondsThisWeek +
        (_isWorking && _startTime != null ? _elapsed.inSeconds : 0);
    final weekProgress = (totalWeekSecs / _weeklyTargetSeconds).clamp(0.0, 1.0);
    final weekHours = totalWeekSecs / 3600;
    final progressColor = weekHours >= 12
        ? const Color(0xFF00C48C)
        : weekHours >= 8
            ? const Color(0xFFFFB800)
            : const Color(0xFFFF6B6B);

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () async { await _loadHistory(); await _loadWeekStats(); },
        color: const Color(0xFF4DA6FF),
        backgroundColor: const Color(0xFF1A2B4A),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ── Header ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Work Logs', style: poppins(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
                              Text(widget.userData?.name ?? '', style: poppins(fontSize: 13, color: const Color(0xFF4DA6FF))),
                            ],
                          ),
                        ),
                        // Bell Notification Icon Button
                        IconButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => DesktopPageWrapper(
                                  child: Scaffold(
                                    backgroundColor: const Color(0xFF080F1F),
                                    body: Stack(
                                      children: [
                                        if (kIsWeb || (!kIsWeb && !Platform.isWindows)) ...[
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
                                        NotificationsPage(userData: widget.userData),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                          icon: const Icon(
                            Icons.notifications_outlined,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Subtle Divider Line below notification and name area
                    Container(
                      height: 1.5,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFF4DA6FF).withValues(alpha: 0.5),
                            Colors.white.withValues(alpha: 0.05),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20), // Gap before map
                    // ── Live 2D Location Map Card ──
                    Container(
                      height: 240,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 15,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        children: [
                          FlutterMap(
                            mapController: _mapController,
                            options: MapOptions(
                              initialCenter: _currentPosition != null
                                  ? latlong.LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
                                  : _getGeofenceCenter(),
                              initialZoom: 18.2,
                              minZoom: 15,
                              maxZoom: 20,
                            ),
                            children: [
                              TileLayer(
                                urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
                                subdomains: const ['a', 'b', 'c', 'd'],
                                userAgentPackageName: 'com.example.frontend_fluttter_app',
                              ),
                              PolylineLayer(
                                polylines: [
                                  if (_currentPosition != null)
                                    Polyline(
                                      points: [
                                        latlong.LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                                        _getGeofenceCenter(), // SEDS Lab Center
                                      ],
                                      color: const Color(0xFFFF2D55), // Bright red route line
                                      strokeWidth: 4.0,
                                    ),
                                ],
                              ),
                              PolygonLayer(
                                polygons: [
                                  if (_geofencePoints.isNotEmpty)
                                    Polygon(
                                      points: _geofencePoints,
                                      color: const Color(0xFF00C48C).withValues(alpha: 0.15),
                                      borderColor: const Color(0xFF00C48C),
                                      borderStrokeWidth: 2,
                                    ),
                                ],
                              ),
                              MarkerLayer(
                                markers: [
                                  // SEDS Lab Center Destination Pin
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
                                  if (_currentPosition != null)
                                    Marker(
                                      point: latlong.LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                                      width: 32,
                                      height: 32,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF00E5FF).withValues(alpha: 0.25),
                                          shape: BoxShape.circle,
                                          border: Border.all(color: const Color(0xFF00E5FF), width: 1.5),
                                        ),
                                        alignment: Alignment.center,
                                        child: Container(
                                          width: 12,
                                          height: 12,
                                          decoration: const BoxDecoration(
                                            color: Color(0xFF00E5FF),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                          // Floating overlay badge for Live location status
                          Positioned(
                            top: 12,
                            left: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF080F1F).withValues(alpha: 0.85),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF00E5FF),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'SEDS LAB FENCE (2D)',
                                    style: poppins(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: const Color(0xFFC9D1E6),
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Timer Card ──
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: _isWorking
                            ? (_isPaused
                                ? const LinearGradient(colors: [Color(0xFF3D2E0D), Color(0xFF1A1A1A)], begin: Alignment.topLeft, end: Alignment.bottomRight)
                                : const LinearGradient(colors: [Color(0xFF0D3D2E), Color(0xFF0D2A4A)], begin: Alignment.topLeft, end: Alignment.bottomRight))
                            : const LinearGradient(colors: [Color(0xFF1A2B4A), Color(0xFF0D1E3A)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: _isWorking 
                              ? (_isPaused 
                                  ? const Color(0xFFFFB800).withValues(alpha: 0.4) 
                                  : const Color(0xFF00C48C).withValues(alpha: 0.4)) 
                              : Colors.white.withValues(alpha: 0.08),
                          width: 1.5,
                        ),
                        boxShadow: _isWorking ? [
                          BoxShadow(
                            color: _isPaused 
                                ? const Color(0xFFFFB800).withValues(alpha: 0.2) 
                                : const Color(0xFF00C48C).withValues(alpha: 0.2), 
                            blurRadius: 24, 
                            spreadRadius: 2,
                          ),
                        ] : [],
                      ),
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          if (_isWorking) ...[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 10, height: 10,
                                  decoration: BoxDecoration(
                                    color: _isPaused ? const Color(0xFFFFB800) : const Color(0xFF00FF87), 
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _isPaused ? 'PAUSED (OUTSIDE BOUNDARY)' : 'WORKING', 
                                  style: poppins(
                                    fontSize: 12, 
                                    fontWeight: FontWeight.w900, 
                                    color: _isPaused ? const Color(0xFFFFB800) : const Color(0xFF00FF87), 
                                    letterSpacing: 2,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _formatDuration(_elapsed),
                              style: poppins(fontSize: 52, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: -2),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Started at ${_startTime != null ? '${_startTime!.hour.toString().padLeft(2,"0")}:${_startTime!.minute.toString().padLeft(2,"0")}' : '--:--'}',
                              style: poppins(fontSize: 13, color: const Color(0xFF8A9CC2)),
                            ),
                            const SizedBox(height: 20),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _stopWork,
                                icon: const Icon(Icons.stop_rounded, size: 22),
                                label: Text('Stop & Save Log', style: poppins(fontWeight: FontWeight.bold, fontSize: 16)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFFF6B6B),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  elevation: 0,
                                ),
                              ),
                            ),
                          ] else ...[
                            const Icon(Icons.work_outline_rounded, color: Color(0xFF4DA6FF), size: 48),
                            const SizedBox(height: 14),
                            Text('Ready to Start', style: poppins(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                            const SizedBox(height: 4),
                            Text(
                              () {
                                final now = DateTime.now();
                                return '${now.day}/${now.month}/${now.year}  •  ${now.hour.toString().padLeft(2,"0")}:${now.minute.toString().padLeft(2,"0")}';
                              }(),
                              style: poppins(fontSize: 13, color: const Color(0xFF8A9CC2)),
                            ),
                            const SizedBox(height: 20),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _startWork,
                                icon: const Icon(Icons.play_arrow_rounded, size: 26),
                                label: Text('Start Work', style: poppins(fontWeight: FontWeight.bold, fontSize: 17)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF4DA6FF),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  elevation: 0,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ── Weekly Stats ──
                    Text('This Week ${_getCurrentWeekDateRange()}', style: poppins(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                      ),
                      padding: const EdgeInsets.all(20),
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
                                    _formatWeeklyProgress(totalWeekSecs),
                                    style: poppins(fontSize: 32, fontWeight: FontWeight.bold, color: progressColor),
                                  ),
                                  Text('of 12h weekly target', style: poppins(fontSize: 12, color: const Color(0xFF8A9CC2))),
                                ],
                              ),
                              Container(
                                width: 64, height: 64,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: progressColor.withValues(alpha: 0.3), width: 3),
                                  color: progressColor.withValues(alpha: 0.1),
                                ),
                                child: Center(
                                  child: Text(
                                    '${(weekProgress * 100).toInt()}%',
                                    style: poppins(fontSize: 13, fontWeight: FontWeight.bold, color: progressColor),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              value: weekProgress,
                              minHeight: 12,
                              backgroundColor: Colors.white.withValues(alpha: 0.08),
                              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('0h', style: poppins(fontSize: 11, color: const Color(0xFF8A9CC2))),
                              if (weekProgress < 1)
                                Text(
                                  '${_formatWeeklyProgress(_weeklyTargetSeconds - totalWeekSecs)} remaining',
                                  style: poppins(fontSize: 11, color: const Color(0xFF8A9CC2)),
                                )
                              else
                                Text('Target reached! 🎉', style: poppins(fontSize: 11, color: const Color(0xFF00C48C), fontWeight: FontWeight.bold)),
                              Text('12h', style: poppins(fontSize: 11, color: const Color(0xFF8A9CC2))),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 28),
                    Text('Session History', style: poppins(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),

            // ── History List ──
            if (_loadingHistory)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator(color: Color(0xFF4DA6FF))),
                ),
              )
            else if (_history.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: Column(
                      children: [
                        const Icon(Icons.history_rounded, color: Color(0xFF8A9CC2), size: 48),
                        const SizedBox(height: 12),
                        Text('No sessions yet.\nStart your first work session!',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(fontSize: 14, color: const Color(0xFF8A9CC2))),
                      ],
                    ),
                  ),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final session = _history[index];
                    final secs = (session['duration_seconds'] as num?)?.toInt();
                    final isActive = session['is_active'] == true;
                    final startStr = session['start_time'] as String?;
                    final ratio = secs != null ? (secs / _weeklyTargetSeconds).clamp(0.0, 1.0) : 0.0;

                    return Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: isActive ? 0.08 : 0.04),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isActive ? const Color(0xFF00C48C).withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.07),
                          ),
                        ),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      isActive ? Icons.play_circle_rounded : Icons.check_circle_rounded,
                                      color: isActive ? const Color(0xFF00C48C) : const Color(0xFF4DA6FF),
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _formatDateTime(startStr),
                                      style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                                    ),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isActive ? const Color(0xFF00C48C).withValues(alpha: 0.15) : const Color(0xFF4DA6FF).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    isActive ? 'Working' : _formatDurationShort(secs),
                                    style: GoogleFonts.poppins(fontSize: 11, fontWeight: isActive ? FontWeight.w900 : FontWeight.bold,
                                      color: isActive ? const Color(0xFF00FF87) : const Color(0xFF4DA6FF)),
                                  ),
                                ),
                              ],
                            ),
                            if (!isActive && secs != null) ...[
                              const SizedBox(height: 10),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: ratio.toDouble(),
                                  minHeight: 5,
                                  backgroundColor: Colors.white.withValues(alpha: 0.07),
                                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF4DA6FF)),
                                ),
                              ),
                            ],
                            if (session['summary'] != null && (session['summary'] as String).isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Summary: ${session['summary']}',
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.poppins(fontSize: 12, color: const Color(0xFFE2E8F0), fontWeight: FontWeight.w500),
                              ),
                            ],
                            if (session['location_log'] != null && (session['location_log'] as String).isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.black26,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  session['location_log'] as String,
                                  style: GoogleFonts.poppins(fontSize: 11, color: const Color(0xFFFFB800)),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                  childCount: _history.length,
                ),
              ),

            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }
}
