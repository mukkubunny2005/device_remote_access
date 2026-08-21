import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/websocket_service.dart';
import 'access_provider.dart';
import 'pairing_provider.dart';
import 'webrtc_provider.dart';

/// WebSocket provider — manages a single WebSocket connection and
/// routes incoming events to the appropriate notifiers.
class WebSocketNotifier extends StateNotifier<bool> {
  final WebSocketService _ws;
  final Ref _ref;
  StreamSubscription? _sub;

  WebSocketNotifier(this._ws, this._ref) : super(false);

  Future<void> connect(String deviceId) async {
    await _ws.connect(deviceId);
    state = true;
    _sub = _ws.messages.listen(_routeEvent);
  }

  void _routeEvent(Map<String, dynamic> event) {
    final type = event['type'] as String? ?? '';

    // Pairing events
    if (type.startsWith('pairing_')) {
      _ref.read(pairingProvider.notifier).handleWebSocketEvent(event);
    }
    // Access & session events
    else if (type.startsWith('access_') || type == 'session_ended') {
      _ref.read(accessProvider.notifier).handleWebSocketEvent(event);
    }
    // WebRTC signaling events (offer/answer/ice)
    else if (type.startsWith('webrtc_')) {
      _ref.read(webrtcProvider.notifier).handleSignalingEvent(event);
    }
  }

  Future<void> disconnect() async {
    await _sub?.cancel();
    await _ws.disconnect();
    state = false;
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ws.dispose();
    super.dispose();
  }
}

final webSocketServiceProvider =
    Provider<WebSocketService>((ref) => WebSocketService());

final webSocketProvider =
    StateNotifierProvider<WebSocketNotifier, bool>((ref) {
  final ws = ref.read(webSocketServiceProvider);
  return WebSocketNotifier(ws, ref);
});
