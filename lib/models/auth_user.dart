class AuthUser {
  final String id;
  final String username;
  final String? email;
  final String? displayName;
  final bool mfaEnabled;

  const AuthUser({
    required this.id,
    required this.username,
    this.email,
    this.displayName,
    this.mfaEnabled = false,
  });

  String get label => displayName?.isNotEmpty == true ? displayName! : username;

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: (json['id'] ?? '') as String,
      username: (json['username'] ?? '') as String,
      email: json['email'] as String?,
      displayName: json['display_name'] as String?,
      mfaEnabled: (json['mfa_enabled'] ?? false) as bool,
    );
  }

  AuthUser copyWith({bool? mfaEnabled}) {
    return AuthUser(
      id: id,
      username: username,
      email: email,
      displayName: displayName,
      mfaEnabled: mfaEnabled ?? this.mfaEnabled,
    );
  }
}

class AuthResult {
  final AuthUser user;
  final String token;
  final bool mfaRequired;

  const AuthResult({
    required this.user,
    required this.token,
    this.mfaRequired = false,
  });

  factory AuthResult.fromJson(Map<String, dynamic> json) {
    return AuthResult(
      user: AuthUser.fromJson(
        (json['user'] ?? const <String, dynamic>{}) as Map<String, dynamic>,
      ),
      token: (json['token'] ?? '') as String,
      mfaRequired: (json['mfa_required'] ?? false) as bool,
    );
  }
}

class RegisterResult extends AuthResult {
  final List<String> passwordRecoveryCodes;
  final List<String> mfaRecoveryCodes;

  const RegisterResult({
    required super.user,
    required super.token,
    required this.passwordRecoveryCodes,
    required this.mfaRecoveryCodes,
  });

  factory RegisterResult.fromJson(Map<String, dynamic> json) {
    final codes =
        (json['recovery_codes'] ?? const <String, dynamic>{})
            as Map<String, dynamic>;
    List<String> list(String key) =>
        ((codes[key] ?? const <dynamic>[]) as List<dynamic>)
            .map((value) => '$value')
            .toList();
    return RegisterResult(
      user: AuthUser.fromJson(
        (json['user'] ?? const <String, dynamic>{}) as Map<String, dynamic>,
      ),
      token: (json['token'] ?? '') as String,
      passwordRecoveryCodes: list('password'),
      mfaRecoveryCodes: list('mfa'),
    );
  }
}

class MfaSetup {
  final String secret;
  final String otpauthUri;

  const MfaSetup({required this.secret, required this.otpauthUri});

  factory MfaSetup.fromJson(Map<String, dynamic> json) {
    return MfaSetup(
      secret: (json['secret'] ?? '') as String,
      otpauthUri: (json['otpauth_uri'] ?? '') as String,
    );
  }
}

class AuthSession {
  final String id;
  final DateTime? createdAt;
  final DateTime? lastUsedAt;
  final DateTime? expiresAt;
  final String? userAgent;
  final String? ip;
  final bool current;

  const AuthSession({
    required this.id,
    this.createdAt,
    this.lastUsedAt,
    this.expiresAt,
    this.userAgent,
    this.ip,
    this.current = false,
  });

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      id: (json['id'] ?? '') as String,
      createdAt: _date(json['created_at']),
      lastUsedAt: _date(json['last_used_at']),
      expiresAt: _date(json['expires_at']),
      userAgent: json['user_agent'] as String?,
      ip: json['ip'] as String?,
      current: (json['current'] ?? false) as bool,
    );
  }

  static DateTime? _date(dynamic value) =>
      value is String ? DateTime.tryParse(value)?.toLocal() : null;
}
