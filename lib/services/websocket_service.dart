import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;

import '../config/app_config.dart';
import 'storage_service.dart';

/// WebSocket service — maintains a single authenticated WS connection per device.
///
/// Phase 2: Receives pairing events (pairing_request, pairing_response, pairing_revoked).
/// Phase 3: Will be extended for access-request and signaling events.
class WebSocketService {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;

  // Broadcast stream of decoded JSON messages
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  bool _intentionalClose = false;
  String? _deviceId;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;

  // ── Connect ─────────────────────────────────────────────────────────────────

  Future<void> connect(String deviceId) async {
    _deviceId = deviceId;
    _intentionalClose = false;
    _reconnectAttempts = 0;
    await _connect();
  }

  Future<void> _connect() async {
    final token = await StorageService.getAccessToken();
    if (token == null) return;

    final baseWs = AppConfig.baseUrl
        .replaceFirst('http://', 'ws://')
        .replaceFirst('https://', 'wss://');
    final uri = Uri.parse('$baseWs/ws/device/$_deviceId?token=$token');

    try {
      _channel = WebSocketChannel.connect(uri);
      await _channel!.ready;

      _subscription = _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: false,
      );

      _reconnectAttempts = 0;
      _startHeartbeat();
    } catch (e) {
      _scheduleReconnect();
    }
  }

  // ── Message handling ────────────────────────────────────────────────────────

  void _onMessage(dynamic raw) {
    try {
      final msg = jsonDecode(raw as String) as Map<String, dynamic>;
      final type = msg['type'] as String? ?? '';

      if (type == 'ping') {
        send({'type': 'pong'});
        return;
      }
      if (type == 'heartbeat_ack') return;

      // Forward all other messages to listeners
      _messageController.add(msg);
    } catch (_) {}
  }

  void _onError(Object error) {
    if (!_intentionalClose) _scheduleReconnect();
  }

  void _onDone() {
    _stopHeartbeat();
    if (!_intentionalClose) _scheduleReconnect();
  }

  // ── Heartbeat ────────────────────────────────────────────────────────────────

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(AppConfig.wsHeartbeatInterval, (_) {
      send({'type': 'heartbeat'});
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  // ── Reconnect ─────────────────────────────────────────────────────────────────

  void _scheduleReconnect() {
    if (_intentionalClose) return;
    if (_reconnectAttempts >= _maxReconnectAttempts) return;

    _reconnectAttempts++;
    final delay = Duration(seconds: _reconnectAttempts * 3); // back-off
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, _connect);
  }

  // ── Send ──────────────────────────────────────────────────────────────────────

  void send(Map<String, dynamic> msg) {
    try {
      _channel?.sink.add(jsonEncode(msg));
    } catch (_) {}
  }

  // ── Disconnect ────────────────────────────────────────────────────────────────

  Future<void> disconnect() async {
    _intentionalClose = true;
    _stopHeartbeat();
    _reconnectTimer?.cancel();
    await _subscription?.cancel();
    await _channel?.sink.close(ws_status.normalClosure);
    _channel = null;
  }

  void dispose() {
    disconnect();
    _messageController.close();
  }

  bool get isConnected => _channel != null;
}
