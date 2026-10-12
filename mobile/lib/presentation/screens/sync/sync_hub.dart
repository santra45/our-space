import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/engine.dart';
import '../../files/vault_files.dart';
import '../../space_scope.dart';
import '../../widgets/our_widgets.dart';
import '../people/who_is_who.dart';
import 'backup_dialogs.dart';
import 'invite_qr.dart';
import 'peer_link.dart';
import 'qr_scanner.dart';

Future<void> showSyncHub(BuildContext context) {
  return showOurModal<void>(
    context: context,
    backdrop: OurBackdropTone.black50,
    entrance: OurModalEntrance.popSoft,
    builder: (_) => const SyncHub(),
  );
}

abstract final class SyncHubCopy {
  static const String title = 'Pair & Sync Hub';
  static const String subtitle = 'Your two phones, straight to each other';
  static const String waiting = 'Waiting to connect';
  static const String connected = 'Connected to Partner';
  static const String handshaking = 'Making sure it is them…';
  static const String connecting = 'Connecting to Partner...';
  static const String syncNow = 'Sync Now';
  static const String howConnected = 'How you are connected:';
  static const String direct = 'Phone to phone ⚡';
  static const String relayed = 'Via a helper 🛡️';
  static const String notSure = 'Not sure';
  static const String notSureBody =
      'Connected. We cannot tell exactly how it routed, but your things are still private.';
  static const String partnerLabel = 'Partner:';
  static const String reconnect = 'Reconnect';
  static const String unpair = 'Unpair';
  static const String unpairConfirm = 'Unpair from this partner device?';
  static const String partnerAppFallback = 'Partner App';
  static String partnerApp(String partnerName) => partnerName.isEmpty ? partnerAppFallback : '$partnerName\'s App';
  static const String activeNow = 'Active now';
  static String active(String seen) => 'Active $seen';
  static const String waitingForSync = 'Waiting for sync';
  static const String lastConnected = 'Last Connected';
  static const String connectedNow = 'Connected now';
  static const String notYetPaired = 'Not yet paired';
  static const String passphraseMismatchHelp =
      'Both phones must use the exact same secret passphrase. Re-enter it on one device from the lock screen, then pair again.';
  static const String tryAgain = 'Try again';
  static const String dismiss = 'Dismiss';
  static const String syncingWithPartner = 'Syncing with your partner...';
  static const String mailboxChecking = 'Checking for things…';
  static const String mailboxFailed = 'Could not check just now';
  static const String mailboxReady = 'Works even when you are apart';
  static const String checkNow = 'Check now';
  static const String mailboxFailedBody = 'No connection right now. It will try again on its own.';
  static const String mailboxBody =
      'Anything either of you writes is waiting for the other next time they open this, even if you are never here at the same time.';
  static const String qrTitle = 'Your Device Pairing QR';
  static const String preparingYourInvite = 'Preparing your invite…';
  static const String preparingInvite = 'Preparing invite…';
  static const String generating = 'Generating...';
  static const String copyIdLabel = 'Click to copy your Device ID';
  static const String copiedId = 'Copied ID!';
  static const String linkCopied = 'Link Copied to Clipboard!';
  static const String shareLink = 'Share Pairing Link (WhatsApp)';
  static const String connectTitle = 'Connect to Partner\'s Phone';
  static const String scan = 'Scan Partner\'s QR';
  static const String pasteHint = 'Paste Partner\'s ID or Link...';
  static const String pair = 'Pair';
  static const String recognise = 'Only pair with a code you recognise.';
  static const String inviteNotReady = 'Your invite is not quite ready. Give it a second and try again.';
  static const String couldNotCopy = 'Could not copy the link. Long-press your pairing code above to copy it instead.';
  static const String notAnInvite =
      'That does not look like a pairing code or invite link. Paste the whole link your partner sent you, or their code.';
  static const String notAPairingQr = 'That QR code is not an Our Space pairing invite.';
  static const String shareTitle = 'Our Private Space 💕';
  static const String shareText = 'Connect with me on our private space app! Tap to pair our phones directly:';
}

