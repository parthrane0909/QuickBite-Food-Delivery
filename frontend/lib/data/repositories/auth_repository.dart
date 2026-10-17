/// Auth repository: `POST /auth/login` and `GET /me` only (registration and
/// password reset are explicitly out of scope for Milestone 5).
library;

import '../dto/auth_dto.dart';
import '../../core/network/api_client.dart';

class AuthRepository {
  const AuthRepository(this._client);

  final ApiClient _client;

  Future<Session> login({required String email, required String password}) async {
    final json = await _client.post(
      'auth/login',
      body: {'email': email.trim(), 'password': password},
    );
    return Session.fromJson(json);
  }

  Future<UserSummary> me() async {
    final json = await _client.get('me');
    return UserSummary.fromJson(json);
  }
}
