import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../models/auth_user.dart';
import '../services/api_client.dart';
import 'bootstrap_providers.dart';
import 'settings_provider.dart';

enum AuthStatus { unknown, loggedOut, mfaRequired, loggedIn }

class AuthState {
  final AuthStatus status;
  final String? token;
  final AuthUser? user;
  final List<String>? newRecoveryCodes;

  const AuthState({
    required this.status,
    this.token,
    this.user,
    this.newRecoveryCodes,
  });

  static const unknown = AuthState(status: AuthStatus.unknown);
  static const loggedOut = AuthState(status: AuthStatus.loggedOut);
}

class AuthNotifier extends Notifier<AuthState> {
  StreamSubscription<sb.AuthState>? _subscription;

  @override
  AuthState build() {
    final client = sb.Supabase.instance.client;
    _subscription = client.auth.onAuthStateChange.listen(_onAuthChange);
    ref.onDispose(() => _subscription?.cancel());
    final session = client.auth.currentSession;
    if (session == null) {
      return AuthState.loggedOut;
    }
    return AuthState(
      status: AuthStatus.loggedIn,
      token: session.accessToken,
      user: _userFromSession(session),
    );
  }

  AuthUser? _userFromSession(sb.Session session) {
    final user = session.user;
    return AuthUser(
      id: user.id,
      username: user.email?.split('@').first ?? '',
      email: user.email,
      displayName: (user.userMetadata?['display_name'] ?? '') as String?,
    );
  }

  void _onAuthChange(sb.AuthState event) {
    final session = event.session;
    switch (event.event) {
      case sb.AuthChangeEvent.signedOut:
        state = AuthState.loggedOut;
        break;
      case sb.AuthChangeEvent.tokenRefreshed:
      case sb.AuthChangeEvent.userUpdated:
      case sb.AuthChangeEvent.initialSession:
      case sb.AuthChangeEvent.signedIn:
      case sb.AuthChangeEvent.mfaChallengeVerified:
        if (session != null) {
          unawaited(_syncSession(session));
        }
        break;
      default:
        break;
    }
  }

  Future<void> _syncSession(sb.Session session) async {
    if (state.status == AuthStatus.loggedIn &&
        state.token == session.accessToken) {
      return;
    }
    final client = sb.Supabase.instance.client;
    try {
      final level = client.auth.mfa.getAuthenticatorAssuranceLevel();
      if (level.currentLevel == sb.AuthenticatorAssuranceLevels.aal1 &&
          level.nextLevel == sb.AuthenticatorAssuranceLevels.aal2) {
        state = AuthState(
          status: AuthStatus.mfaRequired,
          token: session.accessToken,
          user: _userFromSession(session),
        );
        return;
      }
    } catch (_) {}
    await _completeLogin(session);
  }

  ApiClient _api(String token) =>
      ApiClient(ref.read(apiBaseUrlProvider), token: token);

  Future<void> _completeLogin(sb.Session session) async {
    AuthUser? user = _userFromSession(session);
    try {
      user = await _api(session.accessToken).me();
    } catch (_) {}
    state = AuthState(
      status: AuthStatus.loggedIn,
      token: session.accessToken,
      user: user,
    );
    unawaited(_ensureRecoveryCodes(session));
  }

  Future<void> _ensureRecoveryCodes(sb.Session session) async {
    try {
      final client = _api(session.accessToken);
      final counts = await client.recoveryCodeCounts();
      if (counts.password > 0) return;
      final codes = await client.regenerateRecoveryCodes();
      if (state.status == AuthStatus.loggedIn &&
          state.token == session.accessToken) {
        state = AuthState(
          status: AuthStatus.loggedIn,
          token: session.accessToken,
          user: state.user,
          newRecoveryCodes: codes,
        );
      }
    } catch (_) {}
  }

  void clearNewRecoveryCodes() {
    state = AuthState(
      status: state.status,
      token: state.token,
      user: state.user,
    );
  }

  Future<void> login({required String email, required String password}) async {
    final client = sb.Supabase.instance.client;
    try {
      await client.auth.signInWithPassword(email: email, password: password);
    } on sb.AuthException catch (error) {
      throw ApiException(401, error.message);
    }
    await _afterSignIn();
  }

  Future<void> _afterSignIn() async {
    final client = sb.Supabase.instance.client;
    final session = client.auth.currentSession;
    if (session == null) {
      state = AuthState.loggedOut;
      return;
    }
    await _syncSession(session);
  }

  /// Returns true when a session was created, false when the account needs
  /// email confirmation first.
  Future<bool> register({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final client = sb.Supabase.instance.client;
    final config = ref.read(supabaseReadyProvider).value;
    try {
      final response = await client.auth.signUp(
        email: email,
        password: password,
        data: (displayName == null || displayName.isEmpty)
            ? null
            : {'display_name': displayName},
        emailRedirectTo: config?.emailConfirmRedirectUrl,
      );
      final session = response.session;
      if (session == null) return false;
      await _syncSession(session);
      return true;
    } on sb.AuthException catch (error) {
      throw ApiException(400, error.message);
    }
  }

  Future<void> verifyMfa(String code) async {
    final client = sb.Supabase.instance.client;
    try {
      final factors = await client.auth.mfa.listFactors();
      final verified = factors.totp
          .where((factor) => factor.status == sb.FactorStatus.verified)
          .toList();
      if (verified.isEmpty) {
        throw ApiException(400, 'no verified factor');
      }
      await client.auth.mfa.challengeAndVerify(
        factorId: verified.first.id,
        code: code,
      );
    } on sb.AuthException catch (error) {
      throw ApiException(401, error.message);
    }
    final session = client.auth.currentSession;
    if (session == null) {
      throw ApiException(401, 'unauthorized');
    }
    await _completeLogin(session);
  }

  Future<void> cancelMfa() async {
    try {
      await sb.Supabase.instance.client.auth.signOut();
    } catch (_) {}
    state = AuthState.loggedOut;
  }

  Future<void> logout() async {
    try {
      await sb.Supabase.instance.client.auth.signOut();
    } catch (_) {}
    state = AuthState.loggedOut;
  }

  Future<void> signOutEverywhere() async {
    try {
      await sb.Supabase.instance.client.auth.signOut(
        scope: sb.SignOutScope.global,
      );
    } catch (_) {}
    state = AuthState.loggedOut;
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final client = sb.Supabase.instance.client;
    try {
      await client.auth.updateUser(
        sb.UserAttributes(
          password: newPassword,
          currentPassword: currentPassword,
        ),
      );
    } on sb.AuthException catch (error) {
      throw ApiException(400, error.message);
    }
  }

  Future<AuthUser> refreshUser() async {
    final token = state.token;
    if (token == null || token.isEmpty) {
      throw ApiException(401, 'unauthorized');
    }
    final user = await _api(token).me();
    state = AuthState(status: state.status, token: token, user: user);
    return user;
  }

  Future<AuthUser> syncMfa() async {
    final token = state.token;
    if (token == null || token.isEmpty) {
      throw ApiException(401, 'unauthorized');
    }
    final user = await _api(token).mfaSync();
    state = AuthState(status: state.status, token: token, user: user);
    return user;
  }

  Future<void> handleUnauthorized() async {
    final client = sb.Supabase.instance.client;
    final session = client.auth.currentSession;
    if (session != null) {
      try {
        await client.auth.refreshSession();
        return;
      } catch (_) {}
    }
    state = AuthState.loggedOut;
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);
