import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'main.dart'; // To access apiBaseUrl and userData classes
import 'attendance.dart';

class AttendanceAdminTab extends StatefulWidget {
  final UserData? userData;

  const AttendanceAdminTab({super.key, this.userData});

  @override
  State<AttendanceAdminTab> createState() => _AttendanceAdminTabState();
}

class _AttendanceAdminTabState extends State<AttendanceAdminTab> {
  bool _isLoading = true;
  String? _errorMessage;
  List<dynamic> _allRecords = [];
  List<dynamic> _filteredRecords = [];
  bool _showMarkAttendance = false;
  String _attendanceCategory = 'member'; // 'member' or 'lead'
  bool _sortAscending = false;

  // Search & Filter state
  final TextEditingController _searchController = TextEditingController();
  String _selectedTeam = 'All';
  String _selectedRole = 'All';

  List<String> _teams = ['All', 'PR', 'Media', 'Events', 'Web Dev', 'Admin'];
  final List<String> _roles = ['All', 'Lead', 'Member'];

  @override
  void initState() {
    super.initState();
    _loadTeams();
    _fetchSummary();
  }

  Future<void> _loadTeams() async {
    try {
      final fetched = await fetchUniqueTeams();
      if (fetched.isNotEmpty) {
        if (mounted) {
          setState(() {
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
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchSummary() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await http.get(
        Uri.parse('$apiBaseUrl/api/admin/attendance-summary'),
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          _allRecords = data;
          _applyFilters();
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = 'Server returned error status code: ${response.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Network connection failed. Pull down to retry.';
        _isLoading = false;
      });
    }
  }

  void _applyFilters() {
    final query = _searchController.text.trim().toLowerCase();

    setState(() {
      _filteredRecords = _allRecords.where((user) {
        // Search matches Name or Roll Number
        final name = (user['name'] ?? '').toString().toLowerCase();
        final roll = (user['roll_number'] ?? '').toString().toLowerCase();
        final matchesSearch = name.contains(query) || roll.contains(query);

        // Team filter matches
        final team = (user['team'] ?? '').toString();
        final matchesTeam = _selectedTeam == 'All' || team.toLowerCase() == _selectedTeam.toLowerCase();

        // Role filter matches
        final isLead = user['isLead'] == true;
        final matchesRole = _selectedRole == 'All' ||
            (_selectedRole == 'Lead' && isLead) ||
            (_selectedRole == 'Member' && !isLead);

        return matchesSearch && matchesTeam && matchesRole;
      }).toList();

      // Sort by attendance percentage
      _filteredRecords.sort((a, b) {
        final double pctA = (a['percentage'] as num?)?.toDouble() ?? 0.0;
        final double pctB = (b['percentage'] as num?)?.toDouble() ?? 0.0;
        return _sortAscending ? pctA.compareTo(pctB) : pctB.compareTo(pctA);
      });
    });
  }

  Color _getPercentageColor(double percentage) {
    if (percentage >= 75.0) {
      return const Color(0xFF00C48C); // Emerald Green
    } else if (percentage >= 50.0) {
      return const Color(0xFFFFB01A); // Amber
    } else {
      return const Color(0xFFFF6B6B); // Coral Red
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toUpperCase()) {
      case 'PRESENT': return const Color(0xFF00C48C);
      case 'ABSENT': return const Color(0xFFFF6B6B);
      case 'CANCELLED': return const Color(0xFF8A9CC2);
      default: return Colors.white54;
    }
  }

  Widget _buildConsoleToggle(TextStyle Function({double? fontSize, FontWeight? fontWeight, Color? color}) poppins) {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () {
              setState(() {
                _showMarkAttendance = false;
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: !_showMarkAttendance
                    ? const Color(0xFF4DA6FF).withValues(alpha: 0.15)
                    : Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: !_showMarkAttendance
                      ? const Color(0xFF4DA6FF).withValues(alpha: 0.3)
                      : Colors.white10,
                ),
              ),
              child: Text(
                'Directory Console',
                textAlign: TextAlign.center,
                style: poppins(
                  fontSize: 12,
                  color: !_showMarkAttendance ? const Color(0xFF4DA6FF) : Colors.white70,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: GestureDetector(
            onTap: () {
              setState(() {
                _showMarkAttendance = true;
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: _showMarkAttendance
                    ? const Color(0xFF4DA6FF).withValues(alpha: 0.15)
                    : Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _showMarkAttendance
                      ? const Color(0xFF4DA6FF).withValues(alpha: 0.3)
                      : Colors.white10,
                ),
              ),
              child: Text(
                'Mark Attendance',
                textAlign: TextAlign.center,
                style: poppins(
                  fontSize: 12,
                  color: _showMarkAttendance ? const Color(0xFF4DA6FF) : Colors.white70,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final poppins = GoogleFonts.poppins;

    return Scaffold(
      backgroundColor: Colors.transparent, // transparency for background.png
      body: SafeArea(
        child: _showMarkAttendance
            ? Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                    child: _buildConsoleToggle(poppins),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _attendanceCategory = 'member';
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: _attendanceCategory == 'member'
                                    ? const Color(0xFF4DA6FF).withValues(alpha: 0.15)
                                    : Colors.white.withValues(alpha: 0.03),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: _attendanceCategory == 'member'
                                      ? const Color(0xFF4DA6FF).withValues(alpha: 0.3)
                                      : Colors.white10,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.people_rounded,
                                    color: _attendanceCategory == 'member' ? const Color(0xFF4DA6FF) : Colors.white70,
                                    size: 14,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Members',
                                    style: poppins(
                                      fontSize: 12,
                                      color: _attendanceCategory == 'member' ? const Color(0xFF4DA6FF) : Colors.white70,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _attendanceCategory = 'lead';
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: _attendanceCategory == 'lead'
                                    ? const Color(0xFF00C48C).withValues(alpha: 0.15)
                                    : Colors.white.withValues(alpha: 0.03),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: _attendanceCategory == 'lead'
                                      ? const Color(0xFF00C48C).withValues(alpha: 0.3)
                                      : Colors.white10,
                                ),
                              ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.supervisor_account_rounded,
                                    color: _attendanceCategory == 'lead' ? const Color(0xFF00C48C) : Colors.white70,
                                    size: 14,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Leads',
                                    style: poppins(
                                      fontSize: 12,
                                      color: _attendanceCategory == 'lead' ? const Color(0xFF00C48C) : Colors.white70,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _attendanceCategory == 'lead'
                        ? AttendanceTab(
                            key: const ValueKey('leads_attendance'),
                            userData: widget.userData,
                            forceTeam: 'Leads',
                          )
                        : AttendanceTab(
                            key: const ValueKey('members_attendance'),
                            userData: widget.userData,
                          ),
                  ),
                ],
              )
            : RefreshIndicator(
                onRefresh: _fetchSummary,
                color: const Color(0xFF4DA6FF),
                backgroundColor: const Color(0xFF1A2B4A),
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          'Attendance Control',
                                          style: poppins(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
                                        ),
                                        const SizedBox(width: 8),
                                        GestureDetector(
                                          onTap: () {
                                            setState(() {
                                              _sortAscending = !_sortAscending;
                                              _applyFilters();
                                            });
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF4DA6FF).withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: const Color(0xFF4DA6FF).withValues(alpha: 0.2)),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  _sortAscending
                                                      ? Icons.arrow_upward_rounded
                                                      : Icons.arrow_downward_rounded,
                                                  color: const Color(0xFF4DA6FF),
                                                  size: 13,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  _sortAscending ? 'Shortest' : 'Longest',
                                                  style: poppins(
                                                    fontSize: 10.5,
                                                    color: const Color(0xFF4DA6FF),
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      'Admin Directory Console',
                                      style: poppins(fontSize: 13, color: const Color(0xFF4DA6FF), fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                                IconButton(
                                  onPressed: _fetchSummary,
                                  icon: const Icon(Icons.sync_rounded, color: Color(0xFF4DA6FF), size: 26),
                                  tooltip: 'Sync Data',
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _buildConsoleToggle(poppins),
                            const SizedBox(height: 16),
                            // Search Bar
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                              ),
                              child: TextField(
                                controller: _searchController,
                                onChanged: (_) => _applyFilters(),
                                style: poppins(color: Colors.white, fontSize: 14),
                                decoration: InputDecoration(
                                  hintText: 'Search by name or roll number...',
                                  hintStyle: poppins(color: const Color(0xFF8A9CC2), fontSize: 13),
                                  prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF4DA6FF)),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            // Dropdown Filters Row
                            Row(
                              children: [
                                // Team Filter
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.06),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                                    ),
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<String>(
                                        value: _selectedTeam,
                                        dropdownColor: const Color(0xFF1A2B4A),
                                        icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF4DA6FF), size: 18),
                                        items: _teams.map((t) => DropdownMenuItem(
                                          value: t,
                                          child: Text('Team: $t', style: poppins(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold)),
                                        )).toList(),
                                        onChanged: (val) {
                                          if (val != null) {
                                            setState(() => _selectedTeam = val);
                                            _applyFilters();
                                          }
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                // Role Filter
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.06),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                                    ),
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<String>(
                                        value: _selectedRole,
                                        dropdownColor: const Color(0xFF1A2B4A),
                                        icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF4DA6FF), size: 18),
                                        items: _roles.map((r) => DropdownMenuItem(
                                          value: r,
                                          child: Text('Role: $r', style: poppins(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold)),
                                        )).toList(),
                                        onChanged: (val) {
                                          if (val != null) {
                                            setState(() => _selectedRole = val);
                                            _applyFilters();
                                          }
                                        },
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

              // ── Data Content ──
              if (_isLoading)
                const SliverFillRemaining(
                  child: Center(
                    child: CircularProgressIndicator(color: Color(0xFF4DA6FF)),
                  ),
                )
              else if (_errorMessage != null)
                SliverFillRemaining(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.cloud_off_rounded, color: Color(0xFFFF6B6B), size: 48),
                          const SizedBox(height: 16),
                          Text(
                            _errorMessage!,
                            textAlign: TextAlign.center,
                            style: poppins(fontSize: 14, color: const Color(0xFF8A9CC2)),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: _fetchSummary,
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4DA6FF)),
                            child: Text('Retry', style: poppins(color: Colors.white)),
                          )
                        ],
                      ),
                    ),
                  ),
                )
              else if (_filteredRecords.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.people_outline_rounded, color: Color(0xFF8A9CC2), size: 56),
                        const SizedBox(height: 16),
                        Text(
                          'No member records match search criteria.',
                          style: poppins(fontSize: 15, fontWeight: FontWeight.w500, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final user = _filteredRecords[index];
                        final name = user['name'] ?? 'N/A';
                        final roll = user['roll_number'] ?? 'N/A';
                        final role = user['role'] ?? 'Member';
                        final team = user['team'] ?? 'Admin';
                        final double percentage = (user['percentage'] as num?)?.toDouble() ?? 100.0;
                        final int totalMeetings = (user['total_meetings'] as num?)?.toInt() ?? 0;
                        final int presentCount = (user['present_count'] as num?)?.toInt() ?? 0;
                        final List<dynamic> history = user['records'] ?? [];
                        final bool isLead = user['isLead'] == true;
                        final Color pctColor = _getPercentageColor(percentage);
                        final String? imageUrl = user['image_url'];

                        return Container(
                          margin: const EdgeInsets.only(bottom: 14),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: Theme(
                              data: Theme.of(context).copyWith(
                                dividerColor: Colors.transparent,
                              ),
                              child: ExpansionTile(
                                iconColor: const Color(0xFF4DA6FF),
                                collapsedIconColor: Colors.white54,
                                title: Row(
                                  children: [
                                    // Profile image or initials badge
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: isLead ? const Color(0xFF3A5BD9).withValues(alpha: 0.15) : const Color(0xFF4DA6FF).withValues(alpha: 0.15),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: isLead ? const Color(0xFF3A5BD9).withValues(alpha: 0.5) : const Color(0xFF4DA6FF).withValues(alpha: 0.5),
                                          width: 1.5,
                                        ),
                                      ),
                                      child: ClipOval(
                                        child: imageUrl != null && imageUrl.isNotEmpty
                                            ? Image.network(
                                                imageUrl,
                                                fit: BoxFit.cover,
                                                width: 44,
                                                height: 44,
                                                errorBuilder: (ctx, err, st) => Center(
                                                  child: Icon(
                                                    Icons.person_rounded,
                                                    size: 24,
                                                    color: isLead ? const Color(0xFF3A5BD9) : const Color(0xFF4DA6FF),
                                                  ),
                                                ),
                                              )
                                            : Center(
                                                child: Icon(
                                                  Icons.person_rounded,
                                                  size: 24,
                                                  color: isLead ? const Color(0xFF3A5BD9) : const Color(0xFF4DA6FF),
                                                ),
                                              ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            name,
                                            style: poppins(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '$roll • $team',
                                            style: poppins(fontSize: 12, color: const Color(0xFF8A9CC2)),
                                          ),
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
                                          '$percentage%',
                                          style: poppins(fontSize: 16, fontWeight: FontWeight.w800, color: pctColor),
                                        ),
                                        Text(
                                          '$presentCount/$totalMeetings Attended',
                                          style: poppins(fontSize: 10, color: Colors.white38, fontWeight: FontWeight.bold),
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
                                const Divider(color: Colors.white12, height: 1),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(Icons.email_outlined, color: Color(0xFF4DA6FF), size: 14),
                                          const SizedBox(width: 6),
                                          Text('Email: ${user['email'] ?? 'N/A'}', style: poppins(fontSize: 12, color: Colors.white70)),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          const Icon(Icons.badge_outlined, color: Color(0xFF4DA6FF), size: 14),
                                          const SizedBox(width: 6),
                                          Text('Roll No: $roll', style: poppins(fontSize: 12, color: Colors.white70)),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          const Icon(Icons.group_outlined, color: Color(0xFF4DA6FF), size: 14),
                                          const SizedBox(width: 6),
                                          Text('Team: $team', style: poppins(fontSize: 12, color: Colors.white70)),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          Icon(isLead ? Icons.star_rounded : Icons.person_outline, color: const Color(0xFF4DA6FF), size: 14),
                                          const SizedBox(width: 6),
                                          Text('Role: $role', style: poppins(fontSize: 12, color: Colors.white70)),
                                        ],
                                      ),
                                      const SizedBox(height: 14),
                                      Text(
                                        'ATTENDANCE LOG HISTORY',
                                        style: poppins(fontSize: 10, fontWeight: FontWeight.w800, color: const Color(0xFF8A9CC2), letterSpacing: 0.8),
                                      ),
                                      const SizedBox(height: 8),
                                      if (history.isEmpty)
                                        Padding(
                                          padding: const EdgeInsets.all(8.0),
                                          child: Text(
                                            'No sessions recorded yet.',
                                            style: poppins(fontSize: 12, color: Colors.white30, fontStyle: FontStyle.italic),
                                          ),
                                        )
                                      else
                                        Container(
                                          decoration: BoxDecoration(
                                            color: Colors.black.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                                          ),
                                          child: ListView.separated(
                                            shrinkWrap: true,
                                            physics: const NeverScrollableScrollPhysics(),
                                            itemCount: history.length,
                                            separatorBuilder: (BuildContext context, int index) => const Divider(color: Colors.white10, height: 1),
                                            itemBuilder: (context, hIdx) {
                                              final record = history[hIdx];
                                              final date = record['date'] ?? 'N/A';
                                              final status = record['status'] ?? 'N/A';
                                              final reason = record['reason'] ?? '';
                                              final statusColor = _getStatusColor(status);

                                              return Padding(
                                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                      crossAxisAlignment: CrossAxisAlignment.center,
                                                      children: [
                                                        Expanded(
                                                          child: Row(
                                                            children: [
                                                              const Icon(Icons.event, color: Color(0xFF4DA6FF), size: 14),
                                                              const SizedBox(width: 6),
                                                              Expanded(
                                                                child: Text(
                                                                  date,
                                                                  style: poppins(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                                                                  overflow: TextOverflow.ellipsis,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                        const SizedBox(width: 8),
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                          decoration: BoxDecoration(
                                                            color: statusColor.withValues(alpha: 0.12),
                                                            borderRadius: BorderRadius.circular(12),
                                                            border: Border.all(color: statusColor.withValues(alpha: 0.3), width: 0.8),
                                                          ),
                                                          child: Text(
                                                            status.toUpperCase(),
                                                            style: poppins(fontSize: 9, fontWeight: FontWeight.w800, color: statusColor),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    if (status.toUpperCase() == 'ABSENT' && reason.isNotEmpty) ...[
                                                      const SizedBox(height: 6),
                                                      Row(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          const Icon(Icons.info_outline_rounded, color: Color(0xFFFF6B6B), size: 13),
                                                          const SizedBox(width: 6),
                                                          Expanded(
                                                            child: Text(
                                                              'Reason: $reason',
                                                              style: poppins(fontSize: 11, color: const Color(0xFFFF6B6B), fontWeight: FontWeight.bold),
                                                            ),
                                                          ),
                                                        ],
                                                      )
                                                    ] else if (status.toUpperCase() == 'CANCELLED') ...[
                                                      const SizedBox(height: 6),
                                                      Row(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          const Icon(Icons.cancel_presentation_outlined, color: Color(0xFF8A9CC2), size: 13),
                                                          const SizedBox(width: 6),
                                                          Expanded(
                                                            child: Text(
                                                              'Status: Meeting Cancelled',
                                                              style: poppins(fontSize: 11, color: const Color(0xFF8A9CC2), fontStyle: FontStyle.italic),
                                                            ),
                                                          ),
                                                        ],
                                                      )
                                                    ]
                                                  ],
                                                ),
                                              );
                                            },
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
                      },
                      childCount: _filteredRecords.length,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