typedef InviteSharer = Future<bool> Function({required String title, required String text, required String url});

typedef TextCopier = Future<void> Function(String text);

abstract final class SyncHubShare {
  static InviteSharer share = _shareWithSystem;
  static TextCopier copy = _copyWithSystem;

  static Future<bool> _shareWithSystem({required String title, required String text, required String url}) async {
    final result = await Share.share('$text $url', subject: title);
    return result.status != ShareResultStatus.dismissed;
  }

  static Future<void> _copyWithSystem(String text) => Clipboard.setData(ClipboardData(text: text));
}

String? syncHubInviteLink({required String? myPeerId, required VaultService vault}) {
  final salt = vault.salt;
  if (myPeerId == null || myPeerId.isEmpty || salt == null || salt.isEmpty) return null;
  final config = vault.config;
  return buildInviteUrl(myPeerId, salt, startDate: config?.startDate, coupleNames: config?.coupleNames);
}

class SyncHub extends StatefulWidget {
  const SyncHub({super.key});

  @override
  State<SyncHub> createState() => _SyncHubState();
}

class _SyncHubState extends State<SyncHub> {
  static const Duration _presenceTick = Duration(seconds: 30);

  final TextEditingController _partnerInput = TextEditingController();
  late final String _devicePeerId;
  Timer? _clock;
  Timer? _copyTimer;
  Timer? _codeTimer;
  int _now = DateTime.now().millisecondsSinceEpoch;
  bool _copySuccess = false;
  bool _codeCopied = false;
  String? _pairError;
  String? _backupNotice;
  String? _backupError;

