import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/bootstrap_providers.dart';
import '../../providers/settings_provider.dart';
import '../../services/api_client.dart';

class BootstrapErrorScreen extends ConsumerStatefulWidget {
  final String error;

  const BootstrapErrorScreen({super.key, required this.error});

  @override
  ConsumerState<BootstrapErrorScreen> createState() =>
      _BootstrapErrorScreenState();
}

class _BootstrapErrorScreenState extends ConsumerState<BootstrapErrorScreen> {
  late final TextEditingController _serverController;
  bool _detecting = false;
  bool _testing = false;
  bool? _resultOk;
  String? _resultMessage;

  @override
  void initState() {
    super.initState();
    _serverController = TextEditingController(
      text: ref.read(apiBaseUrlProvider),
    );
    // The VM address changes with the hotspot: try to find the server right
    // away instead of making the user type it every time.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _detect();
    });
  }

  @override
  void dispose() {
    _serverController.dispose();
    super.dispose();
  }

  Future<void> _applyBaseUrl(String value) async {
    final normalized = value.trim();
    if (normalized.isEmpty) return;
    await ref.read(apiBaseUrlProvider.notifier).setBaseUrl(normalized);
    ref.invalidate(apiConfigProvider);
    ref.invalidate(supabaseReadyProvider);
  }

  Future<void> _saveAndRetry() async {
    await _applyBaseUrl(_serverController.text);
  }

  /// Verifies the typed server and, when it answers, saves it and lets the
  /// bootstrap continue (the listener in build closes this screen once the app
  /// is ready).
  Future<void> _testConnection() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _testing = true;
      _resultMessage = null;
    });
    final target = _serverController.text.trim().replaceAll(
      RegExp(r'/+$'),
      '',
    );
    final online = await ApiClient(
      target,
    ).health(timeout: const Duration(seconds: 4));
    if (!mounted) return;
    if (!online) {
      setState(() {
        _testing = false;
        _resultOk = false;
        _resultMessage = l10n.serverTestFailed;
      });
      return;
    }
    setState(() {
      _resultOk = true;
      _resultMessage = l10n.serverTestOk;
    });
    // Keep the buttons disabled while the bootstrap runs; the listener below
    // re-enables them on error or dismisses the screen on success.
    await _applyBaseUrl(target);
  }

  Future<void> _detect() async {
    if (_detecting || _testing) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _detecting = true;
      _resultMessage = l10n.serverSearching;
    });
    try {
      final found = await ref
          .read(apiBaseUrlProvider.notifier)
          .detectAndSave(prefer: _serverController.text, scanLan: true);
      if (!mounted) return;
      if (found != null) {
        _serverController.text = found;
        setState(() {
          _resultOk = true;
          _resultMessage = l10n.serverFound(found);
        });
        ref.invalidate(apiConfigProvider);
        ref.invalidate(supabaseReadyProvider);
      } else {
        setState(() {
          _resultOk = false;
          _resultMessage = l10n.serverNotFound;
        });
      }
    } finally {
      if (mounted) setState(() => _detecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // When the saved server works the app becomes ready: close this screen if
    // it was pushed (e.g. from the splash), otherwise the home swaps itself.
    ref.listen(supabaseReadyProvider, (previous, next) {
      if (next.isLoading) return;
      if (next.hasError) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            _testing = false;
            _detecting = false;
            _resultOk = false;
            _resultMessage = '${next.error}';
          });
        });
      } else if (next.hasValue) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final navigator = Navigator.of(context);
          if (navigator.canPop()) navigator.pop();
        });
      }
    });
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final candidates = apiBaseUrlCandidates(
      saved: ref.watch(apiBaseUrlProvider),
    ).take(4).toList();
    final resultColor = _resultOk == true ? null : scheme.error;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.cloud_off, size: 48, color: scheme.error),
                    const SizedBox(height: 8),
                    Text(
                      l10n.bootstrapErrorTitle,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.bootstrapErrorBody,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    SelectableText(
                      widget.error,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: scheme.error),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _serverController,
                      decoration: InputDecoration(
                        labelText: l10n.apiBaseUrl,
                        hintText: l10n.apiBaseUrlHint,
                      ),
                      keyboardType: TextInputType.url,
                      onChanged: (_) => setState(() => _resultMessage = null),
                    ),
                    if (candidates.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          for (final candidate in candidates)
                            ActionChip(
                              label: Text(candidate),
                              onPressed: _detecting || _testing
                                  ? null
                                  : () => setState(() {
                                      _serverController.text = candidate;
                                      _resultMessage = null;
                                    }),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton(
                          onPressed: _detecting || _testing
                              ? null
                              : _saveAndRetry,
                          child: Text(l10n.retry),
                        ),
                        OutlinedButton.icon(
                          onPressed: _detecting || _testing
                              ? null
                              : _testConnection,
                          icon: _testing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.network_check),
                          label: Text(l10n.testConnection),
                        ),
                        OutlinedButton.icon(
                          onPressed: _detecting || _testing ? null : _detect,
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
                      ],
                    ),
                    if (_resultMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _resultMessage!,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: resultColor),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
