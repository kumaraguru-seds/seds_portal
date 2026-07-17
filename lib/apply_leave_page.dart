import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'app_toast.dart';
import 'main.dart';

class ApplyLeavePage extends StatefulWidget {
  final UserData userData;
  const ApplyLeavePage({super.key, required this.userData});

  @override
  State<ApplyLeavePage> createState() => _ApplyLeavePageState();
}

class _ApplyLeavePageState extends State<ApplyLeavePage> {
  final ScrollController _scrollController = ScrollController();
  TimeOfDay? _timeFrom;
  TimeOfDay? _timeTo;
  bool _isEditing = false;
  int? _editingLeaveId;

  TimeOfDay? _parseTime(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return null;
    try {
      final parts = timeStr.split(':');
      if (parts.length >= 2) {
        final hour = int.parse(parts[0]);
        final minute = int.parse(parts[1]);
        return TimeOfDay(hour: hour, minute: minute);
      }
    } catch (_) {}
    return null;
  }

  void _resetForm() {
    setState(() {
      _showForm = false;
      _isEditing = false;
      _editingLeaveId = null;
      _dateFrom = null;
      _dateTo = null;
      _timeFrom = null;
      _timeTo = null;
      _reasonController.clear();
      _uploadedFileName = null;
      _uploadedFileBytes = null;
    });
  }

  void _startEditLeave(Map<String, dynamic> leave) {
    setState(() {
      _isEditing = true;
      _editingLeaveId = leave['id'] as int?;
      _reasonController.text = leave['reason'] as String? ?? '';
      _dateFrom = leave['date_from'] != null ? DateTime.parse(leave['date_from'].toString().substring(0, 10)) : null;
      _dateTo = leave['date_to'] != null ? DateTime.parse(leave['date_to'].toString().substring(0, 10)) : null;
      _timeFrom = _parseTime(leave['time_from'] as String?);
      _timeTo = _parseTime(leave['time_to'] as String?);
      _selectedTeam = leave['team'] as String?;
      _uploadedFileName = leave['drive_link'] != null && (leave['drive_link'] as String).isNotEmpty
          ? 'Previous Document Attached'
          : null;
      _uploadedFileBytes = null;
      _showForm = true;
    });
  }
  List<Map<String, dynamic>> _myLeaves = [];
  bool _isLoadingLeaves = true;

  // Form state
  final _reasonController = TextEditingController();
  DateTime? _dateFrom;
  DateTime? _dateTo;
  String? _selectedTeam;
  String? _uploadedFileName;
  List<int>? _uploadedFileBytes;
  bool _isSubmitting = false;
  bool _showForm = false;

  // Approval (Lead & Admin)
  List<Map<String, dynamic>> _pendingLeaves = [];
  bool _isLoadingPending = true;

  List<String> get _teams {
    if (widget.userData.teams.isNotEmpty) {
      return widget.userData.teams;
    }
    if (widget.userData.team != null) return [widget.userData.team!];
    return [];
  }

  String get _role => widget.userData.role;
  bool get _isLead => _role.toLowerCase() == 'lead';
  bool get _isAdmin => _role.toLowerCase() == 'admin';

