import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/engine.dart';
import '../../sky/sky.dart';
import '../daily/daily_copy.dart';
import '../daily/daily_question_model.dart';
import 'sky_constellations.dart';
import 'sky_map_detail.dart';
import 'sky_map_plan.dart';
import 'sky_night_sheet.dart';

Future<void> openSkyMap(BuildContext context, {required DailyQuestionModel model}) => skyPush<void>(
  context,
  (_) => SkyMapPage(model: model),
  settings: const RouteSettings(name: SkyMapPage.routeName),
);

class SkyMapPage extends StatefulWidget {
  const SkyMapPage({super.key, required this.model});

  static const String routeName = '/sky/map';

  static const SkyScene scene = SkyScene(
    stars: 50,
    moon: Offset(326, 96),
    sun: false,
    clouds: [SkyCloud(312, 104, scale: 0.9, opacity: 0.85), SkyCloud(60, 236, scale: 0.6, opacity: 0.5)],
  );

  final DailyQuestionModel model;

  @override
  State<SkyMapPage> createState() => _SkyMapPageState();
}

class _SkyMapPageState extends State<SkyMapPage> {
  bool _opening = false;
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

  Future<void> _open(int index) async {
    if (_opening || !mounted) return;
    _opening = true;
    await skyPush<void>(
      context,
      (_) => SkyMapConstellationPage(model: model, index: index),
      settings: const RouteSettings(name: SkyMapConstellationPage.routeName),
    );
    _opening = false;
  }

  Future<void> _everyDay() async {
    if (_opening || !mounted) return;
    _opening = true;
    await openEveryDay(context, model);
    _opening = false;
  }

  @override
  Widget build(BuildContext context) {
    final unlocked = context.watch<VaultService>().isUnlocked;
    if (!unlocked) {
      _leaveSoon();
      return const SkyScaffold(showSky: false, body: SizedBox.shrink());
    }
    return ListenableBuilder(listenable: model, builder: (context, _) => _build(context));
  }

  Widget _build(BuildContext context) {
    final t = context.sky;
    final series = skyMapSeries(model);
    final entries = SkyMapPlan.entriesOf(series);
    final growing = entries.growing;
    final children = <Widget>[];

    if (entries.isEmpty) {
      if (model.failed) {
        children.add(SkyErrorState(onRetry: () => unawaited(model.retry())));
      } else if (model.loading) {
        children.add(const Padding(padding: EdgeInsets.all(40), child: Center(child: SkySpinner())));
      } else {
        children.add(SkyMapEmpty(key: SkyMapKeys.empty, night: t.isNight));
      }
    } else if (growing != null) {
      children.add(
        SkyMapGrowingCard(
          key: SkyMapKeys.growing,
          chapter: growing,
          constellation: SkyMapPlan.figure(growing, litToday: series.litToday),
          onTap: () => unawaited(_open(growing.index)),
        ),
      );
    }

    if (model.visible) {
      children.add(
        SkyListGroup(
          children: [
            SkyListRow(
              key: SkyMapKeys.everyDay,
              title: DailyCopy.everyDay,
              subtitle: SkyMapCopy.everyDayNote,
              icon: SkyIcons.calendar,
              tone: SkyTone.lavender,
              onTap: () => unawaited(_everyDay()),
            ),
          ],
        ),
      );
    }

    if (entries.finished.isNotEmpty) {
      children.add(
        const Padding(
          key: SkyMapKeys.finished,
          padding: EdgeInsets.fromLTRB(4, SkySpace.sm, 4, 0),
          child: SkyLabel(SkyMapCopy.finished, icon: SkyIcons.star, tone: SkyTone.gold),
        ),
      );
      for (final chapter in entries.finished) {
        children.add(
          SkyMapCard(
            key: SkyMapKeys.constellation(chapter.index),
            chapter: chapter,
            constellation: SkyMapPlan.figure(chapter, litToday: false),
            onTap: () => unawaited(_open(chapter.index)),
          ),
        );
      }
    } else if (growing != null) {
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: SkySpace.lg),
          child: Text(
            SkyMapCopy.keepNote,
            key: SkyMapKeys.keepNote,
            textAlign: TextAlign.center,
            style: SkyType.caption.copyWith(color: t.faint),
          ),
        ),
      );
    }

    return SkyScrollScaffold(
      key: SkyMapKeys.page,
      scene: SkyMapPage.scene,
      topBar: SkyTopBar(
        compact: true,
        leading: const SkyBackButton(),
        kicker: SkyMapCopy.kicker(series.stars),
        title: SkyMapCopy.title,
      ),
      padding: const EdgeInsets.fromLTRB(SkySpace.gutter, SkySpace.xl, SkySpace.gutter, 0),
      children: children,
    );
  }
}

class SkyMapWindow extends StatelessWidget {
  const SkyMapWindow({
    super.key,
    required this.constellation,
    required this.height,
    this.width,
    this.designWidth = 390,
    this.stars = 24,
    this.seed = 7,
    this.margin = 24,
    this.radius = SkyRadii.md,
    this.glow = false,
  });

  final SkyConstellation constellation;
  final double height;
  final double? width;
  final double designWidth;
  final int stars;
  final int seed;
  final double margin;
  final double radius;
  final bool glow;

  static int seedFor(int index) => 7 + index * 13;

