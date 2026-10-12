import 'package:flutter/material.dart';

import '../../../core/engine.dart';
import '../../widgets/our_widgets.dart';

abstract final class BackupCopy {
  static const String sectionTitle = 'Keep a copy, just in case';
  static const String saveCopy = 'Save a copy';
  static const String bringInCopy = 'Bring in a copy';
  static const String exportTitle = 'Lock this copy';
  static const String exportDescription =
      'Use the same passphrase you open Our Space with. We check it before writing the file, so a typo cannot leave you with a copy nobody can open.';
  static const String exportSubmit = 'Save the copy';
  static const String importTitle = 'Open this copy';
  static const String importDescription =
      'Enter the passphrase this file was saved with. Nothing is added yet — you will see exactly what would change first.';
  static const String importSubmit = 'Take a look';
  static const String passphraseHint = 'Secret passphrase';
  static const String confirmHint = 'Type it again to confirm';
  static const String hidePassphrase = 'Hide passphrase';
  static const String showPassphrase = 'Show passphrase';
  static String tooShort() => 'At least $minPassphraseLength characters.';
  static const String mismatch = 'The two entries do not match.';
  static const String cancel = 'Cancel';
  static const String working = 'Working...';
  static const String couldNotRead = 'We could not read that file. Please try another one.';
  static const String didNotFinish = 'That did not finish. Please try again.';

  static const String previewTitle = 'Before we add these';
  static const String previewIntro = 'Nothing has been added yet. Here is what would happen.';
  static const String foreignTitle = 'This is from somewhere else';
  static const String foreignBody =
      'This file came from a different space, not yours. If you were not expecting it, please tap Cancel.';
  static const String unknownTitle = 'We are not sure where this is from';
  static const String unknownBody =
      'This file does not say which space it belongs to. Only things that open with your passphrase can be added. If you were not expecting it, please tap Cancel.';
  static const String noLocalVault =
      'We could not match this file to this phone. Only the things that open with your passphrase will be added.';
  static const String added = 'Added';
  static const String updated = 'Updated';
  static const String removedForGood = 'Removed for good';
  static const String nothingRemoved = 'Nothing you still have gets removed.';
  static String willRemove(int deleted) =>
      'This will remove $deleted ${deleted == 1 ? 'thing' : 'things'} you still have, here and on the other phone. That cannot be undone.';
  static String leftOut(int count) => '$count ${count == 1 ? 'thing was' : 'things were'} left out';
  static const String why = 'Why?';
  static const String whyBody =
      'Some are older than the copies you already have, and some could not be opened with your passphrase.';
  static String acknowledge(int deleted) =>
      'I understand $deleted ${deleted == 1 ? 'thing' : 'things'} I still have will be gone for good.';
  static const String nothingToAdd = 'Nothing to add';
  static const String adding = 'Adding…';
  static String addRemoving(int deleted) => 'Add, removing $deleted';
  static String add(int count) => 'Add $count';
}

@immutable
class PromptStep<T> {
  const PromptStep.finish(T this.value)
      : finished = true,
        error = null;

  const PromptStep.stay([this.error])
      : finished = false,
        value = null;

  final bool finished;
  final T? value;
  final String? error;
}

typedef PromptSubmit<T> = Future<PromptStep<T>> Function(String passphrase);

Future<T?> showPassphrasePrompt<T>(
  BuildContext context, {
  required String title,
  required String description,
  required bool requireConfirm,
  required String submitLabel,
  required PromptSubmit<T> onSubmit,
  String fallbackError = BackupMessages.couldNotSave,
}) {
  return showOurModal<T>(
    context: context,
    backdrop: OurBackdropTone.black60,
    entrance: OurModalEntrance.popSoft,
    builder: (_) => PassphrasePrompt<T>(
      title: title,
      description: description,
      requireConfirm: requireConfirm,
      submitLabel: submitLabel,
      onSubmit: onSubmit,
      fallbackError: fallbackError,
    ),
  );
}

class DialogButtons extends StatelessWidget {
  const DialogButtons({
    super.key,
    required this.confirmLabel,
    required this.onConfirm,
    required this.onCancel,
    required this.busy,
    required this.confirmEnabled,
    this.confirmColor = AppColors.blush500,
    this.confirmShadow = AppColors.blush300,
  });

  final String confirmLabel;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final bool busy;
  final bool confirmEnabled;
  final Color confirmColor;
  final Color confirmShadow;

