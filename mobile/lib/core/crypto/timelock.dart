import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'crypto_engine.dart';
import '../constants/app_constants.dart';

const String timeLockContext = 'our-space/time-lock/v1';

class TimeLockedException implements Exception {
  final String unlockDate;
  TimeLockedException(this.unlockDate);

  @override
  String toString() => 'Letter is sealed until $unlockDate 💕';
}

/// Cryptographic time-lock engine for secret capsule love letters.
///
/// Letters are sealed using key wrapping: the body is encrypted under an
/// ephemeral content key, which is itself encrypted under a key derived from
/// the unlock date and the master vault key. Tampering with the unlock date
/// mathematically corrupts key derivation and decryption fails.
class TimeLockEngine {
  TimeLockEngine._();

  static final Random _random = Random.secure();

  /// Computes the local midnight timestamp for a given YYYY-MM-DD date.
  static int? getTimeLockBoundary(String unlockDate) {
    try {
      final parts = unlockDate.split('-');
      if (parts.length < 3) return null;
      final year = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final day = int.parse(parts[2].substring(0, 2));
      final localMidnight = DateTime(year, month, day, 0, 0, 0, 0);
      return localMidnight.millisecondsSinceEpoch;
    } catch (_) {
      return null;
    }
  }

  /// True when the current time is past the unlock date boundary.
  static bool isTimeLockOpen(String? unlockDate, [int? now]) {
    if (unlockDate == null || unlockDate.isEmpty) return true;
    final boundary = getTimeLockBoundary(unlockDate);
    if (boundary == null) return true;
    final current = now ?? DateTime.now().millisecondsSinceEpoch;
    return current >= boundary;
  }

  static String _timeLockBinding(String unlockDate, String context) {
    return '$timeLockContext|$unlockDate|$context';
  }

  /// Seals letter plaintext into a time-locked envelope.
  static Future<Map<String, dynamic>> sealTimeLocked(
    String plainText,
    String unlockDate,
    Uint8List vaultKey, {
    String context = '',
  }) async {
    final boundary = getTimeLockBoundary(unlockDate);
    if (boundary == null) {
      throw ArgumentError('sealTimeLocked: unlockDate is not a valid date.');
    }

    final binding = _timeLockBinding(unlockDate, context);
    final bindingBytes = Uint8List.fromList(utf8.encode(binding));

    // 1. Generate random 32-byte content key
    final contentKey = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      contentKey[i] = _random.nextInt(256);
    }

    // 2. Encrypt plaintext under contentKey with binding as AAD
    final bodyEncrypted = await CryptoEngine.instance.encryptBytes(
      Uint8List.fromList(utf8.encode(plainText)),
      contentKey,
      aad: bindingBytes,
    );

    // 3. Generate salt & IVs
    final lockSalt = Uint8List.fromList(
      List.generate(32, (_) => _random.nextInt(256)),
    );
    final lockIv = Uint8List.fromList(
      List.generate(ivLengthBytes, (_) => _random.nextInt(256)),
    );
    final wrapIv = Uint8List.fromList(
      List.generate(ivLengthBytes, (_) => _random.nextInt(256)),
    );

    // 4. Derive material = AES-GCM(vaultKey, lockIv, binding)
    final materialEncrypted = await CryptoEngine.instance.encryptBytes(
      bindingBytes,
      vaultKey,
      iv: lockIv,
    );
    final materialBytes = base64Decode(materialEncrypted['ciphertext']!);

    // 5. Derive lockKey = HKDF-SHA256(material, salt = lockSalt, info = binding)
    final hkdf = Hkdf(
      hmac: Hmac.sha256(),
      outputLength: 32,
    );
    final lockKeySecret = await hkdf.deriveKey(
      secretKey: SecretKey(materialBytes),
      nonce: lockSalt,
      info: bindingBytes,
    );
    final lockKeyBytes = Uint8List.fromList(await lockKeySecret.extractBytes());

    // 6. Wrap contentKey under lockKey with binding as AAD
    final wrappedEncrypted = await CryptoEngine.instance.encryptBytes(
      contentKey,
      lockKeyBytes,
      iv: wrapIv,
      aad: bindingBytes,
    );

    return {
      'lockVersion': 1,
      'unlockDate': unlockDate,
      'ciphertext': bodyEncrypted['ciphertext']!,
      'iv': bodyEncrypted['iv']!,
      'wrappedKey': wrappedEncrypted['ciphertext']!,
      'wrapIv': wrappedEncrypted['iv']!,
      'lockSalt': base64Encode(lockSalt),
      'lockIv': base64Encode(lockIv),
    };
  }

  /// Unseals a time-locked letter. Throws TimeLockedException if accessed before unlock date.
  static Future<String> unsealTimeLocked(
    Map<String, dynamic> sealed,
    Uint8List vaultKey, {
    String context = '',
    int? now,
  }) async {
    final unlockDate = sealed['unlockDate'] as String?;
    if (unlockDate == null || unlockDate.isEmpty) {
      throw ArgumentError('unsealTimeLocked: missing unlockDate');
    }

    if (!isTimeLockOpen(unlockDate, now)) {
      throw TimeLockedException(unlockDate);
    }

    final binding = _timeLockBinding(unlockDate, context);
    final bindingBytes = Uint8List.fromList(utf8.encode(binding));

    final lockIv = base64Decode(sealed['lockIv'] as String);
    final lockSalt = base64Decode(sealed['lockSalt'] as String);
    final wrappedKey = sealed['wrappedKey'] as String;
    final wrapIv = sealed['wrapIv'] as String;
    final ciphertext = sealed['ciphertext'] as String;
    final iv = sealed['iv'] as String;

    // 1. Re-derive material = AES-GCM(vaultKey, lockIv, binding)
    final materialEncrypted = await CryptoEngine.instance.encryptBytes(
      bindingBytes,
      vaultKey,
      iv: lockIv,
    );
    final materialBytes = base64Decode(materialEncrypted['ciphertext']!);

    // 2. Re-derive lockKey = HKDF-SHA256(material, salt = lockSalt, info = binding)
    final hkdf = Hkdf(
      hmac: Hmac.sha256(),
      outputLength: 32,
    );
    final lockKeySecret = await hkdf.deriveKey(
      secretKey: SecretKey(materialBytes),
      nonce: lockSalt,
      info: bindingBytes,
    );
    final lockKeyBytes = Uint8List.fromList(await lockKeySecret.extractBytes());

    // 3. Unseal contentKey
    final contentKey = await CryptoEngine.instance.decryptBytes(
      wrappedKey,
      wrapIv,
      lockKeyBytes,
      aad: bindingBytes,
    );

    // 4. Decrypt body
    final bodyBytes = await CryptoEngine.instance.decryptBytes(
      ciphertext,
      iv,
      contentKey,
      aad: bindingBytes,
    );

    return utf8.decode(bodyBytes);
  }
}
