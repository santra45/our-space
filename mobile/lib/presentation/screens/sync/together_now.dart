import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/engine.dart';
import '../../app_shell.dart' show ShellCopy;
import '../../sky/sky.dart';
import '../../space_scope.dart';
import '../../widgets/app_haptics.dart';
import '../settings/widgets/sheet_parts.dart';
import 'peer_link.dart';

abstract final class TogetherNowCopy {
  static const String title = 'Your two phones';
  static const String together = 'Together right now';
  static const String makingSure = 'Making sure it is them…';
  static const String reaching = 'Reaching their phone…';
  static const String waiting = 'Waiting to find each other';
  static const String notJoined = 'Only this phone so far';
  static String lastTogether(String when) => 'Last together ${ShellCopy.when(when)}';
  static const String sheetIntro = 'When both phones are open, everything you write finds its way across.';
  static const String catchUp = 'Catch up now';
  static const String howTitle = 'How they reach each other';
  static const String direct = 'Straight to each other';
  static const String helper = 'Through a safe helper';
  static const String notSure = 'Not sure';
  static const String notSureBody = 'They found each other. We cannot tell which way, but your things stay private.';
  static String partnerPhone(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'Their phone';
    return '${trimmed[0].toUpperCase()}${trimmed.substring(1)}\'s phone';
  }

  static const String hereNow = 'Here right now';
  static String lastHere(String when) => 'Last here ${ShellCopy.when(when)}';
  static const String notHereYet = 'Not here yet';
  static const String lastTogetherTitle = 'Last together';
  static const String rightNow = 'Right now';
  static const String notYet = 'Not yet';
  static const String theirCode = 'Their code';
  static const String reachAgain = 'Reach them again';
  static const String forget = 'Forget their phone';
  static const String forgetTitle = 'Forget their phone?';
  static const String forgetBody =
      'This phone stops reaching theirs until you add it again with their link or code. Nothing you wrote is lost.';
  static const String forgetConfirm = 'Forget it';
  static const String keep = 'Keep it';
  static const String mismatchHelp =
      'Both phones need the very same passphrase. Type it again on one phone from the lock screen, then add the phone again.';
  static const String tryAgain = 'Try again';
  static const String dismiss = 'Dismiss';
  static String catchingUp(String name) => 'Catching up with $name…';
  static const String apartChecking = 'Checking for things…';
  static const String apartFailed = 'Could not check just now';
  static const String apartReady = 'Works even when you are apart';
  static const String checkNow = 'Check now';
  static const String apartFailedBody = 'No connection right now. It will try again on its own.';
  static const String apartBody =
      'Anything either of you writes is waiting for the other next time they open this, even if you are never here at the same time.';
}

enum TogetherState { together, makingSure, reaching, waiting, notJoined }

TogetherState togetherStateOf(PeerLinkView link) {
  if (link.authorized) return TogetherState.together;
  if (link.handshaking) return TogetherState.makingSure;
  if (link.connecting) return TogetherState.reaching;
  final partner = link.partnerId;
  final known = (partner != null && partner.isNotEmpty) || link.lastConnectedAt != null;
  return known ? TogetherState.waiting : TogetherState.notJoined;
}

String togetherSentence(PeerLinkView link, {int? now}) {
  switch (togetherStateOf(link)) {
    case TogetherState.together:
      return TogetherNowCopy.together;
    case TogetherState.makingSure:
      return TogetherNowCopy.makingSure;
    case TogetherState.reaching:
      return TogetherNowCopy.reaching;
    case TogetherState.waiting:
      final last = formatLastConnected(link.lastConnectedAt, now: now);
      return last == null ? TogetherNowCopy.waiting : TogetherNowCopy.lastTogether(last);
    case TogetherState.notJoined:
      return TogetherNowCopy.notJoined;
  }
}

class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.state, this.size = 9});

  final TogetherState state;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final Color color;
    final bool pulse;
    switch (state) {
      case TogetherState.together:
        color = t.rose;
        pulse = true;
      case TogetherState.makingSure:
      case TogetherState.reaching:
        color = t.gold;
        pulse = true;
      case TogetherState.waiting:
      case TogetherState.notJoined:
        color = t.faint;
        pulse = false;
    }
    final dot = AnimatedContainer(
      duration: skyMotionAllowed(context) ? SkyMotion.base : Duration.zero,
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: pulse ? [BoxShadow(color: color.withValues(alpha: 0.7), blurRadius: size)] : const [],
      ),
    );
    if (!pulse) return dot;
    return SkyPulse(child: dot);
  }
}

class TogetherNowError extends StatelessWidget {
  const TogetherNowError({super.key, required this.link, required this.peer});

