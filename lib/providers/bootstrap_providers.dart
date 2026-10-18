import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/api_config.dart';
import '../services/api_client.dart';
import '../services/supabase_bootstrap.dart';
import 'settings_provider.dart';

final apiConfigProvider = FutureProvider<ApiConfig>((ref) async {
  await ref.read(apiBaseUrlProvider.notifier).ready;
  final baseUrl = ref.watch(apiBaseUrlProvider);
  try {
    return await ApiClient(baseUrl).apiConfig();
  } on ApiException {
    final found = await ref
        .read(apiBaseUrlProvider.notifier)
        .detectAndSave(prefer: defaultApiBaseUrl);
    if (found == null) rethrow;
    return ApiClient(found).apiConfig();
  }
});

final supabaseReadyProvider = FutureProvider<ApiConfig>((ref) async {
  final config = await ref.watch(apiConfigProvider.future);
  await SupabaseBootstrap.ensure(config).timeout(
    const Duration(seconds: 25),
    onTimeout: () => throw StateError(
      'Supabase initialization timed out: check the internet connection',
    ),
  );
  return config;
});
