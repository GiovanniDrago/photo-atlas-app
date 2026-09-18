import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/api_config.dart';

class SecureLocalStorage extends LocalStorage {
  static const _key = 'supabase_session';
  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  Future<String?> _read() async {
    try {
      return await _secure.read(key: _key);
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_key);
    }
  }

  Future<void> _write(String value) async {
    try {
      await _secure.write(key: _key, value: value);
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, value);
    }
  }

  Future<void> _delete() async {
    try {
      await _secure.delete(key: _key);
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() async => (await _read()) != null;

  @override
  Future<String?> accessToken() => _read();

  @override
  Future<void> persistSession(String persistSessionString) =>
      _write(persistSessionString);

  @override
  Future<void> removePersistedSession() => _delete();
}

class SupabaseBootstrap {
  static bool _initialized = false;
  static String? _url;

  static Future<void> ensure(ApiConfig config) async {
    if (config.supabaseUrl.isEmpty || config.supabasePublishableKey.isEmpty) {
      throw StateError(
        'The API did not return the Supabase configuration (/api/config)',
      );
    }
    if (_initialized && _url == config.supabaseUrl) return;
    if (_initialized) {
      try {
        await Supabase.instance.dispose();
      } catch (_) {}
      _initialized = false;
    }
    await Supabase.initialize(
      url: config.supabaseUrl,
      publishableKey: config.supabasePublishableKey,
      authOptions: FlutterAuthClientOptions(localStorage: SecureLocalStorage()),
    );
    _initialized = true;
    _url = config.supabaseUrl;
  }
}
