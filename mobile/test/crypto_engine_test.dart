import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/crypto/crypto_engine.dart';
import 'package:our_space_mobile/core/crypto/envelope.dart';
import 'package:our_space_mobile/core/crypto/timelock.dart';
import 'package:our_space_mobile/core/storage/tombstone_helper.dart';

void main() {
  group('Our Space 💕 — Flutter Cryptographic Invariants', () {
    late CryptoEngine crypto;

    setUp(() {
      crypto = CryptoEngine.instance;
    });

    test('1. Primitives: salt, nonces, and normalization', () {
      final salt = crypto.generateSalt();
      expect(salt.isNotEmpty, isTrue);

      final nonce = crypto.generateSecureNonce(16);
      expect(nonce.isNotEmpty, isTrue);

      final urlNonce = crypto.generateUrlSafeNonce(16);
      expect(urlNonce.contains('+'), isFalse);
      expect(urlNonce.contains('/'), isFalse);
      expect(urlNonce.contains('='), isFalse);

      final normalized = crypto.normalizePassphrase('  our-secret-passphrase-12345  ');
      expect(normalized, equals('our-secret-passphrase-12345'));
    });

    test('2. Key derivation: PBKDF2 generates 32 bytes and rejects short phrases', () async {
      const validPassphrase = 'this-is-a-valid-passphrase-for-testing';
      final salt = crypto.generateSalt();

      final key = await crypto.deriveKeyFromPassphrase(
        validPassphrase,
        salt,
        iterations: 1000,
      );

      expect(key.length, equals(32));

      expect(
        () async => await crypto.deriveKeyFromPassphrase('too-short', salt),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('3. AES-GCM 256 encryption and decryption round-trip', () async {
      final salt = crypto.generateSalt();
      final key = await crypto.deriveKeyFromPassphrase('passphrase-for-roundtrip-test-16chars', salt, iterations: 100);

      final testData = {'greeting': 'Hello my love', 'count': 42, 'active': true};
      final encrypted = await crypto.encryptJSON(testData, key);

      expect(encrypted['ciphertext']!.isNotEmpty, isTrue);
      expect(encrypted['iv']!.isNotEmpty, isTrue);

      final decrypted = await crypto.decryptJSON(encrypted['ciphertext']!, encrypted['iv']!, key);
      expect(decrypted['greeting'], equals('Hello my love'));
      expect(decrypted['count'], equals(42));
      expect(decrypted['active'], equals(true));
    });

    test('4. Schema v2 Envelopes: authenticated metadata and tampering detection', () async {
      final salt = crypto.generateSalt();
      final key = await crypto.deriveKeyFromPassphrase('passphrase-for-envelopes-test-16chars', salt, iterations: 100);

      final record = {
        'id': 'mem-001',
        'caption': 'Our sunset walk',
        'updatedAt': 1700000000000,
        'deleted': false,
      };

      final envelope = await RecordEnvelope.encryptRecord(record, key, table: 'memories');
      expect(envelope['id'], equals('mem-001'));
      expect(envelope['v'], equals(2));

      final result = await RecordEnvelope.decryptRecord(envelope, key, table: 'memories');
      expect(result.isHeaderTampered, isFalse);
      expect(result.data['caption'], equals('Our sunset walk'));

      final tampered = Map<String, dynamic>.from(envelope);
      tampered['updatedAt'] = 1700000099999;

      final tamperedResult = await RecordEnvelope.decryptRecord(tampered, key, table: 'memories');
      expect(tamperedResult.isHeaderTampered, isTrue);
    });

    test('5. Time-locked letters: refuses before date, opens on/after date', () async {
      final salt = crypto.generateSalt();
      final key = await crypto.deriveKeyFromPassphrase('passphrase-for-timelock-test-16chars', salt, iterations: 100);

      const secretText = 'Happy 10th anniversary my sweetheart!';
      const futureDate = '2099-01-01';
      const pastDate = '2020-01-01';

      final sealedFuture = await TimeLockEngine.sealTimeLocked(secretText, futureDate, key, context: 'let-1');
      expect(
        () async => await TimeLockEngine.unsealTimeLocked(sealedFuture, key, context: 'let-1'),
        throwsA(isA<TimeLockedException>()),
      );

      final sealedPast = await TimeLockEngine.sealTimeLocked(secretText, pastDate, key, context: 'let-2');
      final unsealed = await TimeLockEngine.unsealTimeLocked(sealedPast, key, context: 'let-2');
      expect(unsealed, equals(secretText));
    });

    test('6. Tombstone & LWW Merge: newer timestamp and deletion tie-break win', () {
      final oldRecord = {'id': '1', 'updatedAt': 100, 'deleted': 0};
      final newRecord = {'id': '1', 'updatedAt': 200, 'deleted': 0};

      expect(TombstoneHelper.incomingWins(oldRecord, newRecord), isTrue);
      expect(TombstoneHelper.incomingWins(newRecord, oldRecord), isFalse);

      final sameTimeEdit = {'id': '1', 'updatedAt': 150, 'deleted': 0, 'ciphertext': 'a'};
      final sameTimeDelete = {'id': '1', 'updatedAt': 150, 'deleted': 1, 'ciphertext': 'b'};

      expect(TombstoneHelper.incomingWins(sameTimeEdit, sameTimeDelete), isTrue);
      expect(TombstoneHelper.incomingWins(sameTimeDelete, sameTimeEdit), isFalse);
    });
  });
}
