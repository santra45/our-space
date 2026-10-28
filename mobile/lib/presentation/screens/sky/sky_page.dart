import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/engine.dart';
import '../../app_shell.dart';
import '../../sky/sky.dart';
import '../../space_scope.dart';
import '../daily/daily_question_card.dart';
import '../daily/daily_question_model.dart';
import '../daily/daily_question_sheet.dart';
import '../daily/daily_reveal_page.dart';
import 'sky_copy.dart';
import 'sky_days.dart';
import 'sky_constellation_plan.dart';
import 'sky_constellations.dart';
import 'sky_letters_watch.dart';
import 'sky_map_page.dart';
import 'sky_marks.dart';
import 'sky_night_sheet.dart';
import 'sky_sheet_layout.dart';
import 'sky_stats.dart';
import 'together/sky_keepsakes.dart';

abstract final class SkyPageKeys {
  static const Key canvas = ValueKey<String>('sky-home-canvas');
  static const Key letterTip = ValueKey<String>('sky-letter-tip');
  static const Key tonightTip = ValueKey<String>('sky-tonight-tip');
  static const Key reliveTip = ValueKey<String>('sky-relive-tip');
  static const Key starTouch = ValueKey<String>('sky-star-touch');
  static const Key presenceRing = ValueKey<String>('sky-presence-ring');
  static const Key myName = ValueKey<String>('sky-my-name');
  static const Key partnerName = ValueKey<String>('sky-partner-name');
  static const Key starsStat = ValueKey<String>('sky-stat-stars');
  static const Key milestoneStat = ValueKey<String>('sky-stat-milestone');
  static const Key lettersStat = ValueKey<String>('sky-stat-letters');

  static Key night(int number) => ValueKey<String>('sky-night-$number');
}

class OurSkyPage extends StatefulWidget {
  const OurSkyPage({super.key});

  static const double skyHeight = 484;
  static const double sheetTop = 444;
  static const double sheetTopMin = 404;
  static const Offset letterTipAt = Offset(140, 152);

  @override
  State<OurSkyPage> createState() => _OurSkyPageState();
}

class _OurSkyPageState extends State<OurSkyPage> with WidgetsBindingObserver {
  late final DailyQuestionModel _daily = DailyQuestionModel(context.space);
  late final SkyLettersWatch _letters;
  late final Listenable _changes = Listenable.merge([_daily, _letters]);
  final ValueNotifier<double?> _topBar = ValueNotifier<double?>(null);
  bool _sheetOpen = false;
  bool _revealOpen = false;
  bool _nightOpen = false;
  bool _mapOpen = false;
  bool? _relive;

