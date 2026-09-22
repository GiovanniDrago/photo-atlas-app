import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../models/json_value.dart';
import '../../models/source.dart';
import '../../providers/auth_provider.dart';
import '../../providers/gallery_providers.dart';
import '../../providers/library_providers.dart';
import '../../providers/settings_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/locale_provider.dart';
import '../../services/api_client.dart';
import '../../services/local_scan_service.dart';
import '../../services/scan_service.dart';
import '../../theme/app_theme.dart';
import '../../services/update_service.dart';
import 'change_password_dialog.dart';
import 'local_folder_picker.dart';
import 'security_section.dart';
import 'kdrive_folder_picker.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _apiController;
  final TextEditingController _tokenController = TextEditingController();
  final TextEditingController _driveIdController = TextEditingController();
  final TextEditingController _folderIdController = TextEditingController(
    text: '1',
  );

  bool _scanning = false;
  String _scanStatus = '';
  int _scanSeen = 0;
  int _scanIndexed = 0;
  bool _detecting = false;

  KDriveAccountStatus? _kdriveStatus;
  String? _kdriveStatusError;
  bool _kdriveChecking = false;
  bool _kdriveConnecting = false;
  bool _kdriveScanning = false;
  bool _kdriveEnriching = false;
  bool _replaceTokenMode = false;
  bool _kdrivePreviewsRunning = false;
  String _kdrivePreviewsMessage = '';
  String _kdriveMessage = '';

  @override
  void initState() {
    super.initState();
    _apiController = TextEditingController(text: ref.read(apiBaseUrlProvider));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshKDrive();
      _loadPreviewState();
    });
  }

  @override
  void dispose() {
    _apiController.dispose();
    _tokenController.dispose();
    _driveIdController.dispose();
    _folderIdController.dispose();
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _refreshKDrive({bool userInitiated = false}) async {
    if (mounted) setState(() => _kdriveChecking = true);
    try {
      final status = await ref.read(apiClientProvider).kdriveStatus();
      if (!mounted) return;
      setState(() {
        _kdriveStatus = status;
        _kdriveStatusError = null;
      });
      if (userInitiated) {
        final l10n = AppLocalizations.of(context)!;
        _snack(
          status.connected
              ? l10n.kdriveConnected('${status.driveId}')
              : l10n.kdriveNotConnected,
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _kdriveStatusError = error is ApiException ? error.message : '$error';
      });
      if (userInitiated) _snack(_kdriveStatusError!);
    } finally {
      if (mounted) setState(() => _kdriveChecking = false);
    }
  }

  Future<void> _saveApiBaseUrl() async {
    final l10n = AppLocalizations.of(context)!;
    await ref.read(apiBaseUrlProvider.notifier).setBaseUrl(_apiController.text);
    ref.invalidate(healthProvider);
    _snack(l10n.saved);
  }

  Future<void> _detectServer() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _detecting = true);
    try {
      final found = await ref
          .read(apiBaseUrlProvider.notifier)
          .detectAndSave(prefer: _apiController.text);
      if (!mounted) return;
      if (found != null) {
        _apiController.text = found;
        ref.invalidate(healthProvider);
        _snack(l10n.serverFound(found));
      } else {
        _snack(l10n.serverNotFound);
      }
    } finally {
      if (mounted) setState(() => _detecting = false);
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _showKDriveInfo() async {
    final l10n = AppLocalizations.of(context)!;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.kdriveInfoTitle),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.kdriveInfoBody),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () => _openUrl(
                  'https://manager.infomaniak.com/v3/ng/accounts/token/list',
                ),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: Text(l10n.kdriveInfoTokenPage),
              ),
              TextButton.icon(
                onPressed: () =>
                    _openUrl('https://ksuite.infomaniak.com/all/kdrive/app'),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: Text(l10n.kdriveInfoWebApp),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.close),
          ),
        ],
      ),
    );
  }

  Future<void> _scanLocalFolder() async {
    final l10n = AppLocalizations.of(context)!;
    if (!ScanService.isSupported) {
      _snack(l10n.scanUnsupportedWeb);
      return;
    }
    if (ScanService.isAlbumBased) {
      final selection = await showLocalFolderPicker(context);
      if (selection == null || !mounted) return;
      await _runLocalScan(
        label: selection.name,
        rootPath: 'album:${selection.id}',
      );
      return;
    }
    final path = await FilePicker.getDirectoryPath(
      dialogTitle: l10n.scanFolder,
    );
    if (path == null || !mounted) return;
    final folderName = path
        .split(RegExp(r'[/\\]'))
        .where((part) => part.isNotEmpty)
        .last;
    await _runLocalScan(label: 'Local: $folderName', rootPath: path);
  }

  Future<void> _runLocalScan({
    required String label,
    required String rootPath,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _scanning = true;
      _scanSeen = 0;
      _scanIndexed = 0;
      _scanStatus = l10n.scanning;
    });
    try {
      final client = ref.read(apiClientProvider);
      final scanner = LocalScanService(client);
      final sourceId = await scanner.ensureSource(
        label: label,
        rootPath: rootPath,
      );
      final result = await scanner.scanSource(
        sourceId: sourceId,
        rootPath: rootPath,
        onProgress: (seen, indexed) {
          if (mounted) {
            setState(() {
              _scanSeen = seen;
              _scanIndexed = indexed;
              _scanStatus = '${l10n.scanning} $seen / $indexed';
            });
          }
        },
      );
      if (mounted) {
        setState(() {
          _scanning = false;
          _scanStatus = result.indexed == 0
              ? l10n.localNoMedia
              : '${l10n.scanComplete}: ${result.indexed}';
        });
      }
      ref.invalidate(sourcesProvider);
      ref.invalidate(galleryProvider);
      ref.invalidate(timelineProvider);
      ref.invalidate(clustersProvider);
    } on ScanPermissionException {
      if (mounted) {
        setState(() {
          _scanning = false;
          _scanStatus = l10n.localPermissionDenied;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _scanning = false;
          _scanStatus = '$error';
        });
      }
    }
  }

  Future<void> _rescanLocalSource(MediaSource source) async {
    final rootPath = source.rootPath;
    if (rootPath == null) return;
    await _runLocalScan(label: source.label, rootPath: rootPath);
  }

  Future<void> _deleteLocalSource(MediaSource source) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.localDeleteTitle(source.label)),
        content: Text(l10n.localDeleteBody(source.itemCount)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.kdriveCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.localDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(apiClientProvider).deleteSource(source.id);
      ref.invalidate(sourcesProvider);
      _invalidateLibrary();
    } catch (error) {
      _snack('$error');
    }
  }

  Future<void> _connectKDrive() async {
    final l10n = AppLocalizations.of(context)!;
    final token = _tokenController.text.trim();
    final driveId = int.tryParse(_driveIdController.text.trim());
    if (token.isEmpty || driveId == null) {
      _snack('${l10n.kdriveToken} / ${l10n.kdriveDriveId}');
      return;
    }
    setState(() => _kdriveConnecting = true);
    try {
      await ref
          .read(apiClientProvider)
          .kdriveConnect(token: token, driveId: driveId);
      _tokenController.clear();
      await _refreshKDrive();
      if (mounted) setState(() => _replaceTokenMode = false);
      _snack(l10n.kdriveConnected('$driveId'));
    } catch (error) {
      _snack('$error');
    } finally {
      if (mounted) setState(() => _kdriveConnecting = false);
    }
  }

  void _invalidateLibrary() {
    ref.invalidate(galleryProvider);
    ref.invalidate(timelineProvider);
    ref.invalidate(clustersProvider);
  }

  Future<void> _pollScanRun(String scanRunId) async {
    final l10n = AppLocalizations.of(context)!;
    final client = ref.read(apiClientProvider);
    while (mounted) {
      await Future<void>.delayed(const Duration(seconds: 2));
      final run = await client.scanRun(scanRunId);
      final seen = asInt(run['files_seen']) ?? 0;
      final indexed = asInt(run['files_indexed']) ?? 0;
      final status = (run['status'] ?? 'running') as String;
      if (!mounted) return;
      setState(() => _kdriveMessage = '${l10n.scanning} $seen / $indexed');
      if (status != 'running') {
        setState(() {
          _kdriveScanning = false;
          _kdriveMessage = status == 'completed' ? l10n.scanComplete : status;
        });
        return;
      }
    }
  }

  Future<void> _addKDriveFolder() async {
    final l10n = AppLocalizations.of(context)!;
    final selection = await showKDriveFolderPicker(context);
    if (selection == null || !mounted) return;
    setState(() {
      _kdriveScanning = true;
      _kdriveMessage = l10n.scanning;
    });
    try {
      final scanRunId = await ref
          .read(apiClientProvider)
          .kdriveScan(
            folderId: selection.folderId,
            includeSubfolders: selection.includeSubfolders,
            label: 'kDrive: ${selection.path}',
          );
      await _pollScanRun(scanRunId);
      ref.invalidate(sourcesProvider);
      _invalidateLibrary();
      unawaited(_watchPreviews());
    } catch (error) {
      if (mounted) {
        setState(() {
          _kdriveScanning = false;
          _kdriveMessage = '$error';
        });
      }
    }
  }

  Future<void> _rescanSource(MediaSource source) async {
    final folderId = source.kdriveFolderId;
    if (folderId == null) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _kdriveScanning = true;
      _kdriveMessage = l10n.scanning;
    });
    try {
      final scanRunId = await ref
          .read(apiClientProvider)
          .kdriveScan(
            folderId: folderId,
            includeSubfolders: source.includeSubfolders,
            label: source.label,
          );
      await _pollScanRun(scanRunId);
      ref.invalidate(sourcesProvider);
      _invalidateLibrary();
      unawaited(_watchPreviews());
    } catch (error) {
      if (mounted) {
        setState(() {
          _kdriveScanning = false;
          _kdriveMessage = '$error';
        });
      }
    }
  }

  Future<void> _toggleSubfolders(MediaSource source, bool value) async {
    try {
      await ref
          .read(apiClientProvider)
          .updateSource(source.id, includeSubfolders: value);
      ref.invalidate(sourcesProvider);
    } catch (error) {
      _snack('$error');
    }
  }

  Future<void> _deleteSource(MediaSource source) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.kdriveDeleteTitle(source.label)),
        content: Text(l10n.kdriveDeleteBody(source.itemCount)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.kdriveCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.kdriveDeleteFolder),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(apiClientProvider).deleteSource(source.id);
      ref.invalidate(sourcesProvider);
      _invalidateLibrary();
    } catch (error) {
      _snack('$error');
    }
  }

  Future<void> _scanKDrive() async {
    final l10n = AppLocalizations.of(context)!;
    final folderId = int.tryParse(_folderIdController.text.trim()) ?? 1;
    setState(() {
      _kdriveScanning = true;
      _kdriveMessage = l10n.scanning;
    });
    try {
      final scanRunId = await ref
          .read(apiClientProvider)
          .kdriveScan(folderId: folderId);
      await _pollScanRun(scanRunId);
      ref.invalidate(sourcesProvider);
      _invalidateLibrary();
      unawaited(_watchPreviews());
    } catch (error) {
      if (mounted) {
        setState(() {
          _kdriveScanning = false;
          _kdriveMessage = '$error';
        });
      }
    }
  }

  Future<void> _loadPreviewState() async {
    try {
      final state = await ref.read(apiClientProvider).kdrivePreviewsState();
      if (!mounted) return;
      if (state.running || state.processed > 0) {
        setState(() {
          _kdrivePreviewsRunning = state.running;
          _kdrivePreviewsMessage =
              '${AppLocalizations.of(context)!.kdrivePreviews}: ${state.processed} (${state.updated})';
        });
      }
      if (state.running) unawaited(_watchPreviews());
    } catch (_) {}
  }

  Future<void> _generatePreviews() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _kdrivePreviewsRunning = true;
      _kdrivePreviewsMessage = l10n.kdrivePreviews;
    });
    try {
      await ref.read(apiClientProvider).kdrivePreviews();
      await _watchPreviews();
    } catch (error) {
      if (mounted) {
        setState(() {
          _kdrivePreviewsRunning = false;
          _kdrivePreviewsMessage = '$error';
        });
      }
    }
  }

  Future<void> _watchPreviews() async {
    final l10n = AppLocalizations.of(context)!;
    final client = ref.read(apiClientProvider);
    while (mounted) {
      await Future<void>.delayed(const Duration(seconds: 3));
      final state = await client.kdrivePreviewsState();
      if (!mounted) return;
      setState(() {
        _kdrivePreviewsRunning = state.running;
        _kdrivePreviewsMessage =
            '${l10n.kdrivePreviews}: ${state.processed} (${state.updated})';
      });
      if (!state.running) break;
    }
    if (mounted) ref.invalidate(sourcesProvider);
  }

  Widget _buildLocalFolderTile(MediaSource source, AppLocalizations l10n) {
    final parts = <String>[l10n.itemCount(source.itemCount)];
    final rootPath = source.rootPath;
    if (rootPath != null &&
        rootPath.isNotEmpty &&
        !rootPath.startsWith('album:')) {
      parts.add(rootPath);
    }
    final lastScan = source.lastScanAt;
    if (lastScan != null) {
      parts.add(l10n.kdriveLastScan(DateFormat.yMd().format(lastScan)));
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.folder_outlined),
      title: Text(source.label),
      subtitle: Text(
        parts.join(' · '),
        style: Theme.of(context).textTheme.bodySmall,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (value) async {
          if (value == 'scan') {
            await _rescanLocalSource(source);
          } else if (value == 'delete') {
            await _deleteLocalSource(source);
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(value: 'scan', child: Text(l10n.localScanAgain)),
          PopupMenuItem(value: 'delete', child: Text(l10n.localDelete)),
        ],
      ),
    );
  }

  Widget _buildKDriveFolderTile(MediaSource source, AppLocalizations l10n) {
    final parts = <String>[
      l10n.itemCount(source.itemCount),
      source.includeSubfolders
          ? l10n.kdriveSubfoldersOn
          : l10n.kdriveSubfoldersOff,
    ];
    final lastScan = source.lastScanAt;
    if (lastScan != null) {
      parts.add(l10n.kdriveLastScan(DateFormat.yMd().format(lastScan)));
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.folder_outlined),
      title: Text(source.label),
      subtitle: Text(
        parts.join(' · '),
        style: Theme.of(context).textTheme.bodySmall,
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (value) async {
          if (value == 'scan') {
            await _rescanSource(source);
          } else if (value == 'subfolders') {
            await _toggleSubfolders(source, !source.includeSubfolders);
          } else if (value == 'delete') {
            await _deleteSource(source);
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(value: 'scan', child: Text(l10n.kdriveScanAgain)),
          PopupMenuItem(
            value: 'subfolders',
            child: Text(l10n.kdriveSubfolders),
          ),
          PopupMenuItem(value: 'delete', child: Text(l10n.kdriveDeleteFolder)),
        ],
      ),
    );
  }

  Future<void> _enrichKDrive() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _kdriveEnriching = true;
      _kdriveMessage = l10n.kdriveEnrichRunning;
    });
    try {
      final client = ref.read(apiClientProvider);
      await client.kdriveEnrich(limit: 50);
      while (mounted) {
        await Future<void>.delayed(const Duration(seconds: 2));
        final state = await client.kdriveEnrichState();
        if (!mounted) return;
        setState(
          () => _kdriveMessage =
              '${l10n.kdriveEnrichRunning} ${state.processed} (${state.updated})',
        );
        if (!state.running) break;
      }
      if (mounted) {
        setState(() {
          _kdriveEnriching = false;
          _kdriveMessage = l10n.kdriveEnrichDone;
        });
      }
      ref.invalidate(galleryProvider);
      ref.invalidate(timelineProvider);
      ref.invalidate(clustersProvider);
    } catch (error) {
      if (mounted) {
        setState(() {
          _kdriveEnriching = false;
          _kdriveMessage = '$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final health = ref.watch(healthProvider);
    final kdrive = _kdriveStatus;
    final user = ref.watch(authProvider).user;
    final sourcesAsync = ref.watch(sourcesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            l10n.authAccountSection,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(user?.label ?? ''),
              subtitle: user != null
                  ? Text(user.email ?? l10n.authLoggedInAs(user.username))
                  : null,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: l10n.changePassword,
                    onPressed: () async {
                      final changed = await ChangePasswordDialog.show(context);
                      if (changed == true && mounted) {
                        _snack(l10n.passwordChanged);
                      }
                    },
                    icon: const Icon(Icons.password, size: 20),
                  ),
                  IconButton(
                    tooltip: l10n.authLogout,
                    onPressed: () => ref.read(authProvider.notifier).logout(),
                    icon: const Icon(Icons.logout, size: 20),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            l10n.securitySection,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const SecuritySection(),
          const SizedBox(height: 20),
          Text(l10n.apiSection, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _apiController,
                    decoration: InputDecoration(
                      labelText: l10n.apiBaseUrl,
                      hintText: l10n.apiBaseUrlHint,
                    ),
                    keyboardType: TextInputType.url,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      FilledButton(
                        onPressed: _saveApiBaseUrl,
                        child: Text(l10n.save),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _detecting ? null : _detectServer,
                        icon: _detecting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.search),
                        label: Text(l10n.detectServer),
                      ),
                      const SizedBox(width: 12),
                      health.when(
                        data: (online) => Chip(
                          avatar: Icon(
                            online ? Icons.check_circle : Icons.error_outline,
                            size: 16,
                            color: online ? scheme.primary : scheme.error,
                          ),
                          label: Text(
                            online ? l10n.serverOnline : l10n.serverOffline,
                          ),
                        ),
                        loading: () => const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        error: (error, stackTrace) => Chip(
                          label: Text(l10n.serverOffline),
                          avatar: Icon(
                            Icons.error_outline,
                            size: 16,
                            color: scheme.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            l10n.localScanSection,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.scanFolderDescription,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _scanning ? null : _scanLocalFolder,
                    icon: const Icon(Icons.folder_open),
                    label: Text(l10n.localAddFolder),
                  ),
                  if (_scanStatus.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(_scanStatus),
                    if (_scanning)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: LinearProgressIndicator(
                          value: _scanSeen == 0
                              ? null
                              : _scanIndexed / _scanSeen,
                        ),
                      ),
                  ],
                  const Divider(height: 32),
                  Text(
                    l10n.localFoldersSection,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  sourcesAsync.when(
                    data: (sources) {
                      final folders = sources
                          .where((source) => source.kind == 'local')
                          .toList();
                      if (folders.isEmpty) {
                        return Text(
                          l10n.localNoFolders,
                          style: Theme.of(context).textTheme.bodySmall,
                        );
                      }
                      return Column(
                        children: [
                          for (final folder in folders)
                            _buildLocalFolderTile(folder, l10n),
                        ],
                      );
                    },
                    loading: () => const Padding(
                      padding: EdgeInsets.all(8),
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                    error: (error, stackTrace) => Text(
                      l10n.errorLoading,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.kdriveSection,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: l10n.kdriveInfoTitle,
                onPressed: _showKDriveInfo,
                icon: const Icon(Icons.info_outline),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (kdrive?.connected == true && !_replaceTokenMode) ...[
                    Row(
                      children: [
                        Expanded(
                          child: Chip(
                            avatar: const Icon(
                              Icons.cloud_done_outlined,
                              size: 16,
                            ),
                            label: Text(
                              l10n.kdriveConnected('${kdrive?.driveId}'),
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              setState(() => _replaceTokenMode = true),
                          child: Text(l10n.kdriveReplaceToken),
                        ),
                      ],
                    ),
                    Text(
                      l10n.kdriveTokenSaved,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (_kdriveStatusError != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.warning_amber_outlined,
                            size: 16,
                            color: scheme.error,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              l10n.kdriveStatusUnknown,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          TextButton(
                            onPressed: _kdriveChecking
                                ? null
                                : () => _refreshKDrive(userInitiated: true),
                            child: Text(l10n.retry),
                          ),
                        ],
                      ),
                    ],
                  ] else ...[
                    if (_kdriveChecking)
                      Row(
                        children: [
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 12),
                          Text(l10n.kdriveChecking),
                        ],
                      )
                    else if (_kdriveStatusError != null) ...[
                      Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 16,
                            color: scheme.error,
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(l10n.kdriveStatusUnknown)),
                          TextButton(
                            onPressed: () =>
                                _refreshKDrive(userInitiated: true),
                            child: Text(l10n.retry),
                          ),
                        ],
                      ),
                      Text(
                        '${ref.watch(apiBaseUrlProvider)} — $_kdriveStatusError',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                    ] else if (kdrive != null && !kdrive.connected) ...[
                      Chip(label: Text(l10n.kdriveNotConnected)),
                      const SizedBox(height: 12),
                    ],
                    Text(
                      l10n.kdriveHowTo,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _tokenController,
                      obscureText: true,
                      decoration: InputDecoration(labelText: l10n.kdriveToken),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _driveIdController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: l10n.kdriveDriveId,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        FilledButton(
                          onPressed: _kdriveConnecting ? null : _connectKDrive,
                          child: Text(l10n.kdriveConnect),
                        ),
                        if (_replaceTokenMode) ...[
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () =>
                                setState(() => _replaceTokenMode = false),
                            child: Text(l10n.kdriveCancel),
                          ),
                        ],
                      ],
                    ),
                  ],
                  const Divider(height: 32),
                  Text(
                    l10n.kdriveFoldersSection,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    onPressed: _kdriveScanning ? null : _addKDriveFolder,
                    icon: const Icon(Icons.create_new_folder_outlined),
                    label: Text(l10n.kdriveAddFolder),
                  ),
                  const SizedBox(height: 8),
                  sourcesAsync.when(
                    data: (sources) {
                      final folders = sources
                          .where((source) => source.isKDrive)
                          .toList();
                      if (folders.isEmpty) {
                        return Text(
                          l10n.kdriveNoFolders,
                          style: Theme.of(context).textTheme.bodySmall,
                        );
                      }
                      return Column(
                        children: [
                          for (final folder in folders)
                            _buildKDriveFolderTile(folder, l10n),
                        ],
                      );
                    },
                    loading: () => const Padding(
                      padding: EdgeInsets.all(8),
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                    error: (error, stackTrace) => Text(
                      l10n.errorLoading,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  if (_kdriveMessage.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(_kdriveMessage),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: _kdrivePreviewsRunning
                            ? null
                            : _generatePreviews,
                        icon: const Icon(Icons.image_outlined),
                        label: Text(l10n.kdrivePreviews),
                      ),
                      const SizedBox(width: 12),
                      if (_kdrivePreviewsMessage.isNotEmpty)
                        Expanded(
                          child: Text(
                            _kdrivePreviewsMessage,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                    ],
                  ),
                  const Divider(height: 32),
                  FilledButton.tonalIcon(
                    onPressed: _kdriveEnriching ? null : _enrichKDrive,
                    icon: const Icon(Icons.auto_awesome),
                    label: Text(l10n.kdriveEnrich),
                  ),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text(l10n.kdriveAdvanced),
                    children: [
                      TextField(
                        controller: _folderIdController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: l10n.kdriveFolderId,
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.tonalIcon(
                        onPressed: _kdriveScanning ? null : _scanKDrive,
                        icon: const Icon(Icons.cloud_download_outlined),
                        label: Text(l10n.kdriveScan),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            l10n.themeSection,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.themeLabel),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final option in appThemes)
                        ChoiceChip(
                          label: Text(option.name),
                          selected: ref.watch(themeProvider).id == option.id,
                          onSelected: (selected) {
                            if (selected) {
                              ref
                                  .read(themeProvider.notifier)
                                  .setTheme(option.id);
                            }
                          },
                        ),
                    ],
                  ),
                  const Divider(height: 32),
                  Text(l10n.languageLabel),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('English'),
                        selected:
                            ref.watch(localeProvider).languageCode == 'en',
                        onSelected: (selected) {
                          if (selected) {
                            ref
                                .read(localeProvider.notifier)
                                .setLocale(const Locale('en'));
                          }
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Italiano'),
                        selected:
                            ref.watch(localeProvider).languageCode == 'it',
                        onSelected: (selected) {
                          if (selected) {
                            ref
                                .read(localeProvider.notifier)
                                .setLocale(const Locale('it'));
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            l10n.aboutSection,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    l10n.aboutText,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const Divider(height: 1),
                FutureBuilder<String>(
                  future: UpdateService.currentVersionLabel,
                  builder: (context, snapshot) {
                    final version = snapshot.data ?? '';
                    return ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: Text(l10n.version),
                      subtitle: version.isEmpty ? null : Text(version),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.system_update),
                  title: Text(l10n.checkForUpdates),
                  onTap: () =>
                      UpdateService.checkForUpdates(context, silent: false),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
