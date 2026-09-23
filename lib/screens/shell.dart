import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../providers/backup_runner_provider.dart';
import 'backup/backup_screen.dart';
import 'collections/collections_screen.dart';
import 'gallery/gallery_screen.dart';
import 'map/map_screen.dart';
import 'settings/settings_screen.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  int _index = 0;
  Timer? _catchUpTimer;

  static const List<Widget> _screens = [
    MapScreen(),
    CollectionsScreen(),
    GalleryScreen(),
    SettingsScreen(),
  ];

  /// Tabs are built on first visit: no burst of API requests at startup and
  /// the media permission prompt appears only when the gallery is opened.
  final Set<int> _built = {0};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _catchUpTimer = Timer.periodic(
      const Duration(minutes: 15),
      (_) => _catchUp(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _catchUp());
  }

  @override
  void dispose() {
    _catchUpTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _catchUp();
  }

  /// Uploads the pending files of the enabled folders while the app is open.
  void _catchUp() {
    if (!mounted) return;
    ref.read(backupRunnerProvider.notifier).catchUp();
  }

  void _select(int index) {
    setState(() {
      _index = index;
      _built.add(index);
    });
  }

  Future<void> _openBackup() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const BackupScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          for (var index = 0; index < _screens.length; index += 1)
            _built.contains(index) ? _screens[index] : const SizedBox.shrink(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openBackup,
        tooltip: l10n.backupTitle,
        child: const Icon(Icons.add),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        height: 64,
        padding: EdgeInsets.zero,
        child: Row(
          children: [
            _barItem(index: 0, icon: Icons.public, label: l10n.mapTab),
            _barItem(
              index: 1,
              icon: Icons.collections_outlined,
              label: l10n.collectionsTab,
            ),
            const SizedBox(width: 64),
            _barItem(
              index: 2,
              icon: Icons.photo_library_outlined,
              label: l10n.galleryTab,
            ),
            _barItem(
              index: 3,
              icon: Icons.settings_outlined,
              label: l10n.settingsTab,
            ),
          ],
        ),
      ),
    );
  }

  Widget _barItem({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _index == index;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    return Expanded(
      child: InkWell(
        onTap: () => _select(index),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(fontSize: 11, color: color),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
