import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/api_client.dart';
import 'forgot_password_screen.dart';
import 'recovery_codes_dialog.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final TextEditingController _identifierController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _displayNameController = TextEditingController();
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
    _identifierController.dispose();
    _passwordController.dispose();
    _displayNameController.dispose();
    _serverController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    final identifier = _identifierController.text.trim();
    final password = _passwordController.text;
    if (identifier.isEmpty || password.isEmpty) {
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
        final result = await notifier.register(
          email: identifier,
          password: password,
          displayName: _displayNameController.text.trim(),
        );
        if (!mounted) return;
        if (result.passwordRecoveryCodes.isNotEmpty ||
            result.mfaRecoveryCodes.isNotEmpty) {
          await showRecoveryCodesDialog(
            context,
            title: l10n.authRecoveryCodesTitle,
            passwordCodes: result.passwordRecoveryCodes,
            mfaCodes: result.mfaRecoveryCodes,
          );
        }
        await notifier.completeRegistration(result);
      } else {
        await notifier.login(identifier: identifier, password: password);
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openForgotPassword() async {
    final l10n = AppLocalizations.of(context)!;
    final reset = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
    );
    if (reset == true && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.forgotPasswordSuccess)));
    }
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
                      controller: _identifierController,
                      decoration: InputDecoration(
                        labelText: _registerMode
                            ? l10n.authEmail
                            : l10n.authIdentifier,
                      ),
                      keyboardType: _registerMode
                          ? TextInputType.emailAddress
                          : TextInputType.text,
                      autocorrect: false,
                      textInputAction: TextInputAction.next,
                    ),
                    if (_registerMode) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _displayNameController,
                        decoration: InputDecoration(
                          labelText: l10n.authDisplayName,
                        ),
                        textInputAction: TextInputAction.next,
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passwordController,
                      decoration: InputDecoration(
                        labelText: l10n.authPassword,
                        helperText: _registerMode
                            ? l10n.authPasswordMinHint
                            : null,
                      ),
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
                    if (!_registerMode)
                      TextButton(
                        onPressed: _loading ? null : _openForgotPassword,
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
