import 'package:flutter/material.dart';

import '../../../core/engine.dart';
import '../../sky/sky.dart';
import '../settings/widgets/settings_field.dart';
import '../settings/widgets/sheet_parts.dart';

abstract final class BackupCopy {
  static const String sectionTitle = 'Keep a copy';
  static const String saveCopy = 'Save a copy';
  static const String saveHint = 'Keep one somewhere safe, just in case';
  static String lastSaved(String date) => 'Last saved $date';
  static const String bringInCopy = 'Bring in a copy';
  static const String bringInHint = 'From a file you saved before';
  static const String exportTitle = 'Lock this copy';
  static const String exportDescription =
      'Use the same passphrase you open Our Space with. We check it before writing the file, so a typo cannot leave you with a copy nobody can open.';
  static const String exportSubmit = 'Save the copy';
  static const String importTitle = 'Open this copy';
  static const String importDescription =
      'Enter the passphrase this file was saved with. Nothing is added yet. You will see exactly what would change first.';
  static const String importSubmit = 'Take a look';
  static const String passphraseHint = 'Secret passphrase';
  static const String confirmHint = 'Type it again to confirm';
  static const String hidePassphrase = SettingsFieldCopy.hide;
  static const String showPassphrase = SettingsFieldCopy.show;
  static String tooShort() => 'At least $minPassphraseLength characters.';
  static const String mismatch = 'The two entries do not match.';
  static const String cancel = 'Cancel';
  static const String working = 'Working…';
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
  const PromptStep.finish(T this.value) : finished = true, error = null;

  const PromptStep.stay([this.error]) : finished = false, value = null;

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
  SkyIcons icon = SkyIcons.lock,
  SkyTone tone = SkyTone.gold,
}) {
  return showSkySheet<T>(
    context: context,
    enableDrag: false,
    builder: (_) => PassphrasePrompt<T>(
      title: title,
      description: description,
      requireConfirm: requireConfirm,
      submitLabel: submitLabel,
      onSubmit: onSubmit,
      fallbackError: fallbackError,
      icon: icon,
      tone: tone,
    ),
  );
}

class SheetButtons extends StatelessWidget {
  const SheetButtons({
    super.key,
    required this.confirmLabel,
    required this.onConfirm,
    required this.onCancel,
    required this.busy,
    required this.confirmEnabled,
    this.busyLabel,
    this.cancelLabel = BackupCopy.cancel,
    this.variant = SkyButtonVariant.primary,
  });

  final String confirmLabel;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final bool busy;
  final bool confirmEnabled;
  final String? busyLabel;
  final String cancelLabel;
  final SkyButtonVariant variant;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SkyButton(label: cancelLabel, variant: SkyButtonVariant.ghost, onPressed: busy ? null : onCancel),
        ),
        const SizedBox(width: SkySpace.md - 2),
        Expanded(
          child: SkyButton(
            label: confirmLabel,
            variant: variant,
            busy: busy,
            busyLabel: busyLabel,
            onPressed: confirmEnabled ? onConfirm : null,
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
    this.icon = SkyIcons.lock,
    this.tone = SkyTone.gold,
  });

  final String title;
  final String description;
  final bool requireConfirm;
  final String submitLabel;
  final PromptSubmit<T> onSubmit;
  final String fallbackError;
  final SkyIcons icon;
  final SkyTone tone;

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
    final t = context.sky;
    final hint = <Widget>[
      if (_value.text.isNotEmpty && _tooShort)
        Text(
          BackupCopy.tooShort(),
          key: const ValueKey<String>('prompt-short'),
          style: SkyType.small.copyWith(color: t.gold, fontWeight: FontWeight.w600),
        ),
      if (_mismatch)
        Text(
          BackupCopy.mismatch,
          key: const ValueKey<String>('prompt-mismatch'),
          style: SkyType.small.copyWith(color: t.rose, fontWeight: FontWeight.w600),
        ),
    ];
    return PopScope(
      canPop: !_busy,
      child: SheetScroll(
        children: [
          SheetHeader(title: widget.title, subtitle: widget.description, icon: widget.icon, tone: widget.tone),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              SettingsField(
                controller: _value,
                hint: BackupCopy.passphraseHint,
                obscured: !_reveal,
                onToggleReveal: () => setState(() => _reveal = !_reveal),
                autofocus: true,
                autocorrect: false,
                enableSuggestions: false,
                autofillHints: const [AutofillHints.password],
                textInputAction: widget.requireConfirm ? TextInputAction.next : TextInputAction.done,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) {
                  if (!widget.requireConfirm) _submit();
                },
              ),
              if (widget.requireConfirm) ...[
                const SizedBox(height: SkySpace.sm),
                SettingsField(
                  controller: _confirm,
                  hint: BackupCopy.confirmHint,
                  obscured: !_reveal,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _submit(),
                ),
              ],
              GrowIn(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final line in hint)
                      Padding(
                        padding: const EdgeInsets.only(top: SkySpace.sm),
                        child: line,
                      ),
                  ],
                ),
              ),
              SettingsNotes(notes: [if (_error != null) SettingsNote.error(_error!)], top: SkySpace.md),
            ],
          ),
          SheetButtons(
            confirmLabel: widget.submitLabel,
            busyLabel: BackupCopy.working,
            onConfirm: _submit,
            onCancel: _cancel,
            busy: _busy,
            confirmEnabled: _canSubmit,
          ),
        ],
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
  final result = await showSkySheet<bool>(
    context: context,
    enableDrag: false,
    builder: (_) => ImportPreviewSheet(totals: totals, relation: relation, onConfirm: onConfirm),
  );
  return result ?? false;
}

