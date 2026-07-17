import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'main.dart'; // To access apiBaseUrl and userData classes if needed

class AttendanceMembersTab extends StatefulWidget {
  final dynamic userData;

  const AttendanceMembersTab({super.key, this.userData});

  @override
  State<AttendanceMembersTab> createState() => _AttendanceMembersTabState();
}

class _AttendanceMembersTabState extends State<AttendanceMembersTab> {
  bool _isLoading = true;
  String? _errorMessage;
  Map<String, dynamic> _attendanceData = {
    'percentage': 100.0,
    'total_meetings': 0,
    'present_count': 0,
    'absent_count': 0,
    'absent_records': []
  };
  List<dynamic> _upcomingMeetings = [];

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    await Future.wait([
      _fetchMemberAttendance(),
      _fetchUpcomingMeetings(),
    ]);
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _fetchMemberAttendance() async {
    final roll = widget.userData?.rollNumber;
    final team = widget.userData?.team;

    if (roll == null || team == null || roll.isEmpty || team.isEmpty) {
      setState(() {
        _errorMessage = 'Invalid user profile data.';
      });
      return;
    }

    try {
      final response = await http.get(
        Uri.parse('$apiBaseUrl/api/attendance/member?roll_number=${Uri.encodeComponent(roll)}&team=${Uri.encodeComponent(team)}'),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        setState(() {
          _attendanceData = data;
        });
      } else {
        setState(() {
          _errorMessage = 'Failed to load attendance summary.';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Network connection error: $e';
      });
    }
  }

  Future<void> _fetchUpcomingMeetings() async {
    final team = widget.userData?.team;
    if (team == null || team.isEmpty) return;

    try {
      final response = await http.get(
        Uri.parse('$apiBaseUrl/api/meetings?team_name=${Uri.encodeComponent(team)}'),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          _upcomingMeetings = data;
        });
      }
    } catch (e) {
      debugPrint('Error fetching upcoming meetings: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final poppins = GoogleFonts.poppins;
    final teamName = widget.userData?.team ?? 'SEDS Member';

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _fetchData,
          color: const Color(0xFF4DA6FF),
          backgroundColor: const Color(0xFF0D1E3A),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header Card ──
                _buildHeaderCard(poppins, teamName),
                const SizedBox(height: 16),

                // ── Loader / Error / Content Switch ──
                if (_isLoading)
                  const SizedBox(
                    height: 250,
                    child: Center(
                      child: CircularProgressIndicator(color: Color(0xFF4DA6FF)),
                    ),
                  )
                else if (_errorMessage != null)
                  SizedBox(
                    height: 250,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.2)),
                        ),
                        child: Text(
                          _errorMessage!,
                          style: poppins(color: Colors.redAccent, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  )
                else ...[
                  // ── Chart & Percentage Card ──
                  _buildChartCard(poppins),
                  const SizedBox(height: 20),

                  // ── Stats Row ──
                  _buildStatsRow(poppins),
                  const SizedBox(height: 24),

                  // ── Upcoming Meetings Section ──
                  Text(
                    'Upcoming Meetings',
                    style: poppins(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white70),
                  ),
                  const SizedBox(height: 12),
                  _buildUpcomingMeetingsSection(poppins),
                  const SizedBox(height: 24),

                  // ── Attendance History Log ──
                  Text(
                    'Attendance History Log',
                    style: poppins(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white70),
                  ),
                  const SizedBox(height: 12),
                  _buildAttendanceHistoryList(poppins),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard(TextStyle Function({double? fontSize, FontWeight? fontWeight, Color? color}) poppins, String teamName) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'My Attendance',
                style: poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Text(
                '$teamName Team Member',
                style: poppins(
                  fontSize: 13,
                  color: const Color(0xFF4DA6FF),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          Row(
            children: [
              Icon(Icons.badge_rounded, color: const Color(0xFF4DA6FF).withValues(alpha: 0.8), size: 32),
              const SizedBox(width: 8),
              AppNotificationBell(userData: widget.userData),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChartCard(TextStyle Function({double? fontSize, FontWeight? fontWeight, Color? color}) poppins) {
    final double percentage = (_attendanceData['percentage'] as num?)?.toDouble() ?? 100.0;
    final int total = (_attendanceData['total_meetings'] as num?)?.toInt() ?? 0;

    // Gradient bar widths
    final double fillFactor = total > 0 ? (percentage / 100.0) : 1.0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Attendance Rate',
                style: poppins(fontSize: 14, color: Colors.white60, fontWeight: FontWeight.w500),
              ),
              Text(
                '$percentage%',
                style: poppins(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: percentage >= 75 ? const Color(0xFF00E676) : Colors.orangeAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Horizontal Bar Chart (Robust via LayoutBuilder) ──
          LayoutBuilder(
            builder: (context, constraints) {
              final trackWidth = constraints.maxWidth;
              final fillWidth = trackWidth * fillFactor;
              return Stack(
                children: [
                  // Track
                  Container(
                    height: 14,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(7),
                    ),
                  ),
                  // Fill Bar
                  Container(
                    height: 14,
                    width: fillWidth > 0 ? fillWidth : 0.1,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF00E676), Color(0xFF00B0FF)],
                      ),
                      borderRadius: BorderRadius.circular(7),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00E676).withValues(alpha: 0.25),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '0%',
                style: poppins(fontSize: 11, color: Colors.white30),
              ),
              if (percentage < 75 && total > 0)
                Text(
                  'Needs Improvement (Aim for 75%+)',
                  style: poppins(fontSize: 10, color: Colors.orangeAccent, fontWeight: FontWeight.w500),
                )
              else
                Text(
                  'Good Standing',
                  style: poppins(fontSize: 10, color: const Color(0xFF00E676), fontWeight: FontWeight.w500),
                ),
              Text(
                '100%',
                style: poppins(fontSize: 11, color: Colors.white30),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow(TextStyle Function({double? fontSize, FontWeight? fontWeight, Color? color}) poppins) {
    final int total = (_attendanceData['total_meetings'] as num?)?.toInt() ?? 0;
    final int present = (_attendanceData['present_count'] as num?)?.toInt() ?? 0;
    final int absent = (_attendanceData['absent_count'] as num?)?.toInt() ?? 0;

    return Row(
      children: [
        Expanded(child: _buildStatItem(poppins, 'Total', '$total', Colors.white)),
        const SizedBox(width: 10),
        Expanded(child: _buildStatItem(poppins, 'Attended', '$present', const Color(0xFF00E676))),
        const SizedBox(width: 10),
        Expanded(child: _buildStatItem(poppins, 'Missed', '$absent', Colors.redAccent)),
      ],
    );
  }

  Widget _buildStatItem(
    TextStyle Function({double? fontSize, FontWeight? fontWeight, Color? color}) poppins,
    String label,
    String value,
    Color accentColor,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentColor.withValues(alpha: 0.25), width: 1.5),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: poppins(fontSize: 22, fontWeight: FontWeight.bold, color: accentColor),
          ),
          const SizedBox(height: 6),
          Text(
            label.toUpperCase(),
            style: poppins(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ],
      ),
    );
  }

  DateTime? _parseMeetingEndDateTime(String dateStr, String endTimeStr) {
    try {
      final dateParts = dateStr.trim().split('/');
      if (dateParts.length != 3) return null;
      final month = int.parse(dateParts[0]);
      final day = int.parse(dateParts[1]);
      final year = int.parse(dateParts[2]);

      final timeParts = endTimeStr.trim().split(' ');
      if (timeParts.length != 2) return null;
      
      final isPM = timeParts[1].toUpperCase() == 'PM';
      final hourMinute = timeParts[0].split(':');
      if (hourMinute.length != 2) return null;

      int hour = int.parse(hourMinute[0]);
      final minute = int.parse(hourMinute[1]);

      if (isPM && hour < 12) {
        hour += 12;
      } else if (!isPM && hour == 12) {
        hour = 0;
      }

      return DateTime(year, month, day, hour, minute);
    } catch (e) {
      debugPrint('Error parsing end date time: $e');
    }
    return null;
  }

  Widget _buildUpcomingMeetingsSection(TextStyle Function({double? fontSize, FontWeight? fontWeight, Color? color}) poppins) {
    final now = DateTime.now();
    
    final List<dynamic> upcomingOnly = _upcomingMeetings.where((meeting) {
      final dateStr = meeting['meeting_date'] ?? '';
      final endTimeStr = meeting['end_time'] ?? '';
      
      final endDateTime = _parseMeetingEndDateTime(dateStr, endTimeStr);
      if (endDateTime == null) return true; // Keep if unparseable to be safe
      
      return now.isBefore(endDateTime);
    }).toList();

    if (upcomingOnly.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Center(
          child: Text(
            'No upcoming meetings scheduled.',
            style: poppins(fontSize: 13, color: Colors.white38, fontWeight: FontWeight.bold),
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: upcomingOnly.length,
      itemBuilder: (context, index) {
        final meeting = upcomingOnly[index];
        final date = meeting['meeting_date'] ?? '';
        final start = meeting['start_time'] ?? '';
        final end = meeting['end_time'] ?? '';
        final venue = meeting['venue'] ?? '';
        final mode = meeting['meeting_mode'] ?? 'OFFLINE';
        final agenda = meeting['agenda'] ?? '';
        final status = meeting['status'] ?? 'SCHEDULED';
        final bool isCancelled = status == 'CANCELLED';

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isCancelled
                ? Colors.redAccent.withValues(alpha: 0.05)
                : Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isCancelled
                  ? Colors.redAccent.withValues(alpha: 0.3)
                  : Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    date,
                    style: poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isCancelled ? Colors.redAccent : const Color(0xFF4DA6FF),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isCancelled
                          ? Colors.redAccent.withValues(alpha: 0.15)
                          : const Color(0xFF4DA6FF).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isCancelled
                            ? Colors.redAccent.withValues(alpha: 0.25)
                            : const Color(0xFF4DA6FF).withValues(alpha: 0.25),
                      ),
                    ),
                    child: Text(
                      isCancelled ? 'CANCELLED' : mode.toUpperCase(),
                      style: poppins(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: isCancelled ? Colors.redAccent : const Color(0xFF4DA6FF),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.access_time_rounded,
                    size: 14,
                    color: isCancelled ? Colors.redAccent.withValues(alpha: 0.7) : Colors.white70,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$start - $end',
                    style: poppins(
                      fontSize: 12,
                      color: isCancelled ? Colors.redAccent.withValues(alpha: 0.9) : Colors.white,
                      fontWeight: FontWeight.bold,
                    ).copyWith(
                      decoration: isCancelled ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Icon(
                    Icons.location_on_rounded,
                    size: 14,
                    color: isCancelled ? Colors.redAccent.withValues(alpha: 0.7) : Colors.white70,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      venue,
                      style: poppins(
                        fontSize: 12,
                        color: isCancelled ? Colors.redAccent.withValues(alpha: 0.9) : Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (agenda.isNotEmpty) ...[
                const SizedBox(height: 10),
                Divider(color: isCancelled ? Colors.redAccent.withValues(alpha: 0.2) : Colors.white10),
                const SizedBox(height: 6),
                Text(
                  'Agenda / Discussion Points:',
                  style: poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isCancelled ? Colors.redAccent.withValues(alpha: 0.7) : Colors.white70,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  agenda,
                  style: poppins(
                    fontSize: 12,
                    color: isCancelled ? Colors.white70 : Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildAttendanceHistoryList(TextStyle Function({double? fontSize, FontWeight? fontWeight, Color? color}) poppins) {
    final List<dynamic> records = _attendanceData['all_records'] ?? _attendanceData['absent_records'] ?? [];

    if (records.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Column(
          children: [
            const Icon(Icons.history_rounded, color: Colors.white38, size: 48),
            const SizedBox(height: 12),
            Text(
              'No Attendance History',
              style: poppins(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white70),
            ),
            const SizedBox(height: 4),
            Text(
              'No meetings attendance logs recorded yet.',
              textAlign: TextAlign.center,
              style: poppins(fontSize: 12, color: Colors.white30),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: records.length,
      itemBuilder: (context, index) {
        final rec = records[index];
        final meetingStr = rec['date'] ?? '';
        final status = (rec['status'] as String? ?? 'Absent').toLowerCase();
        final reason = rec['reason'] ?? '';
        final bool isPresent = status == 'present';

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isPresent
                ? const Color(0xFF00E676).withValues(alpha: 0.03)
                : Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isPresent
                  ? const Color(0xFF00E676).withValues(alpha: 0.15)
                  : Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      meetingStr,
                      style: poppins(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.9)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isPresent
                          ? const Color(0xFF00E676).withValues(alpha: 0.15)
                          : Colors.redAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isPresent
                            ? const Color(0xFF00E676).withValues(alpha: 0.25)
                            : Colors.redAccent.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Text(
                      isPresent ? 'PRESENT' : 'ABSENT',
                      style: poppins(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: isPresent ? const Color(0xFF00E676) : Colors.redAccent,
                      ),
                    ),
                  ),
                ],
              ),
              if (!isPresent && reason.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                  ),
                  child: Text(
                    'Reason: $reason',
                    style: poppins(fontSize: 12, color: const Color(0xFFC9D1E6)).copyWith(fontStyle: FontStyle.italic),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
