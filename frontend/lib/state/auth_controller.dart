/// Authentication controller (Riverpod `Notifier`): login, silent session
/// restore from secure storage, role-aware session state and global 401
/// handling (server-authoritative token expiry -> session cleared -> router
/// redirects to sign-in and protected polling stops).
///
/// Passwords are NEVER stored. On web, `TokenStorage.platform()` is
/// memory-only, so a reload simply requires signing in again (assignment §7).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_exception.dart';
import '../data/dto/auth_dto.dart';
import 'providers.dart';

enum AuthPhase { restoring, signedOut, signedIn }

class AuthState {
  const AuthState({
    required this.phase,
    this.session,
    this.sessionExpired = false,
  });

  static const AuthState restoring = AuthState(phase: AuthPhase.restoring);

  final AuthPhase phase;

  /// Non-null iff [AuthPhase.signedIn].
  final Session? session;

  /// True when a server 401 ended the session (login screen explains why
  /// the user is back at sign-in).
  final bool sessionExpired;

  bool get isSignedIn => phase == AuthPhase.signedIn;
  bool get isAdmin => session?.isAdmin ?? false;

  AuthState copyWith({AuthPhase? phase, Session? session, bool? sessionExpired}) =>
      AuthState(
        phase: phase ?? this.phase,
        session: session ?? this.session,
        sessionExpired: sessionExpired ?? this.sessionExpired,
      );
}

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    _restore();
    return AuthState.restoring;
  }

  /// Silent restore: validates any persisted token against `GET /me`.
  /// Network failures leave the user signed OUT but keep the token for the
  /// next launch; a 401/403 clears it for good.
  Future<void> _restore() async {
    final storage = ref.read(tokenStorageProvider);
    String? token;
    try {
      token = await storage.readToken();
    } catch (_) {
      // Secure storage unavailable (e.g. desktop without a keyring service):
      // fall back to memory-only session for this run.
      token = null;
    }
    if (token == null || token.isEmpty) {
      _set(const AuthState(phase: AuthPhase.signedOut));
      return;
    }

    final store = ref.read(sessionStoreProvider);
    store.current = Session(
      accessToken: token,
      tokenType: 'bearer',
      user: const UserSummary(id: '', email: '', fullName: '', role: 'customer'),
    );
    try {
      final user = await ref.read(authRepositoryProvider).me();
      if (!ref.mounted) return;
      store.current = Session(
        accessToken: token,
        tokenType: 'bearer',
        user: user,
      );
      _set(AuthState(phase: AuthPhase.signedIn, session: store.current));
    } on ApiException catch (exc) {
      if (!ref.mounted) return;
      store.current = null;
      if (exc.isUnauthorized || exc.isForbidden) {
        try {
          await storage.deleteToken();
        } catch (_) {}
      }
      // Transport failure: keep the stored token, sign out for this run.
      _set(const AuthState(phase: AuthPhase.signedOut));
    } catch (_) {
      if (!ref.mounted) return;
      store.current = null;
      _set(const AuthState(phase: AuthPhase.signedOut));
    }
  }

  /// `POST /auth/login`. Throws [ApiException] for the login form to render
  /// (invalid credentials, network, timeout...).
  Future<Session> signIn({required String email, required String password}) async {
    final session =
        await ref.read(authRepositoryProvider).login(email: email, password: password);
    if (!ref.mounted) return session;
    ref.read(sessionStoreProvider).current = session;
    try {
      await ref.read(tokenStorageProvider).writeToken(session.accessToken);
    } catch (_) {
      // Memory-only fallback for the run — session still works.
    }
    _set(AuthState(phase: AuthPhase.signedIn, session: session));
    return session;
  }

  /// Server answered 401: the token is expired/invalid — clear everything so
  /// the router redirects and background polling stops immediately.
  void handleUnauthorized() {
    if (!state.isSignedIn && state.phase == AuthPhase.signedOut) return;
    final store = ref.read(sessionStoreProvider);
    store.current = null;
    ref.read(tokenStorageProvider).deleteToken().catchError((Object _) {});
    _set(const AuthState(phase: AuthPhase.signedOut, sessionExpired: true));
  }

  Future<void> signOut() async {
    ref.read(sessionStoreProvider).current = null;
    try {
      await ref.read(tokenStorageProvider).deleteToken();
    } catch (_) {}
    if (!ref.mounted) return;
    _set(const AuthState(phase: AuthPhase.signedOut));
  }

  /// Login screen consumes the banner once shown.
  void acknowledgeSessionExpiry() {
    if (state.sessionExpired) {
      _set(state.copyWith(sessionExpired: false));
    }
  }

  void _set(AuthState next) {
    if (!ref.mounted) return;
    state = next;
  }
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);
