import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/access_session_model.dart';
import '../../providers/access_provider.dart';

/// Full-screen or modal explicit consent prompt on Device B.
/// Shows countdown timer, requester details, permission toggles, and Accept/Deny buttons.
class ConsentDialog extends ConsumerStatefulWidget {
  final AccessSessionModel request;

  const ConsentDialog({super.key, required this.request});

  static Future<void> show(BuildContext context, AccessSessionModel request) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ConsentDialog(request: request),
    );
  }

  @override
  ConsumerState<ConsentDialog> createState() => _ConsentDialogState();
}

class _ConsentDialogState extends ConsumerState<ConsentDialog> {
  late int _remainingSeconds;
  Timer? _timer;
  late bool _allowControl;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _allowControl = widget.request.canControl;
    final diff = widget.request.expiresAt.difference(DateTime.now()).inSeconds;
    _remainingSeconds = diff > 0 ? diff : 60;

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_remainingSeconds <= 1) {
        timer.cancel();
        _onExpire();
      } else {
        setState(() => _remainingSeconds--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _onExpire() {
    ref.read(accessProvider.notifier).clearIncomingPrompt();
    Navigator.of(context, rootNavigator: true).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Access request expired.')),
    );
  }

  Future<void> _respond(bool accept) async {
    setState(() => _submitting = true);
    _timer?.cancel();

    try {
      await ref.read(accessProvider.notifier).respondAccess(
            sessionId: widget.request.id,
            accept: accept,
            allowControl: _allowControl,
          );
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              accept
                ? 'Remote access session started. You can stop it at any time.'
                : 'Access request declined.',
              style: GoogleFonts.inter(),
            ),
            backgroundColor: accept ? const Color(0xFF00E5CC) : const Color(0xFF161B22),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  String _formatDeviceId(String id) {
    if (id.length == 8) {
      return '${id.substring(0, 4)} ${id.substring(4)}';
    }
    return id;
  }

  @override
  Widget build(BuildContext context) {
    final progress = _remainingSeconds / 60.0;

    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: const Color(0xFF161B22),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(
            color: const Color(0xFFFFB347).withValues(alpha: 0.4),
            width: 1.5,
          ),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Header Icon & Alert ──────────────────────────────────────
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFB347).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.shield_outlined,
                  color: Color(0xFFFFB347),
                  size: 30,
                ),
              ),
              const SizedBox(height: 16),

              Text(
                'Remote Access Request',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),

              Text(
                'A paired device is asking to connect to this device.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: Colors.white70,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),

              // ── Requester ID card ─────────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1117),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      'REQUESTER DEVICE ID',
                      style: GoogleFonts.inter(
                        color: const Color(0xFF00E5CC),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _formatDeviceId(widget.request.requesterDeviceId),
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // ── Permissions requested ────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1117),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.visibility_rounded,
                          color: Color(0xFF00E5CC),
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'View Screen in Real-Time',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.check_circle_rounded,
                          color: Color(0xFF00E5CC),
                          size: 18,
                        ),
                      ],
                    ),
                    const Divider(color: Color(0xFF30363D), height: 20),
                    Row(
                      children: [
                        const Icon(
                          Icons.touch_app_rounded,
                          color: Color(0xFFFFB347),
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Remote Control (Gestures & Input)',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Switch(
                          value: _allowControl,
                          activeThumbColor: const Color(0xFF00E5CC),
                          activeTrackColor:
                              const Color(0xFF00E5CC).withValues(alpha: 0.5),
                          onChanged: (val) =>
                              setState(() => _allowControl = val),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // ── Countdown Timer Bar ──────────────────────────────────────
              Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Auto-expires in',
                        style: GoogleFonts.inter(
                          color: Colors.white38,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        '${_remainingSeconds}s',
                        style: GoogleFonts.inter(
                          color: const Color(0xFFFFB347),
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: progress.clamp(0.0, 1.0),
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                    valueColor: const AlwaysStoppedAnimation(Color(0xFFFFB347)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ── Action Buttons ───────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: OutlinedButton(
                        onPressed: _submitting ? null : () => _respond(false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          side: BorderSide(
                            color: Colors.redAccent.withValues(alpha: 0.5),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'DENY',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _submitting ? null : () => _respond(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00E5CC),
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _submitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.black,
                                ),
                              )
                            : Text(
                                'ALLOW',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2,
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
