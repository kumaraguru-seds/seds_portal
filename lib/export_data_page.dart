import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart' as ex;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:permission_handler/permission_handler.dart';

import 'main.dart'; // For UserData, DesktopPageWrapper, apiBaseUrl
import 'app_toast.dart';
import 'network_utils.dart';

class ExportDataPage extends StatefulWidget {
  final UserData userData;

  const ExportDataPage({super.key, required this.userData});

  @override
  State<ExportDataPage> createState() => _ExportDataPageState();
}

class _ExportDataPageState extends State<ExportDataPage> {
  // Config & Selection state
  String _selectedTopic = 'Work Logs'; // 'Work Logs', 'Attendance', 'Both'
  String _selectedFormat = 'PDF'; // 'PDF', 'CSV', 'Excel'
  
  // Loading & Progress state
  bool _isLoadingUsers = false;
  bool _isExporting = false;
  double _exportProgress = 0.0;
  String _exportStatusText = '';

  // User list state (Admin/Lead only)
  List<dynamic> _allUsersList = [];
  List<dynamic> _filteredUsersList = [];
  
  // Scoping selection state
  String _selectedScope = 'Self'; // 'Self', 'Team', 'Specific Member'
  String? _selectedTeamFilter; // For admin team scoping (All or Specific team)
  String? _selectedRoleFilter = 'All Roles'; // 'All Roles', 'Leads Only', 'Members Only'
  dynamic _selectedSpecificMember; // The chosen specific user object
  String _memberSearchQuery = '';

  final List<String> _topics = ['Work Logs', 'Attendance', 'Both'];
  final List<String> _formats = ['PDF', 'CSV', 'Excel'];
  
  // Constant teams list from main.dart or standard (default fallbacks)
  List<String> _sedsTeams = [
    'Rocketry',
    'Avionics',
    'CANSAT',
    'Media',
    'Corporate',
    'Web Dev & AI',
    'Admin'
  ];

  @override
  void initState() {
    super.initState();
    _selectedTeamFilter = widget.userData.role == 'Admin' ? 'All' : widget.userData.team;
    _loadUsersData();
  }

