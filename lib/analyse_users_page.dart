import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'app_toast.dart';
import 'main.dart';

class AnalyseUsersPage extends StatefulWidget {
  const AnalyseUsersPage({super.key});

  @override
  State<AnalyseUsersPage> createState() => _AnalyseUsersPageState();
}

class _AnalyseUsersPageState extends State<AnalyseUsersPage> with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  
  List<dynamic> _searchResults = [];
  bool _isSearching = false;
  bool _isLoadingUser = false;
  
  Map<String, dynamic>? _selectedUserData;
  TabController? _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _tabController?.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }
    _performSearch(query);
  }

  Future<void> _performSearch(String query) async {
    setState(() {
      _isSearching = true;
    });
    try {
      final response = await http.get(Uri.parse('$apiBaseUrl/api/users/search?q=${Uri.encodeComponent(query)}'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _searchResults = data;
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

  Future<void> _loadUserAnalysis(String email) async {
    _searchFocusNode.unfocus();
    setState(() {
      _searchResults = [];
      _isLoadingUser = true;
      _selectedUserData = null;
    });

    try {
      final response = await http.get(Uri.parse('$apiBaseUrl/api/admin/analyse-user?email=${Uri.encodeComponent(email)}'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _selectedUserData = data;
          });
        }
      } else {
        final errData = jsonDecode(response.body);
        if (mounted) {
          AppToast.error(context, errData['message'] ?? 'Failed to load user analysis.');
        }
      }
    } catch (e) {
      debugPrint('Error loading user analysis: $e');
      if (mounted) {
        AppToast.error(context, 'Connection timeout or server error.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingUser = false;
        });
      }
    }
  }

  String _formatDuration(int? seconds) {
    if (seconds == null || seconds <= 0) return '0m';
    final duration = Duration(seconds: seconds);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }

  String _formatFileSize(dynamic size) {
    if (size == null) return '0 B';
    final double bytes = double.tryParse(size.toString()) ?? 0;
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    var i = 0;
    var doubleSize = bytes;
    while (doubleSize >= 1024 && i < suffixes.length - 1) {
      doubleSize /= 1024;
      i++;
    }
    return '${doubleSize.toStringAsFixed(1)} ${suffixes[i]}';
  }

  @override
  Widget build(BuildContext context) {
    final poppins = GoogleFonts.poppins;
    return Scaffold(
      resizeToAvoidBottomInset: false,
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
            child: Container(color: Colors.black.withValues(alpha: 0.45)),
          ),
          SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFD93D).withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.analytics_rounded,
                          color: Color(0xFFFFD93D),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'User Analytics',
                        style: poppins(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),

                // Search Box
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    style: poppins(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Search by Name, Roll No, or Email...',
                      hintStyle: poppins(color: Colors.white54, fontSize: 14),
                      prefixIcon: _isSearching
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFFD93D)),
                                ),
                              ),
                            )
                          : const Icon(Icons.search_rounded, color: Colors.white70),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, color: Colors.white70),
                              onPressed: () {
                                _searchController.clear();
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.08),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFFFD93D), width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),

                // Search Results Dropdown List
                if (_searchResults.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    constraints: const BoxConstraints(maxHeight: 250),
                    decoration: BoxDecoration(
                      color: const Color(0xFF142850),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        )
                      ],
                    ),
                    child: Scrollbar(
                      thumbVisibility: true,
                      child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _searchResults.length,
                      separatorBuilder: (context, index) => Divider(color: Colors.white.withValues(alpha: 0.1), height: 1),
                      itemBuilder: (context, index) {
                        final item = _searchResults[index];
                        final name = item['name'] ?? '';
                        final roll = item['roll_number'] ?? '';
                        final email = item['email'] ?? '';
                        final role = item['role'] ?? 'Member';
                        final team = item['team'] ?? '';
                        final img = item['image_url'] ?? '';

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.white24,
                            backgroundImage: img.isNotEmpty ? NetworkImage(img) : null,
                            child: img.isEmpty
                                ? const Icon(Icons.person_rounded, color: Colors.white)
                                : null,
                          ),
                          title: Text(
                            name,
                            style: poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          subtitle: Text(
                            '$roll • $email',
                            style: poppins(color: const Color(0xFF8A9CC2), fontSize: 11),
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFD93D).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              team.isNotEmpty && team != 'Admin' ? '$role ($team)' : role,
                              style: poppins(color: const Color(0xFFFFD93D), fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                          onTap: () {
                            _searchController.removeListener(_onSearchChanged);
                            _searchController.text = name;
                            _searchController.addListener(_onSearchChanged);
                            _loadUserAnalysis(email);
                          },
                        );
                      },
                    ),
                  ),
                ),

                // Main Content View
                Expanded(
                  child: _isLoadingUser
                      ? const Center(
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFFD93D)),
                          ),
                        )
                      : _selectedUserData == null
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.person_search_rounded,
                                    size: 64,
                                    color: Colors.white.withValues(alpha: 0.2),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Search and select a user to analyze',
                                    style: poppins(color: Colors.white54, fontSize: 14),
                                  ),
                                ],
                              ),
                            )
                          : _buildUserDashboard(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserDashboard() {
    final poppins = GoogleFonts.poppins;
    final user = _selectedUserData!['user'] ?? {};
    final String name = user['name'] ?? '';
    final String email = user['email'] ?? '';
    final String roll = user['roll_number'] ?? '';
    final String img = user['image_url'] ?? '';
    final bool hasBiometrics = user['has_biometrics'] ?? false;
    final List<dynamic> roles = user['roles'] ?? [];
    final List<dynamic> teams = user['teams'] ?? [];

    return Column(
      children: [
        // User Profile Brief Summary Card
        Padding(
          padding: const EdgeInsets.all(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundColor: Colors.white24,
                  backgroundImage: img.isNotEmpty ? NetworkImage(img) : null,
                  child: img.isEmpty ? const Icon(Icons.person_rounded, size: 36, color: Colors.white) : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              style: poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Tooltip(
                            message: hasBiometrics ? 'Biometrics Registered (Face/Fingerprint)' : 'Biometrics Not Configured',
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: (hasBiometrics ? const Color(0xFF00C48C) : Colors.amber).withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                hasBiometrics ? Icons.verified_user_rounded : Icons.gpp_maybe_rounded,
                                color: hasBiometrics ? const Color(0xFF00C48C) : Colors.amber,
                                size: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$roll • $email',
                        style: poppins(color: const Color(0xFF8A9CC2), fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          ...roles.map((r) => Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF4DA6FF).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  r.toString(),
                                  style: poppins(color: const Color(0xFF4DA6FF), fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              )),
                          ...teams.map((t) => Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.purple.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'Team: $t',
                                  style: poppins(color: Colors.purpleAccent, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              )),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // Tabs
        TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: const Color(0xFFFFD93D),
          unselectedLabelColor: Colors.white54,
          indicatorColor: const Color(0xFFFFD93D),
          indicatorWeight: 3,
          labelStyle: poppins(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: const [
            Tab(text: 'Work Tracking'),
            Tab(text: 'Login Logs'),
            Tab(text: 'Attendance'),
            Tab(text: 'Documents'),
            Tab(text: 'Notifications'),
            Tab(text: 'Raw DB Dump'),
          ],
        ),

        // Tab views
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildWorkSessionsTab(),
              _buildLoginSessionsTab(),
              _buildAttendanceTab(),
              _buildDocumentsTab(),
              _buildNotificationsTab(),
              _buildRawDumpTab(),
            ],
          ),
        ),
      ],
    );
  }

  // TAB 1: Work tracking sessions
  Widget _buildWorkSessionsTab() {
    final poppins = GoogleFonts.poppins;
    final List<dynamic> list = _selectedUserData!['work_sessions'] ?? [];
    if (list.isEmpty) {
      return Center(child: Text('No work sessions logged.', style: poppins(color: Colors.white54)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final item = list[index];
        final start = item['start_time'] != null ? DateTime.parse(item['start_time']).toLocal() : null;
        final stop = item['stop_time'] != null ? DateTime.parse(item['stop_time']).toLocal() : null;
        final summary = item['summary'] ?? '(No summary provided)';
        final ip = item['ip_address'] ?? 'Unknown IP';
        final isPaused = item['is_paused'] ?? false;
        final isActive = item['is_active'] ?? false;
        final locationLog = item['location_log'] ?? '';

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: (isActive ? const Color(0xFF00C48C) : Colors.white24).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isActive ? 'ACTIVE NOW' : 'COMPLETED',
                      style: poppins(
                        color: isActive ? const Color(0xFF00C48C) : Colors.white70,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _formatDuration(item['duration_seconds']),
                    style: poppins(color: const Color(0xFFFFD93D), fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Summary: $summary',
                style: poppins(color: Colors.white, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Text(
                'Start: ${start?.toString().split('.')[0] ?? 'N/A'}',
                style: poppins(color: Colors.white54, fontSize: 11),
              ),
              if (stop != null)
                Text(
                  'Stop: ${stop.toString().split('.')[0]}',
                  style: poppins(color: Colors.white54, fontSize: 11),
                ),
              Text(
                'IP Address: $ip',
                style: poppins(color: Colors.white54, fontSize: 11),
              ),
              if (isPaused)
                Text(
                  'Status: Paused',
                  style: poppins(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              if (locationLog.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Locations Tracked: $locationLog',
                  style: poppins(color: const Color(0xFF4DA6FF), fontSize: 11),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // TAB 2: Login sessions and visited pages activity
  Widget _buildLoginSessionsTab() {
    final poppins = GoogleFonts.poppins;
    final List<dynamic> list = _selectedUserData!['login_sessions'] ?? [];
    if (list.isEmpty) {
      return Center(child: Text('No login activity registered.', style: poppins(color: Colors.white54)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final item = list[index];
        final loginTime = item['login_time'] != null ? DateTime.parse(item['login_time']).toLocal() : null;
        final logoutTime = item['logout_time'] != null ? DateTime.parse(item['logout_time']).toLocal() : null;
        final ip = item['ip_address'] ?? 'Unknown';
        final pagesStr = item['visited_pages'] ?? '';
        final actionsStr = item['actions_performed'] ?? '';

        final List<String> pages = pagesStr.toString().split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
        final List<String> actions = actionsStr.toString().split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.login_rounded, color: Color(0xFF00C48C), size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Logged In: ${loginTime?.toString().split('.')[0] ?? 'N/A'}',
                    style: poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),
              if (logoutTime != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Logged Out: ${logoutTime.toString().split('.')[0]}',
                      style: poppins(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 6),
              Text('IP: $ip', style: poppins(color: Colors.white54, fontSize: 11)),
              if (pages.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text('Visited Pages:', style: poppins(color: const Color(0xFF4DA6FF), fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: pages.map((p) => Chip(
                        label: Text(p, style: poppins(fontSize: 10, color: Colors.white)),
                        backgroundColor: Colors.white.withValues(alpha: 0.08),
                        padding: EdgeInsets.zero,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      )).toList(),
                ),
              ],
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text('Actions Tracked:', style: poppins(color: Colors.purpleAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: actions.map((a) => Chip(
                        label: Text(a, style: poppins(fontSize: 10, color: Colors.white)),
                        backgroundColor: Colors.purple.withValues(alpha: 0.15),
                        padding: EdgeInsets.zero,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      )).toList(),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // TAB 3: Team Attendance View
  Widget _buildAttendanceTab() {
    final poppins = GoogleFonts.poppins;
    final Map<String, dynamic> attendance = _selectedUserData!['attendance'] ?? {};
    if (attendance.isEmpty) {
      return Center(child: Text('No attendance database table found for user\'s teams.', style: poppins(color: Colors.white54)));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: attendance.entries.map((entry) {
        final team = entry.key;
        final data = entry.value;
        final double percentage = double.tryParse(data['percentage'].toString()) ?? 100.0;
        final int total = data['total_meetings'] ?? 0;
        final int present = data['present_count'] ?? 0;
        final int absent = data['absent_count'] ?? 0;
        final List<dynamic> records = data['records'] ?? [];

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Team: $team',
                    style: poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: (percentage >= 75 ? const Color(0xFF00C48C) : Colors.redAccent).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$percentage%',
                      style: poppins(
                        color: percentage >= 75 ? const Color(0xFF00C48C) : Colors.redAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatItem('Total', total.toString(), Colors.white70),
                  _buildStatItem('Present', present.toString(), const Color(0xFF00C48C)),
                  _buildStatItem('Absent', absent.toString(), Colors.redAccent),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(color: Colors.white24),
              const SizedBox(height: 6),
              Text(
                'Meeting Logs:',
                style: poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 8),
              if (records.isEmpty)
                Text('No meetings recorded.', style: poppins(color: Colors.white54, fontSize: 12))
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: records.length,
                  itemBuilder: (context, idx) {
                    final rec = records[idx];
                    final date = rec['date'] ?? '';
                    final status = rec['status'] ?? '';
                    final reason = rec['reason'] ?? '';
                    final isPresent = status.toString().toLowerCase() == 'present';

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            isPresent ? Icons.check_circle_rounded : Icons.cancel_rounded,
                            color: isPresent ? const Color(0xFF00C48C) : Colors.redAccent,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Date: $date • Status: $status',
                                  style: poppins(color: Colors.white70, fontSize: 12),
                                ),
                                if (reason.toString().isNotEmpty)
                                  Text(
                                    'Reason: $reason',
                                    style: poppins(color: Colors.amber, fontSize: 11, fontStyle: FontStyle.italic),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    final poppins = GoogleFonts.poppins;
    return Column(
      children: [
        Text(value, style: poppins(color: color, fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(label, style: poppins(color: Colors.white38, fontSize: 11)),
      ],
    );
  }

  // TAB 4: Uploaded Documents
  Widget _buildDocumentsTab() {
    final poppins = GoogleFonts.poppins;
    final List<dynamic> list = _selectedUserData!['uploads'] ?? [];
    if (list.isEmpty) {
      return Center(child: Text('No uploaded files found for this user.', style: poppins(color: Colors.white54)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final doc = list[index];
        final name = doc['file_name'] ?? 'file';
        final size = _formatFileSize(doc['file_size']);
        final ext = doc['file_extension'] ?? '';
        final link = doc['drive_link'] ?? '';
        final time = doc['upload_time'] != null ? DateTime.parse(doc['upload_time']).toLocal() : null;
        final visibility = doc['visibility_type'] ?? 'anyone';

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF4DA6FF).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.insert_drive_file_rounded, color: Color(0xFF4DA6FF), size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$size • $ext • Visibility: $visibility',
                      style: poppins(color: const Color(0xFF8A9CC2), fontSize: 11),
                    ),
                    if (time != null)
                      Text(
                        'Uploaded: ${time.toString().split('.')[0]}',
                        style: poppins(color: Colors.white30, fontSize: 10),
                      ),
                  ],
                ),
              ),
              if (link.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.open_in_new_rounded, color: Color(0xFFFFD93D), size: 20),
                  onPressed: () async {
                    final uri = Uri.parse(link);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    } else {
                      if (context.mounted) {
                        AppToast.error(context, 'Could not launch Google Drive link.');
                      }
                    }
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  // TAB 5: Notifications
  Widget _buildNotificationsTab() {
    final poppins = GoogleFonts.poppins;
    final List<dynamic> list = _selectedUserData!['notifications'] ?? [];
    if (list.isEmpty) {
      return Center(child: Text('No notification history found.', style: poppins(color: Colors.white54)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final item = list[index];
        final title = item['title'] ?? 'Notification';
        final body = item['body'] ?? '';
        final type = item['type'] ?? 'General';
        final sentAt = item['sent_at'] != null ? DateTime.parse(item['sent_at']).toLocal() : null;
        final isRead = item['is_read'] ?? false;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.purple.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      type.toString().toUpperCase(),
                      style: poppins(color: Colors.purpleAccent, fontSize: 9, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const Spacer(),
                  if (sentAt != null)
                    Text(
                      sentAt.toString().split('.')[0],
                      style: poppins(color: Colors.white30, fontSize: 10),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 4),
              Text(
                body,
                style: poppins(color: const Color(0xFF8A9CC2), fontSize: 12),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                    isRead ? Icons.mark_chat_read_rounded : Icons.mark_chat_unread_rounded,
                    color: isRead ? const Color(0xFF00C48C) : Colors.amber,
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isRead ? 'Read by user' : 'Delivered / Unread',
                    style: poppins(color: isRead ? const Color(0xFF00C48C) : Colors.amber, fontSize: 10),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // TAB 6: Raw JSON database dump
  Widget _buildRawDumpTab() {
    final poppins = GoogleFonts.poppins;
    final rawJsonStr = const JsonEncoder.withIndent('  ').convert(_selectedUserData);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black38,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: Colors.white10,
              child: Row(
                children: [
                  const Icon(Icons.code_rounded, color: Color(0xFFFFD93D), size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Raw PostgreSQL Record Dump',
                    style: poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Text(
                  rawJsonStr,
                  style: GoogleFonts.sourceCodePro(
                    color: const Color(0xFFA5D6A7),
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
