import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/engine.dart';
import '../../sky/sky.dart';
import '../../space_scope.dart';
import '../../widgets/app_haptics.dart';
import '../settings/widgets/settings_field.dart';
import '../settings/widgets/sheet_parts.dart';
import 'invite_qr.dart';
import 'peer_link.dart';
import 'qr_scanner.dart';
import 'together_now.dart';

abstract final class AddPhoneCopy {
  static const String title = 'Add another phone';
  static const String kicker = 'The two of us';
  static const String intro = 'Open Our Space on the other phone, then scan this code or send them your link.';
  static const String codeTitle = 'Your code to scan';
  static const String preparingYourInvite = 'Preparing your invite…';
  static const String preparingInvite = 'Preparing invite…';
  static const String generating = 'Getting your code…';
  static const String copyHint = 'Tap to copy your code';
  static const String copied = 'Copied';
  static const String linkCopied = 'Link copied. Paste it to them';
  static const String shareLink = 'Send them your link';
  static const String haveTheirs = 'Have their link or code?';
  static const String haveTheirsBody = 'If they sent you something first, bring it in here.';
  static const String scan = 'Scan their code';
  static const String pasteHint = 'Paste their link or code';
  static const String connect = 'Connect';
  static const String recognise = 'Only connect with a code you know came from them.';
  static const String inviteNotReady = 'Your invite is not quite ready. Give it a second and try again.';
  static const String couldNotCopy = 'Could not copy the link. Tap your code above to copy that instead.';
  static const String notAnInvite =
      'That does not look like their link or code. Paste the whole link they sent you, or their code.';
  static const String notAnInviteQr = 'That code is not an Our Space invite.';
  static const String shareTitle = 'Our Space';
  static const String shareText = 'Come into Our Space with me. Tap to bring your phone in:';
}

typedef InviteSharer = Future<bool> Function({required String title, required String text, required String url});

typedef TextCopier = Future<void> Function(String text);

abstract final class InviteShare {
  static InviteSharer share = _shareWithSystem;
  static TextCopier copy = _copyWithSystem;

  static Future<bool> _shareWithSystem({required String title, required String text, required String url}) async {
    final result = await Share.share('$text $url', subject: title);
    return result.status != ShareResultStatus.dismissed;
  }

  static Future<void> _copyWithSystem(String text) => Clipboard.setData(ClipboardData(text: text));
}

String? inviteLinkFor({required String? myPeerId, required VaultService vault}) {
  final salt = vault.salt;
  if (myPeerId == null || myPeerId.isEmpty || salt == null || salt.isEmpty) return null;
  final config = vault.config;
  return buildInviteUrl(myPeerId, salt, startDate: config?.startDate, coupleNames: config?.coupleNames);
}

Future<void> openAddPhone(BuildContext context) => skyPush<void>(context, (_) => const AddPhonePage());

class AddPhonePage extends StatefulWidget {
  const AddPhonePage({super.key});

  static const Color qrInk = Color(0xFF1E1B3A);

  static const SkyScene scene = SkyScene(
    stars: 50,
    moon: Offset(346, 262),
    sun: false,
    clouds: [SkyCloud(344, 262, scale: 0.75, opacity: 0.8), SkyCloud(42, 318, scale: 0.55, opacity: 0.5)],
  );

  @override
  State<AddPhonePage> createState() => _AddPhonePageState();
}

class _AddPhonePageState extends State<AddPhonePage> {
  final TextEditingController _partnerInput = TextEditingController();
  late final String _devicePeerId;
  Timer? _copyTimer;
  Timer? _codeTimer;
  bool _copySuccess = false;
  bool _codeCopied = false;
  String? _pairError;

  @override
  void initState() {
    super.initState();
    _devicePeerId = context.space.device.peerId;
  }

  @override
  void dispose() {
    _copyTimer?.cancel();
    _codeTimer?.cancel();
    _partnerInput.dispose();
    super.dispose();
  }

