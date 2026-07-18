import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'main.dart';
import 'app_toast.dart';

// ─────────────── Admin Logs Page ───────────────
class LogsAdminPage extends StatefulWidget {
  final UserData? userData;
  const LogsAdminPage({super.key, this.userData});
  @override
  State<LogsAdminPage> createState() => _LogsAdminPageState();
}

class _LogsAdminPageState extends State<LogsAdminPage> {
  bool _isLoading = true;
  bool _loadingSummary = true;
  List<Map<String, dynamic>> _allLogs = [];
  List<Map<String, dynamic>> _adminSummaryUsers = [];
  String _selectedTeam = 'All';
  String _selectedRoleFilter = 'All Roles';
  List<String> _teams = ['All', 'PR', 'Media', 'Events', 'Web Dev', 'Admin'];
  final List<String> _roles = ['All Roles', 'Leads Only', 'Members Only'];
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _refreshTimer;
  io.Socket? _socket;

  @override
  void initState() {
    super.initState();
    _loadTeams();
    _fetchLogs();
    _fetchSummary();
    _searchCtrl.addListener(_onSearchChanged);
    _initSocket();
    // Auto-refresh the admin dashboard every 15 seconds for accurate real-time tracking
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _fetchLogs(silent: true);
      _fetchSummary(silent: true);
    });
  }

  Future<void> _loadTeams() async {
    try {
      final fetched = await fetchUniqueTeams();
      if (fetched.isNotEmpty) {
        if (mounted) {
          setState(() {
            // Keep 'All' at the beginning
            _teams = ['All', ...fetched];
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading unique teams: $e');
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _refreshTimer?.cancel();
    _disposeSocket();
    super.dispose();
  }

  void _initSocket() {
    try {
      _socket = io.io(apiBaseUrl, <String, dynamic>{
        'transports': ['websocket'],
        'autoConnect': true,
      });
      _socket?.onConnect((_) {
        debugPrint('[Socket] Admin logs connected');
      });
      _socket?.on('live_location_update', (_) {
        if (mounted) {
          _fetchLogs(silent: true);
          _fetchSummary(silent: true);
        }
      });
      _socket?.on('live_location_removed', (_) {
        if (mounted) {
          _fetchLogs(silent: true);
          _fetchSummary(silent: true);
        }
      });
    } catch (e) {
      debugPrint('Admin socket init error: $e');
    }
  }

  void _disposeSocket() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }

  void _onSearchChanged() {
    _fetchLogs(silent: true);
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _fetchLogs({bool silent = false}) async {
    if (!silent) {
      setState(() => _isLoading = true);
    }
    try {
      final teamFilter = _selectedTeam == 'All' ? '' : '&team=${Uri.encodeComponent(_selectedTeam)}';
      final searchVal = _searchCtrl.text.trim();
      final searchFilter = searchVal.isEmpty ? '' : '&search=${Uri.encodeComponent(searchVal)}';

      final res = await http.get(
        Uri.parse('$apiBaseUrl/api/logs/all?limit=100$teamFilter$searchFilter'),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) {
          setState(() {
            _allLogs = List<Map<String, dynamic>>.from(data['sessions'] ?? []);
            _isLoading = false;
          });
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchSummary({bool silent = false}) async {
    if (!silent) {
      if (mounted) setState(() => _loadingSummary = true);
    }
    try {
      final res = await http.get(Uri.parse('$apiBaseUrl/api/logs/admin-summary'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) {
          setState(() {
            _adminSummaryUsers = List<Map<String, dynamic>>.from(data['users'] ?? []);
            _loadingSummary = false;
          });
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loadingSummary = false);
    }
  }

  Future<void> _refreshAll() async {
    await Future.wait([
      _fetchLogs(),
      _fetchSummary(),
    ]);
  }

  Future<void> _stopSessionByAdmin(Map<String, dynamic> log) async {
    final email = log['user_email'];
    if (email == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A2B4A),
        title: Text(
          'Confirm Stop Session',
          style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to stop ${log['user_name'] ?? 'this member'}\'s active session?',
          style: GoogleFonts.poppins(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel', style: GoogleFonts.poppins(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF6B6B)),
            child: Text('Stop Session', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final res = await http.post(
        Uri.parse('$apiBaseUrl/api/logs/stop'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_email': email,
          'summary': 'Stopped by Admin',
          'session_id': log['id'],
        }),
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true) {
          AppToast.show(context, 'Session stopped successfully.', type: ToastType.success);
        } else {
          AppToast.show(context, data['message'] ?? 'Failed to stop session.', type: ToastType.error);
        }
      } else {
        AppToast.show(context, 'Server error stopping session.', type: ToastType.error);
      }
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, 'Network error stopping session.', type: ToastType.error);
    } finally {
      if (mounted) {
        _refreshAll();
      }
    }
  }

  String _formatDuration(int? seconds) {
    if (seconds == null || seconds <= 0) return '0h 0m 0s';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    return '${h}h ${m}m ${s}s';
  }

  String _formatWeeklyHours(dynamic secs) {
    if (secs == null) return '0h 0m 0s';
    final totalSecs = int.tryParse(secs.toString()) ?? 0;
    final h = totalSecs ~/ 3600;
    final m = (totalSecs % 3600) ~/ 60;
    final s = totalSecs % 60;
    return '${h}h ${m}m ${s}s';
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

  @override
  Widget build(BuildContext context) {
    final poppins = GoogleFonts.poppins;

    // Filter into live working sessions and historical entries
    final activeLogs = _allLogs.where((l) => l['is_active'] == true).toList();
    final completedLogs = _allLogs.where((l) => l['is_active'] != true).toList();

    // Filter Worked Hours summary list
    final filteredSummaryUsers = _adminSummaryUsers.where((u) {
      if (_selectedRoleFilter == 'Leads Only' && u['role'] != 'Lead') return false;
      if (_selectedRoleFilter == 'Members Only' && u['role'] != 'Member') return false;
      
      if (_selectedTeam != 'All') {
        final t = (u['team'] as String? ?? '').toLowerCase();
        if (t != _selectedTeam.toLowerCase()) return false;
      }
      
      final q = _searchCtrl.text.trim().toLowerCase();
      if (q.isNotEmpty) {
        final name = (u['name'] as String? ?? '').toLowerCase();
        final roll = (u['roll_number'] as String? ?? '').toLowerCase();
        final email = (u['email'] as String? ?? '').toLowerCase();
        if (!name.contains(q) && !roll.contains(q) && !email.contains(q)) return false;
      }
      
      return true;
    }).toList();

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text('Work Logs (Admin)', style: poppins(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
          bottom: TabBar(
            indicatorColor: const Color(0xFF4DA6FF),
            labelColor: const Color(0xFF4DA6FF),
            unselectedLabelColor: Colors.white54,
            labelStyle: poppins(fontWeight: FontWeight.bold, fontSize: 13),
            tabs: const [
              Tab(text: 'Real-time Live'),
              Tab(text: 'Session History'),
              Tab(text: 'Worked Hours'),
            ],
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: TabBarView(
                children: [
                  // ── Tab 1: Live Logs ──
                  Column(
                    children: [
                      _buildSearchAndTeamFilter(poppins),
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: _refreshAll,
                          color: const Color(0xFF4DA6FF),
                          backgroundColor: const Color(0xFF1A2B4A),
                          child: _isLoading
                              ? const Center(child: CircularProgressIndicator(color: Color(0xFF4DA6FF)))
                              : activeLogs.isEmpty
                                  ? Center(
                                      child: Text('No members currently active.',
                                          style: poppins(color: const Color(0xFF8A9CC2), fontSize: 14)),
                                    )
                                  : ListView.builder(
                                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                      itemCount: activeLogs.length,
                                      itemBuilder: (context, idx) {
                                        final log = activeLogs[idx];
                                        return AdminLiveLogTile(
                                          log: log,
                                          poppins: poppins,
                                          formatDateTime: _formatDateTime,
                                          onStopPressed: () => _stopSessionByAdmin(log),
                                        );
                                      },
                                    ),
                        ),
                      ),
                    ],
                  ),

                  // ── Tab 2: History Logs ──
                  Column(
                    children: [
                      _buildSearchAndTeamFilter(poppins),
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: _refreshAll,
                          color: const Color(0xFF4DA6FF),
                          backgroundColor: const Color(0xFF1A2B4A),
                          child: _isLoading
                              ? const Center(child: CircularProgressIndicator(color: Color(0xFF4DA6FF)))
                              : completedLogs.isEmpty
                                  ? Center(
                                      child: Text('No historical logs found.',
                                          style: poppins(color: const Color(0xFF8A9CC2))),
                                    )
                                  : ListView.builder(
                                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                      itemCount: completedLogs.length,
                                      itemBuilder: (context, idx) {
                                        final log = completedLogs[idx];
                                        final duration = log['duration_seconds'] as int?;
                                        return Container(
                                          margin: const EdgeInsets.only(bottom: 12),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(alpha: 0.04),
                                            borderRadius: BorderRadius.circular(16),
                                            border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
                                          ),
                                          padding: const EdgeInsets.all(16),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Expanded(
                                                    child: Row(
                                                      children: [
                                                        ClipRRect(
                                                          borderRadius: BorderRadius.circular(20),
                                                          child: Container(
                                                            width: 40,
                                                            height: 40,
                                                            color: Colors.white.withValues(alpha: 0.1),
                                                            child: (log['image_url'] != null && (log['image_url'] as String).isNotEmpty)
                                                                ? Image.network(
                                                                    log['image_url'],
                                                                    fit: BoxFit.cover,
                                                                    errorBuilder: (context, error, stackTrace) {
                                                                      return Center(
                                                                        child: Text(
                                                                          (log['user_name'] ?? 'U').substring(0, 1).toUpperCase(),
                                                                          style: poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                                                                        ),
                                                                      );
                                                                    },
                                                                  )
                                                                : Center(
                                                                    child: Text(
                                                                      (log['user_name'] ?? 'U').substring(0, 1).toUpperCase(),
                                                                      style: poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                                                                    ),
                                                                  ),
                                                          ),
                                                        ),
                                                        const SizedBox(width: 12),
                                                        Expanded(
                                                          child: Column(
                                                            crossAxisAlignment: CrossAxisAlignment.start,
                                                            children: [
                                                              Text(log['user_name'] ?? '',
                                                                  style: poppins(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                                                                  maxLines: 1,
                                                                  overflow: TextOverflow.ellipsis),
                                                              Text('${log['roll_number'] ?? ''}  •  ${log['team'] ?? ''}',
                                                                  style: poppins(fontSize: 11, color: const Color(0xFF8A9CC2))),
                                                            ],
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    _formatDuration(duration),
                                                    style: poppins(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF4DA6FF)),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 10),
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Text(
                                                    'Date: ${_formatDateTime(log['start_time'])}',
                                                    style: poppins(fontSize: 11, color: const Color(0xFF8A9CC2)),
                                                  ),
                                                  Row(
                                                    children: [
                                                      if (log['role'] != null)
                                                        Text(
                                                          log['role'],
                                                          style: poppins(fontSize: 11, color: Colors.white38),
                                                        ),
                                                      const SizedBox(width: 8),
                                                      // Last known location button for completed sessions
                                                      GestureDetector(
                                                        onTap: () {
                                                          Navigator.push(
                                                            context,
                                                            MaterialPageRoute(
                                                              builder: (context) => DesktopPageWrapper(
                                                                child: LiveUserMapPage(
                                                                  userEmail: log['user_email'] ?? '',
                                                                  userName: log['user_name'] ?? 'User',
                                                                  userRole: log['role'] ?? 'Member',
                                                                  isLiveUser: false,
                                                                  sessionId: log['id'] != null ? int.tryParse(log['id'].toString()) : null,
                                                                ),
                                                              ),
                                                            ),
                                                          );
                                                        },
                                                        child: Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                          decoration: BoxDecoration(
                                                            color: const Color(0xFFFFB800).withValues(alpha: 0.12),
                                                            borderRadius: BorderRadius.circular(8),
                                                            border: Border.all(color: const Color(0xFFFFB800).withValues(alpha: 0.4)),
                                                          ),
                                                          child: Row(
                                                            mainAxisSize: MainAxisSize.min,
                                                            children: [
                                                              const Icon(Icons.history_toggle_off_rounded, size: 11, color: Color(0xFFFFB800)),
                                                              const SizedBox(width: 4),
                                                              Text('Click here to see the last location', style: poppins(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFFFFB800))),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                              if (log['summary'] != null && (log['summary'] as String).isNotEmpty) ...[
                                                const SizedBox(height: 8),
                                                Text(
                                                  'Task: "${log['summary']}"',
                                                  style: poppins(fontSize: 12, color: const Color(0xFFE2E8F0), fontStyle: FontStyle.italic),
                                                ),
                                              ],
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                        ),
                      ),
                    ],
                  ),

                  // ── Tab 3: Worked Hours (Weekly summaries + expansion details) ──
                  Column(
                    children: [
                      _buildSearchAndTeamFilter(poppins),
                      // Role filter dropdown
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Weekly Summaries',
                              style: poppins(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _selectedRoleFilter,
                                  dropdownColor: const Color(0xFF1A2B4A),
                                  icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF4DA6FF), size: 18),
                                  items: _roles.map((r) {
                                    return DropdownMenuItem<String>(
                                      value: r,
                                      child: Text(r, style: poppins(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold)),
                                    );
                                  }).toList(),
                                  onChanged: (val) {
                                    if (val != null) {
                                      setState(() => _selectedRoleFilter = val);
                                    }
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: _refreshAll,
                          color: const Color(0xFF4DA6FF),
                          backgroundColor: const Color(0xFF1A2B4A),
                          child: _loadingSummary
                              ? const Center(child: CircularProgressIndicator(color: Color(0xFF4DA6FF)))
                              : filteredSummaryUsers.isEmpty
                                  ? Center(
                                      child: Text('No members found.',
                                          style: poppins(color: const Color(0xFF8A9CC2))),
                                    )
                                  : ListView.builder(
                                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                      itemCount: filteredSummaryUsers.length,
                                      itemBuilder: (context, idx) {
                                        final u = filteredSummaryUsers[idx];
                                        final sessions = u['sessions'] as List? ?? [];
                                        int totalSeconds = 0;
                                        for (final s in sessions) {
                                          if (s['is_active'] == true) {
                                            final start = DateTime.tryParse(s['start_time'] ?? '')?.toLocal();
                                            if (start != null) {
                                              totalSeconds += DateTime.now().difference(start).inSeconds;
                                            }
                                          } else {
                                            totalSeconds += int.tryParse(s['duration_seconds']?.toString() ?? '0') ?? 0;
                                          }
                                        }
                                        return Container(
                                          margin: const EdgeInsets.only(bottom: 12),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(alpha: 0.04),
                                            borderRadius: BorderRadius.circular(16),
                                            border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
                                          ),
                                          child: Material(
                                            color: Colors.transparent,
                                            child: Theme(
                                              data: Theme.of(context).copyWith(
                                                dividerColor: Colors.transparent,
                                              ),
                                              child: ExpansionTile(
                                              collapsedIconColor: Colors.white54,
                                              iconColor: const Color(0xFF4DA6FF),
                                              title: Row(
                                                children: [
                                                  ClipRRect(
                                                    borderRadius: BorderRadius.circular(20),
                                                    child: Container(
                                                      width: 40,
                                                      height: 40,
                                                      color: Colors.white.withValues(alpha: 0.1),
                                                      child: (u['image_url'] != null && (u['image_url'] as String).isNotEmpty)
                                                          ? Image.network(
                                                              u['image_url'],
                                                              fit: BoxFit.cover,
                                                              errorBuilder: (ctx, err, st) => Center(
                                                                child: Text(
                                                                  (u['name'] ?? 'U').substring(0, 1).toUpperCase(),
                                                                  style: poppins(color: Colors.white, fontWeight: FontWeight.bold),
                                                                ),
                                                              ),
                                                            )
                                                          : Center(
                                                              child: Text(
                                                                (u['name'] ?? 'U').substring(0, 1).toUpperCase(),
                                                                style: poppins(color: Colors.white, fontWeight: FontWeight.bold),
                                                              ),
                                                            ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Text(u['name'] ?? '',
                                                            style: poppins(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                                                            maxLines: 1,
                                                            overflow: TextOverflow.ellipsis),
                                                        Text('${u['roll_number'] ?? ''} • ${u['team'] ?? ''}',
                                                            style: poppins(fontSize: 11, color: const Color(0xFF8A9CC2))),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              trailing: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Column(
                                                    mainAxisAlignment: MainAxisAlignment.center,
                                                    crossAxisAlignment: CrossAxisAlignment.end,
                                                    children: [
                                                      Text(
                                                        _formatWeeklyHours(totalSeconds),
                                                        style: poppins(fontSize: 13, fontWeight: FontWeight.w900, color: const Color(0xFF00FF87)),
                                                      ),
                                                      Text(
                                                        u['role'] ?? '',
                                                        style: poppins(fontSize: 10, color: Colors.white38),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(width: 8),
                                                  const Icon(
                                                    Icons.keyboard_arrow_down_rounded,
                                                    color: Colors.white54,
                                                    size: 18,
                                                  ),
                                                ],
                                              ),
                                              children: [
                                                Padding(
                                                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Row(
                                                        children: [
                                                          const Icon(Icons.email_outlined, color: Color(0xFF4DA6FF), size: 14),
                                                          const SizedBox(width: 6),
                                                          Text('Email: ${u['email'] ?? 'N/A'}', style: poppins(fontSize: 12, color: Colors.white70)),
                                                        ],
                                                      ),
                                                      const SizedBox(height: 6),
                                                      Row(
                                                        children: [
                                                          const Icon(Icons.badge_outlined, color: Color(0xFF4DA6FF), size: 14),
                                                          const SizedBox(width: 6),
                                                          Text('Roll No: ${u['roll_number'] ?? 'N/A'}', style: poppins(fontSize: 12, color: Colors.white70)),
                                                        ],
                                                      ),
                                                      const SizedBox(height: 6),
                                                      Row(
                                                        children: [
                                                          const Icon(Icons.group_outlined, color: Color(0xFF4DA6FF), size: 14),
                                                          const SizedBox(width: 6),
                                                          Text('Team: ${u['team'] ?? 'N/A'}', style: poppins(fontSize: 12, color: Colors.white70)),
                                                        ],
                                                      ),
                                                      const SizedBox(height: 6),
                                                      Row(
                                                        children: [
                                                          const Icon(Icons.person_outline, color: Color(0xFF4DA6FF), size: 14),
                                                          const SizedBox(width: 6),
                                                          Text('Role: ${u['role'] ?? 'N/A'}', style: poppins(fontSize: 12, color: Colors.white70)),
                                                        ],
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const Divider(color: Colors.white10, height: 1),
                                                if (sessions.isEmpty)
                                                  Padding(
                                                    padding: const EdgeInsets.all(16.0),
                                                    child: Text('No recent sessions logged.', style: poppins(fontSize: 12, color: Colors.white38)),
                                                  )
                                                else
                                                  ListView.builder(
                                                    shrinkWrap: true,
                                                    physics: const NeverScrollableScrollPhysics(),
                                                    itemCount: sessions.length,
                                                    itemBuilder: (ctx, sIdx) {
                                                      final s = sessions[sIdx];
                                                      final start = DateTime.tryParse(s['start_time'] ?? '')?.toLocal();
                                                      final duration = s['duration_seconds'] as int?;
                                                      final isActive = s['is_active'] == true;
                                                      return Container(
                                                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                                        padding: const EdgeInsets.all(12),
                                                        decoration: BoxDecoration(
                                                          color: Colors.white.withValues(alpha: 0.02),
                                                          borderRadius: BorderRadius.circular(10),
                                                          border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
                                                        ),
                                                        child: Column(
                                                          crossAxisAlignment: CrossAxisAlignment.start,
                                                          children: [
                                                            Row(
                                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                              children: [
                                                                Text(
                                                                  isActive ? 'Working ⚡' : _formatDuration(duration),
                                                                  style: poppins(
                                                                    fontSize: 12,
                                                                    fontWeight: isActive ? FontWeight.w900 : FontWeight.bold,
                                                                    color: isActive ? const Color(0xFF00FF87) : const Color(0xFF4DA6FF),
                                                                  ),
                                                                ),
                                                                Text(
                                                                  start != null ? '${start.day}/${start.month} ${start.hour.toString().padLeft(2, "0")}:${start.minute.toString().padLeft(2, "0")}' : '',
                                                                  style: poppins(fontSize: 10, color: Colors.white38),
                                                                ),
                                                              ],
                                                            ),
                                                            if (s['summary'] != null && (s['summary'] as String).isNotEmpty) ...[
                                                              const SizedBox(height: 6),
                                                              Text(
                                                                'Task: "${s['summary']}"',
                                                                style: poppins(fontSize: 11, color: Colors.white70, fontStyle: FontStyle.italic),
                                                              ),
                                                            ],
                                                          ],
                                                          ),
                                                        );
                                                      },
                                                    ),
                                                  const SizedBox(height: 12),
                                                ],
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchAndTeamFilter(TextStyle Function({Color? color, double? fontSize, FontWeight? fontWeight, double? letterSpacing}) poppins) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: TextField(
                controller: _searchCtrl,
                style: poppins(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Search user, roll, team…',
                  hintStyle: poppins(color: Colors.white38, fontSize: 12),
                  prefixIcon: const Icon(Icons.search, color: Color(0xFF4DA6FF), size: 18),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedTeam,
                dropdownColor: const Color(0xFF1A2B4A),
                icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF4DA6FF), size: 20),
                items: _teams.map((t) {
                  return DropdownMenuItem<String>(
                    value: t,
                    child: Text(t, style: poppins(fontSize: 13, color: Colors.white, fontWeight: FontWeight.bold)),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedTeam = val);
                    _fetchLogs();
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────── Admin Live Log Stateful Tile ───────────────
class AdminLiveLogTile extends StatefulWidget {
  final Map<String, dynamic> log;
  final TextStyle Function({Color? color, double? fontSize, FontWeight? fontWeight, double? letterSpacing}) poppins;
  final String Function(String?) formatDateTime;
  final VoidCallback? onStopPressed;

  const AdminLiveLogTile({
    super.key,
    required this.log,
    required this.poppins,
    required this.formatDateTime,
    this.onStopPressed,
  });

  @override
  State<AdminLiveLogTile> createState() => _AdminLiveLogTileState();
}

class _AdminLiveLogTileState extends State<AdminLiveLogTile> {
  Timer? _ticker;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _startTicker();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AdminLiveLogTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-evaluate ticker whenever backend data changes (e.g. is_paused flips)
    final oldPaused = oldWidget.log['is_paused'] == true;
    final newPaused = widget.log['is_paused'] == true;
    final oldStart = oldWidget.log['start_time'];
    final newStart = widget.log['start_time'];
    if (oldPaused != newPaused || oldStart != newStart) {
      _ticker?.cancel();
      _ticker = null;
      _startTicker();
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = null;

    final startTimeStr = widget.log['start_time'] as String?;
    if (startTimeStr == null) return;
    final st = DateTime.tryParse(startTimeStr)?.toLocal();
    if (st == null) return;

    final isPaused = widget.log['is_paused'] == true;

    if (isPaused) {
      // Session is paused — freeze elapsed at the moment it was paused
      final lastPausedStr = widget.log['last_paused_at'] as String?;
      final lastPaused = lastPausedStr != null
          ? DateTime.tryParse(lastPausedStr)?.toLocal()
          : null;
      _elapsed = lastPaused != null
          ? lastPaused.difference(st)
          : DateTime.now().difference(st);
      // Do NOT start ticker — timer stays frozen
      return;
    }

    // Session is running normally — tick every second
    _elapsed = DateTime.now().difference(st);
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        if (widget.log['is_paused'] == true) {
          timer.cancel();
          return;
        }
        setState(() {
          _elapsed = DateTime.now().difference(st);
        });
      }
    });
  }

  String _formatDuration(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final log = widget.log;
    final isPaused = log['is_paused'] == true;

    final borderColor = isPaused
        ? const Color(0xFFFFB800).withValues(alpha: 0.5)
        : const Color(0xFF00C48C).withValues(alpha: 0.3);
    final bgColor = isPaused
        ? const Color(0xFFFFB800).withValues(alpha: 0.06)
        : const Color(0xFF00C48C).withValues(alpha: 0.08);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        width: 40,
                        height: 40,
                        color: Colors.white.withValues(alpha: 0.1),
                        child: (log['image_url'] != null && (log['image_url'] as String).isNotEmpty)
                            ? Image.network(
                                log['image_url'],
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Center(
                                    child: Text(
                                      (log['user_name'] ?? 'U').substring(0, 1).toUpperCase(),
                                      style: widget.poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                                    ),
                                  );
                                },
                              )
                            : Center(
                                child: Text(
                                  (log['user_name'] ?? 'U').substring(0, 1).toUpperCase(),
                                  style: widget.poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(log['user_name'] ?? '',
                              style: widget.poppins(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          Text('${log['roll_number'] ?? ''}  •  ${log['team'] ?? ''}',
                              style: widget.poppins(fontSize: 11, color: const Color(0xFF8A9CC2))),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // ── Role + paused badge ──
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00C48C).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      log['role'] ?? 'Member',
                      style: widget.poppins(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFF00C48C)),
                    ),
                  ),
                  if (isPaused) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFB800).withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.warning_amber_rounded, size: 10, color: Color(0xFFFFB800)),
                          const SizedBox(width: 4),
                          Text(
                            'Paused',
                            style: widget.poppins(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFFFFB800)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          // ── Alert bar when paused ──
          if (isPaused) ...[
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFFFB800).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFFB800).withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 14, color: Color(0xFFFFB800)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '⚠ Session paused — user is outside the geofence',
                      style: widget.poppins(
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isPaused
                        ? 'Paused at: ${_formatDuration(_elapsed)}'
                        : 'Elapsed: ${_formatDuration(_elapsed)}',
                    style: widget.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: isPaused ? const Color(0xFFFFB800) : const Color(0xFF00FF87),
                    ),
                  ),
                  Text(
                    'Started: ${widget.formatDateTime(log['start_time'])}',
                    style: widget.poppins(fontSize: 11, color: const Color(0xFF8A9CC2)),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton.icon(
                    onPressed: widget.onStopPressed,
                    icon: const Icon(Icons.stop_circle_rounded, size: 14, color: Colors.white),
                    label: Text('Stop', style: widget.poppins(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6B6B),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => DesktopPageWrapper(
                            child: LiveUserMapPage(
                              userEmail: log['user_email'] ?? '',
                              userName: log['user_name'] ?? 'User',
                              userRole: log['role'] ?? 'Member',
                              isLiveUser: true,
                            ),
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.location_on_rounded, size: 14, color: Colors.white),
                    label: Text('Track Live', style: widget.poppins(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4DA6FF),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
