import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/scan_models.dart';
import '../../services/scan_service.dart';

class LocalFolderSelection {
  final String id;
  final String name;

  const LocalFolderSelection({required this.id, required this.name});
}

Future<LocalFolderSelection?> showLocalFolderPicker(BuildContext context) {
  return showModalBottomSheet<LocalFolderSelection>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _LocalFolderPickerSheet(),
  );
}

class _LocalFolderPickerSheet extends StatefulWidget {
  const _LocalFolderPickerSheet();

  @override
  State<_LocalFolderPickerSheet> createState() =>
      _LocalFolderPickerSheetState();
}

class _LocalFolderPickerSheetState extends State<_LocalFolderPickerSheet> {
  List<ScanFolder>? _folders;
  String? _error;
  bool _permissionDenied = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _folders = null;
      _error = null;
      _permissionDenied = false;
    });
    try {
      final folders = await ScanService.listFolders();
      if (mounted) setState(() => _folders = folders);
    } on ScanPermissionException {
      if (mounted) {
        setState(() {
          _permissionDenied = true;
          _folders = const [];
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '$error';
          _folders = const [];
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final folders = _folders;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.7,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              l10n.localPickAlbum,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: folders == null
                ? const Center(child: CircularProgressIndicator())
                : _permissionDenied
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            l10n.localPermissionDenied,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          FilledButton(
                            onPressed: _load,
                            child: Text(l10n.retry),
                          ),
                        ],
                      ),
                    ),
                  )
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
                : folders.isEmpty
                ? Center(child: Text(l10n.localNoFolders))
                : ListView.builder(
                    itemCount: folders.length,
                    itemBuilder: (context, index) {
                      final folder = folders[index];
                      return ListTile(
                        leading: const Icon(Icons.photo_library_outlined),
                        title: Text(folder.name),
                        subtitle: Text(l10n.itemCount(folder.count)),
                        onTap: () => Navigator.of(context).pop(
                          LocalFolderSelection(
                            id: folder.id,
                            name: folder.name,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
