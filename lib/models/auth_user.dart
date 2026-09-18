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

  String get label {
    if (displayName != null && displayName!.isNotEmpty) return displayName!;
    if (username.isNotEmpty) return username;
    return email ?? id;
  }

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    final email = json['email'] as String?;
    final rawUsername = (json['username'] ?? '') as String;
    return AuthUser(
      id: (json['id'] ?? '') as String,
      username: rawUsername.isNotEmpty
          ? rawUsername
          : (email?.split('@').first ?? ''),
      email: email,
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
