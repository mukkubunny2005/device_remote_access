import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../services/webrtc_service.dart';
import 'websocket_provider.dart';

class WebRTCState {
  final WebRTCConnectionStatus status;
  final bool isStreaming;
  final bool isViewing;
  final String? sessionId;
  final String? peerDeviceId;
  final String? error;

  const WebRTCState({
    this.status = WebRTCConnectionStatus.idle,
    this.isStreaming = false,
    this.isViewing = false,
    this.sessionId,
    this.peerDeviceId,
    this.error,
  });

  bool get isConnected => status == WebRTCConnectionStatus.connected;
  bool get isConnecting => status == WebRTCConnectionStatus.connecting || status == WebRTCConnectionStatus.capturing;

  WebRTCState copyWith({
    WebRTCConnectionStatus? status,
    bool? isStreaming,
    bool? isViewing,
    String? sessionId,
    String? peerDeviceId,
    String? error,
  }) {
    return WebRTCState(
      status: status ?? this.status,
      isStreaming: isStreaming ?? this.isStreaming,
      isViewing: isViewing ?? this.isViewing,
      sessionId: sessionId ?? this.sessionId,
      peerDeviceId: peerDeviceId ?? this.peerDeviceId,
      error: error,
    );
  }
}

final webrtcServiceProvider = Provider<WebRTCService>((ref) {
  final ws = ref.read(webSocketServiceProvider);
  return WebRTCService(ws: ws);
});

class WebRTCNotifier extends StateNotifier<WebRTCState> {
  final WebRTCService _service;
  StreamSubscription? _statusSub;

  WebRTCNotifier(this._service) : super(const WebRTCState()) {
    _init();
  }

  Future<void> _init() async {
    await _service.initialize();
    _statusSub = _service.statusStream.listen((status) {
      state = state.copyWith(status: status);
    });
  }

  RTCVideoRenderer get remoteRenderer => _service.remoteRenderer;
  Stream<String> get dataMessages => _service.dataMessages;

  Future<void> startViewing({
    required String sessionId,
    required String targetDeviceId,
  }) async {
    state = state.copyWith(
      isViewing: true,
      isStreaming: false,
      sessionId: sessionId,
      peerDeviceId: targetDeviceId,
      status: WebRTCConnectionStatus.connecting,
      error: null,
    );
    try {
      await _service.startViewerSession(
        sessionId: sessionId,
        targetDeviceId: targetDeviceId,
      );
    } catch (e) {
      state = state.copyWith(
        status: WebRTCConnectionStatus.failed,
        error: e.toString(),
      );
    }
  }

  Future<void> startStreaming({
    required String sessionId,
    required String controllerDeviceId,
  }) async {
    state = state.copyWith(
      isStreaming: true,
      isViewing: false,
      sessionId: sessionId,
      peerDeviceId: controllerDeviceId,
      status: WebRTCConnectionStatus.capturing,
      error: null,
    );
    try {
      await _service.startScreenShareSession(
        sessionId: sessionId,
        controllerDeviceId: controllerDeviceId,
      );
    } catch (e) {
      state = state.copyWith(
        status: WebRTCConnectionStatus.failed,
        error: e.toString(),
      );
    }
  }

  Future<void> handleSignalingEvent(Map<String, dynamic> event) async {
    final type = event['type'] as String? ?? '';
    final fromDeviceId = event['from_device_id'] as String? ?? '';

    if (type == 'webrtc_offer') {
      final sdp = event['sdp'] as String? ?? '';
      await _service.handleOffer(sdp, fromDeviceId);
    } else if (type == 'webrtc_answer') {
      final sdp = event['sdp'] as String? ?? '';
      await _service.handleAnswer(sdp);
    } else if (type == 'webrtc_ice_candidate') {
      final candidate = event['candidate'] as Map<String, dynamic>?;
      if (candidate != null) {
        await _service.handleIceCandidate(candidate);
      }
    }
  }

  void sendControlCommand(String cmd) {
    _service.sendDataMessage(cmd);
  }

  Future<void> stop() async {
    await _service.stop();
    state = const WebRTCState();
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _service.dispose();
    super.dispose();
  }
}

final webrtcProvider =
    StateNotifierProvider<WebRTCNotifier, WebRTCState>((ref) {
  final service = ref.read(webrtcServiceProvider);
  return WebRTCNotifier(service);
});
