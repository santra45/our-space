import 'aes_gcm.dart';
import 'base64.dart';
import 'envelope.dart';
import 'js_compat.dart';
import 'pbkdf2.dart';

const int timeLockVersion = 1;
const String timeLockContext = 'our-space/time-lock/v1';
const int _timeLockSaltBytes = 16;

class TimeLockedError implements Exception {
  TimeLockedError(this.unlockDate, this.unlocksAt);
  final String unlockDate;
  final int unlocksAt;
  String get message => 'This letter is still time-locked';
  @override
  String toString() => message;
}

final RegExp _dateOnly = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

int _jsYear(int year) => (year >= 0 && year <= 99) ? 1900 + year : year;

int? getTimeLockBoundary(Object? unlockDate) {
  if (unlockDate is! String || unlockDate.isEmpty) return null;
  final match = _dateOnly.firstMatch(unlockDate);
  if (match != null) {
    return DateTime(
      _jsYear(int.parse(match.group(1)!)),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    ).millisecondsSinceEpoch;
  }
  final parsed = DateTime.tryParse(unlockDate);
  return parsed?.millisecondsSinceEpoch;
}

bool isTimeLockOpen(Object? sealedOrDate, [int? now]) {
  Object? unlockDate;
  if (sealedOrDate is String) {
    unlockDate = sealedOrDate;
  } else if (sealedOrDate is Map) {
    unlockDate = sealedOrDate['unlockDate'];
  }
  if (unlockDate == null || unlockDate == '') return true;
  final boundary = getTimeLockBoundary(unlockDate);
  if (boundary == null) return true;
  return (now ?? systemNow()) >= boundary;
}

String _binding(String unlockDate, String context) => '$timeLockContext|$unlockDate|$context';

VaultKey _deriveTimeLockKey(
  VaultKey vaultKey, {
  required String lockSalt,
  required String lockIv,
  required String unlockDate,
  required String context,
}) {
  final binding = _binding(unlockDate, context);
  final material = aesGcmSeal(vaultKey, base64ToBuffer(lockIv), utf8Bytes(binding));
  final derived = hkdfSha256(
    ikm: material,
    salt: base64ToBuffer(lockSalt),
    info: utf8Bytes(binding),
    length: aesKeyLengthBytes,
  );
  return VaultKey.fromBits(derived);
}

Map<String, Object?> sealTimeLocked(
  String plainText,
  String unlockDate,
  VaultKey vaultKey, {
  String context = '',
}) {
  if (unlockDate.isEmpty) {
    throw RecordError('sealTimeLocked: unlockDate is required');
  }
  if (getTimeLockBoundary(unlockDate) == null) {
    throw RecordError('sealTimeLocked: unlockDate is not a parseable date');
  }

  final binding = _binding(unlockDate, context);
  final lockSalt = generateSecureNonce(_timeLockSaltBytes);
  final lockIv = generateSecureNonce(ivLengthBytes);

  final contentKeyBytes = randomBytes(aesKeyLengthBytes);
  final contentKey = VaultKey.fromBits(contentKeyBytes);
  final content = encryptText(plainText, contentKey, binding);

  final lockKey = _deriveTimeLockKey(
    vaultKey,
    lockSalt: lockSalt,
    lockIv: lockIv,
    unlockDate: unlockDate,
    context: context,
  );
  final wrapIv = randomBytes(ivLengthBytes);
  final wrapped = aesGcmSeal(lockKey, wrapIv, contentKeyBytes, aad: utf8Bytes(binding));

  return {
    'lockVersion': timeLockVersion,
    'unlockDate': unlockDate,
    'lockSalt': lockSalt,
    'lockIv': lockIv,
    'wrapIv': bufferToBase64(wrapIv),
    'wrappedKey': bufferToBase64(wrapped),
    'ciphertext': content.ciphertext,
    'iv': content.iv,
  };
}

String unsealTimeLocked(
  Map<String, Object?> sealed,
  VaultKey vaultKey, {
  String context = '',
  int? now,
}) {
  if (sealed['lockVersion'] != timeLockVersion) {
    throw RecordError('unsealTimeLocked: unsupported lock version ${sealed['lockVersion']}');
  }
  final unlockDate = sealed['unlockDate'];
  final lockSalt = sealed['lockSalt'];
  final lockIv = sealed['lockIv'];
  final wrapIv = sealed['wrapIv'];
  final wrappedKey = sealed['wrappedKey'];
  final ciphertext = sealed['ciphertext'];
  final iv = sealed['iv'];
  if (unlockDate is! String ||
      lockSalt is! String ||
      lockIv is! String ||
      wrapIv is! String ||
      wrappedKey is! String ||
      ciphertext is! String ||
      iv is! String) {
    throw RecordError('unsealTimeLocked: sealed envelope is missing fields');
  }

  final at = now ?? systemNow();
  final boundary = getTimeLockBoundary(unlockDate);
  if (boundary != null && at < boundary) {
    throw TimeLockedError(unlockDate, boundary);
  }

  final binding = _binding(unlockDate, context);
  final lockKey = _deriveTimeLockKey(
    vaultKey,
    lockSalt: lockSalt,
    lockIv: lockIv,
    unlockDate: unlockDate,
    context: context,
  );
  final rawContentKey = aesGcmOpen(
    lockKey,
    base64ToBuffer(wrapIv),
    base64ToBuffer(wrappedKey),
    aad: utf8Bytes(binding),
  );
  final contentKey = VaultKey.fromBits(rawContentKey);
  return decryptText(ciphertext, iv, contentKey, binding);
}
