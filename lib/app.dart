import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'l10n/app_localizations.dart';
import 'providers/auth_provider.dart';
import 'providers/bootstrap_providers.dart';
import 'providers/locale_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/auth/bootstrap_error_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/mfa_screen.dart';
import 'screens/auth/recovery_codes_dialog.dart';
import 'screens/shell.dart';
import 'services/update_service.dart';
import 'theme/app_theme.dart';

class PhotoAtlasApp extends ConsumerWidget {
  const PhotoAtlasApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeOption = ref.watch(themeProvider);
    final locale = ref.watch(localeProvider);
    final ready = ref.watch(supabaseReadyProvider);

    return MaterialApp(
      onGenerateTitle: (context) =>
          AppLocalizations.of(context)?.appTitle ?? 'Photo Atlas',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(themeOption),
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('it')],
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: ready.when(
        loading: () => const _SplashScreen(),
        error: (error, stackTrace) => BootstrapErrorScreen(error: '$error'),
        data: (_) => const _AuthGate(),
      ),
    );
  }
}

class _AuthGate extends ConsumerStatefulWidget {
  const _AuthGate();

  @override
  ConsumerState<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<_AuthGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) UpdateService.checkForUpdates(context, silent: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authProvider, (previous, next) {
      final codes = next.newRecoveryCodes;
      if (codes == null || codes.isEmpty) return;
      final l10n = AppLocalizations.of(context)!;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!context.mounted) return;
        await showRecoveryCodesDialog(
          context,
          title: l10n.authRecoveryCodesTitle,
          passwordCodes: codes,
        );
        ref.read(authProvider.notifier).clearNewRecoveryCodes();
      });
    });
    final auth = ref.watch(authProvider);
    return switch (auth.status) {
      AuthStatus.unknown => const _SplashScreen(),
      AuthStatus.loggedOut => const LoginScreen(),
      AuthStatus.mfaRequired => const MfaScreen(),
      AuthStatus.loggedIn => const AppShell(),
    };
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