  Future<void> _loadUsersData() async {
    if (widget.userData.role == 'Member') return;

    setState(() {
      _isLoadingUsers = true;
    });

    try {
      if (widget.userData.role == 'Admin') {
        final response = await http.get(Uri.parse('$apiBaseUrl/api/admin/users'));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['success'] == true) {
            setState(() {
              _allUsersList = data['users'] ?? [];
              
              // Extract existing teams dynamically
              final Set<String> teamsSet = {};
              for (final user in _allUsersList) {
                final team = user['team'] ?? '';
                if (team.isNotEmpty && team != 'Admin') {
                  teamsSet.add(team);
                }
              }
              if (teamsSet.isNotEmpty) {
                _sedsTeams = teamsSet.toList()..sort();
              }
              
              _filterUsers();
            });
          }
        }
      } else if (widget.userData.role == 'Lead') {
        final leadTeam = widget.userData.team ?? '';
        if (leadTeam.isNotEmpty) {
          final response = await http.get(Uri.parse('$apiBaseUrl/api/members?team=$leadTeam'));
          if (response.statusCode == 200) {
            final List<dynamic> members = jsonDecode(response.body);
            // Prepend the lead themselves to the team member list
            final selfObj = {
              'id': widget.userData.id,
              'name': widget.userData.name,
              'email': widget.userData.email,
              'roll_number': widget.userData.rollNumber,
              'role': 'Lead',
              'team': leadTeam
            };
            setState(() {
              _allUsersList = [selfObj, ...members];
              _filterUsers();
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading user list: $e');
    } finally {
      setState(() {
        _isLoadingUsers = false;
      });
    }
  }

  void _filterUsers() {
    setState(() {
      _filteredUsersList = _allUsersList.where((u) {
        // Name / Roll search filter
        final name = (u['name'] ?? '').toString().toLowerCase();
        final roll = (u['roll_number'] ?? '').toString().toLowerCase();
        final q = _memberSearchQuery.trim().toLowerCase();
        final matchesSearch = q.isEmpty || name.contains(q) || roll.contains(q);

        if (widget.userData.role == 'Admin') {
          // Team filter
          final team = u['team'] ?? '';
          final matchesTeam = _selectedTeamFilter == 'All' || team == _selectedTeamFilter;

          // Role filter
          final role = (u['role'] ?? '').toString().toLowerCase();
          bool matchesRole = true;
          if (_selectedRoleFilter == 'Leads Only') {
            matchesRole = role == 'lead';
          } else if (_selectedRoleFilter == 'Members Only') {
            matchesRole = role == 'member';
          }

          return matchesSearch && matchesTeam && matchesRole;
        } else {
          // Lead can only search within their loaded team members
          return matchesSearch;
        }
      }).toList();
    });
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Trigger export flow
  // ─────────────────────────────────────────────────────────────────────────────
  // Permission helper — must be called before any file write on Android
  // ─────────────────────────────────────────────────────────────────────────────
  Future<bool> _requestStoragePermission() async {
    if (!Platform.isAndroid) return true;

    try {
      // Android 11+ needs MANAGE_EXTERNAL_STORAGE for /storage/emulated/0/Download
      // Android 10 and below use the legacy WRITE_EXTERNAL_STORAGE
      PermissionStatus status = await Permission.manageExternalStorage.status;

      if (status.isGranted) return true;

      if (status.isPermanentlyDenied) {
        // Show dialog → direct user to Settings
        if (mounted) {
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFF0D1C33),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  const Icon(Icons.folder_open_rounded, color: Color(0xFF4DA6FF)),
                  const SizedBox(width: 10),
                  Text(
                    'Storage Permission',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              content: Text(
                'SEDS Portal needs storage access to save your export file to the Downloads folder.\n\nPlease tap "Open Settings", then enable "All files access" (or "Files and media") for SEDS Portal.',
                style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Cancel', style: GoogleFonts.poppins(color: Colors.white38)),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4DA6FF),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.settings_rounded, size: 16),
                  label: Text('Open Settings', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await openAppSettings();
                  },
                ),
              ],
            ),
          );
        }
        return false;
      }

      // Not yet asked or denied — request now
      status = await Permission.manageExternalStorage.request();
      if (status.isGranted) return true;

      // Try legacy storage permission as fallback (Android ≤ 10)
      try {
        final legacy = await Permission.storage.request();
        if (legacy.isGranted) return true;
      } catch (_) {
        // Legacy permission not available on this API level — continue
      }

      // Permission denied — warn user
      if (mounted) {
        AppToast.warning(
          context,
          'Storage permission denied. Export may not save to Downloads folder.',
        );
      }
      // Still return true so the export can try (falls back to app-external dir)
      return true;
    } catch (e) {
      // MissingPluginException: plugin not compiled yet — treat as permitted
      // The app needs a full restart (flutter run) for native plugins to register.
      debugPrint('Permission plugin not available: $e');
      return true;
    }
  }


  // ─────────────────────────────────────────────────────────────────────────────
  // Trigger export flow
  // ─────────────────────────────────────────────────────────────────────────────
  Future<void> _handleExport() async {
    // 0. Storage permission gate (Android only)
    final hasPermission = await _requestStoragePermission();
    if (!mounted) return;
    if (!hasPermission) return;

    // 1. Internet Connection Check
    final isOnline = await NetworkUtils.checkConnection(context);
    if (!mounted) return;
    if (!isOnline) return;

    setState(() {
      _isExporting = true;
      _exportProgress = 0.1;
      _exportStatusText = 'Fetching report details from SEDS server...';
    });

    try {
      // 2. Fetch required logs & attendance
      final List<Map<String, dynamic>> finalLogs = [];
      final List<Map<String, dynamic>> finalAttendance = [];
      String reportScopeText = '';

      if (widget.userData.role == 'Member' || _selectedScope == 'Self') {
        reportScopeText = 'Personal: ${widget.userData.name} (${widget.userData.rollNumber})';
        await _fetchMemberData(widget.userData.email, widget.userData.rollNumber, widget.userData.team ?? '', finalLogs, finalAttendance);
      } 
      else if (_selectedScope == 'Specific Member') {
        if (_selectedSpecificMember == null) {
          AppToast.warning(context, 'Please select a specific team member to export.');
          setState(() => _isExporting = false);
          return;
        }
        final targetEmail = _selectedSpecificMember['email'] ?? '';
        final targetRoll = _selectedSpecificMember['roll_number'] ?? '';
        final targetTeam = _selectedSpecificMember['team'] ?? '';
        final targetName = _selectedSpecificMember['name'] ?? '';
        reportScopeText = 'Member: $targetName ($targetRoll)';
        await _fetchMemberData(targetEmail, targetRoll, targetTeam, finalLogs, finalAttendance);
      } 
      else if (_selectedScope == 'Team') {
        final targetTeam = widget.userData.role == 'Admin' ? _selectedTeamFilter! : widget.userData.team!;
        reportScopeText = 'Team: $targetTeam';
        await _fetchTeamData(targetTeam, finalLogs, finalAttendance);
      }

      setState(() {
        _exportProgress = 0.5;
        _exportStatusText = 'Compiling export records...';
      });

      // 3. Compile output file
      if (finalLogs.isEmpty && finalAttendance.isEmpty) {
        if (mounted) AppToast.warning(context, 'No matching records found for this selection.');
        setState(() => _isExporting = false);
        return;
      }

      final now = DateTime.now();
      final dateSlug = DateFormat('yyyyMMdd_HHmmss').format(now);
      final filename = 'SEDS_Export_${_selectedTopic.replaceAll(" ", "")}_$dateSlug';

      setState(() {
        _exportProgress = 0.7;
        _exportStatusText = 'Generating $_selectedFormat file...';
      });

      // Save output path
      String savedPath = '';

      if (_selectedFormat == 'CSV') {
        final csvString = _generateCSV(finalLogs, finalAttendance);
        savedPath = await _saveStringToFile(csvString, '$filename.csv');
      } else if (_selectedFormat == 'Excel') {
        final excelBytes = _generateExcel(finalLogs, finalAttendance);
        savedPath = await _saveBytesToFile(excelBytes, '$filename.xlsx');
      } else if (_selectedFormat == 'PDF') {
        final pdfBytes = await _generatePDF(finalLogs, finalAttendance, reportScopeText);
        savedPath = await _saveBytesToFile(pdfBytes, '$filename.pdf');
      }

      setState(() {
        _exportProgress = 0.9;
        _exportStatusText = 'Logging audit entry to secure DB...';
      });

      // 4. Log to DB
      await _logExportToDB(
        userEmail: widget.userData.email,
        rollNumber: widget.userData.rollNumber,
        fileExtension: _selectedFormat.toLowerCase() == 'excel' ? 'xlsx' : _selectedFormat.toLowerCase(),
        scope: reportScopeText,
        topic: _selectedTopic,
      );

      setState(() {
        _exportProgress = 1.0;
        _isExporting = false;
      });

      if (mounted) {
        AppToast.success(context, 'Export complete! File saved successfully.');
        _showFileOpenDialog(savedPath);
      }
    } catch (e) {
      debugPrint('Export Error: $e');
      if (mounted) {
        AppToast.error(context, 'Export generation failed. Please try again.');
      }
      setState(() => _isExporting = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Fetch details helpers
  // ─────────────────────────────────────────────────────────────────────────────
  Future<void> _fetchMemberData(
    String email,
    String rollNumber,
    String team,
    List<Map<String, dynamic>> finalLogs,
    List<Map<String, dynamic>> finalAttendance,
  ) async {
    // Fetch logs history
    if (_selectedTopic == 'Work Logs' || _selectedTopic == 'Both') {
      final logsRes = await http.get(Uri.parse('$apiBaseUrl/api/logs/history?email=$email&limit=5000'));
      if (logsRes.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(logsRes.body);
        final List<dynamic> logs = data['sessions'] ?? [];
        for (final item in logs) {
          final m = Map<String, dynamic>.from(item);
          // Backfill missing identity fields from the known userData
          if ((m['user_name'] ?? '').toString().isEmpty) m['user_name'] = widget.userData.name;
          if ((m['roll_number'] ?? '').toString().isEmpty) m['roll_number'] = rollNumber;
          if ((m['team'] ?? '').toString().isEmpty) m['team'] = team;
          finalLogs.add(m);
        }
      }
    }

    // Fetch attendance
    if (_selectedTopic == 'Attendance' || _selectedTopic == 'Both') {
      if (rollNumber.isNotEmpty && team.isNotEmpty) {
        final attRes = await http.get(Uri.parse('$apiBaseUrl/api/attendance/member?roll_number=$rollNumber&team=$team'));
        if (attRes.statusCode == 200) {
          final data = jsonDecode(attRes.body);
          final List<dynamic> records = (data['overall'] != null) ? (data['overall']['all_records'] ?? []) : [];
          for (final r in records) {
            finalAttendance.add({
              'roll_number': rollNumber,
              'name': widget.userData.name,
              'team': r['team'] ?? team,
              'date': r['date'] ?? '',
              'status': r['status'] ?? '',
              'reason': r['reason'] ?? '',
            });
          }
        }
      }
    }
  }

  Future<void> _fetchTeamData(
    String team,
    List<Map<String, dynamic>> finalLogs,
    List<Map<String, dynamic>> finalAttendance,
  ) async {
    // 1. Fetch team logs
    if (_selectedTopic == 'Work Logs' || _selectedTopic == 'Both') {
      final logsRes = await http.get(Uri.parse('$apiBaseUrl/api/logs/all?team=${Uri.encodeComponent(team)}&limit=5000'));
      if (logsRes.statusCode == 200) {
        final data = jsonDecode(logsRes.body);
        // /api/logs/all returns { success: true, sessions: [...] }
        final List<dynamic> listParsed = data is Map ? (data['sessions'] ?? []) : (data is List ? data : []);
        for (final item in listParsed) {
          finalLogs.add(Map<String, dynamic>.from(item));
        }
      }
    }

    // 2. Fetch team attendance
    if (_selectedTopic == 'Attendance' || _selectedTopic == 'Both') {
      // /api/admin/attendance-summary returns a flat array of users with records[]
      final attRes = await http.get(Uri.parse('$apiBaseUrl/api/admin/attendance-summary'));
      if (attRes.statusCode == 200) {
        final dynamic raw = jsonDecode(attRes.body);
        // Response is a flat List of user objects each having a 'records' field
        final List<dynamic> allUsers = raw is List ? raw : [];
        final List<dynamic> teamMembers = allUsers.where((u) => u['team'] == team).toList();

        for (final u in teamMembers) {
          final roll = u['roll_number'] ?? '';
          final name = u['name'] ?? '';
          final List<dynamic> records = u['records'] ?? [];
          for (final r in records) {
            final status = (r['status'] ?? '').toString().toLowerCase();
            // Skip cancelled records
            if (status == 'cancelled') continue;
            finalAttendance.add({
              'roll_number': roll,
              'name': name,
              'team': team,
              'date': r['date'] ?? '',
              'status': r['status'] ?? '',
              'reason': r['reason'] ?? '',
            });
          }
        }
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // File formats generation helpers
  // ─────────────────────────────────────────────────────────────────────────────

  String _generateCSV(List<Map<String, dynamic>> logs, List<Map<String, dynamic>> att) {
    final List<List<dynamic>> csvRows = [];
    
    // Header block
    csvRows.add(['SEDS PORTAL EXPORT REPORT']);
    csvRows.add(['Exporter Name', widget.userData.name]);
    csvRows.add(['Exporter Roll No', widget.userData.rollNumber]);
    csvRows.add(['Export Date', DateFormat('dd/MM/yyyy').format(DateTime.now())]);
    csvRows.add(['Export Time', DateFormat('HH:mm:ss').format(DateTime.now())]);
    csvRows.add([]); // empty spacer

    if (_selectedTopic == 'Work Logs' || _selectedTopic == 'Both') {
      csvRows.add(['--- WORK SESSIONS LOGS ---']);
      csvRows.add(['Roll No', 'Name', 'Team', 'Date', 'Start Time', 'End Time', 'Duration (m)', 'Summary/Activity']);
      for (final log in logs) {
        final start = log['start_time'] != null ? DateTime.tryParse(log['start_time'].toString())?.toLocal() : null;
        final stop = log['stop_time'] != null ? DateTime.tryParse(log['stop_time'].toString())?.toLocal() : null;
        
        final dateStr = start != null ? DateFormat('dd/MM/yyyy').format(start) : '';
        final startStr = start != null ? DateFormat('HH:mm:ss').format(start) : '';
        final stopStr = stop != null ? DateFormat('HH:mm:ss').format(stop) : (log['is_active'] == true ? 'ACTIVE' : '');
        final durationMin = log['duration_seconds'] != null ? (((int.tryParse(log['duration_seconds'].toString()) ?? 0) / 60).toStringAsFixed(1)) : '0';

        csvRows.add([
          log['roll_number'] ?? '',
          log['user_name'] ?? '',
          log['team'] ?? '',
          dateStr,
          startStr,
          stopStr,
          durationMin,
          log['summary'] ?? '',
        ]);
      }
      csvRows.add([]); // empty spacer
    }

    if (_selectedTopic == 'Attendance' || _selectedTopic == 'Both') {
      csvRows.add(['--- ATTENDANCE RECORDS ---']);
      csvRows.add(['Roll No', 'Name', 'Team', 'Date', 'Status', 'Reason/Remarks']);
      for (final record in att) {
        csvRows.add([
          record['roll_number'] ?? '',
          record['name'] ?? '',
          record['team'] ?? '',
          record['date'] ?? '',
          (record['status'] ?? '').toString().toUpperCase(),
          record['reason'] ?? '',
        ]);
      }
    }

    return const ListToCsvConverter().convert(csvRows);
  }

  Uint8List _generateExcel(List<Map<String, dynamic>> logs, List<Map<String, dynamic>> att) {
    final excel = ex.Excel.createExcel();
    
    // Clear default sheet
    excel.rename('Sheet1', 'Attendance Reports');
    
    if (_selectedTopic == 'Work Logs' || _selectedTopic == 'Both') {
      final sheet = excel['Work Sessions'];
      
      // Title metadata
      sheet.appendRow([ex.TextCellValue('SEDS PORTAL WORK SESSIONS REPORT')]);
      sheet.appendRow([ex.TextCellValue('Exporter Name'), ex.TextCellValue(widget.userData.name)]);
      sheet.appendRow([ex.TextCellValue('Exporter Roll'), ex.TextCellValue(widget.userData.rollNumber)]);
      sheet.appendRow([ex.TextCellValue('Exported At'), ex.TextCellValue(DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now()))]);
      sheet.appendRow([]); // Empty spacer row

      // Header row
      sheet.appendRow([
        ex.TextCellValue('Roll Number'),
        ex.TextCellValue('Name'),
        ex.TextCellValue('Team'),
        ex.TextCellValue('Date'),
        ex.TextCellValue('Start Time'),
        ex.TextCellValue('End Time'),
        ex.TextCellValue('Duration (Min)'),
        ex.TextCellValue('Summary / Activity')
      ]);

      for (final log in logs) {
        final start = log['start_time'] != null ? DateTime.tryParse(log['start_time'].toString())?.toLocal() : null;
        final stop = log['stop_time'] != null ? DateTime.tryParse(log['stop_time'].toString())?.toLocal() : null;
        
        final dateStr = start != null ? DateFormat('dd/MM/yyyy').format(start) : '';
        final startStr = start != null ? DateFormat('HH:mm:ss').format(start) : '';
        final stopStr = stop != null ? DateFormat('HH:mm:ss').format(stop) : (log['is_active'] == true ? 'ACTIVE' : '');
        final durationMin = log['duration_seconds'] != null ? double.parse(((int.tryParse(log['duration_seconds'].toString()) ?? 0) / 60).toStringAsFixed(1)) : 0.0;

        sheet.appendRow([
          ex.TextCellValue(log['roll_number'] ?? ''),
          ex.TextCellValue(log['user_name'] ?? ''),
          ex.TextCellValue(log['team'] ?? ''),
          ex.TextCellValue(dateStr),
          ex.TextCellValue(startStr),
          ex.TextCellValue(stopStr),
          ex.DoubleCellValue(durationMin),
          ex.TextCellValue(log['summary'] ?? '')
        ]);
      }
    }

    if (_selectedTopic == 'Attendance' || _selectedTopic == 'Both') {
      final sheet = excel['Attendance Reports'];
      
      // Title metadata
      sheet.appendRow([ex.TextCellValue('SEDS PORTAL ATTENDANCE REPORT')]);
      sheet.appendRow([ex.TextCellValue('Exporter Name'), ex.TextCellValue(widget.userData.name)]);
      sheet.appendRow([ex.TextCellValue('Exporter Roll'), ex.TextCellValue(widget.userData.rollNumber)]);
      sheet.appendRow([ex.TextCellValue('Exported At'), ex.TextCellValue(DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now()))]);
      sheet.appendRow([]); // Empty spacer row

      // Header row
      sheet.appendRow([
        ex.TextCellValue('Roll Number'),
        ex.TextCellValue('Name'),
        ex.TextCellValue('Team'),
        ex.TextCellValue('Date'),
        ex.TextCellValue('Status'),
        ex.TextCellValue('Reason / Remarks')
      ]);

      for (final record in att) {
        sheet.appendRow([
          ex.TextCellValue(record['roll_number'] ?? ''),
          ex.TextCellValue(record['name'] ?? ''),
          ex.TextCellValue(record['team'] ?? ''),
          ex.TextCellValue(record['date'] ?? ''),
          ex.TextCellValue((record['status'] ?? '').toString().toUpperCase()),
          ex.TextCellValue(record['reason'] ?? '')
        ]);
      }
    }

    // Clean empty sheet if not Both
    if (_selectedTopic == 'Work Logs') {
      excel.delete('Attendance Reports');
    }

    final bytes = excel.save();
    return Uint8List.fromList(bytes ?? []);
  }

  Future<Uint8List> _generatePDF(
    List<Map<String, dynamic>> logs,
    List<Map<String, dynamic>> att,
    String reportScopeText,
  ) async {
    final pdf = pw.Document();

    // Load App Logo from assets
    pw.MemoryImage? logoImage;
    try {
      final logoBytes = await rootBundle.load('assets/app_logo.png');
      logoImage = pw.MemoryImage(logoBytes.buffer.asUint8List());
    } catch (e) {
      debugPrint('Failed to load assets/app_logo.png: $e');
    }

    final now = DateTime.now();
    final exportDateStr = DateFormat('dd/MM/yyyy').format(now);
    final exportTimeStr = DateFormat('HH:mm:ss').format(now);

    final String reportTopicTitle = _selectedTopic == 'Both' 
        ? 'Logs & Attendance Report' 
        : (_selectedTopic == 'Work Logs' ? 'Work Sessions logs' : 'Attendance Report');

    // Build reusable header block
    pw.Widget buildPageHeader(pw.Context context) {
      return pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 5.0 * PdfPageFormat.mm),
        padding: const pw.EdgeInsets.only(bottom: 3.0 * PdfPageFormat.mm),
        decoration: pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(width: 0.8, color: PdfColors.grey400))
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            if (logoImage != null)
              pw.Image(logoImage, width: 42, height: 42)
            else
              pw.Text('SEDS Logo', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey700)),
            
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('SEDS PORTAL SECURE AUDIT EXPORT', style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 2),
                pw.Text('Exported By: ${widget.userData.name} (${widget.userData.rollNumber})', style: pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
                pw.Text('Timestamp: $exportDateStr $exportTimeStr', style: pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600)),
                pw.Text('Scope: $reportScopeText', style: pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600)),
              ],
            ),
          ],
        ),
      );
    }

    // Build reusable footer block
    pw.Widget buildPageFooter(pw.Context context) {
      return pw.Container(
        margin: const pw.EdgeInsets.only(top: 5.0 * PdfPageFormat.mm),
        padding: const pw.EdgeInsets.only(top: 2.0 * PdfPageFormat.mm),
        decoration: pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(width: 0.5, color: PdfColors.grey300))
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Confidential - SEDS KCT internal data', style: pw.TextStyle(fontSize: 7, color: PdfColors.grey500)),
            pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
      );
    }

    // ──────────────── WORK LOGS PDF GENERATION ────────────────
    if (_selectedTopic == 'Work Logs' || _selectedTopic == 'Both') {
      // Chunk logs to fit neatly inside tables (e.g. 12 per page)
      const int logsPerPage = 12;
      for (int i = 0; i < logs.length; i += logsPerPage) {
        final chunk = logs.sublist(i, i + logsPerPage > logs.length ? logs.length : i + logsPerPage);

        pdf.addPage(
          pw.MultiPage(
            pageFormat: PdfPageFormat.a4.landscape, // landscape is wider for table columns
            header: buildPageHeader,
            footer: buildPageFooter,
            build: (pw.Context context) => [
              pw.Header(
                level: 0,
                child: pw.Text(
                  '$reportTopicTitle - Work Sessions Logs (Part ${((i / logsPerPage) + 1).toInt()})',
                  style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey800)
                ),
              ),
              pw.SizedBox(height: 6),
              pw.TableHelper.fromTextArray(
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                headers: ['Roll No', 'Name', 'Team', 'Date', 'Start', 'End', 'Duration', 'Summary / Activity'],
                data: chunk.map((log) {
                  final start = log['start_time'] != null ? DateTime.tryParse(log['start_time'].toString())?.toLocal() : null;
                  final stop = log['stop_time'] != null ? DateTime.tryParse(log['stop_time'].toString())?.toLocal() : null;
                  
                  final dateStr = start != null ? DateFormat('dd/MM/yyyy').format(start) : '';
                  final startStr = start != null ? DateFormat('HH:mm:ss').format(start) : '';
                  final stopStr = stop != null ? DateFormat('HH:mm:ss').format(stop) : (log['is_active'] == true ? 'ACTIVE' : '');
                  
                  // Duration format
                  String durStr = '0m';
                  if (log['duration_seconds'] != null) {
                    final sec = int.tryParse(log['duration_seconds']?.toString() ?? '') ?? 0;
                    final hr = sec ~/ 3600;
                    final min = (sec % 3600) ~/ 60;
                    durStr = hr > 0 ? '${hr}h ${min}m' : '${min}m';
                  }

                  return [
                    log['roll_number'] ?? '',
                    log['user_name'] ?? '',
                    log['team'] ?? '',
                    dateStr,
                    startStr,
                    stopStr,
                    durStr,
                    log['summary'] ?? '',
                  ];
                }).toList(),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8, color: PdfColors.white),
                headerDecoration: pw.BoxDecoration(color: PdfColors.blueGrey700),
                cellStyle: pw.TextStyle(fontSize: 7.5),
                columnWidths: {
                  0: const pw.FixedColumnWidth(55),
                  1: const pw.FixedColumnWidth(75),
                  2: const pw.FixedColumnWidth(55),
                  3: const pw.FixedColumnWidth(55),
                  4: const pw.FixedColumnWidth(45),
                  5: const pw.FixedColumnWidth(45),
                  6: const pw.FixedColumnWidth(45),
                  7: const pw.FlexColumnWidth(),
                },
              ),
            ],
          ),
        );
      }
    }

    // ──────────────── ATTENDANCE PDF GENERATION ────────────────
    if (_selectedTopic == 'Attendance' || _selectedTopic == 'Both') {
      const int attPerPage = 18;
      for (int i = 0; i < att.length; i += attPerPage) {
        final chunk = att.sublist(i, i + attPerPage > att.length ? att.length : i + attPerPage);

        pdf.addPage(
          pw.MultiPage(
            pageFormat: PdfPageFormat.a4, // Portrait is perfect for attendance list
            header: buildPageHeader,
            footer: buildPageFooter,
            build: (pw.Context context) => [
              pw.Header(
                level: 0,
                child: pw.Text(
                  '$reportTopicTitle - Team Attendance (Part ${((i / attPerPage) + 1).toInt()})',
                  style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo800)
                ),
              ),
              pw.SizedBox(height: 6),
              pw.TableHelper.fromTextArray(
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                headers: ['Roll Number', 'Name', 'Team', 'Meeting Date', 'Status', 'Remarks / Reason'],
                data: chunk.map((record) {
                  return [
                    record['roll_number'] ?? '',
                    record['name'] ?? '',
                    record['team'] ?? '',
                    record['date'] ?? '',
                    (record['status'] ?? '').toString().toUpperCase(),
                    record['reason'] ?? '',
                  ];
                }).toList(),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.white),
                headerDecoration: pw.BoxDecoration(color: PdfColors.indigo700),
                cellStyle: pw.TextStyle(fontSize: 8.5),
                columnWidths: {
                  0: const pw.FixedColumnWidth(70),
                  1: const pw.FixedColumnWidth(110),
                  2: const pw.FixedColumnWidth(70),
                  3: const pw.FixedColumnWidth(70),
                  4: const pw.FixedColumnWidth(70),
                  5: const pw.FlexColumnWidth(),
                },
              ),
            ],
          ),
        );
      }
    }

    return pdf.save();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Saving & Logging utilities
  // ─────────────────────────────────────────────────────────────────────────────
  Future<String> _saveStringToFile(String content, String filename) async {
    final dirPath = await _getExportDirectory();
    final file = File('$dirPath/$filename');
    await file.writeAsString(content);
    return file.path;
  }

  Future<String> _saveBytesToFile(Uint8List bytes, String filename) async {
    final dirPath = await _getExportDirectory();
    final file = File('$dirPath/$filename');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  Future<String> _getExportDirectory() async {
    if (Platform.isWindows) {
      final dir = await getDownloadsDirectory();
      if (dir != null) return dir.path;
    }
    if (Platform.isAndroid) {
      // Permission was already granted by _requestStoragePermission() before this is called
      const downloadsPath = '/storage/emulated/0/Download';
      final dir = Directory(downloadsPath);
      if (await dir.exists()) return downloadsPath;
      // Fallback to app external dir
      final extDir = await getExternalStorageDirectory();
      if (extDir != null) return extDir.path;
    }
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  Future<void> _logExportToDB({
    required String userEmail,
    required String rollNumber,
    required String fileExtension,
    required String scope,
    required String topic,
  }) async {
    try {
      await http.post(
        Uri.parse('$apiBaseUrl/api/exports/log'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_email': userEmail,
          'roll_number': rollNumber,
          'file_extension': fileExtension,
          'scope': scope,
          'topic': topic,
        }),
      );
    } catch (e) {
      debugPrint('Error logging export: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // UI triggers & feedback helpers
  // ─────────────────────────────────────────────────────────────────────────────
  void _showFileOpenDialog(String filePath) {
    final poppins = GoogleFonts.poppins;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF162544),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Export Successful! 📥',
          style: poppins(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your file has been exported successfully.',
              style: poppins(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Text(
              'Location:\n$filePath',
              style: poppins(color: Colors.cyanAccent, fontSize: 11),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close', style: poppins(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF9F43),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              Navigator.pop(context);
              try {
                final result = await OpenFile.open(filePath);
                if (!context.mounted) return;
                if (result.type != ResultType.done) {
                  AppToast.error(context, 'Could not open file: ${result.message}');
                }
              } catch (e) {
                if (context.mounted) AppToast.error(context, 'Could not open file: $e');
              }
            },
            child: Text('Open File', style: poppins(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Layout rendering
  // ─────────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final poppins = GoogleFonts.poppins;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background PNG setup
          Positioned.fill(
            child: Image.asset(
              'assets/background.png',
              fit: BoxFit.cover,
            ),
          ),
          // Dark overlays for premium contrast
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.45),
            ),
          ),
          
          // Main Scrollable Area
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 850),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Elegant Page Header Back Button and Title
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                            onPressed: () => Navigator.pop(context),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'EXPORT CENTER',
                                  style: poppins(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                                Text(
                                  'Secure CSV, Excel, and PDF Document Generation',
                                  style: poppins(
                                    fontSize: 12,
                                    color: Colors.white54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 24),

                      // Selection configuration Grid card
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: const Color(0xFF4DA6FF).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.18),
                            width: 1.2,
                          ),
                        ),
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '1. Configure Report Options',
                              style: poppins(color: const Color(0xFFFF9F43), fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            const SizedBox(height: 16),

                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Select Topic', style: poppins(color: Colors.white70, fontSize: 12)),
                                      const SizedBox(height: 6),
                                      _buildDropdown(
                                        value: _selectedTopic,
                                        items: _topics,
                                        onChanged: (val) {
                                          setState(() => _selectedTopic = val!);
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('File Format', style: poppins(color: Colors.white70, fontSize: 12)),
                                      const SizedBox(height: 6),
                                      _buildDropdown(
                                        value: _selectedFormat,
                                        items: _formats,
                                        onChanged: (val) {
                                          setState(() => _selectedFormat = val!);
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Role-based Access scope selector
                      if (widget.userData.role != 'Member') ...[
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: const Color(0xFF4DA6FF).withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.18),
                              width: 1.2,
                            ),
                          ),
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '2. Select Export Target Scope',
                                style: poppins(color: const Color(0xFFFF9F43), fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              const SizedBox(height: 16),

                              // Toggle buttons for scoping
                              Row(
                                children: [
                                  _buildScopeToggleOption('Self', Icons.person_outline_rounded),
                                  const SizedBox(width: 10),
                                  _buildScopeToggleOption('Team', Icons.group_outlined),
                                  const SizedBox(width: 10),
                                  _buildScopeToggleOption('Specific Member', Icons.person_search_outlined),
                                ],
                              ),

                              const SizedBox(height: 20),

                              // Scope Options Rendering
                              if (_selectedScope == 'Self') ...[
                                Text(
                                  'Only your own logs/attendance details will be exported.',
                                  style: poppins(color: Colors.white54, fontSize: 13, fontStyle: FontStyle.italic),
                                ),
                              ] 
                              else if (_selectedScope == 'Team') ...[
                                if (widget.userData.role == 'Admin') ...[
                                  Text('Select target team:', style: poppins(color: Colors.white70, fontSize: 12)),
                                  const SizedBox(height: 8),
                                  _buildDropdown(
                                    value: _selectedTeamFilter ?? 'All',
                                    items: ['All', ..._sedsTeams],
                                    onChanged: (val) {
                                      setState(() {
                                        _selectedTeamFilter = val;
                                        _filterUsers();
                                      });
                                    },
                                  ),
                                ] else ...[
                                  Text(
                                    'Export all members belonging to team: ${widget.userData.team}',
                                    style: poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                ]
                              ] 
                              else if (_selectedScope == 'Specific Member') ...[
                                // Admin Filter selections
                                if (widget.userData.role == 'Admin') ...[
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('Filter Team', style: poppins(color: Colors.white70, fontSize: 11)),
                                            const SizedBox(height: 4),
                                            _buildDropdown(
                                              value: _selectedTeamFilter ?? 'All',
                                              items: ['All', ..._sedsTeams],
                                              onChanged: (val) {
                                                setState(() {
                                                  _selectedTeamFilter = val;
                                                  _filterUsers();
                                                });
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('Filter Role', style: poppins(color: Colors.white70, fontSize: 11)),
                                            const SizedBox(height: 4),
                                            _buildDropdown(
                                              value: _selectedRoleFilter ?? 'All Roles',
                                              items: const ['All Roles', 'Leads Only', 'Members Only'],
                                              onChanged: (val) {
                                                setState(() {
                                                  _selectedRoleFilter = val;
                                                  _filterUsers();
                                                });
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                ],

                                // Search Field
                                TextField(
                                  onChanged: (val) {
                                    _memberSearchQuery = val;
                                    _filterUsers();
                                  },
                                  style: poppins(color: Colors.white, fontSize: 13),
                                  decoration: InputDecoration(
                                    hintText: 'Search by name or roll number...',
                                    hintStyle: poppins(color: Colors.white38),
                                    prefixIcon: const Icon(Icons.search_rounded, color: Colors.white38),
                                    filled: true,
                                    fillColor: const Color(0xFF1E2E4A).withValues(alpha: 0.6),
                                    contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(color: Colors.white12),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(color: Colors.white12),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(color: Color(0xFFFF9F43)),
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 12),

                                // Choice selection list
                                if (_isLoadingUsers) ...[
                                  const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(16.0),
                                      child: CircularProgressIndicator(color: Color(0xFFFF9F43)),
                                    ),
                                  )
                                ] else if (_filteredUsersList.isEmpty) ...[
                                  Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Text(
                                      'No matching users found.',
                                      style: poppins(color: Colors.white38, fontSize: 13),
                                    ),
                                  )
                                ] else ...[
                                  Container(
                                    height: 200,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1E2E4A).withValues(alpha: 0.4),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.white10),
                                    ),
                                    child: RawScrollbar(
                                      thumbVisibility: true,
                                      thumbColor: const Color(0xFF4DA6FF).withValues(alpha: 0.5),
                                      radius: const Radius.circular(4),
                                      child: ListView.builder(
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      itemCount: _filteredUsersList.length,
                                      itemBuilder: (context, idx) {
                                        final user = _filteredUsersList[idx];
                                        final isChosen = _selectedSpecificMember != null &&
                                            _selectedSpecificMember['email'] == user['email'];
                                        
                                        return ListTile(
                                          dense: true,
                                          selected: isChosen,
                                          selectedTileColor: const Color(0xFFFF9F43).withValues(alpha: 0.15),
                                          title: Text(
                                            user['name'] ?? '',
                                            style: poppins(
                                              color: isChosen ? const Color(0xFFFF9F43) : Colors.white,
                                              fontWeight: isChosen ? FontWeight.bold : FontWeight.normal,
                                              fontSize: 13,
                                            ),
                                          ),
                                          subtitle: Text(
                                            'Roll: ${user['roll_number']} | Team: ${user['team']} | Role: ${user['role']}',
                                            style: poppins(color: Colors.white54, fontSize: 11),
                                          ),
                                          trailing: isChosen 
                                              ? const Icon(Icons.check_circle_rounded, color: Color(0xFFFF9F43), size: 18)
                                              : null,
                                          onTap: () {
                                            setState(() {
                                              _selectedSpecificMember = user;
                                            });
                                          },
                                        );
                                      },
                                    ),
                                  ),
                                  ),
                                ],
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // Disclaimer & Audit Notice
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFB347).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFFB347).withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.security_rounded, color: Color(0xFFFFB347), size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Notice: All exports are cryptographically logged with your account details (Email, Roll No, Time, IP, Scope) for audit trails and compliance reports.',
                                style: poppins(color: Colors.white70, fontSize: 11.5, height: 1.4),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 28),

                      // Generate Export Button
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF9F43),
                            foregroundColor: Colors.white,
                            elevation: 8,
                            shadowColor: const Color(0xFFFF9F43).withValues(alpha: 0.4),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          icon: const Icon(Icons.document_scanner_rounded, size: 22),
                          label: Text(
                            'COMPILE & EXPORT DATA',
                            style: poppins(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1.2, color: Colors.white),
                          ),
                          onPressed: _isExporting ? null : _handleExport,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Custom visual loading progress overlay
          if (_isExporting)
            Positioned.fill(
              child: Container(
                color: Colors.black87,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(
                          color: Color(0xFFFF9F43),
                          strokeWidth: 4.5,
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'GENERATING REPORT',
                          style: poppins(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.0,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _exportStatusText,
                          textAlign: TextAlign.center,
                          style: poppins(color: Colors.white54, fontSize: 12),
                        ),
                        const SizedBox(height: 20),
                        // Linear progress indicator
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: _exportProgress,
                            minHeight: 4,
                            backgroundColor: Colors.white10,
                            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFF9F43)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Helper scopes builder
  Widget _buildScopeToggleOption(String scope, IconData icon) {
    final poppins = GoogleFonts.poppins;
    final isSelected = _selectedScope == scope;
    
    // Check if user has permission for this scope
    bool hasPermission = true;
    if (widget.userData.role == 'Member' && scope != 'Self') {
      hasPermission = false;
    }

    if (!hasPermission) return const SizedBox.shrink();

    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedScope = scope;
            _selectedSpecificMember = null;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected 
                ? const Color(0xFFFF9F43).withValues(alpha: 0.15)
                : const Color(0xFF1E2E4A).withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? const Color(0xFFFF9F43) : Colors.white10,
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: isSelected ? const Color(0xFFFF9F43) : Colors.white60, size: 20),
              const SizedBox(height: 6),
              Text(
                scope,
                textAlign: TextAlign.center,
                style: poppins(
                  color: isSelected ? const Color(0xFFFF9F43) : Colors.white70,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Helper dropdown builder
  Widget _buildDropdown({
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    final poppins = GoogleFonts.poppins;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2E4A).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: const Color(0xFF162544),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white54),
          style: poppins(color: Colors.white, fontSize: 13),
          items: items.map((e) {
            return DropdownMenuItem<String>(
              value: e,
              child: Text(e),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
