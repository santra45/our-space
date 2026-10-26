import 'dart:async';

import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/engine.dart';
import '../../sky/sky.dart';
import '../../widgets/app_haptics.dart';
import '../../widgets/confetti_burst.dart';
import 'daily_answer_card.dart';
import 'daily_copy.dart';
import 'daily_question_card.dart';
import 'daily_question_model.dart';

enum DailySheetResult { lit }

enum DailySheetView { today, archive, catchUp }

Future<DailySheetResult?> showDailySheet(
  BuildContext context, {
  required DailyQuestionModel model,
  bool archive = false,
}) {
  model.resetSheet();
  if (archive) unawaited(model.openArchive());
  return showSkySheet<DailySheetResult>(
    context: context,
    settings: const RouteSettings(name: DailyQuestionSheet.routeName),
    builder: (_) => DailyQuestionSheet(model: model),
  );
}

class DailyQuestionSheet extends StatefulWidget {
  const DailyQuestionSheet({super.key, required this.model});

  static const String routeName = '/sky/daily';

  final DailyQuestionModel model;

  @override
  State<DailyQuestionSheet> createState() => _DailyQuestionSheetState();
}

class _DailyQuestionSheetState extends State<DailyQuestionSheet> {
  DailySheetView _shown = DailySheetView.today;
  bool _reverse = false;
  bool _leaving = false;

  DailyQuestionModel get model => widget.model;

  DailySheetView get _view {
    if (model.catchUp != null) return DailySheetView.catchUp;
    if (model.showArchive) return DailySheetView.archive;
    return DailySheetView.today;
  }