  @override
  void initState() {
    super.initState();
    final space = context.space;
    _letters = SkyLettersWatch(space.letters, settings: space.store.settings);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    setState(() {});
    unawaited(_daily.refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _daily.dispose();
    _letters.dispose();
    _topBar.dispose();
    super.dispose();
  }

  void _measureTopBar(double height) {
    if (mounted) _topBar.value = height;
  }

  Future<void> _openSheet({bool archive = false}) async {
    if (_sheetOpen || !_daily.visible) return;
    _sheetOpen = true;
    final result = await showDailySheet(context, model: _daily, archive: archive);
    _sheetOpen = false;
    if (!mounted || result != DailySheetResult.lit) return;
    await _openReveal();
  }

  Future<void> _openReveal() async {
    if (_revealOpen || !mounted || !_daily.visible) return;
    _revealOpen = true;
    final scope = SkyShellScope.maybeOf(context);
    await skyPush<void>(
      context,
      (_) => DailyRevealPage(model: _daily, onSendLove: scope?.openLove),
      settings: const RouteSettings(name: DailyRevealPage.routeName),
    );
    _revealOpen = false;
  }

  Future<void> _openNight(StarNight night) async {
    if (_nightOpen || !mounted) return;
    _nightOpen = true;
    if (_relive == true) setState(() => _relive = false);
    final identity = context.read<IdentityController>();
    final result = await showStarNightSheet(
      context,
      night: night,
      partnerName: identity.partnerName,
      myName: identity.me != null ? identity.myName : null,
    );
    _nightOpen = false;
    if (!mounted || result != StarNightResult.everyDay) return;
    await _openSheet(archive: true);
  }

  Future<void> _openMap() async {
    if (_mapOpen || !mounted) return;
    _mapOpen = true;
    await openSkyMap(context, model: _daily);
    _mapOpen = false;
  }

  void _touchSky(Offset design, SkyConstellation constellation, ConstellationChapter chapter, double scale) {
    final slot = constellation.starAt(design, radius: SkyConstellation.hitRadius / scale);
    final night = slot == null ? null : chapter.nightAt(slot);
    if (night != null) unawaited(_openNight(night));
  }

  bool _reliveTip({required bool eligible}) {
    if (!eligible) return false;
    if (_relive != null) return _relive!;
    final settings = context.space.store.settings;
    final fresh = !StarNightTip.seen(settings);
    _relive = fresh;
    if (fresh) unawaited(StarNightTip.remember(settings).catchError((Object _) {}));
    return fresh;
  }

  void _answer() {
    if (_daily.bothIn) {
      unawaited(_openReveal());
      return;
    }
    unawaited(_openSheet());
  }

  void _select(SkyTab tab) => SkyShellScope.maybeOf(context)?.selectTab(tab);

  @override
  Widget build(BuildContext context) {
    final vault = context.watch<VaultService>();
    final identity = context.watch<IdentityController>();
    final scope = SkyShellScope.maybeOf(context);
    _daily.bindTo(vault: vault, identity: identity);
    final presence = scope?.presence ?? const PartnerPresence.unknown();
    final me = identity.me != null ? identity.myName : null;
    final partner = identity.partner != null ? identity.partnerName : null;
    final startDate = vault.config?.startDate;
    return ListenableBuilder(
      listenable: _changes,
      builder: (context, _) => _build(
        context,
        presence: presence,
        me: me,
        partner: partner,
        startDate: startDate,
      ),
    );
  }

  Widget _build(
    BuildContext context, {
    required PartnerPresence presence,
    required String? me,
    required String? partner,
    required String? startDate,
  }) {
    final t = context.sky;
    final night = t.isNight;
    final now = DateTime.now();
    final moonPhase = MoonPhase.tonight(now);
    final start = SkyDays.startOf(startDate);
    final dayNumber = start == null ? null : SkyDays.dayNumber(start, now);
    final milestone = SkyDays.next(start ?? SkyDays.dateOnly(now), now);
    final weekday = DateFormat('EEEE').format(now);

    final loaded = _daily.visible || _daily.failed;
    final stars = _daily.stars;
    final litToday = _daily.bothIn;
    final waiting = _letters.waiting;
    final series = ConstellationSeries.fromAnswered(_daily.nights, today: _daily.todayKey ?? dayKey());
    final constellation = SkyConstellationPlan.forSeries(series, presence: presence.isHere);
    final shape = constellation.shape;
    final showTonight = _daily.visible && !litToday;
    final tonightAt = constellation.gap == null ? null : constellation.pointAt(constellation.gap!);
    final scaler = MediaQuery.textScalerOf(context);
    final k = SkyPageFrame.scaleOf(MediaQuery.sizeOf(context).width);
    final letterTip = SkyTip.measure(SkyHomeCopy.letterFell, textScaler: scaler) / k;
    final avoid = [
      ...SkyConstellationPlan.labelAreas(
        constellation,
        me: me != null,
        partner: partner != null,
        partnerChip: presence.label != null,
      ),
      if (waiting > 0) OurSkyPage.letterTipAt & letterTip,
    ];
    final tipTitle = SkyHomeCopy.tonightStar(night);
    final tipSubtitle = _daily.answered ? SkyHomeCopy.almostLit : SkyHomeCopy.answerToLight;
    final tipSize = SkyTip.measureTwo(tipTitle, tipSubtitle, textScaler: scaler) / k;
    final placement = tonightAt == null
        ? null
        : SkyConstellationPlan.tipFor(tonightAt, constellation: constellation, avoid: avoid, size: tipSize);
    final chapter = series.current;
    final latest = chapter.latest;
    final relive = latest != null && _reliveTip(eligible: loaded && !showTonight);
    final reliveAt = latest != null && relive ? constellation.pointAt(latest.slot) : null;
    final reliveSize = SkyTip.measure(StarNightCopy.relive, textScaler: scaler) / k;
    final relivePlacement = reliveAt == null
        ? null
        : SkyConstellationPlan.tipFor(reliveAt, constellation: constellation, avoid: avoid, size: reliveSize);

    final anchors = <SkyAnchor>[
      if (loaded)
        for (final lit in chapter.nights)
          SkyAnchor(
            at: SkyPoint.star(lit.slot),
            alignment: Alignment.center,
            child: Semantics(
              key: SkyPageKeys.night(lit.number),
              button: true,
              label: StarNightCopy.title(lit),
              onTap: () => unawaited(_openNight(lit)),
              child: const SizedBox.square(dimension: SkyConstellation.hitRadius),
            ),
          ),
      if (loaded && presence.isHere && partner != null && !constellation.isLit(constellation.partner))
        const SkyAnchor(
          at: SkyPoint.partner(),
          alignment: Alignment.center,
          child: SkyPresenceRing(key: SkyPageKeys.presenceRing),
        ),
      if (loaded && me != null)
        SkyAnchor(
          at: const SkyPoint.me(),
          offset: shape.meLabel.offset,
          alignment: shape.meLabel.alignment,
          child: SkyEntrance(child: SkyNameLabel(me, key: SkyPageKeys.myName)),
        ),
      if (loaded && partner != null)
        SkyAnchor(
          at: const SkyPoint.partner(),
          offset: shape.partnerLabel.offset,
          alignment: shape.partnerLabel.alignment,
          child: SkyEntrance(
            index: 1,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SkyNameLabel(partner, key: SkyPageKeys.partnerName),
                if (presence.label != null) SkyHereChip(label: presence.label!, pulse: presence.isHere),
              ],
            ),
          ),
        ),
      if (showTonight && tonightAt != null && placement != null)
        SkyAnchor(
          at: SkyPoint.design(tonightAt),
          offset: placement.offset,
          alignment: placement.alignment,
          child: SkyEntrance(
            index: 2,
            child: SkyTip.two(
              key: SkyPageKeys.tonightTip,
              title: tipTitle,
              subtitle: tipSubtitle,
              icon: SkyIcons.sparkle,
              arrow: placement.arrow,
              tapAlignment: placement.alignment,
              onTap: _answer,
            ),
          ),
        ),
      if (latest != null && reliveAt != null && relivePlacement != null)
        SkyAnchor(
          at: SkyPoint.design(reliveAt),
          offset: relivePlacement.offset,
          alignment: relivePlacement.alignment,
          child: SkyEntrance(
            index: 2,
            child: SkyTip(
              key: SkyPageKeys.reliveTip,
              text: StarNightCopy.relive,
              icon: SkyIcons.star,
              tapAlignment: relivePlacement.alignment,
              onTap: () => unawaited(_openNight(latest)),
            ),
          ),
        ),
      if (waiting > 0)
        SkyAnchor(
          at: const SkyPoint.design(OurSkyPage.letterTipAt),
          alignment: Alignment.topLeft,
          child: SkyEntrance(
            delay: const Duration(milliseconds: 620),
            child: SkyTip(
              key: SkyPageKeys.letterTip,
              text: SkyHomeCopy.letterFell,
              icon: SkyIcons.letter,
              onTap: () => _select(SkyTab.letters),
            ),
          ),
        ),
    ];

