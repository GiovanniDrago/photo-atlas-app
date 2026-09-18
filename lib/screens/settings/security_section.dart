import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../l10n/app_localizations.dart';
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

  Future<void> _enableMfa() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _busy = true);
    try {
      final client = sb.Supabase.instance.client;
      final response = await client.auth.mfa.enroll(
        factorType: sb.FactorType.totp,
        friendlyName: 'Photo Atlas',
      );
      final secret = response.totp?.secret;
      if (secret == null || secret.isEmpty) {
        throw const ApiException(500, 'Supabase did not return a TOTP secret');
      }
      if (!mounted) return;
      final code = await _showQrDialog(response.id, secret);
      if (code == null || code.isEmpty) {
        await client.auth.mfa.unenroll(response.id);
        return;
      }
      await client.auth.mfa.challengeAndVerify(
        factorId: response.id,
        code: code,
      );
      await ref.read(authProvider.notifier).syncMfa();
      final codes = await ref
          .read(apiClientProvider)
          .regenerateRecoveryCodes(kind: 'mfa');
      if (!mounted) return;
      await showRecoveryCodesDialog(
        context,
        title: l10n.authRecoveryCodesTitle,
        mfaCodes: codes,
      );
    } on sb.AuthException catch (error) {
      if (mounted) _snack(error.message);
    } on ApiException catch (error) {
      if (mounted) _snack(error.message);
    } catch (error) {
      if (mounted) _snack('$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _showQrDialog(String factorId, String secret) {
    final l10n = AppLocalizations.of(context)!;
    final account = ref.read(authProvider).user?.email ?? 'user';
    final uri =
        'otpauth://totp/${Uri.encodeComponent('Photo Atlas:$account')}'
        '?secret=$secret&issuer=Photo%20Atlas&algorithm=SHA1&digits=6&period=30';
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
                child: QrImageView(data: uri, size: 200),
              ),
              const SizedBox(height: 12),
              SelectableText(
                secret,
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
    setState(() => _busy = true);
    try {
      final client = sb.Supabase.instance.client;
      final factors = await client.auth.mfa.listFactors();
      final verified = factors.totp
          .where((factor) => factor.status == sb.FactorStatus.verified)
          .toList();
      for (final factor in verified) {
        await client.auth.mfa.unenroll(factor.id);
      }
      await ref.read(authProvider.notifier).syncMfa();
      if (mounted) _snack(l10n.securityMfaDisabledMessage);
    } on sb.AuthException catch (error) {
      if (mounted) _snack(error.message);
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
    final mfaEnabled = ref.read(authProvider).user?.mfaEnabled ?? false;
    setState(() => _busy = true);
    try {
      final client = ref.read(apiClientProvider);
      final passwordCodes = await client.regenerateRecoveryCodes();
      final mfaCodes = mfaEnabled
          ? await client.regenerateRecoveryCodes(kind: 'mfa')
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

  Future<void> _signOutEverywhere() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.securitySignOutEverywhere),
        content: Text(l10n.securitySignOutEverywhereBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.kdriveCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.securitySignOutEverywhere),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(authProvider.notifier).signOutEverywhere();
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
            leading: const Icon(Icons.logout),
            title: Text(l10n.securitySignOutEverywhere),
            trailing: const Icon(Icons.chevron_right),
            onTap: _busy ? null : _signOutEverywhere,
          ),
        ],
      ),
    );
  }
}