  final PeerLinkView link;
  final PeerLink? peer;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final error = link.error;
    if (error == null) return const SizedBox.shrink();
    final partnerId = link.partnerId;
    final canRetry = partnerId != null && partnerId.isNotEmpty;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        decoration: BoxDecoration(
          color: t.roseSoft,
          borderRadius: SkyRadii.all(SkyRadii.tile),
          border: Border.all(color: t.roseBorder),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: SkyIcon(SkyIcons.alert, size: 18, color: t.rose),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    skyCalmText(error.text),
                    style: SkyType.bodySmall.copyWith(color: t.text, fontWeight: FontWeight.w600),
                  ),
                  if (error.code == PeerLinkError.passphraseMismatch) ...[
                    const SizedBox(height: 4),
                    Text(TogetherNowCopy.mismatchHelp, style: SkyType.small.copyWith(color: t.muted, height: 1.45)),
                  ],
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 16,
                    children: [
                      if (canRetry)
                        TextAction(
                          label: TogetherNowCopy.tryAgain,
                          onTap: () {
                            AppHaptics.tap();
                            peer?.reconnect();
                          },
                        ),
                      TextAction(
                        label: TogetherNowCopy.dismiss,
                        color: t.muted,
                        onTap: () {
                          AppHaptics.tap();
                          peer?.clearError();
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TogetherNowAlerts extends StatelessWidget {
  const TogetherNowAlerts({
    super.key,
    required this.link,
    required this.peer,
    required this.warning,
    required this.partnerName,
    this.showSyncing = true,
    this.gap = SkySpace.sm,
  });

  final PeerLinkView link;
  final PeerLink? peer;
  final String? warning;
  final String partnerName;
  final bool showSyncing;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final items = <Widget>[
      if (link.error != null)
        SkyEntrance(
          key: ValueKey<String>('together-error-${link.error!.text}'),
          offset: const Offset(0, -8),
          duration: SkyMotion.base,
          child: TogetherNowError(link: link, peer: peer),
        ),
      if (warning != null)
        SkyEntrance(
          key: ValueKey<String>('together-warning-$warning'),
          offset: const Offset(0, -8),
          duration: SkyMotion.base,
          child: SkyNotice(text: skyCalmText(warning!), tone: SkyNoticeTone.warning),
        ),
      if (showSyncing && link.syncing)
        Row(
          key: const ValueKey<String>('together-syncing'),
          children: [
            SkySpinner(size: 12, color: t.gold),
            const SizedBox(width: SkySpace.sm),
            Expanded(
              child: Text(TogetherNowCopy.catchingUp(partnerName), style: SkyType.small.copyWith(color: t.muted)),
            ),
          ],
        ),
    ];
    return GrowIn(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < items.length; i++)
            Padding(
              key: items[i].key,
              padding: EdgeInsets.only(top: gap),
              child: items[i],
            ),
        ],
      ),
    );
  }
}

class ApartPanel extends StatelessWidget {
  const ApartPanel({super.key, required this.state, required this.onCheck});

  final MailboxRunState state;
  final VoidCallback onCheck;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final checking = state == MailboxRunState.syncing;
    final failed = state == MailboxRunState.failed;
    return SkyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SkyIconTile(icon: SkyIcons.letter, tone: failed ? SkyTone.rose : SkyTone.lavender, size: 32),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  checking
                      ? TogetherNowCopy.apartChecking
                      : failed
                      ? TogetherNowCopy.apartFailed
                      : TogetherNowCopy.apartReady,
                  style: SkyType.bodyStrong.copyWith(color: t.text),
                ),
              ),
              const SizedBox(width: SkySpace.sm),
              if (checking) ...[SkySpinner(size: 12, color: t.lavender), const SizedBox(width: 6)],
              TextAction(
                label: TogetherNowCopy.checkNow,
                icon: SkyIcons.refresh,
                color: t.lavender,
                enabled: !checking,
                onTap: onCheck,
              ),
            ],
          ),
          const SizedBox(height: SkySpace.sm),
          Text(
            failed ? TogetherNowCopy.apartFailedBody : TogetherNowCopy.apartBody,
            style: SkyType.small.copyWith(color: t.muted, height: 1.5),
          ),
        ],
      ),
    );
  }
}

Future<void> showTogetherNowSheet(BuildContext context) {
  return showSkySheet<void>(context: context, builder: (_) => const TogetherNowSheet());
}

class TogetherNowSheet extends StatefulWidget {
  const TogetherNowSheet({super.key});

  @override
  State<TogetherNowSheet> createState() => _TogetherNowSheetState();
}

class _TogetherNowSheetState extends State<TogetherNowSheet> {
  static const Duration _tick = Duration(seconds: 30);

