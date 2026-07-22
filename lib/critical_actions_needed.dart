import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'main.dart' show apiBaseUrl, UserData;

class CriticalActionsNeededPage extends StatefulWidget {
  final UserData? userData;
  final String? teamFilter; // if set, show only deficits for this team
  const CriticalActionsNeededPage({super.key, this.userData, this.teamFilter});

  @override
  State<CriticalActionsNeededPage> createState() => _CriticalActionsNeededPageState();
}

class _CriticalActionsNeededPageState extends State<CriticalActionsNeededPage> with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  String? _errorMessage;
  List<dynamic> _allDeficits = [];
  List<dynamic> _filteredDeficits = [];

  // Search & Filters
  final TextEditingController _searchController = TextEditingController();
  String _selectedFilter = 'All'; // 'All', 'Log Deficits', 'Att Deficits', 'Critical Needed'

  @override
  void initState() {
    super.initState();
    _fetchDeficits();
  }

  Future<void> _fetchDeficits() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await http.get(Uri.parse('$apiBaseUrl/api/logs/deficits')).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) {
          List<dynamic> deficits = data['deficits'] ?? [];
          // Filter by team if teamFilter is set (Leads see only their team)
          if (widget.teamFilter != null && widget.teamFilter!.isNotEmpty) {
            final leadTeams = widget.teamFilter!
                .toLowerCase()
                .split(',')
                .map((t) => t.trim())
                .where((t) => t.isNotEmpty && t != 'leads')
                .toList();

            if (leadTeams.isNotEmpty) {
              deficits = deficits.where((d) {
                final memberTeams = (d['team'] ?? '')
                    .toString()
                    .toLowerCase()
                    .split(',')
                    .map((t) => t.trim())
                    .toList();
                return memberTeams.any((mt) => leadTeams.contains(mt));
              }).toList();
            }
          }
          setState(() {
            _allDeficits = deficits;
            _applyFilters();
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _errorMessage = 'Failed to load deficits. Server error.';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Connection error: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _applyFilters() {
    final query = _searchController.text.toLowerCase().trim();
    List<dynamic> temp = _allDeficits;

    // Search query match
    if (query.isNotEmpty) {
      temp = temp.where((def) {
        final name = (def['name'] ?? '').toString().toLowerCase();
        final roll = (def['roll_number'] ?? '').toString().toLowerCase();
        final team = (def['team'] ?? '').toString().toLowerCase();
        return name.contains(query) || roll.contains(query) || team.contains(query);
      }).toList();
    }

    // Filter by type
    if (_selectedFilter == 'Log Deficits') {
      temp = temp.where((def) => def['has_hours_deficit'] == true).toList();
    } else if (_selectedFilter == 'Att Deficits') {
      temp = temp.where((def) => def['latest_absent'] != null).toList();
    } else if (_selectedFilter == 'Critical Needed') {
      temp = temp.where((def) => def['has_hours_deficit'] == true && def['latest_absent'] != null).toList();
    }

    setState(() {
      _filteredDeficits = temp;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final poppins = GoogleFonts.poppins;

    return Scaffold(
      backgroundColor: const Color(0xFF0F1E36),
      appBar: AppBar(
        titleSpacing: 0,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Actions Needed',
              style: poppins(color: const Color(0xFFFF6B6B), fontWeight: FontWeight.bold, fontSize: 18),
            ),
            Text(
              widget.teamFilter != null
                  ? 'Team: ${widget.teamFilter} — critical deficits'
                  : 'Critical target deficits or absents detected',
              style: poppins(color: Colors.white54, fontSize: 11),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
            onPressed: _fetchDeficits,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          // Background image layer
          Positioned.fill(
            child: Image.asset(
              'assets/background.png',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  Container(color: const Color(0xFF0F1E36)),
            ),
          ),
          // Dark overlay
          Positioned.fill(
            child: Container(color: Colors.black.withValues(alpha: 0.50)),
          ),
          // Content
          Column(
          children: [
            // Search Input Row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: TextField(
                  controller: _searchController,
                  style: poppins(color: Colors.white, fontSize: 14),
                  onChanged: (_) => _applyFilters(),
                  decoration: InputDecoration(
                    hintText: 'Search by name, roll, or team...',
                    hintStyle: poppins(color: const Color(0xFF8A9CC2)),
                    prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF4DA6FF)),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, color: Colors.white54),
                            onPressed: () {
                              _searchController.clear();
                              _applyFilters();
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ),

            // Segmented Filters (All, Log Deficits, Att Deficits, Critical Needed)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  Row(
                    children: [
                      _filterTab('All'),
                      const SizedBox(width: 8),
                      _filterTab('Log Deficits'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _filterTab('Att Deficits'),
                      const SizedBox(width: 8),
                      _filterTab('Critical Needed'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Alert Banner
            if (_filteredDeficits.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6B6B).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFF6B6B).withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, color: Color(0xFFFF6B6B), size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Total of ${_filteredDeficits.length} ${_selectedFilter == 'All' ? 'critical issues' : _selectedFilter} require attention.',
                          style: poppins(color: const Color(0xFFFF6B6B), fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Content Area
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF6B6B)))
                  : _errorMessage != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Text(
                              _errorMessage!,
                              textAlign: TextAlign.center,
                              style: poppins(color: Colors.redAccent, fontSize: 14),
                            ),
                          ),
                        )
                      : _filteredDeficits.isEmpty
                          ? Center(
                              child: Text(
                                'No critical issues found.',
                                style: poppins(color: const Color(0xFF8A9CC2)),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                              itemCount: _filteredDeficits.length,
                              itemBuilder: (context, index) {
                                final def = _filteredDeficits[index];
                                return _buildDeficitCard(def, poppins);
                              },
                            ),
            ),
          ],
          ),
        ],
      ),
    );
  }

  Widget _filterTab(String label) {
    final bool active = _selectedFilter == label;
    final poppins = GoogleFonts.poppins;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedFilter = label;
            _applyFilters();
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active ? const Color(0xFFFF6B6B).withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active ? const Color(0xFFFF6B6B).withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.05),
              width: 1.2,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: poppins(
              fontSize: 12,
              color: active ? const Color(0xFFFF6B6B) : const Color(0xFF8A9CC2),
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDeficitCard(dynamic def, TextStyle Function({Color? color, double? fontSize, FontWeight? fontWeight}) poppins) {
    final int weeklySec = (def['weekly_seconds'] ?? 0) as int;
    final double targetHours = (def['target_seconds'] ?? 0) / 3600.0;
    final int wh = weeklySec ~/ 3600;
    final int wm = (weeklySec % 3600) ~/ 60;
    final int ws = weeklySec % 60;
    final String workedStr = wh > 0
        ? '${wh}h ${wm}m ${ws}s'
        : wm > 0
            ? '${wm}m ${ws}s'
            : '${ws}s';
    final List<Widget> alerts = [];

    if (def['has_hours_deficit'] == true) {
      alerts.add(
        Container(
          margin: const EdgeInsets.only(top: 4, right: 6),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFFF6B6B).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.hourglass_empty_rounded, color: Color(0xFFFF6B6B), size: 12),
              const SizedBox(width: 4),
              Text(
                'Worked: $workedStr / ${targetHours.toStringAsFixed(0)}h',
                style: poppins(fontSize: 11, color: const Color(0xFFFF6B6B), fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      );
    }

    if (def['latest_absent'] != null) {
      final date = def['latest_absent']['date'] ?? '';
      alerts.add(
        Container(
          margin: const EdgeInsets.only(top: 4),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFFFC048).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.calendar_today_rounded, color: Color(0xFFFFC048), size: 12),
              const SizedBox(width: 4),
              Text(
                'Absent: $date',
                style: poppins(fontSize: 11, color: const Color(0xFFFFC048), fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      );
    }

    final String imgUrl = def['image_url'] ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: def['has_hours_deficit'] == true
              ? const Color(0xFFFF6B6B).withValues(alpha: 0.2)
              : const Color(0xFFFFC048).withValues(alpha: 0.2),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: const Color(0xFF4DA6FF).withValues(alpha: 0.1),
            backgroundImage: imgUrl.isNotEmpty ? NetworkImage(imgUrl) : null,
            child: imgUrl.isEmpty ? const Icon(Icons.person_rounded, color: Colors.white70, size: 22) : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  def['name'] ?? 'N/A',
                  style: poppins(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  '${def['roll_number'] ?? 'N/A'} • ${def['role']} • ${def['team']}',
                  style: poppins(color: const Color(0xFF8A9CC2), fontSize: 11),
                ),
                const SizedBox(height: 6),
                Wrap(children: alerts),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
