import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/engine.dart';
import '../../widgets/our_widgets.dart';
import 'daily_copy.dart';
import 'daily_question_model.dart';

class DailyQuestionSheet extends StatelessWidget {
  const DailyQuestionSheet({super.key, required this.model, required this.onCelebrate});

  final DailyQuestionModel model;
  final VoidCallback onCelebrate;

  void _dismissSoon(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      if (ModalRoute.of(context)?.isCurrent ?? false) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final identity = context.watch<IdentityController>();
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        final today = model.today;
        if (!model.visible || today == null) {
          _dismissSoon(context);
          return const SizedBox.shrink();
        }
        final catchUp = model.catchUp;
        final Widget body;
        if (catchUp != null) {
          body = _CatchUpView(model: model, catchUp: catchUp, identity: identity, onCelebrate: onCelebrate);
        } else if (!model.showArchive) {
          body = _TodayView(model: model, today: today, identity: identity, onCelebrate: onCelebrate);
        } else {
          body = _ArchiveView(model: model, identity: identity);
        }
        return OurModalCard(
          sheet: true,
          borderColor: AppColors.lavender100,
          onClose: () => Navigator.of(context).pop(),
          child: body,
        );
      },
    );
  }
}

class SheetDayLabel extends StatelessWidget {
  const SheetDayLabel(this.text, {super.key, this.bottom = 4});

  final String text;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Text(text.toUpperCase(), style: Tw.px11.bold.trackingWide.c(AppColors.lavender500)),
    );
  }
}

class SheetQuestionTitle extends StatelessWidget {
  const SheetQuestionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, right: 32),
      child: Text(text, style: Tw.x2l.handwriting.snug.c(AppColors.slate800)),
    );
  }
}

class SheetFooterButton extends StatelessWidget {
  const SheetFooterButton({super.key, required this.label, required this.onTap, this.icon});

