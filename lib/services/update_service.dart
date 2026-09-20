import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';

class UpdateService {
  static const String _owner = 'GiovanniDrago';
  static const String _repo = 'photo-atlas-app';
  static const String _lastCheckKey = 'last_update_check';
  static const String _skippedVersionKey = 'skipped_update_version';

  static String? _cachedVersion;
  static String? _cachedBuild;

  static Future<String> get currentVersion async {
    if (_cachedVersion != null) return _cachedVersion!;
    final info = await PackageInfo.fromPlatform();
    _cachedVersion = info.version;
    _cachedBuild = info.buildNumber;
    return _cachedVersion!;
  }

  static Future<String> get currentBuild async {
    if (_cachedBuild != null) return _cachedBuild!;
    await currentVersion;
    return _cachedBuild ?? '';
  }

  static Future<String> get currentVersionLabel async {
    final version = await currentVersion;
    final build = await currentBuild;
    return build.isEmpty ? 'v$version' : 'v$version ($build)';
  }

  static Future<void> checkForUpdates(
    BuildContext context, {
    bool silent = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    if (silent && prefs.getString(_lastCheckKey) == today) return;

    final release = await _fetchLatestRelease();
    final current = await currentVersion;
    await prefs.setString(_lastCheckKey, today);

    if (release == null) {
      if (!silent && context.mounted) {
        _showSnack(context, AppLocalizations.of(context)!.updateError);
      }
      return;
    }
    if (!isNewer(release.version, current)) {
      if (!silent && context.mounted) {
        _showSnack(context, AppLocalizations.of(context)!.noUpdates);
      }
      return;
    }
    if (silent && prefs.getString(_skippedVersionKey) == release.version) {
      return;
    }
    if (!context.mounted) return;
    await _showUpdateDialog(context, release, current);
  }

  static bool isNewer(String latest, String current) {
    final latestParts = latest
        .split('+')
        .first
        .split('.')
        .map(int.tryParse)
        .toList();
    final currentParts = current
        .split('+')
        .first
        .split('.')
        .map(int.tryParse)
        .toList();
    for (var index = 0; index < 3; index += 1) {
      final latestValue = index < latestParts.length
          ? (latestParts[index] ?? 0)
          : 0;
      final currentValue = index < currentParts.length
          ? (currentParts[index] ?? 0)
          : 0;
      if (latestValue > currentValue) return true;
      if (latestValue < currentValue) return false;
    }
    return false;
  }

  static String pickDownloadUrl(String platform, List<dynamic> assets) {
    final urls = <String, String>{};
    for (final asset in assets) {
      if (asset is! Map) continue;
      final name = asset['name']?.toString() ?? '';
      final url = asset['browser_download_url']?.toString() ?? '';
      if (name.isNotEmpty && url.isNotEmpty) urls[name] = url;
    }
    String? picked;
    if (platform == 'android') {
      picked = urls['app-arm64-v8a-release.apk'];
      if (picked == null) {
        for (final entry in urls.entries) {
          if (entry.key.endsWith('.apk')) {
            picked = entry.value;
            break;
          }
        }
      }
    } else if (platform == 'linux') {
      picked = urls['photoatlas-linux-x86_64.tar.gz'];
    }
    return picked ?? 'https://github.com/$_owner/$_repo/releases/latest';
  }

  static String currentPlatform() {
    if (kIsWeb) return 'web';
    return defaultTargetPlatform.name;
  }

  static Future<_ReleaseInfo?> _fetchLatestRelease() async {
    try {
      final current = await currentVersion;
      final response = await http.get(
        Uri.parse(
          'https://api.github.com/repos/$_owner/$_repo/releases/latest',
        ),
        headers: {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'photoatlas/$current',
        },
      );
      if (response.statusCode != 200) {
        debugPrint('Update check failed: ${response.statusCode}');
        return null;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final tagName = data['tag_name'] as String?;
      if (tagName == null || tagName.isEmpty) return null;
      final assets = (data['assets'] ?? const <dynamic>[]) as List<dynamic>;
      return _ReleaseInfo(
        version: tagName.replaceFirst(RegExp(r'^v'), ''),
        downloadUrl: pickDownloadUrl(currentPlatform(), assets),
      );
    } catch (error) {
      debugPrint('Update check error: $error');
      return null;
    }
  }

  static Future<void> _showUpdateDialog(
    BuildContext context,
    _ReleaseInfo release,
    String current,
  ) async {
    final skip = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final l10n = AppLocalizations.of(dialogContext)!;
        return AlertDialog(
          title: Text('${l10n.updateAvailable} v${release.version}'),
          content: Text(l10n.updateDialogBody(release.version, current)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.later),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.download),
            ),
          ],
        );
      },
    );
    if (skip == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_skippedVersionKey, release.version);
      return;
    }
    final uri = Uri.parse(release.downloadUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (context.mounted) {
      _showSnack(context, AppLocalizations.of(context)!.updateError);
    }
  }

  static void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ReleaseInfo {
  final String version;
  final String downloadUrl;

  const _ReleaseInfo({required this.version, required this.downloadUrl});
}