  @override
  void initState() {
    super.initState();
    _devicePeerId = context.space.device.peerId;
    _clock = Timer.periodic(_presenceTick, (_) {
      if (mounted) setState(() => _now = DateTime.now().millisecondsSinceEpoch);
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _copyTimer?.cancel();
    _codeTimer?.cancel();
    _partnerInput.dispose();
    super.dispose();
  }

  void _close() {
    AppHaptics.tap();
    Navigator.of(context).maybePop();
  }

  void _connect(String partnerPeerId) => context.read<PeerLink?>()?.connect(partnerPeerId);

  Future<void> _shareInvite(String? link) async {
    AppHaptics.tap();
    if (link == null) {
      setState(() => _pairError = SyncHubCopy.inviteNotReady);
      return;
    }
    try {
      final shared = await SyncHubShare.share(title: SyncHubCopy.shareTitle, text: SyncHubCopy.shareText, url: link);
      if (shared) {
        AppHaptics.celebration();
        return;
      }
    } catch (_) {}
    try {
      await SyncHubShare.copy(link);
      if (!mounted) return;
      setState(() => _copySuccess = true);
      _copyTimer?.cancel();
      _copyTimer = Timer(const Duration(milliseconds: 2500), () {
        if (mounted) setState(() => _copySuccess = false);
      });
    } catch (_) {
      if (mounted) setState(() => _pairError = SyncHubCopy.couldNotCopy);
    }
  }

  Future<void> _copyCode(String? myPeerId) async {
    if (myPeerId == null || myPeerId.isEmpty) return;
    AppHaptics.tap();
    try {
      await SyncHubShare.copy(myPeerId);
      if (!mounted) return;
      setState(() => _codeCopied = true);
      _codeTimer?.cancel();
      _codeTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _codeCopied = false);
      });
    } catch (_) {}
  }

  void _manualConnect() {
    setState(() => _pairError = null);
    final raw = _partnerInput.text.trim();
    if (raw.isEmpty) return;
    final parsed = parseInvite(raw);
    if (parsed == null) {
      setState(() => _pairError = SyncHubCopy.notAnInvite);
      return;
    }
    AppHaptics.tap();
    _connect(parsed.partnerPeerId);
  }

  Future<void> _openScanner() async {
    AppHaptics.tap();
    setState(() => _pairError = null);
    final payload = await showQrScanner(context);
    if (!mounted || payload == null) return;
    final parsed = parseInvite(payload);
    if (parsed == null) {
      setState(() => _pairError = SyncHubCopy.notAPairingQr);
      return;
    }
    AppHaptics.celebration();
    _connect(parsed.partnerPeerId);
  }

  Future<void> _unpair(PeerLink peer) async {
    final yes = await showOurConfirm(context, message: SyncHubCopy.unpairConfirm);
    if (yes) peer.unpair();
  }

  void _clearBackupMessages() {
    setState(() {
      _backupNotice = null;
      _backupError = null;
    });
  }

  Future<void> _exportBackup() async {
    AppHaptics.tap();
    _clearBackupMessages();
    final backup = context.space.backup;
    final saved = await showPassphrasePrompt<bool>(
      context,
      title: BackupCopy.exportTitle,
      description: BackupCopy.exportDescription,
      requireConfirm: true,
      submitLabel: BackupCopy.exportSubmit,
      onSubmit: (passphrase) async {
        BackupFile file;
        try {
          file = await backup.exportBackup(passphrase);
        } on BackupFailure catch (failure) {
          return PromptStep<bool>.stay(failure.message);
        } catch (_) {
          return const PromptStep<bool>.stay(BackupMessages.couldNotSave);
        }
        try {
          final written = await VaultFiles.save(file);
          return written ? const PromptStep<bool>.finish(true) : const PromptStep<bool>.stay();
        } catch (_) {
          return const PromptStep<bool>.stay(BackupMessages.couldNotSave);
        }
      },
    );
    if (!mounted || saved != true) return;
    setState(() => _backupNotice = BackupMessages.saved);
    AppHaptics.celebration();
  }

  Future<void> _importBackup() async {
    final backup = context.space.backup;
    PickedVaultFile? picked;
    try {
      picked = await VaultFiles.pick();
    } catch (_) {
      if (mounted) setState(() => _backupError = BackupCopy.couldNotRead);
      return;
    }
    if (!mounted || picked == null) return;
    _clearBackupMessages();
    if (picked.tooBig) {
      setState(() => _backupError = BackupMessages.tooBig(picked!.size));
      return;
    }
    AppHaptics.tap();
    if (picked.bytes == null) {
      setState(() => _backupError = BackupCopy.couldNotRead);
      return;
    }
    Map<String, Object?> container;
    try {
      container = backup.parseBackupFile(picked.readText() ?? '', sizeBytes: picked.size);
    } on BackupFailure catch (failure) {
      setState(() => _backupError = failure.message);
      return;
    } catch (_) {
      setState(() => _backupError = BackupMessages.notOurFile);
      return;
    }

    final preview = await showPassphrasePrompt<ImportPreview>(
      context,
      title: BackupCopy.importTitle,
      description: BackupCopy.importDescription,
      requireConfirm: false,
      submitLabel: BackupCopy.importSubmit,
      fallbackError: BackupMessages.couldNotOpen,
      onSubmit: (passphrase) async {
        try {
          return PromptStep<ImportPreview>.finish(await backup.previewImport(container, passphrase));
        } on BackupFailure catch (failure) {
          return PromptStep<ImportPreview>.stay(failure.message);
        } catch (_) {
          return const PromptStep<ImportPreview>.stay(BackupMessages.couldNotOpen);
        }
      },
    );
    if (!mounted || preview == null) return;
    await showImportPreview(
      context,
      totals: preview.plan.totals,
      relation: preview.relation,
      onConfirm: () => _applyImport(backup, preview),
    );
  }

  Future<void> _applyImport(BackupService backup, ImportPreview preview) async {
    final plannedDeletes = preview.plan.totals.deleted;
    if (mounted) setState(() => _backupError = null);
    try {
      final text = await backup.applyImport(preview);
      if (!mounted) return;
      setState(() => _backupNotice = text);
      if (plannedDeletes > 0) {
        AppHaptics.tap();
      } else {
        AppHaptics.celebration();
      }
    } catch (_) {
      if (mounted) setState(() => _backupError = BackupCopy.didNotFinish);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vault = context.watch<VaultService>();
    final identity = context.watch<IdentityController>();
    final sync = context.watch<SyncService>();
    final notices = context.watch<AppNotices>();
    final peer = context.watch<PeerLink?>();
    final link = peer?.state ?? PeerLinkView.offline;
    final myPeerId = link.myPeerId ?? _devicePeerId;
    final shareUrl = syncHubInviteLink(myPeerId: myPeerId, vault: vault);

    return OurModalCard(
      onClose: _close,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(SyncHubCopy.title, textAlign: TextAlign.center, style: Tw.base.bold.c(AppColors.slate800)),
          Text(SyncHubCopy.subtitle, textAlign: TextAlign.center, style: Tw.xs.c(AppColors.slate400)),
          const SizedBox(height: 16),
          _StatusPanel(
            link: link,
            peer: peer,
            partnerName: identity.partnerName,
            partnerLastActive: identity.partnerLastActive,
            syncWarning: notices.syncWarning,
            now: _now,
            onUnpair: peer == null ? null : () => _unpair(peer),
          ),
          const SizedBox(height: 16),
          if (sync.mailboxEnabled) ...[
            MailboxPanel(
              state: sync.status.state,
              onCheck: () {
                AppHaptics.tap();
                unawaited(sync.syncNow('manual'));
              },
            ),
            const SizedBox(height: 16),
          ],
          const WhoIsWho(),
          _InvitePanel(
            myPeerId: myPeerId,
            shareUrl: shareUrl,
            codeCopied: _codeCopied,
            copySuccess: _copySuccess,
            onCopyCode: () => _copyCode(myPeerId),
            onShare: () => _shareInvite(shareUrl),
          ),
          const SizedBox(height: 16),
          _ConnectPanel(
            controller: _partnerInput,
            pairError: _pairError,
            onScan: _openScanner,
            onPair: _manualConnect,
          ),
          const SizedBox(height: 16),
          _BackupPanel(
            notice: _backupNotice,
            error: _backupError,
            onSave: _exportBackup,
            onBringIn: _importBackup,
          ),
        ],
      ),
    );
  }
}

