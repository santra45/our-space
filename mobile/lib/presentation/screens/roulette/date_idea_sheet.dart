import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/engine.dart';
import '../../sky/sky.dart';
import '../us/us_keys.dart';
import '../us/widgets/us_sheet_frame.dart';
import 'roulette_copy.dart';

enum DateIdeaAction { saved, removed }

typedef DateIdeaSaver = Future<SaveOutcome> Function(String title, String desc, String category);

Future<DateIdeaAction?> showDateIdeaSheet(
  BuildContext context, {
  DateIdeaRecord? idea,
  required String category,
  required DateIdeaSaver onSave,
}) {
  return showSkySheet<DateIdeaAction>(
    context: context,
    builder: (_) => DateIdeaSheet(idea: idea, category: category, onSave: onSave),
  );
}

class DateIdeaSheet extends StatefulWidget {
  const DateIdeaSheet({super.key, this.idea, required this.category, required this.onSave});

  final DateIdeaRecord? idea;
  final String category;
  final DateIdeaSaver onSave;

  @override
  State<DateIdeaSheet> createState() => _DateIdeaSheetState();
}

class _DateIdeaSheetState extends State<DateIdeaSheet> {
  late final TextEditingController _title = TextEditingController(text: widget.idea?.title ?? '');
  late final TextEditingController _desc = TextEditingController(text: widget.idea?.desc ?? '');
  late String _category = isDateIdeaKind(widget.category) ? widget.category : dateIdeaCategories[1].id;
  bool _busy = false;
  bool _failed = false;

  bool get _editing => widget.idea != null;

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    final outcome = await widget.onSave(_title.text, _desc.text, _category);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failed = outcome == SaveOutcome.failed;
    });
    if (outcome == SaveOutcome.saved) Navigator.of(context).pop(DateIdeaAction.saved);
  }

  Future<void> _remove() async {
    final confirmed = await showSkyConfirm(
      context,
      title: RouletteCopy.confirmRemove,
      message: RouletteCopy.confirmRemoveNote,
      confirmLabel: RouletteCopy.confirmRemoveYes,
      cancelLabel: RouletteCopy.keep,
      destructive: true,
      icon: SkyIcons.trash,
    );
    if (!confirmed || !mounted) return;
    Navigator.of(context).pop(DateIdeaAction.removed);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    return UsSheetFrame(
      kicker: RouletteCopy.ideasKicker,
      title: _editing ? RouletteCopy.editTitle : RouletteCopy.newTitle,
      children: skyStaggered([
        SkyTextField(
          key: UsKeys.ideaTitle,
          controller: _title,
          label: RouletteCopy.titleLabel,
          hint: RouletteCopy.titleHint,
          maxLength: dateIdeaTitleLimit,
          autofocus: !_editing,
          textInputAction: TextInputAction.next,
        ),
        Padding(
          padding: const EdgeInsets.only(top: SkySpace.lg),
          child: SkyTextField(
            key: UsKeys.ideaDesc,
            controller: _desc,
            label: RouletteCopy.descLabel,
            hint: RouletteCopy.descHint,
            minLines: 2,
            maxLines: 4,
            maxLength: dateIdeaDescLimit,
            keyboardType: TextInputType.multiline,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: SkySpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                RouletteCopy.kindLabel,
                style: SkyType.sans(11, weight: FontWeight.w600).copyWith(color: t.muted),
              ),
              const SizedBox(height: 1),
              Wrap(
                spacing: SkySpace.sm,
                children: [
                  for (final kind in dateIdeaCategories)
                    if (isDateIdeaKind(kind.id))
                      SkyChip(
                        label: RouletteCopy.categoryLabel(kind.id, kind.label),
                        tone: kind.id == _category ? SkyChipTone.on : SkyChipTone.plain,
                        onTap: () => setState(() => _category = kind.id),
                      ),
                ],
              ),
              if (_failed)
                Padding(
                  padding: const EdgeInsets.only(top: SkySpace.lg),
                  child: SkyEntrance(
                    child: SkyNotice(text: RouletteCopy.saveFailed, tone: SkyNoticeTone.error),
                  ),
                ),
            ],
          ),
        ),
        UsSheetActions(
          primary: ListenableBuilder(
            listenable: _title,
            builder: (context, _) => SkyButton(
              key: UsKeys.ideaSave,
              label: _editing ? RouletteCopy.save : RouletteCopy.add,
              icon: _editing ? SkyIcons.check : SkyIcons.sparkle,
              busy: _busy,
              onPressed: _title.text.trim().isEmpty ? null : () => unawaited(_save()),
            ),
          ),
          secondary: _editing
              ? SkyButton(
                  key: UsKeys.ideaRemove,
                  label: RouletteCopy.remove,
                  icon: SkyIcons.trash,
                  variant: SkyButtonVariant.danger,
                  onPressed: _busy ? null : () => unawaited(_remove()),
                )
              : null,
        ),
      ], offset: const Offset(0, 10)),
    );
  }
}
