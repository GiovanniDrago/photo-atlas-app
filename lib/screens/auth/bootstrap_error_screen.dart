import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/bootstrap_providers.dart';
import '../../providers/settings_provider.dart';

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

  @override
  void initState() {
    super.initState();
    _serverController = TextEditingController(
      text: ref.read(apiBaseUrlProvider),
    );
  }

  @override
  void dispose() {
    _serverController.dispose();
    super.dispose();
  }

  Future<void> _saveAndRetry() async {
    await ref
        .read(apiBaseUrlProvider.notifier)
        .setBaseUrl(_serverController.text);
    ref.invalidate(apiConfigProvider);
    ref.invalidate(supabaseReadyProvider);
  }

  Future<void> _detect() async {
    setState(() => _detecting = true);
    try {
      final found = await ref
          .read(apiBaseUrlProvider.notifier)
          .detectAndSave(prefer: _serverController.text);
      if (!mounted) return;
      if (found != null) {
        _serverController.text = found;
        ref.invalidate(apiConfigProvider);
        ref.invalidate(supabaseReadyProvider);
      }
    } finally {
      if (mounted) setState(() => _detecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
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
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        FilledButton(
                          onPressed: _saveAndRetry,
                          child: Text(l10n.retry),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: _detecting ? null : _detect,
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