  void _dismissSoon() {
    if (_leaving) return;
    _leaving = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ModalRoute.of(context)?.isCurrent ?? false) Navigator.of(context).pop();
    });
  }

  void _close([DailySheetResult? result]) {
    if (ModalRoute.of(context)?.isCurrent ?? false) Navigator.of(context).pop(result);
  }

  Future<void> _submit() async {
    final catchUp = model.catchUp != null;
    final saved = await model.save(onSaved: AppHaptics.celebration);
    if (!saved || !mounted) return;
    if (!catchUp && model.bothIn) {
      _close(DailySheetResult.lit);
      return;
    }
    fireHeartConfetti(context);
  }

  @override
  Widget build(BuildContext context) {
    final identity = context.watch<IdentityController>();
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        final today = model.today;
        if (!model.visible || today == null) {
          _dismissSoon();
          return const SizedBox.shrink();
        }
        final view = _view;
        if (view != _shown) {
          _reverse = view.index < _shown.index;
          _shown = view;
        }
        final Widget body;
        switch (view) {
          case DailySheetView.catchUp:
            body = _CatchUpView(model: model, catchUp: model.catchUp!, identity: identity, onSubmit: _submit);
          case DailySheetView.archive:
            body = _ArchiveView(model: model, identity: identity);
          case DailySheetView.today:
            body = _TodayView(
              model: model,
              today: today,
              identity: identity,
              onSubmit: _submit,
              onSeeStar: () => _close(DailySheetResult.lit),
            );
        }
        return Stack(
          key: DailyKeys.sheet,
          clipBehavior: Clip.none,
          children: [
            SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: SkySharedAxisSwitcher(
                axis: SharedAxisTransitionType.horizontal,
                reverse: _reverse,
                child: KeyedSubtree(key: ValueKey<DailySheetView>(view), child: body),
              ),
            ),
            Positioned(
              top: -4,
              right: -4,
              child: SkyIconButton(
                icon: SkyIcons.close,
                semanticLabel: DailyCopy.close,
                tone: SkyIconButtonTone.ghost,
                size: 36,
                iconSize: 16,
                onPressed: _close,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SheetHeading extends StatelessWidget {
  const _SheetHeading({required this.label, this.icon = SkyIcons.sparkle, this.title});

  final String label;
  final SkyIcons icon;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    return Padding(
      padding: const EdgeInsets.only(right: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: SkyLabel(label, icon: icon, tone: SkyTone.rose),
          ),
          if (title != null) ...[
            const SizedBox(height: 8),
            Semantics(
              header: true,
              child: Text(title!, style: SkyType.serif(22, height: 1.25).copyWith(color: t.text)),
            ),
          ],
        ],
      ),
    );
  }
}

class DailySheetLink extends StatelessWidget {
  const DailySheetLink({super.key, required this.label, required this.onTap, this.icon});

  final String label;
  final VoidCallback onTap;
  final SkyIcons? icon;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    return Padding(
      padding: const EdgeInsets.only(top: SkySpace.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SkyDivider(),
          Center(
            child: SkyPressable(
              onTap: onTap,
              semanticLabel: label,
              excludeSemantics: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[SkyIcon(icon!, size: 15, color: t.muted), const SizedBox(width: 7)],
                    Flexible(
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        style: SkyType.sans(12.5, weight: FontWeight.w700, height: 1.3).copyWith(color: t.muted),
                      ),
                    ),
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

class DailyAnswerForm extends StatelessWidget {
  const DailyAnswerForm({super.key, required this.model, required this.onSubmit, required this.footer, this.hint});

  final DailyQuestionModel model;
  final Future<void> Function() onSubmit;
  final String? hint;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hint != null) ...[SkyNotice(text: hint!, tone: SkyNoticeTone.love), const SizedBox(height: SkySpace.md)],
        SkyTextField(
          key: DailyKeys.answerField,
          controller: model.draft,
          hint: DailyCopy.placeholder,
          minLines: 5,
          maxLines: 5,
          maxLength: maxAnswerLength,
          autofocus: true,
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
        ),
        if (model.error.isNotEmpty) ...[
          const SizedBox(height: SkySpace.sm),
          Semantics(
            liveRegion: true,
            child: Row(
              children: [
                SkyIcon(SkyIcons.alert, size: 14, color: t.rose),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    model.error,
                    style: SkyType.sans(12, weight: FontWeight.w600, height: 1.35).copyWith(color: t.rose),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: SkySpace.md),
        ListenableBuilder(
          listenable: model.draft,
          builder: (context, _) => SkyButton(
            key: DailyKeys.submit,
            label: DailyCopy.answer,
            icon: SkyIcons.heart,
            busy: model.saving,
            busyLabel: DailyCopy.saving,
            onPressed: model.draft.text.trim().isEmpty ? null : () => unawaited(onSubmit()),
          ),
        ),
        const SizedBox(height: SkySpace.md),
        footer,
      ],
    );
  }
}

class _TodayView extends StatelessWidget {
  const _TodayView({
    required this.model,
    required this.today,
    required this.identity,
    required this.onSubmit,
    required this.onSeeStar,
  });

  final DailyQuestionModel model;
  final QuestionOfTheDay today;
  final IdentityController identity;
  final Future<void> Function() onSubmit;
  final VoidCallback onSeeStar;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final night = t.isNight;
    final day = model.day;
    final mine = day?.mine;
    final theirs = day?.partnerAnswer;
    final partner = identity.partnerName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _SheetHeading(label: prettyDay(today.day), title: DailyCopy.quoted(today.question.text)),
        const SizedBox(height: SkySpace.lg),
        if (mine == null)
          DailyAnswerForm(
            model: model,
            onSubmit: onSubmit,
            hint: model.partnerWaiting ? DailyCopy.partnerWaitingHint(partner) : null,
            footer: Text(
              DailyCopy.notUntilYours(identity.partnerPossessive),
              textAlign: TextAlign.center,
              style: SkyType.caption.copyWith(color: t.faint),
            ),
          )
        else ...[
          SkyEntrance(
            child: DailyAnswerCard(
              name: DailyCopy.you,
              initial: SkyAvatar.initialOf(identity.me != null ? identity.myName : null, fallback: 'Y'),
              text: mine.text,
              time: DailyCopy.answeredAt(mine.answeredAt),
            ),
          ),
          const SizedBox(height: 10),
          SkyEntrance(
            index: 1,
            child: theirs != null
                ? DailyAnswerCard(
                    name: capitalized(partner),
                    initial: SkyAvatar.initialOf(partner),
                    text: theirs.text,
                    time: DailyCopy.answeredAt(theirs.answeredAt),
                    partner: true,
                  )
                : DailyWaitingCard(message: DailyCopy.nothingYet(partner)),
          ),
          if (model.bothIn) ...[
            const SizedBox(height: 14),
            SkyEntrance(
              index: 2,
              child: SkyButton(
                label: DailyCopy.seeStar(night),
                icon: SkyIcons.star,
                variant: SkyButtonVariant.gold,
                onPressed: onSeeStar,
              ),
            ),
          ],
        ],
        DailySheetLink(
          key: DailyKeys.everyDay,
          label: DailyCopy.everyDay,
          icon: SkyIcons.calendar,
          onTap: () => unawaited(model.openArchive()),
        ),
      ],
    );
  }
}

class _CatchUpView extends StatelessWidget {
  const _CatchUpView({required this.model, required this.catchUp, required this.identity, required this.onSubmit});

  final DailyQuestionModel model;
  final DailyCatchUp catchUp;
  final IdentityController identity;
  final Future<void> Function() onSubmit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _SheetHeading(label: prettyDay(catchUp.day), title: DailyCopy.quoted(catchUp.question.text)),
        const SizedBox(height: SkySpace.lg),
        DailyAnswerForm(
          model: model,
          onSubmit: onSubmit,
          hint: DailyCopy.catchUpHint(identity.partnerName),
          footer: DailySheetLink(label: DailyCopy.backToArchive, icon: SkyIcons.back, onTap: model.leaveCatchUp),
        ),
      ],
    );
  }
}

