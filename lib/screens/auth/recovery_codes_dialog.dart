import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';

Future<void> showRecoveryCodesDialog(
  BuildContext context, {
  required String title,
  List<String> passwordCodes = const [],
  List<String> mfaCodes = const [],
}) {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  final all = <String>[...passwordCodes, ...mfaCodes];
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.authRecoveryCodesBody),
            if (passwordCodes.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                l10n.authRecoveryCodesPasswordLabel,
                style: Theme.of(dialogContext).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              for (final code in passwordCodes)
                SelectableText(
                  code,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 16),
                ),
            ],
            if (mfaCodes.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                l10n.authRecoveryCodesMfaLabel,
                style: Theme.of(dialogContext).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              for (final code in mfaCodes)
                SelectableText(
                  code,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 16),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: all.isEmpty
              ? null
              : () async {
                  await Clipboard.setData(ClipboardData(text: all.join('\n')));
                  messenger.showSnackBar(
                    SnackBar(content: Text(l10n.authRecoveryCodesCopied)),
                  );
                },
          icon: const Icon(Icons.copy, size: 18),
          label: Text(l10n.authRecoveryCodesCopy),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(l10n.authRecoveryCodesDone),
        ),
      ],
    ),
  );
}