class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.color, this.size = 10, this.pulse = false, this.ping = false});

  final Color color;
  final double size;
  final bool pulse;
  final bool ping;

  @override
  Widget build(BuildContext context) {
    Widget dot = CssBox(width: size, height: size, color: color, borderRadius: AppRadii.all(AppRadii.full));
    if (pulse) dot = TwPulse(child: dot);
    if (ping) dot = TwPing(child: dot);
    return dot;
  }
}

class HubTextButton extends StatelessWidget {
  const HubTextButton({
    super.key,
    required this.label,
    required this.color,
    required this.onTap,
    this.style,
    this.icon,
    this.iconSize = 12,
    this.gap = 4,
    this.underline = false,
    this.enabled = true,
    this.disabledOpacity = 0.4,
  });

  final String label;
  final Color color;
  final VoidCallback? onTap;
  final TextStyle? style;
  final LucideIconData? icon;
  final double iconSize;
  final double gap;
  final bool underline;
  final bool enabled;
  final double disabledOpacity;

  @override
  Widget build(BuildContext context) {
    var resolved = (style ?? Tw.xs.semibold).c(color);
    if (underline) resolved = resolved.underline.copyWith(decorationColor: color);
    final active = enabled && onTap != null;
    return Semantics(
      button: true,
      enabled: active,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: active ? onTap : null,
        child: Opacity(
          opacity: enabled ? 1 : disabledOpacity,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                LucideIcon(icon!, size: iconSize, color: color),
                SizedBox(width: gap),
              ],
              Flexible(child: Text(label, style: resolved)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Divided extends StatelessWidget {
  const _Divided({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CssBox(
      padding: const EdgeInsets.only(top: 8),
      border: Border(top: BorderSide(color: AppColors.blush100.withValues(alpha: 0.7))),
      child: child,
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({
    required this.link,
    required this.peer,
    required this.partnerName,
    required this.partnerLastActive,
    required this.syncWarning,
    required this.now,
    required this.onUnpair,
  });

  final PeerLinkView link;
  final PeerLink? peer;
  final String partnerName;
  final int? partnerLastActive;
  final String? syncWarning;
  final int now;
  final VoidCallback? onUnpair;

  Widget _route() {
    switch (link.route) {
      case PeerRoute.direct:
        return OurPill(
          label: SyncHubCopy.direct,
          icon: AppIcons.zap,
          iconColor: AppColors.amber500,
          iconFill: AppColors.amber400,
          iconSize: 12,
          gap: 4,
          background: AppColors.emerald100.withValues(alpha: 0.8),
          foreground: AppColors.emerald700,
          border: AppColors.emerald200,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          textStyle: Tw.px11.bold,
          shadows: AppShadows.sm,
        );
      case PeerRoute.relayed:
        return OurPill(
          label: SyncHubCopy.relayed,
          icon: AppIcons.shieldCheck,
          iconColor: AppColors.indigo500,
          iconSize: 12,
          gap: 4,
          background: AppColors.indigo50,
          foreground: AppColors.indigo700,
          border: AppColors.indigo200,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          textStyle: Tw.px11.semibold,
        );
      case null:
        return OurPill(
          label: SyncHubCopy.notSure,
          icon: AppIcons.helpCircle,
          iconColor: AppColors.slate400,
          iconSize: 12,
          gap: 4,
          background: AppColors.slate100,
          foreground: AppColors.slate600,
          border: AppColors.slate200,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          textStyle: Tw.px11.semibold,
        );
    }
  }

  Widget _miniCard({required String label, required Widget dot, required String value}) {
    return CssBox(
      padding: const EdgeInsets.all(10),
      color: AppColors.white.withValues(alpha: 0.8),
      border: Border.all(color: AppColors.blush100.withValues(alpha: 0.6)),
      borderRadius: AppRadii.all(AppRadii.xl),
      shadows: AppShadows.hairline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Tw.px10.medium.c(AppColors.slate500),
                ),
              ),
              const SizedBox(width: 4),
              dot,
            ],
          ),
          const SizedBox(height: 4),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tw.px11.bold.c(AppColors.slate700)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authorized = link.authorized;
    final String label;
    final Widget dot;
    if (authorized) {
      label = SyncHubCopy.connected;
      dot = const StatusDot(color: AppColors.emerald500, pulse: true);
    } else if (link.handshaking) {
      label = SyncHubCopy.handshaking;
      dot = const StatusDot(color: AppColors.amber500, ping: true);
    } else if (link.connecting) {
      label = SyncHubCopy.connecting;
      dot = const StatusDot(color: AppColors.amber500, ping: true);
    } else {
      label = SyncHubCopy.waiting;
      dot = const StatusDot(color: AppColors.amber400);
    }

    final lastActive = partnerLastActive == null || partnerLastActive == 0 ? null : partnerLastActive;
    final seen = formatLastSeen(lastActive, now: now);
    final lastConnected = formatLastConnected(link.lastConnectedAt, now: now);
    final partnerId = link.partnerId;
    final error = link.error;

    final rows = <Widget>[
      Row(
        children: [
          dot,
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: Tw.xs.bold.c(AppColors.slate700))),
          if (authorized)
            HubTextButton(
              label: SyncHubCopy.syncNow,
              icon: AppIcons.refreshCw,
              color: AppColors.blush600,
              onTap: () {
                AppHaptics.tap();
                peer?.syncNow();
              },
            ),
        ],
      ),
      if (authorized)
        _Divided(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(SyncHubCopy.howConnected, style: Tw.px11.medium.c(AppColors.slate500)),
                  const SizedBox(width: 8),
                  Expanded(child: Align(alignment: Alignment.centerRight, child: _route())),
                ],
              ),
              if (link.route == null) ...[
                const SizedBox(height: 4),
                Text(SyncHubCopy.notSureBody, style: Tw.px10.relaxed.c(AppColors.slate500)),
              ],
            ],
          ),
        ),
      if (partnerId != null && partnerId.isNotEmpty)
        _Divided(
          child: Row(
            children: [
              Text(SyncHubCopy.partnerLabel, style: Tw.px11.medium.c(AppColors.slate500)),
              const SizedBox(width: 6),
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 130),
                  child: Text(
                    partnerId,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Tw.px11.mono.bold.c(AppColors.slate700),
                  ),
                ),
              ),
              const Spacer(),
              if (!authorized) ...[
                HubTextButton(
                  label: SyncHubCopy.reconnect,
                  icon: AppIcons.refreshCw,
                  color: AppColors.blush600,
                  style: Tw.xs.bold,
                  underline: true,
                  onTap: () {
                    AppHaptics.tap();
                    peer?.reconnect();
                  },
                ),
                const SizedBox(width: 8),
              ],
              HubTextButton(
                label: SyncHubCopy.unpair,
                color: AppColors.slate400,
                style: Tw.px10,
                onTap: onUnpair,
              ),
            ],
          ),
        ),
      _Divided(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _miniCard(
                label: SyncHubCopy.partnerApp(partnerName),
                dot: StatusDot(
                  size: 8,
                  color: authorized
                      ? AppColors.emerald500
                      : lastActive != null
                          ? AppColors.slate400
                          : AppColors.slate300,
                  pulse: authorized,
                ),
                value: authorized
                    ? SyncHubCopy.activeNow
                    : seen != null
                        ? SyncHubCopy.active(seen)
                        : SyncHubCopy.waitingForSync,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _miniCard(
                label: SyncHubCopy.lastConnected,
                dot: StatusDot(
                  size: 8,
                  color: authorized
                      ? AppColors.emerald500
                      : lastConnected != null
                          ? AppColors.indigo400
                          : AppColors.slate300,
                  pulse: authorized,
                ),
                value: authorized ? SyncHubCopy.connectedNow : lastConnected ?? SyncHubCopy.notYetPaired,
              ),
            ),
          ],
        ),
      ),
      if (error != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: CssBox(
            padding: const EdgeInsets.all(10),
            color: AppColors.rose50,
            border: Border.all(color: AppColors.rose200),
            borderRadius: AppRadii.all(AppRadii.xl),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: LucideIcon(AppIcons.alertTriangle, size: 14, color: AppColors.rose500),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(error.text, style: Tw.px11.bold.relaxed.c(AppColors.rose700)),
                      if (error.code == PeerLinkError.passphraseMismatch) ...[
                        const SizedBox(height: 4),
                        Text(SyncHubCopy.passphraseMismatchHelp, style: Tw.px10.relaxed.c(AppColors.rose600)),
                      ],
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          if (partnerId != null && partnerId.isNotEmpty) ...[
                            HubTextButton(
                              label: SyncHubCopy.tryAgain,
                              color: AppColors.rose700,
                              style: Tw.px10.bold,
                              underline: true,
                              onTap: () {
                                AppHaptics.tap();
                                peer?.reconnect();
                              },
                            ),
                            const SizedBox(width: 12),
                          ],
                          HubTextButton(
                            label: SyncHubCopy.dismiss,
                            color: AppColors.rose600,
                            style: Tw.px10.bold,
                            underline: true,
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
        ),
      if (error == null && syncWarning != null)
        CssBox(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
          color: AppColors.amber50,
          border: Border.all(color: AppColors.amber200.withValues(alpha: 0.6)),
          borderRadius: AppRadii.all(AppRadii.xl),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: LucideIcon(AppIcons.shieldAlert, size: 12, color: AppColors.amber500),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(syncWarning!, style: Tw.px10.relaxed.c(AppColors.amber700))),
            ],
          ),
        ),
      if (link.syncing) Text(SyncHubCopy.syncingWithPartner, style: Tw.px10.medium.c(AppColors.slate500)),
    ];

    return CssBox(
      padding: const EdgeInsets.all(14),
      color: AppColors.blush50.withValues(alpha: 0.6),
      border: Border.all(color: AppColors.blush100),
      borderRadius: AppRadii.all(AppRadii.x2l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: spaced(rows, 10),
      ),
    );
  }
}

