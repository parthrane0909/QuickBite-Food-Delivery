/// Auth DTOs — verified field-for-field against the live OpenAPI contract
/// (`POST /auth/login`, `GET /me`).
library;

class UserSummary {
  const UserSummary({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
  });

  final String id;
  final String email;
  final String fullName;

  /// "customer" | "admin" (server-enforced; the client only branches UI).
  final String role;

  bool get isAdmin => role == 'admin';

  factory UserSummary.fromJson(Map<String, dynamic> json) => UserSummary(
        id: json['id'] as String,
        email: json['email'] as String,
        fullName: json['full_name'] as String,
        role: json['role'] as String,
      );
}

/// Bearer session: token + expiry metadata + the user it belongs to.
class Session {
  const Session({
    required this.accessToken,
    required this.tokenType,
    required this.user,
    this.expiresIn,
    this.expiresAt,
  });

  final String accessToken;
  final String tokenType;

  /// Only known from a fresh login; a restored session has no local expiry
  /// metadata (the SERVER enforces expiry — a 401 ends the session).
  final int? expiresIn;
  final DateTime? expiresAt;
  final UserSummary user;

  bool get isAdmin => user.isAdmin;

  factory Session.fromJson(Map<String, dynamic> json) => Session(
        accessToken: json['access_token'] as String,
        tokenType: json['token_type'] as String,
        expiresIn: json['expires_in'] as int?,
        expiresAt: json['expires_at'] == null
            ? null
            : DateTime.parse(json['expires_at'] as String),
        user: UserSummary.fromJson(json['user'] as Map<String, dynamic>),
      );
}
