import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine/crypto/aes_gcm.dart';
import 'package:our_space_mobile/core/engine/crypto/backup.dart';
import 'package:our_space_mobile/core/engine/crypto/base64.dart';
import 'package:our_space_mobile/core/engine/crypto/canary.dart';
import 'package:our_space_mobile/core/engine/crypto/derived_ids.dart';
import 'package:our_space_mobile/core/engine/crypto/envelope.dart';
import 'package:our_space_mobile/core/engine/crypto/js_compat.dart';
import 'package:our_space_mobile/core/engine/crypto/kdf.dart';
import 'package:our_space_mobile/core/engine/crypto/time_lock.dart';
import 'package:our_space_mobile/core/engine/domain/daily_question.dart';
import 'package:our_space_mobile/core/engine/domain/limits.dart';
import 'package:our_space_mobile/core/engine/invite/invite.dart';
import 'package:our_space_mobile/core/engine/storage/tables.dart';
import 'package:our_space_mobile/core/engine/sync/mailbox.dart';

import 'support/harness.dart';

void main() {
  final fixture = readFixture('web_sealed.json');
  late VaultKey key;

  setUpAll(() async {
    key = await deriveKeyFromPassphrase(
      fixture['passphrase'] as String,
      fixture['salt'] as String,
      iterations: fixture['kdfIterations'] as int,
    );
  });

  group('key derivation', () {
    test('Dart derives the exact key the web derived at 600,000 iterations', () {
      expect(bufferToBase64(key.rawBytes), fixture['keyBits']);
    });

    test('passphrase normalisation matches NFKC plus JS trim', () {
      for (final vector in (fixture['normalizeVectors'] as List).cast<Map>()) {
        expect(normalizePassphrase(vector['input']), vector['output'], reason: vector['input'] as String);
      }
    });

    test('raw and normalised KDF vectors match', () async {
      for (final vector in (fixture['kdfVectors'] as List).cast<Map>()) {
        final bits = await deriveVaultKeyBits(
          vector['passphrase'] as String,
          vector['salt'] as String,
          iterations: vector['iterations'] as int,
          normalize: vector['normalize'] as bool,
        );
        expect(bufferToBase64(bits), vector['bits'], reason: '${vector['passphrase']}');
      }
    });

    test('a vault sealed with the raw passphrase still unlocks through the fallback', () async {
      final raw = asStringMap(fixture['rawVault'])!;
      final derived = await deriveKeyWithVerification(
        raw['passphrase'] as String,
        raw['salt'] as String,
        (candidate) => readCanary(candidate, raw) != null,
        iterations: raw['kdfIterations'] as int,
      );
      expect(derived.normalized, isFalse);
      expect(derived.iterations, 1000);
    });

    test('base64 helpers accept and reject exactly what the web does', () {
      for (final vector in (fixture['base64Vectors'] as List).cast<Map>()) {
        final input = vector['input'] as String;
        expect(isValidBase64(input), vector['valid'], reason: input);
        expect(isValidSalt(input), vector['validSalt'], reason: input);
        String? bytes;
        try {
          bytes = bufferToBase64(base64ToBuffer(input));
        } catch (_) {
          bytes = null;
        }
        expect(bytes, vector['bytes'], reason: input);
      }
    });
  });

  group('vault identity', () {
    test('the web canary opens and carries the couple config', () {
      final meta = asStringMap(fixture['vaultMeta'])!;
      final payload = readCanary(key, meta)!;
      final config = asStringMap(fixture['canaryConfig'])!;
      expect(payload['token'], vaultCanaryToken);
      expect(payload['coupleNames'], config['coupleNames']);
      expect(payload['startDate'], config['startDate']);
      expect(payload['createdAt'], config['createdAt']);
      expect(payload['updatedAt'], config['updatedAt']);
    });

    test('a wrong key does not read the canary', () async {
      final wrong = VaultKey.fromBits(randomBytes(32));
      expect(readCanary(wrong, asStringMap(fixture['vaultMeta'])), isNull);
    });

    test('mailbox id, person slots and record keys match', () {
      final derived = asStringMap(fixture['derived'])!;
      expect(deriveMailboxId(key), derived['mailboxId']);
      expect(derivePersonSlots(key), derived['personSlots']);
      for (final entry in (derived['recordKeys'] as List).cast<Map>()) {
        expect(recordKey(entry['id']), entry['key'], reason: entry['id'] as String);
      }
    });

    test('the daily question order and the question for each day match', () {
      final derived = asStringMap(fixture['derived'])!;
      expect(buildQuestionOrder(key).map((q) => q.id).toList(), derived['questionOrder']);
      for (final entry in (derived['questionForDay'] as List).cast<Map>()) {
        final when = entry['when'] as int;
        final q = getQuestionForDay(key, when);
        expect(q.question.id, entry['id'], reason: '$when');
        expect(q.day, entry['day'], reason: '$when');
        expect(q.index, entry['index'], reason: '$when');
        expect(dayIndex(when), entry['dayIndex'], reason: '$when');
      }
    });

    test('the question bank has the same ids, tones, text and order', () {
      final questions = (fixture['questions'] as List).cast<Map>();
      expect(allQuestions.length, questions.length);
      for (var i = 0; i < questions.length; i++) {
        expect(allQuestions[i].toJson(), questions[i]);
      }
    });

    test('limits and constants match', () {
      final constants = asStringMap(fixture['constants'])!;
      expect(recordSchemaVersion, constants['recordSchemaVersion']);
      expect(minPassphraseLength, constants['minPassphraseLength']);
      expect(pbkdf2IterationsCurrent, constants['pbkdf2Iterations']);
      expect(maxImageBlobBytes, constants['maxImageBlobBytes']);
      expect(maxSingleRecordBytes, constants['maxSingleRecordBytes']);
      expect(maxBatchPayloadBytes, constants['maxBatchPayloadBytes']);
      expect(maxMailboxObjectBytes, constants['maxObjectBytes']);
      expect(syncedTables, constants['syncedTables']);
      expect(exportedTables, constants['exportedTables']);
    });
  });

  group('sealed rows', () {
    final rows = asStringMap(fixture['rows'])!;

    test('there is at least one web row for every synced table', () {
      for (final table in syncedTables) {
        expect((rows[table] as List).isNotEmpty, isTrue, reason: table);
      }
    });

    for (final table in syncedTables) {
      test('Dart opens every web $table row exactly as the web does', () {
        for (final entry in (rows[table] as List).cast<Map>()) {
          final row = rowFromFixture(asStringMap(entry['row'])!);
          final opened = decryptRecord(row, key, table: table);
          final expected = fromFixtureValue(entry['expected']);
          expect(jsonDeepEquals(opened, expected), isTrue, reason: '$table/${row['id']}\n$opened\n$expected');
          expect(opened['_headerTampered'], isFalse);
          expect(opened['_tableUnverified'], isFalse);
        }
      });
    }

    test('photos open after the binary digest checks out', () {
      final memory = (rows[memoriesTable] as List).cast<Map>().first;
      final row = rowFromFixture(asStringMap(memory['row'])!);
      final photo = decryptBlob(row['imageBlob'] as Uint8List, key);
      expect(bufferToBase64(photo), asStringMap(fixture['blob'])!['plain']);
    });

    test('sealed letters unseal, and future ones stay locked', () {
      for (final entry in (rows[lettersTable] as List).cast<Map>()) {
        final plain = decryptRecord(rowFromFixture(asStringMap(entry['row'])!), key, table: lettersTable);
        final sealed = plain['sealedContent'];
        if (sealed is! Map) continue;
        final id = plain['id'] as String;
        if (id == 'let-interop-future') {
          expect(
            () => unsealTimeLocked(asStringMap(sealed)!, key, context: id),
            throwsA(isA<TimeLockedError>()),
          );
          expect(
            unsealTimeLocked(asStringMap(sealed)!, key, context: id, now: DateTime(2100).millisecondsSinceEpoch),
            'Not yet, my love.',
          );
        } else {
          expect(unsealTimeLocked(asStringMap(sealed)!, key, context: id), 'This one was sealed until 2020.');
          expect(() => unsealTimeLocked(asStringMap(sealed)!, key, context: 'another-letter'), throwsA(anything));
        }
      }
    });

    test('every tamper case is caught the same way the web catches it', () {
      for (final entry in (fixture['tampered'] as List).cast<Map>()) {
        final row = rowFromFixture(asStringMap(entry['row'])!);
        final table = entry['table'] as String;
        final expected = entry['expected'];
        if (expected == 'throws') {
          expect(() => decryptRecord(row, key, table: table), throwsA(anything), reason: entry['name'] as String);
          continue;
        }
        final opened = decryptRecord(row, key, table: table);
        expect(jsonDeepEquals(opened, fromFixtureValue(expected)), isTrue, reason: '${entry['name']}\n$opened\n$expected');
      }
    });
  });

  group('other sealed shapes', () {
    test('the sealed manifest opens to the same manifest', () {
      final manifest = asStringMap(fixture['manifest'])!;
      final sealed = asStringMap(manifest['sealed'])!;
      final opened = decryptJson(sealed['ciphertext'] as String, sealed['iv'] as String, key);
      expect(jsonDeepEquals(opened, manifest['plain']), isTrue);
    });

    test('the photo blob opens', () {
      final blob = asStringMap(fixture['blob'])!;
      expect(bufferToBase64(decryptBlob(base64ToBuffer(blob['packed']), key)), blob['plain']);
    });

    test('time locks with and without context, and with ISO boundaries', () {
      for (final lock in (fixture['timeLocks'] as List).cast<Map>()) {
        final sealed = asStringMap(lock['sealed'])!;
        final context = lock['context'] as String;
        expect(getTimeLockBoundary(lock['unlockDate']), lock['boundaryLocal']);
        if (lock['unlockDate'] == '2099-01-01') {
          expect(() => unsealTimeLocked(sealed, key, context: context), throwsA(isA<TimeLockedError>()));
          continue;
        }
        expect(unsealTimeLocked(sealed, key, context: context), lock['plain']);
      }
    });

    test('texts with and without additional data', () {
      for (final text in (fixture['texts'] as List).cast<Map>()) {
        expect(
          decryptText(text['ciphertext'] as String, text['iv'] as String, key, text['aad']),
          text['plain'],
        );
      }
    });

    test('the backup file opens with its own passphrase', () async {
      final backup = asStringMap(fixture['backup'])!;
      final payload = await decryptBackupContainer(backup['container'], backup['passphrase'] as String);
      final tables = asStringMap(payload['tables'])!;
      expect((tables['vaultMeta'] as List).length, 1);
      expect(asStringMap((tables['vaultMeta'] as List).first)!['salt'], fixture['salt']);
      await expectLater(
        decryptBackupContainer(backup['container'], 'not the right backup passphrase'),
        throwsA(isA<BackupError>()),
      );
    });
  });

  group('invites', () {
    final invites = asStringMap(fixture['invites'])!;

    test('Dart parses every link exactly as the web does', () {
      for (final entry in (invites['parsed'] as List).cast<Map>()) {
        final parsed = parseInvite(entry['input']);
        expect(parsed?.toJson(), entry['result'], reason: entry['input'] as String);
      }
    });

    test('Dart builds the identical link from the same inputs', () {
      for (final entry in (invites['built'] as List).cast<Map>()) {
        final options = entry['options'];
        String url;
        if (options is String) {
          url = buildInviteUrl(entry['peerId'] as String?, entry['salt'] as String?, baseUrl: options);
        } else {
          final o = asStringMap(options)!;
          url = buildInviteUrl(
            entry['peerId'] as String?,
            entry['salt'] as String?,
            baseUrl: o['baseUrl'] as String?,
            startDate: o['startDate'] as String?,
            coupleNames: o['coupleNames'] as String?,
            canary: o['canary'] as String?,
            canaryIv: o['canaryIv'] as String?,
          );
        }
        expect(url, entry['url']);
        expect(parseInvite(url)?.toJson(), entry['parsed']);
      }
    });
  });
}