  @override
  Widget build(BuildContext context) {
    final radius = AppRadii.all(AppRadii.x2l);
    return Row(
      children: [
        Expanded(
          child: Semantics(
            button: true,
            enabled: !busy,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: busy ? null : onCancel,
              child: CssBox(
                padding: const EdgeInsets.symmetric(vertical: 10),
                border: Border.all(color: AppColors.slate200),
                borderRadius: radius,
                opacity: busy ? 0.5 : 1,
                child: Text(BackupCopy.cancel, textAlign: TextAlign.center, style: Tw.xs.bold.c(AppColors.slate600)),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Semantics(
            button: true,
            enabled: confirmEnabled,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: confirmEnabled ? onConfirm : null,
              child: CssBox(
                padding: const EdgeInsets.symmetric(vertical: 10),
                color: confirmColor,
                borderRadius: radius,
                shadows: AppShadows.tinted(AppShadows.sm, confirmShadow.withValues(alpha: 0.5)),
                opacity: confirmEnabled ? 1 : 0.5,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (busy) ...[
                      const TwSpin(child: LucideIcon(AppIcons.loader2, size: 14, color: AppColors.white)),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(confirmLabel, textAlign: TextAlign.center, style: Tw.xs.bold.c(AppColors.white)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class PassphrasePrompt<T> extends StatefulWidget {
  const PassphrasePrompt({
    super.key,
    required this.title,
    required this.description,
    required this.requireConfirm,
    required this.submitLabel,
    required this.onSubmit,
    this.fallbackError = BackupMessages.couldNotSave,
  });

  final String title;
  final String description;
  final bool requireConfirm;
  final String submitLabel;
  final PromptSubmit<T> onSubmit;
  final String fallbackError;

  @override
  State<PassphrasePrompt<T>> createState() => _PassphrasePromptState<T>();
}

class _PassphrasePromptState<T> extends State<PassphrasePrompt<T>> {
  final TextEditingController _value = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  bool _reveal = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _value.dispose();
    _confirm.dispose();
    super.dispose();
  }

  bool get _tooShort => normalizePassphrase(_value.text).length < minPassphraseLength;

  bool get _mismatch => widget.requireConfirm && _confirm.text.isNotEmpty && _value.text != _confirm.text;

  bool get _canSubmit => !_busy && !_tooShort && (!widget.requireConfirm || (_confirm.text.isNotEmpty && !_mismatch));

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    PromptStep<T> step;
    try {
      step = await widget.onSubmit(_value.text);
    } catch (_) {
      step = PromptStep<T>.stay(widget.fallbackError);
    }
    if (!mounted) return;
    if (step.finished) {
      Navigator.of(context).pop(step.value);
      return;
    }
    setState(() {
      _busy = false;
      _error = step.error;
    });
  }

  void _cancel() {
    if (_busy) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final field = OurFieldStyle.muted;
    final mainField = Stack(
      clipBehavior: Clip.none,
      children: [
        OurTextField(
          controller: _value,
          style: field.copyWith(padding: const EdgeInsets.fromLTRB(12, 10, 40, 10)),
          hint: BackupCopy.passphraseHint,
          obscure: !_reveal,
          showObscureToggle: false,
          autofocus: true,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: widget.requireConfirm ? TextInputAction.next : TextInputAction.done,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => widget.requireConfirm ? null : _submit(),
          semanticLabel: BackupCopy.passphraseHint,
        ),
        Positioned(
          right: 8,
          top: 0,
          bottom: 0,
          child: Center(
            child: Semantics(
              button: true,
              label: _reveal ? BackupCopy.hidePassphrase : BackupCopy.showPassphrase,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _reveal = !_reveal),
                child: SizedBox.square(
                  dimension: 28,
                  child: Center(
                    child: LucideIcon(_reveal ? AppIcons.eyeOff : AppIcons.eye, size: 16, color: AppColors.slate400),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );

    return PopScope(
      canPop: !_busy,
      child: OurModalCard(
        showClose: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: Tw.base.bold.c(AppColors.slate800)),
            const SizedBox(height: 4),
            Text(widget.description, style: Tw.px11.relaxed.c(AppColors.slate500)),
            const SizedBox(height: 12),
            mainField,
            if (widget.requireConfirm) ...[
              const SizedBox(height: 8),
              OurTextField(
                controller: _confirm,
                style: field,
                hint: BackupCopy.confirmHint,
                obscure: !_reveal,
                showObscureToggle: false,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _submit(),
                semanticLabel: BackupCopy.confirmHint,
              ),
            ],
            if (_value.text.isNotEmpty && _tooShort) ...[
              const SizedBox(height: 8),
              Text(BackupCopy.tooShort(), style: Tw.px10.semibold.c(AppColors.amber600)),
            ],
            if (_mismatch) ...[
              const SizedBox(height: 8),
              Text(BackupCopy.mismatch, style: Tw.px10.semibold.c(AppColors.rose600)),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              CssBox(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                color: AppColors.rose50,
                border: Border.all(color: AppColors.rose200),
                borderRadius: AppRadii.all(AppRadii.xl),
                child: Text(_error!, style: Tw.px10.semibold.relaxed.c(AppColors.rose700)),
              ),
            ],
            const SizedBox(height: 16),
            DialogButtons(
              confirmLabel: _busy ? BackupCopy.working : widget.submitLabel,
              onConfirm: _submit,
              onCancel: _cancel,
              busy: _busy,
              confirmEnabled: _canSubmit,
            ),
          ],
        ),
      ),
    );
  }
}

Future<bool> showImportPreview(
  BuildContext context, {
  required MergeStats totals,
  required String relation,
  required Future<void> Function() onConfirm,
}) async {
  final result = await showOurModal<bool>(
    context: context,
    backdrop: OurBackdropTone.black60,
    entrance: OurModalEntrance.popSoft,
    builder: (_) => ImportPreviewCard(totals: totals, relation: relation, onConfirm: onConfirm),
  );
  return result ?? false;
}

class ImportPreviewCard extends StatefulWidget {
  const ImportPreviewCard({super.key, required this.totals, required this.relation, required this.onConfirm});

  final MergeStats totals;
  final String relation;
  final Future<void> Function() onConfirm;

  @override
  State<ImportPreviewCard> createState() => _ImportPreviewCardState();
}

class _ImportPreviewCardState extends State<ImportPreviewCard> {
  bool _ackDelete = false;
  bool _showWhy = false;
  bool _busy = false;

  Future<void> _confirm() async {
    setState(() => _busy = true);
    try {
      await widget.onConfirm();
    } catch (_) {}
    if (mounted) Navigator.of(context).pop(true);
  }

  Widget _banner({
    required Color background,
    required Color border,
    required Color icon,
    required Color text,
    required String title,
    required String body,
  }) {
    return CssBox(
      padding: const EdgeInsets.all(12),
      color: background,
      border: Border.all(color: border, width: 2),
      borderRadius: AppRadii.all(AppRadii.xl),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: LucideIcon(AppIcons.shieldAlert, size: 16, color: icon),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title.toUpperCase(), style: Tw.px11.extrabold.trackingWide.relaxed.c(text)),
                const SizedBox(height: 4),
                Text(body, style: Tw.px11.relaxed.c(text)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(int value, String label, Color background, Color border, Color number, Color caption) {
    return CssBox(
      padding: const EdgeInsets.all(10),
      color: background,
      border: Border.all(color: border),
      borderRadius: AppRadii.all(AppRadii.xl),
      child: Column(
        children: [
          Text('$value', textAlign: TextAlign.center, style: Tw.lg.extrabold.c(number)),
          Text(label.toUpperCase(), textAlign: TextAlign.center, style: Tw.px10.bold.trackingWide.c(caption)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.totals;
    final added = t.added;
    final updated = t.updated;
    final deleted = t.deleted;
    final leftOut = t.stale + t.invalid + t.undecryptable + t.tampered + t.unauthenticated;
    final willWrite = added + updated + deleted;
    final destructive = deleted > 0;
    final relation = widget.relation;
    final enabled = !_busy && willWrite > 0 && (!destructive || _ackDelete);
    final label = willWrite == 0
        ? BackupCopy.nothingToAdd
        : _busy
            ? BackupCopy.adding
            : destructive
                ? BackupCopy.addRemoving(deleted)
                : BackupCopy.add(willWrite);

    return PopScope(
      canPop: !_busy,
      child: OurModalCard(
        showClose: false,
        maxHeightFactor: 0.85,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(BackupCopy.previewTitle, style: Tw.base.bold.c(AppColors.slate800)),
            const SizedBox(height: 4),
            Text(BackupCopy.previewIntro, style: Tw.px11.relaxed.c(AppColors.slate500)),
            if (relation == 'foreign') ...[
              const SizedBox(height: 12),
              _banner(
                background: AppColors.rose50,
                border: AppColors.rose300,
                icon: AppColors.rose600,
                text: AppColors.rose800,
                title: BackupCopy.foreignTitle,
                body: BackupCopy.foreignBody,
              ),
            ],
            if (relation == 'unknown') ...[
              const SizedBox(height: 12),
              _banner(
                background: AppColors.amber50,
                border: AppColors.amber300,
                icon: AppColors.amber600,
                text: AppColors.amber900,
                title: BackupCopy.unknownTitle,
                body: BackupCopy.unknownBody,
              ),
            ],
            if (relation == 'no-local-vault') ...[
              const SizedBox(height: 12),
              CssBox(
                padding: const EdgeInsets.all(10),
                color: AppColors.amber50,
                border: Border.all(color: AppColors.amber200),
                borderRadius: AppRadii.all(AppRadii.xl),
                child: Text(BackupCopy.noLocalVault, style: Tw.px11.relaxed.c(AppColors.amber900)),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _stat(
                    added,
                    BackupCopy.added,
                    AppColors.emerald50,
                    AppColors.emerald100,
                    AppColors.emerald700,
                    AppColors.emerald800,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _stat(
                    updated,
                    BackupCopy.updated,
                    AppColors.indigo50,
                    AppColors.indigo100,
                    AppColors.indigo700,
                    AppColors.indigo800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            CssBox(
              padding: const EdgeInsets.all(12),
              color: destructive ? AppColors.rose50 : AppColors.slate50,
              border: Border.all(color: destructive ? AppColors.rose300 : AppColors.slate200, width: 2),
              borderRadius: AppRadii.all(AppRadii.xl),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: LucideIcon(
                      AppIcons.trash2,
                      size: 16,
                      color: destructive ? AppColors.rose600 : AppColors.slate400,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Expanded(
                              child: Text(
                                BackupCopy.removedForGood.toUpperCase(),
                                style: Tw.px10.extrabold.trackingWide.c(
                                  destructive ? AppColors.rose800 : AppColors.slate500,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '$deleted',
                              style: Tw.lg.extrabold.leadingNone.c(
                                destructive ? AppColors.rose700 : AppColors.slate400,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          destructive ? BackupCopy.willRemove(deleted) : BackupCopy.nothingRemoved,
                          style: Tw.px11.relaxed.c(destructive ? AppColors.rose800 : AppColors.slate500),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (leftOut > 0) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Expanded(child: Text(BackupCopy.leftOut(leftOut), style: Tw.px11.c(AppColors.slate600))),
                        const SizedBox(width: 8),
                        Semantics(
                          button: true,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => setState(() => _showWhy = !_showWhy),
                            child: Text(BackupCopy.why, style: Tw.px10.bold.underline.c(AppColors.slate400)),
                          ),
                        ),
                      ],
                    ),
                    if (_showWhy) ...[
                      const SizedBox(height: 4),
                      Text(BackupCopy.whyBody, style: Tw.px10.relaxed.c(AppColors.slate500)),
                    ],
                  ],
                ),
              ),
            ],
            if (destructive) ...[
              const SizedBox(height: 12),
              Semantics(
                checked: _ackDelete,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _busy ? null : () => setState(() => _ackDelete = !_ackDelete),
                  child: CssBox(
                    padding: const EdgeInsets.all(10),
                    color: AppColors.rose50,
                    border: Border.all(color: AppColors.rose200),
                    borderRadius: AppRadii.all(AppRadii.xl),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: AckBox(checked: _ackDelete, enabled: !_busy),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            BackupCopy.acknowledge(deleted),
                            style: Tw.px11.bold.relaxed.c(AppColors.rose800),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            DialogButtons(
              confirmLabel: label,
              onConfirm: _confirm,
              onCancel: () => Navigator.of(context).pop(false),
              busy: _busy,
              confirmEnabled: enabled,
              confirmColor: destructive ? AppColors.rose600 : AppColors.blush500,
              confirmShadow: destructive ? AppColors.rose300 : AppColors.blush300,
            ),
          ],
        ),
      ),
    );
  }
}

class AckBox extends StatelessWidget {
  const AckBox({super.key, required this.checked, this.enabled = true});

  final bool checked;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return CssBox(
      width: 14,
      height: 14,
      color: checked ? AppColors.rose600 : AppColors.white,
      border: checked ? null : Border.all(color: AppColors.slate500),
      borderRadius: AppRadii.all(3),
      opacity: enabled ? 1 : 0.5,
      child: checked
          ? const Center(child: LucideIcon(AppIcons.check, size: 12, color: AppColors.white, strokeWidth: 3))
          : null,
    );
  }
}
