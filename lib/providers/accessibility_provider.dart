import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/accessibility_control_service.dart';
import 'webrtc_provider.dart';

/// State for Accessibility Service on Device B (Target).
class AccessibilityState {
  final bool isEnabled;
  final bool isArmed;

  const AccessibilityState({
    this.isEnabled = false,
    this.isArmed = false,
  });

  AccessibilityState copyWith({bool? isEnabled, bool? isArmed}) {
    return AccessibilityState(
      isEnabled: isEnabled ?? this.isEnabled,
      isArmed: isArmed ?? this.isArmed,
    );
  }
}

/// Manages the Accessibility Service state and wires DataChannel messages
/// to gesture injection on Device B.
class AccessibilityNotifier extends StateNotifier<AccessibilityState> {
  final AccessibilityControlService _service;
  final Ref _ref;
  StreamSubscription<String>? _dataSub;

  AccessibilityNotifier(this._service, this._ref)
      : super(const AccessibilityState());

  Future<void> refresh() async {
    final enabled = await _service.isEnabled();
    state = state.copyWith(isEnabled: enabled);
  }

  Future<void> openSettings() => _service.openSettings();

  /// Called by Device B when a session with canControl=true is accepted.
  Future<void> armForSession() async {
    if (!state.isEnabled) return;
    await _service.enableControl();
    state = state.copyWith(isArmed: true);

    // Subscribe to DataChannel messages from WebRTC
    _dataSub?.cancel();
    _dataSub = _ref
        .read(webrtcProvider.notifier)
        .dataMessages
        .listen(_dispatchDataMessage);
  }

  /// Called when the session ends — disarms injection and stops listening.
  Future<void> disarm() async {
    _dataSub?.cancel();
    _dataSub = null;
    await _service.disableControl();
    state = state.copyWith(isArmed: false);
  }

  // ── DataChannel Message Dispatch ─────────────────────────────────────────────

  Future<void> _dispatchDataMessage(String raw) async {
    try {
      final Map<String, dynamic> msg = jsonDecode(raw) as Map<String, dynamic>;
      final action = msg['action'] as String? ?? '';

      switch (action) {
        case 'tap':
          final x = (msg['x'] as num?)?.toDouble() ?? 0.0;
          final y = (msg['y'] as num?)?.toDouble() ?? 0.0;
          await _service.performTap(x, y);
          break;

        case 'swipe':
          await _service.performSwipe(
            fromX: (msg['fromX'] as num?)?.toDouble() ?? 0.0,
            fromY: (msg['fromY'] as num?)?.toDouble() ?? 0.0,
            toX: (msg['toX'] as num?)?.toDouble() ?? 0.0,
            toY: (msg['toY'] as num?)?.toDouble() ?? 0.0,
            durationMs: (msg['durationMs'] as num?)?.toInt() ?? 300,
          );
          break;

        case 'move':
          // Treat move as a single-point tap for now (Phase 6 can improve)
          final x = (msg['x'] as num?)?.toDouble() ?? 0.0;
          final y = (msg['y'] as num?)?.toDouble() ?? 0.0;
          await _service.performTap(x, y);
          break;

        case 'back':
          await _service.performBack();
          break;

        case 'home':
          await _service.performHome();
          break;

        case 'recents':
          await _service.performRecents();
          break;
      }
    } catch (_) {
      // Malformed DataChannel message — ignore silently
    }
  }

  @override
  void dispose() {
    _dataSub?.cancel();
    super.dispose();
  }
}

final accessibilityServiceProvider =
    Provider<AccessibilityControlService>((ref) => AccessibilityControlService());

final accessibilityProvider =
    StateNotifierProvider<AccessibilityNotifier, AccessibilityState>((ref) {
  final svc = ref.read(accessibilityServiceProvider);
  return AccessibilityNotifier(svc, ref);
});
