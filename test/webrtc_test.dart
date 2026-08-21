import 'package:flutter_test/flutter_test.dart';
import 'package:remote_access/services/webrtc_service.dart';
import 'package:remote_access/providers/webrtc_provider.dart';

void main() {
  group('WebRTCState & Enum tests', () {
    test('Initial WebRTCState defaults to idle and not streaming/viewing', () {
      const state = WebRTCState();

      expect(state.status, equals(WebRTCConnectionStatus.idle));
      expect(state.isStreaming, isFalse);
      expect(state.isViewing, isFalse);
      expect(state.isConnected, isFalse);
      expect(state.isConnecting, isFalse);
      expect(state.sessionId, isNull);
      expect(state.peerDeviceId, isNull);
    });

    test('WebRTCState copyWith correctly updates state flags', () {
      const state = WebRTCState();
      final updated = state.copyWith(
        status: WebRTCConnectionStatus.connected,
        isViewing: true,
        sessionId: 'session-123',
        peerDeviceId: '22223333',
      );

      expect(updated.status, equals(WebRTCConnectionStatus.connected));
      expect(updated.isConnected, isTrue);
      expect(updated.isViewing, isTrue);
      expect(updated.sessionId, equals('session-123'));
      expect(updated.peerDeviceId, equals('22223333'));
    });

    test('isConnecting is true during connecting or capturing', () {
      const connectingState = WebRTCState(status: WebRTCConnectionStatus.connecting);
      expect(connectingState.isConnecting, isTrue);
      expect(connectingState.isConnected, isFalse);

      const capturingState = WebRTCState(status: WebRTCConnectionStatus.capturing);
      expect(capturingState.isConnecting, isTrue);
    });
  });
}
