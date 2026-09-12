import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'l10n/app_localizations.dart';
import 'providers/locale_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/shell.dart';
import 'theme/app_theme.dart';

class PhotoAtlasApp extends ConsumerWidget {
  const PhotoAtlasApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeOption = ref.watch(themeProvider);
    final locale = ref.watch(localeProvider);

    return MaterialApp(
      onGenerateTitle: (context) =>
          AppLocalizations.of(context)?.appTitle ?? 'Photo Atlas',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(themeOption),
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('it')],
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: const AppShell(),
    );
  }
}
