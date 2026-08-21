import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/pairing_model.dart';
import '../services/pairing_service.dart';

// ── State ──────────────────────────────────────────────────────────────────────

class PairingState {
  final List<PairingModel> pending;
  final List<PairingModel> paired;
  final bool loading;
  final String? error;

  const PairingState({
    this.pending = const [],
    this.paired = const [],
    this.loading = false,
    this.error,
  });

  PairingState copyWith({
    List<PairingModel>? pending,
    List<PairingModel>? paired,
    bool? loading,
    String? error,
  }) {
    return PairingState(
      pending: pending ?? this.pending,
      paired: paired ?? this.paired,
      loading: loading ?? this.loading,
      error: error,
    );
  }
}

// ── Provider ───────────────────────────────────────────────────────────────────

final pairingServiceProvider =
    Provider<PairingService>((ref) => PairingService());

class PairingNotifier extends StateNotifier<PairingState> {
  final PairingService _service;

  PairingNotifier(this._service) : super(const PairingState());

  // ── Load ─────────────────────────────────────────────────────────────────────

  Future<void> loadAll() async {
    state = state.copyWith(loading: true);
    try {
      final results = await Future.wait([
        _service.getPendingRequests(),
        _service.getPairedDevices(),
      ]);
      state = state.copyWith(
        loading: false,
        pending: results[0],
        paired: results[1],
        error: null,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  // ── Send request ──────────────────────────────────────────────────────────────

  Future<PairingModel> sendRequest(String targetDeviceId) async {
    final pairing = await _service.sendPairingRequest(targetDeviceId);
    // Refresh lists after sending
    await loadAll();
    return pairing;
  }

  // ── Accept / Reject ───────────────────────────────────────────────────────────

  Future<void> acceptRequest(String pairingId) async {
    await _service.acceptPairing(pairingId);
    await loadAll();
  }

  Future<void> rejectRequest(String pairingId) async {
    await _service.rejectPairing(pairingId);
    await loadAll();
  }

  // ── Revoke ────────────────────────────────────────────────────────────────────

  Future<void> revokePairing(String pairingId) async {
    await _service.revokePairing(pairingId);
    await loadAll();
  }

  // ── Handle incoming WebSocket event ──────────────────────────────────────────

  void handleWebSocketEvent(Map<String, dynamic> event) {
    final type = event['type'] as String? ?? '';
    if (type == 'pairing_request' ||
        type == 'pairing_response' ||
        type == 'pairing_revoked') {
      loadAll(); // Refresh state on any pairing-related WS event
    }
  }
}

final pairingProvider =
    StateNotifierProvider<PairingNotifier, PairingState>((ref) {
  return PairingNotifier(ref.read(pairingServiceProvider));
});
