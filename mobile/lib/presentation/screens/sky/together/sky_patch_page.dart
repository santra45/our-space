import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/engine.dart';
import '../../../sky/sky.dart';
import '../../../widgets/app_haptics.dart';
import 'sky_patch_canvas.dart';
import 'sky_patch_naming.dart';
import 'sky_patch_session.dart';
import 'sky_together_copy.dart';
import 'sky_together_layer.dart';

class SkyPatchPage extends StatefulWidget {
  const SkyPatchPage({
    super.key,
    required this.session,
    required this.partner,
    this.me,
    this.dayNumber,
    this.onClosed,
  });

  static const Duration homeAfterSaved = Duration(milliseconds: 1600);

  final SkyPatchSession session;
  final String partner;
  final String? me;
  final int? dayNumber;
  final VoidCallback? onClosed;

  static SkyScene scene() => const SkyScene(
    seed: 23,
    stars: 95,
    dayStars: 16,
    sun: false,
    clouds: [SkyCloud(330, 640, scale: 0.75, opacity: 0.55), SkyCloud(56, 214, scale: 0.55, opacity: 0.45)],
  );

  @override
  State<SkyPatchPage> createState() => _SkyPatchPageState();
}

class _SkyPatchPageState extends State<SkyPatchPage> {
  final SkyToastController _toast = SkyToastController();
  StreamSubscription<SkyPatchNotice>? _notices;
  Timer? _home;
  bool _leaving = false;
  bool _awayShown = false;
  bool _confirming = false;

  SkyPatchSession get session => widget.session;

  @override
  void initState() {
    super.initState();
    session.addListener(_onSession);
    _notices = session.notices.listen(_onNotice);
  }

  @override
  void dispose() {
    session.removeListener(_onSession);
    unawaited(_notices?.cancel());
    _home?.cancel();
    _toast.dispose();
    final closed = widget.onClosed;
    if (closed != null) scheduleMicrotask(closed);
    super.dispose();
  }

