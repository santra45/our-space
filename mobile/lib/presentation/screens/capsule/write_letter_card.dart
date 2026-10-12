import 'package:flutter/material.dart';

import '../../../core/engine.dart';
import '../../space_scope.dart';
import '../../widgets/our_widgets.dart';
import 'capsule_copy.dart';

class LetterDraft {
  String title = '';
  String content = '';
  String? unlockDate;
  String saveError = '';

  void clear() {
    title = '';
    content = '';
    unlockDate = null;
  }
}

class WriteLetterCard extends StatefulWidget {
  const WriteLetterCard({super.key, required this.draft, required this.minDate});

  final LetterDraft draft;
  final DateTime minDate;

  @override
  State<WriteLetterCard> createState() => _WriteLetterCardState();
}

class _WriteLetterCardState extends State<WriteLetterCard> {
  late final TextEditingController _title = TextEditingController(text: widget.draft.title);
  late final TextEditingController _content = TextEditingController(text: widget.draft.content);
  bool _saving = false;

  LetterDraft get _draft => widget.draft;

  bool get _canSave => !_saving && _title.text.trim().isNotEmpty && _content.text.trim().isNotEmpty;

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty || _content.text.trim().isEmpty || _saving) return;
    final letters = context.space.letters;
    setState(() {
      _draft.saveError = '';
      _saving = true;
    });
    AppHaptics.tap();
    try {
      await letters.writeLetter(title: _title.text, content: _content.text, unlockDate: _draft.unlockDate);
      if (!mounted) return;
      AppHaptics.celebration();
      fireHeartConfetti(context);
      _draft.clear();
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _draft.saveError = CapsuleCopy.saveFailed);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _pickDate(DateTime picked) {
    setState(() => _draft.unlockDate = toLocalDateInput(picked));
  }

  void _clearDate() {
    AppHaptics.tick();
    setState(() => _draft.unlockDate = null);
  }

  @override
  Widget build(BuildContext context) {
    final unlockDate = _draft.unlockDate;
    return OurModalCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const OurModalHeader(
            title: CapsuleCopy.modalTitle,
            subtitle: CapsuleCopy.modalSubtitle,
            icon: AppIcons.heart,
            iconColor: AppColors.blush500,
            iconFill: AppColors.blush400,
          ),
          ...spaced([
            _group(
              label: CapsuleCopy.titleLabel,
              note: CapsuleCopy.titleNote,
              field: OurTextField(
                controller: _title,
                hint: CapsuleCopy.titleHint,
                maxLength: CapsuleCopy.titleMaxLength,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.sentences,
                semanticLabel: CapsuleCopy.titleLabel,
                onChanged: (value) => setState(() => _draft.title = value),
              ),
            ),
            _group(
              label: CapsuleCopy.bodyLabel,
              field: OurTextField(
                controller: _content,
                hint: CapsuleCopy.bodyHint,
                minLines: 6,
                maxLines: 6,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                semanticLabel: CapsuleCopy.bodyLabel,
                style: OurFieldStyle.form.copyWith(
                  fill: AppColors.amber50.withValues(alpha: 0.3),
                  textStyle: Tw.lg.handwriting.c(AppColors.slate800),
                  hintStyle: Tw.lg.handwriting.c(AppColors.placeholder),
                ),
                onChanged: (value) => setState(() => _draft.content = value),
              ),
            ),
            _group(
              label: CapsuleCopy.lockLabel,
              note: CapsuleCopy.lockNote,
              field: Stack(
                fit: StackFit.passthrough,
                children: [
                  OurDateField(
                    value: unlockDate == null ? null : parseLocalDate(unlockDate),
                    firstDate: widget.minDate,
                    onChanged: _pickDate,
                    semanticLabel: CapsuleCopy.lockLabel,
                  ),
                  if (unlockDate != null)
                    Positioned(
                      top: 0,
                      bottom: 0,
                      right: 4,
                      child: Semantics(
                        button: true,
                        label: 'Clear date',
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _clearDate,
                          child: const SizedBox(
                            width: 32,
                            child: Center(child: LucideIcon(AppIcons.x, size: 14, color: AppColors.slate400)),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            OurNotice(
              tone: NoticeTone.info,
              icon: AppIcons.info,
              iconSize: 14,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              textStyle: Tw.px10.relaxed,
              message: CapsuleCopy.promise,
            ),
            if (_draft.saveError.isNotEmpty)
              Text(
                _draft.saveError,
                textAlign: TextAlign.center,
                style: Tw.px11.semibold.c(AppColors.rose600),
              ),
            BouncyButton(
              label: CapsuleCopy.sealButton(saving: _saving, unlockDate: unlockDate),
              expand: true,
              enabled: _canSave,
              onPressed: _save,
            ),
          ], 12),
        ],
      ),
    );
  }

  Widget _group({required String label, required Widget field, String? note}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        OurFieldLabel(label),
        field,
        if (note != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(note, style: Tw.px10.c(AppColors.slate400)),
          ),
      ],
    );
  }
}