  @override
  void initState() {
    super.initState();
    if (_teams.isNotEmpty) _selectedTeam = _teams.first;
    _loadMyLeaves();
    if (_isLead || _isAdmin) _loadPendingLeaves();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _loadMyLeaves() async {
    setState(() => _isLoadingLeaves = true);
    try {
      final res = await http
          .get(Uri.parse('$apiBaseUrl/api/leave/my-leaves?email=${Uri.encodeComponent(widget.userData.email)}'))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) {
          setState(() {
            _myLeaves = List<Map<String, dynamic>>.from(data['leaves'] ?? []);
          });
        }
      }
    } catch (e) {
      debugPrint('Load leaves error: $e');
    } finally {
      if (mounted) setState(() => _isLoadingLeaves = false);
    }
  }

  Future<void> _loadPendingLeaves() async {
    setState(() => _isLoadingPending = true);
    try {
      String url;
      if (_isAdmin) {
        url = '$apiBaseUrl/api/leave/all-leaves';
      } else {
        final team = _teams.isNotEmpty ? _teams.first : '';
        url = '$apiBaseUrl/api/leave/team-leaves?team=${Uri.encodeComponent(team)}';
      }
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) {
          setState(() {
            _pendingLeaves = List<Map<String, dynamic>>.from(data['leaves'] ?? []);
          });
        }
      }
    } catch (e) {
      debugPrint('Load pending leaves error: $e');
    } finally {
      if (mounted) setState(() => _isLoadingPending = false);
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(withData: true);
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        setState(() {
          _uploadedFileName = file.name;
          _uploadedFileBytes = file.bytes;
        });
        if (mounted) AppToast.success(context, 'File selected: ${file.name}');
      }
    } catch (e) {
      if (mounted) AppToast.error(context, 'Failed to pick file: $e');
    }
  }

  Future<void> _submitLeave() async {
    if (_dateFrom == null || _dateTo == null) {
      AppToast.error(context, 'Please select From and To dates.');
      return;
    }
    if (_reasonController.text.trim().isEmpty) {
      AppToast.error(context, 'Please enter a reason for leave.');
      return;
    }
    if (_dateTo!.isBefore(_dateFrom!)) {
      AppToast.error(context, '"To" date must be after "From" date.');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final url = _isEditing
          ? Uri.parse('$apiBaseUrl/api/leave/edit')
          : Uri.parse('$apiBaseUrl/api/leave/apply');
      final request = http.MultipartRequest('POST', url);
      
      if (_isEditing) {
        request.fields['leave_id'] = _editingLeaveId.toString();
      } else {
        request.fields['user_email'] = widget.userData.email;
        request.fields['user_name'] = widget.userData.name;
        request.fields['roll_number'] = widget.userData.rollNumber;
        request.fields['team'] = _selectedTeam ?? widget.userData.team ?? '';
        request.fields['role'] = _role;
      }
      request.fields['date_from'] = DateFormat('yyyy-MM-dd').format(_dateFrom!);
      request.fields['date_to'] = DateFormat('yyyy-MM-dd').format(_dateTo!);
      request.fields['reason'] = _reasonController.text.trim();

      if (_timeFrom != null) {
        final hh = _timeFrom!.hour.toString().padLeft(2, '0');
        final mm = _timeFrom!.minute.toString().padLeft(2, '0');
        request.fields['time_from'] = '$hh:$mm';
      }
      if (_timeTo != null) {
        final hh = _timeTo!.hour.toString().padLeft(2, '0');
        final mm = _timeTo!.minute.toString().padLeft(2, '0');
        request.fields['time_to'] = '$hh:$mm';
      }

      if (_uploadedFileBytes != null && _uploadedFileName != null) {
        request.files.add(http.MultipartFile.fromBytes(
          'file',
          _uploadedFileBytes!,
          filename: _uploadedFileName!,
        ));
      }

      final streamedRes = await request.send().timeout(const Duration(seconds: 30));
      final res = await http.Response.fromStream(streamedRes);
      final data = jsonDecode(res.body);

      if (res.statusCode == 200 && data['success'] == true) {
        if (mounted) {
          AppToast.success(context, _isEditing ? 'Leave request updated successfully! ✅' : 'Leave request submitted successfully! ✅');
          _resetForm();
          _loadMyLeaves();
        }
      } else {
        if (mounted) AppToast.error(context, data['message'] ?? 'Failed to submit leave.');
      }
    } catch (e) {
      if (mounted) AppToast.error(context, 'Network error. Please try again.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _approveLeave(int leaveId, String action) async {
    try {
      final res = await http
          .post(
            Uri.parse('$apiBaseUrl/api/leave/approve'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'leave_id': leaveId,
              'action': action,
              'approved_by_email': widget.userData.email,
              'approved_by_name': widget.userData.name,
            }),
          )
          .timeout(const Duration(seconds: 15));
      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['success'] == true) {
        if (mounted) {
          final emoji = action == 'approved' ? '✅' : '❌';
          AppToast.success(context, 'Leave ${action == 'approved' ? 'approved' : 'rejected'} $emoji');
          _loadPendingLeaves();
        }
      } else {
        if (mounted) AppToast.error(context, data['message'] ?? 'Failed to $action leave.');
      }
    } catch (e) {
      if (mounted) AppToast.error(context, 'Error. Please try again.');
    }
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return const Color(0xFF00C48C);
      case 'rejected':
        return const Color(0xFFFF6B6B);
      default:
        return const Color(0xFFFFD93D);
    }
  }

  String _statusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return '✅ Approved';
      case 'rejected':
        return '❌ Rejected';
      default:
        return '⏳ Pending';
    }
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
            child: Image.asset('assets/background.png', fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(color: const Color(0xFF0D1E3A))),
          ),
          Positioned.fill(child: Container(color: Colors.black.withValues(alpha: 0.50))),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
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
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF9B59B6).withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.event_available_rounded, color: Color(0xFF9B59B6), size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Apply Leave', style: poppins(fontSize: 17.0, fontWeight: FontWeight.w900, color: Colors.white)),
                            Text(widget.userData.name, style: poppins(fontSize: 11.0, color: Colors.white54)),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          if (_showForm) {
                            _resetForm();
                          } else {
                            setState(() => _showForm = true);
                          }
                        },
                        icon: Icon(_showForm ? Icons.close_rounded : Icons.add_rounded, color: Colors.white),
                        tooltip: _showForm ? 'Cancel' : 'Apply Leave',
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: Scrollbar(
                    controller: _scrollController,
                    thumbVisibility: true,
                    child: ListView(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      children: [
                        // Apply Leave Form (expandable)
                        AnimatedCrossFade(
                          firstChild: const SizedBox.shrink(),
                          secondChild: _buildApplyForm(poppins),
                          crossFadeState: _showForm ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                          duration: const Duration(milliseconds: 300),
                        ),

                        // My Leave History
                        _buildSectionHeader('My Leave Requests', poppins, onRefresh: _loadMyLeaves),
                        if (_isLoadingLeaves)
                          const Center(child: Padding(
                            padding: EdgeInsets.all(20),
                            child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF9B59B6))),
                          ))
                        else if (_myLeaves.isEmpty)
                          _buildEmptyCard('No leave requests yet. Tap + to apply.', poppins)
                        else
                          ..._myLeaves.map((leave) => _buildMyLeaveCard(leave, poppins)),

                        // Pending Approvals (Lead/Admin only)
                        if (_isLead || _isAdmin) ...[
                          const SizedBox(height: 8),
                          _buildSectionHeader(
                            _isAdmin ? 'Member & Lead Requests' : 'Team Leave Requests',
                            poppins, onRefresh: _loadPendingLeaves),
                          if (_isLoadingPending)
                            const Center(child: Padding(
                              padding: EdgeInsets.all(20),
                              child: CircularProgressIndicator(
                                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4DA6FF))),
                            ))
                          else if (_pendingLeaves.isEmpty)
                            _buildEmptyCard('No leave requests to review.', poppins)
                          else
                            ..._pendingLeaves.map((leave) => _buildPendingCard(leave, poppins)),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
        ],
      ),
      floatingActionButton: !_showForm
          ? FloatingActionButton.extended(
              onPressed: () => setState(() => _showForm = true),
              backgroundColor: const Color(0xFF9B59B6),
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: Text('Apply Leave', style: poppins(fontWeight: FontWeight.bold)),
            )
          : null,
    );
  }

  Widget _buildApplyForm(dynamic poppins) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF9B59B6).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_isEditing ? 'Edit Leave Request' : 'New Leave Request', style: poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14.0)),
          const SizedBox(height: 14),

          // Team selector (only if multi-team)
          if (_teams.length > 1) ...[
            Text('Team', style: poppins(color: Colors.white70, fontSize: 12.0)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedTeam,
                  dropdownColor: const Color(0xFF1A2B4A),
                  isExpanded: true,
                  style: poppins(color: Colors.white, fontSize: 13.0),
                  items: _teams
                      .map((t) => DropdownMenuItem<String>(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedTeam = v),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Date range
          Row(
            children: [
              Expanded(child: _buildDateField('From Date', _dateFrom, (d) => setState(() => _dateFrom = d), poppins)),
              const SizedBox(width: 10),
              Expanded(child: _buildDateField('To Date', _dateTo, (d) => setState(() => _dateTo = d), poppins)),
            ],
          ),
          const SizedBox(height: 12),

          // Timings range
          Row(
            children: [
              Expanded(child: _buildTimeField('From Time', _timeFrom, (t) => setState(() => _timeFrom = t), poppins)),
              const SizedBox(width: 10),
              Expanded(child: _buildTimeField('To Time', _timeTo, (t) => setState(() => _timeTo = t), poppins)),
            ],
          ),
          const SizedBox(height: 12),

          // Reason
          Text('Reason *', style: poppins(color: Colors.white70, fontSize: 12.0)),
          const SizedBox(height: 6),
          TextField(
            controller: _reasonController,
            maxLines: 3,
            style: poppins(color: Colors.white, fontSize: 13.0),
            decoration: InputDecoration(
              hintText: 'Enter reason for leave...',
              hintStyle: poppins(color: Colors.white38, fontSize: 12.0),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.04),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF9B59B6))),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
          const SizedBox(height: 12),

          // File upload (optional)
          Text('Supporting Document (Optional)', style: poppins(color: Colors.white70, fontSize: 12.0)),
          const SizedBox(height: 6),
          InkWell(
            onTap: _pickFile,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _uploadedFileName != null
                      ? const Color(0xFF00C48C).withValues(alpha: 0.5)
                      : Colors.white.withValues(alpha: 0.12),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _uploadedFileName != null ? Icons.attach_file_rounded : Icons.upload_file_rounded,
                    color: _uploadedFileName != null ? const Color(0xFF00C48C) : Colors.white54,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _uploadedFileName ?? 'Tap to attach a file (uploaded to Drive)',
                      style: poppins(
                          color: _uploadedFileName != null ? const Color(0xFF00C48C) : Colors.white54,
                          fontSize: 12.0),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_uploadedFileName != null)
                    IconButton(
                      onPressed: () => setState(() {
                        _uploadedFileName = null;
                        _uploadedFileBytes = null;
                      }),
                      icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 16),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Submit button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isSubmitting ? null : () => _showApplyConfirmation(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF9B59B6),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              icon: _isSubmitting
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                  : const Icon(Icons.send_rounded, size: 18),
              label: Text(_isSubmitting ? 'Submitting...' : (_isEditing ? 'Update Leave Request' : 'Submit Leave Request'),
                  style: poppins(fontWeight: FontWeight.bold, fontSize: 14.0)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeField(String label, TimeOfDay? time, Function(TimeOfDay) onPick, dynamic poppins) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: poppins(color: Colors.white70, fontSize: 12.0)),
        const SizedBox(height: 6),
        InkWell(
          onTap: () async {
            final picked = await showTimePicker(
              context: context,
              initialTime: time ?? TimeOfDay.now(),
              builder: (ctx, child) => Theme(
                data: ThemeData.dark().copyWith(
                  colorScheme: const ColorScheme.dark(
                    primary: Color(0xFF9B59B6),
                    surface: Color(0xFF1A2B4A),
                  ),
                ),
                child: child!,
              ),
            );
            if (picked != null) onPick(picked);
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: time != null
                    ? const Color(0xFF9B59B6).withValues(alpha: 0.5)
                    : Colors.white.withValues(alpha: 0.1),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.access_time_rounded, color: Colors.white54, size: 16),
                const SizedBox(width: 8),
                Text(
                  time != null ? time.format(context) : 'Select Time',
                  style: poppins(
                    color: time != null ? Colors.white : Colors.white30,
                    fontSize: 12.0,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDateField(String label, DateTime? date, Function(DateTime) onPick, dynamic poppins) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: poppins(color: Colors.white70, fontSize: 12.0)),
        const SizedBox(height: 6),
        InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: date ?? DateTime.now(),
              firstDate: DateTime.now().subtract(const Duration(days: 30)),
              lastDate: DateTime.now().add(const Duration(days: 365)),
              builder: (ctx, child) => Theme(
                data: ThemeData.dark().copyWith(
                  colorScheme: const ColorScheme.dark(
                    primary: Color(0xFF9B59B6),
                    surface: Color(0xFF1A2B4A),
                  ),
                ),
                child: child!,
              ),
            );
            if (picked != null) onPick(picked);
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: date != null
                    ? const Color(0xFF9B59B6).withValues(alpha: 0.5)
                    : Colors.white.withValues(alpha: 0.1),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.calendar_today_rounded,
                    size: 14,
                    color: date != null ? const Color(0xFF9B59B6) : Colors.white54),
                const SizedBox(width: 6),
                Text(
                  date != null ? DateFormat('dd MMM yy').format(date) : 'Select',
                  style: poppins(
                      color: date != null ? Colors.white : Colors.white54,
                      fontSize: 12.0, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, dynamic poppins, {VoidCallback? onRefresh}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Text(title, style: poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14.0)),
          const Spacer(),
          if (onRefresh != null)
            IconButton(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded, color: Colors.white54, size: 18),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
        ],
      ),
    );
  }

  Widget _buildMyLeaveCard(Map<String, dynamic> leave, dynamic poppins) {
    final status = leave['status'] as String? ?? 'pending';
    final dateFrom = leave['date_from']?.toString().substring(0, 10) ?? '';
    final dateTo = leave['date_to']?.toString().substring(0, 10) ?? '';
    final timeFrom = leave['time_from'] as String?;
    final timeTo = leave['time_to'] as String?;
    final timeStr = (timeFrom != null && timeTo != null) ? ' ($timeFrom - $timeTo)' : '';
    final driveLink = leave['drive_link'] as String?;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _statusColor(status).withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('$dateFrom → $dateTo$timeStr',
                    style: poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.0)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: _statusColor(status).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_statusLabel(status),
                    style: poppins(color: _statusColor(status), fontSize: 11.0, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(leave['reason'] as String? ?? '',
              style: poppins(color: Colors.white70, fontSize: 12.0), maxLines: 2, overflow: TextOverflow.ellipsis),
          if (leave['team'] != null) ...[
            const SizedBox(height: 4),
            Text('Team: ${leave['team']}', style: poppins(color: Colors.white54, fontSize: 11.0)),
          ],
          if (driveLink != null && driveLink.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.attach_file_rounded, color: Color(0xFF4DA6FF), size: 13),
                const SizedBox(width: 4),
                Text('Document attached', style: poppins(color: const Color(0xFF4DA6FF), fontSize: 11.0)),
              ],
            ),
          ],
          if (leave['approved_by'] != null && status != 'pending') ...[
            const SizedBox(height: 4),
            Text('By: ${leave['approved_by']}', style: poppins(color: Colors.white38, fontSize: 10.0)),
          ],
          if (status == 'pending') ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _startEditLeave(leave),
                  icon: const Icon(Icons.edit_rounded, size: 14),
                  label: Text('Edit', style: poppins(fontSize: 11.0, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFFD93D),
                    side: const BorderSide(color: Color(0xFFFFD93D)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildPendingCard(Map<String, dynamic> leave, dynamic poppins) {
    final status = leave['status'] as String? ?? 'pending';
    final dateFrom = leave['date_from']?.toString().substring(0, 10) ?? '';
    final dateTo = leave['date_to']?.toString().substring(0, 10) ?? '';
    final timeFrom = leave['time_from'] as String?;
    final timeTo = leave['time_to'] as String?;
    final timeStr = (timeFrom != null && timeTo != null) ? ' ($timeFrom - $timeTo)' : '';
    final isPending = status == 'pending';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: isPending
                ? const Color(0xFF4DA6FF).withValues(alpha: 0.3)
                : _statusColor(status).withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(leave['user_name'] as String? ?? '',
                    style: poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.0)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _statusColor(status).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_statusLabel(status),
                    style: poppins(color: _statusColor(status), fontSize: 10.0, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          if (leave['team'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('${leave['team']} · ${leave['roll_number'] ?? ''}',
                  style: poppins(color: Colors.white54, fontSize: 11.0)),
            ),
          const SizedBox(height: 6),
          Text('$dateFrom → $dateTo$timeStr', style: poppins(color: Colors.white70, fontSize: 12.0, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(leave['reason'] as String? ?? '',
              style: poppins(color: Colors.white54, fontSize: 12.0), maxLines: 2, overflow: TextOverflow.ellipsis),
          if (isPending) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showRejectConfirmation(context, leave['id'] as int, leave['user_name'] as String? ?? 'this member'),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFFF6B6B)),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.close_rounded, color: Color(0xFFFF6B6B), size: 16),
                    label: Text('Reject', style: poppins(color: const Color(0xFFFF6B6B), fontSize: 12.0, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _showApproveConfirmation(context, leave['id'] as int, leave['user_name'] as String? ?? 'this member'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00C48C),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: Text('Approve', style: poppins(fontWeight: FontWeight.bold, fontSize: 12.0)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyCard(String msg, dynamic poppins) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Center(
        child: Text(msg, style: poppins(color: Colors.white38, fontSize: 13.0), textAlign: TextAlign.center),
      ),
    );
  }

  void _showApplyConfirmation(BuildContext context) {
    final poppins = GoogleFonts.poppins;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2B4A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(_isEditing ? 'Update Request?' : 'Submit Request?',
            style: poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16.0)),
        content: Text(
            _isEditing
                ? 'Are you sure you want to save modifications to this leave request?'
                : 'Are you sure you want to submit this leave request for approval?',
            style: poppins(color: Colors.white70, fontSize: 13.0)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: poppins(color: Colors.white38, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _submitLeave();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF9B59B6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text('Confirm', style: poppins(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showApproveConfirmation(BuildContext context, int leaveId, String applicantName) {
    final poppins = GoogleFonts.poppins;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2B4A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Approve Leave?',
            style: poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16.0)),
        content: Text('Are you sure you want to approve the leave request for $applicantName?',
            style: poppins(color: Colors.white70, fontSize: 13.0)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: poppins(color: Colors.white38, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _approveLeave(leaveId, 'approved');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00C48C),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text('Approve', style: poppins(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showRejectConfirmation(BuildContext context, int leaveId, String applicantName) {
    final poppins = GoogleFonts.poppins;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2B4A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Reject Leave?',
            style: poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16.0)),
        content: Text('Are you sure you want to reject the leave request for $applicantName?',
            style: poppins(color: Colors.white70, fontSize: 13.0)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: poppins(color: Colors.white38, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _approveLeave(leaveId, 'rejected');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B6B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text('Reject', style: poppins(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

}