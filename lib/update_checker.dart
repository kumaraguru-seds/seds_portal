import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

// ──────────────────────────────────────────────────────────────────────────────
// CONFIGURATION
// ──────────────────────────────────────────────────────────────────────────────
const String _kGitHubOwner = 'kumaraguru-seds';
const String _kGitHubRepo  = 'seds_portal';

/// Always resolves to version.json of the latest GitHub Release.
const String _kVersionJsonUrl =
    'https://github.com/$_kGitHubOwner/$_kGitHubRepo/releases/latest/download/version.json';

// ──────────────────────────────────────────────────────────────────────────────
// UpdateChecker
// ──────────────────────────────────────────────────────────────────────────────

class UpdateChecker {
  UpdateChecker._();

  /// Call this from your home page initState (already wired in main.dart).
  static Future<void> checkForUpdates(BuildContext context) async {
    if (kIsWeb) return;
    if (!Platform.isAndroid && !Platform.isWindows) return;

    try {
      final response = await http
          .get(Uri.parse(_kVersionJsonUrl))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return;

      final Map<String, dynamic> remote =
          jsonDecode(response.body) as Map<String, dynamic>;

      final String remoteVersion = (remote['version'] as String?) ?? '0.0.0';
      final String androidUrl    = (remote['android_url'] as String?) ?? '';
      final String windowsUrl    = (remote['windows_url'] as String?) ?? '';
      final String notes =
          (remote['release_notes'] as String?) ?? 'Bug fixes and improvements.';

      final PackageInfo info = await PackageInfo.fromPlatform();
      final String currentVersion = info.version;

      if (!_isNewer(remoteVersion, currentVersion)) return;

      if (context.mounted) {
        _showUpdateDialog(
          context: context,
          newVersion: remoteVersion,
          notes: notes,
          downloadUrl: Platform.isAndroid ? androidUrl : windowsUrl,
        );
      }
    } catch (e) {
      debugPrint('[UpdateChecker] check failed: $e');
    }
  }

  // ── Semantic version comparison ──────────────────────────────────────────

  static bool _isNewer(String remote, String current) {
    List<int> parse(String v) =>
        v.split('.').map((s) => int.tryParse(s.trim()) ?? 0).toList();
    final r = parse(remote);
    final c = parse(current);
    final len = r.length > c.length ? r.length : c.length;
    for (int i = 0; i < len; i++) {
      final rv = i < r.length ? r[i] : 0;
      final cv = i < c.length ? c[i] : 0;
      if (rv > cv) return true;
      if (rv < cv) return false;
    }
    return false;
  }

  // ── Update available dialog ───────────────────────────────────────────────

  static void _showUpdateDialog({
    required BuildContext context,
    required String newVersion,
    required String notes,
    required String downloadUrl,
  }) {
    final tp = GoogleFonts.poppins;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1A2B4A), Color(0xFF0F1C35)],
            ),
            border: Border.all(color: const Color(0xFF2A4080), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF4DA6FF).withValues(alpha: 0.25),
                blurRadius: 40,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF4DA6FF).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.system_update_rounded,
                      color: Color(0xFF4DA6FF),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Update Available',
                        style: tp(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                        ),
                      ),
                      Text(
                        'Version $newVersion',
                        style: tp(
                          color: const Color(0xFF4DA6FF),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 20),
              Divider(color: const Color(0xFF2A4080).withValues(alpha: 0.6)),
              const SizedBox(height: 16),

              // Release notes
              Text(
                "What's new",
                style: tp(
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                notes,
                style: tp(color: Colors.white60, fontSize: 13, height: 1.5),
              ),

              const SizedBox(height: 24),

              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(
                      'Later',
                      style: tp(color: Colors.white38, fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4DA6FF),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: Text(
                      'Update Now',
                      style: tp(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Colors.white,
                      ),
                    ),
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      // Both Android & Windows: download in-app + auto-launch installer
                      _downloadAndInstall(
                        ctx,
                        downloadUrl,
                        newVersion,
                        Platform.isAndroid ? 'apk' : 'exe',
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Android + Windows: download in-app and auto-launch installer ──────────

  static Future<void> _downloadAndInstall(
    BuildContext context,
    String fileUrl,
    String version,
    String extension,  // 'apk' or 'exe'
  ) async {
    // ValueNotifier lets us update the dialog from outside its builder
    final progressNotifier = ValueNotifier<double>(0.0);
    final overlayContext = context;
    final cancelToken = CancelToken();

    if (!overlayContext.mounted) return;

    showDialog<void>(
      context: overlayContext,
      barrierDismissible: false,
      builder: (ctx) => ValueListenableBuilder<double>(
        valueListenable: progressNotifier,
        builder: (_, prog, _) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                colors: [Color(0xFF1A2B4A), Color(0xFF0F1C35)],
              ),
              border: Border.all(color: const Color(0xFF2A4080), width: 1.5),
            ),
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.download_rounded,
                    color: Color(0xFF4DA6FF), size: 36),
                const SizedBox(height: 16),
                Text(
                  'Downloading Update...',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'v$version',
                  style: GoogleFonts.poppins(
                      color: const Color(0xFF4DA6FF), fontSize: 12),
                ),
                const SizedBox(height: 20),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: prog,
                    backgroundColor:
                        const Color(0xFF2A4080).withValues(alpha: 0.4),
                    color: const Color(0xFF4DA6FF),
                    minHeight: 8,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${(prog * 100).toStringAsFixed(0)}%',
                  style: GoogleFonts.poppins(
                      color: Colors.white60, fontSize: 12),
                ),
                const SizedBox(height: 20),
                TextButton.icon(
                  onPressed: () {
                    cancelToken.cancel('User cancelled download');
                    Navigator.of(ctx).pop();
                  },
                  icon: const Icon(Icons.close_rounded, color: Colors.white60, size: 16),
                  label: Text(
                    'Cancel Update',
                    style: GoogleFonts.poppins(color: Colors.white60, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      // Save to app's temp directory — no storage permission needed
      final dir = await getTemporaryDirectory();
      final savePath = '${dir.path}/seds_portal_update_v$version.$extension';

      final dio = Dio();
      await dio.download(
        fileUrl,
        savePath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            progressNotifier.value = received / total;
          }
        },
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: true,
          receiveTimeout: const Duration(minutes: 10),
        ),
      );

      // Close progress dialog
      if (overlayContext.mounted) {
        Navigator.of(overlayContext, rootNavigator: true).pop();
      }

      // Launch Android package installer / Windows exe setup
      final result = await OpenFile.open(savePath);
      debugPrint('[UpdateChecker] OpenFile result: ${result.message}');
      if (Platform.isWindows) {
        exit(0);
      }
    } catch (e) {
      debugPrint('[UpdateChecker] Download failed: $e');

      // If download was cancelled by the user, show cancel toast rather than error message
      if (e is DioException && e.type == DioExceptionType.cancel) {
        if (overlayContext.mounted) {
          ScaffoldMessenger.of(overlayContext).showSnackBar(
            const SnackBar(
              content: Text('Update cancelled.'),
              backgroundColor: Color(0xFF2A4080),
            ),
          );
        }
        return;
      }

      if (overlayContext.mounted) {
        Navigator.of(overlayContext, rootNavigator: true).pop();
        ScaffoldMessenger.of(overlayContext).showSnackBar(
          SnackBar(
            content: Text('Download failed. Please try again.'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }
}
