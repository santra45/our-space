import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

const int aesKeyLengthBytes = 32;
const int gcmTagLengthBytes = 16;

class CryptoFailure implements Exception {
  CryptoFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class VaultKey {
  VaultKey._(this._bytes);

  factory VaultKey.fromBits(List<int> bits) {
    if (bits.length != aesKeyLengthBytes) {
      throw CryptoFailure('importVaultKeyFromBits: expected 32 bytes of key material');
    }
    return VaultKey._(Uint8List.fromList(bits));
  }

  final Uint8List _bytes;

  Uint8List get rawBytes => Uint8List.fromList(_bytes);

  SecretKeyData get _secret => SecretKeyData(_bytes);

  bool sameKeyAs(VaultKey other) {
    if (other._bytes.length != _bytes.length) return false;
    var diff = 0;
    for (var i = 0; i < _bytes.length; i++) {
      diff |= _bytes[i] ^ other._bytes[i];
    }
    return diff == 0;
  }
}

final DartAesGcm _gcm = DartAesGcm.with256bits();

Uint8List aesGcmSeal(VaultKey key, List<int> iv, List<int> plain, {List<int>? aad}) {
  final box = _gcm.encryptSync(
    plain,
    secretKeyData: key._secret,
    nonce: iv,
    aad: aad ?? const <int>[],
  );
  final out = Uint8List(box.cipherText.length + gcmTagLengthBytes);
  out.setRange(0, box.cipherText.length, box.cipherText);
  out.setRange(box.cipherText.length, out.length, box.mac.bytes);
  return out;
}

Uint8List aesGcmOpen(VaultKey key, List<int> iv, List<int> sealed, {List<int>? aad}) {
  if (sealed.length < gcmTagLengthBytes) {
    throw CryptoFailure('The operation failed for an operation-specific reason');
  }
  if (iv.isEmpty) {
    throw CryptoFailure('The operation failed for an operation-specific reason');
  }
  final split = sealed.length - gcmTagLengthBytes;
  final box = SecretBox(
    sealed.sublist(0, split),
    nonce: iv,
    mac: Mac(sealed.sublist(split)),
  );
  try {
    final clear = _gcm.decryptSync(
      box,
      secretKeyData: key._secret,
      aad: aad ?? const <int>[],
    );
    return Uint8List.fromList(clear);
  } on SecretBoxAuthenticationError {
    throw CryptoFailure('The operation failed for an operation-specific reason');
  } catch (_) {
    throw CryptoFailure('The operation failed for an operation-specific reason');
  }
}
