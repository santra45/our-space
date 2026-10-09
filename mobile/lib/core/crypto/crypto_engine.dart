import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as std_crypto;
import 'package:cryptography/cryptography.dart';
import '../constants/app_constants.dart';

class CryptoEngine {
  CryptoEngine._();
  static final CryptoEngine instance = CryptoEngine._();

  final Random _random = Random.secure();

  String generateSalt() {
    final bytes = Uint8List(saltLengthBytes);
    for (int i = 0; i < saltLengthBytes; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return base64Encode(bytes);
  }

  String generateSecureNonce([int byteLength = 16]) {
    final bytes = Uint8List(byteLength);
    for (int i = 0; i < byteLength; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return base64Encode(bytes);
  }

  String generateUrlSafeNonce([int byteLength = 16]) {
    return generateSecureNonce(byteLength)
        .replaceAll('+', '-')
        .replaceAll('/', '_')
        .replaceAll('=', '');
  }

  String normalizePassphrase(String passphrase) {
    return passphrase.trim();
  }

  Future<Uint8List> deriveKeyFromPassphrase(
    String passphrase,
    String saltBase64, {
    int iterations = pbkdf2IterationsCurrent,
  }) async {
    final normalized = normalizePassphrase(passphrase);
    if (normalized.length < minPassphraseLength) {
      throw ArgumentError(
        'Passphrase must be at least $minPassphraseLength characters long.',
      );
    }

    final saltBytes = base64Decode(saltBase64);
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: aesKeyLengthBits,
    );

    final secretKey = await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(normalized)),
      nonce: saltBytes,
    );

    final keyBytes = await secretKey.extractBytes();
    return Uint8List.fromList(keyBytes);
  }

  Future<Map<String, String>> encryptBytes(
    Uint8List plainBytes,
    Uint8List keyBytes, {
    Uint8List? iv,
    Uint8List? aad,
  }) async {
    final nonce = iv ??
        Uint8List.fromList(
          List<int>.generate(ivLengthBytes, (_) => _random.nextInt(256)),
        );

    final algorithm = AesGcm.with256bits();
    final secretBox = await algorithm.encrypt(
      plainBytes,
      secretKey: SecretKey(keyBytes),
      nonce: nonce,
      aad: aad ?? Uint8List(0),
    );

    final concatenated = secretBox.concatenation();

    return {
      'ciphertext': base64Encode(concatenated),
      'iv': base64Encode(nonce),
    };
  }

  Future<Uint8List> decryptBytes(
    String ciphertextBase64,
    String ivBase64,
    Uint8List keyBytes, {
    Uint8List? aad,
  }) async {
    final concatenated = base64Decode(ciphertextBase64);
    final iv = base64Decode(ivBase64);

    if (concatenated.length < 16) {
      throw ArgumentError('Malformed ciphertext: too short for AES-GCM MAC.');
    }

    final algorithm = AesGcm.with256bits();
    final secretBox = SecretBox.fromConcatenation(
      concatenated,
      nonceLength: iv.length,
      macLength: 16,
    );

    final decrypted = await algorithm.decrypt(
      SecretBox(
        secretBox.cipherText,
        nonce: iv,
        mac: secretBox.mac,
      ),
      secretKey: SecretKey(keyBytes),
      aad: aad ?? Uint8List(0),
    );

    return Uint8List.fromList(decrypted);
  }

  Future<Map<String, String>> encryptText(
    String plainText,
    Uint8List keyBytes, {
    String? aadText,
  }) async {
    return encryptBytes(
      Uint8List.fromList(utf8.encode(plainText)),
      keyBytes,
      aad: aadText != null ? Uint8List.fromList(utf8.encode(aadText)) : null,
    );
  }

  Future<String> decryptText(
    String ciphertextBase64,
    String ivBase64,
    Uint8List keyBytes, {
    String? aadText,
  }) async {
    final bytes = await decryptBytes(
      ciphertextBase64,
      ivBase64,
      keyBytes,
      aad: aadText != null ? Uint8List.fromList(utf8.encode(aadText)) : null,
    );
    return utf8.decode(bytes);
  }

  Future<Map<String, String>> encryptJSON(
    Map<String, dynamic> data,
    Uint8List keyBytes,
  ) async {
    return encryptText(jsonEncode(data), keyBytes);
  }

  Future<Map<String, dynamic>> decryptJSON(
    String ciphertextBase64,
    String ivBase64,
    Uint8List keyBytes,
  ) async {
    final decryptedText = await decryptText(ciphertextBase64, ivBase64, keyBytes);
    return jsonDecode(decryptedText) as Map<String, dynamic>;
  }

  Future<Map<String, String>> createCanary(
    Uint8List keyBytes, {
    String coupleNames = 'Us',
    String startDate = '',
    int? createdAt,
    int? updatedAt,
  }) async {
    final payload = {
      'token': vaultCanaryToken,
      'coupleNames': coupleNames,
      'startDate': startDate,
      'createdAt': createdAt ?? DateTime.now().millisecondsSinceEpoch,
      'updatedAt': updatedAt ?? 0,
    };
    final encrypted = await encryptJSON(payload, keyBytes);
    return {
      'canary': encrypted['ciphertext']!,
      'canaryIv': encrypted['iv']!,
    };
  }

  Future<Map<String, dynamic>?> readCanary(
    Uint8List keyBytes,
    Map<String, dynamic> meta,
  ) async {
    final canary = meta['canary'] as String?;
    final canaryIv = meta['canaryIv'] as String?;
    if (canary == null || canaryIv == null) return null;

    try {
      final payload = await decryptJSON(canary, canaryIv, keyBytes);
      if (payload['token'] != vaultCanaryToken) return null;
      return payload;
    } catch (_) {
      return null;
    }
  }

  String digestBytes(Uint8List bytes) {
    final digest = std_crypto.sha256.convert(bytes);
    return base64Encode(digest.bytes);
  }
}
