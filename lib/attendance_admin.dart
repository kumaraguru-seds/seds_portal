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
  String _selectedWeekFilter = 'This Week';

  List<String> _teams = ['All', 'PR', 'Media', 'Events', 'Web Dev', 'Admin'];
  final List<String> _roles = ['All', 'Lead', 'Member'];
  DateTimeRange? _customDateRange;
  final List<String> _weekKeys = [
    'Today',
    'Yesterday',
    'This Week',
    'Last Week',
    '2 Weeks Ago',
    '3 Weeks Ago',
    'Specific Date',
    'All',
  ];

  Map<String, DateTimeRange> _getWeekRanges() {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);

    final yesterdayStart = todayStart.subtract(const Duration(days: 1));
    final yesterdayEnd = DateTime(yesterdayStart.year, yesterdayStart.month, yesterdayStart.day, 23, 59, 59);

    final int daysSinceSunday = now.weekday == 7 ? 0 : now.weekday;
    final DateTime sundayThisWeek = todayStart.subtract(Duration(days: daysSinceSunday));
    final DateTime saturdayThisWeek = sundayThisWeek.add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59));

    final DateTime startLast = sundayThisWeek.subtract(const Duration(days: 7));
    final DateTime endLast = startLast.add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59));

    final DateTime start2Ago = sundayThisWeek.subtract(const Duration(days: 14));
    final DateTime end2Ago = start2Ago.add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59));

    final DateTime start3Ago = sundayThisWeek.subtract(const Duration(days: 21));
    final DateTime end3Ago = start3Ago.add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59));

    final ranges = <String, DateTimeRange>{
      'Today': DateTimeRange(start: todayStart, end: todayEnd),
      'Yesterday': DateTimeRange(start: yesterdayStart, end: yesterdayEnd),
      'This Week': DateTimeRange(start: sundayThisWeek, end: saturdayThisWeek),
      'Last Week': DateTimeRange(start: startLast, end: endLast),
      '2 Weeks Ago': DateTimeRange(start: start2Ago, end: end2Ago),
      '3 Weeks Ago': DateTimeRange(start: start3Ago, end: end3Ago),
    };

    if (_customDateRange != null) {
      ranges['Specific Date'] = _customDateRange!;
    }

    return ranges;
  }

  String _getWeekLabel(String key) {
    if (key == 'All') return 'All Time';
    if (key == 'Today') return 'Today';
    if (key == 'Yesterday') return 'Yesterday';
    if (key == 'Specific Date...' || key == 'Specific Date') {
      if (_customDateRange != null) {
        final s = _customDateRange!.start;
        return 'Date: ${s.day.toString().padLeft(2, "0")}/${s.month.toString().padLeft(2, "0")}/${s.year}';
      }
      return 'Specific Date...';
    }
    final ranges = _getWeekRanges();
    final range = ranges[key];
    if (range == null) return key;
    final sDay = range.start.day.toString().padLeft(2, '0');
    final sMonth = range.start.month.toString().padLeft(2, '0');
    final eDay = range.end.day.toString().padLeft(2, '0');
    final eMonth = range.end.month.toString().padLeft(2, '0');
    return '$key ($sDay/$sMonth to $eDay/$eMonth)';
  }

  Future<void> _pickCustomDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _customDateRange?.start ?? DateTime.now(),
      firstDate: DateTime(2023),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF4DA6FF),
              onPrimary: Colors.white,
              surface: Color(0xFF1A2B4A),
              onSurface: Colors.white,
            ),
            dialogTheme: const DialogThemeData(backgroundColor: Color(0xFF0D1E3A)),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      final start = DateTime(picked.year, picked.month, picked.day, 0, 0, 0);
      final end = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
      setState(() {
        _customDateRange = DateTimeRange(start: start, end: end);
        _selectedWeekFilter = 'Specific Date';
      });
      _applyFilters();
    }
  }

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

  bool _isDateInSelectedWeek(String? dateStr) {
    if (_selectedWeekFilter == 'All') return true;
    if (dateStr == null || dateStr.isEmpty) return false;

    // Try ISO parse first (for timestamp-style dates)
    DateTime? dt = DateTime.tryParse(dateStr)?.toLocal();

    if (dt == null) {
      // Attendance date field looks like: "07/23/2026 (5:00 PM - 11:00 PM) at SEDS office [OFFLINE]"
      // Extract the first MM/DD/YYYY or YYYY-MM-DD pattern
      try {
        final match = RegExp(r'(\d{1,4})[-/](\d{1,2})[-/](\d{2,4})').firstMatch(dateStr);
        if (match != null) {
          final p1 = int.parse(match.group(1)!);
          final p2 = int.parse(match.group(2)!);
          final p3 = int.parse(match.group(3)!);
          if (p1 > 1900) {
            // YYYY-MM-DD
            dt = DateTime(p1, p2, p3);
          } else if (p3 > 1900) {
            // MM/DD/YYYY (US format used in attendance table)
            dt = DateTime(p3, p1, p2);
          } else {
            // DD/MM/YY fallback
            dt = DateTime(2000 + p3, p2, p1);
          }
        }
      } catch (_) {}
    }

    if (dt == null) return false;

    if (_selectedWeekFilter == 'Specific Date' && _customDateRange != null) {
      return (dt.isAfter(_customDateRange!.start) || dt.isAtSameMomentAs(_customDateRange!.start)) &&
             (dt.isBefore(_customDateRange!.end) || dt.isAtSameMomentAs(_customDateRange!.end));
    }

    final ranges = _getWeekRanges();
    final range = ranges[_selectedWeekFilter];
    if (range == null) return true;

    return (dt.isAfter(range.start) || dt.isAtSameMomentAs(range.start)) &&
           (dt.isBefore(range.end) || dt.isAtSameMomentAs(range.end));
  }


  void _applyFilters() {
    final query = _searchController.text.trim().toLowerCase();

    setState(() {
      final List<dynamic> processed = [];

      for (var rawUser in _allRecords) {
        final user = Map<String, dynamic>.from(rawUser);

        // Search matches Name or Roll Number
        final name = (user['name'] ?? '').toString().toLowerCase();
        final roll = (user['roll_number'] ?? '').toString().toLowerCase();
        final matchesSearch = query.isEmpty || name.contains(query) || roll.contains(query);

        // Team filter matches
        final team = (user['team'] ?? '').toString();
        final matchesTeam = _selectedTeam == 'All' || team.toLowerCase() == _selectedTeam.toLowerCase();

        // Role filter matches
        final isLead = user['isLead'] == true;
        final matchesRole = _selectedRole == 'All' ||
            (_selectedRole == 'Lead' && isLead) ||
            (_selectedRole == 'Member' && !isLead);

        if (!matchesSearch || !matchesTeam || !matchesRole) continue;

        // Week filter & recalculated metrics
        final List<dynamic> allRecords = user['records'] ?? [];
        final filteredRecords = _selectedWeekFilter != 'All'
            ? allRecords.where((r) {
                final dateStr = (r['date'] ?? r['meeting_date'] ?? r['created_at'])?.toString();
                return _isDateInSelectedWeek(dateStr);
              }).toList()
            : allRecords;

        int presentCount = 0;
        int activeMeetings = 0;
        for (var r in filteredRecords) {
          final status = (r['status'] ?? '').toString().toUpperCase();
          if (status == 'PRESENT' || status == 'ABSENT') {
            activeMeetings++;
            if (status == 'PRESENT') {
              presentCount++;
            }
          }
        }
        final double percentage = activeMeetings > 0 ? (presentCount / activeMeetings) * 100.0 : 0.0;

        user['records'] = filteredRecords;
        user['total_meetings'] = activeMeetings;
        user['present_count'] = presentCount;
        user['percentage'] = percentage;

        processed.add(user);
      }

      // Sort by attendance percentage
      processed.sort((a, b) {
        final double pctA = (a['percentage'] as num?)?.toDouble() ?? 0.0;
        final double pctB = (b['percentage'] as num?)?.toDouble() ?? 0.0;
        if (pctA != pctB) {
          return _sortAscending ? pctA.compareTo(pctB) : pctB.compareTo(pctA);
        }
        // Fallback to name sort
        final String nameA = (a['name'] ?? '').toString().toLowerCase();
        final String nameB = (b['name'] ?? '').toString().toLowerCase();
        return nameA.compareTo(nameB);
      });

      _filteredRecords = processed;
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
                                                  _sortAscending ? 'Lowest' : 'Highest',
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
                                  hintText: 'Search user, roll, team...',
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
                            const SizedBox(height: 10),
                            // Week Filter Dropdown
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _weekKeys.contains(_selectedWeekFilter) ? _selectedWeekFilter : 'This Week',
                                  isExpanded: true,
                                  dropdownColor: const Color(0xFF1A2B4A),
                                  icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF4DA6FF), size: 18),
                                  items: _weekKeys.map((w) => DropdownMenuItem(
                                    value: w,
                                    child: Text(_getWeekLabel(w), style: poppins(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold)),
                                  )).toList(),
                                  onChanged: (val) {
                                    if (val != null) {
                                      if (val == 'Specific Date') {
                                        _pickCustomDate(context);
                                      } else {
                                        setState(() => _selectedWeekFilter = val);
                                        _applyFilters();
                                      }
                                    }
                                  },
                                ),
                              ),
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