class MailboxPanel extends StatelessWidget {
  const MailboxPanel({super.key, required this.state, required this.onCheck});

  final MailboxRunState state;
  final VoidCallback onCheck;

  @override
  Widget build(BuildContext context) {
    final syncing = state == MailboxRunState.syncing;
    final failed = state == MailboxRunState.failed;
    return CssBox(
      padding: const EdgeInsets.all(14),
      color: AppColors.indigo50.withValues(alpha: 0.6),
      border: Border.all(color: AppColors.indigo100),
      borderRadius: AppRadii.all(AppRadii.x2l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const LucideIcon(AppIcons.inbox, size: 14, color: AppColors.indigo500),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  syncing
                      ? SyncHubCopy.mailboxChecking
                      : failed
                          ? SyncHubCopy.mailboxFailed
                          : SyncHubCopy.mailboxReady,
                  style: Tw.xs.bold.c(AppColors.slate700),
                ),
              ),
              const SizedBox(width: 8),
              HubTextButton(
                label: SyncHubCopy.checkNow,
                icon: AppIcons.refreshCw,
                color: AppColors.indigo600,
                enabled: !syncing,
                onTap: onCheck,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            failed ? SyncHubCopy.mailboxFailedBody : SyncHubCopy.mailboxBody,
            style: Tw.px10.relaxed.c(AppColors.slate500),
          ),
        ],
      ),
    );
  }
}

