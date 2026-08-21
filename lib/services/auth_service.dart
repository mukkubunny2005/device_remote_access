import '../models/user_model.dart';
import 'api_service.dart';
import 'storage_service.dart';

/// Authentication service.
///
/// Wraps the /auth/* endpoints and manages token persistence.
class AuthService {
  final ApiService _api;

  AuthService({ApiService? api}) : _api = api ?? ApiService();

  // ── Register ───────────────────────────────────────────────────────────────

  /// Create a new account and persist returned tokens.
  Future<void> register({
    required String email,
    required String password,
  }) async {
    final resp = await _api.post('/auth/register', data: {
      'email': email,
      'password': password,
    });
    await StorageService.saveTokens(
      accessToken: resp.data['access_token'] as String,
      refreshToken: resp.data['refresh_token'] as String,
    );
  }

  // ── Login ──────────────────────────────────────────────────────────────────

  /// Login with email/password and persist tokens.
  Future<void> login({
    required String email,
    required String password,
  }) async {
    final resp = await _api.post('/auth/login', data: {
      'email': email,
      'password': password,
    });
    await StorageService.saveTokens(
      accessToken: resp.data['access_token'] as String,
      refreshToken: resp.data['refresh_token'] as String,
    );
  }

  // ── Logout ─────────────────────────────────────────────────────────────────

  /// Log out and clear local tokens.
  Future<void> logout() async {
    try {
      await _api.post('/auth/logout');
    } catch (_) {
      // Ignore — always clear tokens locally
    } finally {
      await StorageService.clearTokens();
    }
  }

  // ── Current user ───────────────────────────────────────────────────────────

  /// Return the currently authenticated user from the backend.
  Future<UserModel> getCurrentUser() async {
    final resp = await _api.get('/auth/me');
    return UserModel.fromJson(resp.data as Map<String, dynamic>);
  }

  // ── Token state ────────────────────────────────────────────────────────────

  /// True if a locally-stored access token exists.
  Future<bool> isLoggedIn() => StorageService.hasTokens();
}
