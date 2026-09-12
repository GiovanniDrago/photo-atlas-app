import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'gallery/gallery_screen.dart';
import 'map/map_screen.dart';
import 'settings/settings_screen.dart';
import 'timeline/timeline_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const List<Widget> _screens = [
    MapScreen(),
    TimelineScreen(),
    GalleryScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.public),
            label: l10n.mapTab,
          ),
          NavigationDestination(
            icon: const Icon(Icons.timeline),
            label: l10n.timelineTab,
          ),
          NavigationDestination(
            icon: const Icon(Icons.photo_library_outlined),
            label: l10n.galleryTab,
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            label: l10n.settingsTab,
          ),
        ],
      ),
    );
  }
}
