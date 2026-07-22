import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'main.dart';
import 'analyse_users_page.dart';

class StatisticsPage extends StatefulWidget {
  final UserData? userData;
  final bool isActive;
  const StatisticsPage({super.key, this.userData, this.isActive = false});

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _allUsers = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _isLoading = true;
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();
  late AnimationController _animCtrl;
  late Animation<double> _anim;

  List<String> _leadTeams = [];
  String _selectedStatsTeam = 'All';
  int _selectedBarIndex = -1;
  int _selectedAttendanceBarIndex = -1;
  String _activeTab = 'logs'; // 'logs' or 'attendance'

  @override
  void didUpdateWidget(covariant StatisticsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _animCtrl.forward(from: 0);
    }
  }

  bool get _isAdmin => widget.userData?.role.toLowerCase() == 'admin';
  bool get _isLead => widget.userData?.role.toLowerCase() == 'lead';
  bool get _isMember => widget.userData != null && !_isAdmin && !_isLead;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _anim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _loadStats();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _searchCtrl.dispose();

    super.dispose();
  }

  Future<void> _loadStats() async {
    setState(() => _isLoading = true);
    try {
      String url = '$apiBaseUrl/api/stats/performance-summary';


      if (_isMember) {
        // Members load standard performance summary without team filtering duplication
      } else if (_isLead) {
        final teamList = (widget.userData?.team ?? '')
            .split(',')
            .map((t) => t.trim())
            .where((t) => t.isNotEmpty)
            .toList();

        if (mounted) {
          setState(() {
            _leadTeams = teamList;
          });
        }

        if (teamList.length > 1) {
          final Map<String, Map<String, dynamic>> emailToUser = {};
          for (final t in teamList) {
            final teamUrl =
                '$apiBaseUrl/api/stats/performance-summary?team=${Uri.encodeComponent(t)}';
            final teamRes = await http
                .get(Uri.parse(teamUrl))
                .timeout(const Duration(seconds: 20));
            if (teamRes.statusCode == 200) {
              final teamData = jsonDecode(teamRes.body);
              final teamUsers = List<Map<String, dynamic>>.from(
                teamData['users'] ?? [],
              );
              for (var tu in teamUsers) {
                final email = (tu['email'] as String? ?? '').toLowerCase().trim();
                if (email.isEmpty) continue;
                if (!emailToUser.containsKey(email)) {
                  emailToUser[email] = tu;
                } else {
                  // Merge teams
                  final existing = emailToUser[email]!;
                  final List<String> existingTeams = (existing['team'] as String? ?? '')
                      .split(',')
                      .map((x) => x.trim())
                      .where((x) => x.isNotEmpty)
                      .toList();
                  final List<String> newTeams = (tu['team'] as String? ?? '')
                      .split(',')
                      .map((x) => x.trim())
                      .where((x) => x.isNotEmpty)
                      .toList();
                  for (final nt in newTeams) {
                    if (!existingTeams.contains(nt)) {
                      existingTeams.add(nt);
                    }
                  }
                  existing['team'] = existingTeams.join(', ');

                  // Merge team_stats
                  final Map<String, dynamic> existingTeamStats = Map<String, dynamic>.from(existing['team_stats'] ?? {});
                  final Map<String, dynamic> newTeamStats = Map<String, dynamic>.from(tu['team_stats'] ?? {});
                  existingTeamStats.addAll(newTeamStats);
                  existing['team_stats'] = existingTeamStats;
                }
              }
            }
          }
          final combined = emailToUser.values.toList();
          if (mounted) {
            setState(() {
              _allUsers = combined;
              _filtered = combined;
            });
            _animCtrl.forward(from: 0);
          }
          return;
        }
        url +=
            '?team=${Uri.encodeComponent(teamList.isNotEmpty ? teamList.first : '')}';
      }

      final res = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 20));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        List<Map<String, dynamic>> users = List<Map<String, dynamic>>.from(
          data['users'] ?? [],
        );

        if (_isMember) {
          users = users
              .where(
                (u) =>
                    (u['email'] as String? ?? '').toLowerCase() ==
                    (widget.userData?.email ?? '').toLowerCase(),
              )
              .toList();
        }

        if (_isAdmin) {
          final Set<String> extractedTeams = {};
          for (var u in users) {
            final String? t = u['team'];
            if (t != null && t.isNotEmpty) {
              for (var part in t.split(',')) {
                final trimmed = part.trim();
                if (trimmed.isNotEmpty) {
                  extractedTeams.add(trimmed);
                }
              }
            }
          }
          if (mounted) {
            setState(() {
              _leadTeams = extractedTeams.toList()..sort();
            });
          }
        }

        if (mounted) {
          setState(() {
            _allUsers = users;
            _filtered = users;
          });
          _animCtrl.forward(from: 0);
        }
      }
    } catch (e) {
      debugPrint('Stats load error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyStatsFilter() {
    setState(() {
      _filtered = _allUsers.where((u) {
        final name = (u['name'] as String? ?? '').toLowerCase();
        final team = (u['team'] as String? ?? '').toLowerCase();
        final roll = (u['roll_number'] as String? ?? '').toLowerCase();
        final matchesSearch =
            name.contains(_searchQuery) ||
            team.contains(_searchQuery) ||
            roll.contains(_searchQuery);

        final List<String> userTeamsList = team
            .split(',')
            .map((t) => t.trim().toLowerCase())
            .toList();
        final matchesTeam =
            _selectedStatsTeam == 'All' ||
            userTeamsList.contains(_selectedStatsTeam.trim().toLowerCase());

        return matchesSearch && matchesTeam;
      }).toList();
    });
  }

  String _fmtSeconds(int s) {
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    return '${h}h ${m}m ${sec}s';
  }

  void _showUserAnalysis(String? email) {
    if (email == null || email.isEmpty) return;
    if (_isMember) return; // Members cannot inspect others
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DesktopPageWrapper(
          child: AnalyseUsersPage(
            userData: widget.userData,
            initialUserEmail: email,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final poppins = GoogleFonts.poppins;
    final maxSec = _allUsers.isNotEmpty
        ? (_allUsers
                  .map((u) => (u['total_seconds'] as int? ?? 0))
                  .reduce(math.max))
              .toDouble()
        : 1.0;

    final pageTitle = _isAdmin
        ? 'All Users — Performance'
        : _isLead
        ? 'Team Statistics'
        : 'My Statistics';

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          SafeArea(
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
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF4DA6FF), Color(0xFF9B59B6)],
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.bar_chart_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              pageTitle,
                              style: poppins(
                                fontSize: 16.0,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                              ),
                            ),
                            if (_isLead)
                              Text(
                                (widget.userData?.team ?? '')
                                    .split(',')
                                    .map((t) => t.trim())
                                    .join(' · '),
                                style: poppins(
                                  fontSize: 11.0,
                                  color: Colors.white54,
                                ),
                              ),
                            if (_isAdmin)
                              Text(
                                '${_allUsers.length} users',
                                style: poppins(
                                  fontSize: 11.0,
                                  color: Colors.white54,
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
                        onPressed: () {
                          _animCtrl.reset();
                          _loadStats();
                        },
                      ),
                    ],
                  ),
                ),

                // Search & Filter (Admin & Lead)
                if (!_isMember)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: Column(
                      children: [
                        TextField(
                          controller: _searchCtrl,
                          onChanged: (val) {
                            _searchQuery = val.toLowerCase();
                            _applyStatsFilter();
                          },
                          style: poppins(color: Colors.white, fontSize: 13.0),
                          decoration: InputDecoration(
                            hintText: 'Search by name, team, roll no...',
                            hintStyle: poppins(
                              color: Colors.white38,
                              fontSize: 12.0,
                            ),
                            prefixIcon: const Icon(
                              Icons.search_rounded,
                              color: Colors.white54,
                              size: 20,
                            ),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    onPressed: () {
                                      _searchCtrl.clear();
                                      _searchQuery = '';
                                      _applyStatsFilter();
                                    },
                                    icon: const Icon(
                                      Icons.close_rounded,
                                      color: Colors.white54,
                                      size: 18,
                                    ),
                                  )
                                : null,
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.06),
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        if (_isAdmin || _leadTeams.length > 1) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.1),
                              ),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _selectedStatsTeam,
                                isExpanded: true,
                                dropdownColor: const Color(0xFF1A2B4A),
                                icon: const Icon(
                                  Icons.keyboard_arrow_down,
                                  color: Color(0xFF4DA6FF),
                                  size: 18,
                                ),
                                items: ['All', ..._leadTeams]
                                    .map(
                                      (t) => DropdownMenuItem(
                                        value: t,
                                        child: Text(
                                          t == 'All' ? 'All Teams' : '$t Team',
                                          style: poppins(
                                            fontSize: 12,
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() => _selectedStatsTeam = val);
                                    _applyStatsFilter();
                                  }
                                },
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                // Content
                Expanded(
                  child: _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Color(0xFF4DA6FF),
                            ),
                          ),
                        )
                      : _filtered.isEmpty
                      ? Center(
                          child: Text(
                            'No performance data found.',
                            style: poppins(
                              color: Colors.white54,
                              fontSize: 13.0,
                            ),
                          ),
                        )
                      : AnimatedBuilder(
                          animation: _anim,
                          builder: (context, child) {
                            final displayUsers = List<Map<String, dynamic>>.from(_filtered);
                            if (_activeTab == 'logs') {
                              displayUsers.sort((a, b) {
                                final aSec = a['total_seconds'] as int? ?? 0;
                                final bSec = b['total_seconds'] as int? ?? 0;
                                return bSec.compareTo(aSec);
                              });
                            } else {
                              displayUsers.sort((a, b) {
                                final aPct = (a['attendance_pct'] as num? ?? 0.0).toDouble();
                                final bPct = (b['attendance_pct'] as num? ?? 0.0).toDouble();
                                if (bPct != aPct) {
                                  return bPct.compareTo(aPct);
                                }
                                final aPres = a['attendance_present'] as int? ?? 0;
                                final bPres = b['attendance_present'] as int? ?? 0;
                                return bPres.compareTo(aPres);
                              });
                            }

                            return RefreshIndicator(
                              onRefresh: _loadStats,
                              color: const Color(0xFF4DA6FF),
                              backgroundColor: const Color(0xFF1A2B4A),
                              child: _isMember
                                  ? ListView(
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        0,
                                        16,
                                        24,
                                      ),
                                      physics:
                                          const AlwaysScrollableScrollPhysics(),
                                      children: [
                                        // Show per-team stats for every entry
                                        // (multi-team members have multiple entries)
                                        ..._filtered.map(
                                          (u) =>
                                              _buildMemberDashboard(u, poppins),
                                        ),
                                        if (_filtered.isNotEmpty) ...[
                                          const SizedBox(height: 8),
                                          _buildMemberGraphCard(
                                            _filtered.first['total_seconds']
                                                    as int? ??
                                                0,
                                            _filtered.first['week_seconds']
                                                    as int? ??
                                                0,
                                            ((_filtered.first['total_sessions']
                                                            as int? ??
                                                        0) >
                                                    0)
                                                ? ((_filtered.first['total_seconds']
                                                                  as int? ??
                                                              0) /
                                                          (_filtered.first['total_sessions']
                                                                  as int? ??
                                                              1))
                                                      .round()
                                                : 0,
                                            poppins,
                                          ),
                                          const SizedBox(height: 16),
                                        ],
                                      ],
                                    )
                                  : ListView(
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        0,
                                        16,
                                        24,
                                      ),
                                      physics:
                                          const AlwaysScrollableScrollPhysics(),
                                      children: [
                                        // Lead/Admin overview dashboard header
                                        if (_isLead || _isAdmin) ...[
                                          _buildLeadDashboardHeader(poppins),
                                          const SizedBox(height: 8),
                                        ],

                                        // Segmented tab selector to toggle between Logs & Attendance
                                        if (!_isMember) ...[
                                          Container(
                                            margin: const EdgeInsets.only(bottom: 16),
                                            padding: const EdgeInsets.all(4),
                                            decoration: BoxDecoration(
                                              color: Colors.white.withValues(alpha: 0.05),
                                              borderRadius: BorderRadius.circular(14),
                                              border: Border.all(
                                                color: Colors.white.withValues(alpha: 0.08),
                                              ),
                                            ),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: GestureDetector(
                                                    onTap: () => setState(() => _activeTab = 'logs'),
                                                    child: AnimatedContainer(
                                                      duration: const Duration(milliseconds: 200),
                                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                                      decoration: BoxDecoration(
                                                        color: _activeTab == 'logs'
                                                            ? const Color(0xFF4DA6FF).withValues(alpha: 0.15)
                                                            : Colors.transparent,
                                                        borderRadius: BorderRadius.circular(10),
                                                        border: Border.all(
                                                          color: _activeTab == 'logs'
                                                              ? const Color(0xFF4DA6FF).withValues(alpha: 0.3)
                                                              : Colors.transparent,
                                                        ),
                                                      ),
                                                      child: Center(
                                                        child: Row(
                                                          mainAxisAlignment: MainAxisAlignment.center,
                                                          children: [
                                                            Icon(
                                                              Icons.timer_rounded,
                                                              color: _activeTab == 'logs' ? const Color(0xFF4DA6FF) : Colors.white60,
                                                              size: 16,
                                                            ),
                                                            const SizedBox(width: 6),
                                                            Text(
                                                              'Logs (Work Hours)',
                                                              style: poppins(
                                                                color: _activeTab == 'logs' ? const Color(0xFF4DA6FF) : Colors.white60,
                                                                fontWeight: FontWeight.bold,
                                                                fontSize: 11.5,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 4),
                                                Expanded(
                                                  child: GestureDetector(
                                                    onTap: () => setState(() => _activeTab = 'attendance'),
                                                    child: AnimatedContainer(
                                                      duration: const Duration(milliseconds: 200),
                                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                                      decoration: BoxDecoration(
                                                        color: _activeTab == 'attendance'
                                                            ? const Color(0xFF00C48C).withValues(alpha: 0.15)
                                                            : Colors.transparent,
                                                        borderRadius: BorderRadius.circular(10),
                                                        border: Border.all(
                                                          color: _activeTab == 'attendance'
                                                              ? const Color(0xFF00C48C).withValues(alpha: 0.3)
                                                              : Colors.transparent,
                                                        ),
                                                      ),
                                                      child: Center(
                                                        child: Row(
                                                          mainAxisAlignment: MainAxisAlignment.center,
                                                          children: [
                                                            Icon(
                                                              Icons.fact_check_rounded,
                                                              color: _activeTab == 'attendance' ? const Color(0xFF00C48C) : Colors.white60,
                                                              size: 16,
                                                            ),
                                                            const SizedBox(width: 6),
                                                            Text(
                                                              'Attendance',
                                                              style: poppins(
                                                                color: _activeTab == 'attendance' ? const Color(0xFF00C48C) : Colors.white60,
                                                                fontWeight: FontWeight.bold,
                                                                fontSize: 11.5,
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
                                          ),
                                        ],

                                        // Summary bar chart
                                        if (displayUsers.length > 1) ...[
                                          _activeTab == 'logs'
                                              ? _buildBarChart(maxSec, poppins)
                                              : _buildAttendanceBarChart(poppins),
                                          const SizedBox(height: 16),
                                        ],

                                        // Top performer badge
                                        if (displayUsers.isNotEmpty)
                                          _buildTopPerformerCard(
                                            displayUsers.first,
                                            poppins,
                                          ),

                                        const SizedBox(height: 8),

                                        // User cards
                                        ...displayUsers.asMap().entries.map((
                                          entry,
                                        ) {
                                          return _buildUserCard(
                                            entry.key,
                                            entry.value,
                                            maxSec,
                                            poppins,
                                          );
                                        }),
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

  Widget _buildBarChart(double maxSec, dynamic poppins) {
    final displayCount = math.min(_filtered.length, 8);
    final topUsers = _filtered.take(displayCount).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Work Hours — Top $displayCount Performance',
                style: poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13.0,
                ),
              ),
              if (_selectedBarIndex != -1 &&
                  _selectedBarIndex < topUsers.length)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4DA6FF).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFF4DA6FF).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    '${topUsers[_selectedBarIndex]['name'].split(' ').first}: ${_fmtSeconds((topUsers[_selectedBarIndex]['total_seconds'] as int? ?? 0))}',
                    style: poppins(
                      color: const Color(0xFF4DA6FF),
                      fontSize: 10.0,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 220,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: topUsers.asMap().entries.map((entry) {
                final u = entry.value;
                final sec = (u['total_seconds'] as int? ?? 0).toDouble();
                final ratio = maxSec > 0 ? (sec / maxSec) : 0.0;
                final isSelected = _selectedBarIndex == entry.key;

                final barH = (ratio * 150 * _anim.value).clamp(6.0, 150.0);

                final colors = [
                  [const Color(0xFF4DA6FF), const Color(0xFF007FFF)],
                  [const Color(0xFF00C48C), const Color(0xFF00966C)],
                  [const Color(0xFFFFD93D), const Color(0xFFFFB300)],
                  [const Color(0xFF9B59B6), const Color(0xFF8E44AD)],
                  [const Color(0xFFFF6B6B), const Color(0xFFE74C3C)],
                  [const Color(0xFF00E676), const Color(0xFF00B0FF)],
                  [const Color(0xFF1ABC9C), const Color(0xFF16A085)],
                  [const Color(0xFFE67E22), const Color(0xFFD35400)],
                ];
                final colPair = colors[entry.key % colors.length];
                final name = (u['name'] as String? ?? '').split(' ').first;

                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedBarIndex = isSelected ? -1 : entry.key;
                      });
                    },
                    behavior: HitTestBehavior.opaque,
                    child: AnimatedScale(
                      scale: isSelected ? 1.05 : 1.0,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              _fmtSeconds(sec.toInt()),
                              style: poppins(
                                color: isSelected
                                    ? const Color(0xFF4DA6FF)
                                    : Colors.white70,
                                fontSize: isSelected ? 9.5 : 8.0,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 6),
                            Container(
                              height: barH,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: isSelected
                                      ? [
                                          const Color(0xFF00DFFF),
                                          const Color(0xFF0084FF),
                                        ]
                                      : colPair,
                                ),
                                borderRadius: BorderRadius.circular(8),
                                border: isSelected
                                    ? Border.all(
                                        color: Colors.white,
                                        width: 1.5,
                                      )
                                    : Border.all(
                                        color: Colors.white.withValues(
                                          alpha: 0.1,
                                        ),
                                        width: 0.8,
                                      ),
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                        (isSelected
                                                ? const Color(0xFF00DFFF)
                                                : colPair.first)
                                            .withValues(
                                              alpha: isSelected ? 0.6 : 0.25,
                                            ),
                                    blurRadius: isSelected ? 12 : 6,
                                    spreadRadius: isSelected ? 2 : 0,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              name,
                              style: poppins(
                                color: isSelected
                                    ? const Color(0xFF4DA6FF)
                                    : Colors.white,
                                fontSize: isSelected ? 9.5 : 8.5,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceBarChart(dynamic poppins) {
    final displayCount = math.min(_filtered.length, 8);
    final topUsers = List<Map<String, dynamic>>.from(_filtered);
    topUsers.sort((a, b) {
      final aPct = (a['attendance_pct'] as num? ?? 0.0).toDouble();
      final bPct = (b['attendance_pct'] as num? ?? 0.0).toDouble();
      return bPct.compareTo(aPct);
    });
    final topAttendanceUsers = topUsers.take(displayCount).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Attendance — Top $displayCount Performance',
                style: poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13.0,
                ),
              ),
              if (_selectedAttendanceBarIndex != -1 &&
                  _selectedAttendanceBarIndex < topAttendanceUsers.length)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00C48C).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFF00C48C).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    '${topAttendanceUsers[_selectedAttendanceBarIndex]['name'].split(' ').first}: ${(topAttendanceUsers[_selectedAttendanceBarIndex]['attendance_pct'] as num? ?? 0.0).toDouble().toStringAsFixed(1)}%',
                    style: poppins(
                      color: const Color(0xFF00C48C),
                      fontSize: 10.0,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 220,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: topAttendanceUsers.asMap().entries.map((entry) {
                final u = entry.value;
                final pct = (u['attendance_pct'] as num? ?? 0.0).toDouble();
                final ratio = pct / 100.0;
                final isSelected = _selectedAttendanceBarIndex == entry.key;

                final barH = (ratio * 150 * _anim.value).clamp(6.0, 150.0);

                final colors = [
                  [const Color(0xFF00C48C), const Color(0xFF00966C)],
                  [const Color(0xFF4DA6FF), const Color(0xFF007FFF)],
                  [const Color(0xFFFFD93D), const Color(0xFFFFB300)],
                  [const Color(0xFF9B59B6), const Color(0xFF8E44AD)],
                  [const Color(0xFFFF6B6B), const Color(0xFFE74C3C)],
                  [const Color(0xFF00E676), const Color(0xFF00B0FF)],
                  [const Color(0xFF1ABC9C), const Color(0xFF16A085)],
                  [const Color(0xFFE67E22), const Color(0xFFD35400)],
                ];
                final colPair = colors[entry.key % colors.length];
                final name = (u['name'] as String? ?? '').split(' ').first;

                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedAttendanceBarIndex = isSelected ? -1 : entry.key;
                      });
                    },
                    behavior: HitTestBehavior.opaque,
                    child: AnimatedScale(
                      scale: isSelected ? 1.05 : 1.0,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              '${pct.toStringAsFixed(0)}%',
                              style: poppins(
                                color: isSelected
                                    ? const Color(0xFF00C48C)
                                    : Colors.white70,
                                fontSize: isSelected ? 9.5 : 8.0,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 6),
                            Container(
                              height: barH,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: isSelected
                                      ? [
                                          const Color(0xFF00FFC4),
                                          const Color(0xFF00966C),
                                        ]
                                      : colPair,
                                ),
                                borderRadius: BorderRadius.circular(8),
                                border: isSelected
                                    ? Border.all(
                                        color: Colors.white,
                                        width: 1.5,
                                      )
                                    : Border.all(
                                        color: Colors.white.withValues(
                                          alpha: 0.1,
                                        ),
                                        width: 0.8,
                                      ),
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                        (isSelected
                                                ? const Color(0xFF00FFC4)
                                                : colPair.first)
                                            .withValues(
                                              alpha: isSelected ? 0.6 : 0.25,
                                            ),
                                    blurRadius: isSelected ? 12 : 6,
                                    spreadRadius: isSelected ? 2 : 0,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              name,
                              style: poppins(
                                color: isSelected
                                    ? const Color(0xFF00C48C)
                                    : Colors.white,
                                fontSize: isSelected ? 9.5 : 8.5,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopPerformerCard(Map<String, dynamic> u, dynamic poppins) {
    return GestureDetector(
      onTap: () => _showUserAnalysis(u['email'] as String?),
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFFFFD93D).withValues(alpha: 0.12),
              const Color(0xFF4DA6FF).withValues(alpha: 0.08),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFFFFD93D).withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFFFD93D).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Icon(
                  Icons.workspace_premium_rounded,
                  color: Color(0xFFFFD93D),
                  size: 26,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Builder(builder: (context) {
                // Always use global totals — no per-team split
                final totalSec = u['total_seconds'] as int? ?? 0;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Top Performer',
                          style: poppins(
                            color: const Color(0xFFFFD93D),
                            fontSize: 11.0,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFFFFD93D,
                            ).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            u['role'] as String? ?? '',
                            style: poppins(
                              color: const Color(0xFFFFD93D),
                              fontSize: 9.0,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      u['name'] as String? ?? '',
                      style: poppins(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14.0,
                      ),
                    ),
                    Text(
                      u['email'] as String? ?? '',
                      style: poppins(
                        color: const Color(0xFF4DA6FF),
                        fontSize: 10.0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A2B4A),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.15),
                            ),
                          ),
                          child: Text(
                            (u['team'] as String? ?? '').isNotEmpty ? (u['team'] as String) : 'N/A',
                            style: poppins(
                              color: Colors.white,
                              fontSize: 10.0,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '·  ${_fmtSeconds(totalSec)} worked',
                          style: poppins(color: Colors.white70, fontSize: 11.0),
                        ),
                      ],
                    ),
                  ],
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserCard(
    int rank,
    Map<String, dynamic> u,
    double maxSec,
    dynamic poppins,
  ) {

    // Always use global totals — team dropdown removed, no per-team split needed
    final totalSec = u['total_seconds'] as int? ?? 0;
    final weekSec = u['week_seconds'] as int? ?? 0;
    final loginCount = u['login_count'] as int? ?? 0;
    final sessions = u['total_sessions'] as int? ?? 0;

    final attPct = (u['attendance_pct'] as num? ?? 0.0).toDouble();
    final attPresent = u['attendance_present'] as int? ?? 0;
    final attTotal = u['attendance_total'] as int? ?? 0;
    final attRatio = attPct / 100.0;

    final barRatio = maxSec > 0 ? (totalSec / maxSec).clamp(0.0, 1.0) : 0.0;

    final rankColors = [
      const Color(0xFFFFD93D),
      const Color(0xFFB0B0B0),
      const Color(0xFFCD7F32),
    ];
    final rankColor = rank < 3 ? rankColors[rank] : const Color(0xFF4DA6FF);

    return AnimatedBuilder(
      animation: _anim,
      builder: (context, child) {
        return GestureDetector(
          onTap: () => _showUserAnalysis(u['email'] as String?),
          behavior: HitTestBehavior.opaque,
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: rankColor.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: rankColor.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        '${rank + 1}',
                        style: poppins(
                          color: rankColor,
                          fontSize: 10.0,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                      backgroundImage:
                          u['image_url'] != null &&
                              u['image_url'].toString().isNotEmpty
                          ? NetworkImage(u['image_url'])
                          : null,
                      child:
                          u['image_url'] != null &&
                              u['image_url'].toString().isNotEmpty
                          ? null
                          : Text(
                              (u['name'] as String? ?? 'S')
                                  .substring(0, 1)
                                  .toUpperCase(),
                              style: poppins(
                                color: Colors.white70,
                                fontSize: 10.0,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            u['name'] as String? ?? 'N/A',
                            style: poppins(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13.0,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Roll: ${u['roll_number'] ?? ''}',
                            style: poppins(
                              color: Colors.white54,
                              fontSize: 10.0,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A2B4A),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.15),
                              ),
                            ),
                            child: Text(
                              (u['team'] as String? ?? '').isNotEmpty ? (u['team'] as String) : 'N/A',
                              style: poppins(
                                color: Colors.white,
                                fontSize: 10.0,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _roleColor(
                          u['role'] as String? ?? '',
                        ).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        u['role'] as String? ?? '',
                        style: poppins(
                          color: _roleColor(u['role'] as String? ?? ''),
                          fontSize: 10.0,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                if (_activeTab == 'logs') ...[
                  // Work hours bar
                  _buildStatBar(
                    'Work Hours',
                    _fmtSeconds(totalSec),
                    barRatio * _anim.value,
                    const Color(0xFF4DA6FF),
                    poppins,
                  ),
                  const SizedBox(height: 10),
                  // Stat chips
                  Row(
                    children: [
                      _chip(
                        '$sessions',
                        'Sessions',
                        const Color(0xFF9B59B6),
                        poppins,
                      ),
                      const SizedBox(width: 6),
                      _chip(
                        '$loginCount',
                        'Logins',
                        const Color(0xFFFFD93D),
                        poppins,
                      ),
                      const SizedBox(width: 6),
                      _chip(
                        _fmtSeconds(weekSec),
                        'This Week',
                        const Color(0xFF00C48C),
                        poppins,
                      ),
                    ],
                  ),
                ] else ...[
                  // Attendance bar
                  Builder(
                    builder: (context) {
                      final int attOnDuty = u['attendance_on_duty'] as int? ?? 0;
                      final String displayStats = attOnDuty > 0
                          ? '$attPresent/$attTotal | $attOnDuty OD'
                          : '$attPresent/$attTotal';
                      return _buildStatBar(
                        'Attendance',
                        '${attPct.toStringAsFixed(1)}% ($displayStats)',
                        attRatio * _anim.value,
                        attPct >= 75
                            ? const Color(0xFF00C48C)
                            : const Color(0xFFFF6B6B),
                        poppins,
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  // Stat chips for attendance details
                  Row(
                    children: [
                      _chip(
                        '$attPresent',
                        'Present',
                        const Color(0xFF00C48C),
                        poppins,
                      ),
                      const SizedBox(width: 6),
                      _chip(
                        '$attTotal',
                        'Total Days',
                        const Color(0xFF4DA6FF),
                        poppins,
                      ),
                      const SizedBox(width: 6),
                      _chip(
                        '${u['attendance_on_duty'] as int? ?? 0}',
                        'On Duty',
                        const Color(0xFFFFD93D),
                        poppins,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatBar(
    String label,
    String value,
    double ratio,
    Color color,
    dynamic poppins,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: poppins(
                color: Colors.white70,
                fontSize: 11.0,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            Text(
              value,
              style: poppins(
                color: Colors.white,
                fontSize: 12.0,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: LinearProgressIndicator(
            value: ratio.clamp(0.0, 1.0),
            minHeight: 10,
            backgroundColor: Colors.white.withValues(alpha: 0.07),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }

  Widget _chip(String value, String label, Color color, dynamic poppins) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: poppins(
                color: color,
                fontSize: 11.0,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(label, style: poppins(color: Colors.white54, fontSize: 9.0)),
          ],
        ),
      ),
    );
  }

  Color _roleColor(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
        return const Color(0xFFFFD93D);
      case 'lead':
        return const Color(0xFF4DA6FF);
      default:
        return const Color(0xFF00C48C);
    }
  }

  Widget _buildMemberDashboard(Map<String, dynamic> u, dynamic poppins) {
    final totalSec = u['total_seconds'] as int? ?? 0;
    final weekSec = u['week_seconds'] as int? ?? 0;
    final sessions = u['total_sessions'] as int? ?? 0;
    final attPct = (u['attendance_pct'] as num? ?? 100.0).toDouble();
    final attPresent = u['attendance_present'] as int? ?? 0;
    final attTotal = u['attendance_total'] as int? ?? 0;
    final teamLabel = u['team'] as String? ?? '';

    // Calculate average session duration
    final avgSec = sessions > 0 ? (totalSec / sessions).round() : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // User Card Profile Header with team badge
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF4DA6FF).withValues(alpha: 0.15),
                const Color(0xFF9B59B6).withValues(alpha: 0.1),
              ],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: const Color(0xFF4DA6FF).withValues(alpha: 0.2),
                backgroundImage:
                    u['image_url'] != null &&
                        u['image_url'].toString().isNotEmpty
                    ? NetworkImage(u['image_url'])
                    : null,
                child:
                    u['image_url'] != null &&
                        u['image_url'].toString().isNotEmpty
                    ? null
                    : Text(
                        (u['name'] as String? ?? 'S')
                            .substring(0, 1)
                            .toUpperCase(),
                        style: poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18.0,
                        ),
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      u['name'] as String? ?? '',
                      style: poppins(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15.0,
                      ),
                    ),
                    Text(
                      '${u['role'] ?? 'Member'} · $teamLabel',
                      style: poppins(color: Colors.white54, fontSize: 11.0),
                    ),
                    Text(
                      u['roll_number'] ?? '',
                      style: poppins(color: Colors.white30, fontSize: 10.0),
                    ),
                  ],
                ),
              ),
              // Team pill badge
              if (teamLabel.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4DA6FF).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFF4DA6FF).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    teamLabel,
                    style: poppins(
                      color: const Color(0xFF4DA6FF),
                      fontSize: 10.0,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Dashboard Title
        Text(
          'Personal Dashboard',
          style: poppins(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 14.0,
          ),
        ),
        const SizedBox(height: 12),

        // 2x2 Grid of statistics
        Builder(
          builder: (context) {
            double textScale = MediaQuery.textScalerOf(context).scale(1.0);
            if (textScale < 1.0) textScale = 1.0;
            final double adjustedRatio = (1.4 / textScale).clamp(1.0, 1.4);

            return GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: adjustedRatio,
              children: [
                _dashboardCard(
                  'Work Hours',
                  _fmtSeconds(totalSec),
                  'Total duration logged',
                  Icons.timer_rounded,
                  const Color(0xFF4DA6FF),
                  poppins,
                ),
                _dashboardCard(
                  'Attendance',
                  '${attPct.toStringAsFixed(1)}%',
                  '$attPresent of $attTotal present',
                  Icons.fact_check_rounded,
                  attPct >= 75
                      ? const Color(0xFF00C48C)
                      : const Color(0xFFFF6B6B),
                  poppins,
                ),
                _dashboardCard(
                  'Sessions',
                  '$sessions',
                  'Total activity check-ins',
                  Icons.login_rounded,
                  const Color(0xFFFFD93D),
                  poppins,
                ),
                _dashboardCard(
                  'Avg Session',
                  _fmtSeconds(avgSec),
                  'Per check-in duration',
                  Icons.av_timer_rounded,
                  const Color(0xFF9B59B6),
                  poppins,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),

        // Extra Stats Card (Full Width)
        _fullWidthStatCard(
          'Activity This Week',
          _fmtSeconds(weekSec),
          'Hours logged in the last 7 days',
          Icons.show_chart_rounded,
          const Color(0xFF00C48C),
          poppins,
        ),
        const SizedBox(height: 24),

        // Team divider if more entries follow
        Divider(color: Colors.white.withValues(alpha: 0.08), thickness: 1),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildMemberGraphCard(
    int totalSec,
    int weekSec,
    int avgSec,
    dynamic poppins,
  ) {
    final maxVal = math.max(
      1.0,
      math.max(totalSec.toDouble(), math.max(weekSec.toDouble(), avgSec * 5.0)),
    );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Activity Breakdown',
            style: poppins(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14.0,
            ),
          ),
          const SizedBox(height: 16),
          _buildGraphBar(
            'Total Logged',
            totalSec.toDouble(),
            maxVal,
            const Color(0xFF4DA6FF),
            poppins,
          ),
          const SizedBox(height: 12),
          _buildGraphBar(
            'This Week',
            weekSec.toDouble(),
            maxVal,
            const Color(0xFF00C48C),
            poppins,
          ),
          const SizedBox(height: 12),
          _buildGraphBar(
            'Avg per Session',
            avgSec.toDouble(),
            maxVal,
            const Color(0xFFFFD93D),
            poppins,
          ),
        ],
      ),
    );
  }

  Widget _buildGraphBar(
    String label,
    double sec,
    double maxSec,
    Color color,
    dynamic poppins,
  ) {
    final ratio = maxSec > 0 ? (sec / maxSec) : 0.0;
    final widthFactor = (ratio * _anim.value).clamp(0.01, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: poppins(
                color: Colors.white70,
                fontSize: 11.0,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              _fmtSeconds(sec.toInt()),
              style: poppins(
                color: Colors.white,
                fontSize: 11.0,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          height: 14,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: widthFactor,
            child: Container(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 6),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _dashboardCard(
    String title,
    String value,
    String subtitle,
    IconData icon,
    Color color,
    dynamic poppins,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 18),
                const Spacer(),
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: poppins(
                color: Colors.white,
                fontSize: 20.0,
                fontWeight: FontWeight.w900,
                shadows: [
                  Shadow(color: color.withValues(alpha: 0.3), blurRadius: 8),
                ],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              style: poppins(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 12.0,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              subtitle,
              style: poppins(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 9.0,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _fullWidthStatCard(
    String title,
    String value,
    String subtitle,
    IconData icon,
    Color color,
    dynamic poppins,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: poppins(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 12.0,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: poppins(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 10.0,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Text(
            value,
            style: poppins(
              color: Colors.white,
              fontSize: 20.0,
              fontWeight: FontWeight.w900,
              shadows: [
                Shadow(color: color.withValues(alpha: 0.3), blurRadius: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeadDashboardHeader(dynamic poppins) {
    if (_filtered.isEmpty) return const SizedBox.shrink();

    final memberCount = _filtered.length;
    final totalTeamSeconds = _filtered.fold<int>(
      0,
      (sum, u) => sum + (u['total_seconds'] as int? ?? 0),
    );
    final avgTeamSeconds = memberCount > 0
        ? (totalTeamSeconds / memberCount).round()
        : 0;

    final totalAttPct = _filtered.fold<double>(
      0.0,
      (sum, u) => sum + (u['attendance_pct'] as num? ?? 100.0).toDouble(),
    );
    final avgAttPct = memberCount > 0 ? totalAttPct / memberCount : 100.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF4DA6FF).withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isAdmin ? 'Club Overview' : 'Team Overview',
            style: poppins(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12.0,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _teamOverviewItem(
                'Members',
                '$memberCount',
                Icons.people_rounded,
                const Color(0xFF4DA6FF),
                poppins,
              ),
              _teamOverviewItem(
                'Avg Work',
                _fmtSeconds(avgTeamSeconds),
                Icons.timer_rounded,
                const Color(0xFF9B59B6),
                poppins,
              ),
              _teamOverviewItem(
                'Avg Attendance',
                '${avgAttPct.toStringAsFixed(1)}%',
                Icons.fact_check_rounded,
                const Color(0xFF00C48C),
                poppins,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _teamOverviewItem(
    String label,
    String value,
    IconData icon,
    Color color,
    dynamic poppins,
  ) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: color.withValues(alpha: 0.8), size: 20),
          const SizedBox(height: 6),
          Text(
            value,
            style: poppins(
              color: Colors.white,
              fontSize: 14.0,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: poppins(color: Colors.white54, fontSize: 9.0),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
