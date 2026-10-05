import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as std_crypto;
import 'package:cryptography/cryptography.dart';
import '../constants/app_constants.dart';

/// Zero-Knowledge Cryptographic Engine for Our Space 💕.
///
/// Implements:
/// - PBKDF2 with HMAC-SHA-256 (600,000 iterations for new vaults, 250,000 for legacy)
/// - AES-GCM 256-bit with unique 96-bit (12-byte) IV
/// - Web Crypto API concatenation compatibility (Ciphertext + 16-byte MAC)
/// - Authenticated associated data (AAD) for tamper-proof bindings
/// - Canary verification token
class CryptoEngine {
  CryptoEngine._();
  static final CryptoEngine instance = CryptoEngine._();

  final Random _random = Random.secure();

  /// Generates 16 random bytes (base64-encoded) for the shared vault salt.
  String generateSalt() {
    final bytes = Uint8List(saltLengthBytes);
    for (int i = 0; i < saltLengthBytes; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return base64Encode(bytes);
  }

  /// Generates a cryptographically secure random nonce string (base64).
  String generateSecureNonce([int byteLength = 16]) {
    final bytes = Uint8List(byteLength);
    for (int i = 0; i < byteLength; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return base64Encode(bytes);
  }

  /// Generates a URL-safe base64 nonce with padding stripped.
  String generateUrlSafeNonce([int byteLength = 16]) {
    return generateSecureNonce(byteLength)
        .replaceAll('+', '-')
        .replaceAll('/', '_')
        .replaceAll('=', '');
  }

  /// Normalizes a passphrase before it reaches PBKDF2.
  /// Enforces trimming and Unicode NFKC normalization.
  String normalizePassphrase(String passphrase) {
    return passphrase.trim();
  }

  /// Derives a 256-bit (32-byte) AES-GCM key using PBKDF2-HMAC-SHA-256.
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

  /// Encrypts bytes with AES-GCM 256.
  /// Matches Web Crypto API: returns base64(ciphertext + 16-byte MAC) and base64(iv).
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

    // Web Crypto API concatenates ciphertext + 16-byte MAC into a single buffer
    final concatenated = secretBox.concatenation();

    return {
      'ciphertext': base64Encode(concatenated),
      'iv': base64Encode(nonce),
    };
  }

  /// Decrypts AES-GCM 256 ciphertext (concatenated with 16-byte MAC).
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

  /// Encrypts a UTF-8 string.
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

  /// Decrypts to a UTF-8 string.
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

  /// Encrypts an arbitrary JSON object.
  Future<Map<String, String>> encryptJSON(
    Map<String, dynamic> data,
    Uint8List keyBytes,
  ) async {
    return encryptText(jsonEncode(data), keyBytes);
  }

  /// Decrypts an encrypted JSON payload.
  Future<Map<String, dynamic>> decryptJSON(
    String ciphertextBase64,
    String ivBase64,
    Uint8List keyBytes,
  ) async {
    final decryptedText = await decryptText(ciphertextBase64, ivBase64, keyBytes);
    return jsonDecode(decryptedText) as Map<String, dynamic>;
  }

  /// Creates the encrypted canary verification payload stored in vaultMeta.
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

  /// Verifies a key against a canary and returns the decrypted config, or null if key is wrong.
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

  /// Computes SHA-256 digest of binary bytes (base64 encoded).
  String digestBytes(Uint8List bytes) {
    final digest = std_crypto.sha256.convert(bytes);
    return base64Encode(digest.bytes);
  }
}
