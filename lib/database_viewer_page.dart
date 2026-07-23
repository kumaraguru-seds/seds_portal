import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'main.dart'; // For UserData, DesktopPageWrapper, apiBaseUrl
import 'app_toast.dart';

class DatabaseViewerPage extends StatefulWidget {
  final UserData userData;

  const DatabaseViewerPage({super.key, required this.userData});

  @override
  State<DatabaseViewerPage> createState() => _DatabaseViewerPageState();
}

class _DatabaseViewerPageState extends State<DatabaseViewerPage> {
  // DB list & selection state
  Map<String, dynamic> _databases = {};
  String? _selectedDb;
  String? _selectedTable;
  bool _isLoadingMeta = false;

  // Query results state
  List<dynamic> _columns = [];
  List<dynamic> _rows = [];
  bool _isLoadingQuery = false;
  int _totalRows = 0;
  int _currentPage = 1;
  final int _rowsLimit = 50;
  int? _selectedRowIndex; // Track selected/touched row index for glowing highlight

  // Zoom & fullscreen state
  final TransformationController _transformCtrl = TransformationController();
  double _currentScale = 1.0;
  static const double _minScale = 0.5;
  static const double _maxScale = 4.0;
  static const double _zoomStep = 0.25;
  bool _isFullscreen = false;

