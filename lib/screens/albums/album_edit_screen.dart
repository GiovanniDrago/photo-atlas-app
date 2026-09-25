import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../models/album.dart';
import '../../providers/album_providers.dart';
import '../../providers/library_providers.dart';
import 'location_picker_screen.dart';

/// Smart-album builder: name, capture/upload date ranges, location + radius,
/// media type, with a live match count preview.
class AlbumEditScreen extends ConsumerStatefulWidget {
  /// Null creates a new smart album, otherwise its rules and name are edited.
  final Album? album;

  const AlbumEditScreen({super.key, this.album});

  @override
  ConsumerState<AlbumEditScreen> createState() => _AlbumEditScreenState();
}

class _AlbumEditScreenState extends ConsumerState<AlbumEditScreen> {
  late final TextEditingController _name;
  late AlbumRuleDraft _draft;
  Timer? _debounce;
  int? _preview;
  bool _previewing = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.album?.name ?? '');
    _draft = widget.album == null
        ? AlbumRuleDraft()
        : AlbumRuleDraft.fromRules(widget.album!.rules);
    Future.microtask(() => _schedulePreview(immediate: true));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _name.dispose();
    super.dispose();
  }

  void _schedulePreview({bool immediate = false}) {
    _debounce?.cancel();
    _debounce = Timer(
      immediate ? Duration.zero : const Duration(milliseconds: 400),
      _runPreview,
    );
  }

  Future<void> _runPreview() async {
    if (!mounted) return;
    if (_draft.isEmpty) {
      setState(() {
        _preview = 0;
        _previewing = false;
      });
      return;
    }
    setState(() => _previewing = true);
    try {
      final total = await ref
          .read(apiClientProvider)
          .previewAlbumRules(_draft.toRules());
      if (mounted) {
        setState(() {
          _preview = total;
          _previewing = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _previewing = false);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickDate({required bool taken, required bool isFrom}) async {
    final now = DateTime.now();
    final DateTime initial;
    if (isFrom) {
      initial = (taken ? _draft.takenFrom : _draft.uploadedFrom) ?? now;
    } else {
      initial = (taken ? _draft.takenTo : _draft.uploadedTo) ?? now;
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1970),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (taken) {
        if (isFrom) {
          _draft.takenFrom = picked;
        } else {
          _draft.takenTo = picked;
        }
      } else {
        if (isFrom) {
          _draft.uploadedFrom = picked;
        } else {
          _draft.uploadedTo = picked;
        }
      }
    });
    _schedulePreview();
  }

  Future<void> _pickLocation() async {
    final result = await Navigator.of(context)
        .push<({double lat, double lon, double radiusM})>(
          MaterialPageRoute(
            builder: (_) => LocationPickerScreen(
              initialLat: _draft.centerLat,
              initialLon: _draft.centerLon,
              initialRadiusM: _draft.radiusM,
            ),
          ),
        );
    if (result == null || !mounted) return;
    setState(() {
      _draft.centerLat = result.lat;
      _draft.centerLon = result.lon;
      _draft.radiusM = result.radiusM;
    });
    _schedulePreview();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context)!;
    final name = _name.text.trim();
    if (name.isEmpty) {
      _snack(l10n.albumNameRequired);
      return;
    }
    final rules = _draft.toRules();
    if (rules.isEmpty) {
      _snack(l10n.albumRulesRequired);
      return;
    }
    setState(() => _saving = true);
    try {
      final client = ref.read(apiClientProvider);
      final existing = widget.album;
      final saved = existing == null
          ? await client.createAlbum(
              name: name,
              kind: AlbumKind.smart,
              rules: rules,
            )
          : await client.updateAlbum(existing.id, name: name, rules: rules);
      ref.invalidate(albumsProvider);
      if (mounted) Navigator.of(context).pop(saved);
    } catch (error) {
      if (mounted) _snack('$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final format = DateFormat.yMd();
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.album == null ? l10n.albumCreateSmart : l10n.albumEditRules,
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.save),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          TextField(
            controller: _name,
            maxLength: 120,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: l10n.albumNameLabel),
          ),
          const SizedBox(height: 8),
          _sectionTitle(l10n.albumRuleTaken),
          _dateRow(
            from: _draft.takenFrom,
            to: _draft.takenTo,
            format: format,
            onPickFrom: () => _pickDate(taken: true, isFrom: true),
            onPickTo: () => _pickDate(taken: true, isFrom: false),
            onClear: () {
              setState(() {
                _draft.takenFrom = null;
                _draft.takenTo = null;
              });
              _schedulePreview();
            },
          ),
          const SizedBox(height: 12),
          _sectionTitle(l10n.albumRuleUploaded),
          _dateRow(
            from: _draft.uploadedFrom,
            to: _draft.uploadedTo,
            format: format,
            onPickFrom: () => _pickDate(taken: false, isFrom: true),
            onPickTo: () => _pickDate(taken: false, isFrom: false),
            onClear: () {
              setState(() {
                _draft.uploadedFrom = null;
                _draft.uploadedTo = null;
              });
              _schedulePreview();
            },
          ),
          const SizedBox(height: 12),
          _sectionTitle(l10n.albumRuleLocation),
          if (!_draft.hasLocation)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _pickLocation,
                icon: const Icon(Icons.map_outlined),
                label: Text(l10n.albumRulePickOnMap),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_draft.centerLat!.toStringAsFixed(4)}, '
                    '${_draft.centerLon!.toStringAsFixed(4)} · '
                    '${l10n.albumRuleRadius(_radiusKm(_draft.radiusM!))}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                TextButton(
                  onPressed: _pickLocation,
                  child: Text(l10n.albumRulePickOnMap),
                ),
                IconButton(
                  tooltip: l10n.albumRuleRemoveLocation,
                  onPressed: () {
                    setState(() {
                      _draft.centerLat = null;
                      _draft.centerLon = null;
                      _draft.radiusM = null;
                    });
                    _schedulePreview();
                  },
                  icon: const Icon(Icons.clear),
                ),
              ],
            ),
          const SizedBox(height: 12),
          _sectionTitle(l10n.albumRuleType),
          Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'all', label: Text(l10n.albumRuleTypeAll)),
                ButtonSegment(
                  value: 'image',
                  label: Text(l10n.albumRuleTypeImages),
                ),
                ButtonSegment(
                  value: 'video',
                  label: Text(l10n.albumRuleTypeVideos),
                ),
              ],
              selected: {_draft.mediaType},
              onSelectionChanged: (selection) {
                setState(() => _draft.mediaType = selection.first);
                _schedulePreview();
              },
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                if (_previewing)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(Icons.photo_library_outlined, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _draft.isEmpty
                        ? l10n.albumRulesRequired
                        : l10n.albumPreview(_preview ?? 0),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.check),
            label: Text(l10n.save),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall
            ?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _dateRow({
    required DateTime? from,
    required DateTime? to,
    required DateFormat format,
    required VoidCallback onPickFrom,
    required VoidCallback onPickTo,
    required VoidCallback onClear,
  }) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: onPickFrom,
            child: Text(
              from == null ? l10n.albumRuleFrom : format.format(from),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton(
            onPressed: onPickTo,
            child: Text(
              to == null ? l10n.albumRuleTo : format.format(to),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        if (from != null || to != null)
          IconButton(
            tooltip: l10n.albumRuleClear,
            onPressed: onClear,
            icon: const Icon(Icons.clear),
          ),
      ],
    );
  }

  static String _radiusKm(double meters) {
    final km = meters / 1000;
    return km == km.roundToDouble()
        ? km.toStringAsFixed(0)
        : km.toStringAsFixed(1);
  }
}
