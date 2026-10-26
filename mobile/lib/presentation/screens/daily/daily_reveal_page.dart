import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/engine.dart';
import '../../sky/sky.dart';
import '../love/love_sheet.dart';
import '../sky/sky_days.dart';
import '../sky/sky_constellation_plan.dart';
import '../sky/sky_map_page.dart';
import '../sky/sky_map_plan.dart';
import '../sky/sky_sheet_layout.dart';
import 'daily_answer_card.dart';
import 'daily_copy.dart';
import 'daily_question_card.dart';
import 'daily_question_model.dart';
import 'daily_question_sheet.dart';

class DailyRevealButton extends StatelessWidget {
  const DailyRevealButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primary = false,
  });

  final String label;
  final SkyIcons icon;
  final VoidCallback onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final fg = primary ? SkyTokens.white : t.text;
    final decoration = primary
        ? BoxDecoration(
            gradient: t.primaryGradient,
            borderRadius: SkyRadii.all(SkyRadii.button),
            boxShadow: t.primaryShadow,
          )
        : BoxDecoration(
            color: t.chip,
            borderRadius: SkyRadii.all(SkyRadii.button),
            border: Border.all(color: t.chipBorder),
          );
    return SkyPressable(
      onTap: onPressed,
      semanticLabel: label,
      excludeSemantics: true,
      child: Container(
        height: SkySizes.button,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: decoration,
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SkyIcon(icon, size: 17, color: fg),
                const SizedBox(width: 8),
                Text(label, maxLines: 1, style: SkyType.button.copyWith(color: fg)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DailyRevealPage extends StatefulWidget {
  const DailyRevealPage({super.key, required this.model, this.onSendLove});

  static const String routeName = '/sky/reveal';
  static const double skyHeight = 420;
  static const double sheetTop = 360;
  static const Offset badgeAt = Offset(195, 314);
  static const SkyConstellation constellationBase = SkyConstellation(center: Offset(195, 206), scale: 5.1);

  final DailyQuestionModel model;
  final VoidCallback? onSendLove;

  static SkyScene sceneFor(int stars) => SkyScene(
    moon: const Offset(330, 120),
    sunAt: const Offset(30, 380),
    clouds: const [SkyCloud(322, 120, scale: 0.9, opacity: 0.8), SkyCloud(52, 200, scale: 0.6, opacity: 0.55)],
    constellation: SkyConstellationPlan.reveal(stars: stars, base: constellationBase),
  );

  @override
  State<DailyRevealPage> createState() => _DailyRevealPageState();
}

class _DailyRevealPageState extends State<DailyRevealPage> {
  bool _leaving = false;
  bool _sheetOpen = false;
  bool _mapOpen = false;

  DailyQuestionModel get model => widget.model;

  Future<void> _skyMap() async {
    if (_mapOpen) return;
    _mapOpen = true;
    await openSkyMap(context, model: model);
    _mapOpen = false;
  }

  void _leaveSoon() {
    if (_leaving) return;
    _leaving = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ModalRoute.of(context)?.isCurrent ?? false) Navigator.of(context).maybePop();
    });
  }

  Future<void> _everyDay() async {
    if (_sheetOpen) return;
    _sheetOpen = true;
    await showDailySheet(context, model: model, archive: true);
    _sheetOpen = false;
  }

  void _sendLove() {
    final handler = widget.onSendLove;
    if (handler != null) {
      handler();
      return;
    }
    unawaited(showLoveSheet(context));
  }

  @override
  Widget build(BuildContext context) {
    final vault = context.watch<VaultService>();
    final identity = context.watch<IdentityController>();
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        final today = model.today;
        final mine = model.day?.mine;
        if (!model.visible || today == null || mine == null) {
          _leaveSoon();
          return const SkyScaffold(showSky: false, body: SizedBox.shrink());
        }
        final t = context.sky;
        final night = t.isNight;
        final stars = math.max(model.stars, 1);
        final start = SkyDays.startOf(vault.config?.startDate);
        final dayNumber = start == null ? null : SkyDays.dayNumber(start, DateTime.now());
        final partner = identity.partnerName;
        final theirs = model.day?.partnerAnswer;
        final media = MediaQuery.of(context);
        final complete = SkyConstellationPlan.completes(stars);
        final badgeText = complete ? SkyConstellationPlan.completeLine(stars) : DailyCopy.starIsLit(night);

        final badge = Semantics(
          liveRegion: true,
          label: badgeText,
          excludeSemantics: true,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
            decoration: BoxDecoration(
              color: t.activeBg,
              borderRadius: SkyRadii.all(SkyRadii.pill),
              boxShadow: [BoxShadow(color: t.activeGlow, offset: const Offset(0, 8), blurRadius: 20)],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SkyIcon(SkyIcons.sparkle, size: 13, color: t.activeFg),
                const SizedBox(width: 6),
                Text(
                  badgeText,
                  style: SkyType.sans(11.5, weight: FontWeight.w700, height: 1.2).copyWith(color: t.activeFg),
                ),
              ],
            ),
          ),
        );

        final top = Padding(
          padding: EdgeInsets.fromLTRB(SkySpace.gutter, media.viewPadding.top + 10, SkySpace.gutter, 0),
          child: SkyEntrance(
            child: Row(
              children: [
                const SkyBackButton(),
                Expanded(
                  child: Text(
                    DailyCopy.revealKicker(night: night, dayNumber: dayNumber, stars: stars).toUpperCase(),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.skyText.kicker,
                  ),
                ),
                const SizedBox(width: SkySizes.iconButton),
              ],
            ),
          ),
        );

        final sheet = SkyEntrance(
          index: 1,
          offset: const Offset(0, 40),
          child: SkyPanel(
            padding: EdgeInsets.fromLTRB(SkySpace.gutter, 0, SkySpace.gutter, media.padding.bottom + SkySpace.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const SkyLabel(DailyCopy.bothAnswered, icon: SkyIcons.sparkle, tone: SkyTone.rose),
                const SizedBox(height: SkySpace.sm),
                Semantics(
                  header: true,
                  child: Text(DailyCopy.quoted(today.question.text), style: SkyType.serifLarge.copyWith(color: t.text)),
                ),
                const SizedBox(height: 14),
                ...skyStaggered(startIndex: 2, [
                  theirs != null
                      ? DailyAnswerCard(
                          name: capitalized(partner),
                          initial: SkyAvatar.initialOf(partner),
                          text: theirs.text,
                          time: DailyCopy.answeredAt(theirs.answeredAt),
                          partner: true,
                        )
                      : DailyWaitingCard(message: DailyCopy.nothingYet(partner)),
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: DailyAnswerCard(
                      name: DailyCopy.you,
                      initial: SkyAvatar.initialOf(identity.me != null ? identity.myName : null, fallback: 'Y'),
                      text: mine.text,
                      time: DailyCopy.answeredAt(mine.answeredAt),
                    ),
                  ),
                  if (complete)
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: SkyButton(
                        key: SkyMapKeys.fromReveal,
                        label: SkyMapCopy.seeInMap,
                        icon: SkyIcons.star,
                        variant: SkyButtonVariant.gold,
                        onPressed: () => unawaited(_skyMap()),
                      ),
                    ),
                  Padding(
                    padding: EdgeInsets.only(top: complete ? 10 : 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: DailyRevealButton(
                            key: DailyKeys.everyDay,
                            label: DailyCopy.everyDay,
                            icon: SkyIcons.calendar,
                            onPressed: () => unawaited(_everyDay()),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DailyRevealButton(
                            key: DailyKeys.sendLove,
                            label: DailyCopy.sendLoveBack,
                            icon: SkyIcons.heart,
                            primary: true,
                            onPressed: _sendLove,
                          ),
                        ),
                      ],
                    ),
                  ),
                ]),
              ],
            ),
          ),
        );

        return SkyScaffold(
          key: DailyKeys.reveal,
          showSky: false,
          body: SkyPageFrame(
            skyHeight: DailyRevealPage.skyHeight,
            maxSheetTop: DailyRevealPage.sheetTop,
            top: top,
            sky: SkyBackdrop(
              scene: DailyRevealPage.sceneFor(stars),
              anchors: [
                SkyAnchor(
                  at: const SkyPoint.design(DailyRevealPage.badgeAt),
                  child: SkyEntrance(delay: const Duration(milliseconds: 520), offset: const Offset(0, 10), child: badge),
                ),
              ],
            ),
            sheet: sheet,
          ),
        );
      },
    );
  }
}
