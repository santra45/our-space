import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../core/engine.dart';
import 'app_shell.dart';
import 'screens/love/love_sheet.dart';
import 'screens/people/people_setup.dart';
import 'screens/sync/peer_link.dart';
import 'sky/sky.dart';
import 'space_scope.dart';
import 'widgets/app_haptics.dart';
import 'widgets/confetti_burst.dart';

PartnerPresence partnerPresenceFor(IdentityController identity, {int? now, bool together = false}) {
  final name = identity.partner == null ? null : identity.partnerName;
  if (together) return PartnerPresence.here(partnerName: name);
  final seen = formatLastSeen(identity.partnerLastActive, now: now);
  if (seen == null) return PartnerPresence.unknown(partnerName: name);
  return PartnerPresence.seen(partnerName: name, lastSeen: seen);
}

abstract final class JoinRequestCopy {
  static const String title = 'Connect with this phone?';
  static const String fromLink = 'A link is asking to connect with the phone below.';
  static const String saved = 'A phone saved here has not connected with you before.';
  static const String caution = 'Only connect if you know who sent you this link.';
  static const String notNow = 'Not now';
  static const String connect = 'Connect';
}

Future<bool> showJoinRequestDialog(BuildContext context, {required String peerId, required bool fromLink}) async {
  final result = await showSkyDialog<bool>(
    context: context,
    dismissible: false,
    builder: (dialogContext) {
      final t = dialogContext.sky;
      return SkyDialog(
        icon: SkyIcons.phone,
        tone: SkyTone.gold,
        title: JoinRequestCopy.title,
        message: fromLink ? JoinRequestCopy.fromLink : JoinRequestCopy.saved,
        actions: [
          SkyButton(
            label: JoinRequestCopy.notNow,
            variant: SkyButtonVariant.ghost,
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          SkyButton(
            label: JoinRequestCopy.connect,
            onPressed: () {
              AppHaptics.tap();
              Navigator.of(dialogContext).pop(true);
            },
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: t.chip,
                borderRadius: SkyRadii.all(SkyRadii.md),
                border: Border.all(color: t.chipBorder),
              ),
              child: Text(
                peerId,
                textAlign: TextAlign.center,
                style: SkyType.sans(12.5, weight: FontWeight.w700).copyWith(color: t.text),
              ),
            ),
            const SizedBox(height: SkySpace.md),
            const SkyNotice(text: JoinRequestCopy.caution, tone: SkyNoticeTone.warning),
          ],
        ),
      );
    },
  );
  return result ?? false;
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.pageBuilder, this.initialTab = SkyTab.sky});

  final SkyTabBuilder? pageBuilder;
  final SkyTab initialTab;

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
    final yes = await showJoinRequestDialog(context, peerId: pending.peerId, fromLink: pending.fromLink);
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

  @override
  Widget build(BuildContext context) {
    final vault = context.watch<VaultService>();
    final identity = context.watch<IdentityController>();
    final notices = context.watch<AppNotices>();
    final peer = context.watch<PeerLink?>();
    final link = peer?.state ?? PeerLinkView.offline;
    final couple = vault.config?.coupleNames;

    return SkyShell(
      initialTab: widget.initialTab,
      pageBuilder: widget.pageBuilder ?? skyTabPage,
      toastController: notices.toast,
      presence: partnerPresenceFor(identity, now: _now, together: link.authorized),
      status: ShellStatus(
        errorText: link.error?.text,
        onDismissError: peer?.clearError,
        warningText: notices.syncWarning,
      ),
      myName: identity.me != null ? identity.myName : couple,
      partnerName: identity.partner != null ? identity.partnerName : null,
      onOpenSettings: () => unawaited(openSettings(context)),
      onOpenLove: () => unawaited(showLoveSheet(context)),
      onLock: vault.lock,
      overlays: const [PeopleSetup()],
    );
  }
}
