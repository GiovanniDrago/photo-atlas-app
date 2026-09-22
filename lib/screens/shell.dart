import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'backup/backup_screen.dart';
import 'collections/collections_screen.dart';
import 'gallery/gallery_screen.dart';
import 'map/map_screen.dart';
import 'settings/settings_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const List<Widget> _screens = [
    MapScreen(),
    CollectionsScreen(),
    GalleryScreen(),
    SettingsScreen(),
  ];

  /// Tabs are built on first visit: no burst of API requests at startup and
  /// the media permission prompt appears only when the gallery is opened.
  final Set<int> _built = {0};

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
