import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';

/// Persistent storage service.
///
/// - [SharedPreferences] for non-sensitive data (Device ID, device name).
/// - [FlutterSecureStorage] for sensitive data (JWT access & refresh tokens).
class StorageService {
  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  // ── Device ID (non-sensitive, survives reinstall only if backup enabled) ───

  static Future<String?> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(AppConfig.kDeviceId);
  }

  static Future<void> saveDeviceId(String deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConfig.kDeviceId, deviceId);
  }

  static Future<String?> getDeviceName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(AppConfig.kDeviceName);
  }

  static Future<void> saveDeviceName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConfig.kDeviceName, name);
  }

  // ── Tokens (encrypted) ────────────────────────────────────────────────────

  static Future<String?> getAccessToken() async {
    return _secureStorage.read(key: AppConfig.kAccessToken);
  }

  static Future<void> saveAccessToken(String token) async {
    await _secureStorage.write(key: AppConfig.kAccessToken, value: token);
  }

  static Future<String?> getRefreshToken() async {
    return _secureStorage.read(key: AppConfig.kRefreshToken);
  }

  static Future<void> saveRefreshToken(String token) async {
    await _secureStorage.write(key: AppConfig.kRefreshToken, value: token);
  }

  static Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await Future.wait([
      saveAccessToken(accessToken),
      saveRefreshToken(refreshToken),
    ]);
  }

  static Future<void> clearTokens() async {
    await Future.wait([
      _secureStorage.delete(key: AppConfig.kAccessToken),
      _secureStorage.delete(key: AppConfig.kRefreshToken),
    ]);
  }

  static Future<bool> hasTokens() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }
}