  void _onSession() {
    if (!mounted) return;
    if (session.partnerAway && !_awayShown && !_leaving && session.step != SkyPatchStep.saved) {
      _awayShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_showAway()));
    }
    setState(() {});
  }

  void _onNotice(SkyPatchNotice notice) {
    if (!mounted) return;
    switch (notice.kind) {
      case SkyPatchNoticeKind.partnerStartedOver:
        _toast.show(SkyTogetherCopy.startedOver(widget.partner));
      case SkyPatchNoticeKind.saved:
        _home?.cancel();
        _home = Timer(SkyPatchPage.homeAfterSaved, _leave);
      case SkyPatchNoticeKind.partnerStar:
        break;
    }
  }

  void _leave() {
    if (_leaving) return;
    _leaving = true;
    unawaited(session.leave());
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route == null) return;
    if (route.isCurrent) {
      Navigator.of(context).pop();
    } else if (route.isActive) {
      Navigator.of(context).removeRoute(route);
    }
  }

  Future<void> _showAway() async {
    if (!mounted || _leaving) return;
    final night = context.sky.isNight;
    await showSkyDialog<void>(
      context: context,
      dismissible: false,
      builder: (dialogContext) => SkyDialog(
        icon: night ? SkyIcons.moon : SkyIcons.sun,
        tone: SkyTone.gold,
        title: SkyTogetherCopy.steppedAway(widget.partner),
        message: SkyTogetherCopy.steppedAwayMessage(night),
        actions: [
          SkyButton(
            label: SkyTogetherCopy.backToSky,
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
        ],
      ),
    );
    _leave();
  }

  Future<void> _startOver() async {
    if (_confirming || !session.canEdit) return;
    _confirming = true;
    final yes = await showSkyConfirm(
      context,
      title: SkyTogetherCopy.startOverTitle,
      message: SkyTogetherCopy.startOverMessage,
      confirmLabel: SkyTogetherCopy.startOver,
      cancelLabel: SkyTogetherCopy.keepDrawing,
      icon: SkyIcons.refresh,
    );
    _confirming = false;
    if (!yes || !mounted) return;
    if (session.startOver()) session.haptic(HapticKind.tap);
  }

  void _done() {
    if (session.finishDrawing()) session.haptic(HapticKind.tick);
  }

  bool _unlocked(BuildContext context) {
    try {
      return Provider.of<VaultService>(context).isUnlocked;
    } on ProviderNotFoundException {
      return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_unlocked(context) && !_leaving) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _leave());
    }
    final step = session.step;
    final drawing = step == SkyPatchStep.drawing;
    final content = drawing
        ? KeyedSubtree(key: const ValueKey<String>('sky-patch-drawing'), child: _drawingView(context))
        : KeyedSubtree(
            key: const ValueKey<String>('sky-patch-naming'),
            child: SkyPatchNaming(
              session: session,
              partner: widget.partner,
              me: widget.me,
              dayNumber: widget.dayNumber,
            ),
          );
    return PopScope(
      canPop: step != SkyPatchStep.naming,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _leaving = true;
          unawaited(session.leave());
          return;
        }
        if (step == SkyPatchStep.naming) session.backToDrawing();
      },
      child: SkyScaffold(
        key: SkyTogetherKeys.patch,
        showSky: false,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(child: SkyBackdrop(scene: SkyPatchPage.scene())),
            Positioned.fill(
              child: SkySharedAxisSwitcher(duration: SkyMotion.slow, expand: true, child: content),
            ),
            Positioned(
              top: MediaQuery.viewPaddingOf(context).top + SkySpace.sm,
              left: SkySpace.lg,
              right: SkySpace.lg,
              child: SkyToastHost(controller: _toast),
            ),
          ],
        ),
      ),
    );
  }

  String? _limit(SkyDrawing drawing) {
    final stars = drawing.visibleStars.length;
    if (drawing.starsFull) return SkyTogetherCopy.fullOfStars;
    if (drawing.linesFull) return SkyTogetherCopy.noRoomForLines;
    final left = skyDrawingMaxStars - stars;
    if (left <= 5) return SkyTogetherCopy.starsLeft(left);
    return null;
  }

  Widget _drawingView(BuildContext context) {
    final t = context.sky;
    final media = MediaQuery.of(context);
    final drawing = session.drawing;
    final note = _limit(drawing);
    final editable = session.canEdit;
    final help = note == null
        ? Text.rich(
            TextSpan(
              children: [
                for (final (i, part) in SkyTogetherCopy.helpParts.indexed) ...[
                  if (i > 0)
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: Text('·', style: SkyType.sans(11.5).copyWith(color: t.faint)),
                      ),
                    ),
                  TextSpan(text: part),
                ],
              ],
            ),
            textAlign: TextAlign.center,
            style: SkyType.sans(11.5, height: 1.4).copyWith(color: t.muted),
            semanticsLabel: SkyTogetherCopy.help,
          )
        : Text(note, textAlign: TextAlign.center, style: SkyType.sans(11.5, height: 1.4).copyWith(color: t.muted));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SkyEntrance(
          child: SkyTopBar(
            compact: true,
            leading: SkyBackButton(semanticLabel: SkyTogetherCopy.leave, onPressed: _leave),
            kicker: SkyTogetherCopy.patchKicker(night: t.isNight, dayNumber: widget.dayNumber),
            note: SkyTogetherCopy.drawingWith(widget.partner),
            title: SkyTogetherCopy.drawTitle,
            trailing: _TogetherPill(me: widget.me, partner: widget.partner),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(SkySpace.gutter, 16, SkySpace.gutter, 10),
            child: SkyPatchCanvas(session: session, partner: widget.partner),
          ),
        ),
        Padding(
          key: SkyTogetherKeys.help,
          padding: const EdgeInsets.symmetric(horizontal: SkySpace.gutter),
          child: AnimatedSwitcher(
            duration: skyMotionAllowed(context) ? SkyMotion.quick : Duration.zero,
            child: KeyedSubtree(key: ValueKey<String?>(note), child: help),
          ),
        ),
        const SizedBox(height: 18),
        Padding(
          padding: EdgeInsets.fromLTRB(SkySpace.gutter, 0, SkySpace.gutter, media.viewPadding.bottom + SkySpace.xl),
          child: Row(
            children: [
              SkyPressable(
                key: SkyTogetherKeys.startOver,
                onTap: editable && !drawing.isBlank ? () => unawaited(_startOver()) : null,
                enabled: editable && !drawing.isBlank,
                semanticLabel: SkyTogetherCopy.startOver,
                excludeSemantics: true,
                child: AnimatedOpacity(
                  opacity: editable && !drawing.isBlank ? 1 : 0.45,
                  duration: SkyMotion.fast,
                  child: SizedBox(
                    height: SkySizes.button,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SkyIcon(SkyIcons.refresh, size: 17, color: t.muted),
                          const SizedBox(width: 8),
                          Text(
                            SkyTogetherCopy.startOver,
                            style: SkyType.sans(13.5, weight: FontWeight.w600).copyWith(color: t.muted),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SkyButton(
                  key: SkyTogetherKeys.done,
                  label: SkyTogetherCopy.done,
                  icon: SkyIcons.check,
                  onPressed: editable && session.canFinish ? _done : null,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TogetherPill extends StatelessWidget {
  const _TogetherPill({required this.me, required this.partner});

  final String? me;
  final String partner;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    const size = 30.0;
    return ExcludeSemantics(
      child: Container(
        key: SkyTogetherKeys.pill,
        padding: const EdgeInsets.fromLTRB(4, 4, 9, 4),
        decoration: BoxDecoration(
          color: t.chip,
          borderRadius: SkyRadii.all(SkyRadii.pill),
          border: Border.all(color: t.chipBorder),
          boxShadow: t.softShadow,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: size * 2 - 7,
              height: size,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(left: 0, child: SkyAvatar(initial: SkyAvatar.initialOf(me, fallback: 'O'), size: size)),
                  Positioned(
                    left: size - 7,
                    child: SkyAvatar(initial: SkyAvatar.initialOf(partner), style: SkyAvatarStyle.partner, size: size),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: t.rose,
                boxShadow: [BoxShadow(color: t.rose, blurRadius: 8)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
