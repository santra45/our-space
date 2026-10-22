import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/engine.dart';
import '../../sky/sky.dart';
import '../us/us_keys.dart';
import '../us/widgets/us_date_field.dart';
import '../us/widgets/us_sheet_frame.dart';
import 'milestone_copy.dart';

enum MomentAction { saved, removed }

typedef MomentSaver = Future<SaveOutcome> Function(String title, String date);

Future<MomentAction?> showMomentSheet(BuildContext context, {MilestoneRecord? moment, required MomentSaver onSave}) {
  return showSkySheet<MomentAction>(
    context: context,
    builder: (_) => MomentSheet(moment: moment, onSave: onSave),
  );
}

class MomentSheet extends StatefulWidget {
  const MomentSheet({super.key, this.moment, required this.onSave});

  final MilestoneRecord? moment;
  final MomentSaver onSave;

  @override
  State<MomentSheet> createState() => _MomentSheetState();
}

class _MomentSheetState extends State<MomentSheet> {
  late final TextEditingController _title = TextEditingController(text: widget.moment?.title ?? '');
  late String _date = _initialDate();
  bool _busy = false;
  bool _failed = false;

  bool get _editing => widget.moment != null;

  String _initialDate() {
    final date = widget.moment?.date;
    return date == null || date.isEmpty ? toLocalDateInput() : date;
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    final outcome = await widget.onSave(_title.text, _date);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failed = outcome == SaveOutcome.failed;
    });
    if (outcome == SaveOutcome.saved) Navigator.of(context).pop(MomentAction.saved);
  }

  Future<void> _remove() async {
    final confirmed = await showSkyConfirm(
      context,
      title: MilestoneCopy.confirmRemove,
      message: MilestoneCopy.confirmRemoveNote,
      confirmLabel: MilestoneCopy.confirmRemoveYes,
      cancelLabel: MilestoneCopy.keep,
      destructive: true,
      icon: SkyIcons.trash,
    );
    if (!confirmed || !mounted) return;
    Navigator.of(context).pop(MomentAction.removed);
  }

  @override
  Widget build(BuildContext context) {
    return UsSheetFrame(
      kicker: MilestoneCopy.momentKicker,
      title: _editing ? MilestoneCopy.editTitle : MilestoneCopy.newTitle,
      children: skyStaggered([
        SkyTextField(
          key: UsKeys.momentTitle,
          controller: _title,
          label: MilestoneCopy.whatLabel,
          hint: MilestoneCopy.whatHint,
          minLines: 2,
          maxLines: 3,
          autofocus: !_editing,
          keyboardType: TextInputType.multiline,
        ),
        Padding(
          padding: const EdgeInsets.only(top: SkySpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              UsDateField(
                key: UsKeys.momentDate,
                label: MilestoneCopy.whenLabel,
                value: _date,
                onChanged: (date) => setState(() => _date = date),
              ),
              if (_failed)
                Padding(
                  padding: const EdgeInsets.only(top: SkySpace.lg),
                  child: SkyEntrance(
                    child: SkyNotice(
                      text: _editing ? MilestoneCopy.updateFailed : MilestoneCopy.saveFailed,
                      tone: SkyNoticeTone.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
        UsSheetActions(
          primary: ListenableBuilder(
            listenable: _title,
            builder: (context, _) => SkyButton(
              key: UsKeys.momentSave,
              label: _editing ? MilestoneCopy.save : MilestoneCopy.add,
              icon: _editing ? SkyIcons.check : SkyIcons.star,
              busy: _busy,
              onPressed: _title.text.trim().isEmpty ? null : () => unawaited(_save()),
            ),
          ),
          secondary: _editing
              ? SkyButton(
                  key: UsKeys.momentRemove,
                  label: MilestoneCopy.remove,
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