class _ArchiveView extends StatelessWidget {
  const _ArchiveView({required this.model, required this.identity});

  final DailyQuestionModel model;
  final IdentityController identity;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final entries = model.archive;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _SheetHeading(label: DailyCopy.everyDay, icon: SkyIcons.calendar),
        const SizedBox(height: SkySpace.sm),
        if (entries.isEmpty)
          SkyEntrance(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
              child: Text(
                DailyCopy.archiveEmpty,
                textAlign: TextAlign.center,
                style: SkyType.bodySmall.copyWith(color: t.muted),
              ),
            ),
          )
        else
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0) const SkyDivider(),
            SkyEntrance(
              index: i,
              child: DailyArchiveEntry(
                key: ValueKey<String>(entries[i].day),
                entry: entries[i],
                partnerName: identity.partnerName,
                partnerPossessive: identity.partnerPossessive,
                onCatchUp: () => model.startCatchUp(entries[i]),
              ),
            ),
          ],
        DailySheetLink(label: DailyCopy.backToToday, icon: SkyIcons.back, onTap: model.closeArchive),
      ],
    );
  }
}

class DailyArchiveEntry extends StatelessWidget {
  const DailyArchiveEntry({
    super.key,
    required this.entry,
    required this.partnerName,
    required this.partnerPossessive,
    required this.onCatchUp,
  });

  final ArchiveDay entry;
  final String partnerName;
  final String partnerPossessive;
  final VoidCallback onCatchUp;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final question = entry.question;
    final line = SkyType.sans(12.5, height: 1.5).copyWith(color: t.text);
    final Widget detail;
    if (entry.missed) {
      final open = question != null;
      detail = SkyPressable(
        onTap: open ? onCatchUp : null,
        enabled: open,
        pressedScale: 0.98,
        semanticLabel: open ? DailyCopy.missed(partnerPossessive) : DailyCopy.missedGone,
        child: Opacity(
          opacity: open ? 1 : 0.6,
          child: SkyNotice(
            text: open ? DailyCopy.missed(partnerPossessive) : DailyCopy.missedGone,
            tone: open ? SkyNoticeTone.love : SkyNoticeTone.info,
          ),
        ),
      );
    } else {
      final theirs = entry.theirs;
      detail = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: DailyCopy.youPrefix,
                  style: line.copyWith(fontWeight: FontWeight.w700, color: t.gold),
                ),
                TextSpan(text: entry.mine?.text ?? ''),
              ],
            ),
            style: line,
          ),
          if (theirs != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: DailyCopy.partnerPrefix(partnerName),
                      style: line.copyWith(fontWeight: FontWeight.w700, color: t.rose),
                    ),
                    TextSpan(text: theirs.text),
                  ],
                ),
                style: line,
              ),
            ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SkySpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(prettyDay(entry.day), style: SkyType.caption.copyWith(color: t.muted)),
          const SizedBox(height: 4),
          Text(
            question?.text ?? DailyCopy.fromBackThen,
            style: SkyType.serif(16.5, height: 1.3).copyWith(color: t.text),
          ),
          const SizedBox(height: SkySpace.sm),
          detail,
        ],
      ),
    );
  }
}