  // Search
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  // Scrollbar controllers
  final ScrollController _verticalScrollCtrl = ScrollController();
  final ScrollController _horizontalScrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _fetchMetadata();
    _transformCtrl.addListener(_onTransformChanged);
  }

  @override
  void dispose() {
    _transformCtrl.removeListener(_onTransformChanged);
    _transformCtrl.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _verticalScrollCtrl.dispose();
    _horizontalScrollCtrl.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    final scale = _transformCtrl.value.getMaxScaleOnAxis();
    if ((scale - _currentScale).abs() > 0.01) {
      setState(() => _currentScale = scale);
    }
  }

  void _zoomIn() {
    final newScale = (_currentScale + _zoomStep).clamp(_minScale, _maxScale);
    _applyScale(newScale);
  }

  void _zoomOut() {
    final newScale = (_currentScale - _zoomStep).clamp(_minScale, _maxScale);
    _applyScale(newScale);
  }

  void _resetZoom() {
    _transformCtrl.value = Matrix4.identity();
    setState(() => _currentScale = 1.0);
  }

  void _applyScale(double newScale) {
    // Build a uniform-scale matrix and apply it
    final m = Matrix4.diagonal3Values(newScale, newScale, 1.0);
    _transformCtrl.value = m;
    setState(() => _currentScale = newScale);
  }

  // ── Detect primary key column from loaded columns ─────────────
  String _detectPrimaryKey() {
    // Prefer 'id' column, then first column with 'integer' or 'serial' type
    for (final col in _columns) {
      if (col['column_name']?.toString().toLowerCase() == 'id') {
        return col['column_name'].toString();
      }
    }
    // Fallback to first integer column
    for (final col in _columns) {
      final dt = col['data_type']?.toString().toLowerCase() ?? '';
      if (dt.contains('int') || dt.contains('serial')) {
        return col['column_name'].toString();
      }
    }
    // Last resort: first column
    if (_columns.isNotEmpty) return _columns.first['column_name'].toString();
    return 'id';
  }

  // ── Fetch metadata ──────────────────────────────────────────────
  Future<void> _fetchMetadata() async {
    setState(() => _isLoadingMeta = true);
    try {
      final res = await http.get(Uri.parse('$apiBaseUrl/api/admin/databases/metadata'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && data['databases'] != null) {
          setState(() {
            _databases = Map<String, dynamic>.from(data['databases']);
            if (_databases.isNotEmpty) {
              _selectedDb = _databases.keys.first;
              final list = _databases[_selectedDb];
              if (list is List && list.isNotEmpty) {
                _selectedTable = list.first.toString();
              }
            }
          });
          if (_selectedDb != null && _selectedTable != null) {
            _executeQuery();
          }
        } else {
          if (mounted) AppToast.error(context, 'Failed to retrieve database metadata.');
        }
      } else {
        if (mounted) AppToast.error(context, 'Server error fetching database metadata.');
      }
    } catch (e) {
      debugPrint('Metadata error: $e');
      if (mounted) AppToast.error(context, 'Network error loading databases.');
    } finally {
      if (mounted) setState(() => _isLoadingMeta = false);
    }
  }

  // ── Execute query ───────────────────────────────────────────────
  Future<void> _executeQuery({bool resetPage = true}) async {
    if (_selectedDb == null || _selectedTable == null) return;
    if (resetPage) _currentPage = 1;
    setState(() => _isLoadingQuery = true);
    try {
      final res = await http.post(
        Uri.parse('$apiBaseUrl/api/admin/databases/query'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'database': _selectedDb,
          'table': _selectedTable,
          'searchQuery': _searchController.text,
          'page': _currentPage,
          'limit': _rowsLimit,
        }),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true) {
          setState(() {
            _columns = data['columns'] ?? [];
            _rows = data['rows'] ?? [];
            _totalRows = data['total'] ?? 0;
            _selectedRowIndex = null;
          });
        } else {
          if (mounted) AppToast.error(context, data['message'] ?? 'Query execution failed.');
        }
      } else {
        if (mounted) AppToast.error(context, 'Server error executing database query.');
      }
    } catch (e) {
      debugPrint('Query error: $e');
      if (mounted) AppToast.error(context, 'Network error loading table data.');
    } finally {
      if (mounted) setState(() => _isLoadingQuery = false);
    }
  }

  // ── Add Row API call ─────────────────────────────────────────────
  Future<void> _addRow(Map<String, String> data) async {
    if (_selectedDb == null || _selectedTable == null) return;
    try {
      final res = await http.post(
        Uri.parse('$apiBaseUrl/api/admin/databases/row/add'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'database': _selectedDb,
          'table': _selectedTable,
          'data': _normalizeRowData(data),
        }),
      );
      final body = jsonDecode(res.body);
      if (res.statusCode == 200 && body['success'] == true) {
        if (mounted) AppToast.success(context, body['message'] ?? 'Row added!');
        _executeQuery(resetPage: false);
      } else {
        if (mounted) AppToast.error(context, body['message'] ?? 'Failed to add row.');
      }
    } catch (e) {
      if (mounted) AppToast.error(context, 'Network error adding row.');
    }
  }

  // ── Update Row API call ──────────────────────────────────────────
  Future<void> _updateRow(String pkCol, dynamic pkVal, Map<String, String> data) async {
    if (_selectedDb == null || _selectedTable == null) return;
    try {
      final res = await http.put(
        Uri.parse('$apiBaseUrl/api/admin/databases/row/update'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'database': _selectedDb,
          'table': _selectedTable,
          'primaryKey': pkCol,
          'primaryKeyValue': pkVal,
          'data': _normalizeRowData(data),
        }),
      );
      final body = jsonDecode(res.body);
      if (res.statusCode == 200 && body['success'] == true) {
        if (mounted) AppToast.success(context, body['message'] ?? 'Row updated!');
        _executeQuery(resetPage: false);
      } else {
        if (mounted) AppToast.error(context, body['message'] ?? 'Failed to update row.');
      }
    } catch (e) {
      if (mounted) AppToast.error(context, 'Network error updating row.');
    }
  }

  // ── Delete Row API call ──────────────────────────────────────────
  Future<void> _deleteRow(String pkCol, dynamic pkVal) async {
    if (_selectedDb == null || _selectedTable == null) return;
    try {
      final req = http.Request('DELETE', Uri.parse('$apiBaseUrl/api/admin/databases/row/delete'));
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode({
        'database': _selectedDb,
        'table': _selectedTable,
        'primaryKey': pkCol,
        'primaryKeyValue': pkVal,
      });
      final streamed = await req.send();
      final resBody = await streamed.stream.bytesToString();
      final body = jsonDecode(resBody);
      if (streamed.statusCode == 200 && body['success'] == true) {
        if (mounted) AppToast.success(context, body['message'] ?? 'Row deleted!');
        _executeQuery(resetPage: false);
      } else {
        if (mounted) AppToast.error(context, body['message'] ?? 'Failed to delete row.');
      }
    } catch (e) {
      if (mounted) AppToast.error(context, 'Network error deleting row.');
    }
  }

  // ── Show Add Row Dialog ──────────────────────────────────────────
  void _showAddRowDialog() {
    if (_columns.isEmpty) {
      AppToast.error(context, 'No columns loaded. Select a table first.');
      return;
    }

    final poppins = GoogleFonts.poppins;
    final controllers = <String, TextEditingController>{};
    // Skip auto-increment columns (typically 'id' with serial/int type)
    final editableCols = _columns.where((col) {
      final name = col['column_name']?.toString().toLowerCase() ?? '';
      final dtype = col['data_type']?.toString().toLowerCase() ?? '';
      // Skip 'id' if it's integer/serial (likely auto-increment)
      if (name == 'id' && (dtype.contains('int') || dtype.contains('serial'))) return false;
      return true;
    }).toList();

    for (final col in editableCols) {
      controllers[col['column_name'].toString()] = TextEditingController();
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(ctx).size.height * 0.8,
          decoration: const BoxDecoration(
            color: Color(0xFF0D1E3A),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Handle bar
              const SizedBox(height: 12),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 16),
              Text('Add New Row', style: poppins(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              Text('$_selectedDb → $_selectedTable', style: poppins(fontSize: 12, color: Colors.white38)),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: editableCols.length,
                  itemBuilder: (context, index) {
                    final col = editableCols[index];
                    final colName = col['column_name'].toString();
                    final colType = col['data_type']?.toString() ?? '';
                    final isDate = colType.contains('timestamp') || colType.contains('date') || colType.contains('time') || colName.contains('time') || colName.contains('date') || colName.contains('_at');
                    final hintText = isDate ? 'yyyy-MM-dd HH:mm:ss (e.g. 2026-07-22 03:42:08)' : colType;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextField(
                        controller: controllers[colName],
                        style: poppins(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          labelText: colName,
                          labelStyle: poppins(color: const Color(0xFF4DA6FF), fontSize: 12, fontWeight: FontWeight.bold),
                          hintText: hintText,
                          hintStyle: poppins(color: Colors.white24, fontSize: 11),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.05),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white12)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white12)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF4DA6FF))),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: const BorderSide(color: Colors.white24),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: () => Navigator.pop(ctx),
                        child: Text('Cancel', style: poppins(fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00E676),
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: () {
                          final data = <String, String>{};
                          for (final entry in controllers.entries) {
                            if (entry.value.text.isNotEmpty) {
                              data[entry.key] = entry.value.text;
                            }
                          }
                          if (data.isEmpty) {
                            AppToast.error(ctx, 'Fill at least one field.');
                            return;
                          }
                          Navigator.pop(ctx);
                          _addRow(data);
                        },
                        child: Text('Add Row', style: poppins(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Show Edit Row Dialog ─────────────────────────────────────────
  void _showEditRowDialog(Map<String, dynamic> row) {
    final poppins = GoogleFonts.poppins;
    final pkCol = _detectPrimaryKey();
    final pkVal = row[pkCol];
    final controllers = <String, TextEditingController>{};

    for (final col in _columns) {
      final colName = col['column_name'].toString();
      final rawVal = row[colName]?.toString() ?? '';
      final colType = col['data_type']?.toString().toLowerCase() ?? '';

      String initialText = rawVal;
      if (rawVal.isNotEmpty &&
          (colType.contains('timestamp') || colType.contains('date') || colType.contains('time') ||
           colName.contains('time') || colName.contains('date') || colName.contains('_at') ||
           rawVal.contains('T') || RegExp(r'^\d{4}[-/]\d{1,2}[-/]\d{1,2}').hasMatch(rawVal))) {
        initialText = _formatDateTimeDisplay(rawVal);
      }
      controllers[colName] = TextEditingController(text: initialText);
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(ctx).size.height * 0.85,
          decoration: const BoxDecoration(
            color: Color(0xFF0D1E3A),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 16),
              Text('Edit Row', style: poppins(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              Text('$pkCol: $pkVal', style: poppins(fontSize: 12, color: const Color(0xFF4DA6FF))),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: _columns.length,
                  itemBuilder: (context, index) {
                    final col = _columns[index];
                    final colName = col['column_name'].toString();
                    final colType = col['data_type']?.toString() ?? '';
                    final isPk = colName == pkCol;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextField(
                        controller: controllers[colName],
                        readOnly: isPk,
                        style: poppins(color: isPk ? Colors.white38 : Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          labelText: '$colName${isPk ? ' (PK — read only)' : ''}',
                          labelStyle: poppins(color: isPk ? Colors.orangeAccent : const Color(0xFF4DA6FF), fontSize: 12, fontWeight: FontWeight.bold),
                          hintText: colType,
                          hintStyle: poppins(color: Colors.white24, fontSize: 11),
                          filled: true,
                          fillColor: isPk ? Colors.white.withValues(alpha: 0.02) : Colors.white.withValues(alpha: 0.05),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white12)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isPk ? Colors.orangeAccent.withValues(alpha: 0.3) : Colors.white12)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isPk ? Colors.orangeAccent : const Color(0xFF4DA6FF))),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: const BorderSide(color: Colors.white24),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: () => Navigator.pop(ctx),
                        child: Text('Cancel', style: poppins(fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4DA6FF),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: () {
                          final data = <String, String>{};
                          for (final col in _columns) {
                            final colName = col['column_name'].toString();
                            if (colName == pkCol) continue; // skip PK
                            final newVal = controllers[colName]?.text ?? '';
                            data[colName] = newVal;
                          }
                          Navigator.pop(ctx);
                          _updateRow(pkCol, pkVal, data);
                        },
                        child: Text('Save Changes', style: poppins(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Show Delete Confirmation Dialog ──────────────────────────────
  void _showDeleteConfirmDialog(Map<String, dynamic> row) {
    final poppins = GoogleFonts.poppins;
    final pkCol = _detectPrimaryKey();
    final pkVal = row[pkCol];

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0D1E3A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 28),
              const SizedBox(width: 10),
              Text('Delete Row?', style: poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('This will permanently remove this row:', style: poppins(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Database: $_selectedDb', style: poppins(color: Colors.white54, fontSize: 11)),
                    Text('Table: $_selectedTable', style: poppins(color: Colors.white54, fontSize: 11)),
                    const SizedBox(height: 4),
                    Text('$pkCol: $pkVal', style: poppins(color: Colors.redAccent, fontSize: 14, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: poppins(color: Colors.white54, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                _deleteRow(pkCol, pkVal);
              },
              child: Text('Delete', style: poppins(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  // ────────────────────────── BUILD ──────────────────────────
  @override
  Widget build(BuildContext context) {
    final poppins = GoogleFonts.poppins;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background
          Positioned.fill(
            child: Image.asset('assets/background.png', fit: BoxFit.cover),
          ),
          Positioned.fill(
            child: Container(color: Colors.black.withValues(alpha: 0.45)),
          ),

          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ──
                _buildHeader(poppins),

                // ── Controls card ──
                _buildControlsCard(poppins),

                // ── Table area (normal or fullscreen) ──
                _isFullscreen
                    ? Expanded(child: _buildFullscreenTable(poppins))
                    : Expanded(child: _buildNormalTable(poppins)),

                // ── Pagination ──
                if (!_isFullscreen) _buildPagination(poppins),
              ],
            ),
          ),
        ],
      ),
      // FAB for adding rows (Bottom Center)
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: (_selectedTable != null && _columns.isNotEmpty && !_isFullscreen)
          ? FloatingActionButton.extended(
              backgroundColor: const Color(0xFF00E676),
              elevation: 6,
              onPressed: _showAddRowDialog,
              icon: const Icon(Icons.add_rounded, color: Colors.black, size: 24),
              label: Text(
                'Add Row',
                style: GoogleFonts.poppins(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            )
          : null,
    );
  }

  // ── Header ──────────────────────────────────────────────────
  Widget _buildHeader(TextStyle Function({Color? color, double? fontSize, FontWeight? fontWeight, double? letterSpacing}) poppins) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
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
                  'DATABASE VIEWER',
                  style: poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 1.2,
                  ),
                ),
                Text(
                  'AWS SEDS Portal Real-time Database Inspector',
                  style: poppins(fontSize: 11, color: Colors.white54),
                ),
              ],
            ),
          ),
          if (_isLoadingMeta || _isLoadingQuery)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(color: Color(0xFF4DA6FF), strokeWidth: 2.5),
            ),
        ],
      ),
    );
  }

  // ── Controls card (dropdowns + search + zoom) ────────────────
  Widget _buildControlsCard(TextStyle Function({Color? color, double? fontSize, FontWeight? fontWeight, double? letterSpacing}) poppins) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Container(
        padding: const EdgeInsets.all(14.0),
        decoration: BoxDecoration(
          color: const Color(0xFF4DA6FF).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18), width: 1.2),
        ),
        child: Column(
          children: [
            // DB & Table dropdowns
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('SELECT DATABASE',
                          style: poppins(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      _buildDropdown(
                        value: _selectedDb,
                        items: _databases.keys.toList(),
                        onChanged: (val) {
                          setState(() {
                            _selectedDb = val;
                            _selectedTable = null;
                            final list = _databases[_selectedDb];
                            if (list is List && list.isNotEmpty) {
                              _selectedTable = list.first.toString();
                            }
                            _rows.clear();
                            _columns.clear();
                          });
                          _executeQuery();
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
                      Text('SELECT TABLE',
                          style: poppins(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      _buildDropdown(
                        value: _selectedTable,
                        items: _selectedDb != null && _databases[_selectedDb] is List
                            ? List<String>.from(_databases[_selectedDb]!.map((e) => e.toString()))
                            : [],
                        onChanged: (val) {
                          setState(() {
                            _selectedTable = val;
                            _rows.clear();
                            _columns.clear();
                          });
                          _executeQuery();
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Search + zoom row
            Row(
              children: [
                // Search field
                Expanded(
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.black38,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      style: poppins(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Search text columns...',
                        hintStyle: poppins(color: Colors.white30, fontSize: 12),
                        prefixIcon: const Icon(Icons.search, color: Colors.white30, size: 18),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onSubmitted: (_) => _executeQuery(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Run button
                SizedBox(
                  height: 44,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4DA6FF),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => _executeQuery(),
                    child: const Icon(Icons.send_rounded, size: 18),
                  ),
                ),
                const SizedBox(width: 8),
                // Zoom Out
                _buildIconBtn(Icons.zoom_out_rounded, _currentScale <= _minScale ? null : _zoomOut, 'Zoom Out'),
                const SizedBox(width: 4),
                // Zoom reset label
                GestureDetector(
                  onTap: _resetZoom,
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white10),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${(_currentScale * 100).round()}%',
                      style: poppins(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // Zoom In
                _buildIconBtn(Icons.zoom_in_rounded, _currentScale >= _maxScale ? null : _zoomIn, 'Zoom In'),
                const SizedBox(width: 4),
                // Maximize / Minimize
                _buildIconBtn(
                  _isFullscreen ? Icons.close_fullscreen_rounded : Icons.open_in_full_rounded,
                  () => setState(() => _isFullscreen = !_isFullscreen),
                  _isFullscreen ? 'Minimize View' : 'Maximize View',
                  accent: _isFullscreen ? Colors.redAccent : const Color(0xFF4DA6FF),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Normal table area ─────────────────────────────────────────
  Widget _buildNormalTable(TextStyle Function({Color? color, double? fontSize, FontWeight? fontWeight, double? letterSpacing}) poppins) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFF0D1C33).withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: _buildTableContent(poppins),
        ),
      ),
    );
  }

  // ── Fullscreen table area ─────────────────────────────────────
  Widget _buildFullscreenTable(TextStyle Function({Color? color, double? fontSize, FontWeight? fontWeight, double? letterSpacing}) poppins) {
    return Stack(
      children: [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFF0D1C33).withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF4DA6FF).withValues(alpha: 0.4), width: 1.5),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: _buildTableContent(poppins),
          ),
        ),
        // Floating minimize button
        Positioned(
          top: 12,
          right: 24,
          child: GestureDetector(
            onTap: () => setState(() => _isFullscreen = false),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.close_fullscreen_rounded, color: Colors.white, size: 14),
                  const SizedBox(width: 4),
                  Text('Minimize', style: GoogleFonts.poppins(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ),
        // Pagination inside fullscreen
        Positioned(
          bottom: 6,
          left: 24,
          right: 24,
          child: _buildPagination(poppins),
        ),
      ],
    );
  }

  // ── Pagination ────────────────────────────────────────────────
  Widget _buildPagination(TextStyle Function({Color? color, double? fontSize, FontWeight? fontWeight, double? letterSpacing}) poppins) {
    final totalPages = _totalRows > 0 ? ((_totalRows - 1) / _rowsLimit).floor() + 1 : 1;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Total: $_totalRows rows', style: poppins(color: Colors.white54, fontSize: 12)),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white, size: 16),
                onPressed: _currentPage > 1 && !_isLoadingQuery
                    ? () {
                        setState(() => _currentPage--);
                        _executeQuery(resetPage: false);
                      }
                    : null,
              ),
              Text(
                'Page $_currentPage / $totalPages',
                style: poppins(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 16),
                onPressed: _currentPage < totalPages && !_isLoadingQuery
                    ? () {
                        setState(() => _currentPage++);
                        _executeQuery(resetPage: false);
                      }
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Table content with scrollbars + InteractiveViewer ──────────
  Widget _buildTableContent(TextStyle Function({Color? color, double? fontSize, FontWeight? fontWeight, double? letterSpacing}) poppins) {
    if (_isLoadingQuery && _rows.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF4DA6FF)));
    }
    if (_selectedTable == null) {
      return Center(
        child: Text('Select a Database and Table to inspect details',
            style: poppins(color: Colors.white38, fontSize: 13)),
      );
    }
    if (_columns.isEmpty) {
      return Center(
        child: Text('No columns found or schema error.', style: poppins(color: Colors.white38, fontSize: 13)),
      );
    }
    if (_rows.isEmpty) {
      return Center(
        child: Text('Table contains 0 matching rows.', style: poppins(color: Colors.white38, fontSize: 13)),
      );
    }

    // Proper scrollable + zoomable table with always-visible scrollbars:
    return InteractiveViewer(
      transformationController: _transformCtrl,
      minScale: _minScale,
      maxScale: _maxScale,
      constrained: true,
      scaleEnabled: true,
      panEnabled: true,
      child: Scrollbar(
        controller: _verticalScrollCtrl,
        thumbVisibility: true,
        trackVisibility: true,
        thickness: 8,
        radius: const Radius.circular(4),
        child: SingleChildScrollView(
          controller: _verticalScrollCtrl,
          scrollDirection: Axis.vertical,
          physics: const BouncingScrollPhysics(),
          child: Scrollbar(
            controller: _horizontalScrollCtrl,
            thumbVisibility: true,
            trackVisibility: true,
            thickness: 8,
            radius: const Radius.circular(4),
            notificationPredicate: (notification) => notification.depth == 0,
            child: SingleChildScrollView(
              controller: _horizontalScrollCtrl,
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(const Color(0xFF1E3A63).withValues(alpha: 0.9)),
                dataRowColor: WidgetStateProperty.resolveWith<Color>((states) {
                  if (states.contains(WidgetState.selected)) {
                    return const Color(0xFF4DA6FF).withValues(alpha: 0.15);
                  }
                  return Colors.black.withValues(alpha: 0.1);
                }),
                horizontalMargin: 16,
                columnSpacing: 24,
                headingRowHeight: 42,
                dataRowMinHeight: 38,
                dataRowMaxHeight: 56,
                columns: [
                  // Actions column header
                  DataColumn(
                    label: Text(
                      'ACTIONS',
                      style: poppins(
                        color: Colors.orangeAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  ..._columns.map((col) {
                    return DataColumn(
                      label: Text(
                        col['column_name'].toString().toUpperCase(),
                        style: poppins(
                          color: const Color(0xFF4DA6FF),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    );
                  }),
                ],
                rows: _rows.asMap().entries.map((entry) {
                  final rowIndex = entry.key;
                  final row = entry.value;
                  final rowMap = Map<String, dynamic>.from(row);
                  final isSelected = _selectedRowIndex == rowIndex;

                  return DataRow(
                    selected: isSelected,
                    onSelectChanged: (selected) {
                      setState(() {
                        _selectedRowIndex = (selected == true) ? rowIndex : null;
                      });
                    },
                    color: WidgetStateProperty.resolveWith<Color>((states) {
                      if (isSelected) {
                        return const Color(0xFF4DA6FF).withValues(alpha: 0.35);
                      }
                      return rowIndex % 2 == 0
                          ? Colors.black.withValues(alpha: 0.2)
                          : Colors.black.withValues(alpha: 0.08);
                    }),
                    cells: [
                      // Actions cell: edit + delete buttons
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            InkWell(
                              onTap: () => _showEditRowDialog(rowMap),
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF4DA6FF).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Icon(Icons.edit_rounded, color: Color(0xFF4DA6FF), size: 16),
                              ),
                            ),
                            const SizedBox(width: 6),
                            InkWell(
                              onTap: () => _showDeleteConfirmDialog(rowMap),
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.redAccent.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 16),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Data cells
                      ..._columns.map((col) {
                        final columnName = col['column_name'];
                        final rawVal = row[columnName];
                        final displayVal = rawVal == null ? 'NULL' : _formatCellValue(rawVal.toString());
                        return DataCell(
                          Text(
                            displayVal,
                            style: poppins(
                              color: isSelected
                                  ? const Color(0xFF00E676)
                                  : (rawVal == null ? Colors.white30 : Colors.white),
                              fontSize: 12.0,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            ),
                          ),
                          onTap: () {
                            setState(() {
                              _selectedRowIndex = isSelected ? null : rowIndex;
                            });
                          },
                        );
                      }),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Format cell values — convert UTC ISO timestamps to local time ──
  String _formatCellValue(String? raw) {
    if (raw == null || raw.isEmpty) return 'NULL';
    final trimmed = raw.trim();
    if (trimmed.length >= 10 &&
        (trimmed.contains('T') || RegExp(r'^\d{4}[-/]\d{1,2}[-/]\d{1,2}').hasMatch(trimmed))) {
      return _formatDateTimeDisplay(trimmed);
    }
    return trimmed;
  }

  // ── Date/Time helper: format raw DB timestamp explicitly to IST (`yyyy-MM-dd HH:mm:ss`) ──
  String _formatDateTimeDisplay(String? raw) {
    if (raw == null || raw.isEmpty) return 'NULL';
    final trimmed = raw.trim();

    DateTime? dt;
    if (trimmed.contains('T') || RegExp(r'^\d{4}[-/]\d{1,2}[-/]\d{1,2}').hasMatch(trimmed)) {
      if (trimmed.endsWith('Z') || trimmed.contains('+')) {
        // Explicit UTC -> IST (+05:30)
        dt = DateTime.tryParse(trimmed)?.toUtc().add(const Duration(hours: 5, minutes: 30));
      } else if (trimmed.contains('T') && !trimmed.contains('+')) {
        // Postgres ISO string without Z flag (e.g. 2026-07-21T12:07:52.532)
        dt = DateTime.tryParse('${trimmed}Z')?.toUtc().add(const Duration(hours: 5, minutes: 30));
      } else {
        final parsed = DateTime.tryParse(_normalizeDateTime(trimmed) ?? trimmed);
        if (parsed != null) {
          dt = parsed.isUtc ? parsed.add(const Duration(hours: 5, minutes: 30)) : parsed.toLocal();
        }
      }
    }

    if (dt != null) {
      return DateFormat('yyyy-MM-dd HH:mm:ss').format(dt);
    }

    return trimmed;
  }

  // ── Date/Time helper: normalize user inputs like '2026-07-22 03:42:8' into 'yyyy-MM-dd HH:mm:ss' ──
  String? _normalizeDateTime(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    final match = RegExp(r'^(\d{4})[-/](\d{1,2})[-/](\d{1,2})(?:[ T](\d{1,2}):(\d{1,2})(?::(\d{1,2}))?)?').firstMatch(trimmed);
    if (match != null) {
      final year = match.group(1)!;
      final month = match.group(2)!.padLeft(2, '0');
      final day = match.group(3)!.padLeft(2, '0');
      final hour = (match.group(4) ?? '00').padLeft(2, '0');
      final minute = (match.group(5) ?? '00').padLeft(2, '0');
      final second = (match.group(6) ?? '00').padLeft(2, '0');
      return '$year-$month-$day $hour:$minute:$second';
    }

    final dt = DateTime.tryParse(trimmed);
    if (dt != null) {
      return DateFormat('yyyy-MM-dd HH:mm:ss').format(dt.toLocal());
    }

    return null;
  }

  Map<String, String> _normalizeRowData(Map<String, String> data) {
    final normalizedMap = <String, String>{};
    for (final entry in data.entries) {
      final val = entry.value;
      if (val.isNotEmpty && RegExp(r'^\d{4}[-/]\d{1,2}[-/]\d{1,2}').hasMatch(val)) {
        final norm = _normalizeDateTime(val);
        normalizedMap[entry.key] = norm ?? val;
      } else {
        normalizedMap[entry.key] = val;
      }
    }
    return normalizedMap;
  }

  // ── Shared widget builders ────────────────────────────────────
  Widget _buildDropdown({
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.black38,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          dropdownColor: const Color(0xFF162544),
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF4DA6FF)),
          items: items.map((String val) {
            return DropdownMenuItem<String>(
              value: val,
              child: Text(
                val,
                style: GoogleFonts.poppins(fontSize: 13, color: Colors.white, fontWeight: FontWeight.bold),
              ),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildIconBtn(IconData icon, VoidCallback? onPressed, String tooltip, {Color? accent}) {
    return SizedBox(
      width: 44,
      height: 44,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onPressed,
            child: Container(
              decoration: BoxDecoration(
                color: (accent ?? Colors.white).withValues(alpha: onPressed == null ? 0.03 : 0.07),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: (accent ?? Colors.white).withValues(alpha: onPressed == null ? 0.05 : 0.2),
                ),
              ),
              child: Icon(
                icon,
                color: onPressed == null
                    ? Colors.white24
                    : (accent ?? Colors.white),
                size: 18,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
