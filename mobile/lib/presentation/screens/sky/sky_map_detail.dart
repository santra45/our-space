import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/engine.dart';
import '../../sky/sky.dart';
import '../../widgets/app_haptics.dart';
import '../daily/daily_question_model.dart';
import '../daily/daily_question_sheet.dart';
import '../daily/daily_reveal_page.dart';
import 'sky_constellations.dart';
import 'sky_map_plan.dart';
import 'sky_night_sheet.dart';

ConstellationSeries skyMapSeries(DailyQuestionModel model) =>
    ConstellationSeries.fromAnswered(model.nights, today: model.todayKey ?? dayKey());

Future<void> openEveryDay(BuildContext context, DailyQuestionModel model) async {
  if (!model.visible) return;
  final result = await showDailySheet(context, model: model, archive: true);
  if (!context.mounted || result != DailySheetResult.lit || !model.visible) return;
  await skyPush<void>(
    context,
    (_) => DailyRevealPage(model: model),
    settings: const RouteSettings(name: DailyRevealPage.routeName),
  );
}

class SkyMapGhost extends StatefulWidget {
  const SkyMapGhost({super.key, required this.constellation, this.designWidth = 390});

  final SkyConstellation constellation;
  final double designWidth;

  @override
  State<SkyMapGhost> createState() => _SkyMapGhostState();
}

class _SkyMapGhostState extends State<SkyMapGhost> {
  final SkyTime _time = SkyTime();

  @override
  void dispose() {
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scene = SkyScene(
      stars: 0,
      dayStars: 0,
      sun: false,
      clouds: const [],
      haze: false,
      twinkle: false,
      constellation: widget.constellation,
      designWidth: widget.designWidth,
    );
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(painter: SkyLivePainter(scene: scene, tokens: context.sky, time: _time)),
      ),
    );
  }
}

class SkyMapConstellationPage extends StatefulWidget {
  const SkyMapConstellationPage({super.key, required this.model, required this.index});

  static const String routeName = '/sky/map/constellation';
  static const double topRoom = 150;
  static const double bottomRoom = 130;

  final DailyQuestionModel model;
  final int index;

  static SkyScene sceneFor(SkyConstellation figure, {required double designWidth, required double designHeight}) =>
      SkyScene(
        seed: 11,
        stars: 90,
        moon: Offset(designWidth - 60, 126),
        clouds: [
          SkyCloud(designWidth - 74, 118, scale: 0.9, opacity: 0.8),
          SkyCloud(56, math.max(260, designHeight - 170), scale: 0.7, opacity: 0.55),
        ],
        constellation: figure,
        designWidth: designWidth,
      );

  @override
  State<SkyMapConstellationPage> createState() => _SkyMapConstellationPageState();
}

class _SkyMapConstellationPageState extends State<SkyMapConstellationPage> {
  bool _nightOpen = false;
  bool _leaving = false;

  DailyQuestionModel get model => widget.model;

