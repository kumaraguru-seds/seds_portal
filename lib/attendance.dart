// ignore_for_file: deprecated_member_use
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'main.dart';
import 'app_toast.dart';

class AttendanceTab extends StatefulWidget {
  final UserData? userData;
  const AttendanceTab({super.key, this.userData});

  @override
  State<AttendanceTab> createState() => _AttendanceTabState();
}

class _AttendanceTabState extends State<AttendanceTab> {
  bool _isLoading = false;
  List<dynamic> _members = [];
  String? _errorMessage;
  String _selectedTeam = '';
  Map<String, dynamic> _personalAttendance = {};
  bool _loadingPersonalAttendance = false;

  // Selected date / meeting display option
  String _selectedDate = '';
  final List<String> _dateOptions = [];
  List<Map<String, dynamic>> _meetingsList = [];
  bool _isAttendanceSubmittedForSelectedDate = false;
  List<dynamic> _submittedAttendanceRecords = [];

  // Attendance status mapping (rollNumber -> 'Present' or 'Absent')
  final Map<String, String> _attendanceStatus = {};

  // Absence reasons text controllers (rollNumber -> Controller)
  final Map<String, TextEditingController> _reasonControllers = {};

  List<dynamic> _teamLeaves = [];
  List<String> _myTeams = [];

  @override
  void initState() {
    super.initState();
    final bool isAdmin = widget.userData?.role == 'Admin' || widget.userData?.role == 'SuperAdmin';
    if (isAdmin) {
      _loadAdminTeams();
    } else {
      final teams = widget.userData?.teams ?? [];
      if (teams.isNotEmpty) {
        _myTeams = teams;
      } else {
        _myTeams = (widget.userData?.team ?? '')
            .split(',')
            .map((t) => t.trim())
            .where((t) => t.isNotEmpty)
            .toList();
      }
      if (_myTeams.isNotEmpty) {
        _selectedTeam = _myTeams.first;
      } else {
        _selectedTeam = widget.userData?.team ?? '';
      }
      _fetchData();
    }
  }

  Future<void> _loadAdminTeams() async {
    try {
      final fetched = await fetchUniqueTeams();
      if (fetched.isNotEmpty && mounted) {
        setState(() {
          _myTeams = fetched;
          _selectedTeam = _myTeams.first;
        });
        _fetchData();
      }
    } catch (e) {
      debugPrint('Error loading admin teams: $e');
    }
  }

  Future<void> _fetchData() async {
    await _fetchTeamMembers();
    await _fetchTeamLeaves();
    await _fetchMeetings();
    await _fetchPersonalAttendance();
  }

