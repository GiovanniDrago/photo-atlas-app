class AuthUser {
  final String id;
  final String username;

  const AuthUser({required this.id, required this.username});

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: (json['id'] ?? '') as String,
      username: (json['username'] ?? '') as String,
    );
  }
}

class AuthResult {
  final AuthUser user;
  final String token;

  const AuthResult({required this.user, required this.token});

  factory AuthResult.fromJson(Map<String, dynamic> json) {
    return AuthResult(
      user: AuthUser.fromJson(
        (json['user'] ?? const <String, dynamic>{}) as Map<String, dynamic>,
      ),
      token: (json['token'] ?? '') as String,
    );
  }
}
