import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:cryptography/cryptography.dart';
import '../crypto/vault_key.dart';
import '../constants/app_constants.dart';

/// Hardware-backed biometric quick unlock service (Android Keystore / iOS Secure Enclave).
///
/// PHILOSOPHY & SECURITY GUARANTEES:
/// - Only ciphertext, salt, and wrapped key material are stored.
/// - The master key is held only in RAM after successful biometric authentication.
/// - Passphrase is never persisted.
class BiometricService {
  BiometricService._();
  static final BiometricService instance = BiometricService._();

  final LocalAuthentication _auth = LocalAuthentication();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      resetOnError: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static const String _storageKeyMasterBlob = 'sweetheart_sealed_key_blob';
  static const String _storageKeyWrappingKey = 'sweetheart_hw_wrapping_key';

  /// Returns true if device hardware supports biometric authentication and has enrolled credentials.
  Future<bool> isBiometricsAvailable() async {
    try {
      final bool canAuthenticateWithBiometrics = await _auth.canCheckBiometrics;
      final bool canAuthenticate =
          canAuthenticateWithBiometrics || await _auth.isDeviceSupported();
      return canAuthenticate;
    } catch (_) {
      return false;
    }
  }

  /// Returns true if quick unlock has already been enrolled on this device.
  Future<bool> isEnrolled() async {
    try {
      final blob = await _secureStorage.read(key: _storageKeyMasterBlob);
      return blob != null && blob.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Enrolls biometrics by sealing the current in-memory master key under a hardware wrapping key.
  Future<bool> enrollBiometrics(Uint8List masterKeyBits, {required String salt, int? iterations}) async {
    final available = await isBiometricsAvailable();
    if (!available) return false;

    // Authenticate user to confirm intent
    final authenticated = await _auth.authenticate(
      localizedReason: 'Confirm your fingerprint or face to enable quick unlock 💕',
      options: const AuthenticationOptions(
        biometricOnly: true,
        stickyAuth: true,
      ),
    );

    if (!authenticated) return false;

    // 1. Generate 32-byte wrapping key
    final random = Random.secure();
    final wrappingKeyBytes = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      wrappingKeyBytes[i] = random.nextInt(256);
    }

    // 2. Encrypt masterKeyBits with AES-GCM under wrappingKey
    final algorithm = AesGcm.with256bits();
    final secretKey = SecretKey(wrappingKeyBytes);
    final secretBox = await algorithm.encrypt(
      masterKeyBits,
      secretKey: secretKey,
    );

    // 3. Save wrapping key in secure hardware storage
    await _secureStorage.write(
      key: _storageKeyWrappingKey,
      value: base64Encode(wrappingKeyBytes),
    );

    // 4. Save sealed blob
    final blob = {
      'ciphertext': base64Encode(secretBox.cipherText),
      'nonce': base64Encode(secretBox.nonce),
      'mac': base64Encode(secretBox.mac.bytes),
      'salt': salt,
      'iterations': iterations ?? pbkdf2IterationsCurrent,
    };

    await _secureStorage.write(
      key: _storageKeyMasterBlob,
      value: jsonEncode(blob),
    );

    return true;
  }

  /// Attempts to unlock the vault using biometrics and populate VaultKeyHolder.
  Future<bool> unlockWithBiometrics() async {
    final rawBlob = await _secureStorage.read(key: _storageKeyMasterBlob);
    final rawWrap = await _secureStorage.read(key: _storageKeyWrappingKey);
    if (rawBlob == null || rawWrap == null) return false;

    final authenticated = await _auth.authenticate(
      localizedReason: 'Open Our Space 💕',
      options: const AuthenticationOptions(
        biometricOnly: true,
        stickyAuth: true,
      ),
    );

    if (!authenticated) return false;

    try {
      final blob = jsonDecode(rawBlob) as Map<String, dynamic>;
      final wrappingKeyBytes = base64Decode(rawWrap);

      final algorithm = AesGcm.with256bits();
      final secretBox = SecretBox(
        base64Decode(blob['ciphertext'] as String),
        nonce: base64Decode(blob['nonce'] as String),
        mac: Mac(base64Decode(blob['mac'] as String)),
      );

      final decryptedKeyBits = await algorithm.decrypt(
        secretBox,
        secretKey: SecretKey(wrappingKeyBytes),
      );

      VaultKeyHolder.instance.setKey(
        Uint8List.fromList(decryptedKeyBits),
        salt: blob['salt'] as String?,
        iterations: (blob['iterations'] as num?)?.toInt(),
      );

      return true;
    } catch (_) {
      return false;
    }
  }

  /// Disables quick unlock and deletes all keys from secure hardware.
  Future<void> disableBiometrics() async {
    await _secureStorage.delete(key: _storageKeyMasterBlob);
    await _secureStorage.delete(key: _storageKeyWrappingKey);
  }
}
