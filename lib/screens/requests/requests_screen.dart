import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/access_session_model.dart';
import '../../providers/access_provider.dart';
import '../../providers/device_provider.dart';
import '../../widgets/active_session_bar.dart';
import '../access/consent_dialog.dart';

/// Requests & Sessions management tab.
class RequestsScreen extends ConsumerStatefulWidget {
  const RequestsScreen({super.key});

  @override
  ConsumerState<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends ConsumerState<RequestsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(accessProvider.notifier).loadAll();
    });
  }

  Future<void> _refresh() async {
    await ref.read(accessProvider.notifier).loadAll();
  }

  String _myDeviceId() {
    final ds = ref.read(deviceProvider);
    return ds is DeviceReady ? ds.deviceId : '';
  }

  @override
  Widget build(BuildContext context) {
    final accessState = ref.watch(accessProvider);
    final myDeviceId = _myDeviceId();

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: SafeArea(
        child: RefreshIndicator(
          color: const Color(0xFF00E5CC),
          backgroundColor: const Color(0xFF161B22),
          onRefresh: _refresh,
          child: CustomScrollView(
            slivers: [
              // ── App bar ──────────────────────────────────────────────────
              SliverAppBar(
                backgroundColor: const Color(0xFF0D1117),
                pinned: true,
                surfaceTintColor: Colors.transparent,
                title: Text(
                  'Access Requests & Sessions',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(
                      Icons.refresh_rounded,
                      color: Colors.white54,
                    ),
                    onPressed: _refresh,
                  ),
                ],
              ),

              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // ── Active Session Banner ────────────────────────────
                    if (accessState.activeSession != null) ...[
                      ActiveSessionBar(session: accessState.activeSession!),
                      const SizedBox(height: 24),
                    ],

                    if (accessState.loading && accessState.history.isEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: CircularProgressIndicator(
                            valueColor:
                                AlwaysStoppedAnimation(Color(0xFF00E5CC)),
                          ),
                        ),
                      )
                    else ...[
                      // ── Pending Inbound Requests ───────────────────────
                      if (accessState.pendingRequests.isNotEmpty) ...[
                        _SectionTitle(
                          'INCOMING ACCESS REQUESTS',
                          badge: accessState.pendingRequests.length,
                        ),
                        const SizedBox(height: 12),
                        ...accessState.pendingRequests.map(
                          (req) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _PendingAccessTile(
                              request: req,
                              onReview: () => ConsentDialog.show(context, req),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],

                      // ── Session History ────────────────────────────────
                      _SectionTitle('SESSION HISTORY (${accessState.history.length})'),
                      const SizedBox(height: 12),
                      if (accessState.history.isEmpty)
                        const _EmptyHistoryState()
                      else
                        ...accessState.history.map(
                          (s) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _SessionHistoryTile(
                              session: s,
                              myDeviceId: myDeviceId,
                            ),
                          ),
                        ),
                    ],
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final int? badge;
  const _SectionTitle(this.title, {this.badge});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: GoogleFonts.inter(
            color: Colors.white30,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
        if (badge != null && badge! > 0) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFFFB347).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$badge',
              style: GoogleFonts.inter(
                color: const Color(0xFFFFB347),
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _PendingAccessTile extends StatelessWidget {
  final AccessSessionModel request;
  final VoidCallback onReview;

  const _PendingAccessTile({
    required this.request,
    required this.onReview,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFFFB347).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFFFB347).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.screen_share_rounded,
              color: Color(0xFFFFB347),
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'From ${request.requesterDeviceId}',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  request.canControl ? 'Screen + Input Control' : 'View Only',
                  style: GoogleFonts.inter(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: onReview,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00E5CC),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              'Review',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionHistoryTile extends StatelessWidget {
  final AccessSessionModel session;
  final String myDeviceId;

  const _SessionHistoryTile({
    required this.session,
    required this.myDeviceId,
  });

  Color _statusColor(String status) {
    switch (status) {
      case 'active':
        return const Color(0xFF00E5CC);
      case 'ended':
        return Colors.white54;
      case 'rejected':
        return Colors.redAccent;
      case 'expired':
        return const Color(0xFFFFB347);
      default:
        return Colors.white38;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isController = session.isController(myDeviceId);
    final peerId = session.peerDeviceId(myDeviceId);
    final color = _statusColor(session.status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.05),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isController ? Icons.cast_rounded : Icons.phone_android_rounded,
            color: Colors.white38,
            size: 20,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${isController ? "Controlled" : "Session on"} $peerId',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  session.canControl ? 'Control Allowed' : 'View Only',
                  style: GoogleFonts.inter(
                    color: Colors.white38,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Text(
              session.status.toUpperCase(),
              style: GoogleFonts.inter(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyHistoryState extends StatelessWidget {
  const _EmptyHistoryState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Column(
        children: [
          const Icon(Icons.history_rounded, color: Colors.white12, size: 48),
          const SizedBox(height: 12),
          Text(
            'No access requests or session history yet.',
            style: GoogleFonts.inter(
              color: Colors.white30,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
