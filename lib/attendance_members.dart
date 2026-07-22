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
          if (data.containsKey('overall')) {
            _attendanceData = data;
          } else {
            // Backward-compatibility wrapper
            _attendanceData = {
              'success': true,
              'teams': {
                team: data
              },
              'overall': data
            };
          }
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
    // Build team display label — show all teams joined with " · "
    final rawTeam = widget.userData?.team ?? 'SEDS Member';
    final teamName = rawTeam.split(',').map((t) => t.trim()).join(' · ');

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
                  // ── Chart & Percentage Cards ──
                  if (_attendanceData['teams'] != null &&
                      (_attendanceData['teams'] as Map).length > 1) ...[
                    _buildChartCard(
                      poppins,
                      'Overall Attendance Rate',
                      _attendanceData['overall'] ?? {},
                    ),
                    const SizedBox(height: 16),
                    ...(_attendanceData['teams'] as Map<String, dynamic>)
                        .entries
                        .where((entry) => entry.key.toLowerCase().trim() != 'leads')
                        .map((entry) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: _buildChartCard(
                          poppins,
                          '${entry.key} Team Attendance',
                          entry.value,
                        ),
                      );
                    }),
                  ] else ...[
                    _buildChartCard(
                      poppins,
                      'Attendance Rate',
                      _attendanceData['overall'] ?? _attendanceData,
                    ),
                    const SizedBox(height: 20),
                  ],

                  // ── Stats Row ──
                  _buildStatsRow(poppins),
                  if (_attendanceData['teams'] != null &&
                      (_attendanceData['teams'] as Map).length > 1) ...[
                    const SizedBox(height: 16),
                    _buildTeamStatsBreakdownCard(poppins),
                  ],
                  const SizedBox(height: 24),

                  // ── Upcoming Meetings Section ──
                  Text(
                    'Scheduled Meetings',
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
    // Split raw team into individual team labels for chips
    final teams = teamName.split('·').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
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
          Expanded(
            child: Column(
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
                const SizedBox(height: 6),
                // Team chips — one per team
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Member',
                        style: poppins(fontSize: 11, color: Colors.white54),
                      ),
                    ),
                    ...teams.map((t) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4DA6FF).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF4DA6FF).withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        t,
                        style: poppins(
                          fontSize: 11,
                          color: const Color(0xFF4DA6FF),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )),
                  ],
                ),
              ],
            ),
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


  Widget _buildChartCard(
    TextStyle Function({double? fontSize, FontWeight? fontWeight, Color? color}) poppins,
    String title,
    Map<String, dynamic> data,
  ) {
    final double percentage = (data['percentage'] as num?)?.toDouble() ?? 100.0;
    final int total = (data['total_meetings'] as num?)?.toInt() ?? 0;
    final int present = (data['present_count'] as num?)?.toInt() ?? 0;
    final int absent = (data['absent_count'] as num?)?.toInt() ?? 0;
    final int onDuty = (data['on_duty_count'] as num?)?.toInt() ?? 0;

    // Gradient bar widths
    final double fillFactor = total > 0 ? (percentage / 100.0) : 1.0;
    final double presentRatio = total > 0 ? present / total : 0.0;
    final double absentRatio = total > 0 ? absent / total : 0.0;

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
                title,
                style: poppins(fontSize: 14, color: Colors.white70, fontWeight: FontWeight.w600),
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
                  Container(
                    height: 14,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(7),
                    ),
                  ),
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
              Text('0%', style: poppins(fontSize: 11, color: Colors.white30)),
              if (percentage < 75 && total > 0)
                Text('Needs Improvement (Aim for 75%+)',
                    style: poppins(fontSize: 10, color: Colors.orangeAccent, fontWeight: FontWeight.w500))
              else
                Text('Good Standing',
                    style: poppins(fontSize: 10, color: const Color(0xFF00E676), fontWeight: FontWeight.w500)),
              Text('100%', style: poppins(fontSize: 11, color: Colors.white30)),
            ],
          ),

          // ── Per-team present / absent breakdown bars ──
          const SizedBox(height: 16),
          Divider(color: Colors.white.withValues(alpha: 0.07)),
          const SizedBox(height: 10),

          // Present bar
          _buildMiniBar(
            poppins,
            label: 'Attended',
            count: present,
            total: total,
            ratio: presentRatio,
            color: const Color(0xFF00E676),
          ),
          const SizedBox(height: 8),

          // Absent bar
          _buildMiniBar(
            poppins,
            label: 'Absent',
            count: absent,
            total: total,
            ratio: absentRatio,
            color: Colors.redAccent,
          ),

          if (onDuty > 0) ...[
            const SizedBox(height: 8),
            // On Duty bar
            _buildMiniBar(
              poppins,
              label: 'On Duty',
              count: onDuty,
              total: total + onDuty,
              ratio: (total + onDuty) > 0 ? onDuty / (total + onDuty) : 0.0,
              color: const Color(0xFF4DA6FF),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMiniBar(
    TextStyle Function({double? fontSize, FontWeight? fontWeight, Color? color}) poppins, {
    required String label,
    required int count,
    required int total,
    required double ratio,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: poppins(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.bold),
            ),
            Text(
              '$count / $total',
              style: poppins(fontSize: 11, color: color, fontWeight: FontWeight.w900),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: ratio.clamp(0.0, 1.0),
            minHeight: 8,
            backgroundColor: Colors.white.withValues(alpha: 0.07),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }

  Widget _buildStatsRow(TextStyle Function({double? fontSize, FontWeight? fontWeight, Color? color}) poppins) {
    final Map<String, dynamic> overall = _attendanceData['overall'] ?? _attendanceData;
    final int total = (overall['total_meetings'] as num?)?.toInt() ?? 0;
    final int present = (overall['present_count'] as num?)?.toInt() ?? 0;
    final int absent = (overall['absent_count'] as num?)?.toInt() ?? 0;
    final int onDuty = (overall['on_duty_count'] as num?)?.toInt() ?? 0;

    return Row(
      children: [
        Expanded(child: _buildStatItem(poppins, 'Total', '${total + onDuty}', Colors.white)),
        const SizedBox(width: 8),
        Expanded(child: _buildStatItem(poppins, 'Attended', '$present', const Color(0xFF00E676))),
        const SizedBox(width: 8),
        Expanded(child: _buildStatItem(poppins, 'Absent', '$absent', Colors.redAccent)),
        if (onDuty > 0) ...[
          const SizedBox(width: 8),
          Expanded(child: _buildStatItem(poppins, 'On Duty', '$onDuty', const Color(0xFF4DA6FF))),
        ],
      ],
    );
  }

  Widget _buildTeamStatsBreakdownCard(TextStyle Function({double? fontSize, FontWeight? fontWeight, Color? color}) poppins) {
    final teamsData = _attendanceData['teams'] as Map<String, dynamic>;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Team Attendance Breakdown',
            style: poppins(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white70),
          ),
          const SizedBox(height: 14),
          ...teamsData.entries
              .where((entry) => entry.key.toLowerCase().trim() != 'leads')
              .map((entry) {
            final tName = entry.key;
            final tData = entry.value;
            final int present = (tData['present_count'] as num?)?.toInt() ?? 0;
            final int absent = (tData['absent_count'] as num?)?.toInt() ?? 0;
            final int onDuty = (tData['on_duty_count'] as num?)?.toInt() ?? 0;
            final double pct = (tData['percentage'] as num?)?.toDouble() ?? 0.0;

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.02),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '$tName Team',
                        style: poppins(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF4DA6FF)),
                      ),
                      Text(
                        '$pct%',
                        style: poppins(
                          fontSize: 13, 
                          fontWeight: FontWeight.bold, 
                          color: pct >= 75 ? const Color(0xFF00E676) : Colors.orangeAccent
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _smallStatBadge(poppins, 'Attended: $present', const Color(0xFF00E676)),
                      const SizedBox(width: 6),
                      _smallStatBadge(poppins, 'Absent: $absent', Colors.redAccent),
                      if (onDuty > 0) ...[
                        const SizedBox(width: 6),
                        _smallStatBadge(poppins, 'On Duty: $onDuty', const Color(0xFF4DA6FF)),
                      ],
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _smallStatBadge(
    TextStyle Function({double? fontSize, FontWeight? fontWeight, Color? color}) poppins,
    String text,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        text,
        style: poppins(fontSize: 10, fontWeight: FontWeight.bold, color: color),
      ),
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

  DateTime? _parseMeetingDateTime(String dateStr, String timeStr) {
    try {
      final dateParts = dateStr.trim().split('/');
      if (dateParts.length != 3) return null;
      final month = int.parse(dateParts[0]);
      final day = int.parse(dateParts[1]);
      final year = int.parse(dateParts[2]);

      final timeParts = timeStr.trim().split(' ');
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
      debugPrint('Error parsing date time: $e');
    }
    return null;
  }

  Widget _buildUpcomingMeetingsSection(TextStyle Function({double? fontSize, FontWeight? fontWeight, Color? color}) poppins) {
    final now = DateTime.now();
    
    final List<dynamic> upcomingOnly = _upcomingMeetings.where((meeting) {
      final dateStr = meeting['meeting_date'] ?? '';
      final endTimeStr = meeting['end_time'] ?? '';
      final meetingStatus = (meeting['status'] as String? ?? '').toUpperCase();
      
      if (meetingStatus == 'SUBMITTED' || meetingStatus == 'COMPLETED') return false;
      
      final endDateTime = _parseMeetingDateTime(dateStr, endTimeStr);
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
            'No scheduled meetings.',
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
        final agenda = meeting['agenda'] ?? '';
        final status = meeting['status'] ?? 'SCHEDULED';
        final bool isCancelled = status == 'CANCELLED';

        // Compute meeting start and end datetimes to show ONGOING / UPCOMING status
        final startDateTime = _parseMeetingDateTime(date, start);
        final endDateTime = _parseMeetingDateTime(date, end);

        String badgeText = 'UPCOMING';
        Color badgeColor = const Color(0xFF4DA6FF);

        if (isCancelled) {
          badgeText = 'CANCELLED';
          badgeColor = Colors.redAccent;
        } else if (startDateTime != null && endDateTime != null) {
          if (now.isAfter(startDateTime) && now.isBefore(endDateTime)) {
            badgeText = 'ONGOING';
            badgeColor = const Color(0xFF00E676);
          }
        }

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
                      color: badgeColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: badgeColor.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Text(
                      badgeText,
                      style: poppins(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: badgeColor,
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
        final bool isOnDuty = status == 'on_duty';
        final bool isOnDutyPending = status == 'on_duty_pending';
        final teamLabel = rec['team'] != null ? ' · ${rec['team']}' : '';

        // Color theme per status
        final Color statusColor = isPresent
            ? const Color(0xFF00E676)
            : isOnDuty
            ? const Color(0xFF4DA6FF)
            : isOnDutyPending
            ? const Color(0xFFFFD93D)
            : Colors.redAccent;
        final String statusLabel = isPresent
            ? 'PRESENT'
            : isOnDuty
            ? 'ON DUTY'
            : isOnDutyPending
            ? 'ON DUTY⏳'
            : 'ABSENT';

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isPresent
                ? const Color(0xFF00E676).withValues(alpha: 0.03)
                : isOnDuty
                ? const Color(0xFF4DA6FF).withValues(alpha: 0.03)
                : isOnDutyPending
                ? const Color(0xFFFFD93D).withValues(alpha: 0.03)
                : Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: statusColor.withValues(alpha: 0.18),
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
                      '$meetingStr$teamLabel',
                      style: poppins(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.9)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: statusColor.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Text(
                      statusLabel,
                      style: poppins(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
              if (!isPresent && !isOnDuty && !isOnDutyPending && reason.isNotEmpty) ...[
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
