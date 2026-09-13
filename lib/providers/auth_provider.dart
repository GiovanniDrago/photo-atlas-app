import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/auth_user.dart';
import '../services/api_client.dart';
import 'settings_provider.dart';

enum AuthStatus { unknown, loggedOut, loggedIn }

class AuthState {
  final AuthStatus status;
  final String? token;
  final AuthUser? user;

  const AuthState({required this.status, this.token, this.user});

  static const unknown = AuthState(status: AuthStatus.unknown);
  static const loggedOut = AuthState(status: AuthStatus.loggedOut);
}

class AuthNotifier extends Notifier<AuthState> {
  static const _tokenKey = 'auth_token';
  static const _usernameKey = 'auth_username';
  static const _userIdKey = 'auth_user_id';

  @override
  AuthState build() {
    _load();
    return AuthState.unknown;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    if (token == null || token.isEmpty) {
      state = AuthState.loggedOut;
      return;
    }
    final username = prefs.getString(_usernameKey);
    final userId = prefs.getString(_userIdKey);
    state = AuthState(
      status: AuthStatus.loggedIn,
      token: token,
      user: (username != null && userId != null)
          ? AuthUser(id: userId, username: username)
          : null,
    );
  }

  ApiClient _client() => ApiClient(ref.read(apiBaseUrlProvider));

  Future<void> login({
    required String username,
    required String password,
  }) async {
    final result = await _client().login(
      username: username,
      password: password,
    );
    await _persist(result);
  }

  Future<void> register({
    required String username,
    required String password,
  }) async {
    final result = await _client().register(
      username: username,
      password: password,
    );
    await _persist(result);
  }

  Future<void> _persist(AuthResult result) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, result.token);
    await prefs.setString(_usernameKey, result.user.username);
    await prefs.setString(_userIdKey, result.user.id);
    state = AuthState(
      status: AuthStatus.loggedIn,
      token: result.token,
      user: result.user,
    );
  }

  Future<void> logout() async {
    final token = state.token;
    if (token != null && token.isNotEmpty) {
      try {
        await ApiClient(ref.read(apiBaseUrlProvider), token: token).logout();
      } catch (_) {}
    }
    await _clear();
  }

  Future<void> handleUnauthorized() => _clear();

  Future<void> _clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_usernameKey);
    await prefs.remove(_userIdKey);
    state = AuthState.loggedOut;
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);
