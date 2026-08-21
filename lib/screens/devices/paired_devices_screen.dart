import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/pairing_model.dart';
import '../../providers/device_provider.dart';
import '../../providers/pairing_provider.dart';
import '../../services/api_service.dart';
import '../access/request_access_sheet.dart';
import '../pairing/send_pairing_screen.dart';

/// Paired Devices tab — shows accepted pairings, pending incoming requests,
/// and an action to pair a new device.
class PairedDevicesScreen extends ConsumerStatefulWidget {
  const PairedDevicesScreen({super.key});

  @override
  ConsumerState<PairedDevicesScreen> createState() =>
      _PairedDevicesScreenState();
}

class _PairedDevicesScreenState extends ConsumerState<PairedDevicesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(pairingProvider.notifier).loadAll();
    });
  }

  String _myDeviceId() {
    final ds = ref.read(deviceProvider);
    return ds is DeviceReady ? ds.deviceId : '';
  }

  Future<void> _refresh() async {
    await ref.read(pairingProvider.notifier).loadAll();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pairingProvider);

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
                  'Devices',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded,
                        color: Colors.white54),
                    onPressed: _refresh,
                  ),
                ],
              ),

              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // ── Pair new device button ───────────────────────────
                    _PairNewButton(
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const SendPairingScreen()),
                        );
                        await _refresh();
                      },
                    ),
                    const SizedBox(height: 28),

                    if (state.loading)
                      const Center(
                        child: CircularProgressIndicator(
                          valueColor:
                              AlwaysStoppedAnimation(Color(0xFF00E5CC)),
                        ),
                      )
                    else ...[
                      // ── Pending incoming requests ────────────────────
                      if (state.pending.isNotEmpty) ...[
                        _SectionHeader(
                          'PENDING REQUESTS',
                          badge: state.pending.length,
                        ),
                        const SizedBox(height: 12),
                        ...state.pending.map(
                          (p) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _PendingRequestTile(
                              pairing: p,
                              myDeviceId: _myDeviceId(),
                              onAccept: () => _respond(p.id, accept: true),
                              onReject: () => _respond(p.id, accept: false),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // ── Accepted pairings ────────────────────────────
                      _SectionHeader('PAIRED (${state.paired.length})'),
                      const SizedBox(height: 12),
                      if (state.paired.isEmpty)
                        const _EmptyState(
                          icon: Icons.devices_other_outlined,
                          message: 'No paired devices yet.\nTap "+ Pair Device" to get started.',
                        )
                      else
                        ...state.paired.map(
                          (p) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _PairedDeviceTile(
                              pairing: p,
                              myDeviceId: _myDeviceId(),
                              onConnect: () => RequestAccessSheet.show(
                                context,
                                pairing: p,
                                myDeviceId: _myDeviceId(),
                              ),
                              onRevoke: () => _revoke(p.id),
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

  Future<void> _respond(String pairingId, {required bool accept}) async {
    try {
      if (accept) {
        await ref.read(pairingProvider.notifier).acceptRequest(pairingId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Pairing accepted ✓', style: GoogleFonts.inter()),
              backgroundColor:
                  const Color(0xFF00E5CC).withValues(alpha: 0.9),
            ),
          );
        }
      } else {
        await ref.read(pairingProvider.notifier).rejectRequest(pairingId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text('Pairing request rejected.', style: GoogleFonts.inter()),
              backgroundColor: const Color(0xFF161B22),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiService.friendlyError(e))),
        );
      }
    }
  }

  Future<void> _revoke(String pairingId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Remove Pairing',
            style: GoogleFonts.inter(
                color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'Are you sure you want to remove this pairing? '
          'The other device will be notified.',
          style: GoogleFonts.inter(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: GoogleFonts.inter(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Remove',
                style: GoogleFonts.inter(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(pairingProvider.notifier).revokePairing(pairingId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pairing removed.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(ApiService.friendlyError(e))));
      }
    }
  }
}

// ── Sub-widgets ────────────────────────────────────────────────────────────────

class _PairNewButton extends StatelessWidget {
  final VoidCallback onTap;
  const _PairNewButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF00E5CC).withValues(alpha: 0.12),
              const Color(0xFF006EDB).withValues(alpha: 0.08),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: const Color(0xFF00E5CC).withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF00E5CC).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.add_rounded,
                  color: Color(0xFF00E5CC), size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pair a Device',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Enter the 8-digit ID of the other device',
                    style: GoogleFonts.inter(
                        color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded,
                color: Colors.white30, size: 16),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int? badge;
  const _SectionHeader(this.title, {this.badge});

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
            padding:
                const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF00E5CC).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$badge',
              style: GoogleFonts.inter(
                  color: const Color(0xFF00E5CC),
                  fontSize: 11,
                  fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ],
    );
  }
}

class _PendingRequestTile extends StatelessWidget {
  final PairingModel pairing;
  final String myDeviceId;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const _PendingRequestTile({
    required this.pairing,
    required this.myDeviceId,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final peer = pairing.peerDeviceId(myDeviceId);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: const Color(0xFFFFB347).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFB347).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.link_rounded,
                    color: Color(0xFFFFB347), size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pairing request from',
                      style: GoogleFonts.inter(
                          color: Colors.white54, fontSize: 12),
                    ),
                    Text(
                      peer,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onReject,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: BorderSide(
                        color: Colors.redAccent.withValues(alpha: 0.4)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text('Decline',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: onAccept,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E5CC),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text('Accept',
                      style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PairedDeviceTile extends StatelessWidget {
  final PairingModel pairing;
  final String myDeviceId;
  final VoidCallback onConnect;
  final VoidCallback onRevoke;

  const _PairedDeviceTile({
    required this.pairing,
    required this.myDeviceId,
    required this.onConnect,
    required this.onRevoke,
  });

  @override
  Widget build(BuildContext context) {
    final peer = pairing.peerDeviceId(myDeviceId);
    final isRequester = pairing.requesterDeviceId == myDeviceId;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF00E5CC).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.smartphone_rounded,
                color: Color(0xFF00E5CC), size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  peer,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isRequester ? 'You initiated' : 'They initiated',
                  style: GoogleFonts.inter(
                      color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: onConnect,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00E5CC),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              'Connect',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            icon: const Icon(Icons.link_off_rounded,
                color: Colors.redAccent, size: 20),
            onPressed: onRevoke,
            tooltip: 'Remove pairing',
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Icon(icon, color: Colors.white12, size: 52),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
                color: Colors.white38, fontSize: 14, height: 1.6),
          ),
        ],
      ),
    );
  }
}
