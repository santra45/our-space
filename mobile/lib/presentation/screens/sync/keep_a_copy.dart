import 'package:flutter/widgets.dart';

import '../../../core/engine.dart';
import '../../files/vault_files.dart';
import '../../sky/sky.dart';
import '../../space_scope.dart';
import '../../widgets/app_haptics.dart';
import 'backup_dialogs.dart';

const String lastCopySavedKey = 'our_space_last_copy_saved';

@immutable
class CopyOutcome {
  const CopyOutcome.saved(this.text) : failed = false;

  const CopyOutcome.failed(this.text) : failed = true;

  final String text;
  final bool failed;
}

int? lastCopySavedAt(OurSpace space) => int.tryParse(space.store.settings.getItem(lastCopySavedKey) ?? '');

Future<CopyOutcome?> saveACopy(BuildContext context) async {
  AppHaptics.tap();
  final space = context.space;
  final backup = space.backup;
  final saved = await showPassphrasePrompt<bool>(
    context,
    title: BackupCopy.exportTitle,
    description: BackupCopy.exportDescription,
    requireConfirm: true,
    submitLabel: BackupCopy.exportSubmit,
    icon: SkyIcons.download,
    tone: SkyTone.gold,
    onSubmit: (passphrase) async {
      BackupFile file;
      try {
        file = await backup.exportBackup(passphrase);
      } on BackupFailure catch (failure) {
        return PromptStep<bool>.stay(failure.message);
      } catch (_) {
        return const PromptStep<bool>.stay(BackupMessages.couldNotSave);
      }
      try {
        final written = await VaultFiles.save(file);
        return written ? const PromptStep<bool>.finish(true) : const PromptStep<bool>.stay();
      } catch (_) {
        return const PromptStep<bool>.stay(BackupMessages.couldNotSave);
      }
    },
  );
  if (saved != true) return null;
  try {
    await space.store.settings.setItem(lastCopySavedKey, '${DateTime.now().millisecondsSinceEpoch}');
  } catch (_) {}
  AppHaptics.celebration();
  return const CopyOutcome.saved(BackupMessages.saved);
}

Future<CopyOutcome?> bringInACopy(BuildContext context, {VoidCallback? onPicked}) async {
  final backup = context.space.backup;
  PickedVaultFile? picked;
  try {
    picked = await VaultFiles.pick();
  } catch (_) {
    return const CopyOutcome.failed(BackupCopy.couldNotRead);
  }
  if (picked == null || !context.mounted) return null;
  onPicked?.call();
  if (picked.tooBig) return CopyOutcome.failed(BackupMessages.tooBig(picked.size));
  AppHaptics.tap();
  if (picked.bytes == null) return const CopyOutcome.failed(BackupCopy.couldNotRead);
  Map<String, Object?> container;
  try {
    container = backup.parseBackupFile(picked.readText() ?? '', sizeBytes: picked.size);
  } on BackupFailure catch (failure) {
    return CopyOutcome.failed(failure.message);
  } catch (_) {
    return const CopyOutcome.failed(BackupMessages.notOurFile);
  }

  final preview = await showPassphrasePrompt<ImportPreview>(
    context,
    title: BackupCopy.importTitle,
    description: BackupCopy.importDescription,
    requireConfirm: false,
    submitLabel: BackupCopy.importSubmit,
    fallbackError: BackupMessages.couldNotOpen,
    icon: SkyIcons.upload,
    tone: SkyTone.lavender,
    onSubmit: (passphrase) async {
      try {
        return PromptStep<ImportPreview>.finish(await backup.previewImport(container, passphrase));
      } on BackupFailure catch (failure) {
        return PromptStep<ImportPreview>.stay(failure.message);
      } catch (_) {
        return const PromptStep<ImportPreview>.stay(BackupMessages.couldNotOpen);
      }
    },
  );
  if (preview == null || !context.mounted) return null;
  CopyOutcome? outcome;
  await showImportPreview(
    context,
    totals: preview.plan.totals,
    relation: preview.relation,
    onConfirm: () async {
      final plannedDeletes = preview.plan.totals.deleted;
      try {
        final text = await backup.applyImport(preview);
        outcome = CopyOutcome.saved(text);
        if (plannedDeletes > 0) {
          AppHaptics.tap();
        } else {
          AppHaptics.celebration();
        }
      } catch (_) {
        outcome = const CopyOutcome.failed(BackupCopy.didNotFinish);
      }
    },
  );
  return outcome;
}
