// ─────────────────────────────────────────────────────────────────────────────
// update_checker.dart
//
// Silent background APK updater for SEDS Portal.
//
// Behaviour:
//  • Checks GitHub Releases (version.json) 3 seconds after home page loads.
//  • If a newer version is available AND device has network → starts download
//    IMMEDIATELY in the background with NO in-app dialog.
//  • Shows a persistent system notification with real-time download progress
//    (percentage + MB downloaded / MB total).
//  • On download complete → replaces the progress notification with a
//    "Tap to Install" notification. Tapping it opens the Android package installer.
//  • If download fails → shows a brief error notification (auto-dismissed).
//  • Checks connectivity_plus before starting to avoid wasting data on no-network.
//  • Idempotent: if a download is already in progress, a second call is a no-op.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

// ── Notification IDs (must not clash with other channels) ────────────────────
const int _kProgressNotifId = 9901;
const int _kInstallNotifId  = 9902;
const int _kErrorNotifId    = 9903;
const String _kUpdateChannelId   = 'seds_update';
const String _kUpdateChannelName = 'App Updates';

// ── GitHub Release source ─────────────────────────────────────────────────────
const String _kGitHubOwner = 'kumaraguru-seds';
const String _kGitHubRepo  = 'seds_portal';
const String _kVersionJsonUrl =
    'https://github.com/$_kGitHubOwner/$_kGitHubRepo/releases/latest/download/version.json';

// ── Singleton flag: prevent duplicate concurrent downloads ────────────────────
bool _downloadInProgress = false;

// ── Shared notifications plugin instance ─────────────────────────────────────
final _notifications = FlutterLocalNotificationsPlugin();
bool _notifInitialized = false;

/// Public entry-point — call this from your home page initState.
/// Silent, non-blocking. All feedback is via system notifications.
Future<void> checkAndAutoUpdate() async {
  if (kIsWeb) return;
  if (!Platform.isAndroid) return; // Auto-update only makes sense on Android
  if (_downloadInProgress) return; // Already downloading

  try {
    // ── 1. Ensure local notifications plugin is ready ──────────────────────
    await _ensureNotifInit();

    // ── 2. Fetch version.json from GitHub ─────────────────────────────────
    final res = await http
        .get(Uri.parse(_kVersionJsonUrl))
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) return;

    final remote = jsonDecode(res.body) as Map<String, dynamic>;
    final remoteVersion = (remote['version'] as String?) ?? '0.0.0';
    final androidUrl    = (remote['android_url'] as String?) ?? '';
    final notes         = (remote['release_notes'] as String?) ?? '';

    if (androidUrl.isEmpty) return;

    // ── 3. Compare versions ─────────────────────────────────────────────────
    final info = await PackageInfo.fromPlatform();
    if (!_isNewer(remoteVersion, info.version)) return;

    // ── 4. Check connectivity — need actual network ────────────────────────
    final connectivity = await Connectivity().checkConnectivity();
    final hasNetwork = connectivity.any((c) =>
        c == ConnectivityResult.mobile ||
        c == ConnectivityResult.wifi ||
        c == ConnectivityResult.ethernet);
    if (!hasNetwork) return;

    // ── 5. Everything checks out — start background download ───────────────
    _downloadInBackground(remoteVersion, notes, androidUrl);
  } catch (e) {
    debugPrint('[AutoUpdate] Check failed: $e');
  }
}

// ── Background download (fire-and-forget) ─────────────────────────────────────
Future<void> _downloadInBackground(
  String version,
  String notes,
  String fileUrl,
) async {
  if (_downloadInProgress) return;
  _downloadInProgress = true;

  final cancelToken = CancelToken();
  String? savePath;

  try {
    // Show initial "starting" notification
    await _showProgress(
      title: '⬇️ SEDS Portal Update v$version',
      body: 'Starting download…',
      progress: 0,
      maxProgress: 100,
      indeterminate: true,
    );

    // Save to temp directory — no storage permission required
    final dir = await getTemporaryDirectory();
    savePath = '${dir.path}/seds_portal_update_v$version.apk';

    // If we already have a fully downloaded file from a previous run, skip DL
    final existing = File(savePath);
    if (await existing.exists() && (await existing.length()) > 1000000) {
      debugPrint('[AutoUpdate] Using cached APK: $savePath');
      await _showInstallNotification(version, savePath, notes);
      _downloadInProgress = false;
      return;
    }

    int lastPercent = -1;

    final dio = Dio();
    await dio.download(
      fileUrl,
      savePath,
      cancelToken: cancelToken,
      onReceiveProgress: (received, total) async {
        if (total <= 0) return;
        final percent = ((received / total) * 100).round();
        if (percent == lastPercent) return; // No UI spam
        lastPercent = percent;

        final receivedMb = (received / 1048576).toStringAsFixed(1);
        final totalMb    = (total   / 1048576).toStringAsFixed(1);

        await _showProgress(
          title: '⬇️ Updating SEDS Portal v$version',
          body: '$percent%  •  $receivedMb MB / $totalMb MB',
          progress: percent,
          maxProgress: 100,
          indeterminate: false,
        );
      },
      options: Options(
        responseType: ResponseType.bytes,
        followRedirects: true,
        receiveTimeout: const Duration(minutes: 15),
      ),
    );

    // Download complete — replace progress notification with Install button
    await _cancelProgressNotification();
    await _showInstallNotification(version, savePath, notes);
  } on DioException catch (e) {
    if (e.type == DioExceptionType.cancel) {
      debugPrint('[AutoUpdate] Download cancelled.');
    } else {
      debugPrint('[AutoUpdate] Dio error: $e');
      await _cancelProgressNotification();
      await _showErrorNotification();
    }
  } catch (e) {
    debugPrint('[AutoUpdate] Unexpected error: $e');
    await _cancelProgressNotification();
    await _showErrorNotification();
  } finally {
    _downloadInProgress = false;
  }
}