class _InvitePanel extends StatelessWidget {
  const _InvitePanel({
    required this.myPeerId,
    required this.shareUrl,
    required this.codeCopied,
    required this.copySuccess,
    required this.onCopyCode,
    required this.onShare,
  });

  final String? myPeerId;
  final String? shareUrl;
  final bool codeCopied;
  final bool copySuccess;
  final VoidCallback onCopyCode;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final ready = shareUrl != null;
    final frame = Border.all(color: AppColors.slate200);
    return CssBox(
      padding: const EdgeInsets.all(16),
      color: AppColors.slate50,
      border: Border.all(color: AppColors.slate200.withValues(alpha: 0.7)),
      borderRadius: AppRadii.all(AppRadii.x2l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            SyncHubCopy.qrTitle.toUpperCase(),
            textAlign: TextAlign.center,
            style: Tw.px11.semibold.trackingWider.c(AppColors.slate500),
          ),
          const SizedBox(height: 8),
          Center(
            child: ready
                ? CssBox(
                    padding: const EdgeInsets.all(8),
                    color: AppColors.white,
                    border: frame,
                    borderRadius: AppRadii.all(AppRadii.xl),
                    shadows: AppShadows.sm,
                    child: InviteQr(data: shareUrl!),
                  )
                : CssBox(
                    width: 206,
                    height: 206,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    color: AppColors.white,
                    border: frame,
                    borderRadius: AppRadii.all(AppRadii.xl),
                    shadows: AppShadows.sm,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const TwSpin(child: LucideIcon(AppIcons.loader2, size: 20, color: AppColors.slate300)),
                        const SizedBox(height: 8),
                        Text(
                          SyncHubCopy.preparingYourInvite,
                          textAlign: TextAlign.center,
                          style: Tw.px10.relaxed.c(AppColors.slate400),
                        ),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Semantics(
                  button: true,
                  hint: SyncHubCopy.copyIdLabel,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onCopyCode,
                    child: CssBox(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      color: AppColors.white,
                      border: frame,
                      borderRadius: AppRadii.all(AppRadii.lg),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              myPeerId ?? SyncHubCopy.generating,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Tw.xs.mono.bold.c(AppColors.slate600),
                            ),
                          ),
                          const SizedBox(width: 6),
                          const LucideIcon(AppIcons.copy, size: 14, color: AppColors.slate400),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (codeCopied) ...[
                const SizedBox(width: 8),
                Text(SyncHubCopy.copiedId, style: Tw.px10.bold.c(AppColors.emerald600)),
              ],
            ],
          ),
          const SizedBox(height: 12),
          BouncyButton(
            onPressed: onShare,
            enabled: ready,
            expand: true,
            small: true,
            shadows: AppShadows.tinted(AppShadows.sm, AppColors.blush300.withValues(alpha: 0.4)),
            icon: AppIcons.share2,
            label: copySuccess
                ? SyncHubCopy.linkCopied
                : ready
                    ? SyncHubCopy.shareLink
                    : SyncHubCopy.preparingInvite,
          ),
        ],
      ),
    );
  }
}

