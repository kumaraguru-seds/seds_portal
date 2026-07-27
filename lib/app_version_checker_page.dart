import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'main.dart';

// ─── App Version Checker Page (Admin-only) ───────────────────────────────────
class AppVersionCheckerPage extends StatefulWidget {
  final UserData? userData;
  const AppVersionCheckerPage({super.key, this.userData});

  @override
  State<AppVersionCheckerPage> createState() => _AppVersionCheckerPageState();
}

class _AppVersionCheckerPageState extends State<AppVersionCheckerPage> {
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _filtered = [];
  String _currentVersion = '';
  String _searchQuery = '';
  String _filterRole = 'All';
  String _filterVersion = 'All';
  final TextEditingController _searchCtrl = TextEditingController();

  final List<String> _roles = ['All', 'Admin', 'Lead', 'Member'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final pkgInfo = await PackageInfo.fromPlatform();
      _currentVersion = pkgInfo.version;

      final res = await http.get(
        Uri.parse('$apiBaseUrl/api/admin/user-versions'),
        headers: {
          if (currentJwtToken != null) 'Authorization': 'Bearer $currentJwtToken',
        },
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true) {
          final users = List<Map<String, dynamic>>.from(data['users'] ?? []);
          setState(() {
            _users = users;
            _isLoading = false;
          });
          _applyFilters();
          return;
        }
      }
      setState(() {
        _error = 'Failed to load user versions.';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Connection error: $e';
        _isLoading = false;
      });
    }
  }

  void _applyFilters() {
    final q = _searchQuery.toLowerCase().trim();
    setState(() {
      _filtered = _users.where((u) {
        final name = (u['name'] ?? '').toString().toLowerCase();
        final email = (u['email'] ?? '').toString().toLowerCase();
        final roll = (u['roll_number'] ?? '').toString().toLowerCase();
        final version = (u['app_version'] ?? '').toString().toLowerCase();
        final matchSearch = q.isEmpty ||
            name.contains(q) || email.contains(q) ||
            roll.contains(q) || version.contains(q);
        final matchRole = _filterRole == 'All' ||
            (u['role'] ?? '').toString() == _filterRole;
        final matchVersion = _filterVersion == 'All' ||
            (_filterVersion == 'Latest' && (u['app_version'] ?? '') == _currentVersion) ||
            (_filterVersion == 'Outdated' && (u['app_version'] ?? '') != _currentVersion &&
             (u['app_version'] ?? '') != 'Never logged in') ||
            (_filterVersion == 'Never logged in' && (u['app_version'] ?? '') == 'Never logged in');
        return matchSearch && matchRole && matchVersion;
      }).toList();
    });
  }

  int get _latestCount => _users.where((u) => (u['app_version'] ?? '') == _currentVersion).length;
  int get _outdatedCount => _users.where((u) {
    final v = (u['app_version'] ?? '');
    return v != _currentVersion && v != 'Never logged in';
  }).length;
  int get _neverCount => _users.where((u) => (u['app_version'] ?? '') == 'Never logged in').length;

  Color _versionColor(String v) {
    if (v == _currentVersion) return const Color(0xFF00C48C);
    if (v == 'Never logged in') return Colors.white38;
    return const Color(0xFFFF6B6B);
  }

  IconData _versionIcon(String v) {
    if (v == _currentVersion) return Icons.check_circle_rounded;
    if (v == 'Never logged in') return Icons.person_off_rounded;
    return Icons.warning_rounded;
  }

  String _formatDate(dynamic dateStr) {
    if (dateStr == null) return 'Never';
    try {
      final dt = DateTime.parse(dateStr.toString()).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inDays == 0) return 'Today ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      if (diff.inDays == 1) return 'Yesterday';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return dateStr.toString();
    }
  }

  /// Builds a styled text widget using GoogleFonts.poppins directly to avoid
  /// type issues when passing the factory as a parameter.
  TextStyle _ts({
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
  }) =>
      GoogleFonts.poppins(
        color: color,
        fontSize: fontSize,
        fontWeight: fontWeight,
      );

  @override
  Widget build(BuildContext context) {
    final versionFilters = ['All', 'Latest', 'Outdated', 'Never logged in'];

    return Scaffold(
      backgroundColor: const Color(0xFF0D1E3A),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/background.png',
              fit: BoxFit.cover,
              errorBuilder: (_, e, s) => Container(color: const Color(0xFF0D1E3A)),
            ),
          ),
          Positioned.fill(
            child: Container(color: Colors.black.withValues(alpha: 0.55)),
          ),
          SafeArea(
            child: Column(
              children: [
                // ── AppBar ──────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'App Version Checker',
                              style: _ts(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18.0),
                            ),
                            Text(
                              'Current build: v$_currentVersion',
                              style: _ts(color: const Color(0xFF00C48C), fontSize: 12.0, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: _load,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.refresh_rounded, color: Color(0xFF4DA6FF), size: 22),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                // ── Summary Cards ────────────────────────────────────────
                if (!_isLoading && _error == null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        _summaryCard('✅ Latest', _latestCount.toString(), const Color(0xFF00C48C)),
                        const SizedBox(width: 8),
                        _summaryCard('⚠️ Outdated', _outdatedCount.toString(), const Color(0xFFFF6B6B)),
                        const SizedBox(width: 8),
                        _summaryCard('🔇 Never', _neverCount.toString(), Colors.white38),
                      ],
                    ),
                  ),

                const SizedBox(height: 12),

                // ── Search Bar ───────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    child: TextField(
                      controller: _searchCtrl,
                      style: _ts(color: Colors.white, fontSize: 13.0),
                      onChanged: (v) { _searchQuery = v; _applyFilters(); },
                      decoration: InputDecoration(
                        hintText: 'Search name, email, roll, version...',
                        hintStyle: _ts(color: Colors.white38, fontSize: 13.0),
                        prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF4DA6FF), size: 20),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // ── Filter Chips Row ─────────────────────────────────────
                SizedBox(
                  height: 36,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      ..._roles.map((r) => _filterChip(
                        r, _filterRole == r, const Color(0xFF4DA6FF),
                        () { setState(() => _filterRole = r); _applyFilters(); },
                      )),
                      const SizedBox(width: 8),
                      ...versionFilters.where((v) => v != 'All').map((v) => _filterChip(
                        v, _filterVersion == v,
                        v == 'Latest'
                            ? const Color(0xFF00C48C)
                            : v == 'Outdated'
                                ? const Color(0xFFFF6B6B)
                                : Colors.white38,
                        () {
                          setState(() => _filterVersion = (_filterVersion == v) ? 'All' : v);
                          _applyFilters();
                        },
                      )),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                // ── User List ─────────────────────────────────────────────
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator(color: Color(0xFF4DA6FF)))
                      : _error != null
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.error_outline, color: Color(0xFFFF6B6B), size: 48),
                                  const SizedBox(height: 12),
                                  Text(_error!, style: _ts(color: Colors.white54, fontSize: 13.0)),
                                  const SizedBox(height: 16),
                                  ElevatedButton.icon(
                                    onPressed: _load,
                                    icon: const Icon(Icons.refresh_rounded),
                                    label: const Text('Retry'),
                                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4DA6FF)),
                                  ),
                                ],
                              ),
                            )
                          : _filtered.isEmpty
                              ? Center(
                                  child: Text(
                                    'No users match your filter.',
                                    style: _ts(color: Colors.white38, fontSize: 13.0),
                                  ),
                                )
                              : ListView.builder(
                                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                                  itemCount: _filtered.length,
                                  itemBuilder: (ctx, i) {
                                    final u = _filtered[i];
                                    final version = (u['app_version'] ?? 'Unknown').toString();
                                    final vColor = _versionColor(version);
                                    final vIcon = _versionIcon(version);
                                    final isLatest = version == _currentVersion;
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 10),
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.05),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(color: vColor.withValues(alpha: 0.25)),
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 42,
                                            height: 42,
                                            decoration: BoxDecoration(
                                              color: vColor.withValues(alpha: 0.12),
                                              shape: BoxShape.circle,
                                            ),
                                            child: Icon(vIcon, color: vColor, size: 20),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: Text(
                                                        u['name'] ?? '',
                                                        style: _ts(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.0),
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: const Color(0xFF4DA6FF).withValues(alpha: 0.12),
                                                        borderRadius: BorderRadius.circular(6),
                                                      ),
                                                      child: Text(
                                                        u['role'] ?? '',
                                                        style: _ts(color: const Color(0xFF4DA6FF), fontSize: 9.0, fontWeight: FontWeight.bold),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  u['email'] ?? '',
                                                  style: _ts(color: Colors.white38, fontSize: 10.0),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                if ((u['team'] ?? '').toString().isNotEmpty)
                                                  Text('${u['roll_number'] ?? ''} · ${u['team']}',
                                                      style: _ts(color: Colors.white38, fontSize: 10.0))
                                                else
                                                  Text(u['roll_number'] ?? '',
                                                      style: _ts(color: Colors.white38, fontSize: 10.0)),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.end,
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: vColor.withValues(alpha: isLatest ? 0.18 : 0.12),
                                                  borderRadius: BorderRadius.circular(8),
                                                  border: Border.all(color: vColor.withValues(alpha: 0.35)),
                                                ),
                                                child: Text(
                                                  'v$version',
                                                  style: _ts(color: vColor, fontSize: 11.0, fontWeight: FontWeight.w800),
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                _formatDate(u['last_login']),
                                                style: _ts(color: Colors.white30, fontSize: 9.0),
                                              ),
                                            ],
                                          ),
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
    );
  }

  Widget _summaryCard(String label, String count, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Text(count, style: _ts(color: color, fontWeight: FontWeight.w900, fontSize: 20.0)),
            const SizedBox(height: 2),
            Text(label, style: _ts(color: color.withValues(alpha: 0.8), fontSize: 10.0, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String label, bool selected, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color.withValues(alpha: 0.45) : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Text(
          label,
          style: _ts(
            color: selected ? color : Colors.white54,
            fontSize: 11.0,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
