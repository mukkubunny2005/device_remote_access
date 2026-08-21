import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/access_session_model.dart';
import '../services/access_service.dart';

class AccessState {
  final AccessSessionModel? incomingPrompt; // Triggers Consent Dialog on Target Device
  final AccessSessionModel? activeSession;
  final List<AccessSessionModel> pendingRequests;
  final List<AccessSessionModel> history;
  final bool loading;
  final String? error;

  const AccessState({
    this.incomingPrompt,
    this.activeSession,
    this.pendingRequests = const [],
    this.history = const [],
    this.loading = false,
    this.error,
  });

  AccessState copyWith({
    AccessSessionModel? incomingPrompt,
    bool clearIncomingPrompt = false,
    AccessSessionModel? activeSession,
    bool clearActiveSession = false,
    List<AccessSessionModel>? pendingRequests,
    List<AccessSessionModel>? history,
    bool? loading,
    String? error,
  }) {
    return AccessState(
      incomingPrompt: clearIncomingPrompt ? null : (incomingPrompt ?? this.incomingPrompt),
      activeSession: clearActiveSession ? null : (activeSession ?? this.activeSession),
      pendingRequests: pendingRequests ?? this.pendingRequests,
      history: history ?? this.history,
      loading: loading ?? this.loading,
      error: error,
    );
  }
}

final accessServiceProvider = Provider<AccessService>((ref) => AccessService());

class AccessNotifier extends StateNotifier<AccessState> {
  final AccessService _service;

  AccessNotifier(this._service) : super(const AccessState());

  Future<void> loadAll() async {
    state = state.copyWith(loading: true);
    try {
      final active = await _service.getActiveSession();
      final pending = await _service.getPendingRequests();
      final history = await _service.getSessionHistory();

      state = state.copyWith(
        loading: false,
        activeSession: active,
        clearActiveSession: active == null,
        pendingRequests: pending,
        history: history,
        error: null,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<AccessSessionModel> requestAccess({
    required String targetDeviceId,
    bool requestControl = true,
  }) async {
    final session = await _service.requestAccess(
      targetDeviceId: targetDeviceId,
      requestControl: requestControl,
    );
    await loadAll();
    return session;
  }

  Future<AccessSessionModel> respondAccess({
    required String sessionId,
    required bool accept,
    bool allowControl = true,
  }) async {
    final session = await _service.respondAccess(
      sessionId: sessionId,
      accept: accept,
      allowControl: allowControl,
    );
    state = state.copyWith(clearIncomingPrompt: true);
    await loadAll();
    return session;
  }

  Future<void> endSession(String sessionId) async {
    await _service.endSession(sessionId);
    state = state.copyWith(clearActiveSession: true);
    await loadAll();
  }

  void clearIncomingPrompt() {
    state = state.copyWith(clearIncomingPrompt: true);
  }

  void handleWebSocketEvent(Map<String, dynamic> event) {
    final type = event['type'] as String? ?? '';

    if (type == 'access_request') {
      final sessionId = event['session_id'] as String? ?? '';
      final requesterId = event['requester_device_id'] as String? ?? '';
      final canControl = event['can_control'] as bool? ?? false;
      final expiresAtStr = event['expires_at'] as String? ?? '';

      final model = AccessSessionModel(
        id: sessionId,
        requesterDeviceId: requesterId,
        targetDeviceId: '', // local device
        status: 'pending',
        viewOnly: !canControl,
        canControl: canControl,
        createdAt: DateTime.now(),
        expiresAt: DateTime.tryParse(expiresAtStr) ?? DateTime.now().add(const Duration(seconds: 60)),
      );

      state = state.copyWith(incomingPrompt: model);
      loadAll();
    } else if (type == 'access_response') {
      loadAll();
    } else if (type == 'session_ended') {
      state = state.copyWith(clearActiveSession: true);
      loadAll();
    }
  }
}

final accessProvider = StateNotifierProvider<AccessNotifier, AccessState>((ref) {
  return AccessNotifier(ref.read(accessServiceProvider));
});
