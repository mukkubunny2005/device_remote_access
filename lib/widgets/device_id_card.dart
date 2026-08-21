import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Premium glassmorphism card displaying the 8-digit Device ID.
class DeviceIdCard extends StatefulWidget {
  final String deviceId;

  const DeviceIdCard({super.key, required this.deviceId});

  @override
  State<DeviceIdCard> createState() => _DeviceIdCardState();
}

class _DeviceIdCardState extends State<DeviceIdCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _copyId() async {
    await _controller.forward();
    await _controller.reverse();
    await Clipboard.setData(ClipboardData(text: widget.deviceId));
    setState(() => _copied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  /// Format 8 digits as "XXXX XXXX" for readability.
  String get _formatted {
    final d = widget.deviceId;
    if (d.length == 8) return '${d.substring(0, 4)} ${d.substring(4)}';
    return d;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scaleAnim,
      builder: (context, child) => Transform.scale(
        scale: _scaleAnim.value,
        child: child,
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            colors: [
              const Color(0xFF161B22),
              const Color(0xFF0D1117).withValues(alpha: 0.9),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
            color: const Color(0xFF00E5CC).withValues(alpha: 0.25),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00E5CC).withValues(alpha: 0.08),
              blurRadius: 32,
              spreadRadius: 0,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Label
            Text(
              'YOUR DEVICE ID',
              style: GoogleFonts.inter(
                color: const Color(0xFF00E5CC),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 2.5,
              ),
            ),
            const SizedBox(height: 20),

            // 8-digit ID — large display
            Text(
              _formatted,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 42,
                fontWeight: FontWeight.w800,
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Share this ID to allow pairing',
              style: GoogleFonts.inter(
                color: Colors.white38,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 28),

            // Copy button
            SizedBox(
              width: double.infinity,
              height: 46,
              child: OutlinedButton.icon(
                onPressed: _copyId,
                icon: Icon(
                  _copied ? Icons.check_circle_outline : Icons.copy_outlined,
                  size: 18,
                  color: _copied ? Colors.greenAccent : const Color(0xFF00E5CC),
                ),
                label: Text(
                  _copied ? 'Copied!' : 'COPY ID',
                  style: GoogleFonts.inter(
                    color: _copied ? Colors.greenAccent : const Color(0xFF00E5CC),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: _copied
                        ? Colors.greenAccent.withValues(alpha: 0.5)
                        : const Color(0xFF00E5CC).withValues(alpha: 0.4),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
