import 'dart:convert';
import 'dart:io' as io;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'app_toast.dart';
import 'main.dart';

class UpdateCoordinatesPage extends StatefulWidget {
  final UserData userData;
  const UpdateCoordinatesPage({super.key, required this.userData});

  @override
  State<UpdateCoordinatesPage> createState() => _UpdateCoordinatesPageState();
}

class _UpdateCoordinatesPageState extends State<UpdateCoordinatesPage>
    with SingleTickerProviderStateMixin {
  final ScrollController _manualScrollController = ScrollController();
  final ScrollController _kmlScrollController = ScrollController();
  late TabController _tabController;

  List<Map<String, dynamic>> _currentPolygon = [];
  bool _isLoadingCurrent = true;

  final List<Map<String, TextEditingController>> _manualPoints = [];

  String? _kmlFileName;
  List<int>? _kmlFileBytes;
  List<Map<String, dynamic>> _parsedKmlPoints = [];

  bool _isSubmitting = false;

  String _targetType = 'global'; // 'global', 'team', 'user'
  String _targetValue = 'all';

  final List<String> _teams = const [
    'Software',
    'Rover',
    'Satellite',
    'Rocketry',
    'Propulsion',
    'Electronics',
    'Structures',
    'Control'
  ];

  List<Map<String, dynamic>> _filteredUsers = [];
  bool _isLoadingUsers = false;
  bool _showUserSearchOverlay = false;
  final TextEditingController _userSearchCtrl = TextEditingController();

  final List<String> _consoleLogs = [];
  final ScrollController _consoleScrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadCurrentCoordinates();
    for (int i = 0; i < 4; i++) {
      _addManualPoint();
    }
    _consoleLogs.add('[SYSTEM] Geofence system online.');
    _consoleLogs.add('[SYSTEM] Awaiting target scope selection...');
  }

  @override
  void dispose() {
    _tabController.dispose();
    _manualScrollController.dispose();
    _kmlScrollController.dispose();
    _userSearchCtrl.dispose();
    _consoleScrollCtrl.dispose();
    for (final pt in _manualPoints) {
      pt['lat']!.dispose();
      pt['lng']!.dispose();
    }
    super.dispose();
  }

  Future<void> _fetchUsersList(String query) async {
    setState(() => _isLoadingUsers = true);
    try {
      final res = await http.get(Uri.parse('$apiBaseUrl/api/users/search?q=${Uri.encodeComponent(query)}')).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final List data = jsonDecode(res.body);
        setState(() {
          _filteredUsers = List<Map<String, dynamic>>.from(data);
        });
      }
    } catch (e) {
      debugPrint('Error searching users: $e');
    } finally {
      setState(() => _isLoadingUsers = false);
    }
  }

  void _logToConsole(String message) {
    final timeStr = DateTime.now().toString().substring(11, 19);
    setState(() {
      _consoleLogs.add('[$timeStr] $message');
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_consoleScrollCtrl.hasClients) {
        _consoleScrollCtrl.animateTo(
          _consoleScrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _addManualPoint() {
    setState(() {
      _manualPoints.add({
        'lat': TextEditingController(),
        'lng': TextEditingController(),
      });
    });
  }

  void _removeManualPoint(int index) {
    if (_manualPoints.length <= 3) {
      AppToast.warning(context, 'Minimum 3 coordinate points required.');
      return;
    }
    setState(() {
      _manualPoints[index]['lat']!.dispose();
      _manualPoints[index]['lng']!.dispose();
      _manualPoints.removeAt(index);
    });
  }

  Future<void> _loadCurrentCoordinates() async {
    setState(() => _isLoadingCurrent = true);
    try {
      final res = await http
          .get(Uri.parse('$apiBaseUrl/api/admin/coordinates'))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) {
          setState(() {
            _currentPolygon = List<Map<String, dynamic>>.from(
              (data['polygon'] as List).map(
                (p) => {
                  'lat': (p['lat'] as num).toDouble(),
                  'lng': (p['lng'] as num).toDouble(),
                },
              ),
            );
          });
        }
      }
    } catch (e) {
      debugPrint('Load coordinates error: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingCurrent = false);
      }
    }
  }

  Future<void> _pickKmlFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.any);
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        if (!file.name.toLowerCase().endsWith('.kml')) {
          if (mounted) {
            AppToast.error(context, 'Please select a valid .kml file.');
          }
          return;
        }

        List<int>? bytes = file.bytes;
        if (bytes == null && file.path != null) {
          final ioFile = io.File(file.path!);
          if (await ioFile.exists()) {
            bytes = await ioFile.readAsBytes();
          }
        }

        if (bytes == null) {
          if (mounted) {
            AppToast.error(context, 'Could not read KML file content.');
          }
          return;
        }

        final content = utf8.decode(bytes);

        final match = RegExp(
          r'<coordinates>([\s\S]*?)</coordinates>',
        ).firstMatch(content);
        if (match == null) {
          if (mounted) {
            AppToast.error(context, 'No <coordinates> tag found in KML file.');
          }
          return;
        }
        final coordStr = match.group(1)!.trim();
        final pairs = coordStr
            .split(RegExp(r'\s+'))
            .where((s) => s.isNotEmpty)
            .toList();
        final parsed = <Map<String, dynamic>>[];
        for (final p in pairs) {
          final parts = p.split(',');
          if (parts.length >= 2) {
            final lng = double.tryParse(parts[0]);
            final lat = double.tryParse(parts[1]);
            if (lat != null && lng != null) {
              parsed.add({'lat': lat, 'lng': lng});
            }
          }
        }

        if (parsed.length < 3) {
          if (mounted) {
            AppToast.error(
              context,
              'KML must have at least 3 coordinate points.',
            );
          }
          return;
        }

        setState(() {
          _kmlFileName = file.name;
          _kmlFileBytes = bytes;
          _parsedKmlPoints = parsed;
        });
        if (mounted) {
          AppToast.success(
            context,
            'KML parsed: ${parsed.length} points found.',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'Failed to pick KML file: $e');
      }
    }
  }

  Future<void> _submitManualPoints() async {
    _consoleLogs.clear();
    _logToConsole('[INFO] Validating manual points...');
    final List<Map<String, dynamic>> points = [];
    for (int i = 0; i < _manualPoints.length; i++) {
      final lat = double.tryParse(_manualPoints[i]['lat']!.text.trim());
      final lng = double.tryParse(_manualPoints[i]['lng']!.text.trim());
      if (lat == null || lng == null) {
        _logToConsole('[ERROR] Point ${i + 1}: Invalid latitude or longitude.');
        AppToast.error(
          context,
          'Point ${i + 1}: Enter valid latitude and longitude.',
        );
        return;
      }
      points.add({'lat': lat, 'lng': lng});
    }

    _logToConsole('[INFO] targetType: $_targetType, targetValue: $_targetValue');
    _logToConsole('[POST] Sending coordinates to backend...');
    setState(() => _isSubmitting = true);
    try {
      final res = await http
          .post(
            Uri.parse('$apiBaseUrl/api/admin/update-coordinates'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'points': points,
              'targetType': _targetType,
              'targetValue': _targetValue,
            }),
          )
          .timeout(const Duration(seconds: 30));

      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['success'] == true) {
        _logToConsole('[SUCCESS] Geofence updated successfully!');
        _logToConsole('[SUCCESS] ${points.length} coordinates applied.');
        if (mounted) {
          AppToast.success(
            context,
            'Geofence updated with ${points.length} points! ✅',
          );
          setState(() => _currentPolygon = points);
        }
      } else {
        final errMsg = data['message'] ?? 'Failed to update coordinates.';
        _logToConsole('[ERROR] Update failed: $errMsg');
        if (mounted) {
          AppToast.error(
            context,
            errMsg,
          );
        }
      }
    } catch (e) {
      _logToConsole('[ERROR] Connection/Server error: $e');
      if (mounted) {
        AppToast.error(context, 'Connection error. Please try again.');
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _submitKmlFile() async {
    if (_kmlFileBytes == null) {
      _logToConsole('[ERROR] No KML file selected.');
      AppToast.error(context, 'Please pick a .kml file first.');
      return;
    }
    _consoleLogs.clear();
    _logToConsole('[INFO] Uploading KML file...');
    _logToConsole('[INFO] File name: $_kmlFileName');
    _logToConsole('[INFO] targetType: $_targetType, targetValue: $_targetValue');
    _logToConsole('[POST] Sending multipart request to backend...');
    setState(() => _isSubmitting = true);
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$apiBaseUrl/api/admin/update-coordinates'),
      );
      request.fields['targetType'] = _targetType;
      request.fields['targetValue'] = _targetValue;
      request.files.add(
        http.MultipartFile.fromBytes(
          'kmlFile',
          _kmlFileBytes!,
          filename: _kmlFileName ?? 'coordinates.kml',
        ),
      );
      final streamedRes = await request.send().timeout(
        const Duration(seconds: 30),
      );
      final res = await http.Response.fromStream(streamedRes);
      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['success'] == true) {
        _logToConsole('[SUCCESS] KML parsed and applied successfully!');
        _logToConsole('[SUCCESS] ${_parsedKmlPoints.length} coordinates detected.');
        if (mounted) {
          AppToast.success(
            context,
            'KML uploaded! Geofence updated with ${_parsedKmlPoints.length} points. ✅',
          );
          setState(() => _currentPolygon = _parsedKmlPoints);
        }
      } else {
        final errMsg = data['message'] ?? 'Failed to update via KML.';
        _logToConsole('[ERROR] Upload failed: $errMsg');
        if (mounted) {
          AppToast.error(
            context,
            errMsg,
          );
        }
      }
    } catch (e) {
      _logToConsole('[ERROR] Connection/Server error: $e');
      if (mounted) {
        AppToast.error(context, 'Upload error. Please try again.');
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final poppins = GoogleFonts.poppins;
    return Stack(
      children: [
        // ── Truly Fixed Full-Screen Background Image ──
        Positioned.fill(
          child: Image.asset(
            'assets/background.png',
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            errorBuilder: (context, error, stackTrace) {
              return Container(color: const Color(0xFF0D1E3A));
            },
          ),
        ),
        // ── Dim overlay ──
        Positioned.fill(
          child: Container(color: Colors.black.withValues(alpha: 0.48)),
        ),
        Scaffold(
          resizeToAvoidBottomInset: false,
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: Colors.white,
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFF4DA6FF,
                          ).withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.map_rounded,
                          color: Color(0xFF4DA6FF),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Update Geofence',
                              style: poppins(
                                fontSize: 20.0,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              'Admin — Coordinate Control',
                              style: poppins(
                                fontSize: 15.0,
                                fontWeight: FontWeight.w800,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.refresh_rounded,
                          color: Colors.white70,
                        ),
                        onPressed: _loadCurrentCoordinates,
                        tooltip: 'Reload current polygon',
                      ),
                    ],
                  ),
                ),

                // Target Geofence Selector Card
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Geofence Scope Target',
                          style: poppins(color: const Color(0xFF4DA6FF), fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            // Scope Type Dropdown
                            Expanded(
                              flex: 4,
                              child: DropdownButtonFormField<String>(
                                key: ValueKey(_targetType),
                                initialValue: _targetType,
                                dropdownColor: const Color(0xFF0D1B2A),
                                style: poppins(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: Colors.white.withValues(alpha: 0.05),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                items: const [
                                  DropdownMenuItem(value: 'global', child: Text('Global (All)')),
                                  DropdownMenuItem(value: 'team', child: Text('Specific Team')),
                                  DropdownMenuItem(value: 'user', child: Text('Specific Person')),
                                ],
                                onChanged: (val) {
                                  setState(() {
                                    _targetType = val ?? 'global';
                                    if (_targetType == 'global') {
                                      _targetValue = 'all';
                                    } else if (_targetType == 'team') {
                                      _targetValue = _teams[0];
                                    } else {
                                      _targetValue = '';
                                    }
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            // Scope Value Selector
                            Expanded(
                              flex: 5,
                              child: _targetType == 'global'
                                  ? Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.02),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        'All SEDS Users',
                                        style: poppins(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
                                      ),
                                    )
                                  : _targetType == 'team'
                                      ? DropdownButtonFormField<String>(
                                          key: ValueKey(_targetValue),
                                          initialValue: _teams.contains(_targetValue) ? _targetValue : _teams[0],
                                          dropdownColor: const Color(0xFF0D1B2A),
                                          style: poppins(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                          decoration: InputDecoration(
                                            filled: true,
                                            fillColor: Colors.white.withValues(alpha: 0.05),
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                          ),
                                          items: _teams.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                                          onChanged: (val) {
                                            setState(() {
                                              _targetValue = val ?? _teams[0];
                                            });
                                          },
                                        )
                                      : TextField(
                                          controller: _userSearchCtrl,
                                          style: poppins(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                          decoration: InputDecoration(
                                            hintText: 'Search email...',
                                            hintStyle: poppins(color: Colors.white30, fontSize: 12),
                                            filled: true,
                                            fillColor: Colors.white.withValues(alpha: 0.05),
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                            suffixIcon: _isLoadingUsers
                                                ? const SizedBox(
                                                    width: 18,
                                                    height: 18,
                                                    child: Padding(
                                                      padding: EdgeInsets.all(12),
                                                      child: CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4DA6FF)),
                                                      ),
                                                    ),
                                                  )
                                                : const Icon(Icons.search, color: Color(0xFF4DA6FF), size: 18),
                                          ),
                                          onChanged: (val) {
                                            if (val.trim().length >= 2) {
                                              _fetchUsersList(val.trim());
                                              setState(() {
                                                _showUserSearchOverlay = true;
                                              });
                                            } else {
                                              setState(() {
                                                _showUserSearchOverlay = false;
                                              });
                                            }
                                          },
                                        ),
                            ),
                          ],
                        ),
                        if (_targetType == 'user' && _showUserSearchOverlay && _filteredUsers.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Container(
                            constraints: const BoxConstraints(maxHeight: 150),
                            decoration: BoxDecoration(
                              color: const Color(0xFF13223F),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                            ),
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: _filteredUsers.length,
                              itemBuilder: (context, idx) {
                                final u = _filteredUsers[idx];
                                final name = u['name'] ?? '';
                                final email = u['email'] ?? '';
                                return ListTile(
                                  dense: true,
                                  title: Text(name, style: poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                                  subtitle: Text(email, style: poppins(color: Colors.white54, fontSize: 11)),
                                  onTap: () {
                                    setState(() {
                                      _targetValue = email;
                                      _userSearchCtrl.text = email;
                                      _showUserSearchOverlay = false;
                                    });
                                  },
                                );
                              },
                            ),
                          ),
                        ],
                        if (_targetType == 'user' && _targetValue.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.person_pin_circle_rounded, color: Color(0xFF00C48C), size: 16),
                              const SizedBox(width: 6),
                              Text(
                                'Selected: $_targetValue',
                                style: poppins(color: const Color(0xFF00C48C), fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Current polygon chip row
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.09),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.location_on_rounded,
                              color: Color(0xFF00C48C),
                              size: 15,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'Active Geofence',
                              style: poppins(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 14.0,
                              ),
                            ),
                            const Spacer(),
                            if (_isLoadingCurrent)
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Color(0xFF00C48C),
                                  ),
                                ),
                              )
                            else
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF00C48C,
                                  ).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${_currentPolygon.length} pts',
                                  style: poppins(
                                    color: const Color(0xFF00C48C),
                                    fontSize: 10.0,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (!_isLoadingCurrent &&
                            _currentPolygon.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 52,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: _currentPolygon.length,
                              itemBuilder: (_, i) {
                                final pt = _currentPolygon[i];
                                return Container(
                                  margin: const EdgeInsets.only(right: 6),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: 0.08,
                                      ),
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        'P${i + 1}',
                                        style: poppins(
                                          color: const Color(0xFFFFD93D),
                                          fontSize: 9.0,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        (pt['lat'] as double).toStringAsFixed(
                                          5,
                                        ),
                                        style: poppins(
                                          color: Colors.white70,
                                          fontSize: 9.0,
                                        ),
                                      ),
                                      Text(
                                        (pt['lng'] as double).toStringAsFixed(
                                          5,
                                        ),
                                        style: poppins(
                                          color: Colors.white54,
                                          fontSize: 9.0,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                // Tab bar
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    labelColor: const Color(0xFF4DA6FF),
                    unselectedLabelColor: Colors.white54,
                    indicatorColor: const Color(0xFF4DA6FF),
                    indicatorSize: TabBarIndicatorSize.tab,
                    indicatorWeight: 2.5,
                    labelStyle: poppins(
                      fontWeight: FontWeight.w800,
                      fontSize: 15.0,
                    ),
                    tabs: const [
                      Tab(text: 'Manual Input'),
                      Tab(text: 'Upload KML'),
                    ],
                  ),
                ),
                const SizedBox(height: 4),

                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [_buildManualTab(poppins), _buildKmlTab(poppins)],
                  ),
                ),

                // Console Terminal View Panel
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Container(
                    width: double.infinity,
                    height: 120,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF00C48C).withValues(alpha: 0.4), width: 1.2),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00C48C).withValues(alpha: 0.15),
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(10),
                              topRight: Radius.circular(10),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.terminal_rounded, color: Color(0xFF00C48C), size: 14),
                              const SizedBox(width: 8),
                              Text(
                                'CONSOLE TELEMETRY LOGS',
                                style: GoogleFonts.shareTechMono(
                                  color: const Color(0xFF00C48C),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.0,
                                ),
                              ),
                              const Spacer(),
                              GestureDetector(
                                onTap: () => setState(() => _consoleLogs.clear()),
                                child: Text(
                                  'CLEAR',
                                  style: GoogleFonts.shareTechMono(
                                    color: const Color(0xFFFF6B6B),
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Scrollbar(
                            controller: _consoleScrollCtrl,
                            thumbVisibility: true,
                            child: ListView.builder(
                              controller: _consoleScrollCtrl,
                              padding: const EdgeInsets.all(10),
                              itemCount: _consoleLogs.isEmpty ? 1 : _consoleLogs.length,
                              itemBuilder: (context, idx) {
                                return Text(
                                  _consoleLogs.isEmpty
                                      ? 'System ready. Awaiting geofence upload...'
                                      : _consoleLogs[idx],
                                  style: GoogleFonts.shareTechMono(
                                    color: _consoleLogs.isEmpty
                                        ? Colors.white30
                                        : _consoleLogs[idx].contains('[ERROR]')
                                            ? const Color(0xFFFF6B6B)
                                            : _consoleLogs[idx].contains('[SUCCESS]')
                                                ? const Color(0xFF00C48C)
                                                : const Color(0xFF4DA6FF),
                                    fontSize: 11,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildManualTab(dynamic poppins) {
    return Column(
      children: [
        Expanded(
          child: Scrollbar(
            controller: _manualScrollController,
            thumbVisibility: true,
            child: ListView(
              controller: _manualScrollController,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4DA6FF).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFF4DA6FF).withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        color: Color(0xFF4DA6FF),
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Add at least 3 lat/lng points. The polygon auto-closes.',
                          style: poppins(
                            color: const Color(0xFF4DA6FF),
                            fontSize: 11.0,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                ...List.generate(
                  _manualPoints.length,
                  (index) => _buildPointRow(index, poppins),
                ),
                const SizedBox(height: 6),
                InkWell(
                  onTap: _addManualPoint,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF4DA6FF).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.add_location_alt_rounded,
                          color: Color(0xFF4DA6FF),
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Add Point',
                          style: poppins(
                            color: const Color(0xFF4DA6FF),
                            fontWeight: FontWeight.bold,
                            fontSize: 13.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 80),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isSubmitting ? null : _submitManualPoints,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4DA6FF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.save_rounded),
              label: Text(
                _isSubmitting ? 'Updating…' : 'Save & Apply Coordinates',
                style: poppins(fontWeight: FontWeight.bold, fontSize: 15.0),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPointRow(int index, dynamic poppins) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFFFD93D).withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Text(
              '${index + 1}',
              style: poppins(
                color: const Color(0xFFFFD93D),
                fontWeight: FontWeight.bold,
                fontSize: 12.0,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              children: [
                _coordField(
                  _manualPoints[index]['lat']!,
                  'Latitude (e.g. 11.079213)',
                ),
                const SizedBox(height: 6),
                _coordField(
                  _manualPoints[index]['lng']!,
                  'Longitude (e.g. 76.985800)',
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _removeManualPoint(index),
            icon: const Icon(
              Icons.remove_circle_outline_rounded,
              color: Color(0xFFFF6B6B),
              size: 20,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  Widget _coordField(TextEditingController ctrl, String hint) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
        signed: true,
      ),
      style: GoogleFonts.poppins(
        color: Colors.white,
        fontSize: 12.0,
        fontWeight: FontWeight.bold,
      ),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[-0-9.]'))],
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.poppins(
          color: Colors.white38,
          fontSize: 11.0,
          fontWeight: FontWeight.bold,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.04),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF4DA6FF)),
        ),
      ),
    );
  }

  Widget _buildKmlTab(dynamic poppins) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF00C48C).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFF00C48C).withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      color: Color(0xFF00C48C),
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Export from Google Earth/My Maps as .kml and upload here.',
                        style: poppins(
                          color: const Color(0xFF00C48C),
                          fontSize: 11.0,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: _pickKmlFile,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _kmlFileName != null
                          ? const Color(0xFF00C48C).withValues(alpha: 0.6)
                          : Colors.white.withValues(alpha: 0.12),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        _kmlFileName != null
                            ? Icons.check_circle_rounded
                            : Icons.upload_file_rounded,
                        color: _kmlFileName != null
                            ? const Color(0xFF00C48C)
                            : Colors.white38,
                        size: 42,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _kmlFileName ?? 'Tap to select .kml file',
                        style: poppins(
                          color: _kmlFileName != null
                              ? const Color(0xFF00C48C)
                              : Colors.white54,
                          fontWeight: FontWeight.bold,
                          fontSize: 13.0,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (_parsedKmlPoints.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          '${_parsedKmlPoints.length} points detected',
                          style: poppins(
                            color: Colors.white54,
                            fontSize: 11.0,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (_parsedKmlPoints.isNotEmpty) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Icon(
                      Icons.location_on_rounded,
                      color: Color(0xFF4DA6FF),
                      size: 15,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '${_parsedKmlPoints.length} Parsed Points',
                      style: poppins(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13.0,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 220),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.07),
                    ),
                  ),
                  child: Scrollbar(
                    controller: _kmlScrollController,
                    thumbVisibility: true,
                    child: ListView.separated(
                      controller: _kmlScrollController,
                      padding: const EdgeInsets.all(8),
                      shrinkWrap: true,
                      itemCount: _parsedKmlPoints.length,
                      separatorBuilder: (context, index) => Divider(
                        color: Colors.white.withValues(alpha: 0.05),
                        height: 1,
                      ),
                      itemBuilder: (context, i) {
                        final pt = _parsedKmlPoints[i];
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 6,
                            horizontal: 8,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 22,
                                height: 22,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF4DA6FF,
                                  ).withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  '${i + 1}',
                                  style: GoogleFonts.poppins(
                                    color: const Color(0xFF4DA6FF),
                                    fontSize: 9.0,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Lat: ${(pt['lat'] as double).toStringAsFixed(8)}',
                                style: GoogleFonts.poppins(
                                  color: Colors.white70,
                                  fontSize: 11.0,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Lng: ${(pt['lng'] as double).toStringAsFixed(8)}',
                                style: GoogleFonts.poppins(
                                  color: Colors.white54,
                                  fontSize: 11.0,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 80),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (_isSubmitting || _kmlFileBytes == null)
                  ? null
                  : _submitKmlFile,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00C48C),
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.white12,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.upload_rounded),
              label: Text(
                _isSubmitting ? 'Uploading…' : 'Upload KML & Apply',
                style: poppins(fontWeight: FontWeight.bold, fontSize: 15.0),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