  void _connect(String partnerPeerId) => context.read<PeerLink?>()?.connect(partnerPeerId);

  Future<void> _shareInvite(String? link) async {
    AppHaptics.tap();
    if (link == null) {
      setState(() => _pairError = AddPhoneCopy.inviteNotReady);
      return;
    }
    try {
      final shared = await InviteShare.share(title: AddPhoneCopy.shareTitle, text: AddPhoneCopy.shareText, url: link);
      if (shared) {
        AppHaptics.celebration();
        return;
      }
    } catch (_) {}
    try {
      await InviteShare.copy(link);
      if (!mounted) return;
      setState(() => _copySuccess = true);
      _copyTimer?.cancel();
      _copyTimer = Timer(const Duration(milliseconds: 2500), () {
        if (mounted) setState(() => _copySuccess = false);
      });
    } catch (_) {
      if (mounted) setState(() => _pairError = AddPhoneCopy.couldNotCopy);
    }
  }

  Future<void> _copyCode(String? myPeerId) async {
    if (myPeerId == null || myPeerId.isEmpty) return;
    AppHaptics.tap();
    try {
      await InviteShare.copy(myPeerId);
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
      setState(() => _pairError = AddPhoneCopy.notAnInvite);
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
      setState(() => _pairError = AddPhoneCopy.notAnInviteQr);
      return;
    }
    AppHaptics.celebration();
    _connect(parsed.partnerPeerId);
  }

