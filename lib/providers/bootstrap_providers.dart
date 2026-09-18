import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/api_config.dart';
import '../services/api_client.dart';
import '../services/supabase_bootstrap.dart';
import 'settings_provider.dart';

final apiConfigProvider = FutureProvider<ApiConfig>((ref) {
  final client = ApiClient(ref.watch(apiBaseUrlProvider));
  return client.apiConfig();
});

final supabaseReadyProvider = FutureProvider<ApiConfig>((ref) async {
  final config = await ref.watch(apiConfigProvider.future);
  await SupabaseBootstrap.ensure(config);
  return config;
});
