import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
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

  // ── Table content with proper InteractiveViewer ───────────────
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

    // Proper scrollable + zoomable table:
    // Outer scrolls vertically, inner scrolls horizontally, InteractiveViewer handles pinch-zoom
    return InteractiveViewer(
      transformationController: _transformCtrl,
      minScale: _minScale,
      maxScale: _maxScale,
      constrained: true,   // IMPORTANT: keeps the viewer bounded inside its parent
      scaleEnabled: true,
      panEnabled: true,
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        physics: const BouncingScrollPhysics(),
        child: SingleChildScrollView(
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
            columns: _columns.map((col) {
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
            }).toList(),
            rows: _rows.map((row) {
              return DataRow(
                cells: _columns.map((col) {
                  final columnName = col['column_name'];
                  final val = row[columnName]?.toString() ?? 'NULL';
                  return DataCell(
                    Text(
                      val,
                      style: poppins(
                        color: val == 'NULL' ? Colors.white30 : Colors.white,
                        fontSize: 12.0,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  );
                }).toList(),
              );
            }).toList(),
          ),
        ),
      ),
    );
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
