import 'dart:convert';
import '../constants/app_constants.dart';
import '../storage/app_database.dart';
import '../storage/tombstone_helper.dart';
import 'crypto_engine.dart';

const String backupFormat = 'SWEETHEART_VAULT_BACKUP';
const int backupVersion = 2;

class BackupCrypto {
  BackupCrypto._();

  static Future<String> exportBackup(String backupPassphrase) async {
    final salt = CryptoEngine.instance.generateSalt();
    final backupKey = await CryptoEngine.instance.deriveKeyFromPassphrase(
      backupPassphrase,
      salt,
      iterations: pbkdf2IterationsCurrent,
    );

    final Map<String, dynamic> container = {
      'vaultMeta': await AppDatabase.instance.getVaultMeta(),
    };

    for (final table in syncedTables) {
      container[table] = await AppDatabase.instance.getActiveRecords(table);
    }

    final encrypted = await CryptoEngine.instance.encryptJSON(container, backupKey);

    final backupFile = {
      'format': backupFormat,
      'version': backupVersion,
      'salt': salt,
      'iterations': pbkdf2IterationsCurrent,
      'ciphertext': encrypted['ciphertext']!,
      'iv': encrypted['iv']!,
      'exportedAt': DateTime.now().millisecondsSinceEpoch,
    };

    return jsonEncode(backupFile);
  }

  static Future<int> importBackup(String backupJson, String backupPassphrase) async {
    final Map<String, dynamic> backupFile = jsonDecode(backupJson) as Map<String, dynamic>;

    if (backupFile['format'] != backupFormat) {
      throw const FormatException('Not a valid Our Space .vault backup file.');
    }

    final salt = backupFile['salt'] as String;
    final iterations = (backupFile['iterations'] as num?)?.toInt() ?? pbkdf2IterationsCurrent;
    final ciphertext = backupFile['ciphertext'] as String;
    final iv = backupFile['iv'] as String;

    final backupKey = await CryptoEngine.instance.deriveKeyFromPassphrase(
      backupPassphrase,
      salt,
      iterations: iterations,
    );

    final decryptedContainer = await CryptoEngine.instance.decryptJSON(ciphertext, iv, backupKey);
    int importedRecords = 0;

    for (final table in syncedTables) {
      final rows = (decryptedContainer[table] as List<dynamic>?) ?? [];
      for (final r in rows) {
        final incoming = r as Map<String, dynamic>;
        final id = incoming['id'] as String;
        final existing = await AppDatabase.instance.getRecord(table, id);

        if (existing == null || TombstoneHelper.incomingWins(existing, incoming)) {
          await AppDatabase.instance.putEnvelope(table, incoming);
          importedRecords++;
        }
      }
    }

    return importedRecords;
  }
}