  Timer? _clock;
  int _now = DateTime.now().millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(_tick, (_) {
      if (mounted) setState(() => _now = DateTime.now().millisecondsSinceEpoch);
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _forget(PeerLink peer) async {
    final yes = await showSkyConfirm(
      context,
      title: TogetherNowCopy.forgetTitle,
      message: TogetherNowCopy.forgetBody,
      confirmLabel: TogetherNowCopy.forgetConfirm,
      cancelLabel: TogetherNowCopy.keep,
      destructive: true,
      icon: SkyIcons.phone,
    );
    if (yes) peer.unpair();
  }

  Widget _fact(String label, String value, {bool mono = false}) {
    final t = context.sky;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            flex: 2,
            child: Text(label, maxLines: 2, style: SkyType.bodySmall.copyWith(color: t.muted)),
          ),
          const SizedBox(width: SkySpace.md),
          Flexible(
            flex: 3,
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: (mono ? SkyType.sans(12.5, weight: FontWeight.w700, letterSpacing: 0.3) : SkyType.bodyStrong)
                  .copyWith(color: t.text),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final identity = context.watch<IdentityController>();
    final sync = context.watch<SyncService>();
    final notices = context.watch<AppNotices>();
    final peer = context.watch<PeerLink?>();
    final link = peer?.state ?? PeerLinkView.offline;
    final state = togetherStateOf(link);
    final authorized = link.authorized;
    final partnerId = link.partnerId;
    final hasPartner = partnerId != null && partnerId.isNotEmpty;
    final lastActive = identity.partnerLastActive == 0 ? null : identity.partnerLastActive;
    final seen = formatLastSeen(lastActive, now: _now);
    final lastConnected = formatLastConnected(link.lastConnectedAt, now: _now);
    final warning = link.error == null ? notices.syncWarning : null;

    final String how;
    switch (link.route) {
      case PeerRoute.direct:
        how = TogetherNowCopy.direct;
      case PeerRoute.relayed:
        how = TogetherNowCopy.helper;
      case null:
        how = TogetherNowCopy.notSure;
    }

    return SheetScroll(
      spacing: SkySpace.md,
      children: [
        SheetHeader(
          title: TogetherNowCopy.title,
          subtitle: TogetherNowCopy.sheetIntro,
          icon: SkyIcons.phone,
          tone: SkyTone.lavender,
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SkyCard(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  StatusDot(state: state, size: 10),
                  const SizedBox(width: SkySpace.md),
                  Expanded(
                    child: Text(
                      togetherSentence(link, now: _now),
                      style: SkyType.serif(19, weight: FontWeight.w500, height: 1.25).copyWith(color: t.text),
                    ),
                  ),
                  if (authorized) ...[
                    const SizedBox(width: SkySpace.sm),
                    TextAction(
                      label: TogetherNowCopy.catchUp,
                      icon: SkyIcons.refresh,
                      onTap: () {
                        AppHaptics.tap();
                        peer?.syncNow();
                      },
                    ),
                  ],
                ],
              ),
            ),
            TogetherNowAlerts(link: link, peer: peer, warning: warning, partnerName: identity.partnerName),
          ],
        ),
        SkyListGroup(
          children: [
            if (authorized)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _fact(TogetherNowCopy.howTitle, how),
                  if (link.route == null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                      child: Text(
                        TogetherNowCopy.notSureBody,
                        style: SkyType.small.copyWith(color: t.muted, height: 1.45),
                      ),
                    ),
                ],
              ),
            _fact(
              TogetherNowCopy.partnerPhone(identity.partnerName),
              authorized
                  ? TogetherNowCopy.hereNow
                  : seen != null
                  ? TogetherNowCopy.lastHere(seen)
                  : TogetherNowCopy.notHereYet,
            ),
            _fact(
              TogetherNowCopy.lastTogetherTitle,
              authorized ? TogetherNowCopy.rightNow : lastConnected ?? TogetherNowCopy.notYet,
            ),
            if (hasPartner) _fact(TogetherNowCopy.theirCode, partnerId, mono: true),
          ],
        ),
        if (sync.mailboxEnabled)
          ApartPanel(
            state: sync.status.state,
            onCheck: () {
              AppHaptics.tap();
              unawaited(sync.syncNow('manual'));
            },
          ),
        if (hasPartner && peer != null)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!authorized) ...[
                SkyButton(
                  label: TogetherNowCopy.reachAgain,
                  icon: SkyIcons.refresh,
                  variant: SkyButtonVariant.ghost,
                  height: SkySizes.buttonCompact,
                  onPressed: () {
                    AppHaptics.tap();
                    peer.reconnect();
                  },
                ),
                const SizedBox(height: SkySpace.md - 2),
              ],
              SkyButton(
                label: TogetherNowCopy.forget,
                variant: SkyButtonVariant.danger,
                height: SkySizes.buttonCompact,
                onPressed: () => _forget(peer),
              ),
            ],
          ),
      ],
    );
  }
}
