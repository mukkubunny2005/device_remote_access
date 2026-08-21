import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/access_session_model.dart';
import '../../providers/access_provider.dart';
import '../../providers/webrtc_provider.dart';
import '../../services/webrtc_service.dart';

/// Full-screen remote screen viewer for Controller Device.
class RemoteViewScreen extends ConsumerStatefulWidget {
  final AccessSessionModel session;

  const RemoteViewScreen({super.key, required this.session});

  static Future<void> open(BuildContext context, AccessSessionModel session) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RemoteViewScreen(session: session),
      ),
    );
  }

  @override
  ConsumerState<RemoteViewScreen> createState() => _RemoteViewScreenState();
}

class _RemoteViewScreenState extends ConsumerState<RemoteViewScreen> {
  bool _showControls = true;
  bool _controlEnabled = false;
  Offset? _panStart; // track pan start for swipe dispatch

  @override
  void initState() {
    super.initState();
    _controlEnabled = widget.session.canControl;

    // Lock to landscape or allow rotation for best remote view experience
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    // Start WebRTC viewer negotiation
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(webrtcProvider.notifier).startViewing(
            sessionId: widget.session.id,
            targetDeviceId: widget.session.targetDeviceId,
          );
    });
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    super.dispose();
  }

  void _onTapDown(TapDownDetails details, BoxConstraints constraints) {
    if (!_controlEnabled) return;
    final normalizedX =
        (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
    final normalizedY =
        (details.localPosition.dy / constraints.maxHeight).clamp(0.0, 1.0);

    ref.read(webrtcProvider.notifier).sendControlCommand(
          '{"action":"tap","x":$normalizedX,"y":$normalizedY}',
        );
  }

  void _onPanStart(DragStartDetails details, BoxConstraints constraints) {
    if (!_controlEnabled) return;
    final nx = (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
    final ny =
        (details.localPosition.dy / constraints.maxHeight).clamp(0.0, 1.0);
    _panStart = Offset(nx, ny);
  }

  void _onPanEnd(DragEndDetails details, BoxConstraints constraints) {
    if (!_controlEnabled || _panStart == null) return;
    // Use the velocity to estimate end point from start
    final vx = details.velocity.pixelsPerSecond.dx;
    final vy = details.velocity.pixelsPerSecond.dy;
    // Normalise a fraction of that velocity as a displacement
    final toX = (_panStart!.dx + vx / constraints.maxWidth * 0.15)
        .clamp(0.0, 1.0);
    final toY = (_panStart!.dy + vy / constraints.maxHeight * 0.15)
        .clamp(0.0, 1.0);

    ref.read(webrtcProvider.notifier).sendControlCommand(
          '{"action":"swipe",'
          '"fromX":${_panStart!.dx},"fromY":${_panStart!.dy},'
          '"toX":$toX,"toY":$toY,"durationMs":300}',
        );
    _panStart = null;
  }

  void _sendNavCommand(String action) {
    if (!_controlEnabled) return;
    ref.read(webrtcProvider.notifier).sendControlCommand('{"action":"$action"}');
  }

  Future<void> _endSession() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'End Remote Session?',
          style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'This will stop viewing and terminate the connection.',
          style: GoogleFonts.inter(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.inter(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('End Session', style: GoogleFonts.inter(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref.read(webrtcProvider.notifier).stop();
      await ref.read(accessProvider.notifier).endSession(widget.session.id);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final webrtcState = ref.watch(webrtcProvider);
    final renderer = ref.read(webrtcProvider.notifier).remoteRenderer;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // ── Video Stream & Gesture Surface ─────────────────────────────
            LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  onTap: () => setState(() => _showControls = !_showControls),
                  onTapDown: (details) => _onTapDown(details, constraints),
                  onPanStart: (details) => _onPanStart(details, constraints),
                  onPanEnd: (details) => _onPanEnd(details, constraints),
                  child: Container(
                    width: double.infinity,
                    height: double.infinity,
                    color: Colors.black,
                    child: webrtcState.isConnected
                        ? RTCVideoView(
                            renderer,
                            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                          )
                        : _buildConnectingPlaceholder(webrtcState),
                  ),
                );
              },
            ),

            // ── Top Header Controls Overlay ────────────────────────────────
            if (_showControls)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.black.withValues(alpha: 0.85),
                        Colors.transparent,
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Device ${widget.session.targetDeviceId}',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: webrtcState.isConnected ? const Color(0xFF00E5CC) : const Color(0xFFFFB347),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                webrtcState.isConnected
                                    ? (_controlEnabled ? 'Live • Control Active' : 'Live • View Only')
                                    : 'Connecting WebRTC…',
                                style: GoogleFonts.inter(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const Spacer(),

                      // STOP Button
                      ElevatedButton.icon(
                        onPressed: _endSession,
                        icon: const Icon(Icons.stop_rounded, color: Colors.white, size: 16),
                        label: Text(
                          'STOP',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent.withValues(alpha: 0.85),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // ── Bottom System Navigation Bar (Control mode only) ───────────
            if (_showControls && _controlEnabled)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.85),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _NavButton(
                        icon: Icons.arrow_back_rounded,
                        label: 'Back',
                        onTap: () => _sendNavCommand('back'),
                      ),
                      _NavButton(
                        icon: Icons.circle_outlined,
                        label: 'Home',
                        onTap: () => _sendNavCommand('home'),
                      ),
                      _NavButton(
                        icon: Icons.square_rounded,
                        label: 'Recents',
                        onTap: () => _sendNavCommand('recents'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectingPlaceholder(WebRTCState state) {
    if (state.status == WebRTCConnectionStatus.failed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
              const SizedBox(height: 16),
              Text(
                'WebRTC Connection Failed',
                style: GoogleFonts.inter(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                state.error ?? 'Failed to establish peer stream with target device.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(color: Colors.white60, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation(Color(0xFF00E5CC)),
          ),
          const SizedBox(height: 20),
          Text(
            'Negotiating Peer Stream…',
            style: GoogleFonts.inter(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            'Establishing low-latency WebRTC channel',
            style: GoogleFonts.inter(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ── Nav Button Widget ─────────────────────────────────────────────────────────

class _NavButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _NavButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.3),
              ),
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
