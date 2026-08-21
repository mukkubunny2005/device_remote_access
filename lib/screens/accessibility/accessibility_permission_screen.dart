import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../providers/accessibility_provider.dart';

/// Onboarding screen shown to Device B (Target) users explaining the
/// Accessibility Service requirement for remote control.
///
/// PRIVACY: Clearly explains what the service can and cannot do.
/// The user must manually enable it in Android Settings — no bypass.
class AccessibilityPermissionScreen extends ConsumerStatefulWidget {
  const AccessibilityPermissionScreen({super.key});

  @override
  ConsumerState<AccessibilityPermissionScreen> createState() =>
      _AccessibilityPermissionScreenState();
}

class _AccessibilityPermissionScreenState
    extends ConsumerState<AccessibilityPermissionScreen>
    with WidgetsBindingObserver {

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Initial status check
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(accessibilityProvider.notifier).refresh();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check status when app is resumed (user might have just enabled it)
    if (state == AppLifecycleState.resumed) {
      ref.read(accessibilityProvider.notifier).refresh();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a11yState = ref.watch(accessibilityProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1117),
        foregroundColor: Colors.white,
        title: Text(
          'Accessibility Permission',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header Illustration ───────────────────────────────────────
              Center(
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF1C2128),
                    border: Border.all(
                      color: const Color(0xFF00E5CC).withValues(alpha: 0.4),
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.accessibility_new_rounded,
                    color: Color(0xFF00E5CC),
                    size: 48,
                  ),
                ),
              ),

              const SizedBox(height: 28),

              // ── Title ─────────────────────────────────────────────────────
              Text(
                'Remote Control Permission',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 12),

              Text(
                'To allow remote device control, this app needs Android\'s '
                'Accessibility Service to inject gestures on your behalf. '
                'This is only active when you explicitly accept a remote session.',
                style: GoogleFonts.inter(
                  color: Colors.white70,
                  fontSize: 14,
                  height: 1.6,
                ),
              ),

              const SizedBox(height: 28),

              // ── What it CAN do ────────────────────────────────────────────
              const _SectionCard(
                title: 'What Remote Access CAN do',
                iconColor: Color(0xFF00E5CC),
                icon: Icons.check_circle_outline_rounded,
                items: [
                  'Inject tap and swipe gestures when a session is active',
                  'Press Back, Home, and Recents buttons',
                  'Accept and reject control per-session',
                ],
              ),

              const SizedBox(height: 16),

              // ── What it CANNOT do ─────────────────────────────────────────
              const _SectionCard(
                title: 'What Remote Access CANNOT do',
                iconColor: Colors.redAccent,
                icon: Icons.remove_circle_outline_rounded,
                items: [
                  'Access your screen content, notifications, or data',
                  'Operate silently without an active approved session',
                  'Enable itself without your consent in Android Settings',
                ],
              ),

              const SizedBox(height: 32),

              // ── Status Banner ─────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: a11yState.isEnabled
                      ? const Color(0xFF00E5CC).withValues(alpha: 0.1)
                      : Colors.redAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: a11yState.isEnabled
                        ? const Color(0xFF00E5CC).withValues(alpha: 0.4)
                        : Colors.redAccent.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      a11yState.isEnabled
                          ? Icons.check_circle_rounded
                          : Icons.warning_rounded,
                      color: a11yState.isEnabled
                          ? const Color(0xFF00E5CC)
                          : Colors.redAccent,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        a11yState.isEnabled
                            ? 'Accessibility Service is enabled. Remote control is ready.'
                            : 'Accessibility Service is not enabled. Tap below to open Settings.',
                        style: GoogleFonts.inter(
                          color: a11yState.isEnabled
                              ? const Color(0xFF00E5CC)
                              : Colors.redAccent,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ── Primary Action Button ─────────────────────────────────────
              if (!a11yState.isEnabled)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () =>
                        ref.read(accessibilityProvider.notifier).openSettings(),
                    icon: const Icon(Icons.settings_accessibility_rounded,
                        color: Colors.black),
                    label: Text(
                      'Open Accessibility Settings',
                      style: GoogleFonts.inter(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00E5CC),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),

              if (a11yState.isEnabled)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_ios_rounded,
                        color: Colors.black, size: 18),
                    label: Text(
                      'Go Back',
                      style: GoogleFonts.inter(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00E5CC),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),

              const SizedBox(height: 16),

              Center(
                child: TextButton(
                  onPressed: () =>
                      ref.read(accessibilityProvider.notifier).refresh(),
                  child: Text(
                    'Check again',
                    style: GoogleFonts.inter(
                      color: Colors.white38,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Section Card Widget ────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final List<String> items;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C2128),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: iconColor.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item,
                      style: GoogleFonts.inter(
                        color: Colors.white60,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
