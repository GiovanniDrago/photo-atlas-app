import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/api_client.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  late final TextEditingController _serverController;
  bool _registerMode = false;
  bool _loading = false;
  bool _detecting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _serverController = TextEditingController(
      text: ref.read(apiBaseUrlProvider),
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _serverController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = l10n.authFieldsRequired);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final notifier = ref.read(authProvider.notifier);
      if (_registerMode) {
        await notifier.register(username: username, password: password);
      } else {
        await notifier.login(username: username, password: password);
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showForgotPassword() async {
    final l10n = AppLocalizations.of(context)!;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.forgotPasswordTitle),
        content: SingleChildScrollView(child: Text(l10n.forgotPasswordBody)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.close),
          ),
        ],
      ),
    );
  }

  Future<void> _saveServer() async {
    final l10n = AppLocalizations.of(context)!;
    await ref
        .read(apiBaseUrlProvider.notifier)
        .setBaseUrl(_serverController.text);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.saved)));
    }
  }

  Future<void> _detectServer() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _detecting = true);
    try {
      final found = await ref
          .read(apiBaseUrlProvider.notifier)
          .detectAndSave(prefer: _serverController.text);
      if (!mounted) return;
      if (found != null) {
        _serverController.text = found;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.serverFound(found))));
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.serverNotFound)));
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
                    Icon(Icons.public, size: 48, color: scheme.primary),
                    const SizedBox(height: 8),
                    Text(
                      l10n.appTitle,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.authWelcome,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _usernameController,
                      decoration: InputDecoration(labelText: l10n.authUsername),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passwordController,
                      decoration: InputDecoration(labelText: l10n.authPassword),
                      obscureText: true,
                      onSubmitted: (_) => _submit(),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: TextStyle(color: scheme.error)),
                    ],
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _loading ? null : _submit,
                      child: _loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              _registerMode
                                  ? l10n.authCreateAccount
                                  : l10n.authSignIn,
                            ),
                    ),
                    TextButton(
                      onPressed: _loading
                          ? null
                          : () => setState(() {
                              _registerMode = !_registerMode;
                              _error = null;
                            }),
                      child: Text(
                        _registerMode
                            ? l10n.authSwitchToLogin
                            : l10n.authSwitchToRegister,
                      ),
                    ),
                    TextButton(
                      onPressed: _loading ? null : _showForgotPassword,
                      child: Text(l10n.forgotPassword),
                    ),
                    const Divider(height: 24),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text(l10n.authServerSettings),
                      children: [
                        TextField(
                          controller: _serverController,
                          decoration: InputDecoration(
                            labelText: l10n.apiBaseUrl,
                            hintText: l10n.apiBaseUrlHint,
                          ),
                          keyboardType: TextInputType.url,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            FilledButton.tonal(
                              onPressed: _saveServer,
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
                          ],
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