  void _leaveSoon() {
    if (_leaving) return;
    _leaving = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ModalRoute.of(context)?.isCurrent ?? false) Navigator.of(context).maybePop();
    });
  }

  Future<void> _openNight(StarNight night) async {
    if (_nightOpen || !mounted) return;
    _nightOpen = true;
    final identity = context.read<IdentityController>();
    final result = await showStarNightSheet(
      context,
      night: night,
      partnerName: identity.partnerName,
      myName: identity.me != null ? identity.myName : null,
    );
    _nightOpen = false;
    if (!mounted || result != StarNightResult.everyDay) return;
    await openEveryDay(context, model);
  }

  void _touch(Offset design, SkyConstellation figure, ConstellationChapter chapter, double scale) {
    final slot = figure.starAt(design, radius: SkyConstellation.hitRadius / scale);
    final night = slot == null ? null : chapter.nightAt(slot);
    if (night == null) return;
    AppHaptics.tick();
    unawaited(_openNight(night));
  }

  @override
  Widget build(BuildContext context) {
    final unlocked = context.watch<VaultService>().isUnlocked;
    final identity = context.watch<IdentityController>();
    if (!unlocked) {
      _leaveSoon();
      return const SkyScaffold(showSky: false, body: SizedBox.shrink());
    }
    final me = identity.me != null ? identity.myName : null;
    final partner = identity.partner != null ? identity.partnerName : null;
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) => _build(context, me: me, partner: partner),
    );
  }

  Widget _build(BuildContext context, {required String? me, required String? partner}) {
    final t = context.sky;
    final media = MediaQuery.of(context);
    final motion = skyMotionAllowed(context);
    final series = skyMapSeries(model);
    final chapter = series.chapter(widget.index);
    final base = SkyMapPlan.figure(chapter, litToday: series.litToday);
    final shape = chapter.shape;
    final range = StarNightCopy.range(chapter);

    final sky = LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        final k = SkyMapPlan.scaleOf(size.width);
        final designWidth = size.width / k;
        final designHeight = size.height / k;
        final frame = SkyMapPlan.frameFor(
          size,
          media.viewPadding,
          top: SkyMapConstellationPage.topRoom,
          bottom: SkyMapConstellationPage.bottomRoom,
        );
        final figure = SkyMapPlan.fit(base, frame, names: me != null || partner != null);
        final ghost = SkyMapPlan.ghostOf(figure);
        final anchors = <SkyAnchor>[
          for (final night in chapter.nights)
            SkyAnchor(
              at: SkyPoint.star(night.slot),
              alignment: Alignment.center,
              child: Semantics(
                key: SkyMapKeys.night(night.number),
                button: true,
                label: StarNightCopy.title(night),
                onTap: () => unawaited(_openNight(night)),
                child: const SizedBox.square(dimension: SkyConstellation.hitRadius),
              ),
            ),
          if (me != null && figure.isLit(figure.me))
            SkyAnchor(
              at: const SkyPoint.me(),
              offset: shape.meLabel.offset,
              alignment: shape.meLabel.alignment,
              child: SkyEntrance(index: 1, child: SkyNameLabel(me, key: SkyMapKeys.myName)),
            ),
          if (partner != null && figure.isLit(figure.partner))
            SkyAnchor(
              at: const SkyPoint.partner(),
              offset: shape.partnerLabel.offset,
              alignment: shape.partnerLabel.alignment,
              child: SkyEntrance(index: 1, child: SkyNameLabel(partner, key: SkyMapKeys.partnerName)),
            ),
        ];
        return GestureDetector(
          key: SkyMapKeys.starTouch,
          behavior: HitTestBehavior.translucent,
          onTapUp: chapter.started ? (details) => _touch(details.localPosition / k, figure, chapter, k) : null,
          child: Semantics(
            container: true,
            image: true,
            label: SkyMapCopy.sky(chapter),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: motion ? 0 : 1, end: 1),
              duration: motion ? SkyMotion.slow : Duration.zero,
              curve: SkyMotion.gentle,
              builder: (context, dim, _) => Stack(
                fit: StackFit.expand,
                children: [
                  SkyBackdrop(
                    key: SkyMapKeys.canvas,
                    scene: SkyMapConstellationPage.sceneFor(
                      figure.copyWith(dim: dim),
                      designWidth: designWidth,
                      designHeight: designHeight,
                    ),
                    anchors: anchors,
                  ),
                  if (ghost != null)
                    SkyMapGhost(
                      key: SkyMapKeys.ghost,
                      constellation: ghost.copyWith(dim: ghost.dim * dim),
                      designWidth: designWidth,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );

    final status = Container(
      key: SkyMapKeys.status,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: t.chip,
        borderRadius: SkyRadii.all(SkyRadii.pill),
        border: Border.all(color: t.chipBorder),
        boxShadow: t.softShadow,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SkyIcon(SkyIcons.star, size: 13, color: t.isNight ? t.gold : t.goldDeep),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              SkyMapCopy.status(chapter),
              style: SkyType.sans(12, weight: FontWeight.w700, height: 1.2).copyWith(color: t.text),
            ),
          ),
        ],
      ),
    );

    return SkyScaffold(
      key: SkyMapKeys.detail,
      showSky: false,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: sky),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SkyEntrance(
              child: SkyTopBar(
                compact: true,
                leading: const SkyBackButton(),
                kicker: chapter.title,
                note: range.isEmpty ? null : range,
                title: chapter.name,
              ),
            ),
          ),
          Positioned(
            left: SkySpace.gutter,
            right: SkySpace.gutter,
            bottom: media.viewPadding.bottom + SkySpace.xl,
            child: IgnorePointer(
              child: SkyEntrance(
                index: 2,
                offset: const Offset(0, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    status,
                    if (chapter.started) ...[
                      const SizedBox(height: SkySpace.sm),
                      Text(
                        StarNightCopy.relive,
                        textAlign: TextAlign.center,
                        style: SkyType.caption.copyWith(color: t.muted),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
