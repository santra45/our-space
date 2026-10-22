import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/engine.dart';
import '../../sky/sky.dart';
import '../us/us_keys.dart';
import '../us/widgets/us_sheet_frame.dart';
import 'bucket_copy.dart';

enum DreamAction { saved, removed }

typedef DreamSaver = Future<SaveOutcome> Function(String text, String category);

Future<DreamAction?> showDreamSheet(
  BuildContext context, {
  BucketListRecord? dream,
  required String category,
  required DreamSaver onSave,
}) {
  return showSkySheet<DreamAction>(
    context: context,
    builder: (_) => DreamSheet(dream: dream, category: category, onSave: onSave),
  );
}

class DreamSheet extends StatefulWidget {
  const DreamSheet({super.key, this.dream, required this.category, required this.onSave});

  final BucketListRecord? dream;
  final String category;
  final DreamSaver onSave;

  @override
  State<DreamSheet> createState() => _DreamSheetState();
}

class _DreamSheetState extends State<DreamSheet> {
  late final TextEditingController _text = TextEditingController(text: widget.dream?.text ?? '');
  late String _category = widget.category;
  bool _busy = false;
  bool _failed = false;

  bool get _editing => widget.dream != null;

  List<DreamCategory> get _choices {
    final known = dreamCategories.any((category) => category.value == widget.category);
    return [
      ...dreamCategories,
      if (!known) DreamCategory(widget.category, dreamCategoryLabel(widget.category)),
    ];
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    final outcome = await widget.onSave(_text.text, _category);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failed = outcome == SaveOutcome.failed;
    });
    if (outcome == SaveOutcome.saved) Navigator.of(context).pop(DreamAction.saved);
  }

  Future<void> _remove() async {
    final confirmed = await showSkyConfirm(
      context,
      title: BucketCopy.confirmRemove,
      message: BucketCopy.confirmRemoveNote,
      confirmLabel: BucketCopy.confirmRemoveYes,
      cancelLabel: BucketCopy.keep,
      destructive: true,
      icon: SkyIcons.trash,
    );
    if (!confirmed || !mounted) return;
    Navigator.of(context).pop(DreamAction.removed);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    return UsSheetFrame(
      kicker: BucketCopy.kicker,
      title: _editing ? BucketCopy.editTitle : BucketCopy.newTitle,
      children: skyStaggered([
        SkyTextField(
          key: UsKeys.dreamText,
          controller: _text,
          label: BucketCopy.textLabel,
          hint: BucketCopy.hint,
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
              Text(
                BucketCopy.categoryLabel,
                style: SkyType.sans(11, weight: FontWeight.w600).copyWith(color: t.muted),
              ),
              const SizedBox(height: SkySpace.sm),
              Wrap(
                spacing: SkySpace.sm,
                runSpacing: SkySpace.sm,
                children: [
                  for (final choice in _choices)
                    SkyChip(
                      label: choice.label,
                      tone: choice.value == _category ? SkyChipTone.on : SkyChipTone.plain,
                      onTap: () => setState(() => _category = choice.value),
                    ),
                ],
              ),
              if (_failed)
                Padding(
                  padding: const EdgeInsets.only(top: SkySpace.lg),
                  child: SkyEntrance(
                    child: SkyNotice(text: BucketCopy.saveFailed, tone: SkyNoticeTone.error),
                  ),
                ),
            ],
          ),
        ),
        UsSheetActions(
          primary: ListenableBuilder(
            listenable: _text,
            builder: (context, _) => SkyButton(
              key: UsKeys.dreamSave,
              label: _editing ? BucketCopy.save : BucketCopy.add,
              icon: _editing ? SkyIcons.check : SkyIcons.sparkle,
              busy: _busy,
              onPressed: _text.text.trim().isEmpty ? null : () => unawaited(_save()),
            ),
          ),
          secondary: _editing
              ? SkyButton(
                  key: UsKeys.dreamRemove,
                  label: BucketCopy.remove,
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