  Widget _qrCard(String? shareUrl) {
    final t = context.sky;
    final ready = shareUrl != null;
    return Center(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: SkyTokens.white,
          borderRadius: SkyRadii.all(SkyRadii.card),
          border: Border.all(color: t.isNight ? t.gold.withValues(alpha: 0.5) : t.cardBorder),
          boxShadow: t.isNight
              ? [BoxShadow(color: t.gold.withValues(alpha: 0.22), blurRadius: 28, spreadRadius: 2)]
              : t.shadow,
        ),
        child: SizedBox.square(
          dimension: InviteQr.webSize,
          child: AnimatedSwitcher(
            duration: skyMotionAllowed(context) ? SkyMotion.medium : Duration.zero,
            child: ready
                ? RepaintBoundary(
                    key: const ValueKey<String>('qr-ready'),
                    child: InviteQr(data: shareUrl, dark: AddPhonePage.qrInk),
                  )
                : Column(
                    key: const ValueKey<String>('qr-waiting'),
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SkySpinner(size: 20, color: t.roseDeep),
                      const SizedBox(height: SkySpace.sm),
                      Text(
                        AddPhoneCopy.preparingYourInvite,
                        textAlign: TextAlign.center,
                        style: SkyType.small.copyWith(color: SkyTokens.day.muted),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _codeChip(String? myPeerId) {
    final t = context.sky;
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: SkyPressable(
              onTap: () => _copyCode(myPeerId),
              semanticLabel: AddPhoneCopy.copyHint,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: t.chip,
                  borderRadius: SkyRadii.all(SkyRadii.pill),
                  border: Border.all(color: t.chipBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        myPeerId ?? AddPhoneCopy.generating,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SkyType.sans(13, weight: FontWeight.w700, letterSpacing: 0.4).copyWith(color: t.text),
                      ),
                    ),
                    const SizedBox(width: SkySpace.sm),
                    SkyIcon(
                      _codeCopied ? SkyIcons.check : SkyIcons.copy,
                      size: 15,
                      color: _codeCopied ? t.gold : t.muted,
                    ),
                  ],
                ),
              ),
            ),
          ),
          GrowIn(
            child: _codeCopied
                ? Padding(
                    padding: const EdgeInsets.only(left: SkySpace.sm),
                    child: Text(
                      AddPhoneCopy.copied,
                      style: SkyType.small.copyWith(color: t.gold, fontWeight: FontWeight.w700),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final vault = context.watch<VaultService>();
    final identity = context.watch<IdentityController>();
    final notices = context.watch<AppNotices>();
    final peer = context.watch<PeerLink?>();
    final link = peer?.state ?? PeerLinkView.offline;
    final myPeerId = link.myPeerId ?? _devicePeerId;
    final shareUrl = inviteLinkFor(myPeerId: myPeerId, vault: vault);
    final ready = shareUrl != null;
    final state = togetherStateOf(link);
    final warning = link.error == null ? notices.syncWarning : null;

    return SkyScrollScaffold(
      scene: AddPhonePage.scene,
      topBar: const SkyTopBar(
        title: AddPhoneCopy.title,
        kicker: AddPhoneCopy.kicker,
        compact: true,
        leading: SkyBackButton(),
      ),
      padding: const EdgeInsets.fromLTRB(SkySpace.gutter, SkySpace.xl, SkySpace.gutter, 0),
      spacing: SkySpace.lg,
      children: [
        Text(
          AddPhoneCopy.intro,
          textAlign: TextAlign.center,
          style: SkyType.body.copyWith(color: t.muted, height: 1.5),
        ),
        _qrCard(shareUrl),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SkyLabel(AddPhoneCopy.codeTitle, center: true, tone: SkyTone.gold),
            const SizedBox(height: SkySpace.sm),
            _codeChip(myPeerId),
          ],
        ),
        SkyButton(
          label: _copySuccess
              ? AddPhoneCopy.linkCopied
              : ready
              ? AddPhoneCopy.shareLink
              : AddPhoneCopy.preparingInvite,
          icon: _copySuccess ? SkyIcons.check : SkyIcons.share,
          onPressed: ready ? () => _shareInvite(shareUrl) : null,
        ),
        SkyCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(AddPhoneCopy.haveTheirs, style: SkyType.headlineSmall.copyWith(color: t.text)),
              const SizedBox(height: SkySpace.xs),
              Text(AddPhoneCopy.haveTheirsBody, style: SkyType.small.copyWith(color: t.muted)),
              const SizedBox(height: SkySpace.md),
              SkyButton(
                label: AddPhoneCopy.scan,
                icon: SkyIcons.scan,
                variant: SkyButtonVariant.ghost,
                height: SkySizes.buttonCompact,
                onPressed: _openScanner,
              ),
              const SizedBox(height: SkySpace.md),
              Row(
                children: [
                  Expanded(
                    child: SettingsField(
                      controller: _partnerInput,
                      hint: AddPhoneCopy.pasteHint,
                      leadingIcon: SkyIcons.link,
                      autocorrect: false,
                      enableSuggestions: false,
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.go,
                      onSubmitted: (_) => _manualConnect(),
                    ),
                  ),
                  const SizedBox(width: SkySpace.sm),
                  SkyButton(
                    label: AddPhoneCopy.connect,
                    variant: SkyButtonVariant.gold,
                    expand: false,
                    height: 46,
                    onPressed: _manualConnect,
                  ),
                ],
              ),
              SettingsNotes(notes: [if (_pairError != null) SettingsNote.error(_pairError!)], top: SkySpace.md),
              const SizedBox(height: SkySpace.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: SkyIcon(SkyIcons.info, size: 13, color: t.faint),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(AddPhoneCopy.recognise, style: SkyType.caption.copyWith(color: t.faint, height: 1.45)),
                  ),
                ],
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SkyCard(
              onTap: () => showTogetherNowSheet(context),
              semanticLabel: TogetherNowCopy.title,
              child: Row(
                children: [
                  StatusDot(state: state),
                  const SizedBox(width: SkySpace.md),
                  Expanded(
                    child: Text(togetherSentence(link), style: SkyType.bodyStrong.copyWith(color: t.text)),
                  ),
                  SkyIcon(SkyIcons.chevron, size: 15, color: t.muted),
                ],
              ),
            ),
            TogetherNowAlerts(link: link, peer: peer, warning: warning, partnerName: identity.partnerName),
          ],
        ),
      ],
    );
  }
}
