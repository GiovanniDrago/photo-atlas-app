import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../l10n/app_localizations.dart';
import '../../models/auth_user.dart';
import '../../providers/auth_provider.dart';
import '../../providers/library_providers.dart';
import '../../services/api_client.dart';
import '../auth/recovery_codes_dialog.dart';

class SecuritySection extends ConsumerStatefulWidget {
  const SecuritySection({super.key});

  @override
  ConsumerState<SecuritySection> createState() => _SecuritySectionState();
}

class _SecuritySectionState extends ConsumerState<SecuritySection> {
  bool _busy = false;

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<String?> _promptPassword(String title, String label) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(AppLocalizations.of(dialogContext)!.close),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text(AppLocalizations.of(dialogContext)!.continueLabel),
          ),
        ],
      ),
    );
    return result;
  }

  Future<void> _enableMfa() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _busy = true);
    try {
      final setup = await ref.read(apiClientProvider).mfaSetup();
      if (!mounted) return;
      final code = await _showQrDialog(setup);
      if (code == null || code.isEmpty) return;
      final result = await ref.read(apiClientProvider).mfaEnable(code);
      await ref.read(authProvider.notifier).updateMfaUser(result.user);
      if (!mounted) return;
      await showRecoveryCodesDialog(
        context,
        title: l10n.authRecoveryCodesTitle,
        mfaCodes: result.recoveryCodes,
      );
    } on ApiException catch (error) {
      if (mounted) _snack(error.message);
    } catch (error) {
      if (mounted) _snack('$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _showQrDialog(MfaSetup setup) {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.securityMfaTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.securityMfaScan,
                style: Theme.of(dialogContext).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(8),
                child: QrImageView(data: setup.otpauthUri, size: 200),
              ),
              const SizedBox(height: 12),
              SelectableText(
                setup.secret,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: l10n.securityMfaEnterCode,
                ),
                onSubmitted: (value) =>
                    Navigator.of(dialogContext).pop(value.trim()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.kdriveCancel),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: Text(l10n.securityEnableMfa),
          ),
        ],
      ),
    );
  }

  Future<void> _disableMfa() async {
    final l10n = AppLocalizations.of(context)!;
    final password = await _promptPassword(
      l10n.securityDisableMfa,
      l10n.authPassword,
    );
    if (password == null || password.isEmpty) return;
    setState(() => _busy = true);
    try {
      await ref.read(apiClientProvider).mfaDisable(password);
      await ref.read(authProvider.notifier).refreshUser();
      if (mounted) _snack(l10n.securityMfaDisabledMessage);
    } on ApiException catch (error) {
      if (mounted) _snack(error.message);
    } catch (error) {
      if (mounted) _snack('$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _regenerateRecoveryCodes() async {
    final l10n = AppLocalizations.of(context)!;
    final user = ref.read(authProvider).user;
    final password = await _promptPassword(
      l10n.securityRegenerateRecovery,
      l10n.authPassword,
    );
    if (password == null || password.isEmpty) return;
    setState(() => _busy = true);
    try {
      final client = ref.read(apiClientProvider);
      final passwordCodes = await client.regeneratePasswordRecoveryCodes(
        password,
      );
      final mfaCodes = (user?.mfaEnabled ?? false)
          ? await client.regenerateMfaRecoveryCodes(password)
          : <String>[];
      if (!mounted) return;
      await showRecoveryCodesDialog(
        context,
        title: l10n.authRecoveryCodesTitle,
        passwordCodes: passwordCodes,
        mfaCodes: mfaCodes,
      );
    } on ApiException catch (error) {
      if (mounted) _snack(error.message);
    } catch (error) {
      if (mounted) _snack('$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showSessions() async {
    await showDialog<void>(
      context: context,
      builder: (_) => const _SessionsDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final user = ref.watch(authProvider).user;
    final mfaEnabled = user?.mfaEnabled ?? false;
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.security),
            title: Text(l10n.securityMfaTitle),
            subtitle: Text(
              mfaEnabled ? l10n.securityMfaOn : l10n.securityMfaOff,
            ),
            trailing: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : mfaEnabled
                ? TextButton(
                    onPressed: _disableMfa,
                    child: Text(l10n.securityDisableMfa),
                  )
                : FilledButton.tonal(
                    onPressed: _enableMfa,
                    child: Text(l10n.securityEnableMfa),
                  ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.vpn_key_outlined),
            title: Text(l10n.securityRegenerateRecovery),
            trailing: const Icon(Icons.chevron_right),
            onTap: _busy ? null : _regenerateRecoveryCodes,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.devices_outlined),
            title: Text(l10n.securitySessions),
            trailing: const Icon(Icons.chevron_right),
            onTap: _busy ? null : _showSessions,
          ),
        ],
      ),
    );
  }
}

class _SessionsDialog extends ConsumerStatefulWidget {
  const _SessionsDialog();

  @override
  ConsumerState<_SessionsDialog> createState() => _SessionsDialogState();
}

class _SessionsDialogState extends ConsumerState<_SessionsDialog> {
  List<AuthSession> _sessions = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final sessions = await ref.read(apiClientProvider).sessions();
      if (mounted) {
        setState(() {
          _sessions = sessions;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm');
    return AlertDialog(
      title: Text(l10n.securitySessions),
      content: SizedBox(
        width: 420,
        child: _loading
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            : _error != null
            ? Text(_error!)
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final session in _sessions)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          session.current
                              ? Icons.phone_android
                              : Icons.devices_other,
                        ),
                        title: Text(
                          session.current
                              ? l10n.securitySessionCurrent
                              : (session.userAgent ?? session.ip ?? '-'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          dateFormat.format(
                            session.lastUsedAt ??
                                session.createdAt ??
                                DateTime.now(),
                          ),
                        ),
                        trailing: session.current
                            ? null
                            : TextButton(
                                onPressed: () async {
                                  await ref
                                      .read(apiClientProvider)
                                      .revokeSession(session.id);
                                  await _load();
                                },
                                child: Text(l10n.securityRevoke),
                              ),
                      ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await ref.read(apiClientProvider).revokeOtherSessions();
            await _load();
          },
          child: Text(l10n.securityRevokeOthers),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.close),
        ),
      ],
    );
  }
}
