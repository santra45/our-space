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
import 'sky_heart_plan.dart';
import 'sky_letters_watch.dart';
import 'sky_marks.dart';
import 'sky_sheet_layout.dart';
import 'sky_stats.dart';

abstract final class SkyPageKeys {
  static const Key canvas = ValueKey<String>('sky-home-canvas');
  static const Key letterTip = ValueKey<String>('sky-letter-tip');
  static const Key tonightTip = ValueKey<String>('sky-tonight-tip');
  static const Key tonightAside = ValueKey<String>('sky-tonight-aside');
  static const Key presenceRing = ValueKey<String>('sky-presence-ring');
  static const Key myName = ValueKey<String>('sky-my-name');
  static const Key partnerName = ValueKey<String>('sky-partner-name');
  static const Key starsStat = ValueKey<String>('sky-stat-stars');
  static const Key milestoneStat = ValueKey<String>('sky-stat-milestone');
  static const Key lettersStat = ValueKey<String>('sky-stat-letters');
}

class OurSkyPage extends StatefulWidget {
  const OurSkyPage({super.key});

  static const double skyHeight = 484;
  static const double sheetTop = 444;
  static const double sheetTopMin = 404;
  static const Offset letterTipAt = Offset(140, 152);
  static const Rect letterTipArea = Rect.fromLTWH(140, 152, 166, 28);

  @override
  State<OurSkyPage> createState() => _OurSkyPageState();
}

class _OurSkyPageState extends State<OurSkyPage> with WidgetsBindingObserver {
  late final DailyQuestionModel _daily = DailyQuestionModel(context.space);
  late final SkyLettersWatch _letters;
  late final Listenable _changes = Listenable.merge([_daily, _letters]);
  bool _sheetOpen = false;
  bool _revealOpen = false;

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
    super.dispose();
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
    final start = SkyDays.startOf(startDate);
    final dayNumber = start == null ? null : SkyDays.dayNumber(start, now);
    final milestone = SkyDays.next(start ?? SkyDays.dateOnly(now), now);
    final weekday = DateFormat('EEEE').format(now);

    final loaded = _daily.visible || _daily.failed;
    final stars = _daily.stars;
    final litToday = _daily.bothIn;
    final waiting = _letters.waiting;
    final heart = SkyHeartPlan.home(stars: stars, litToday: litToday, presence: presence.isHere);
    final aside = SkyHeartPlan.tonightAside(stars: stars, litToday: litToday);
    final showTonight = _daily.visible && !litToday;
    final tonightAt = aside ? SkyHeartPlan.asideStar : (heart.gap == null ? null : heart.pointAt(heart.gap!));
    final avoid = [
      ...SkyHeartPlan.labelAreas(
        heart,
        me: me != null,
        partner: partner != null,
        partnerChip: presence.label != null,
      ),
      if (waiting > 0) OurSkyPage.letterTipArea,
    ];
    final tipTitle = SkyHomeCopy.tonightStar(night);
    final tipSubtitle = _daily.answered ? SkyHomeCopy.almostLit : SkyHomeCopy.answerToLight;
    final placement = tonightAt == null
        ? null
        : (aside
              ? SkyHeartPlan.below
              : SkyHeartPlan.tipFor(
                  tonightAt,
                  heart: heart,
                  avoid: avoid,
                  size: SkyHeartPlan.tipSizeFor(tipTitle, tipSubtitle),
                ));

    final anchors = <SkyAnchor>[
      if (loaded && presence.isHere && partner != null && !heart.isLit(heart.partner))
        const SkyAnchor(
          at: SkyPoint.partner(),
          alignment: Alignment.center,
          child: SkyPresenceRing(key: SkyPageKeys.presenceRing),
        ),
      if (loaded && me != null)
        SkyAnchor(
          at: const SkyPoint.me(),
          offset: const Offset(0, 18),
          child: SkyEntrance(child: SkyNameLabel(me, key: SkyPageKeys.myName)),
        ),
      if (loaded && partner != null)
        SkyAnchor(
          at: const SkyPoint.partner(),
          offset: const Offset(-12, 30),
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
      if (showTonight && aside)
        const SkyAnchor(
          at: SkyPoint.design(SkyHeartPlan.asideStar),
          alignment: Alignment.center,
          child: SkyTonightStar(key: SkyPageKeys.tonightAside),
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
              onTap: _answer,
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

    final sky = TweenAnimationBuilder<double>(
      tween: Tween<double>(end: loaded ? 1 : 0),
      duration: skyMotionAllowed(context) ? SkyMotion.slow : Duration.zero,
      curve: SkyMotion.gentle,
      builder: (context, dim, _) => SkyBackdrop(
        key: SkyPageKeys.canvas,
        scene: SkyScene.home.copyWith(
          heart: heart.copyWith(dim: dim),
          clearShootingStar: waiting == 0,
        ),
        anchors: anchors,
      ),
    );

    final stats = SkyStatsRow(
      stats: [
        SkyStat(
          key: SkyPageKeys.starsStat,
          icon: SkyIcons.star,
          value: SkyHomeCopy.stars(stars),
          label: SkyHomeCopy.starsLabel(stars),
          valueColor: t.gold,
          onTap: () => unawaited(_openSheet(archive: true)),
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
        top: SkyEntrance(
          child: SkyTopBar(
            kicker: SkyHomeCopy.kicker(night: night, dayNumber: dayNumber, weekday: weekday),
            title: SkyHomeCopy.title(night),
            trailing: const ShellAvatar(),
          ),
        ),
        sheet: sheet,
      ),
    );
  }
}
