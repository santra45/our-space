import 'base64.dart';
import 'envelope.dart';
import 'js_compat.dart';
import 'kdf.dart';

const String backupMagic = 'OUR_SPACE_ENCRYPTED_VAULT_V1';
const int backupContainerVersion = 2;

class BackupError implements Exception {
  BackupError(this.message);
  final String message;
  @override
  String toString() => message;
}

Future<Map<String, Object?>> createEncryptedBackup(
  Map<String, Object?> rawVaultData,
  String passphrase, {
  int iterations = pbkdf2IterationsCurrent,
}) async {
  final normalized = normalizePassphrase(passphrase);
  if (normalized.length < minPassphraseLength) {
    throw BackupError('Passphrase must be at least $minPassphraseLength characters long');
  }
  final salt = generateSalt();
  final backupKey = await deriveKeyFromPassphrase(normalized, salt, iterations: iterations);
  final encrypted = encryptText(jsonStringify(rawVaultData), backupKey);
  return {
    'magic': backupMagic,
    'version': backupContainerVersion,
    'salt': salt,
    'kdfIterations': iterations,
    'iv': encrypted.iv,
    'ciphertext': encrypted.ciphertext,
    'exportedAt': toJsIsoString(systemNow()),
  };
}

Future<Map<String, Object?>> decryptBackupContainer(Object? container, String passphrase) async {
  final map = asStringMap(container);
  if (map == null) {
    throw BackupError('Invalid backup: not a valid object');
  }
  if (map['magic'] != backupMagic) {
    throw BackupError('Invalid backup: unrecognized container header or format');
  }
  final salt = map['salt'];
  final iv = map['iv'];
  final ciphertext = map['ciphertext'];
  if (salt is! String || salt.isEmpty || iv is! String || iv.isEmpty || ciphertext is! String || ciphertext.isEmpty) {
    throw BackupError('Invalid backup: missing cryptographic components');
  }
  final iterationsValue = map['kdfIterations'];
  final iterations = isFiniteNumber(iterationsValue)
      ? (iterationsValue as num).floor()
      : pbkdf2IterationsCurrent;

  String? decrypted;
  try {
    await deriveKeyWithVerification(
      passphrase,
      salt,
      (candidate) {
        decrypted = decryptText(ciphertext, iv, candidate);
        return true;
      },
      iterations: iterations,
    );
  } catch (_) {
    throw BackupError('Incorrect backup passphrase, or the file has been tampered with.');
  }

  final parsed = asStringMap(jsonParse(decrypted!));
  if (parsed == null || parsed['tables'] == null) {
    throw BackupError('Invalid backup: malformed payload inside container');
  }
  return parsed;
}
