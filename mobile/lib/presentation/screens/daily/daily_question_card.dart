import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/engine.dart';
import '../../sky/sky.dart';
import '../sky/sky_copy.dart';
import 'daily_copy.dart';
import 'daily_question_model.dart';

enum DailyCardState { open, waiting, answered, lit }

abstract final class DailyKeys {
  static const Key card = ValueKey<String>('daily-card');
  static const Key status = ValueKey<String>('daily-status');
  static const Key action = ValueKey<String>('daily-action');
  static const Key sheet = ValueKey<String>('daily-sheet');
  static const Key reveal = ValueKey<String>('daily-reveal');
  static const Key answerField = ValueKey<String>('daily-answer-field');
  static const Key submit = ValueKey<String>('daily-submit');
  static const Key everyDay = ValueKey<String>('daily-every-day');
  static const Key sendLove = ValueKey<String>('daily-send-love');
}

DailyCardState dailyCardState(DailyQuestionModel model) {
  if (model.bothIn) return DailyCardState.lit;
  if (model.answered) return DailyCardState.answered;
  if (model.partnerWaiting) return DailyCardState.waiting;
  return DailyCardState.open;
}

class DailyQuestionCard extends StatelessWidget {
  const DailyQuestionCard({
    super.key,
    required this.model,
    required this.onAnswer,
    required this.onReveal,
    this.dayNumber,
  });

  final DailyQuestionModel model;
  final VoidCallback onAnswer;
  final VoidCallback onReveal;
  final int? dayNumber;

  static const LinearGradient daySheetGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFBFAFF), Color(0xFFF5F4FE)],
  );

  static Gradient? gradientFor(SkyTokens t) => t.isDay ? daySheetGradient : null;

  @override
  Widget build(BuildContext context) {
    final identity = context.watch<IdentityController>();
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        if (model.failed) {
          return SkyNotice(
            key: const ValueKey<String>('daily-failed'),
            text: DailyCopy.loadFailed,
            tone: SkyNoticeTone.error,
            actionLabel: DailyCopy.tryAgain,
            onAction: () => unawaited(model.retry()),
          );
        }
        final today = model.today;
        if (!model.visible || today == null) {
          if (!model.loading) return const SizedBox.shrink();
          return const _FindingCard();
        }
        final night = context.sky.isNight;
        final state = dailyCardState(model);
        return SkyCard(
          key: DailyKeys.card,
          gradient: DailyQuestionCard.gradientFor(context.sky),
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: SkyLabel(DailyCopy.questionLabel(night), icon: SkyIcons.sparkle, tone: SkyTone.rose),
                  ),
                  if (dayNumber != null)
                    Text(
                      SkyHomeCopy.dayOfForever(dayNumber!),
                      style: SkyType.sans(10, height: 1.3).copyWith(color: context.sky.muted),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(DailyCopy.quoted(today.question.text), style: SkyType.serifBody.copyWith(color: context.sky.text)),
              const SizedBox(height: 10),
              _Swap(
                child: DailyStatusRow(
                  key: ValueKey<DailyCardState>(state),
                  state: state,
                  status: DailyCopy.status(
                    bothIn: model.bothIn,
                    answered: model.answered,
                    partnerWaiting: model.partnerWaiting,
                    night: night,
                    partnerName: identity.partnerName,
                    partnerPossessive: identity.partnerPossessive,
                    partnerGrammar: identity.partnerGrammar,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _Swap(
                child: KeyedSubtree(key: ValueKey<String>('daily-action-${state.name}'), child: _action(state, night)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _action(DailyCardState state, bool night) {
    switch (state) {
      case DailyCardState.open:
      case DailyCardState.waiting:
        return SkyButton(
          key: DailyKeys.action,
          label: DailyCopy.lightStar(night),
          icon: SkyIcons.sparkle,
          height: 44,
          onPressed: onAnswer,
        );
      case DailyCardState.answered:
        return SkyButton(
          key: DailyKeys.action,
          label: DailyCopy.seeYours,
          icon: SkyIcons.pen,
          variant: SkyButtonVariant.ghost,
          height: 44,
          onPressed: onAnswer,
        );
      case DailyCardState.lit:
        return SkyButton(
          key: DailyKeys.action,
          label: DailyCopy.readBoth,
          icon: SkyIcons.star,
          variant: SkyButtonVariant.gold,
          height: 44,
          onPressed: onReveal,
        );
    }
  }
}

class _Swap extends StatelessWidget {
  const _Swap({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!skyMotionAllowed(context)) return child;
    return AnimatedSwitcher(
      duration: SkyMotion.medium,
      switchInCurve: SkyMotion.standard,
      switchOutCurve: Curves.easeIn,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, ?current],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(scale: Tween<double>(begin: 0.97, end: 1).animate(animation), child: child),
      ),
      child: child,
    );
  }
}

class DailyStatusRow extends StatelessWidget {
  const DailyStatusRow({super.key, required this.state, required this.status});

  final DailyCardState state;
  final DailyStatus status;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final Widget icon;
    switch (state) {
      case DailyCardState.waiting:
        icon = const SkyIcon(SkyIcons.sealedStar, size: 22);
      case DailyCardState.lit:
        icon = SkyIcon(SkyIcons.check, size: 20, color: t.gold);
      case DailyCardState.answered:
        icon = SkyIcon(SkyIcons.clock, size: 20, color: t.gold);
      case DailyCardState.open:
        icon = SkyIcon(SkyIcons.star, size: 20, color: t.gold);
    }
    return Semantics(
      key: DailyKeys.status,
      label: status.sentence,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: t.chip,
          borderRadius: SkyRadii.all(SkyRadii.md),
          border: Border.all(color: t.chipBorder),
        ),
        child: Row(
          children: [
            SizedBox.square(dimension: 22, child: Center(child: icon)),
            const SizedBox(width: 9),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: status.strong,
                      style: SkyType.sans(11.5, weight: FontWeight.w700, height: 1.35).copyWith(color: t.gold),
                    ),
                    TextSpan(text: ' · ${status.rest}'),
                  ],
                ),
                style: SkyType.sans(11.5, height: 1.35).copyWith(color: t.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FindingCard extends StatelessWidget {
  const _FindingCard();

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    return SkyCard(
      gradient: DailyQuestionCard.gradientFor(t),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SkySpinner(size: 14, color: t.gold),
          const SizedBox(width: 10),
          Text(DailyCopy.finding, style: SkyType.small.copyWith(color: t.muted)),
        ],
      ),
    );
  }
}
