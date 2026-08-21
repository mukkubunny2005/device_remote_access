import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../providers/access_provider.dart';
import '../../providers/accessibility_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/device_provider.dart';
import '../../providers/pairing_provider.dart';
import '../../providers/webrtc_provider.dart';
import '../../providers/websocket_provider.dart';
import '../../widgets/active_session_bar.dart';
import '../../widgets/device_id_card.dart';
import '../../widgets/status_badge.dart';
import '../access/consent_dialog.dart';
import '../accessibility/accessibility_permission_screen.dart';
import '../auth/login_screen.dart';
import '../devices/paired_devices_screen.dart';
import '../requests/requests_screen.dart';

/// Home screen — Phase 3.
///
/// Shows the authenticated user's Device ID, online status, paired devices,
/// live incoming consent prompts, and active remote access sessions.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _currentTab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(deviceProvider.notifier).initialize();
    });
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Log out',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Are you sure you want to log out?',
          style: GoogleFonts.inter(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.inter(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Log out', style: GoogleFonts.inter(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref.read(webSocketProvider.notifier).disconnect();
      await ref.read(deviceProvider.notifier).markOffline();
      await ref.read(authProvider.notifier).logout();
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Connect WebSocket and load data as soon as device is ready
    ref.listen<DeviceState>(deviceProvider, (previous, next) {
      if (next is DeviceReady) {
        ref.read(webSocketProvider.notifier).connect(next.deviceId);
        ref.read(pairingProvider.notifier).loadAll();
        ref.read(accessProvider.notifier).loadAll();
      }
    });

    // Listen for real-time incoming access request prompts to trigger Consent Dialog
    ref.listen<AccessState>(accessProvider, (previous, next) {
      if (next.incomingPrompt != null &&
          previous?.incomingPrompt?.id != next.incomingPrompt?.id) {
        ConsentDialog.show(context, next.incomingPrompt!);
      }

      // If active session started and this device is the Target (Device B), initiate stream broadcast
      final active = next.activeSession;
      final ds = ref.read(deviceProvider);
      final myId = ds is DeviceReady ? ds.deviceId : '';
      if (active != null && !active.isController(myId)) {
        final webrtc = ref.read(webrtcProvider);
        if (!webrtc.isStreaming && webrtc.sessionId != active.id) {
          ref.read(webrtcProvider.notifier).startStreaming(
                sessionId: active.id,
                controllerDeviceId: active.requesterDeviceId,
              );
        }
        // Arm accessibility control service when session allows control
        if (active.canControl) {
          ref.read(accessibilityProvider.notifier).armForSession();
        }
      } else if (active == null && previous?.activeSession != null) {
        ref.read(webrtcProvider.notifier).stop();
        // Disarm accessibility control when session ends
        ref.read(accessibilityProvider.notifier).disarm();
      }
    });

    final deviceState = ref.watch(deviceProvider);
    final authState = ref.watch(authProvider);
    final pairingState = ref.watch(pairingProvider);
    final accessState = ref.watch(accessProvider);
    final a11yState = ref.watch(accessibilityProvider);

    final userEmail =
        authState is AuthAuthenticated ? authState.user.email : '';
    final pendingPairingCount = pairingState.pending.length;
    final pendingAccessCount = accessState.pendingRequests.length;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: IndexedStack(
        index: _currentTab,
        children: [
          _HomeTab(
            deviceState: deviceState,
            accessState: accessState,
            a11yState: a11yState,
            userEmail: userEmail,
            onLogout: _logout,
            onGoToDevices: () => setState(() => _currentTab = 1),
            onGoToRequests: () => setState(() => _currentTab = 2),
            onGoToAccessibility: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const AccessibilityPermissionScreen(),
              )).then((_) {
                ref.read(accessibilityProvider.notifier).refresh();
              });
            },
          ),
          const PairedDevicesScreen(),
          const RequestsScreen(),
          const _ComingSoonTab(
            label: 'Settings',
            icon: Icons.settings_outlined,
          ),
        ],
      ),
      bottomNavigationBar: _buildNavBar(pendingPairingCount, pendingAccessCount),
    );
  }

  Widget _buildNavBar(int pendingPairing, int pendingAccess) {
    const activeColor = Color(0xFF00E5CC);
    const inactiveColor = Color(0xFF6B7280);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: NavigationBar(
        backgroundColor: Colors.transparent,
        indicatorColor: activeColor.withValues(alpha: 0.12),
        selectedIndex: _currentTab,
        onDestinationSelected: (i) => setState(() => _currentTab = i),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined, color: inactiveColor),
            selectedIcon: Icon(Icons.home_rounded, color: activeColor),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: pendingPairing > 0,
              label: Text('$pendingPairing'),
              backgroundColor: const Color(0xFFFFB347),
              textColor: Colors.black,
              child: const Icon(
                Icons.devices_other_outlined,
                color: inactiveColor,
              ),
            ),
            selectedIcon: Badge(
              isLabelVisible: pendingPairing > 0,
              label: Text('$pendingPairing'),
              backgroundColor: const Color(0xFFFFB347),
              textColor: Colors.black,
              child: const Icon(
                Icons.devices_other_rounded,
                color: activeColor,
              ),
            ),
            label: 'Devices',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: pendingAccess > 0,
              label: Text('$pendingAccess'),
              backgroundColor: const Color(0xFFFFB347),
              textColor: Colors.black,
              child: const Icon(
                Icons.swap_horiz_outlined,
                color: inactiveColor,
              ),
            ),
            selectedIcon: Badge(
              isLabelVisible: pendingAccess > 0,
              label: Text('$pendingAccess'),
              backgroundColor: const Color(0xFFFFB347),
              textColor: Colors.black,
              child: const Icon(
                Icons.swap_horiz_rounded,
                color: activeColor,
              ),
            ),
            label: 'Requests',
          ),
          const NavigationDestination(
            icon: Icon(Icons.settings_outlined, color: inactiveColor),
            selectedIcon: Icon(Icons.settings_rounded, color: activeColor),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

// ── Home tab ───────────────────────────────────────────────────────────────────

class _HomeTab extends StatelessWidget {
  final DeviceState deviceState;
  final AccessState accessState;
  final String userEmail;
  final VoidCallback onLogout;
  final VoidCallback onGoToDevices;
  final VoidCallback onGoToRequests;
  final AccessibilityState a11yState;
  final VoidCallback onGoToAccessibility;

  const _HomeTab({
    required this.deviceState,
    required this.accessState,
    required this.a11yState,
    required this.userEmail,
    required this.onLogout,
    required this.onGoToDevices,
    required this.onGoToRequests,
    required this.onGoToAccessibility,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          // ── App bar ──────────────────────────────────────────────────────
          SliverAppBar(
            backgroundColor: const Color(0xFF0D1117),
            surfaceTintColor: Colors.transparent,
            pinned: true,
            title: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [Color(0xFF00E5CC), Color(0xFF006EDB)],
                    ),
                  ),
                  child: const Icon(
                    Icons.screen_share_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Remote Access',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(
                  Icons.logout_rounded,
                  color: Colors.white54,
                  size: 22,
                ),
                onPressed: onLogout,
                tooltip: 'Log out',
              ),
              const SizedBox(width: 4),
            ],
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // ── Active Session Banner (if active) ─────────────────────
                if (accessState.activeSession != null) ...[
                  ActiveSessionBar(session: accessState.activeSession!),
                  const SizedBox(height: 20),
                ],

                // ── Greeting ────────────────────────────────────────────
                if (userEmail.isNotEmpty) ...[
                  Text(
                    'Hello 👋',
                    style: GoogleFonts.inter(
                      color: Colors.white54,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    userEmail,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 24),
                ],

                // ── Device ID card ───────────────────────────────────────
                switch (deviceState) {
                  DeviceLoading() => _loadingCard(),
                  DeviceReady(:final deviceId, :final registeredDevice) =>
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DeviceIdCard(deviceId: deviceId),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            StatusBadge(
                              online: registeredDevice?.online ?? false,
                            ),
                          ],
                        ),
                      ],
                    ),
                  DeviceError(:final message) => _errorCard(message),
                },

                const SizedBox(height: 36),

                // ── Feature tiles ────────────────────────────────────────
                Text(
                  'QUICK ACTIONS',
                  style: GoogleFonts.inter(
                    color: Colors.white30,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 12),
                _FeatureTile(
                  icon: Icons.link_rounded,
                  label: 'Paired Devices',
                  subtitle: 'View paired devices and connect',
                  enabled: true,
                  onTap: onGoToDevices,
                ),
                const SizedBox(height: 10),
                _FeatureTile(
                  icon: Icons.swap_horiz_rounded,
                  label: 'Access Requests & Sessions',
                  subtitle: 'Review incoming requests & active session',
                  enabled: true,
                  badge: accessState.pendingRequests.isNotEmpty
                      ? accessState.pendingRequests.length
                      : null,
                  onTap: onGoToRequests,
                ),
                const SizedBox(height: 24),

                Text(
                  'PHASE 5 — REMOTE CONTROL',
                  style: GoogleFonts.inter(
                    color: Colors.white30,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 12),
                _AccessibilityTile(
                  a11yState: a11yState,
                  onTap: onGoToAccessibility,
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _loadingCard() => Container(
        height: 220,
        decoration: BoxDecoration(
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation(Color(0xFF00E5CC)),
          ),
        ),
      );

  Widget _errorCard(String msg) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.redAccent.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                msg,
                style: GoogleFonts.inter(
                  color: Colors.redAccent,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      );
}

class _FeatureTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool enabled;
  final int? badge;
  final VoidCallback? onTap;

  const _FeatureTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.enabled,
    this.badge,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: enabled
                ? const Color(0xFF00E5CC).withValues(alpha: 0.25)
                : Colors.white.withValues(alpha: 0.05),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: enabled
                    ? const Color(0xFF00E5CC).withValues(alpha: 0.15)
                    : Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: enabled ? const Color(0xFF00E5CC) : Colors.white30,
                size: 20,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        label,
                        style: GoogleFonts.inter(
                          color: enabled ? Colors.white : Colors.white60,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (badge != null && badge! > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFB347),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$badge',
                            style: GoogleFonts.inter(
                              color: Colors.black,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      color: Colors.white38,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              enabled ? Icons.chevron_right_rounded : Icons.lock_outline,
              color: enabled ? const Color(0xFF00E5CC) : const Color(0x33FFFFFF),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Placeholder tab ───────────────────────────────────────────────────────────

class _ComingSoonTab extends StatelessWidget {
  final String label;
  final IconData icon;

  const _ComingSoonTab({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white24, size: 56),
          const SizedBox(height: 16),
          Text(
            label,
            style: GoogleFonts.inter(
              color: Colors.white54,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Available in a future phase',
            style: GoogleFonts.inter(color: Colors.white30, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ── Accessibility Tile ─────────────────────────────────────────────────────────

class _AccessibilityTile extends StatelessWidget {
  final AccessibilityState a11yState;
  final VoidCallback onTap;

  const _AccessibilityTile({required this.a11yState, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isEnabled = a11yState.isEnabled;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isEnabled
                ? const Color(0xFF00E5CC).withValues(alpha: 0.4)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isEnabled
                    ? const Color(0xFF00E5CC).withValues(alpha: 0.15)
                    : Colors.white.withValues(alpha: 0.05),
              ),
              child: Icon(
                Icons.touch_app_rounded,
                color: isEnabled
                    ? const Color(0xFF00E5CC)
                    : Colors.white30,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Remote Control',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    isEnabled
                        ? 'Accessibility Service enabled — control ready'
                        : 'Tap to enable Accessibility Service',
                    style: GoogleFonts.inter(
                      color: isEnabled
                          ? const Color(0xFF00E5CC)
                          : Colors.white38,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              isEnabled ? Icons.check_circle_rounded : Icons.chevron_right_rounded,
              color: isEnabled ? const Color(0xFF00E5CC) : Colors.white24,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
