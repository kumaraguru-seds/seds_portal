import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'app_toast.dart';
import 'package:dio/dio.dart' as dio_pkg;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'main.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DocumentsPage — Dedicated Full-Screen Page
// ─────────────────────────────────────────────────────────────────────────────
class DocumentsPage extends StatelessWidget {
  final UserData? userData;
  const DocumentsPage({super.key, this.userData});

  @override
  Widget build(BuildContext context) {
    final poppins = GoogleFonts.poppins;
    return Scaffold(
      backgroundColor: const Color(0xFF0D1E3A),
      body: Stack(
        children: [
          // Background Image
          Positioned.fill(
            child: Image.asset(
              'assets/background.png',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  Container(color: const Color(0xFF0D1E3A)),
            ),
          ),
          // Blur overlay
          Positioned.fill(
            child: Container(color: Colors.black.withValues(alpha: 0.45)),
          ),
          // Content
          SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4DA6FF).withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.folder_shared_rounded,
                          color: Color(0xFF4DA6FF),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Documents & Files',
                              style: poppins(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              'Access and upload team files',
                              style: poppins(
                                fontSize: 11,
                                color: const Color(0xFF8A9CC2),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(color: Colors.white10, height: 1),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24.0),
                    child: DocumentsSection(userData: userData),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DocumentsSection Widget
// ─────────────────────────────────────────────────────────────────────────────
class DocumentsSection extends StatefulWidget {
  final UserData? userData;
  const DocumentsSection({super.key, this.userData});

  @override
  State<DocumentsSection> createState() => _DocumentsSectionState();
}

class _DocumentsSectionState extends State<DocumentsSection> {
  bool _isLoading = true;
  bool _showDeleted = false;
  List<dynamic> _documents = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchDocuments();
  }

  Future<void> _fetchDocuments() async {
    if (widget.userData == null) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final dio = dio_pkg.Dio();
      final response = await dio.get(
        '$apiBaseUrl/api/documents',
        queryParameters: {
          'email': widget.userData!.email,
          'role': widget.userData!.role,
          'team': widget.userData!.team ?? '',
          'status': _showDeleted ? 'deleted' : 'available',
        },
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        setState(() {
          _documents = response.data['documents'] ?? [];
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = response.data['message'] ?? 'Failed to load documents.';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Connection error: Could not load documents.';
        _isLoading = false;
      });
    }
  }

  void _showUploadModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _UploadDocumentModal(
        userData: widget.userData,
        onUploadComplete: () {
          Navigator.pop(ctx);
          _fetchDocuments();
        },
      ),
    );
  }

  Future<void> _viewDocument(String url) async {
    _showOpenOptions(url);
  }

  void _showOpenOptions(String link) {
    final poppins = GoogleFonts.poppins;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF162544),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Open File',
              style: poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline, color: Color(0xFF4DA6FF)),
              title: Text('Open with Google Drive App', style: poppins(color: Colors.white)),
              subtitle: Text('Launches Google Drive app natively', style: poppins(color: Colors.white54, fontSize: 12)),
              onTap: () {
                Navigator.pop(ctx);
                _launchFileLink(link, forceDrive: true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.language_rounded, color: Color(0xFF00C48C)),
              title: Text('Open in Web Browser', style: poppins(color: Colors.white)),
              subtitle: Text('Opens Chrome, Safari, or default browser', style: poppins(color: Colors.white54, fontSize: 12)),
              onTap: () {
                Navigator.pop(ctx);
                _launchFileLink(link, forceDrive: false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_rounded, color: Colors.amber),
              title: Text('Copy Link to Clipboard', style: poppins(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                Clipboard.setData(ClipboardData(text: link));
                AppToast.success(context, 'Link copied to clipboard!');
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _launchFileLink(String url, {required bool forceDrive}) async {
    try {
      String finalUrl = url;
      if (forceDrive) {
        final driveId = _getDriveId(url);
        if (driveId != null) {
          finalUrl = 'googledrive://docs.google.com/file/d/$driveId/view';
        }
      }
      
      final uri = Uri.parse(finalUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        final webUri = Uri.parse(url);
        if (await canLaunchUrl(webUri)) {
          await launchUrl(webUri, mode: LaunchMode.externalApplication);
        } else {
          if (mounted) {
            AppToast.error(context, 'Could not open document link.');
          }
        }
      }
    } catch (e) {
      final webUri = Uri.parse(url);
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _deleteDocument(int docId) async {
    if (widget.userData == null) return;
    setState(() {
      _isLoading = true;
    });
    try {
      final dio = dio_pkg.Dio();
      final response = await dio.delete(
        '$apiBaseUrl/api/documents/$docId',
        queryParameters: {
          'email': widget.userData!.email,
          'role': widget.userData!.role,
        },
      );

      if (!mounted) return;
      if (response.statusCode == 200 && response.data['success'] == true) {
        AppToast.success(context, 'Document moved to trash successfully.');
        _fetchDocuments();
      } else {
        AppToast.error(context, response.data['message'] ?? 'Failed to delete document.');
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, 'Connection error: Could not delete document.');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _confirmDeleteDocument(int docId, String fileName) {
    final poppins = GoogleFonts.poppins;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF162544),
        title: Text(
          'Delete Document',
          style: poppins(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to delete "$fileName"? This will permanently remove the file from the portal and Google Drive.',
          style: poppins(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: poppins(color: Colors.white54, fontWeight: FontWeight.bold),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF6B6B)),
            onPressed: () {
              Navigator.pop(ctx);
              _deleteDocument(docId);
            },
            child: Text(
              'Delete',
              style: poppins(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _restoreDocument(int docId) async {
    if (widget.userData == null) return;
    setState(() {
      _isLoading = true;
    });
    try {
      final dio = dio_pkg.Dio();
      final response = await dio.post(
        '$apiBaseUrl/api/documents/$docId/restore',
        queryParameters: {
          'email': widget.userData!.email,
          'role': widget.userData!.role,
        },
      );

      if (!mounted) return;
      if (response.statusCode == 200 && response.data['success'] == true) {
        AppToast.success(context, 'Document restored successfully!');
        _fetchDocuments();
      } else {
        AppToast.error(context, response.data['message'] ?? 'Failed to restore document.');
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, 'Connection error: Could not restore document.');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _confirmRestoreDocument(int docId, String fileName) {
    final poppins = GoogleFonts.poppins;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF162544),
        title: Text(
          'Restore Document',
          style: poppins(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to restore "$fileName"? This will make it available again on the portal.',
          style: poppins(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: poppins(color: Colors.white54, fontWeight: FontWeight.bold),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00C48C)),
            onPressed: () {
              Navigator.pop(ctx);
              _restoreDocument(docId);
            },
            child: Text(
              'Restore',
              style: poppins(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    var i = 0;
    double d = bytes.toDouble();
    while (d >= 1024 && i < suffixes.length - 1) {
      d /= 1024;
      i++;
    }
    return '${d.toStringAsFixed(1)} ${suffixes[i]}';
  }


  @override
  Widget build(BuildContext context) {
    final poppins = GoogleFonts.poppins;
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width > 700;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _showDeleted ? 'Trash / Deleted Files' : 'Shared Files',
              style: poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: _showDeleted ? const Color(0xFFFF6B6B) : const Color(0xFF8A9CC2),
              ),
            ),
            Row(
              children: [
                IconButton(
                  onPressed: () {
                    setState(() {
                      _showDeleted = !_showDeleted;
                    });
                    _fetchDocuments();
                  },
                  tooltip: _showDeleted ? 'View Active Files' : 'View Trash / Deleted Files',
                  icon: Icon(
                    _showDeleted ? Icons.unarchive_rounded : Icons.delete_sweep_rounded,
                    color: _showDeleted ? const Color(0xFFFF6B6B) : const Color(0xFF8A9CC2),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _showUploadModal,
                  icon: const Icon(Icons.upload_file_rounded, size: 18),
                  label: Text(
                    'Upload File',
                    style: poppins(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4DA6FF),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),

        // List / Grid Container
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: _isLoading
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24.0),
                    child: CircularProgressIndicator(color: Color(0xFF4DA6FF)),
                  ),
                )
              : _errorMessage != null
                  ? Center(
                      child: Text(
                        _errorMessage!,
                        style: poppins(color: const Color(0xFFFF6B6B), fontSize: 13),
                      ),
                    )
                  : _documents.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Column(
                              children: [
                                Icon(Icons.folder_open_rounded, size: 40, color: Colors.white.withValues(alpha: 0.3)),
                                const SizedBox(height: 10),
                                Text(
                                  'No documents available or shared with you.',
                                  style: poppins(color: const Color(0xFF8A9CC2), fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        )
                      : isDesktop
                          ? GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 320,
                                mainAxisSpacing: 16,
                                crossAxisSpacing: 16,
                                mainAxisExtent: 400, // Fits visual previews, description and details without overlapping
                              ),
                              itemCount: _documents.length,
                              itemBuilder: (context, idx) => _buildDocCard(_documents[idx]),
                            )
                          : ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _documents.length,
                              separatorBuilder: (context, index) => const SizedBox(height: 12),
                              itemBuilder: (context, idx) => _buildDocCard(_documents[idx]),
                            ),
        ),
      ],
    );
  }

  String? _getDriveId(String link) {
    final RegExp regExp = RegExp(r'/d/([a-zA-Z0-9_-]+)');
    final match = regExp.firstMatch(link);
    if (match != null && match.groupCount >= 1) {
      return match.group(1);
    }
    final uri = Uri.tryParse(link);
    if (uri != null) {
      return uri.queryParameters['id'];
    }
    return null;
  }

  Widget _buildDocCard(dynamic doc) {
    final poppins = GoogleFonts.poppins;
    final String name = doc['file_name'] ?? 'File';
    final int size = int.tryParse(doc['file_size']?.toString() ?? '0') ?? 0;
    final String ext = doc['file_extension'] ?? '';
    final String uploader = doc['user_name'] ?? 'SEDS User';
    final String uploaderRole = doc['role'] ?? 'Member';
    final String rollNo = doc['roll_number'] ?? '';
    final String summary = doc['summary'] ?? 'No description provided.';
    final String link = doc['drive_link'] ?? '';
    final String visibility = doc['visibility_type'] ?? 'anyone';
    final String? target = doc['visibility_target'];
    final String timeStr = doc['upload_time'] != null
        ? DateTime.parse(doc['upload_time']).toLocal().toString().substring(0, 16)
        : '';

    String visLabel = 'Anyone';
    if (visibility == 'admin') visLabel = 'Admins Only';
    if (visibility == 'lead') visLabel = 'Leads & Admins';
    if (visibility == 'team') visLabel = '${target ?? "Team"} Only';
    if (visibility == 'person') visLabel = 'Private File';

    final fileColor = _getFileColor(ext);
    final driveId = _getDriveId(link);
    final bool canDelete = (widget.userData?.email != null &&
            doc['user_email']?.toString().toLowerCase().trim() == widget.userData!.email.toLowerCase().trim()) ||
        widget.userData?.role == 'Admin' ||
        widget.userData?.role == 'SuperAdmin';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // Type Icon container
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: fileColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_getFileIcon(ext), color: fileColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: poppins(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatBytes(size),
                      style: poppins(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              if (_showDeleted && canDelete) ...[
                IconButton(
                  icon: const Icon(Icons.restore_rounded, color: Color(0xFF00C48C), size: 18),
                  onPressed: () => _confirmRestoreDocument(doc['id'], name),
                  tooltip: 'Restore File',
                ),
              ] else if (!_showDeleted && canDelete) ...[
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFFF6B6B), size: 18),
                  onPressed: () => _confirmDeleteDocument(doc['id'], name),
                  tooltip: 'Delete File',
                ),
              ],
              IconButton(
                icon: const Icon(Icons.open_in_new_rounded, color: Color(0xFF4DA6FF), size: 18),
                onPressed: () => _viewDocument(link),
                tooltip: 'View File',
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Description / Summary Box
          Text(
            summary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: poppins(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              color: Colors.white.withValues(alpha: 0.9),
              fontWeight: FontWeight.w600,
            ),
          ),
          // Large Visual Preview Cover (for ALL documents: PDFs, Images, HTMLs, text, sheets, docx)
          if (driveId != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                height: 140, // Elegant landscape aspect ratio
                color: Colors.white.withValues(alpha: 0.03),
                child: Image.network(
                  'https://drive.google.com/thumbnail?id=$driveId&sz=w600',
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    color: fileColor.withValues(alpha: 0.05),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(_getFileIcon(ext), color: fileColor, size: 36),
                          const SizedBox(height: 8),
                          Text(
                            'Preview not available',
                            style: poppins(fontSize: 11, color: const Color(0xFF8A9CC2)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return const Center(
                      child: CircularProgressIndicator(color: Color(0xFF4DA6FF)),
                    );
                  },
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          const Divider(color: Colors.white10, height: 1),
          const SizedBox(height: 12),
          // Metadata Row
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Left Column: Uploader info (bold & bright)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      text: TextSpan(
                        style: poppins(fontSize: 11, color: Colors.white),
                        children: [
                          TextSpan(text: 'Uploader: ', style: poppins(color: const Color(0xFF8A9CC2), fontWeight: FontWeight.bold)),
                          TextSpan(text: uploader, style: poppins(color: Colors.white, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    if (rollNo.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      RichText(
                        text: TextSpan(
                          style: poppins(fontSize: 10, color: Colors.white),
                          children: [
                            TextSpan(text: 'Roll No: ', style: poppins(color: const Color(0xFF8A9CC2), fontWeight: FontWeight.bold)),
                            TextSpan(text: rollNo, style: poppins(color: Colors.white, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 3),
                    RichText(
                      text: TextSpan(
                        style: poppins(fontSize: 10, color: Colors.white),
                        children: [
                          TextSpan(text: 'Role: ', style: poppins(color: const Color(0xFF8A9CC2), fontWeight: FontWeight.bold)),
                          TextSpan(text: uploaderRole, style: poppins(color: Colors.white, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Right Column: Date, Time & Visibility
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    timeStr,
                    style: poppins(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4DA6FF).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF4DA6FF).withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      visLabel,
                      style: poppins(fontSize: 10, color: const Color(0xFF4DA6FF), fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Upload Modal with Target Recipient Search & Description Field
// ─────────────────────────────────────────────────────────────────────────────
class _UploadDocumentModal extends StatefulWidget {
  final UserData? userData;
  final VoidCallback onUploadComplete;
  const _UploadDocumentModal({this.userData, required this.onUploadComplete});

  @override
  State<_UploadDocumentModal> createState() => _UploadDocumentModalState();
}

class _UploadDocumentModalState extends State<_UploadDocumentModal> {
  final List<PlatformFile> _selectedFiles = [];
  bool _isUploading = false;
  int _uploadingIndex = 0;
  double _uploadProgress = 0.0;
  int _uploadedBytes = 0;
  int _totalBytes = 0;
  dio_pkg.CancelToken? _cancelToken;

  String _visibilityType = 'anyone';
  final _searchController = TextEditingController();
  final _summaryController = TextEditingController();

  List<String> _teams = [];
  String _selectedTeam = '';

  @override
  void initState() {
    super.initState();
    _loadTeams();
  }

  Future<void> _loadTeams() async {
    final teams = await fetchUniqueTeams();
    if (mounted) {
      setState(() {
        _teams = teams;
        if (teams.isNotEmpty) {
          _selectedTeam = teams.first;
        }
      });
    }
  }

  // Search autocomplete variables
  List<Map<String, dynamic>> _searchResults = [];
  List<Map<String, dynamic>> _selectedTargetUsers = [];
  bool _isSearching = false;

  Future<void> _searchUsers(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
      });
      return;
    }
    setState(() {
      _isSearching = true;
    });
    try {
      final dio = dio_pkg.Dio();
      final response = await dio.get(
        '$apiBaseUrl/api/users/search',
        queryParameters: {'q': query},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        setState(() {
          _searchResults = List<Map<String, dynamic>>.from(data);
        });
      }
    } catch (e) {
      debugPrint('Error searching users: $e');
    } finally {
      setState(() {
        _isSearching = false;
      });
    }
  }

  Future<void> _pickFile() async {
    final poppins = GoogleFonts.poppins;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: true,
      );

      if (result != null && result.files.isNotEmpty) {
        List<PlatformFile> validFiles = [];
        List<String> largeFileNames = [];

        for (var file in result.files) {
          if (file.size > 10 * 1024 * 1024) {
            largeFileNames.add('${file.name} (${(file.size / (1024 * 1024)).toStringAsFixed(2)} MB)');
          } else {
            if (!_selectedFiles.any((f) => f.name == file.name && f.size == file.size)) {
              validFiles.add(file);
            }
          }
        }

        if (largeFileNames.isNotEmpty && mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFF162544),
              title: Text(
                'Some Files Too Large',
                style: poppins(color: const Color(0xFFFF6B6B), fontWeight: FontWeight.bold),
              ),
              content: Text(
                'The following files exceed the 10 MB limit and were skipped:\n\n${largeFileNames.join('\n')}',
                style: poppins(color: Colors.white70),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('OK', style: poppins(color: const Color(0xFF4DA6FF), fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
        }

        if (validFiles.isNotEmpty) {
          setState(() {
            _selectedFiles.addAll(validFiles);
          });
        }
      }
    } catch (e) {
      debugPrint('File picker error: $e');
    }
  }

  Future<void> _startUpload() async {
    if (_selectedFiles.isEmpty || widget.userData == null) return;

    final summaryText = _summaryController.text.trim();

    if (summaryText.isEmpty) {
      AppToast.warning(context, 'Please enter a description/summary of the file.');
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadingIndex = 0;
    });

    _cancelToken = dio_pkg.CancelToken();

    try {
      final dio = dio_pkg.Dio();
      
      String targetVal = '';
      if (_visibilityType == 'team') {
        targetVal = _selectedTeam;
      } else if (_visibilityType == 'person') {
        if (_selectedTargetUsers.isEmpty) {
          AppToast.warning(context, 'Please select at least one recipient user.');
          setState(() => _isUploading = false);
          return;
        }
        targetVal = _selectedTargetUsers.map((u) => u['email']).join(',');
      }

      for (int i = 0; i < _selectedFiles.length; i++) {
        final file = _selectedFiles[i];
        setState(() {
          _uploadingIndex = i;
          _uploadProgress = 0.0;
          _uploadedBytes = 0;
          _totalBytes = 0;
        });

        dio_pkg.MultipartFile filePayload;
        if (kIsWeb) {
          filePayload = dio_pkg.MultipartFile.fromBytes(
            file.bytes!,
            filename: file.name,
          );
        } else {
          filePayload = await dio_pkg.MultipartFile.fromFile(
            file.path!,
            filename: file.name,
          );
        }

        final formData = dio_pkg.FormData.fromMap({
          'email': widget.userData!.email,
          'name': widget.userData!.name,
          'roll_number': widget.userData!.rollNumber,
          'role': widget.userData!.role,
          'visibility_type': _visibilityType,
          'visibility_target': targetVal,
          'summary': summaryText,
          'file': filePayload,
        });

        final response = await dio.post(
          '$apiBaseUrl/api/documents/upload',
          data: formData,
          cancelToken: _cancelToken,
          onSendProgress: (sent, total) {
            if (total > 0) {
              setState(() {
                _uploadProgress = sent / total;
                _uploadedBytes = sent;
                _totalBytes = total;
              });
            }
          },
        );

        if (response.statusCode != 200 || response.data['success'] != true) {
          if (mounted) AppToast.error(context, response.data['message'] ?? 'Upload failed for ${file.name}.');
          setState(() => _isUploading = false);
          return;
        }
      }

      widget.onUploadComplete();
    } catch (e) {
      if (!dio_pkg.DioException.connectionError.toString().contains('cancel')) {
        if (mounted) AppToast.error(context, 'Upload failed or was cancelled.');
      }
      setState(() => _isUploading = false);
    }
  }

  void _cancelUpload() {
    _cancelToken?.cancel();
    setState(() {
      _isUploading = false;
      _uploadProgress = 0.0;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _summaryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final poppins = GoogleFonts.poppins;
    final isLeadOrAdmin = widget.userData?.role == 'Lead' ||
        widget.userData?.role == 'Admin' ||
        widget.userData?.role == 'SuperAdmin';

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF162544),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 48,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Upload Document',
              style: poppins(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 18),

            // Pre-filled Info fields
            _buildPrefilledField('Uploader Name', widget.userData?.name ?? '', poppins),
            const SizedBox(height: 12),
            _buildPrefilledField('Uploader Email', widget.userData?.email ?? '', poppins),
            const SizedBox(height: 16),

            // Visibility options (restricted feature for Leads & Admins only)
            if (isLeadOrAdmin) ...[
              Text(
                'Restrict View Permissions',
                style: poppins(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF4DA6FF)),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    dropdownColor: const Color(0xFF162544),
                    value: _visibilityType,
                    icon: const Icon(Icons.arrow_drop_down, color: Colors.white54),
                    isExpanded: true,
                    style: poppins(color: Colors.white, fontSize: 14),
                    items: [
                      const DropdownMenuItem(value: 'anyone', child: Text('Anyone (Public)')),
                      const DropdownMenuItem(value: 'admin', child: Text('Only Admins')),
                      const DropdownMenuItem(value: 'lead', child: Text('Only Leads & Admins')),
                      const DropdownMenuItem(value: 'team', child: Text('Specific Team')),
                      const DropdownMenuItem(value: 'person', child: Text('Specific Person (Email)')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _visibilityType = val;
                          _selectedTargetUsers = [];
                          _searchResults = [];
                          _searchController.clear();
                        });
                      }
                    },
                  ),
                ),
              ),
              if (_visibilityType == 'team' && _selectedTeam.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Select Team',
                  style: poppins(fontSize: 11, color: const Color(0xFF8A9CC2)),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      dropdownColor: const Color(0xFF162544),
                      value: _selectedTeam,
                      isExpanded: true,
                      style: poppins(color: Colors.white, fontSize: 14),
                      items: _teams.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _selectedTeam = val;
                          });
                        }
                      },
                    ),
                  ),
                ),
              ],
              if (_visibilityType == 'person') ...[
                const SizedBox(height: 12),
                if (_selectedTargetUsers.isNotEmpty) ...[
                  Text(
                    'Selected Recipients (${_selectedTargetUsers.length})',
                    style: poppins(fontSize: 11, color: const Color(0xFF8A9CC2)),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _selectedTargetUsers.map((user) {
                      return Chip(
                        label: Text(
                          '${user['name']} (${user['role']})',
                          style: poppins(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        deleteIcon: const Icon(Icons.close_rounded, size: 14, color: Colors.white70),
                        onDeleted: () {
                          setState(() {
                            _selectedTargetUsers.remove(user);
                          });
                        },
                        backgroundColor: const Color(0xFF00C48C).withValues(alpha: 0.15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: const BorderSide(color: Color(0xFF00C48C)),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                ],
                // User Search Input Field
                TextField(
                  controller: _searchController,
                  style: poppins(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'Search Specific Recipients',
                    labelStyle: poppins(color: const Color(0xFF8A9CC2), fontSize: 13),
                    hintText: 'Enter name, email, or roll no...',
                    hintStyle: poppins(color: Colors.white24, fontSize: 13),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.05),
                    prefixIcon: const Icon(Icons.search_rounded, color: Colors.white38),
                    suffixIcon: _isSearching
                        ? const Padding(
                            padding: EdgeInsets.all(12.0),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(color: Color(0xFF4DA6FF), strokeWidth: 2),
                            ),
                          )
                        : null,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF4DA6FF)),
                    ),
                  ),
                  onChanged: _searchUsers,
                ),
                if (_searchResults.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 180),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1F2F52),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _searchResults.length,
                      separatorBuilder: (ctx, idx) => const Divider(color: Colors.white10, height: 1),
                      itemBuilder: (ctx, index) {
                        final user = _searchResults[index];
                        return ListTile(
                          dense: true,
                          title: Text(
                            user['name'] ?? '',
                            style: poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          subtitle: Text(
                            '${user['role']} • ${user['email']}',
                            style: poppins(color: const Color(0xFF8A9CC2), fontSize: 11),
                          ),
                          trailing: Text(
                            user['roll_number'] ?? '',
                            style: poppins(color: Colors.white38, fontSize: 11),
                          ),
                          onTap: () {
                            setState(() {
                              if (!_selectedTargetUsers.any((u) => u['email'] == user['email'])) {
                                _selectedTargetUsers.add(user);
                              }
                              _searchResults = [];
                              _searchController.clear();
                            });
                          },
                        );
                      },
                    ),
                  ),
                ],
              ],
            ] else ...[
              // Members default to public uploads
              _buildPrefilledField('Visibility', 'Anyone (Public)', poppins),
            ],
            const SizedBox(height: 16),

            // Summary Field (Required description for all uploads)
            Text(
              'Document Description / Summary *',
              style: poppins(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF4DA6FF)),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _summaryController,
              maxLines: 3,
              style: poppins(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Enter brief summary about this file (e.g. Minutes of SEDS events, Web dev logo)...',
                hintStyle: poppins(color: Colors.white24, fontSize: 12),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF4DA6FF)),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // File selection
            GestureDetector(
              onTap: _isUploading ? null : _pickFile,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _selectedFiles.isEmpty ? Colors.white24 : const Color(0xFF00C48C),
                    style: BorderStyle.solid,
                    width: 1.5,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      _selectedFiles.isEmpty ? Icons.cloud_upload_outlined : Icons.check_circle_outline_rounded,
                      color: _selectedFiles.isEmpty ? const Color(0xFF8A9CC2) : const Color(0xFF00C48C),
                      size: 32,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _selectedFiles.isEmpty ? 'Select Documents to Upload' : 'Add More Documents',
                      style: poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: _selectedFiles.isEmpty ? Colors.white70 : const Color(0xFF4DA6FF),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Maximum file size: 10 MB per file',
                      style: poppins(
                        fontSize: 11,
                        color: const Color(0xFFFF6B6B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Selected Files List
            if (_selectedFiles.isNotEmpty) ...[
              Text(
                'Selected Files (${_selectedFiles.length})',
                style: poppins(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF8A9CC2)),
              ),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 180),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.02),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const ClampingScrollPhysics(),
                  itemCount: _selectedFiles.length,
                  separatorBuilder: (ctx, idx) => const Divider(color: Colors.white10, height: 1),
                  itemBuilder: (ctx, index) {
                    final file = _selectedFiles[index];
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        _getFileIcon(file.extension ?? ''),
                        color: _getFileColor(file.extension ?? ''),
                        size: 20,
                      ),
                      title: Text(
                        file.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: poppins(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        'Size: ${(file.size / (1024 * 1024)).toStringAsFixed(2)} MB',
                        style: poppins(color: const Color(0xFF8A9CC2), fontSize: 11),
                      ),
                      trailing: _isUploading
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFFF6B6B), size: 18),
                              onPressed: () {
                                setState(() {
                                  _selectedFiles.removeAt(index);
                                });
                              },
                            ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Progress bar
            if (_isUploading) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Uploading File ${_uploadingIndex + 1} of ${_selectedFiles.length}...',
                    style: poppins(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${(_uploadProgress * 100).toStringAsFixed(0)}%',
                    style: poppins(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF4DA6FF)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _uploadProgress,
                  backgroundColor: Colors.white12,
                  color: const Color(0xFF4DA6FF),
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${(_uploadedBytes / (1024 * 1024)).toStringAsFixed(2)} MB of ${(_totalBytes / (1024 * 1024)).toStringAsFixed(2)} MB',
                    style: poppins(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Remaining: ${((_totalBytes - _uploadedBytes) / (1024 * 1024)).clamp(0, double.infinity).toStringAsFixed(2)} MB',
                    style: poppins(fontSize: 11, color: const Color(0xFF8A9CC2), fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isUploading ? _cancelUpload : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      _isUploading ? 'Cancel' : 'Close',
                      style: poppins(color: Colors.white70, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                if (!_isUploading && _selectedFiles.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _startUpload,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4DA6FF),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: Text(
                        'Upload All',
                        style: poppins(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrefilledField(String label, String value, TextStyle Function({Color? color, double? fontSize, FontWeight? fontWeight, double? letterSpacing}) poppins) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: poppins(fontSize: 11, color: const Color(0xFF8A9CC2)),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: Text(
            value,
            style: poppins(fontSize: 13, color: Colors.white70),
          ),
        ),
      ],
    );
  }
}

IconData _getFileIcon(String ext) {
  ext = ext.toLowerCase();
  if (['pdf'].contains(ext)) return Icons.picture_as_pdf_rounded;
  if (['png', 'jpg', 'jpeg', 'gif', 'webp'].contains(ext)) return Icons.image_outlined;
  if (['zip', 'rar', 'tar', 'gz'].contains(ext)) return Icons.archive_outlined;
  if (['doc', 'docx', 'txt', 'rtf'].contains(ext)) return Icons.description_outlined;
  if (['xls', 'xlsx', 'csv'].contains(ext)) return Icons.table_chart_outlined;
  return Icons.insert_drive_file_outlined;
}

Color _getFileColor(String ext) {
  ext = ext.toLowerCase();
  if (['pdf'].contains(ext)) return const Color(0xFFFF4D4D);
  if (['png', 'jpg', 'jpeg', 'gif', 'webp'].contains(ext)) return const Color(0xFF00C48C);
  if (['zip', 'rar'].contains(ext)) return const Color(0xFFFF9F43);
  if (['doc', 'docx', 'txt'].contains(ext)) return const Color(0xFF4DA6FF);
  return const Color(0xFF8A9CC2);
}
