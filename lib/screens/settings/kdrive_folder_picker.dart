import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/source.dart';
import '../../providers/library_providers.dart';

class KDriveFolderSelection {
  final int folderId;
  final String path;
  final bool includeSubfolders;

  const KDriveFolderSelection({
    required this.folderId,
    required this.path,
    required this.includeSubfolders,
  });
}

Future<KDriveFolderSelection?> showKDriveFolderPicker(BuildContext context) {
  return showModalBottomSheet<KDriveFolderSelection>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => const KDriveFolderPickerSheet(),
  );
}

class _Crumb {
  final int id;
  final String? name;

  const _Crumb(this.id, this.name);
}

class KDriveFolderPickerSheet extends ConsumerStatefulWidget {
  const KDriveFolderPickerSheet({super.key});

  @override
  ConsumerState<KDriveFolderPickerSheet> createState() =>
      _KDriveFolderPickerSheetState();
}

class _KDriveFolderPickerSheetState
    extends ConsumerState<KDriveFolderPickerSheet> {
  List<_Crumb> _crumbs = const [_Crumb(1, null)];
  List<KDriveFolder> _children = const [];
  bool _loading = true;
  bool _includeSubfolders = true;
  String? _error;

  int get _currentId => _crumbs.last.id;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final children = await ref
          .read(apiClientProvider)
          .kdriveFolders(parentId: _currentId);
      if (!mounted) return;
      setState(() {
        _children = children;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  void _enter(KDriveFolder folder) {
    setState(() => _crumbs = [..._crumbs, _Crumb(folder.id, folder.name)]);
    _load();
  }

  void _jumpTo(int index) {
    setState(() => _crumbs = _crumbs.sublist(0, index + 1));
    _load();
  }

  void _select() {
    final path = _crumbs
        .skip(1)
        .map((crumb) => crumb.name ?? '')
        .where((name) => name.isNotEmpty)
        .join('/');
    Navigator.of(context).pop(
      KDriveFolderSelection(
        folderId: _currentId,
        path: path.isEmpty ? 'Root' : path,
        includeSubfolders: _includeSubfolders,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.72,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              l10n.kdriveAddFolder,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                for (var i = 0; i < _crumbs.length; i++) ...[
                  if (i > 0) const Icon(Icons.chevron_right, size: 16),
                  ActionChip(
                    label: Text(_crumbs[i].name ?? l10n.kdriveRoot),
                    onPressed: i == _crumbs.length - 1
                        ? null
                        : () => _jumpTo(i),
                  ),
                ],
              ],
            ),
          ),
          if (_currentId == 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                l10n.kdriveRootWarning,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(l10n.errorLoading),
                        TextButton(onPressed: _load, child: Text(l10n.retry)),
                      ],
                    ),
                  )
                : _children.isEmpty
                ? Center(child: Text(l10n.kdriveNoSubfolders))
                : ListView.builder(
                    itemCount: _children.length,
                    itemBuilder: (context, index) {
                      final folder = _children[index];
                      return ListTile(
                        leading: const Icon(Icons.folder_outlined),
                        title: Text(folder.name),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _enter(folder),
                      );
                    },
                  ),
          ),
          SwitchListTile(
            value: _includeSubfolders,
            onChanged: (value) => setState(() => _includeSubfolders = value),
            title: Text(l10n.kdriveSubfolders),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: FilledButton.icon(
              onPressed: _select,
              icon: const Icon(Icons.add),
              label: Text(l10n.kdriveSelectFolder),
            ),
          ),
        ],
      ),
    );
  }
}