  final String label;
  final VoidCallback onTap;
  final LucideIconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Semantics(
        button: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: CssBox(
            padding: const EdgeInsets.only(top: 12),
            border: const Border(top: BorderSide(color: AppColors.slate100)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  LucideIcon(icon!, size: 14, color: AppColors.slate500),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(label, textAlign: TextAlign.center, style: Tw.xs.bold.c(AppColors.slate500)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class LavenderHint extends StatelessWidget {
  const LavenderHint(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return OurNotice(
      tone: NoticeTone.lavender,
      padding: const EdgeInsets.all(10),
      textStyle: Tw.px11.relaxed,
      message: message,
    );
  }
}

class AnswerForm extends StatelessWidget {
  const AnswerForm({
    super.key,
    required this.model,
    required this.onCelebrate,
    required this.footer,
    this.hint,
  });

  final DailyQuestionModel model;
  final VoidCallback onCelebrate;
  final Widget? hint;
  final Widget footer;

  static final OurFieldStyle fieldStyle = OurFieldStyle.soft.copyWith(
    textStyle: Tw.sm.relaxed.c(AppColors.slate800),
    hintStyle: Tw.sm.relaxed.c(AppColors.slate400),
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: spaced([
        if (hint != null) hint!,
        OurTextField(
          controller: model.draft,
          style: fieldStyle,
          hint: DailyCopy.placeholder,
          minLines: 5,
          maxLines: 5,
          maxLength: maxAnswerLength,
          autofocus: true,
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
        ),
        if (model.error.isNotEmpty)
          Semantics(
            liveRegion: true,
            child: Text(model.error, style: Tw.px11.semibold.c(AppColors.rose600)),
          ),
        ListenableBuilder(
          listenable: model.draft,
          builder: (context, _) => BouncyButton(
            expand: true,
            label: model.saving ? DailyCopy.saving : DailyCopy.answer,
            enabled: !model.saving && model.draft.text.trim().isNotEmpty,
            onPressed: () => unawaited(model.save(onSaved: onCelebrate)),
          ),
        ),
        footer,
      ], 12),
    );
  }
}

class _CatchUpView extends StatelessWidget {
  const _CatchUpView({
    required this.model,
    required this.catchUp,
    required this.identity,
    required this.onCelebrate,
  });

  final DailyQuestionModel model;
  final DailyCatchUp catchUp;
  final IdentityController identity;
  final VoidCallback onCelebrate;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetDayLabel(prettyDay(catchUp.day)),
        SheetQuestionTitle(catchUp.question.text),
        AnswerForm(
          model: model,
          onCelebrate: onCelebrate,
          hint: LavenderHint(DailyCopy.catchUpHint(identity.partnerName)),
          footer: Semantics(
            button: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                AppHaptics.tap();
                model.leaveCatchUp();
              },
              child: Text(
                DailyCopy.backToArchive,
                textAlign: TextAlign.center,
                style: Tw.px11.bold.c(AppColors.slate400),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TodayView extends StatelessWidget {
  const _TodayView({
    required this.model,
    required this.today,
    required this.identity,
    required this.onCelebrate,
  });

  final DailyQuestionModel model;
  final QuestionOfTheDay today;
  final IdentityController identity;
  final VoidCallback onCelebrate;

  @override
  Widget build(BuildContext context) {
    final day = model.day;
    final mine = day?.mine;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetDayLabel(prettyDay(today.day)),
        SheetQuestionTitle(today.question.text),
        if (mine == null)
          AnswerForm(
            model: model,
            onCelebrate: onCelebrate,
            hint: model.partnerWaiting ? LavenderHint(DailyCopy.partnerWaitingHint(identity.partnerName)) : null,
            footer: Text(
              DailyCopy.notUntilYours(identity.partnerPossessive),
              textAlign: TextAlign.center,
              style: Tw.px10.relaxed.c(AppColors.slate400),
            ),
          )
        else
          AnsweredPair(
            mine: mine.text,
            partnerName: identity.partnerName,
            partnerAnswer: day?.partnerAnswer?.text,
          ),
        SheetFooterButton(
          label: DailyCopy.everything,
          icon: AppIcons.history,
          onTap: () {
            AppHaptics.tap();
            unawaited(model.openArchive());
          },
        ),
      ],
    );
  }
}

class AnsweredPair extends StatelessWidget {
  const AnsweredPair({super.key, required this.mine, required this.partnerName, this.partnerAnswer});

  final String mine;
  final String partnerName;
  final String? partnerAnswer;

  Widget _answer({
    required String label,
    required String text,
    required Color background,
    required Color border,
    required Color labelColor,
  }) {
    return CssBox(
      padding: const EdgeInsets.all(12),
      color: background,
      border: Border.all(color: border),
      borderRadius: AppRadii.all(AppRadii.x2l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label.toUpperCase(), style: Tw.px10.bold.trackingWide.c(labelColor)),
          const SizedBox(height: 4),
          Text(text, style: Tw.sm.relaxed.c(AppColors.slate700)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theirs = partnerAnswer;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _answer(
          label: DailyCopy.you,
          text: mine,
          background: AppColors.blush50.withValues(alpha: 0.7),
          border: AppColors.blush100,
          labelColor: AppColors.blush500,
        ),
        const SizedBox(height: 12),
        if (theirs != null)
          _answer(
            label: partnerName,
            text: theirs,
            background: AppColors.lavender50,
            border: AppColors.lavender100,
            labelColor: AppColors.lavender500,
          )
        else
          CssBox(
            padding: const EdgeInsets.all(12),
            color: AppColors.slate50,
            border: Border.all(color: AppColors.slate100),
            borderRadius: AppRadii.all(AppRadii.x2l),
            child: Text(
              DailyCopy.nothingYet(partnerName),
              textAlign: TextAlign.center,
              style: Tw.px11.relaxed.c(AppColors.slate500),
            ),
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
    final entries = model.archive;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetDayLabel(DailyCopy.everyDay, bottom: 12),
        if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              DailyCopy.archiveEmpty,
              textAlign: TextAlign.center,
              style: Tw.xs.relaxed.c(AppColors.slate500),
            ),
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: spaced([
              for (var i = 0; i < entries.length; i++)
                ArchiveEntry(
                  key: ValueKey<String>(entries[i].day),
                  entry: entries[i],
                  last: i == entries.length - 1,
                  partnerName: identity.partnerName,
                  partnerPossessive: identity.partnerPossessive,
                  onCatchUp: () {
                    AppHaptics.tap();
                    model.startCatchUp(entries[i]);
                  },
                ),
            ], 16),
          ),
        SheetFooterButton(label: DailyCopy.backToToday, onTap: model.closeArchive),
      ],
    );
  }
}

class ArchiveEntry extends StatelessWidget {
  const ArchiveEntry({
    super.key,
    required this.entry,
    required this.last,
    required this.partnerName,
    required this.partnerPossessive,
    required this.onCatchUp,
  });

  final ArchiveDay entry;
  final bool last;
  final String partnerName;
  final String partnerPossessive;
  final VoidCallback onCatchUp;

  @override
  Widget build(BuildContext context) {
    final question = entry.question;
    final lineStyle = Tw.px11.relaxed.c(AppColors.slate600);
    final Widget detail;
    if (entry.missed) {
      detail = Semantics(
        button: true,
        enabled: question != null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: question == null ? null : onCatchUp,
          child: Opacity(
            opacity: question == null ? 0.6 : 1,
            child: OurNotice(
              tone: NoticeTone.lavender,
              padding: const EdgeInsets.all(10),
              iconSize: 14,
              textStyle: Tw.px11.relaxed,
              message: question == null ? DailyCopy.missedGone : DailyCopy.missed(partnerPossessive),
            ),
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
                TextSpan(text: DailyCopy.youPrefix, style: lineStyle.bold.c(AppColors.blush500)),
                TextSpan(text: entry.mine?.text ?? ''),
              ],
            ),
            style: lineStyle,
          ),
          if (theirs != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: DailyCopy.partnerPrefix(partnerName),
                      style: lineStyle.bold.c(AppColors.lavender500),
                    ),
                    TextSpan(text: theirs.text),
                  ],
                ),
                style: lineStyle,
              ),
            ),
        ],
      );
    }

    return CssBox(
      padding: const EdgeInsets.only(bottom: 12),
      border: last ? null : const Border(bottom: BorderSide(color: AppColors.slate100)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(prettyDay(entry.day), style: Tw.px10.mono.c(AppColors.slate400)),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              question?.text ?? DailyCopy.fromBackThen,
              style: Tw.lg.handwriting.snug.c(AppColors.slate800),
            ),
          ),
          detail,
        ],
      ),
    );
  }
}