class ImportPreviewSheet extends StatefulWidget {
  const ImportPreviewSheet({super.key, required this.totals, required this.relation, required this.onConfirm});

  final MergeStats totals;
  final String relation;
  final Future<void> Function() onConfirm;

  @override
  State<ImportPreviewSheet> createState() => _ImportPreviewSheetState();
}

class _ImportPreviewSheetState extends State<ImportPreviewSheet> {
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

  Widget _banner({required String title, required String body, required bool rose}) {
    final t = context.sky;
    final accent = rose ? t.rose : t.gold;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: rose ? t.roseSoft : t.goldSoft,
        borderRadius: SkyRadii.all(SkyRadii.tile),
        border: Border.all(color: rose ? t.roseBorder : t.gold.withValues(alpha: 0.4), width: 1.4),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: SkyIcon(SkyIcons.alert, size: 18, color: accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title.toUpperCase(), style: SkyType.label.copyWith(color: accent)),
                const SizedBox(height: 6),
                Text(body, style: SkyType.bodySmall.copyWith(color: t.text, height: 1.45)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(int value, String label, SkyTone tone) {
    final t = context.sky;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: tone.background(t),
        borderRadius: SkyRadii.all(SkyRadii.tile),
        border: Border.all(color: t.cardBorder),
      ),
      child: Column(
        children: [
          Text(
            '$value',
            textAlign: TextAlign.center,
            style: SkyType.stat.copyWith(fontSize: 26, color: tone.foreground(t)),
          ),
          const SizedBox(height: 2),
          Text(
            label.toUpperCase(),
            textAlign: TextAlign.center,
            style: SkyType.label.copyWith(color: t.muted),
          ),
        ],
      ),
    );
  }

