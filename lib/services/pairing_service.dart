import '../models/pairing_model.dart';
import 'api_service.dart';

/// Pairing service — wraps /pairing/* endpoints.
class PairingService {
  final ApiService _api;

  PairingService({ApiService? api}) : _api = api ?? ApiService();

  // ── Send request ────────────────────────────────────────────────────────────

  /// Device A sends a pairing request to [targetDeviceId].
  Future<PairingModel> sendPairingRequest(String targetDeviceId) async {
    final resp = await _api.post(
      '/pairing/request',
      data: {'target_device_id': targetDeviceId},
    );
    return PairingModel.fromJson(resp.data as Map<String, dynamic>);
  }

  // ── Respond ─────────────────────────────────────────────────────────────────

  /// Device B accepts a pending request.
  Future<PairingModel> acceptPairing(String pairingId) async {
    final resp = await _api.post(
      '/pairing/$pairingId/respond',
      data: {'action': 'accept'},
    );
    return PairingModel.fromJson(resp.data as Map<String, dynamic>);
  }

  /// Device B rejects a pending request.
  Future<PairingModel> rejectPairing(String pairingId) async {
    final resp = await _api.post(
      '/pairing/$pairingId/respond',
      data: {'action': 'reject'},
    );
    return PairingModel.fromJson(resp.data as Map<String, dynamic>);
  }

  // ── Revoke ──────────────────────────────────────────────────────────────────

  /// Either device revokes an existing pairing.
  Future<PairingModel> revokePairing(String pairingId) async {
    final resp = await _api.delete('/pairing/$pairingId');
    return PairingModel.fromJson(resp.data as Map<String, dynamic>);
  }

  // ── List ────────────────────────────────────────────────────────────────────

  Future<List<PairingModel>> getPendingRequests() async {
    final resp = await _api.get('/pairing/pending');
    return (resp.data as List)
        .map((e) => PairingModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<PairingModel>> getPairedDevices() async {
    final resp = await _api.get('/pairing/paired');
    return (resp.data as List)
        .map((e) => PairingModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<PairingModel>> getAllPairings() async {
    final resp = await _api.get('/pairing/all');
    return (resp.data as List)
        .map((e) => PairingModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
