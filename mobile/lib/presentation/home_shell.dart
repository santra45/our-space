import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../core/engine.dart';
import 'app_shell.dart';
import 'screens/people/people_setup.dart';
import 'screens/sync/peer_link.dart';
import 'screens/sync/sync_hub.dart';
import 'space_scope.dart';
import 'widgets/our_widgets.dart';

HeaderPresence headerPresenceFor(IdentityController identity, {int? now, bool together = false}) {
  if (together) return HeaderPresence.activeNow(partnerName: identity.partnerName);
  final seen = formatLastSeen(identity.partnerLastActive, now: now);
  if (seen == null) return const HeaderPresence.justForUs();
  return HeaderPresence.lastSeen(partnerName: identity.partnerName, lastSeen: seen);
}

SyncPillState syncPillFor(PeerLinkView link) {
  if (link.error != null) return SyncPillState.error;
  if (link.authorized) {
    switch (link.route) {
      case PeerRoute.direct:
        return SyncPillState.direct;
      case PeerRoute.relayed:
        return SyncPillState.relayed;
      case null:
        return SyncPillState.connected;
    }
  }
  if (link.handshaking) return SyncPillState.checking;
  if (link.connecting) return SyncPillState.pairing;
  return SyncPillState.idle;
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.pageBuilder, this.particles = true});

  final AppTabBuilder? pageBuilder;
  final bool particles;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const Duration _presenceTick = Duration(seconds: 30);

  Timer? _clock;
  int _now = DateTime.now().millisecondsSinceEpoch;
  AppNotices? _notices;
  PeerLink? _peer;
  bool _askingInvite = false;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(_presenceTick, (_) {
      if (mounted) setState(() => _now = DateTime.now().millisecondsSinceEpoch);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final notices = context.read<AppNotices>();
    if (!identical(notices, _notices)) {
      _notices?.removeListener(_onNotices);
      _notices = notices..addListener(_onNotices);
      _onNotices();
    }
    final peer = context.read<PeerLink?>();
    if (!identical(peer, _peer)) {
      _peer?.removeListener(_onPeer);
      _peer = peer?..addListener(_onPeer);
      _onPeer();
    }
  }

  void _onPeer() {
    if (_askingInvite || _peer?.state.pendingInvite == null) return;
    _askingInvite = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_askAboutInvite()));
  }

  Future<void> _askAboutInvite() async {
    final peer = _peer;
    final pending = peer?.state.pendingInvite;
    if (!mounted || peer == null || pending == null) {
      _askingInvite = false;
      return;
    }
    final yes = await showConnectDeviceDialog(context, peerId: pending.peerId, fromLink: pending.fromLink);
    _askingInvite = false;
    if (!mounted || peer.state.pendingInvite == null) return;
    if (yes) {
      peer.confirmInvite();
    } else {
      peer.declineInvite();
    }
  }

  void _onNotices() {
    if ((_notices?.pendingCelebrations ?? 0) <= 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if ((_notices?.takeCelebrations() ?? 0) <= 0) return;
      AppHaptics.celebration();
      fireCelebrationBurst(context);
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _notices?.removeListener(_onNotices);
    _peer?.removeListener(_onPeer);
    super.dispose();
  }

  void _openSync() => unawaited(showSyncHub(context));

  @override
  Widget build(BuildContext context) {
    final vault = context.watch<VaultService>();
    final identity = context.watch<IdentityController>();
    final notices = context.watch<AppNotices>();
    final peer = context.watch<PeerLink?>();
    final link = peer?.state ?? PeerLinkView.offline;

    return AppShell(
      header: OurHeader(
        title: vault.config?.coupleNames,
        presence: headerPresenceFor(identity, now: _now, together: link.authorized),
        syncState: syncPillFor(link),
        onOpenSync: _openSync,
        onLock: vault.lock,
        syncErrorText: link.error?.text,
        onDismissSyncError: peer?.clearError,
        syncWarningText: notices.syncWarning,
      ),
      pageBuilder: widget.pageBuilder ?? tabPage,
      toastController: notices.toast,
      onOpenSync: _openSync,
      onLock: vault.lock,
      particles: widget.particles,
      overlays: const [PeopleSetup()],
    );
  }
}