class _ConnectPanel extends StatelessWidget {
  const _ConnectPanel({
    required this.controller,
    required this.pairError,
    required this.onScan,
    required this.onPair,
  });

  final TextEditingController controller;
  final String? pairError;
  final VoidCallback onScan;
  final VoidCallback onPair;

  @override
  Widget build(BuildContext context) {
    final field = OurFieldStyle.muted.copyWith(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      textStyle: Tw.xs.c(AppColors.slate800),
      hintStyle: Tw.xs.c(AppColors.placeholder),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: spaced([
        Row(
          children: [
            Expanded(child: Text(SyncHubCopy.connectTitle, style: Tw.xs.bold.c(AppColors.slate700))),
            HubTextButton(
              label: SyncHubCopy.scan,
              icon: AppIcons.camera,
              iconSize: 14,
              color: AppColors.blush600,
              style: Tw.xs.bold,
              onTap: onScan,
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: OurTextField(
                controller: controller,
                style: field,
                hint: SyncHubCopy.pasteHint,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.go,
                onSubmitted: (_) => onPair(),
                semanticLabel: SyncHubCopy.pasteHint,
              ),
            ),
            const SizedBox(width: 8),
            BouncyButton(onPressed: onPair, small: true, label: SyncHubCopy.pair),
          ],
        ),
        if (pairError != null) Text(pairError!, style: Tw.px10.semibold.relaxed.c(AppColors.rose600)),
        Text(SyncHubCopy.recognise, style: Tw.px10.relaxed.c(AppColors.slate400)),
      ], 12),
    );
  }
}