  Future<void> _fetchPersonalAttendance() async {
    final role = widget.userData?.role;
    final bool isAdmin = role == 'Admin' || role == 'SuperAdmin';
    if (isAdmin) return; // Admins don't have personal team attendance to track

    final roll = widget.userData?.rollNumber;
    final team = widget.userData?.team;
    if (roll == null || team == null || roll.isEmpty || team.isEmpty) return;

    if (mounted) setState(() => _loadingPersonalAttendance = true);
    try {
      final response = await http.get(
        Uri.parse('$apiBaseUrl/api/attendance/member?roll_number=${Uri.encodeComponent(roll)}&team=${Uri.encodeComponent(team)}'),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _personalAttendance = data;
            _loadingPersonalAttendance = false;
          });
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loadingPersonalAttendance = false);
    }
  }

  Future<void> _fetchTeamLeaves() async {
    final team = _selectedTeam;
    if (team.isEmpty) return;
    try {
      final response = await http.get(
        Uri.parse('$apiBaseUrl/api/leave/team-leaves?team=${Uri.encodeComponent(team)}'),
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        setState(() {
          _teamLeaves = data['leaves'] ?? [];
        });
      }
    } catch (e) {
      debugPrint('Error fetching team leaves: $e');
    }
  }

  String? _getMemberLeaveStatusOnDate(String rollNumber, String meetingDateStr) {
    if (meetingDateStr.isEmpty) return null;
    try {
      // meetingDateStr can be MM/DD/YYYY or YYYY-MM-DD
      DateTime meetingDate;
      if (meetingDateStr.contains('/')) {
        final parts = meetingDateStr.split('/');
        if (parts.length == 3) {
          meetingDate = DateTime(
            int.parse(parts[2].trim()),
            int.parse(parts[0].trim()),
            int.parse(parts[1].trim()),
          );
        } else {
          return null;
        }
      } else {
        meetingDate = DateTime.parse(meetingDateStr.substring(0, 10));
      }

      // Strip time for clean date-only check
      meetingDate = DateTime(meetingDate.year, meetingDate.month, meetingDate.day);

      for (var leave in _teamLeaves) {
        final leaveRoll = leave['roll_number'] ?? '';
        if (leaveRoll.toString().toLowerCase() != rollNumber.toLowerCase()) continue;
        
        final fromStr = leave['date_from'] ?? '';
        final toStr = leave['date_to'] ?? '';
        if (fromStr.isEmpty || toStr.isEmpty) continue;
        
        DateTime fromDate = DateTime.parse(fromStr.substring(0, 10));
        DateTime toDate = DateTime.parse(toStr.substring(0, 10));
        
        fromDate = DateTime(fromDate.year, fromDate.month, fromDate.day);
        toDate = DateTime(toDate.year, toDate.month, toDate.day);
        
        if (meetingDate.isAtSameMomentAs(fromDate) ||
            meetingDate.isAtSameMomentAs(toDate) ||
            (meetingDate.isAfter(fromDate) && meetingDate.isBefore(toDate))) {
          return leave['status'] ?? 'pending';
        }
      }
    } catch (e) {
      debugPrint('Error checking leave status on date: $e');
    }
    return null;
  }

  @override
  void dispose() {
    for (var controller in _reasonControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _fetchTeamMembers() async {
    final team = _selectedTeam;
    final role = widget.userData?.role;
    final bool isAdmin = role == 'Admin' || role == 'SuperAdmin';
    final bool isLead = role == 'Lead' || isAdmin;

    // Attendance is only for Leads and Admins managing a team
    if (!isLead || team.isEmpty) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await http.get(
        Uri.parse('$apiBaseUrl/api/members?team=${Uri.encodeComponent(team)}&include_leads=true'),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          _members = data;
          for (var member in _members) {
            final roll = member['roll_number'] ?? '';
            _attendanceStatus[roll] = 'Present'; // Default to Present
            _reasonControllers[roll] = TextEditingController();
          }
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = 'Failed to load team members.';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Network connection error: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchMeetings() async {
    final team = _selectedTeam;
    if (team.isEmpty) return;

    try {
      final response = await http.get(
        Uri.parse('$apiBaseUrl/api/meetings?team_name=${Uri.encodeComponent(team)}'),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          _meetingsList = List<Map<String, dynamic>>.from(data);
          
          _dateOptions.clear();
          for (var meeting in _meetingsList) {
            final dateStr = meeting['meeting_date'] ?? '';
            final start = meeting['start_time'] ?? '';
            final end = meeting['end_time'] ?? '';
            final venue = meeting['venue'] ?? '';
            final mode = meeting['meeting_mode'] ?? '';
            
            final status = meeting['status'] ?? 'SCHEDULED';
            
            var displayOption = "$dateStr ($start - $end) at $venue [$mode]";
            if (status == 'CANCELLED') {
              displayOption += " [CANCELLED]";
            } else if (status == 'EXPIRED') {
              displayOption += " [EXPIRED]";
            }
            _dateOptions.add(displayOption);
          }

          if (_dateOptions.isNotEmpty) {
            _selectedDate = _dateOptions.first;
          } else {
            _selectedDate = '';
          }
        });
        _checkAttendanceSubmissionStatus();
      }
    } catch (e) {
      debugPrint('Error fetching meetings: $e');
    }
  }

  void _resetAttendanceStates() {
    final meeting = _getSelectedMeeting();
    final dateStr = meeting?['meeting_date'] ?? '';
    setState(() {
      for (var member in _members) {
        final roll = member['roll_number'] ?? '';
        final leaveStatus = _getMemberLeaveStatusOnDate(roll, dateStr);
        if (leaveStatus == 'approved') {
          _attendanceStatus[roll] = 'On Duty';
        } else if (leaveStatus == 'pending') {
          _attendanceStatus[roll] = 'On Duty (Pending)';
        } else {
          _attendanceStatus[roll] = 'Present';
        }
        _reasonControllers[roll]?.clear();
      }
    });
  }

  Map<String, dynamic>? _getSelectedMeeting() {
    if (_selectedDate.isEmpty || _meetingsList.isEmpty) return null;
    final index = _dateOptions.indexOf(_selectedDate);
    if (index >= 0 && index < _meetingsList.length) {
      return _meetingsList[index];
    }
    return null;
  }

  Future<void> _cancelMeeting() async {
    final meeting = _getSelectedMeeting();
    if (meeting == null) return;
    final meetingId = meeting['id'];

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0F1E36),
          title: Text(
            'Cancel Meeting',
            style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Text(
            'Are you sure you want to cancel this scheduled meeting? This action cannot be undone.',
            style: GoogleFonts.poppins(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('No', style: GoogleFonts.poppins(color: Colors.white38)),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text('Yes, Cancel', style: GoogleFonts.poppins(color: Colors.redAccent, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await http.post(
        Uri.parse('$apiBaseUrl/api/meetings/cancel'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'id': meetingId}),
      ).timeout(const Duration(seconds: 15));

      if (!mounted) return;
      if (response.statusCode == 200) {
        trackUserAction('Cancelled meeting: $_selectedDate');
        AppToast.success(context, 'Meeting cancelled successfully.');
        await _fetchMeetings();
      } else {
        AppToast.error(context, 'Failed to cancel meeting.');
      }
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, 'Error: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _checkAttendanceSubmissionStatus() async {
    final team = _selectedTeam;
    if (team.isEmpty || _selectedDate.isEmpty) return;

    try {
      final response = await http.get(
        Uri.parse('$apiBaseUrl/api/attendance?team=${Uri.encodeComponent(team)}&date=${Uri.encodeComponent(_selectedDate)}'),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        setState(() {
          _isAttendanceSubmittedForSelectedDate = data['submitted'] ?? false;
          _submittedAttendanceRecords = data['records'] ?? [];
        });
        if (!_isAttendanceSubmittedForSelectedDate) {
          _resetAttendanceStates();
        }
      } else {
        setState(() {
          _isAttendanceSubmittedForSelectedDate = false;
          _submittedAttendanceRecords = [];
        });
        _resetAttendanceStates();
      }
    } catch (e) {
      debugPrint('Error checking attendance status: $e');
    }
  }



  Future<void> _submitAttendance() async {
    final team = _selectedTeam;
    if (team.isEmpty || _members.isEmpty) return;

    if (_selectedDate.isEmpty) {
      _showErrorSnackBar('Please select a scheduled meeting session first.');
      return;
    }

    final poppins = GoogleFonts.poppins;
    showDialog(
      context: context,
      builder: (BuildContext confirmContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0D1E3A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF4DA6FF), width: 1.5),
          ),
          title: Text(
            'Confirm Submission',
            style: poppins(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Text(
            'Are you sure you want to submit the attendance for this meeting session?',
            style: poppins(color: const Color(0xFFC9D1E6)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(confirmContext),
              child: Text('Cancel', style: poppins(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(confirmContext);
                await _executeSubmitAttendance();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4DA6FF),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text('Submit', style: poppins(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _executeSubmitAttendance() async {
    final team = _selectedTeam;
    if (team.isEmpty || _members.isEmpty) return;

    setState(() => _isLoading = true);

    final List<Map<String, dynamic>> records = _members.map((member) {
      final roll = member['roll_number'] ?? '';
      final status = _attendanceStatus[roll] ?? 'Present';
      final reason = status == 'Absent' ? _reasonControllers[roll]?.text.trim() : '';

      return {
        'name': member['name'],
        'roll_number': roll,
        'status': status,
        'reason': reason,
      };
    }).toList();

    try {
      final response = await http.post(
        Uri.parse('$apiBaseUrl/api/attendance'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'team': team,
          'date': _selectedDate,
          'records': records,
        }),
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (response.statusCode == 200 && data['success'] == true) {
        trackUserAction('Submitted attendance for $team on $_selectedDate');
        AppToast.success(context, 'Attendance submitted successfully for $team!');
        _checkAttendanceSubmissionStatus();
      } else {
        _showErrorSnackBar(data['message'] ?? 'Failed to submit attendance.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showErrorSnackBar('Network error: Could not submit attendance.');
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    AppToast.error(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final poppins = GoogleFonts.poppins;
    final bool isAdmin = widget.userData?.role == 'Admin' || widget.userData?.role == 'SuperAdmin';
    final bool isLead = widget.userData?.role == 'Lead' || isAdmin;
    final teamName = _selectedTeam;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _fetchData,
          color: const Color(0xFF4DA6FF),
          backgroundColor: const Color(0xFF1A2B4A),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header Card ──
                _buildHeaderCard(poppins, isLead, teamName),
                const SizedBox(height: 16),

                if (_personalAttendance.isNotEmpty) ...[
                  _buildPersonalAttendanceCard(poppins),
                  const SizedBox(height: 16),
                ],

                // ── Main Body Content ──
                _buildMainBody(poppins, isLead),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPersonalAttendanceCard(TextStyle Function({double? fontSize, FontWeight? fontWeight, Color? color}) poppins) {
    if (_loadingPersonalAttendance && _personalAttendance.isEmpty) {
      return Container(
        height: 80,
        alignment: Alignment.center,
        child: const CircularProgressIndicator(color: Color(0xFF4DA6FF)),
      );
    }

    final overall = _personalAttendance['overall'] ?? _personalAttendance;
    final double percentage = (overall['percentage'] as num?)?.toDouble() ?? 100.0;
    final int present = (overall['present_count'] as num?)?.toInt() ?? 0;
    final int total = (overall['total_meetings'] as num?)?.toInt() ?? 0;
    final int absent = (overall['absent_count'] as num?)?.toInt() ?? 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF4DA6FF).withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'My Personal Attendance',
                style: poppins(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white70),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (percentage >= 75 ? Colors.greenAccent : Colors.redAccent).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${percentage.toStringAsFixed(1)}%',
                  style: poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: percentage >= 75 ? Colors.greenAccent : Colors.redAccent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatsTile(poppins, 'Present', '$present', Colors.greenAccent),
              _buildStatsTile(poppins, 'Absent', '$absent', Colors.redAccent),
              _buildStatsTile(poppins, 'Total Meetings', '$total', const Color(0xFF4DA6FF)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatsTile(
    TextStyle Function({double? fontSize, FontWeight? fontWeight, Color? color}) poppins,
    String label,
    String value,
    Color color,
  ) {
    return Column(
      children: [
        Text(
          value,
          style: poppins(fontSize: 18, fontWeight: FontWeight.bold, color: color),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: poppins(fontSize: 11, color: Colors.white38),
        ),
      ],
    );
  }

  Widget _buildHeaderCard(TextStyle Function({double? fontSize, FontWeight? fontWeight, Color? color}) poppins, bool isLead, String teamName) {
    final bool isAdmin = widget.userData?.role == 'Admin' || widget.userData?.role == 'SuperAdmin';
    final bool hasMultipleTeams = _myTeams.length > 1;

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
                  'Mark Attendance',
                  style: poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                if ((isLead || isAdmin) && hasMultipleTeams) ...[
                  DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedTeam,
                      dropdownColor: const Color(0xFF162544),
                      icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF4DA6FF)),
                      isDense: true,
                      style: poppins(
                        fontSize: 14,
                        color: const Color(0xFF4DA6FF),
                        fontWeight: FontWeight.bold,
                      ),
                      items: _myTeams.map((String val) {
                        return DropdownMenuItem<String>(
                          value: val,
                          child: Text('$val Team'),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _selectedTeam = val;
                          });
                          _fetchData();
                        }
                      },
                    ),
                  ),
                ] else if ((isLead || isAdmin) && teamName.isNotEmpty) ...[
                  Text(
                    '$teamName Team',
                    style: poppins(
                      fontSize: 13,
                      color: const Color(0xFF4DA6FF),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Row(
            children: [
              Icon(Icons.calendar_month_rounded, color: const Color(0xFF4DA6FF).withValues(alpha: 0.8), size: 32),
              const SizedBox(width: 8),
              AppNotificationBell(userData: widget.userData),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExpiredMeetingView(TextStyle Function({double? fontSize, FontWeight? fontWeight, Color? color}) poppins) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 24),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFFF5252).withValues(alpha: 0.25)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.timer_off_rounded, color: Color(0xFFFF5252), size: 56),
            const SizedBox(height: 16),
            Text(
              'Meeting Expired',
              style: poppins(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              'The scheduled date and time for this meeting have passed. Attendance can no longer be marked or submitted.',
              textAlign: TextAlign.center,
              style: poppins(fontSize: 13, color: const Color(0xFFC9D1E6)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainBody(TextStyle Function({double? fontSize, FontWeight? fontWeight, Color? color}) poppins, bool isLead) {
    if (!isLead) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_person_rounded, color: Colors.amberAccent, size: 56),
              const SizedBox(height: 16),
              Text(
                'Access Restricted',
                style: poppins(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 8),
              Text(
                'Attendance marking is only available for SEDS Team Leads.',
                textAlign: TextAlign.center,
                style: poppins(fontSize: 13, color: const Color(0xFFC9D1E6)),
              ),
            ],
          ),
        ),
      );
    }

    if (_isLoading && _members.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF4DA6FF)));
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off_rounded, color: Colors.redAccent, size: 48),
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: poppins(color: const Color(0xFFC9D1E6), fontSize: 14),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _fetchTeamMembers,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            )
          ],
        ),
      );
    }

    if (_members.isEmpty) {
      return Center(
        child: Text(
          'No members found for this team.',
          style: poppins(color: const Color(0xFFC9D1E6), fontSize: 14),
        ),
      );
    }

    return Column(
      children: [
        _buildMeetingManagementCard(poppins, widget.userData?.team ?? 'Media'),
        const SizedBox(height: 16),
        
        // ── Full-Width Meeting selector ──
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedDate.isNotEmpty && _dateOptions.contains(_selectedDate) ? _selectedDate : null,
              hint: Text(
                'Select Scheduled Meeting Session...',
                style: poppins(color: Colors.white38, fontSize: 13),
              ),
              dropdownColor: const Color(0xFF0F1E36),
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF4DA6FF)),
              style: poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF4DA6FF),
              ),
              onChanged: (String? newValue) {
                if (newValue != null) {
                  setState(() {
                    _selectedDate = newValue;
                  });
                  _checkAttendanceSubmissionStatus();
                }
              },
              items: _dateOptions.map<DropdownMenuItem<String>>((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value, overflow: TextOverflow.ellipsis),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 16),

        if (_selectedDate.isNotEmpty && _getSelectedMeeting()?['status'] == 'CANCELLED') ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.cancel_rounded, color: Colors.redAccent, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'This scheduled meeting has been CANCELLED.',
                    style: poppins(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ] else ...[
          if (_selectedDate.isNotEmpty && !_isAttendanceSubmittedForSelectedDate) ...[
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _cancelMeeting,
                icon: const Icon(Icons.cancel_presentation_rounded, color: Colors.redAccent, size: 18),
                label: Text(
                  'Cancel This Meeting',
                  style: poppins(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ],

        // ── Grid of Members or Submitted View ──
        if (_dateOptions.isEmpty)
          Center(
            child: Container(
              padding: const EdgeInsets.all(24),
              margin: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.event_busy_rounded, color: Colors.orangeAccent, size: 56),
                  const SizedBox(height: 16),
                  Text(
                    'No Meetings Scheduled',
                    style: poppins(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'You must schedule a meeting using the panel above before marking attendance for your team.',
                    textAlign: TextAlign.center,
                    style: poppins(fontSize: 13, color: const Color(0xFFC9D1E6)),
                  ),
                ],
              ),
            ),
          )
        else if (_selectedDate.isNotEmpty && _getSelectedMeeting()?['status'] == 'CANCELLED')
          const SizedBox.shrink()
        else if (_selectedDate.isNotEmpty && _getSelectedMeeting()?['status'] == 'EXPIRED')
          _buildExpiredMeetingView(poppins)
        else if (_isAttendanceSubmittedForSelectedDate)
          _buildSubmittedView(poppins)
        else ...[
          Builder(builder: (context) {
            double textScale = MediaQuery.textScalerOf(context).scale(1.0);
            if (textScale < 1.0) textScale = 1.0;
            final double adjustedRatio = (0.86 / textScale).clamp(0.6, 0.86);

            final leads = _members.where((m) => (m['role'] ?? '').toString().toLowerCase() == 'lead').toList();
            final members = _members.where((m) => (m['role'] ?? '').toString().toLowerCase() != 'lead').toList();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (leads.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12.0, top: 4.0),
                    child: Text(
                      'Team Leads',
                      style: poppins(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF4DA6FF)),
                    ),
                  ),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: adjustedRatio,
                    ),
                    itemCount: leads.length,
                    itemBuilder: (context, index) {
                      final member = leads[index];
                      return _buildMemberCard(poppins, member);
                    },
                  ),
                  const SizedBox(height: 24),
                ],
                if (members.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12.0, top: 4.0),
                    child: Text(
                      'Team Members',
                      style: poppins(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white70),
                    ),
                  ),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: adjustedRatio,
                    ),
                    itemCount: members.length,
                    itemBuilder: (context, index) {
                      final member = members[index];
                      return _buildMemberCard(poppins, member);
                    },
                  ),
                ],
              ],
            );
          }),
          const SizedBox(height: 16),

          // ── Submit Button ──
          SizedBox(
            width: double.infinity,
            height: 54,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  colors: [Color(0xFF00E676), Color(0xFF00B0FF)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00E676).withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: (_isLoading || _dateOptions.isEmpty) ? null : _submitAttendance,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                      )
                    : Text(
                        'Submit Attendance',
                        style: poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMemberCard(TextStyle Function({double? fontSize, FontWeight? fontWeight, Color? color}) poppins, dynamic member) {
    final String name = member['name'] ?? 'SEDS Member';
    final String roll = member['roll_number'] ?? 'N/A';
    final String imgUrl = member['image_url'] ?? 'https://kumaraguruseds.space/mani.jpeg';
    final String status = _attendanceStatus[roll] ?? 'Present';

    final bool isPresent = status == 'Present';
    final bool isOnDuty = status == 'On Duty';
    final bool isOnDutyPending = status == 'On Duty (Pending)';
    final bool isAbsent = status == 'Absent';

    final meeting = _getSelectedMeeting();
    final dateStr = meeting?['meeting_date'] ?? '';
    final leaveStatus = _getMemberLeaveStatusOnDate(roll, dateStr);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Stack(
        children: [
          // Left-side Indicator Stripe
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 4,
            child: Container(
              decoration: BoxDecoration(
                color: isPresent
                    ? const Color(0xFF00E676)
                    : isOnDuty
                    ? const Color(0xFF4DA6FF)
                    : isOnDutyPending
                    ? const Color(0xFFFFD93D)
                    : const Color(0xFFFF5252),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  bottomLeft: Radius.circular(20),
                ),
              ),
            ),
          ),

          // Main Card Content
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 16, 12, 12),
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                // Profile Image (Rounded square)
                Container(
                  width: 65,
                  height: 65,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: Image.network(
                      imgUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          color: Colors.white10,
                          child: const Icon(Icons.person_rounded, color: Colors.white54, size: 30),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 6),

                // Name
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),

                // Roll Number
                Text(
                  roll,
                  style: poppins(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
                
                // Leave Badge (if leave requested)
                if (leaveStatus != null) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: leaveStatus == 'approved'
                          ? const Color(0xFF4DA6FF).withValues(alpha: 0.15)
                          : const Color(0xFFFFD93D).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: leaveStatus == 'approved'
                            ? const Color(0xFF4DA6FF).withValues(alpha: 0.25)
                            : const Color(0xFFFFD93D).withValues(alpha: 0.25),
                      ),
                    ),
                    child: Text(
                      leaveStatus == 'approved' ? 'Leave: Approved' : 'Leave: Pending',
                      style: poppins(
                        fontSize: 9,
                        color: leaveStatus == 'approved' ? const Color(0xFF4DA6FF) : const Color(0xFFFFD93D),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 6),

                // Toggle Buttons: P, AB, or Static Leave Badge
                if (leaveStatus == 'approved' || leaveStatus == 'pending') ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: leaveStatus == 'approved'
                          ? const Color(0xFF4DA6FF).withValues(alpha: 0.15)
                          : const Color(0xFFFFD93D).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: leaveStatus == 'approved'
                            ? const Color(0xFF4DA6FF).withValues(alpha: 0.3)
                            : const Color(0xFFFFD93D).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      leaveStatus == 'approved' ? 'ON DUTY (APPROVED)' : 'ON DUTY (PENDING)',
                      style: poppins(
                        fontSize: 11,
                        color: leaveStatus == 'approved' ? const Color(0xFF4DA6FF) : const Color(0xFFFFD93D),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ] else ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // P (Present) Button
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _attendanceStatus[roll] = 'Present';
                            _reasonControllers[roll]?.clear();
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: isPresent
                                ? const Color(0xFF00E676)
                                : Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isPresent
                                  ? const Color(0xFF00E676)
                                  : Colors.white.withValues(alpha: 0.12),
                            ),
                          ),
                          child: Text(
                            'P',
                            style: poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: isPresent ? Colors.black : Colors.white70,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // AB (Absent) Button
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _attendanceStatus[roll] = 'Absent';
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: isAbsent
                                ? const Color(0xFFFF5252)
                                : Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isAbsent
                                  ? const Color(0xFFFF5252)
                                  : Colors.white.withValues(alpha: 0.12),
                            ),
                          ),
                          child: Text(
                            'AB',
                            style: poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: isAbsent ? Colors.white : Colors.white70,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],

                if (isAbsent) ...[
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 28,
                    child: TextField(
                      controller: _reasonControllers[roll],
                      style: poppins(fontSize: 10, color: Colors.white),
                      cursorColor: const Color(0xFF4DA6FF),
                      decoration: InputDecoration(
                        hintText: 'Enter reason...',
                        hintStyle: poppins(fontSize: 10, color: Colors.white38),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                        filled: true,
                        fillColor: Colors.black.withValues(alpha: 0.2),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: const BorderSide(color: Color(0xFF4DA6FF), width: 1),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

  Widget _buildMeetingManagementCard(
    TextStyle Function({double? fontSize, FontWeight? fontWeight, Color? color}) poppins,
    String teamName,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                'Meeting',
                style: poppins(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              Text(
                'Management',
                style: poppins(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ],
          ),
          Row(
            children: [
              OutlinedButton(
                onPressed: () => _quickScheduleMeeting(context),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF4DA6FF), width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                child: Text(
                  '⚡ Quick\nSchedule',
                  textAlign: TextAlign.center,
                  style: poppins(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF4DA6FF)),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () => _showNewMeetingDialog(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4DA6FF),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                child: Text(
                  'Schedule\nMeeting',
                  textAlign: TextAlign.center,
                  style: poppins(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _quickScheduleMeeting(BuildContext context) {
    final now = DateTime.now();
    final String teamName = _selectedTeam.isNotEmpty ? _selectedTeam : (widget.userData?.team ?? 'Media');
    final String dateStr = "${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}/${now.year}";
    final String startStr = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
    final end = now.add(const Duration(hours: 1));
    final String endStr = "${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}";

    final leadName = widget.userData?.name ?? 'Lead';
    final agendaStr = "Quick sync scheduled by $leadName";
    const venueStr = "SEDS Lab";

    showDialog(
      context: context,
      builder: (confirmContext) {
        final poppins = GoogleFonts.poppins;
        return AlertDialog(
          backgroundColor: const Color(0xFF0D1E3A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFF4DA6FF), width: 1.5),
          ),
          title: Text(
            '⚡ Quick Schedule Meeting',
            style: poppins(color: const Color(0xFF4DA6FF), fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Team: $teamName', style: poppins(color: Colors.white, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text('Date: $dateStr', style: poppins(color: Colors.white70)),
              const SizedBox(height: 4),
              Text('Time: $startStr to $endStr', style: poppins(color: Colors.white70)),
              const SizedBox(height: 4),
              Text('Venue: $venueStr', style: poppins(color: Colors.white70)),
              const SizedBox(height: 4),
              Text('Agenda: $agendaStr', style: poppins(color: Colors.white70)),
              const SizedBox(height: 12),
              Text(
                'This will schedule the meeting and send notifications to all team members, admin, and leads.',
                style: poppins(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(confirmContext),
              child: Text('Cancel', style: poppins(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(confirmContext); // Close confirm
                // Call backend API
                try {
                  final response = await http.post(
                    Uri.parse('$apiBaseUrl/api/meetings'),
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode({
                      'team_name': teamName,
                      'meeting_mode': 'OFFLINE',
                      'meeting_date': dateStr,
                      'start_time': startStr,
                      'end_time': endStr,
                      'venue': venueStr,
                      'agenda': agendaStr,
                    }),
                  ).timeout(const Duration(seconds: 15));

                  final data = jsonDecode(response.body);
                  if (response.statusCode == 200 && data['success'] == true) {
                    trackUserAction('Scheduled a quick meeting: $agendaStr on $dateStr');
                    _fetchMeetings();
                    if (context.mounted) AppToast.success(context, 'Quick meeting scheduled!');
                  } else {
                    _showErrorSnackBar(data['message'] ?? 'Failed to schedule meeting.');
                  }
                } catch (e) {
                  _showErrorSnackBar('Network error: Could not schedule meeting.');
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4DA6FF)),
              child: Text('Schedule', style: poppins(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _showNewMeetingDialog(BuildContext context) {
    final poppins = GoogleFonts.poppins;
    String selectedMeetingTeam = _selectedTeam.isNotEmpty ? _selectedTeam : (widget.userData?.team ?? 'Media');
    
    String meetingMode = 'OFFLINE';
    String selectedDate = '';
    String startTime = '';
    String endTime = '';
    
    final venueController = TextEditingController();
    final agendaController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Dialog(
              backgroundColor: const Color(0xFF0D1E3A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: const BorderSide(color: Color(0xFF4DA6FF), width: 1.5),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: SingleChildScrollView(
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title & Close Button Row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'New Meeting',
                              style: poppins(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF4DA6FF),
                              ),
                            ),
                            GestureDetector(
                              onTap: () => Navigator.pop(context),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.redAccent,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Divider(color: Colors.white12),
                        const SizedBox(height: 16),

                        // TEAM NAME
                        Text(
                          'TEAM NAME',
                          style: poppins(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white60),
                        ),
                        const SizedBox(height: 6),
                        _myTeams.length > 1
                            ? Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.white12),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: selectedMeetingTeam,
                                    isExpanded: true,
                                    dropdownColor: const Color(0xFF0D1E3A),
                                    icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF4DA6FF)),
                                    style: poppins(
                                      fontSize: 15,
                                      color: const Color(0xFF4DA6FF),
                                      fontWeight: FontWeight.bold,
                                    ),
                                    items: _myTeams.map((String val) {
                                      return DropdownMenuItem<String>(
                                        value: val,
                                        child: Text(val),
                                      );
                                    }).toList(),
                                    onChanged: (val) {
                                      if (val != null) {
                                        setModalState(() {
                                          selectedMeetingTeam = val;
                                        });
                                      }
                                    },
                                  ),
                                ),
                              )
                            : Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.white12),
                                ),
                                child: Text(
                                  selectedMeetingTeam,
                                  style: poppins(fontSize: 15, color: const Color(0xFF4DA6FF), fontWeight: FontWeight.bold),
                                ),
                              ),
                        const SizedBox(height: 16),

                        // MEETING MODE
                        Text(
                          'MEETING MODE',
                          style: poppins(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white60),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Radio<String>(
                              value: 'OFFLINE',
                              groupValue: meetingMode,
                              activeColor: const Color(0xFF4DA6FF),
                              onChanged: (val) {
                                if (val != null) setModalState(() => meetingMode = val);
                              },
                            ),
                            Text('OFFLINE', style: poppins(color: Colors.white, fontSize: 13)),
                            const SizedBox(width: 20),
                            Radio<String>(
                              value: 'ONLINE',
                              groupValue: meetingMode,
                              activeColor: const Color(0xFF4DA6FF),
                              onChanged: (val) {
                                if (val != null) setModalState(() => meetingMode = val);
                              },
                            ),
                            Text('ONLINE', style: poppins(color: Colors.white, fontSize: 13)),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // DATE
                        Text(
                          'DATE',
                          style: poppins(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white60),
                        ),
                        const SizedBox(height: 6),
                        GestureDetector(
                          onTap: () async {
                            final DateTime? picked = await showDatePicker(
                              context: context,
                              initialDate: DateTime.now(),
                              firstDate: DateTime(2025),
                              lastDate: DateTime(2030),
                              builder: (context, child) {
                                return Theme(
                                  data: Theme.of(context).copyWith(
                                    colorScheme: const ColorScheme.dark(
                                      primary: Color(0xFF4DA6FF),
                                      onPrimary: Colors.black,
                                      surface: Color(0xFF0F1E36),
                                      onSurface: Colors.white,
                                    ),
                                    textButtonTheme: TextButtonThemeData(
                                      style: TextButton.styleFrom(
                                        foregroundColor: const Color(0xFF4DA6FF),
                                      ),
                                    ),
                                  ),
                                  child: child!,
                                );
                              },
                            );
                            if (picked != null) {
                              final formatted = "${picked.month.toString().padLeft(2, '0')}/${picked.day.toString().padLeft(2, '0')}/${picked.year}";
                              setModalState(() {
                                selectedDate = formatted;
                              });
                            }
                          },
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  selectedDate.isEmpty ? 'Select Date...' : selectedDate,
                                  style: poppins(
                                    color: selectedDate.isEmpty ? Colors.white30 : Colors.white,
                                    fontSize: 14,
                                  ),
                                ),
                                const Icon(Icons.calendar_today_rounded, color: Color(0xFF4DA6FF), size: 18),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // START TIME & END TIME side-by-side
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'START TIME',
                                    style: poppins(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white60),
                                  ),
                                  const SizedBox(height: 6),
                                  GestureDetector(
                                    onTap: () async {
                                      final TimeOfDay? picked = await showTimePicker(
                                        context: context,
                                        initialTime: const TimeOfDay(hour: 9, minute: 0),
                                        builder: (context, child) {
                                          return Theme(
                                            data: Theme.of(context).copyWith(
                                              colorScheme: const ColorScheme.dark(
                                                primary: Color(0xFF4DA6FF),
                                                onPrimary: Colors.black,
                                                surface: Color(0xFF0F1E36),
                                                onSurface: Colors.white,
                                              ),
                                              textButtonTheme: TextButtonThemeData(
                                                style: TextButton.styleFrom(
                                                  foregroundColor: const Color(0xFF4DA6FF),
                                                ),
                                              ),
                                            ),
                                            child: child!,
                                          );
                                        },
                                      );
                                      if (picked != null) {
                                        if (!context.mounted) return;
                                        setModalState(() {
                                          startTime = picked.format(context);
                                        });
                                      }
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.05),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: Colors.white12),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            startTime.isEmpty ? 'Start Time...' : startTime,
                                            style: poppins(
                                              color: startTime.isEmpty ? Colors.white30 : Colors.white,
                                              fontSize: 14,
                                            ),
                                          ),
                                          const Icon(Icons.access_time_rounded, color: Color(0xFF4DA6FF), size: 18),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'END TIME',
                                    style: poppins(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white60),
                                  ),
                                  const SizedBox(height: 6),
                                  GestureDetector(
                                    onTap: () async {
                                      final TimeOfDay? picked = await showTimePicker(
                                        context: context,
                                        initialTime: const TimeOfDay(hour: 10, minute: 0),
                                        builder: (context, child) {
                                          return Theme(
                                            data: Theme.of(context).copyWith(
                                              colorScheme: const ColorScheme.dark(
                                                primary: Color(0xFF4DA6FF),
                                                onPrimary: Colors.black,
                                                surface: Color(0xFF0F1E36),
                                                onSurface: Colors.white,
                                              ),
                                              textButtonTheme: TextButtonThemeData(
                                                style: TextButton.styleFrom(
                                                  foregroundColor: const Color(0xFF4DA6FF),
                                                ),
                                              ),
                                            ),
                                            child: child!,
                                          );
                                        },
                                      );
                                      if (picked != null) {
                                        if (!context.mounted) return;
                                        setModalState(() {
                                          endTime = picked.format(context);
                                        });
                                      }
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.05),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: Colors.white12),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            endTime.isEmpty ? 'End Time...' : endTime,
                                            style: poppins(
                                              color: endTime.isEmpty ? Colors.white30 : Colors.white,
                                              fontSize: 14,
                                            ),
                                          ),
                                          const Icon(Icons.access_time_rounded, color: Color(0xFF4DA6FF), size: 18),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // VENUE
                        Text(
                          'VENUE',
                          style: poppins(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white60),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: venueController,
                          style: poppins(color: Colors.white, fontSize: 14),
                          cursorColor: const Color(0xFF4DA6FF),
                          validator: (val) => val == null || val.trim().isEmpty ? 'Venue is required' : null,
                          decoration: InputDecoration(
                            hintText: 'e.g. Aero Seminar Hall',
                            hintStyle: poppins(color: Colors.white30, fontSize: 13),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.05),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Colors.white12),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFF4DA6FF), width: 1.5),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // AGENDA
                        Text(
                          'AGENDA / DISCUSSION POINTS',
                          style: poppins(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white60),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: agendaController,
                          maxLines: 3,
                          style: poppins(color: Colors.white, fontSize: 14),
                          cursorColor: const Color(0xFF4DA6FF),
                          validator: (val) => val == null || val.trim().isEmpty ? 'Agenda is required' : null,
                          decoration: InputDecoration(
                            hintText: 'What is the objective of this meeting?',
                            hintStyle: poppins(color: Colors.white30, fontSize: 13),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.05),
                            contentPadding: const EdgeInsets.all(16),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Colors.white12),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFF4DA6FF), width: 1.5),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Confirm Schedule Button
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: () {
                              if (selectedDate.isEmpty) {
                                AppToast.warning(context, 'Please select a meeting date.');
                                return;
                              }
                              if (startTime.isEmpty) {
                                AppToast.warning(context, 'Please select a start time.');
                                return;
                              }
                              if (endTime.isEmpty) {
                                AppToast.warning(context, 'Please select an end time.');
                                return;
                              }
                              if (formKey.currentState!.validate()) {
                                _showConfirmationDialog(
                                  context,
                                  teamName: selectedMeetingTeam,
                                  mode: meetingMode,
                                  date: selectedDate,
                                  start: startTime,
                                  end: endTime,
                                  venue: venueController.text.trim(),
                                  agenda: agendaController.text.trim(),
                                );
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00E676),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: Text(
                              'Confirm Schedule',
                              style: poppins(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showConfirmationDialog(
    BuildContext context, {
    required String teamName,
    required String mode,
    required String date,
    required String start,
    required String end,
    required String venue,
    required String agenda,
  }) {
    final poppins = GoogleFonts.poppins;
    showDialog(
      context: context,
      builder: (BuildContext confirmContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0D1E3A),
          title: Text(
            'Confirm Schedule',
            style: poppins(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Text(
            'Are you sure you want to schedule this meeting for the $teamName team?',
            style: poppins(color: const Color(0xFFC9D1E6)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(confirmContext),
              child: Text('Cancel', style: poppins(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(confirmContext); // Close confirm
                Navigator.pop(context); // Close new meeting dialog

                // Call backend API to store meeting
                try {
                  final response = await http.post(
                    Uri.parse('$apiBaseUrl/api/meetings'),
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode({
                      'team_name': teamName,
                      'meeting_mode': mode,
                      'meeting_date': date,
                      'start_time': start,
                      'end_time': end,
                      'venue': venue,
                      'agenda': agenda,
                    }),
                  ).timeout(const Duration(seconds: 15));

                  final data = jsonDecode(response.body);
                  if (response.statusCode == 200 && data['success'] == true) {
                    trackUserAction('Scheduled a new meeting: $agenda on $date');
                    _fetchMeetings();
                    if (mounted) AppToast.success(context, 'Meeting scheduled successfully!'); // ignore: use_build_context_synchronously
                  } else {
                    _showErrorSnackBar(data['message'] ?? 'Failed to schedule meeting.');
                  }
                } catch (e) {
                  _showErrorSnackBar('Network error: Could not schedule meeting.');
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4DA6FF)),
              child: Text('Confirm', style: poppins(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSubmittedView(TextStyle Function({double? fontSize, FontWeight? fontWeight, Color? color}) poppins) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Green Success Card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF00E676).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Color(0xFF00E676), size: 36),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Attendance Submitted',
                      style: poppins(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'The attendance for this meeting has been successfully logged.',
                      style: poppins(fontSize: 12, color: const Color(0xFFC9D1E6)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Summary List Title
        Text(
          'Attendance Summary',
          style: poppins(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white70),
        ),
        const SizedBox(height: 10),

        // Roster Summary List
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _submittedAttendanceRecords.length,
            itemBuilder: (context, index) {
              final rec = _submittedAttendanceRecords[index];
              final name = rec['member_name'] ?? '';
              final roll = rec['roll_number'] ?? '';
              final status = rec['status'] ?? 'Present';
              final reason = rec['reason'] ?? '';
              final isPresent = status.toLowerCase() == 'present';
              final isOnDuty = status.toLowerCase() == 'on duty' || status.toLowerCase() == 'on_duty';
              final isOnDutyPending = status.toLowerCase() == 'on duty (pending)' || status.toLowerCase() == 'on_duty_pending';

              // Color theme per status
              final Color statusColor = isPresent
                  ? const Color(0xFF00E676)
                  : isOnDuty
                  ? const Color(0xFF4DA6FF)
                  : isOnDutyPending
                  ? const Color(0xFFFFD93D)
                  : Colors.redAccent;

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
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
                              name,
                              style: poppins(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              roll,
                              style: poppins(fontSize: 11, color: Colors.white38),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: statusColor.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Text(
                            status.toUpperCase(),
                            style: poppins(
                              fontSize: 11, 
                              fontWeight: FontWeight.bold, 
                              color: statusColor
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (!isPresent && !isOnDuty && !isOnDutyPending && reason.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black26,
                          borderRadius: BorderRadius.circular(8),
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
          ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton.icon(
            onPressed: () {
              setState(() {
                for (var rec in _submittedAttendanceRecords) {
                  final roll = rec['roll_number'] ?? '';
                  _attendanceStatus[roll] = rec['status'] ?? 'Present';
                  _reasonControllers[roll]?.text = rec['reason'] ?? '';
                }
                _isAttendanceSubmittedForSelectedDate = false;
              });
            },
            icon: const Icon(Icons.edit_rounded, color: Color(0xFF4DA6FF)),
            label: Text(
              'Edit Attendance',
              style: poppins(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF4DA6FF)),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFF4DA6FF)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      ],
    );
  }
}
