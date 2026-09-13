import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../models/source.dart';
import '../../providers/auth_provider.dart';
import '../../providers/library_providers.dart';
import '../../providers/settings_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/locale_provider.dart';
import '../../services/scan_service.dart';
import '../../theme/app_theme.dart';

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
  bool _kdriveConnecting = false;
  bool _kdriveScanning = false;
  bool _kdriveEnriching = false;
  String _kdriveMessage = '';

  @override
  void initState() {
    super.initState();
    _apiController = TextEditingController(text: ref.read(apiBaseUrlProvider));
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshKDrive());
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

  Future<void> _refreshKDrive() async {
    try {
      final status = await ref.read(apiClientProvider).kdriveStatus();
      if (mounted) setState(() => _kdriveStatus = status);
    } catch (_) {
      if (mounted) {
        setState(
          () => _kdriveStatus = const KDriveAccountStatus(connected: false),
        );
      }
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
    final path = await FilePicker.getDirectoryPath(
      dialogTitle: l10n.scanFolder,
    );
    if (path == null) return;
    if (!mounted) return;
    setState(() {
      _scanning = true;
      _scanSeen = 0;
      _scanIndexed = 0;
      _scanStatus = l10n.scanning;
    });
    try {
      final client = ref.read(apiClientProvider);
      final folderName = path
          .split(RegExp(r'[/\\]'))
          .where((part) => part.isNotEmpty)
          .last;
      final sources = await client.sources();
      String? sourceId;
      for (final source in sources) {
        if (source.kind == 'local' && source.rootPath == path) {
          sourceId = source.id;
          break;
        }
      }
      sourceId ??= await client.createSource(
        kind: 'local',
        label: 'Local: $folderName',
        rootPath: path,
      );
      final scanRunId = await client.createScanRun(sourceId);
      final result = await ScanService.scanDirectory(
        directoryPath: path,
        onBatch: (batch) async {
          await client.batchMedia(
            sourceId: sourceId!,
            scanRunId: scanRunId,
            items: batch.map((item) => item.toJson()).toList(),
          );
        },
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
      await client.patchScanRun(
        scanRunId,
        status: 'completed',
        filesSeen: result.filesSeen,
        filesIndexed: result.indexed,
      );
      if (mounted) {
        setState(() {
          _scanning = false;
          _scanStatus = '${l10n.scanComplete}: ${result.indexed}';
        });
      }
      ref.invalidate(galleryProvider);
      ref.invalidate(timelineProvider);
    } catch (error) {
      if (mounted) {
        setState(() {
          _scanning = false;
          _scanStatus = '$error';
        });
      }
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
      _snack(l10n.kdriveConnected('$driveId'));
    } catch (error) {
      _snack('$error');
    } finally {
      if (mounted) setState(() => _kdriveConnecting = false);
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
      final client = ref.read(apiClientProvider);
      final scanRunId = await client.kdriveScan(folderId: folderId);
      while (mounted) {
        await Future<void>.delayed(const Duration(seconds: 2));
        final run = await client.scanRun(scanRunId);
        final seen = (run['files_seen'] as num?)?.toInt() ?? 0;
        final indexed = (run['files_indexed'] as num?)?.toInt() ?? 0;
        final status = (run['status'] ?? 'running') as String;
        if (!mounted) return;
        setState(() => _kdriveMessage = '${l10n.scanning} $seen / $indexed');
        if (status != 'running') {
          setState(() {
            _kdriveScanning = false;
            _kdriveMessage = status == 'completed' ? l10n.scanComplete : status;
          });
          break;
        }
      }
      ref.invalidate(galleryProvider);
      ref.invalidate(timelineProvider);
      ref.invalidate(clustersProvider);
    } catch (error) {
      if (mounted) {
        setState(() {
          _kdriveScanning = false;
          _kdriveMessage = '$error';
        });
      }
    }
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
              title: Text(user?.username ?? ''),
              subtitle: user != null
                  ? Text(l10n.authLoggedInAs(user.username))
                  : null,
              trailing: TextButton.icon(
                onPressed: () => ref.read(authProvider.notifier).logout(),
                icon: const Icon(Icons.logout, size: 18),
                label: Text(l10n.authLogout),
              ),
            ),
          ),
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
                    label: Text(l10n.scanFolder),
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
                    decoration: InputDecoration(labelText: l10n.kdriveDriveId),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      FilledButton(
                        onPressed: _kdriveConnecting ? null : _connectKDrive,
                        child: Text(l10n.kdriveConnect),
                      ),
                      const SizedBox(width: 12),
                      if (kdrive != null)
                        Chip(
                          label: Text(
                            kdrive.connected
                                ? l10n.kdriveConnected('${kdrive.driveId}')
                                : l10n.kdriveNotConnected,
                          ),
                        ),
                    ],
                  ),
                  const Divider(height: 32),
                  TextField(
                    controller: _folderIdController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: l10n.kdriveFolderId),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: _kdriveScanning ? null : _scanKDrive,
                        icon: const Icon(Icons.cloud_download_outlined),
                        label: Text(l10n.kdriveScan),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: _kdriveEnriching ? null : _enrichKDrive,
                        icon: const Icon(Icons.auto_awesome),
                        label: Text(l10n.kdriveEnrich),
                      ),
                    ],
                  ),
                  if (_kdriveMessage.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(_kdriveMessage),
                  ],
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
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l10n.aboutText,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
