import '../crypto/backup.dart';
import '../crypto/canary.dart';
import '../crypto/js_compat.dart';
import '../crypto/kdf.dart';
import '../storage/tables.dart';
import '../storage/vault_store.dart';
import '../vault/vault_service.dart';

class BackupMessages {
  static const String wrongPassphrase =
      'That is not the passphrase you open Our Space with. The copy has to use the same one, or nothing could ever bring it back.';
  static const String saved = 'Copy saved. Only that passphrase opens it. 💕';
  static const String couldNotSave = 'We could not save that copy. Please try again.';
  static const String notOurFile = 'That does not look like a file Our Space saved.';
  static const String locked = 'Our Space is locked right now. Unlock it and try again.';
  static const String couldNotOpen = 'We could not open that file. Check the passphrase and try again.';
  static const String unreadableHere = 'We could not read what is already on this phone, so we stopped. Nothing changed.';
  static int get maxFileMb => (maxBackupFileBytes / (1024 * 1024)).round();
  static String tooBig(int bytes) =>
      'That file is ${(bytes / (1024 * 1024)).round()}MB — a bit big. The most we can take is ${maxFileMb}MB.';

  static String added(MergeResult result, int plannedDeletes) {
    final written = result.totalWritten;
    final superseded = result.supersededSincePreview;
    final supersededNote =
        superseded > 0 ? ' $superseded already had a newer copy here, so we left those alone.' : '';
    final deleteNote = plannedDeletes > 0
        ? (superseded > 0
            ? ' Up to $plannedDeletes of them removed something you had.'
            : ' $plannedDeletes of them removed something you had — those are gone for good.')
        : '';
    return 'Added $written ${written == 1 ? 'thing' : 'things'}.$deleteNote$supersededNote';
  }
}

class BackupFailure implements Exception {
  BackupFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class BackupFile {
  const BackupFile({required this.fileName, required this.contents});

  final String fileName;
  final String contents;
}

class ImportPreview {
  const ImportPreview({required this.plan, required this.relation, required this.identity});

  final MergePlan plan;
  final String relation;
  final Map<String, Object?>? identity;
}

Future<bool> verifyPassphraseAgainstMeta(String passphrase, Map<String, Object?>? meta) async {
  final salt = meta?['salt'];
  if (meta == null || salt is! String) return false;
  try {
    await deriveKeyWithVerification(
      passphrase,
      salt,
      (key) => readCanary(key, meta) != null,
      iterations: isFiniteNumber(meta['kdfIterations']) ? meta['kdfIterations'] as num : pbkdf2IterationsCurrent,
    );
    return true;
  } catch (_) {
    return false;
  }
}

class BackupService {
  BackupService({required this.store, required this.vault});

  final VaultStore store;
  final VaultService vault;

  Future<BackupFile> exportBackup(String passphrase) async {
    final meta = await store.getVaultMeta();
    if (!await verifyPassphraseAgainstMeta(passphrase, meta)) {
      throw BackupFailure(BackupMessages.wrongPassphrase);
    }
    try {
      final raw = await store.exportRawDataForBackup();
      final container = await createEncryptedBackup(raw, passphrase);
      await decryptBackupContainer(container, passphrase);
      final day = toJsIsoString(store.now()).split('T').first;
      return BackupFile(fileName: 'our-space-$day.vault', contents: jsonStringify(container));
    } catch (_) {
      throw BackupFailure(BackupMessages.couldNotSave);
    }
  }

  Map<String, Object?> parseBackupFile(String text, {int? sizeBytes}) {
    if (sizeBytes != null && sizeBytes > maxBackupFileBytes) {
      throw BackupFailure(BackupMessages.tooBig(sizeBytes));
    }
    Object? parsed;
    try {
      parsed = jsonParse(text);
    } catch (_) {
      throw BackupFailure(BackupMessages.notOurFile);
    }
    final map = parsed is Map ? asStringMap(parsed) : null;
    if (map == null) throw BackupFailure(BackupMessages.notOurFile);
    return map;
  }

  Future<Map<String, Object?>> openContainer(Map<String, Object?> container, String passphrase) async {
    try {
      return await decryptBackupContainer(container, passphrase);
    } catch (_) {
      throw BackupFailure(BackupMessages.couldNotOpen);
    }
  }

  Future<ImportPreview> previewImport(Map<String, Object?> container, String passphrase) async {
    final decrypted = await openContainer(container, passphrase);
    final key = vault.key;
    if (key == null) throw BackupFailure(BackupMessages.locked);
    final identity = readBackupVaultIdentity(decrypted['tables']);
    final localRead = await store.readVaultIdentity();
    final relation = compareVaultIdentity(identity, localRead);
    if (relation == 'unknown' && !localRead.ok) {
      throw BackupFailure(BackupMessages.unreadableHere);
    }
    try {
      final plan = await store.planBackupMerge(decrypted['tables'], key);
      return ImportPreview(plan: plan, relation: relation, identity: identity);
    } catch (_) {
      throw BackupFailure(BackupMessages.couldNotOpen);
    }
  }

  Future<String> applyImport(ImportPreview preview) async {
    final plannedDeletes = preview.plan.totals.deleted;
    final result = await store.applyBackupMerge(preview.plan);
    return BackupMessages.added(result, plannedDeletes);
  }
}