  Widget _removed(int deleted, bool destructive) {
    final t = context.sky;
    final accent = destructive ? t.rose : t.muted;
    return AnimatedContainer(
      duration: skyMotionAllowed(context) ? SkyMotion.base : Duration.zero,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: destructive ? t.roseSoft : t.chip,
        borderRadius: SkyRadii.all(SkyRadii.tile),
        border: Border.all(color: destructive ? t.roseBorder : t.chipBorder, width: destructive ? 1.4 : 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: SkyIcon(SkyIcons.trash, size: 18, color: accent),
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
                        style: SkyType.label.copyWith(color: accent),
                      ),
                    ),
                    const SizedBox(width: SkySpace.sm),
                    Text('$deleted', style: SkyType.stat.copyWith(fontSize: 22, color: accent, height: 1)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  destructive ? BackupCopy.willRemove(deleted) : BackupCopy.nothingRemoved,
                  style: SkyType.bodySmall.copyWith(color: destructive ? t.text : t.muted, height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final totals = widget.totals;
    final added = totals.added;
    final updated = totals.updated;
    final deleted = totals.deleted;
    final leftOut = totals.stale + totals.invalid + totals.undecryptable + totals.tampered + totals.unauthenticated;
    final willWrite = added + updated + deleted;
    final destructive = deleted > 0;
    final relation = widget.relation;
    final enabled = !_busy && willWrite > 0 && (!destructive || _ackDelete);
    final label = willWrite == 0
        ? BackupCopy.nothingToAdd
        : destructive
        ? BackupCopy.addRemoving(deleted)
        : BackupCopy.add(willWrite);

    return PopScope(
      canPop: !_busy,
      child: SheetScroll(
        spacing: SkySpace.md,
        children: [
          const SheetHeader(
            title: BackupCopy.previewTitle,
            subtitle: BackupCopy.previewIntro,
            icon: SkyIcons.upload,
            tone: SkyTone.lavender,
          ),
          if (relation == 'foreign') _banner(title: BackupCopy.foreignTitle, body: BackupCopy.foreignBody, rose: true),
          if (relation == 'unknown') _banner(title: BackupCopy.unknownTitle, body: BackupCopy.unknownBody, rose: false),
          if (relation == 'no-local-vault') const SkyNotice(text: BackupCopy.noLocalVault, tone: SkyNoticeTone.warning),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _stat(added, BackupCopy.added, SkyTone.gold)),
              const SizedBox(width: SkySpace.sm),
              Expanded(child: _stat(updated, BackupCopy.updated, SkyTone.lavender)),
            ],
          ),
          _removed(deleted, destructive),
          if (leftOut > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(BackupCopy.leftOut(leftOut), style: SkyType.bodySmall.copyWith(color: t.muted)),
                      ),
                      const SizedBox(width: SkySpace.sm),
                      TextAction(
                        label: BackupCopy.why,
                        color: t.muted,
                        underline: true,
                        small: true,
                        onTap: () => setState(() => _showWhy = !_showWhy),
                      ),
                    ],
                  ),
                  GrowIn(
                    child: _showWhy
                        ? Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              BackupCopy.whyBody,
                              style: SkyType.small.copyWith(color: t.muted, height: 1.45),
                            ),
                          )
                        : const SizedBox(width: double.infinity),
                  ),
                ],
              ),
            ),
          if (destructive)
            SkyPressable(
              onTap: _busy ? null : () => setState(() => _ackDelete = !_ackDelete),
              enabled: !_busy,
              pressedScale: 0.98,
              semanticLabel: BackupCopy.acknowledge(deleted),
              selected: _ackDelete,
              child: Semantics(
                checked: _ackDelete,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: t.roseSoft,
                    borderRadius: SkyRadii.all(SkyRadii.md),
                    border: Border.all(color: t.roseBorder),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkyCheckBox(checked: _ackDelete, enabled: !_busy),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          BackupCopy.acknowledge(deleted),
                          style: SkyType.bodySmall.copyWith(color: t.text, fontWeight: FontWeight.w600, height: 1.45),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: SkySpace.xs),
            child: SheetButtons(
              confirmLabel: label,
              busyLabel: BackupCopy.adding,
              onConfirm: _confirm,
              onCancel: () => Navigator.of(context).pop(false),
              busy: _busy,
              confirmEnabled: enabled,
              variant: destructive ? SkyButtonVariant.danger : SkyButtonVariant.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class SkyCheckBox extends StatelessWidget {
  const SkyCheckBox({super.key, required this.checked, this.enabled = true});

  final bool checked;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    return AnimatedOpacity(
      opacity: enabled ? 1 : 0.5,
      duration: SkyMotion.fast,
      child: AnimatedContainer(
        duration: skyMotionAllowed(context) ? SkyMotion.fast : Duration.zero,
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: checked ? t.roseDeep : t.surface,
          borderRadius: SkyRadii.all(SkyRadii.xs),
          border: Border.all(color: checked ? t.roseDeep : t.muted, width: 1.4),
        ),
        alignment: Alignment.center,
        child: checked ? const SkyIcon(SkyIcons.check, size: 14, color: SkyTokens.white) : null,
      ),
    );
  }
}