    final skyLabel = SkyHomeCopy.skySemantics(
      stars: stars,
      night: night,
      lit: _daily.visible && litToday,
      waiting: showTonight,
      letters: waiting,
    );
    final backdrop = TweenAnimationBuilder<double>(
      tween: Tween<double>(end: loaded ? 1 : 0),
      duration: skyMotionAllowed(context) ? SkyMotion.slow : Duration.zero,
      curve: SkyMotion.gentle,
      builder: (context, dim, _) => SkyBackdrop(
        key: SkyPageKeys.canvas,
        scene: SkyScene.home.copyWith(
          moonPhase: moonPhase,
          constellation: constellation.copyWith(dim: dim),
          clearShootingStar: waiting == 0,
        ),
        anchors: anchors,
      ),
    );
    final keepsakes = SkyKeepsakes(
      constellation: constellation,
      topBar: _topBar,
      sky: const Size(SkyPageFrame.designWidth, OurSkyPage.skyHeight),
      sheetTop: OurSkyPage.sheetTopMin,
      avoid: [
        ...avoid,
        if (showTonight && tonightAt != null && placement != null)
          SkyConstellationPlan.tipRect(tonightAt, placement, tipSize),
        if (reliveAt != null && relivePlacement != null)
          SkyConstellationPlan.tipRect(reliveAt, relivePlacement, reliveSize),
      ],
      streak: waiting > 0 ? SkyScene.home.shootingStar : null,
      partner: partner,
      shown: loaded,
    );
    final sky = LayoutBuilder(
      builder: (context, box) {
        final scale = box.maxWidth.isFinite && box.maxWidth > 0 ? box.maxWidth / SkyPageFrame.designWidth : k;
        return GestureDetector(
          key: SkyPageKeys.starTouch,
          behavior: HitTestBehavior.translucent,
          onTapUp: loaded && chapter.started
              ? (details) => _touchSky(details.localPosition / scale, constellation, chapter, scale)
              : null,
          child: Semantics(
            container: true,
            image: true,
            label: skyLabel,
            child: Stack(fit: StackFit.expand, children: [backdrop, keepsakes]),
          ),
        );
      },
    );

