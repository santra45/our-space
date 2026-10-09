import 'dart:async';
import 'dart:typed_data';

import 'package:unorm_dart/unorm_dart.dart' as unorm;

import 'aes_gcm.dart';
import 'base64.dart';
import 'js_compat.dart';
import 'pbkdf2.dart';

const int pbkdf2IterationsCurrent = 600000;
const int minPassphraseLength = 16;

class PassphraseError implements Exception {
  PassphraseError(this.message);
  final String message;
  @override
  String toString() => message;
}

String normalizePassphrase(Object? passphrase) {
  if (passphrase is! String) return '';
  return jsTrim(unorm.nfkc(passphrase));
}

int _iterationsFrom(Object? iterations) {
  if (iterations is num && iterations.isFinite) return iterations.floor();
  return pbkdf2IterationsCurrent;
}

Future<Uint8List> deriveVaultKeyBits(
  String passphrase,
  String saltBase64, {
  num? iterations,
  bool normalize = true,
}) async {
  final count = _iterationsFrom(iterations);
  final effective = normalize ? normalizePassphrase(passphrase) : passphrase;
  if (effective.length < minPassphraseLength) {
    throw PassphraseError('Passphrase must be at least $minPassphraseLength characters long');
  }
  if (!isValidBase64(saltBase64)) {
    throw PassphraseError('Invalid vault salt');
  }
  return _derive(effective, saltBase64, count);
}

Future<Uint8List> _derive(String passphrase, String saltBase64, int iterations) {
  if (iterations < 1) {
    throw PassphraseError('Invalid iteration count');
  }
  return pbkdf2HmacSha256Async(
    utf8Bytes(passphrase),
    base64ToBuffer(saltBase64),
    iterations,
    aesKeyLengthBytes,
  );
}

Future<VaultKey> deriveKeyFromPassphrase(
  String passphrase,
  String saltBase64, {
  num? iterations,
  bool normalize = true,
}) async {
  final bits = await deriveVaultKeyBits(
    passphrase,
    saltBase64,
    iterations: iterations,
    normalize: normalize,
  );
  return VaultKey.fromBits(bits);
}

VaultKey importVaultKeyFromBits(List<int> bits) => VaultKey.fromBits(bits);

class DerivedKey {
  DerivedKey({required this.key, required this.iterations, required this.normalized});
  final VaultKey key;
  final int iterations;
  final bool normalized;
}

typedef KeyVerifier = FutureOr<bool> Function(VaultKey candidate);

Future<DerivedKey> deriveKeyWithVerification(
  String passphrase,
  String saltBase64,
  KeyVerifier verify, {
  num? iterations,
}) async {
  if (!isValidBase64(saltBase64)) {
    throw PassphraseError('Invalid vault salt');
  }
  final normalized = normalizePassphrase(passphrase);
  final raw = passphrase;

  final iterationCandidates = <int>[];
  if (iterations is num && iterations.isFinite) iterationCandidates.add(iterations.floor());
  iterationCandidates.add(pbkdf2IterationsCurrent);

  final passphraseCandidates = raw == normalized ? [normalized] : [normalized, raw];

  final seen = <String>{};
  for (var variant = 0; variant < passphraseCandidates.length; variant++) {
    final candidate = passphraseCandidates[variant];
    if (candidate.length < minPassphraseLength) continue;
    for (final count in iterationCandidates) {
      final fingerprint = '$variant:$count';
      if (seen.contains(fingerprint)) continue;
      seen.add(fingerprint);

      VaultKey key;
      try {
        key = VaultKey.fromBits(await _derive(candidate, saltBase64, count));
      } catch (_) {
        continue;
      }
      try {
        if (await verify(key)) {
          return DerivedKey(key: key, iterations: count, normalized: candidate == normalized);
        }
      } catch (_) {}
    }
  }

  throw PassphraseError('Incorrect passphrase');
}