// ── Notification helpers ──────────────────────────────────────────────────────

Future<void> _ensureNotifInit() async {
  if (_notifInitialized) return;
  // Create the update channel
  final androidPlugin = _notifications
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
  await androidPlugin?.createNotificationChannel(
    const AndroidNotificationChannel(
      _kUpdateChannelId,
      _kUpdateChannelName,
      description: 'Automatic app update download progress',
      importance: Importance.low, // Low = silent, no sound while downloading
      playSound: false,
      enableVibration: false,
    ),
  );

  const initSettings = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
  );
  await _notifications.initialize(
    initSettings,
    onDidReceiveNotificationResponse: _onInstallTap,
  );
  _notifInitialized = true;
}

/// Shows / updates the progress bar notification (silent, no sound)
Future<void> _showProgress({
  required String title,
  required String body,
  required int progress,
  required int maxProgress,
  required bool indeterminate,
}) async {
  try {
    await _notifications.show(
      _kProgressNotifId,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _kUpdateChannelId,
          _kUpdateChannelName,
          channelDescription: 'Automatic app update download progress',
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,            // Cannot be dismissed while downloading
          showProgress: true,
          maxProgress: maxProgress,
          progress: progress,
          indeterminate: indeterminate,
          playSound: false,
          enableVibration: false,
          onlyAlertOnce: true,     // Don't buzz on every % update
          largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
          ticker: 'Downloading SEDS Portal update…',
        ),
      ),
    );
  } catch (e) {
    debugPrint('[AutoUpdate] Progress notification error: $e');
  }
}

/// Cancels the in-progress download notification
Future<void> _cancelProgressNotification() async {
  try {
    await _notifications.cancel(_kProgressNotifId);
  } catch (_) {}
}

/// Shows the "Tap to install" notification after download completes
Future<void> _showInstallNotification(
  String version,
  String filePath,
  String releaseNotes,
) async {
  try {
    final short = releaseNotes.length > 120
        ? '${releaseNotes.substring(0, 120)}…'
        : releaseNotes;

    await _notifications.show(
      _kInstallNotifId,
      '✅ SEDS Portal v$version — Ready to Install',
      short.isNotEmpty ? short : 'Tap to install the latest update.',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _kUpdateChannelId,
          _kUpdateChannelName,
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          ongoing: false,
          autoCancel: true,
          largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
          styleInformation: BigTextStyleInformation(
            short.isNotEmpty ? short : 'Tap to install the latest update.',
            contentTitle: '✅ SEDS Portal v$version ready to install',
            summaryText: 'Tap to open the installer',
          ),
          ticker: 'SEDS Portal update ready',
        ),
      ),
      payload: filePath, // Pass APK path as payload so tap can open it
    );
  } catch (e) {
    debugPrint('[AutoUpdate] Install notification error: $e');
  }
}

/// Shows a brief error notification if download failed
Future<void> _showErrorNotification() async {
  try {
    await _notifications.show(
      _kErrorNotifId,
      '⚠️ Update Download Failed',
      'SEDS Portal update could not be downloaded. Will retry next launch.',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _kUpdateChannelId,
          _kUpdateChannelName,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          playSound: false,
          enableVibration: false,
          autoCancel: true,
        ),
      ),
    );
  } catch (_) {}
}

/// Called when user taps the "ready to install" notification
void _onInstallTap(NotificationResponse response) async {
  final filePath = response.payload;
  if (filePath == null || filePath.isEmpty) return;
  try {
    await _notifications.cancel(_kInstallNotifId);
    final result = await OpenFile.open(filePath);
    debugPrint('[AutoUpdate] OpenFile result: ${result.message}');
  } catch (e) {
    debugPrint('[AutoUpdate] Install tap error: $e');
  }
}

// ── Semantic version comparison ───────────────────────────────────────────────
bool _isNewer(String remote, String current) {
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

// ── Legacy shim — keeps existing `UpdateChecker.checkForUpdates(context)` ────
// call sites compiling without any changes to those files.
class UpdateChecker {
  UpdateChecker._();

  static Future<void> checkForUpdates(dynamic context) async {
    await checkAndAutoUpdate();
  }
}