class _BackupPanel extends StatelessWidget {
  const _BackupPanel({required this.notice, required this.error, required this.onSave, required this.onBringIn});

  final String? notice;
  final String? error;
  final VoidCallback onSave;
  final VoidCallback onBringIn;

  Widget _button(LucideIconData icon, String label, VoidCallback onTap) {
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: CssBox(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          border: Border.all(color: AppColors.slate200),
          borderRadius: AppRadii.all(AppRadii.xl),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              LucideIcon(icon, size: 14, color: AppColors.slate600),
              const SizedBox(width: 6),
              Flexible(child: Text(label, style: Tw.px11.semibold.c(AppColors.slate600))),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CssBox(
      padding: const EdgeInsets.only(top: 12),
      border: const Border(top: BorderSide(color: AppColors.slate100)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const LucideIcon(AppIcons.shieldCheck, size: 14, color: AppColors.emerald500),
              const SizedBox(width: 6),
              Flexible(child: Text(BackupCopy.sectionTitle, style: Tw.px11.bold.c(AppColors.slate600))),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _button(AppIcons.download, BackupCopy.saveCopy, onSave)),
              const SizedBox(width: 8),
              Expanded(child: _button(AppIcons.upload, BackupCopy.bringInCopy, onBringIn)),
            ],
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(error!, textAlign: TextAlign.center, style: Tw.px10.semibold.relaxed.c(AppColors.rose600)),
          ],
          if (notice != null) ...[
            const SizedBox(height: 8),
            Text(notice!, textAlign: TextAlign.center, style: Tw.px10.medium.relaxed.c(AppColors.emerald600)),
          ],
        ],
      ),
    );
  }
}
