import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'main.dart';

class StatisticsPage extends StatefulWidget {
  final UserData? userData;
  const StatisticsPage({super.key, this.userData});

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
      if (_isLead && widget.userData?.team != null) {
        url += '?team=${Uri.encodeComponent(widget.userData?.team ?? '')}';
      } else if (_isMember) {
        url += '?team=${Uri.encodeComponent(widget.userData?.team ?? '')}';
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

  void _onSearch(String query) {
    setState(() {
      _searchQuery = query.toLowerCase();
      _filtered = _allUsers.where((u) {
        final name = (u['name'] as String? ?? '').toLowerCase();
        final team = (u['team'] as String? ?? '').toLowerCase();
        final roll = (u['roll_number'] as String? ?? '').toLowerCase();
        return name.contains(_searchQuery) ||
            team.contains(_searchQuery) ||
            roll.contains(_searchQuery);
      }).toList();
    });
  }

  String _fmtSeconds(int s) {
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    return '${h}h ${m}m ${sec}s';
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
                                widget.userData?.team ?? '',
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

                // Search bar (Admin & Lead)
                if (!_isMember)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: _onSearch,
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
                                  _onSearch('');
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
                                        _buildMemberDashboard(
                                          _filtered.first,
                                          poppins,
                                        ),
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
                                        // Lead overview dashboard header
                                        if (_isLead) ...[
                                          _buildLeadDashboardHeader(
                                            poppins,
                                          ),
                                          const SizedBox(height: 8),
                                        ],

                                        // Summary bar chart
                                        if (_filtered.length > 1) ...[
                                          _buildBarChart(maxSec, poppins),
                                          const SizedBox(height: 16),
                                        ],

                                        // Top performer badge
                                        if (_filtered.isNotEmpty)
                                          _buildTopPerformerCard(
                                            _filtered.first,
                                            poppins,
                                          ),

                                        const SizedBox(height: 8),

                                        // User cards
                                        ..._filtered.asMap().entries.map((
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
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Work Hours — Top $displayCount',
            style: poppins(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13.0,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 140,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: topUsers.asMap().entries.map((entry) {
                final u = entry.value;
                final sec = (u['total_seconds'] as int? ?? 0).toDouble();
                final ratio = maxSec > 0 ? (sec / maxSec) : 0.0;
                final barH = (ratio * 110 * _anim.value).clamp(4.0, 110.0);
                final colors = [
                  [const Color(0xFF4DA6FF), const Color(0xFF2D8BE8)],
                  [const Color(0xFF00C48C), const Color(0xFF00A070)],
                  [const Color(0xFFFFD93D), const Color(0xFFF0C020)],
                  [const Color(0xFF9B59B6), const Color(0xFF7D3F9A)],
                  [const Color(0xFFFF6B6B), const Color(0xFFE05050)],
                  [const Color(0xFF4DA6FF), const Color(0xFF2D8BE8)],
                  [const Color(0xFF00C48C), const Color(0xFF00A070)],
                  [const Color(0xFFFFD93D), const Color(0xFFF0C020)],
                ];
                final colPair = colors[entry.key % colors.length];
                final name = (u['name'] as String? ?? '').split(' ').first;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          _fmtSeconds(sec.toInt()),
                          style: poppins(color: Colors.white70, fontSize: 8.0),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 3),
                        Container(
                          height: barH,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: colPair,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          name,
                          style: poppins(color: Colors.white54, fontSize: 8.0),
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
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
    return Container(
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
            child: Column(
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
                        color: const Color(0xFFFFD93D).withValues(alpha: 0.15),
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
                  '${u['team'] ?? ''} · ${_fmtSeconds(u['total_seconds'] as int? ?? 0)} worked',
                  style: poppins(color: Colors.white70, fontSize: 11.0),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserCard(
    int rank,
    Map<String, dynamic> u,
    double maxSec,
    dynamic poppins,
  ) {
    final totalSec = u['total_seconds'] as int? ?? 0;
    final weekSec = u['week_seconds'] as int? ?? 0;
    final loginCount = u['login_count'] as int? ?? 0;
    final attPct = (u['attendance_pct'] as num? ?? 100.0).toDouble();
    final sessions = u['total_sessions'] as int? ?? 0;
    final attPresent = u['attendance_present'] as int? ?? 0;
    final attTotal = u['attendance_total'] as int? ?? 0;

    final barRatio = maxSec > 0 ? (totalSec / maxSec).clamp(0.0, 1.0) : 0.0;
    final attRatio = attPct / 100.0;

    final rankColors = [
      const Color(0xFFFFD93D),
      const Color(0xFFB0B0B0),
      const Color(0xFFCD7F32),
    ];
    final rankColor = rank < 3 ? rankColors[rank] : const Color(0xFF4DA6FF);

    return AnimatedBuilder(
      animation: _anim,
      builder: (context, child) {
        return Container(
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
                    width: 28,
                    height: 28,
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
                        fontSize: 11.0,
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
                          u['name'] as String? ?? '',
                          style: poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13.0,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${u['team'] ?? ''} · ${u['roll_number'] ?? ''}',
                          style: poppins(color: Colors.white54, fontSize: 10.0),
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

              // Work hours bar
              _buildStatBar(
                'Work Hours',
                _fmtSeconds(totalSec),
                barRatio * _anim.value,
                const Color(0xFF4DA6FF),
                poppins,
              ),
              const SizedBox(height: 6),
              // Attendance bar
              _buildStatBar(
                'Attendance',
                '${attPct.toStringAsFixed(1)}% ($attPresent/$attTotal)',
                attRatio * _anim.value,
                attPct >= 75
                    ? const Color(0xFF00C48C)
                    : const Color(0xFFFF6B6B),
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
            ],
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
            Text(label, style: poppins(color: Colors.white70, fontSize: 10.0)),
            const Spacer(),
            Text(
              value,
              style: poppins(
                color: Colors.white,
                fontSize: 10.0,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: ratio.clamp(0.0, 1.0),
            minHeight: 5,
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

    // Calculate average session duration
    final avgSec = sessions > 0 ? (totalSec / sessions).round() : 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // User Card Profile Header
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
                  backgroundColor: const Color(
                    0xFF4DA6FF,
                  ).withValues(alpha: 0.2),
                  child: Text(
                    (u['name'] as String? ?? 'S').substring(0, 1).toUpperCase(),
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
                        '${u['role'] ?? 'Member'} · ${u['team'] ?? ''}',
                        style: poppins(color: Colors.white54, fontSize: 11.0),
                      ),
                      Text(
                        u['roll_number'] ?? '',
                        style: poppins(color: Colors.white30, fontSize: 10.0),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

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
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.4,
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
          const SizedBox(height: 16),
          _buildMemberGraphCard(totalSec, weekSec, avgSec, poppins),
        ],
      ),
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
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ],
          ),
          const Spacer(),
          Text(
            value,
            style: poppins(
              color: Colors.white,
              fontSize: 18.0,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: poppins(
              color: Colors.white70,
              fontSize: 11.0,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            subtitle,
            style: poppins(color: Colors.white30, fontSize: 8.0),
            overflow: TextOverflow.ellipsis,
          ),
        ],
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
                    color: Colors.white70,
                    fontSize: 11.0,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: poppins(color: Colors.white30, fontSize: 9.0),
                ),
              ],
            ),
          ),
          Text(
            value,
            style: poppins(
              color: Colors.white,
              fontSize: 18.0,
              fontWeight: FontWeight.bold,
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
            'Team Overview',
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
