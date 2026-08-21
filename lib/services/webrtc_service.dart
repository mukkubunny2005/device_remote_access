import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'websocket_service.dart';

enum WebRTCConnectionStatus {
  idle,
  capturing,
  connecting,
  connected,
  disconnected,
  failed,
  closed,
}

/// WebRTC Service managing PeerConnection, MediaStream, DataChannel, and Signaling.
class WebRTCService {
  final WebSocketService _ws;

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  RTCDataChannel? _dataChannel;
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  String? _currentSessionId;
  String? _peerDeviceId;
  bool _isController = false;
  bool get isController => _isController;

  final _statusController =
      StreamController<WebRTCConnectionStatus>.broadcast();
  Stream<WebRTCConnectionStatus> get statusStream => _statusController.stream;
  WebRTCConnectionStatus currentStatus = WebRTCConnectionStatus.idle;

  // Stream of incoming data channel messages (e.g. touch gestures in Phase 5)
  final _dataMessageController = StreamController<String>.broadcast();
  Stream<String> get dataMessages => _dataMessageController.stream;

  WebRTCService({WebSocketService? ws}) : _ws = ws ?? WebSocketService();

  static final Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
      {'urls': 'stun:stun3.l.google.com:19302'},
      {'urls': 'stun:stun4.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };

  Future<void> initialize() async {
    await remoteRenderer.initialize();
  }

  void _updateStatus(WebRTCConnectionStatus status) {
    currentStatus = status;
    _statusController.add(status);
  }

  // ── Controller Mode (Device A: Viewer) ──────────────────────────────────────

  Future<void> startViewerSession({
    required String sessionId,
    required String targetDeviceId,
  }) async {
    _currentSessionId = sessionId;
    _peerDeviceId = targetDeviceId;
    _isController = true;
    _updateStatus(WebRTCConnectionStatus.connecting);

    await _createPeerConnection();

    // Create DataChannel for control / touch commands
    final dcInit = RTCDataChannelInit()
      ..ordered = true
      ..maxRetransmits = 30;
    _dataChannel = await _peerConnection!.createDataChannel('control', dcInit);
    _setupDataChannel(_dataChannel!);

    // Create offer
    final offer = await _peerConnection!.createOffer({
      'offerToReceiveVideo': 1,
      'offerToReceiveAudio': 0,
    });
    await _peerConnection!.setLocalDescription(offer);

    // Send offer through WebSocket
    _ws.send({
      'type': 'webrtc_offer',
      'session_id': sessionId,
      'target_device_id': targetDeviceId,
      'sdp': offer.sdp,
    });
  }

  // ── Remote Target Mode (Device B: Streamer) ────────────────────────────────

  Future<void> startScreenShareSession({
    required String sessionId,
    required String controllerDeviceId,
  }) async {
    _currentSessionId = sessionId;
    _peerDeviceId = controllerDeviceId;
    _isController = false;
    _updateStatus(WebRTCConnectionStatus.capturing);

    // 1. Capture screen using MediaDevices.getDisplayMedia (MediaProjection)
    try {
      final mediaConstraints = <String, dynamic>{
        'audio': false,
        'video': {
          'mandatory': {
            'minWidth': '720',
            'minHeight': '1280',
            'minFrameRate': '30',
          },
          'facingMode': 'user',
          'optional': [],
        }
      };

      _localStream = await navigator.mediaDevices.getDisplayMedia(mediaConstraints);
    } catch (e) {
      _updateStatus(WebRTCConnectionStatus.failed);
      rethrow;
    }

    _updateStatus(WebRTCConnectionStatus.connecting);
    await _createPeerConnection();

    // Add screen video track to peer connection
    for (final track in _localStream!.getVideoTracks()) {
      await _peerConnection!.addTrack(track, _localStream!);
    }
  }

  // ── PeerConnection Setup ───────────────────────────────────────────────────

  Future<void> _createPeerConnection() async {
    _peerConnection = await createPeerConnection(_iceServers);

    _peerConnection!.onIceCandidate = (candidate) {
      if (_currentSessionId != null && _peerDeviceId != null) {
        _ws.send({
          'type': 'webrtc_ice_candidate',
          'session_id': _currentSessionId,
          'target_device_id': _peerDeviceId,
          'candidate': {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          },
        });
      }
    };

    _peerConnection!.onTrack = (event) {
      if (event.track.kind == 'video') {
        remoteRenderer.srcObject = event.streams[0];
      }
    };

    _peerConnection!.onDataChannel = (channel) {
      _dataChannel = channel;
      _setupDataChannel(channel);
    };

    _peerConnection!.onConnectionState = (state) {
      switch (state) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          _updateStatus(WebRTCConnectionStatus.connected);
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
          _updateStatus(WebRTCConnectionStatus.connecting);
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          _updateStatus(WebRTCConnectionStatus.disconnected);
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          _updateStatus(WebRTCConnectionStatus.failed);
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
          _updateStatus(WebRTCConnectionStatus.closed);
          break;
        default:
          break;
      }
    };
  }

  void _setupDataChannel(RTCDataChannel dc) {
    dc.onMessage = (data) {
      if (data.isBinary) {
        // Handle binary data if needed
      } else {
        _dataMessageController.add(data.text);
      }
    };
  }

  // ── Signaling Handlers ──────────────────────────────────────────────────────

  Future<void> handleOffer(String sdp, String fromDeviceId) async {
    if (_peerConnection == null) {
      await _createPeerConnection();
    }
    _peerDeviceId = fromDeviceId;
    final desc = RTCSessionDescription(sdp, 'offer');
    await _peerConnection!.setRemoteDescription(desc);

    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);

    _ws.send({
      'type': 'webrtc_answer',
      'session_id': _currentSessionId,
      'target_device_id': fromDeviceId,
      'sdp': answer.sdp,
    });
  }

  Future<void> handleAnswer(String sdp) async {
    if (_peerConnection != null) {
      final desc = RTCSessionDescription(sdp, 'answer');
      await _peerConnection!.setRemoteDescription(desc);
    }
  }

  Future<void> handleIceCandidate(Map<String, dynamic> candidateMap) async {
    if (_peerConnection != null) {
      final candidate = RTCIceCandidate(
        candidateMap['candidate'] as String?,
        candidateMap['sdpMid'] as String?,
        candidateMap['sdpMLineIndex'] as int?,
      );
      await _peerConnection!.addCandidate(candidate);
    }
  }

  // ── Data Transmission ───────────────────────────────────────────────────────

  void sendDataMessage(String msg) {
    if (_dataChannel != null &&
        _dataChannel!.state == RTCDataChannelState.RTCDataChannelOpen) {
      _dataChannel!.send(RTCDataChannelMessage(msg));
    }
  }

  // ── Teardown ────────────────────────────────────────────────────────────────

  Future<void> stop() async {
    _updateStatus(WebRTCConnectionStatus.closed);
    await _localStream?.dispose();
    _localStream = null;

    await _dataChannel?.close();
    _dataChannel = null;

    await _peerConnection?.close();
    _peerConnection = null;

    remoteRenderer.srcObject = null;
    _currentSessionId = null;
    _peerDeviceId = null;
  }

  Future<void> dispose() async {
    await stop();
    await remoteRenderer.dispose();
    await _statusController.close();
    await _dataMessageController.close();
  }
}
