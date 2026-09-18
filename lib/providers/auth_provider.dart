import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/auth_user.dart';
import '../services/api_client.dart';
import 'settings_provider.dart';

enum AuthStatus { unknown, loggedOut, mfaRequired, loggedIn }

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
  static const _emailKey = 'auth_email';
  static const _displayNameKey = 'auth_display_name';
  static const _mfaEnabledKey = 'auth_mfa_enabled';

  static const _secureStorage = FlutterSecureStorage();

  @override
  AuthState build() {
    _load();
    return AuthState.unknown;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    var token = await _readToken();
    final legacyToken = prefs.getString(_tokenKey);
    if ((token == null || token.isEmpty) &&
        legacyToken != null &&
        legacyToken.isNotEmpty) {
      token = legacyToken;
      await _writeToken(legacyToken);
      await prefs.remove(_tokenKey);
    }
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
          ? AuthUser(
              id: userId,
              username: username,
              email: prefs.getString(_emailKey),
              displayName: prefs.getString(_displayNameKey),
              mfaEnabled: prefs.getBool(_mfaEnabledKey) ?? false,
            )
          : null,
    );
    _refreshUser(token);
  }

  Future<void> _refreshUser(String token) async {
    try {
      final user = await ApiClient(
        ref.read(apiBaseUrlProvider),
        token: token,
      ).me();
      if (state.status == AuthStatus.loggedIn && state.token == token) {
        await _persistUser(user);
        state = AuthState(
          status: AuthStatus.loggedIn,
          token: token,
          user: user,
        );
      }
    } on ApiException catch (error) {
      if (error.statusCode == 401) await _clear();
    } catch (_) {}
  }

  Future<String?> _readToken() async {
    try {
      return await _secureStorage.read(key: _tokenKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeToken(String token) async {
    try {
      await _secureStorage.write(key: _tokenKey, value: token);
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, token);
    }
  }

  Future<void> _deleteToken() async {
    try {
      await _secureStorage.delete(key: _tokenKey);
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }

  ApiClient _client() => ApiClient(ref.read(apiBaseUrlProvider));

  Future<RegisterResult> register({
    required String email,
    required String password,
    String? displayName,
  }) async {
    return _client().register(
      email: email,
      password: password,
      displayName: displayName,
    );
  }

  Future<void> completeRegistration(RegisterResult result) async {
    await _persist(result);
  }

  Future<bool> login({
    required String identifier,
    required String password,
  }) async {
    final result = await _client().login(
      identifier: identifier,
      password: password,
    );
    if (result.mfaRequired) {
      state = AuthState(
        status: AuthStatus.mfaRequired,
        token: result.token,
        user: result.user,
      );
      return true;
    }
    await _persist(result);
    return false;
  }

  Future<void> verifyMfa(String code) async {
    final token = state.token;
    if (token == null || token.isEmpty) {
      throw const ApiException(401, 'unauthorized');
    }
    final user = await ApiClient(
      ref.read(apiBaseUrlProvider),
      token: token,
    ).mfaVerify(code);
    await _writeToken(token);
    await _persistUser(user);
    state = AuthState(status: AuthStatus.loggedIn, token: token, user: user);
  }

  Future<void> cancelMfa() async {
    final token = state.token;
    if (token != null && token.isNotEmpty) {
      try {
        await ApiClient(ref.read(apiBaseUrlProvider), token: token).logout();
      } catch (_) {}
    }
    state = AuthState.loggedOut;
  }

  Future<AuthUser> updateMfaUser(AuthUser user) async {
    await _persistUser(user);
    final token = state.token;
    state = AuthState(status: state.status, token: token, user: user);
    return user;
  }

  Future<AuthUser> refreshUser() async {
    final token = state.token;
    if (token == null || token.isEmpty) {
      throw const ApiException(401, 'unauthorized');
    }
    final user = await ApiClient(
      ref.read(apiBaseUrlProvider),
      token: token,
    ).me();
    await _persistUser(user);
    state = AuthState(status: state.status, token: token, user: user);
    return user;
  }

  Future<void> _persist(AuthResult result) async {
    await _writeToken(result.token);
    await _persistUser(result.user);
    state = AuthState(
      status: AuthStatus.loggedIn,
      token: result.token,
      user: result.user,
    );
  }

  Future<void> _persistUser(AuthUser user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_usernameKey, user.username);
    await prefs.setString(_userIdKey, user.id);
    if (user.email != null) {
      await prefs.setString(_emailKey, user.email!);
    }
    if (user.displayName != null) {
      await prefs.setString(_displayNameKey, user.displayName!);
    }
    await prefs.setBool(_mfaEnabledKey, user.mfaEnabled);
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
    await _deleteToken();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_usernameKey);
    await prefs.remove(_userIdKey);
    await prefs.remove(_emailKey);
    await prefs.remove(_displayNameKey);
    await prefs.remove(_mfaEnabledKey);
    state = AuthState.loggedOut;
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);
