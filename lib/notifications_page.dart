import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'main.dart';

class NotificationsPage extends StatefulWidget {
  final UserData? userData;
  const NotificationsPage({super.key, this.userData});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  List<Map<String, dynamic>> _notifications = [];
  String? _error;
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    )..forward();
    _fetchNotifications();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _fetchNotifications() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final email = widget.userData?.email ?? '';
      final res = await http.get(
        Uri.parse('$apiBaseUrl/api/notifications?email=${Uri.encodeComponent(email)}'),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body) as List;
        setState(() {
          _notifications = data.map((e) => Map<String, dynamic>.from(e)).toList();
          _isLoading = false;
        });
      } else {
        setState(() { _error = 'Failed to load notifications'; _isLoading = false; });
      }
    } catch (e) {
      setState(() { _error = 'Connection error'; _isLoading = false; });
    }
  }

  Future<void> _markIndividualRead(int id) async {
    try {
      final res = await http.post(
        Uri.parse('$apiBaseUrl/api/notifications/mark-individual-read'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'id': id}),
      );
      if (res.statusCode == 200 && mounted) {
        setState(() {
          final idx = _notifications.indexWhere((n) => n['id'] == id);
          if (idx != -1) {
            _notifications[idx]['is_read'] = true;
          }
        });
      }
    } catch (_) {}
  }

  Color _typeColor(String type) {
    if (type.contains('meeting')) return const Color(0xFF4DA6FF);
    if (type.contains('session')) return const Color(0xFF00C48C);
    if (type.contains('attendance')) return const Color(0xFFFF9F43);
    if (type.contains('reminder')) return const Color(0xFFFF6B6B);
    if (type.contains('admin')) return const Color(0xFFFFD600); // Bright Gold
    return const Color(0xFF8A9CC2);
  }

  IconData _typeIcon(String type) {
    if (type.contains('meeting')) return Icons.event_note_rounded;
    if (type.contains('session')) return Icons.timer_rounded;
    if (type.contains('attendance')) return Icons.how_to_reg_rounded;
    if (type.contains('reminder')) return Icons.alarm_rounded;
    if (type.contains('admin')) return Icons.campaign_rounded; // Megaphone
    return Icons.notifications_rounded;
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'meeting_scheduled': return 'Meeting Scheduled';
      case 'meeting_reminder': return 'Meeting Reminder';
      case 'meeting_started': return 'Meeting Started';
      case 'session_started': return 'Session Started';
      case 'attendance_submitted': return 'Attendance';
      case 'attendance_reminder': return 'Attendance Reminder';
      case 'admin_broadcast': return 'Admin Message';
      default: return 'Notification';
    }
  }

  String _formatTime(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return DesktopPageWrapper(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            'Notifications',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.bold,
              color: Colors.white,
              fontSize: 18,
            ),
          ),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.done_all_rounded, color: Color(0xFF00C48C)),
              tooltip: 'Mark all as read',
              onPressed: () async {
                try {
                  final email = widget.userData?.email ?? '';
                  final res = await http.post(
                    Uri.parse('$apiBaseUrl/api/notifications/mark-read'),
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode({'email': email}),
                  );
                  if (res.statusCode == 200 && mounted) {
                    setState(() {
                      for (var n in _notifications) {
                        n['is_read'] = true;
                      }
                    });
                  }
                } catch (_) {}
              },
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: Color(0xFF4DA6FF)),
              onPressed: _fetchNotifications,
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF4DA6FF)))
            : _error != null
                ? _buildError()
                : _notifications.isEmpty
                    ? _buildEmpty()
                    : RefreshIndicator(
                        onRefresh: _fetchNotifications,
                        color: const Color(0xFF4DA6FF),
                        backgroundColor: const Color(0xFF1A2B4A),
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                          itemCount: _notifications.length,
                          itemBuilder: (ctx, i) => _buildCard(i),
                        ),
                      ),
      ),
    );
  }

  Widget _buildCard(int i) {
    final n = _notifications[i];
    final type = (n['type'] as String? ?? 'general');
    final color = _typeColor(type);
    final icon = _typeIcon(type);
    final isRead = n['is_read'] == true;
    final isAdminBroadcast = type == 'admin_broadcast';

    return TweenAnimationBuilder<double>(
      key: ValueKey(n['id']),
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 300 + i * 50),
      builder: (ctx, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 20 * (1 - value)),
          child: child,
        ),
      ),
      child: GestureDetector(
        onTap: () {
          if (!isRead) {
            _markIndividualRead(n['id'] as int);
          }
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: isRead
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.white.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isRead
                  ? Colors.white.withValues(alpha: 0.07)
                  : color.withValues(alpha: 0.3),
              width: isRead ? 1 : 1.5,
            ),
          ),
          child: Stack(
            children: [
              // Left vertical color accent indicator stripe
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 4,
                child: Container(
                  decoration: BoxDecoration(
                    color: isRead ? color.withValues(alpha: 0.3) : color,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                // Icon container
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: color.withValues(alpha: 0.3)),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 14),
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _typeLabel(type).toUpperCase(),
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: color.withValues(alpha: 0.8),
                              letterSpacing: 0.5,
                            ),
                          ),
                          Text(
                            _formatTime(n['sent_at'] as String?),
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: const Color(0xFF8A9CC2),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        n['title'] as String? ?? '',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: isAdminBroadcast ? const Color(0xFFFFD600) : Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        n['body'] as String? ?? '',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: isAdminBroadcast ? FontWeight.bold : FontWeight.w400,
                          color: isAdminBroadcast ? const Color(0xFFFFD600) : const Color(0xFFC9D1E6),
                          height: 1.5,
                        ),
                      ),
                      const SizedBox.shrink(),
                    ],
                  ),
                ),
                if (!isRead)
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(left: 8, top: 4),
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
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

  Widget _buildEmpty() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.notifications_off_outlined, color: Color(0xFF8A9CC2), size: 40),
        ),
        const SizedBox(height: 20),
        Text(
          'No notifications yet',
          style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 8),
        Text(
          'You will be notified about meetings,\nattendance and work sessions here.',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(fontSize: 13, color: const Color(0xFF8A9CC2)),
        ),
      ],
    ),
  );

  Widget _buildError() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.cloud_off_rounded, color: Color(0xFF8A9CC2), size: 48),
        const SizedBox(height: 16),
        Text(_error!, style: GoogleFonts.poppins(color: const Color(0xFF8A9CC2), fontSize: 14)),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _fetchNotifications,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Retry'),
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4DA6FF)),
        ),
      ],
    ),
  );
}
