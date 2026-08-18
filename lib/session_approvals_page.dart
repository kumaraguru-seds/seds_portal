import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'app_toast.dart';
import 'main.dart';

final ValueNotifier<int> pendingSessionApprovalsCountNotifier =
    ValueNotifier<int>(0);

Widget buildSessionApprovalsButton(
  BuildContext context,
  UserData? userData, {
  required TextStyle Function({
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
    double? letterSpacing,
  })
  poppins,
}) {
  return ValueListenableBuilder<int>(
    valueListenable: pendingSessionApprovalsCountNotifier,
    builder: (context, count, child) {
      return Container(
        margin: const EdgeInsets.only(right: 14, top: 10, bottom: 10),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        SessionApprovalsPage(userData: userData),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: count > 0
                      ? const Color(0xFFFF3B30).withValues(alpha: 0.18)
                      : Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: count > 0
                        ? const Color(0xFFFF3B30).withValues(alpha: 0.6)
                        : Colors.white.withValues(alpha: 0.15),
                    width: count > 0 ? 1.5 : 1.0,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.rule_folder_rounded,
                      color: count > 0
                          ? const Color(0xFFFF453A)
                          : const Color(0xFF4DA6FF),
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Approvals',
                      style: poppins(
                        fontSize: 12.0,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (count > 0)
              Positioned(
                top: -4,
                right: -4,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Color(0xFFFF3B30),
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 18,
                    minHeight: 18,
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

class SessionApprovalsPage extends StatefulWidget {
  final UserData? userData;

  const SessionApprovalsPage({super.key, this.userData});

  @override
  State<SessionApprovalsPage> createState() => _SessionApprovalsPageState();
}

class _SessionApprovalsPageState extends State<SessionApprovalsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;

  // Data
  List<Map<String, dynamic>> _pendingRequests = [];
  Map<String, List<Map<String, dynamic>>> _pendingApprovers = {};
  List<Map<String, dynamic>> _approvedSessions = [];

  // Filter & Search states
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _dateFilter = 'All'; // 'All', 'Today', 'This Week'
  bool _sortAscending = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      setState(
        () {},
      ); // refresh view to reset search or update UI on tab switch
    });
    _loadAllData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    await Future.wait([_fetchPendingRequests(), _fetchApprovedSessions()]);
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchPendingRequests() async {
    final email = widget.userData?.email;
    final role = widget.userData?.role;
    if (email == null || role == null) return;

    try {
      final res = await http
          .get(
            Uri.parse(
              '$apiBaseUrl/api/logs/pending-approvals?email=${Uri.encodeComponent(email)}&role=${Uri.encodeComponent(role)}',
            ),
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final list = List<Map<String, dynamic>>.from(data['requests'] ?? []);
        final rawApprovers = data['approvers'] as Map<String, dynamic>? ?? {};

        final parsedApprovers = <String, List<Map<String, dynamic>>>{};
        rawApprovers.forEach((key, val) {
          if (val is List) {
            parsedApprovers[key] = List<Map<String, dynamic>>.from(
              val.map((x) => Map<String, dynamic>.from(x)),
            );
          }
        });

        if (mounted) {
          setState(() {
            _pendingRequests = list;
            _pendingApprovers = parsedApprovers;
          });
          pendingSessionApprovalsCountNotifier.value = list.length;
        }
      }
    } catch (e) {
      debugPrint('Error loading pending approvals: $e');
    }
  }

  Future<void> _fetchApprovedSessions() async {
    final email = widget.userData?.email;
    final role = widget.userData?.role;
    if (email == null || role == null) return;

    try {
      final res = await http
          .get(
            Uri.parse(
              '$apiBaseUrl/api/logs/approved-sessions?email=${Uri.encodeComponent(email)}&role=${Uri.encodeComponent(role)}',
            ),
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final list = List<Map<String, dynamic>>.from(data['sessions'] ?? []);
        if (mounted) {
          setState(() {
            _approvedSessions = list;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading approved sessions: $e');
    }
  }

  Future<void> _handleAction(String sessionId, String action) async {
    final approvedByEmail = widget.userData?.email ?? '';
    final approvedByName = widget.userData?.name ?? '';

    try {
      final res = await http.post(
        Uri.parse('$apiBaseUrl/api/logs/approve-start'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'session_id': int.tryParse(sessionId) ?? 0,
          'action': action,
          'approved_by_email': approvedByEmail,
          'approved_by_name': approvedByName,
        }),
      );

      if (!mounted) return;

      if (res.statusCode == 200) {
        final resData = jsonDecode(res.body);
        if (resData['success'] == true) {
          AppToast.show(
            context,
            'Session request ${action == 'approved' ? 'approved' : 'declined'} successfully.',
            type: ToastType.success,
          );
          _loadAllData();
        } else {
          AppToast.show(
            context,
            resData['message'] ?? 'Failed to update request.',
            type: ToastType.error,
          );
        }
      } else {
        AppToast.show(
          context,
          'Server returned error response.',
          type: ToastType.error,
        );
      }
    } catch (e) {
      if (!mounted) return;
      AppToast.show(
        context,
        'Error communicating with server.',
        type: ToastType.error,
      );
    }
  }

  bool _isDateMatch(DateTime? dt) {
    if (dt == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dtDay = DateTime(dt.year, dt.month, dt.day);

    if (_dateFilter == 'Today') {
      return dtDay.isAtSameMomentAs(today);
    }

    if (_dateFilter == 'This Week') {
      final int daysSinceSunday = now.weekday == 7 ? 0 : now.weekday;
      final sunday = today.subtract(Duration(days: daysSinceSunday));
      final saturday = sunday.add(
        const Duration(days: 6, hours: 23, minutes: 59, seconds: 59),
      );
      return (dt.isAfter(sunday) || dt.isAtSameMomentAs(sunday)) &&
          (dt.isBefore(saturday) || dt.isAtSameMomentAs(saturday));
    }

    return true; // 'All'
  }

  List<Map<String, dynamic>> _getFilteredList(
    List<Map<String, dynamic>> original,
    bool isPending,
  ) {
    final query = _searchQuery.toLowerCase().trim();

    // 1. Filter by Search Query & Date
    final filtered = original.where((item) {
      final name = (item['user_name'] ?? '').toString().toLowerCase();
      final roll = (item['roll_number'] ?? '').toString().toLowerCase();
      final team = (item['team'] ?? '').toString().toLowerCase();

      final matchesSearch =
          query.isEmpty ||
          name.contains(query) ||
          roll.contains(query) ||
          team.contains(query);

      if (!matchesSearch) return false;

      // Date match logic — pending items use created_at (start_time is NULL until approved)
      DateTime? dt;
      if (isPending) {
        dt = DateTime.tryParse(
          item['created_at'] ?? item['start_time'] ?? '',
        )?.toLocal();
      } else {
        dt = DateTime.tryParse(
          item['approved_at'] ?? item['start_time'] ?? '',
        )?.toLocal();
      }
      return _isDateMatch(dt);
    }).toList();

    // 2. Sort by time
    filtered.sort((a, b) {
      DateTime? dtA, dtB;
      if (isPending) {
        // Use created_at for pending — start_time is NULL until approved
        dtA = DateTime.tryParse(
          a['created_at'] ?? a['start_time'] ?? '',
        )?.toLocal();
        dtB = DateTime.tryParse(
          b['created_at'] ?? b['start_time'] ?? '',
        )?.toLocal();
      } else {
        dtA = DateTime.tryParse(
          a['approved_at'] ?? a['start_time'] ?? '',
        )?.toLocal();
        dtB = DateTime.tryParse(
          b['approved_at'] ?? b['start_time'] ?? '',
        )?.toLocal();
      }
      dtA ??= DateTime(2000);
      dtB ??= DateTime(2000);

      return _sortAscending ? dtA.compareTo(dtB) : dtB.compareTo(dtA);
    });

    return filtered;
  }

  String _formatDateTime(String? dateStr) {
    if (dateStr == null) return 'N/A';
    final dt = DateTime.tryParse(dateStr)?.toLocal();
    if (dt == null) return 'N/A';

    final period = dt.hour >= 12 ? 'PM' : 'AM';
    var hour12 = dt.hour % 12;
    if (hour12 == 0) hour12 = 12;
    final time12 = '$hour12:${dt.minute.toString().padLeft(2, '0')} $period';

    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} at $time12';
  }

  TextStyle _ts({
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
    double? letterSpacing,
  }) => GoogleFonts.poppins(
    color: color,
    fontSize: fontSize,
    fontWeight: fontWeight,
    letterSpacing: letterSpacing,
  );

  @override
  Widget build(BuildContext context) {
    final currentTabPending = _tabController.index == 0;
    final displayList = currentTabPending
        ? _getFilteredList(_pendingRequests, true)
        : _getFilteredList(_approvedSessions, false);

    return Scaffold(
      backgroundColor: const Color(0xFF0D1E3A),
      body: Stack(
        children: [
          if (!kIsWeb) ...[
            Positioned.fill(
              child: Image.asset(
                'assets/background.png',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    Container(color: const Color(0xFF0D1E3A)),
              ),
            ),
            Positioned.fill(
              child: Container(color: Colors.black.withValues(alpha: 0.5)),
            ),
          ],

          SafeArea(
            child: Column(
              children: [
                // ── Header Bar ──────────────────────────────────────────
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
                          size: 20,
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Approvals Hub',
                              style: _ts(
                                fontSize: 20.0,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              'Manage and review user sessions',
                              style: _ts(
                                fontSize: 12.0,
                                color: const Color(0xFF8A9CC2),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.refresh_rounded,
                          color: Color(0xFF4DA6FF),
                        ),
                        onPressed: _loadAllData,
                      ),
                    ],
                  ),
                ),

                // ── Tab Bar ─────────────────────────────────────────────
                TabBar(
                  controller: _tabController,
                  indicatorColor: const Color(0xFF4DA6FF),
                  labelColor: const Color(0xFF4DA6FF),
                  unselectedLabelColor: Colors.white38,
                  labelStyle: _ts(fontWeight: FontWeight.bold, fontSize: 14.0),
                  unselectedLabelStyle: _ts(
                    fontWeight: FontWeight.w500,
                    fontSize: 14.0,
                  ),
                  tabs: [
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.pending_actions_rounded, size: 18),
                          const SizedBox(width: 6),
                          Text('Pending (${_pendingRequests.length})'),
                        ],
                      ),
                    ),
                    const Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.history_rounded, size: 18),
                          SizedBox(width: 6),
                          Text('History'),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // ── Search & Filter Controls ─────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      // Search field
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                        ),
                        child: TextField(
                          controller: _searchController,
                          style: _ts(color: Colors.white, fontSize: 13.0),
                          onChanged: (v) => setState(() => _searchQuery = v),
                          decoration: InputDecoration(
                            hintText: 'Search by user, roll or team...',
                            hintStyle: _ts(
                              color: Colors.white38,
                              fontSize: 13.0,
                            ),
                            prefixIcon: const Icon(
                              Icons.search_rounded,
                              color: Color(0xFF4DA6FF),
                              size: 20,
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 16,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Filters and Sort Row
                      Row(
                        children: [
                          // Date Range Filter Chips
                          Expanded(
                            child: SizedBox(
                              height: 36,
                              child: ListView(
                                scrollDirection: Axis.horizontal,
                                children: ['All', 'Today', 'This Week'].map((
                                  f,
                                ) {
                                  final isSelected = _dateFilter == f;
                                  return GestureDetector(
                                    onTap: () =>
                                        setState(() => _dateFilter = f),
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 150,
                                      ),
                                      margin: const EdgeInsets.only(right: 8),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? const Color(
                                                0xFF4DA6FF,
                                              ).withValues(alpha: 0.18)
                                            : Colors.white.withValues(
                                                alpha: 0.05,
                                              ),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: isSelected
                                              ? const Color(
                                                  0xFF4DA6FF,
                                                ).withValues(alpha: 0.45)
                                              : Colors.white.withValues(
                                                  alpha: 0.08,
                                                ),
                                        ),
                                      ),
                                      child: Center(
                                        child: Text(
                                          f,
                                          style: _ts(
                                            color: isSelected
                                                ? const Color(0xFF4DA6FF)
                                                : Colors.white54,
                                            fontSize: 12.0,
                                            fontWeight: isSelected
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),

                          // Sort Button
                          GestureDetector(
                            onTap: () => setState(
                              () => _sortAscending = !_sortAscending,
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.white10),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _sortAscending
                                        ? Icons.arrow_upward_rounded
                                        : Icons.arrow_downward_rounded,
                                    color: const Color(0xFF4DA6FF),
                                    size: 16,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _sortAscending ? 'Oldest' : 'Newest',
                                    style: _ts(
                                      color: Colors.white70,
                                      fontSize: 11.0,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),
                const Divider(color: Colors.white10, height: 1),

                // ── Main List Container ─────────────────────────────────
                Expanded(
                  child: _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFF4DA6FF),
                          ),
                        )
                      : displayList.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(
                              height: MediaQuery.of(context).size.height * 0.18,
                            ),
                            Center(
                              child: Column(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(20),
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFF4DA6FF,
                                      ).withValues(alpha: 0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      currentTabPending
                                          ? Icons.check_circle_outline_rounded
                                          : Icons.history_toggle_off_rounded,
                                      color: const Color(0xFF4DA6FF),
                                      size: 56,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    currentTabPending
                                        ? 'No Pending Requests'
                                        : 'No History Found',
                                    style: _ts(
                                      fontSize: 18.0,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    currentTabPending
                                        ? 'All member session start requests have been processed.'
                                        : 'No approved or declined work sessions match your filters.',
                                    style: _ts(
                                      fontSize: 13.0,
                                      color: const Color(0xFF8A9CC2),
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                          itemCount: displayList.length,
                          itemBuilder: (context, idx) {
                            final item = displayList[idx];
                            return currentTabPending
                                ? _buildPendingCard(item)
                                : _buildApprovedCard(item);
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

  Widget _buildPendingCard(Map<String, dynamic> req) {
    final name = req['user_name'] ?? 'Unknown User';
    final role = req['role'] ?? 'Member';
    final team = req['team'] ?? 'N/A';
    final roll = req['roll_number'] ?? '';
    final timeStr = _formatDateTime(req['created_at'] ?? req['start_time']);
    final reqId = req['id'].toString();

    // Fetch lists of leads/admins who received/will receive this request
    final approversList = _pendingApprovers[reqId] ?? [];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2B4A).withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Container(
                  width: 44,
                  height: 44,
                  color: const Color(0xFF4DA6FF).withValues(alpha: 0.2),
                  child:
                      (req['image_url'] != null &&
                          (req['image_url'] as String).isNotEmpty)
                      ? Image.network(
                          req['image_url'],
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Center(
                              child: Text(
                                name.isNotEmpty ? name[0].toUpperCase() : 'U',
                                style: _ts(
                                  fontSize: 16.0,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF4DA6FF),
                                ),
                              ),
                            );
                          },
                        )
                      : Center(
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : 'U',
                            style: _ts(
                              fontSize: 16.0,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF4DA6FF),
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: _ts(
                        fontSize: 15.0,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$role  •  $team ${roll.isNotEmpty ? '•  $roll' : ''}',
                      style: _ts(
                        fontSize: 11.5,
                        color: const Color(0xFF8A9CC2),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.orangeAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.orangeAccent.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  'Pending',
                  style: _ts(
                    fontSize: 10.0,
                    fontWeight: FontWeight.bold,
                    color: Colors.orangeAccent,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(
                Icons.schedule_rounded,
                size: 14,
                color: Colors.white38,
              ),
              const SizedBox(width: 6),
              Text(
                'Requested: $timeStr',
                style: _ts(fontSize: 11.0, color: Colors.white54),
              ),
            ],
          ),

          // Show Leads / Admins who received notifications
          if (approversList.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Divider(color: Colors.white10, height: 1),
            const SizedBox(height: 8),
            Text(
              'Sent to Approvers:',
              style: _ts(
                fontSize: 11.0,
                color: const Color(0xFF4DA6FF),
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: approversList.map((a) {
                final isLead = a['role'] == 'Lead';
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.05),
                    ),
                  ),
                  child: Text(
                    '${a['name']} (${a['role']})',
                    style: _ts(
                      fontSize: 10.0,
                      color: isLead
                          ? Colors.orangeAccent
                          : const Color(0xFF00C48C),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],

          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _handleAction(reqId, 'approved'),
                  icon: const Icon(Icons.check_circle_rounded, size: 18),
                  label: Text(
                    'Approve',
                    style: _ts(fontWeight: FontWeight.bold, fontSize: 13.0),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00C48C),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _handleAction(reqId, 'declined'),
                  icon: const Icon(Icons.cancel_rounded, size: 18),
                  label: Text(
                    'Decline',
                    style: _ts(fontWeight: FontWeight.bold, fontSize: 13.0),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6B6B),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildApprovedCard(Map<String, dynamic> session) {
    final name = session['user_name'] ?? 'Unknown User';
    final role = session['role'] ?? 'Member';
    final team = session['team'] ?? 'N/A';
    final roll = session['roll_number'] ?? '';
    final timeStr = _formatDateTime(session['start_time']);
    final approvedTimeStr = _formatDateTime(session['approved_at']);

    final status = (session['status'] ?? 'approved').toString().toLowerCase();
    final isApproved = status == 'approved';

    final approvedByEmail = session['approved_by_email'] ?? '';
    final approvedByName = session['approved_by_name'] ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2B4A).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isApproved
              ? const Color(0xFF00C48C).withValues(alpha: 0.2)
              : const Color(0xFFFF6B6B).withValues(alpha: 0.2),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Container(
                  width: 44,
                  height: 44,
                  color: isApproved
                      ? const Color(0xFF00C48C).withValues(alpha: 0.15)
                      : const Color(0xFFFF6B6B).withValues(alpha: 0.15),
                  child:
                      (session['image_url'] != null &&
                          (session['image_url'] as String).isNotEmpty)
                      ? Image.network(
                          session['image_url'],
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Center(
                              child: Text(
                                name.isNotEmpty ? name[0].toUpperCase() : 'U',
                                style: _ts(
                                  fontSize: 16.0,
                                  fontWeight: FontWeight.bold,
                                  color: isApproved
                                      ? const Color(0xFF00C48C)
                                      : const Color(0xFFFF6B6B),
                                ),
                              ),
                            );
                          },
                        )
                      : Center(
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : 'U',
                            style: _ts(
                              fontSize: 16.0,
                              fontWeight: FontWeight.bold,
                              color: isApproved
                                  ? const Color(0xFF00C48C)
                                  : const Color(0xFFFF6B6B),
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: _ts(
                        fontSize: 15.0,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$role  •  $team ${roll.isNotEmpty ? '•  $roll' : ''}',
                      style: _ts(
                        fontSize: 11.5,
                        color: const Color(0xFF8A9CC2),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: isApproved
                      ? const Color(0xFF00C48C).withValues(alpha: 0.15)
                      : const Color(0xFFFF6B6B).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isApproved
                        ? const Color(0xFF00C48C).withValues(alpha: 0.3)
                        : const Color(0xFFFF6B6B).withValues(alpha: 0.3),
                  ),
                ),
                isAntiAlias: false,
                child: Text(
                  isApproved ? 'Approved' : 'Declined',
                  style: _ts(
                    fontSize: 10.0,
                    fontWeight: FontWeight.bold,
                    color: isApproved
                        ? const Color(0xFF00C48C)
                        : const Color(0xFFFF6B6B),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(
                Icons.schedule_rounded,
                size: 14,
                color: Colors.white38,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Requested: $timeStr',
                  style: _ts(fontSize: 11.0, color: Colors.white54),
                ),
              ),
            ],
          ),

          if (approvedByEmail.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  isApproved
                      ? Icons.verified_user_rounded
                      : Icons.gpp_bad_rounded,
                  size: 14,
                  color: isApproved
                      ? const Color(0xFF00C48C)
                      : const Color(0xFFFF6B6B),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${isApproved ? "Approved" : "Declined"} by: ${approvedByName.isNotEmpty ? approvedByName : approvedByEmail}',
                    style: _ts(
                      fontSize: 11.5,
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(
                  Icons.event_available_rounded,
                  size: 14,
                  color: Colors.white38,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Processed: $approvedTimeStr',
                    style: _ts(fontSize: 11.0, color: Colors.white54),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
