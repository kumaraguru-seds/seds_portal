import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'main.dart' show apiBaseUrl, UserData;

class InspectWeeklyTargetsPage extends StatefulWidget {
  final UserData? userData;
  const InspectWeeklyTargetsPage({super.key, this.userData});

  @override
  State<InspectWeeklyTargetsPage> createState() => _InspectWeeklyTargetsPageState();
}

class _InspectWeeklyTargetsPageState extends State<InspectWeeklyTargetsPage> with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  String? _errorMessage;
  List<dynamic> _allUsers = [];
  List<dynamic> _filteredUsers = [];

  // Tabs
  TabController? _tabController;

  // Search & Filter state
  final TextEditingController _searchController = TextEditingController();
  String _selectedTeam = 'All';
  String _selectedRole = 'All';
  String _targetStatus = 'All'; // 'All', 'Achieved', 'Pending'

  final List<String> _teams = ['All', 'PR', 'Media', 'Events', 'Web Dev', 'Admin'];
  final List<String> _roles = ['All', 'Lead', 'Member'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController!.addListener(() {
      if (mounted) {
        setState(() {
          if (_tabController!.index == 0) _targetStatus = 'All';
          if (_tabController!.index == 1) _targetStatus = 'Achieved';
          if (_tabController!.index == 2) _targetStatus = 'Pending';
        });
        _applyFilters();
      }
    });
    _fetchTargets();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchTargets() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await http.get(Uri.parse('$apiBaseUrl/api/logs/target-inspection')).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted && data['success'] == true) {
          setState(() {
            _allUsers = data['users'] ?? [];
            _isLoading = false;
          });
          _applyFilters();
        }
      } else {
        throw Exception('Failed to load targets');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Could not fetch targets. Check your connection.';
          _isLoading = false;
        });
      }
    }
  }

  void _applyFilters() {
    final query = _searchController.text.trim().toLowerCase();

    setState(() {
      _filteredUsers = _allUsers.where((u) {
        // Search filter
        final name = (u['name'] ?? '').toString().toLowerCase();
        final roll = (u['roll_number'] ?? '').toString().toLowerCase();
        final matchesSearch = name.contains(query) || roll.contains(query);

        // Team filter
        final team = (u['team'] ?? '').toString();
        final matchesTeam = _selectedTeam == 'All' || team.toLowerCase() == _selectedTeam.toLowerCase();

        // Role filter
        final role = (u['role'] ?? '').toString();
        final matchesRole = _selectedRole == 'All' || role.toLowerCase() == _selectedRole.toLowerCase();

        // Status filter
        final bool achieved = u['achieved'] == true;
        final matchesStatus = _targetStatus == 'All' ||
            (_targetStatus == 'Achieved' && achieved) ||
            (_targetStatus == 'Pending' && !achieved);

        return matchesSearch && matchesTeam && matchesRole && matchesStatus;
      }).toList();

      // Sort by weekly worked hours descending
      _filteredUsers.sort((a, b) {
        final int secA = (a['weekly_seconds'] as num?)?.toInt() ?? 0;
        final int secB = (b['weekly_seconds'] as num?)?.toInt() ?? 0;
        return secB.compareTo(secA);
      });
    });
  }

  String _formatDuration(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    return '${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final poppins = GoogleFonts.poppins;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1E3A),
      body: Stack(
        children: [
          // Background KML image/asset
          Positioned.fill(
            child: Image.asset(
              'assets/background.png',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(color: const Color(0xFF0D1E3A)),
            ),
          ),
          Positioned.fill(
            child: Container(color: Colors.black.withValues(alpha: 0.45)),
          ),
          Positioned.fill(
            child: SafeArea(
              child: Column(
                children: [
                  // App Bar Header
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                          onPressed: () => Navigator.pop(context),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Weekly Targets',
                                style: poppins(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                              Text(
                                'SEDS Member Performance',
                                style: poppins(fontSize: 12, color: const Color(0xFF4DA6FF), fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.sync_rounded, color: Color(0xFF4DA6FF)),
                          onPressed: _fetchTargets,
                        ),
                      ],
                    ),
                  ),

                  // Tabs
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
                    child: TabBar(
                      controller: _tabController,
                      indicatorColor: const Color(0xFF4DA6FF),
                      labelColor: const Color(0xFF4DA6FF),
                      unselectedLabelColor: Colors.white54,
                      labelStyle: poppins(fontWeight: FontWeight.bold, fontSize: 13),
                      tabs: const [
                        Tab(text: 'All'),
                        Tab(text: 'Achieved'),
                        Tab(text: 'Pending'),
                      ],
                    ),
                  ),

                  // Filters
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
                    child: Column(
                      children: [
                        // Search
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                          ),
                          child: TextField(
                            controller: _searchController,
                            onChanged: (_) => _applyFilters(),
                            style: poppins(color: Colors.white, fontSize: 14),
                            decoration: InputDecoration(
                              hintText: 'Search by name or roll...',
                              hintStyle: poppins(color: const Color(0xFF8A9CC2), fontSize: 13),
                              prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF4DA6FF)),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Dropdowns
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: _selectedTeam,
                                    dropdownColor: const Color(0xFF1A2B4A),
                                    icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF4DA6FF), size: 18),
                                    items: _teams.map((t) => DropdownMenuItem(
                                      value: t,
                                      child: Text('Team: $t', style: poppins(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold)),
                                    )).toList(),
                                    onChanged: (val) {
                                      if (val != null) {
                                        setState(() => _selectedTeam = val);
                                        _applyFilters();
                                      }
                                    },
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: _selectedRole,
                                    dropdownColor: const Color(0xFF1A2B4A),
                                    icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF4DA6FF), size: 18),
                                    items: _roles.map((r) => DropdownMenuItem(
                                      value: r,
                                      child: Text('Role: $r', style: poppins(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold)),
                                    )).toList(),
                                    onChanged: (val) {
                                      if (val != null) {
                                        setState(() => _selectedRole = val);
                                        _applyFilters();
                                      }
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // User list
                  Expanded(
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator(color: Color(0xFF4DA6FF)))
                        : _errorMessage != null
                            ? Center(
                                child: Text(_errorMessage!, style: poppins(color: const Color(0xFFFF6B6B))),
                              )
                            : _filteredUsers.isEmpty
                                ? Center(
                                    child: Text('No users match requirements.', style: poppins(color: const Color(0xFF8A9CC2))),
                                  )
                                : ListView.builder(
                                    padding: const EdgeInsets.all(24),
                                    itemCount: _filteredUsers.length,
                                    itemBuilder: (context, index) {
                                      final u = _filteredUsers[index];
                                      final name = u['name'] ?? 'N/A';
                                      final roll = u['roll_number'] ?? 'N/A';
                                      final role = u['role'] ?? 'Member';
                                      final team = u['team'] ?? 'Admin';
                                      final weeklySec = (u['weekly_seconds'] as num?)?.toInt() ?? 0;
                                      final targetSec = (u['target_seconds'] as num?)?.toInt() ?? 0;
                                      final bool achieved = u['achieved'] == true;
                                      final double progress = targetSec > 0 ? (weeklySec / targetSec).clamp(0.0, 1.0) : 1.0;
                                      final String? imageUrl = u['image_url'];

                                      return Container(
                                        margin: const EdgeInsets.only(bottom: 14),
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.05),
                                          borderRadius: BorderRadius.circular(16),
                                          border: Border.all(
                                            color: achieved
                                                ? const Color(0xFF00C48C).withValues(alpha: 0.2)
                                                : Colors.white.withValues(alpha: 0.08),
                                            width: 1.2,
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                // Avatar
                                                Container(
                                                  width: 44,
                                                  height: 44,
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFF4DA6FF).withValues(alpha: 0.15),
                                                    shape: BoxShape.circle,
                                                    border: Border.all(color: const Color(0xFF4DA6FF).withValues(alpha: 0.3)),
                                                  ),
                                                  child: ClipOval(
                                                    child: imageUrl != null && imageUrl.isNotEmpty
                                                        ? Image.network(
                                                            imageUrl,
                                                            fit: BoxFit.cover,
                                                            errorBuilder: (ctx, err, st) => const Icon(Icons.person, color: Colors.white54),
                                                          )
                                                        : const Icon(Icons.person, color: Colors.white54),
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        name,
                                                        style: poppins(
                                                          color: Colors.white,
                                                          fontWeight: FontWeight.bold,
                                                          fontSize: 15,
                                                        ),
                                                      ),
                                                      Text(
                                                        '$roll • $role • $team',
                                                        style: poppins(fontSize: 11, color: const Color(0xFF8A9CC2)),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                // Achievement badge
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                                  decoration: BoxDecoration(
                                                    color: (achieved ? const Color(0xFF00C48C) : const Color(0xFFFFB800)).withValues(alpha: 0.15),
                                                    borderRadius: BorderRadius.circular(12),
                                                    border: Border.all(
                                                      color: (achieved ? const Color(0xFF00C48C) : const Color(0xFFFFB800)).withValues(alpha: 0.3),
                                                    ),
                                                  ),
                                                  child: Text(
                                                    achieved ? 'Achieved' : 'Pending',
                                                    style: poppins(
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.bold,
                                                      color: achieved ? const Color(0xFF00C48C) : const Color(0xFFFFB800),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 14),
                                            // Progress bar
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Text(
                                                  'Progress: ${(progress * 100).toStringAsFixed(0)}%',
                                                  style: poppins(fontSize: 11, color: Colors.white60, fontWeight: FontWeight.bold),
                                                ),
                                                Text(
                                                  '${_formatDuration(weeklySec)} / ${_formatDuration(targetSec)}',
                                                  style: poppins(fontSize: 11, color: Colors.white60, fontWeight: FontWeight.bold),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 6),
                                            ClipRRect(
                                              borderRadius: BorderRadius.circular(4),
                                              child: LinearProgressIndicator(
                                                value: progress,
                                                minHeight: 6,
                                                backgroundColor: Colors.white10,
                                                valueColor: AlwaysStoppedAnimation<Color>(
                                                  achieved ? const Color(0xFF00C48C) : const Color(0xFF4DA6FF),
                                                ),
                                              ),
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
          ),
        ],
      ),
    );
  }
}
