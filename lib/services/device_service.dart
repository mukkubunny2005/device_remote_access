import 'dart:math';

import '../config/app_config.dart';
import '../models/device_model.dart';
import 'api_service.dart';
import 'storage_service.dart';

/// Device service.
///
/// Handles:
/// - 8-digit Device ID generation and local persistence
/// - Device registration with the backend
/// - Status / heartbeat
class DeviceService {
  final ApiService _api;

  DeviceService({ApiService? api}) : _api = api ?? ApiService();

  // ── Device ID ──────────────────────────────────────────────────────────────

  /// Return the persisted Device ID, generating and saving one if absent.
  ///
  /// The ID is generated locally and then registered with the backend.
  /// On subsequent launches the same ID is returned from [SharedPreferences].
  Future<String> getOrCreateDeviceId() async {
    final stored = await StorageService.getDeviceId();
    if (stored != null && stored.length == 8) {
      return stored;
    }
    final newId = _generateDeviceId();
    await StorageService.saveDeviceId(newId);
    return newId;
  }

  /// Generate a cryptographically-random 8-digit numeric string.
  ///
  /// Uses [Random.secure] — does NOT use IMEI, MAC, or any hardware identifier.
  String _generateDeviceId() {
    final rng = Random.secure();
    final digits = List.generate(8, (_) => rng.nextInt(10));
    return digits.join();
  }

  // ── Registration ───────────────────────────────────────────────────────────

  /// Register this device with the backend.
  ///
  /// Safe to call on every launch — the backend performs an upsert.
  Future<DeviceModel> registerDevice({
    required String deviceId,
    required String deviceName,
  }) async {
    final resp = await _api.post('/devices/register', data: {
      'device_id': deviceId,
      'device_name': deviceName,
      'platform': 'android',
      'app_version': AppConfig.appVersion,
    });
    return DeviceModel.fromJson(resp.data as Map<String, dynamic>);
  }

  // ── My devices ─────────────────────────────────────────────────────────────

  /// Return all devices registered to the authenticated user.
  Future<List<DeviceModel>> getMyDevices() async {
    final resp = await _api.get('/devices/me');
    final list = resp.data as List<dynamic>;
    return list
        .map((e) => DeviceModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── Lookup ─────────────────────────────────────────────────────────────────

  /// Look up a device by its 8-digit ID (for pairing, Phase 2).
  Future<Map<String, dynamic>> lookupDevice(String deviceId) async {
    final resp = await _api.get('/devices/$deviceId');
    return resp.data as Map<String, dynamic>;
  }

  // ── Test accessor (do NOT call in production code) ─────────────────────────

  /// Exposed for unit tests only. Calls the same generator used internally.
  // ignore: invalid_use_of_visible_for_testing_member
  String testGenerateDeviceId() => _generateDeviceId();

  // ── Heartbeat ──────────────────────────────────────────────────────────────

  /// Update the device's online status on the backend.
  Future<void> updateStatus(String deviceId, {required bool online}) async {
    await _api.patch(
      '/devices/$deviceId/status',
      data: {'online': online},
    );
  }
}