    final stats = SkyStatsRow(
      stats: [
        SkyStat(
          key: SkyPageKeys.starsStat,
          icon: SkyIcons.star,
          value: SkyHomeCopy.stars(stars),
          label: SkyHomeCopy.starsLabel(stars),
          valueColor: t.gold,
          onTap: () => unawaited(_openMap()),
        ),
        SkyStat(
          key: SkyPageKeys.milestoneStat,
          icon: SkyIcons.moon,
          value: SkyHomeCopy.milestoneValue(milestone, night: night),
          label: SkyHomeCopy.milestoneLabel(milestone),
          valueColor: t.text,
          iconColor: night ? t.goldDeep : t.gold,
          onTap: () => _select(SkyTab.us),
        ),
        SkyStat(
          key: SkyPageKeys.lettersStat,
          icon: SkyIcons.letter,
          value: SkyHomeCopy.letters(waiting),
          label: SkyHomeCopy.waitingToOpen,
          valueColor: t.rose,
          onTap: () => _select(SkyTab.letters),
        ),
      ],
    );

    final sheet = SkyEntrance(
      index: 1,
      offset: const Offset(0, 40),
      child: SkyPanel(
        padding: EdgeInsets.fromLTRB(
          SkySpace.gutter,
          0,
          SkySpace.gutter,
          MediaQuery.paddingOf(context).bottom + SkySpace.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SkyEntrance(index: 2, child: stats),
            const SizedBox(height: 10),
            SkyEntrance(
              index: 3,
              child: DailyQuestionCard(
                model: _daily,
                dayNumber: dayNumber,
                onAnswer: _answer,
                onReveal: () => unawaited(_openReveal()),
              ),
            ),
          ],
        ),
      ),
    );

    return SkyScaffold(
      showSky: false,
      body: SkyPageFrame(
        skyHeight: OurSkyPage.skyHeight,
        minSheetTop: OurSkyPage.sheetTopMin,
        maxSheetTop: OurSkyPage.sheetTop,
        sky: sky,
        top: SkyHeightProbe(
          onHeight: _measureTopBar,
          child: SkyEntrance(
            child: SkyTopBar(
              kicker: SkyHomeCopy.kicker(night: night, dayNumber: dayNumber, weekday: weekday),
              note: night ? SkyHomeCopy.moonLine(moonPhase) : null,
              title: SkyHomeCopy.title(night),
              trailing: const ShellAvatar(),
            ),
          ),
        ),
        sheet: sheet,
      ),
    );
  }
}
