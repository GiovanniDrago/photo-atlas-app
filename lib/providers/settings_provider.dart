import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _compileTimeApiBaseUrl = String.fromEnvironment('API_BASE_URL');

const fallbackApiBaseUrl = 'http://localhost:8787';

String platformDefaultApiBaseUrl() {
  if (kIsWeb) {
    final host = Uri.base.host;
    if (host.isNotEmpty) {
      return 'http://$host:8787';
    }
  }
  return fallbackApiBaseUrl;
}

bool isLoopbackBaseUrl(String value) {
  final host = Uri.tryParse(value)?.host ?? '';
  return host == 'localhost' || host == '127.0.0.1' || host == '::1';
}

class ApiBaseUrlNotifier extends Notifier<String> {
  static const _key = 'api_base_url';

  @override
  String build() {
    _load();
    if (_compileTimeApiBaseUrl.isNotEmpty) return _compileTimeApiBaseUrl;
    return platformDefaultApiBaseUrl();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_key);
    if (value == null || value.isEmpty) return;
    if (kIsWeb && isLoopbackBaseUrl(value)) {
      state = platformDefaultApiBaseUrl();
      return;
    }
    state = value;
  }

  Future<void> setBaseUrl(String value) async {
    final normalized = value.trim().replaceAll(RegExp(r'/+$'), '');
    state = normalized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, normalized);
  }
}

final apiBaseUrlProvider = NotifierProvider<ApiBaseUrlNotifier, String>(
  ApiBaseUrlNotifier.new,
);
