class ApiConfig {
  final String supabaseUrl;
  final String supabasePublishableKey;
  final String? emailConfirmRedirectUrl;

  const ApiConfig({
    required this.supabaseUrl,
    required this.supabasePublishableKey,
    this.emailConfirmRedirectUrl,
  });

  factory ApiConfig.fromJson(Map<String, dynamic> json) {
    return ApiConfig(
      supabaseUrl: (json['supabase_url'] ?? '') as String,
      supabasePublishableKey:
          (json['supabase_publishable_key'] ?? '') as String,
      emailConfirmRedirectUrl:
          (json['email_confirm_redirect_url'] as String?)?.trim().isEmpty ==
              true
          ? null
          : json['email_confirm_redirect_url'] as String?,
    );
  }
}