  @override
  Widget build(BuildContext context) {
    const night = SkyTokens.night;
    final scene = SkyScene(
      seed: seed,
      stars: stars,
      dayStars: 0,
      sun: false,
      clouds: const [],
      twinkle: false,
      designWidth: designWidth,
    );
    final ghost = SkyMapPlan.ghostOf(constellation);
    return Theme(
      data: SkyThemes.legacy(night),
      child: Container(
        width: width,
        height: height,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: night.skyTop, borderRadius: SkyRadii.all(radius)),
        foregroundDecoration: BoxDecoration(
          borderRadius: SkyRadii.all(radius),
          border: Border.all(color: night.gold.withValues(alpha: glow ? 0.3 : 0.14)),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(
              child: CustomPaint(
                painter: SkyBackdropPainter(scene: scene, tokens: night),
                isComplex: true,
              ),
            ),
            if (ghost != null) SkyConstellationView(constellation: ghost, margin: margin, designWidth: designWidth),
            SkyConstellationView(constellation: constellation, margin: margin, designWidth: designWidth),
          ],
        ),
      ),
    );
  }
}

class SkyMapPill extends StatelessWidget {
  const SkyMapPill({super.key, required this.text, this.icon});

  final String text;
  final SkyIcons? icon;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final ink = t.isNight ? t.gold : t.goldDeep;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: t.goldSoft,
        borderRadius: SkyRadii.all(SkyRadii.pill),
        border: Border.all(color: t.gold.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[SkyIcon(icon!, size: 11, color: ink), const SizedBox(width: 5)],
          Flexible(
            child: Text(text, style: SkyType.sans(11.5, weight: FontWeight.w700, height: 1.2).copyWith(color: ink)),
          ),
        ],
      ),
    );
  }
}

class SkyMapGrowingCard extends StatelessWidget {
  const SkyMapGrowingCard({super.key, required this.chapter, required this.constellation, this.onTap});

  final ConstellationChapter chapter;
  final SkyConstellation constellation;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final range = StarNightCopy.range(chapter);
    return SkyPressable(
      onTap: onTap,
      pressedScale: 0.98,
      semanticLabel: SkyMapCopy.card(chapter),
      excludeSemantics: true,
      child: SkyFeatureCard(
        accent: SkyAccent.gold,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SkyMapWindow(
              constellation: constellation,
              height: 180,
              stars: 40,
              seed: SkyMapWindow.seedFor(chapter.index),
              glow: true,
            ),
            const SizedBox(height: 14),
            SkyLabel(chapter.title, icon: SkyIcons.sparkle, tone: SkyTone.rose),
            const SizedBox(height: 6),
            Text(chapter.name, style: SkyType.serif(24, weight: FontWeight.w500, height: 1.15).copyWith(color: t.text)),
            const SizedBox(height: 8),
            Wrap(
              spacing: SkySpace.sm,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SkyMapPill(text: SkyMapCopy.status(chapter)),
                if (range.isNotEmpty) Text(range, style: SkyType.small.copyWith(color: t.muted)),
              ],
            ),
            const SizedBox(height: 14),
            SkyProgressBar(value: chapter.lit / ConstellationChapter.size),
          ],
        ),
      ),
    );
  }
}

class SkyMapCard extends StatelessWidget {
  const SkyMapCard({super.key, required this.chapter, required this.constellation, this.onTap});

  static const Size windowSize = Size(108, 96);

  final ConstellationChapter chapter;
  final SkyConstellation constellation;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final range = StarNightCopy.range(chapter);
    return SkyPressable(
      onTap: onTap,
      pressedScale: 0.98,
      semanticLabel: SkyMapCopy.card(chapter),
      excludeSemantics: true,
      child: SkyCard(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            SkyMapWindow(
              constellation: constellation,
              width: windowSize.width,
              height: windowSize.height,
              designWidth: 250,
              stars: 16,
              margin: 20,
              seed: SkyMapWindow.seedFor(chapter.index),
              glow: true,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SkyLabel(chapter.title, tone: SkyTone.gold),
                  const SizedBox(height: 4),
                  Text(chapter.name, style: SkyType.serif(20, weight: FontWeight.w500, height: 1.2).copyWith(color: t.text)),
                  if (range.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(range, style: SkyType.small.copyWith(color: t.muted)),
                  ],
                  const SizedBox(height: SkySpace.sm),
                  SkyMapPill(text: SkyMapCopy.nights(chapter.lit), icon: SkyIcons.star),
                ],
              ),
            ),
            const SizedBox(width: 6),
            SkyIcon(SkyIcons.chevron, size: 15, color: t.muted),
          ],
        ),
      ),
    );
  }
}

class SkyMapEmpty extends StatelessWidget {
  const SkyMapEmpty({super.key, required this.night});

  final bool night;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    return SkyCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SkyMapWindow(constellation: SkyMapPlan.waiting(), height: 156, stars: 30, seed: 5),
          const SizedBox(height: SkySpace.lg),
          Text(
            SkyMapCopy.emptyTitle,
            textAlign: TextAlign.center,
            style: SkyType.serif(20, weight: FontWeight.w500).copyWith(color: t.text),
          ),
          const SizedBox(height: 6),
          Text(
            SkyMapCopy.emptyMessage(night: night),
            textAlign: TextAlign.center,
            style: SkyType.bodySmall.copyWith(color: t.muted),
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

class SkyMapLink extends StatelessWidget {
  const SkyMapLink({super.key, required this.onTap, this.compact = false});

  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final star = SkyIcon(SkyIcons.star, size: compact ? 16 : 13, color: t.isNight ? t.gold : t.goldDeep);
    return SkyPressable(
      onTap: onTap,
      semanticLabel: SkyMapCopy.action,
      excludeSemantics: true,
      child: SkyTapTarget(
        minWidth: SkySizes.minTap,
        child: compact
            ? star
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  star,
                  const SizedBox(width: 5),
                  Text(SkyMapCopy.action, style: SkyType.sans(12, weight: FontWeight.w600).copyWith(color: t.rose)),
                ],
              ),
      ),
    );
  }
}
