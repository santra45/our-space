import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine/crypto/aes_gcm.dart';
import 'package:our_space_mobile/core/engine/crypto/base64.dart';
import 'package:our_space_mobile/core/engine/crypto/derived_ids.dart';
import 'package:our_space_mobile/core/engine/crypto/envelope.dart';
import 'package:our_space_mobile/core/engine/crypto/js_compat.dart';
import 'package:our_space_mobile/core/engine/crypto/kdf.dart';
import 'package:our_space_mobile/core/engine/crypto/time_lock.dart';
import 'package:our_space_mobile/core/engine/domain/daily_question.dart';
import 'package:our_space_mobile/core/engine/identity/device_id.dart';
import 'package:our_space_mobile/core/engine/invite/invite.dart';
import 'package:our_space_mobile/core/engine/storage/tables.dart';
import 'package:our_space_mobile/core/engine/storage/vault_store.dart';
import 'package:our_space_mobile/core/engine/sync/backup_service.dart';
import 'package:our_space_mobile/core/engine/sync/mailbox.dart';
import 'package:our_space_mobile/core/engine/vault/vault_service.dart';

import 'support/fake_mailbox_worker.dart';
import 'support/harness.dart';

const String dartPassphrase = 'dart sealed this for the web 2026 💌';

Map<String, Object?> _plainFields(Object? expected) {
  final map = asStringMap(fromFixtureValue(expected))!;
  return Map<String, Object?>.fromEntries(map.entries.where((e) => !e.key.startsWith('_')));
}

void main() {
  final fixture = readFixture('web_sealed.json');

  test('Dart seals every table, the manifest, photos, letters, invites, a backup and a mailbox for the web', () async {
    final webKey = await deriveKeyFromPassphrase(
      fixture['passphrase'] as String,
      fixture['salt'] as String,
      iterations: fixture['kdfIterations'] as int,
    );

    final store = await openTestStore();
    final device = DeviceIdentity(store.settings);
    final vault = VaultService(store: store, device: device);
    await vault.check();
    expect(vault.state, VaultCheckState.absent);

    final created = await vault.create(
      passphrase: dartPassphrase,
      coupleNames: 'Sam & Alex ✨',
      startDate: '2021-06-14',
    );
    expect(created.ok, isTrue);
    final key = vault.requireKey();
    final meta = (await store.getVaultMeta())!;
    expect(meta['kdfIterations'], pbkdf2IterationsCurrent);

    final photo = base64ToBuffer(asStringMap(fixture['blob'])!['plain']);
    final webRows = asStringMap(fixture['rows'])!;
    final tombstones = <Map<String, Object?>>[];

    for (final table in syncedTables) {
      for (final entry in (webRows[table] as List).cast<Map>()) {
        final fields = _plainFields(entry['expected']);
        final id = fields['id'] as String;
        if (table == memoriesTable) {
          final webBlob = rowFromFixture(asStringMap(entry['row'])!)['imageBlob'] as Uint8List;
          fields['imageBlob'] = encryptBlob(decryptBlob(webBlob, webKey), key);
        }
        final sealed = fields['sealedContent'];
        if (sealed is Map) {
          final body = unsealTimeLocked(
            asStringMap(sealed)!,
            webKey,
            context: id,
            now: DateTime(2100, 2).millisecondsSinceEpoch,
          );
          fields['sealedContent'] = sealTimeLocked(body, fields['unlockDate'] as String, key, context: id);
        }
        if (fields['deleted'] == true) {
          await store.putEncrypted(table, {
            'id': id,
            'title': 'Will be deleted',
            'date': '2022-01-01',
            'updatedAt': (fields['updatedAt'] as int) - 5000,
            'deleted': false,
          }, key);
          final liveRow = (await store.getRow(table, id))!;
          await store.softDelete(table, id, key, timestamp: () => fields['updatedAt'] as int);
          tombstones.add({'table': table, 'id': id, 'liveRow': rowToFixture(liveRow)});
          continue;
        }
        await store.putEncrypted(table, fields, key);
      }
    }

    final rowsOut = <String, Object?>{};
    final samples = <Map<String, Object?>>[];
    final liveIds = <String, Object?>{};
    var liveCount = 0;
    for (final table in syncedTables) {
      final list = <Map<String, Object?>>[];
      final live = <String>[];
      for (final row in await store.allRows(table)) {
        final opened = decryptRecord(row, key, table: table);
        expect(opened['_headerTampered'], isFalse);
        expect(opened['_tableUnverified'], isFalse);
        list.add({'row': rowToFixture(row), 'expected': toFixtureValue(opened)});
        if (row['deleted'] != true) {
          live.add(row['id'] as String);
          liveCount++;
          samples.add({'table': table, 'id': row['id'], 'expected': toFixtureValue(opened)});
        }
      }
      live.sort();
      liveIds[table] = live;
      rowsOut[table] = list;
    }

    final milestone = (await store.allRows(milestonesTable)).firstWhere((r) => r['deleted'] != true);
    final memory = (await store.allRows(memoriesTable)).first;
    final letter = (await store.allRows(lettersTable)).first;
    final otherKey = VaultKey.fromBits(randomBytes(32));
    Object? outcome(Map<String, Object?> row, String table) {
      try {
        final plain = decryptRecord(row, key, table: table);
        return {
          '_headerTampered': plain['_headerTampered'],
          '_tableTampered': plain['_tableTampered'],
          '_binaryTampered': plain['_binaryTampered'],
        };
      } catch (_) {
        return 'throws';
      }
    }

    final flipped = Uint8List.fromList(memory['imageBlob'] as Uint8List)..[30] ^= 1;
    final tamperCases = <String, List<Map<String, Object?>>>{
      milestonesTable: [
        {'name': 'header updatedAt edited', 'row': {...milestone, 'updatedAt': (milestone['updatedAt'] as num) + 1}},
        {'name': 'sealed for letters, filed as a milestone', 'row': letter},
        {'name': 'sealed with a stranger key', 'row': encryptRecord({'id': 'ms-x', 'updatedAt': 1}, otherKey, table: milestonesTable)},
      ],
      memoriesTable: [
        {'name': 'photo bytes swapped', 'row': {...memory, 'imageBlob': flipped}},
      ],
    };
    final tamperedOut = <String, Object?>{};
    tamperCases.forEach((table, cases) {
      tamperedOut[table] = [
        for (final c in cases)
          {
            'name': c['name'],
            'row': rowToFixture(asStringMap(c['row'])!),
            'expected': outcome(asStringMap(c['row'])!, table),
          },
      ];
    });
    expect((tamperedOut[milestonesTable] as List).every((c) => (c as Map)['expected'] != null), isTrue);

    final manifest = await store.getManifest();
    final sealedManifest = encryptJson(manifest, key);

    final timeLocks = <Map<String, Object?>>[];
    for (final (plain, unlockDate, context) in [
      ('Sealed on a phone, opened on the web.', '2020-05-05', 'ctx-dart-1'),
      ('No context here.', '2019-02-28', ''),
      ('A UTC boundary.', '2021-01-01T10:00:00Z', 'let-dart-iso'),
      ('Still waiting.', '2099-01-01', 'let-dart-locked'),
    ]) {
      timeLocks.add({
        'plain': plain,
        'context': context,
        'sealed': sealTimeLocked(plain, unlockDate, key, context: context),
        'locked': unlockDate == '2099-01-01',
      });
    }

    final texts = <Map<String, Object?>>[];
    for (final (plain, aad) in [
      ('plain text from Dart', null),
      ('bound text from Dart ✨', 'our-space/some-binding'),
      ('', null),
    ]) {
      final sealed = encryptText(plain, key, aad);
      texts.add({'plain': plain, 'aad': aad, 'ciphertext': sealed.ciphertext, 'iv': sealed.iv});
    }

    final invites = <Map<String, Object?>>[];
    void addInvite(String url, Map<String, Object?>? args) {
      invites.add({'url': url, 'expected': parseInvite(url)?.toJson(), 'args': args});
    }

    final salt = vault.salt!;
    addInvite(
      buildInviteUrl('love-dart0123456789', salt,
          baseUrl: 'https://sameskytonight.vercel.app/', startDate: '2021-06-14', coupleNames: 'Sam & Alex ✨'),
      {
        'peerId': 'love-dart0123456789',
        'salt': salt,
        'options': {'baseUrl': 'https://sameskytonight.vercel.app/', 'startDate': '2021-06-14', 'coupleNames': 'Sam & Alex ✨'},
      },
    );
    addInvite(
      buildInviteUrl('love-dart0123456789', salt,
          baseUrl: 'https://sameskytonight.vercel.app/',
          startDate: '2021-06-14',
          coupleNames: 'Sam + Alex = us/2',
          canary: meta['canary'] as String,
          canaryIv: meta['canaryIv'] as String),
      {
        'peerId': 'love-dart0123456789',
        'salt': salt,
        'options': {
          'baseUrl': 'https://sameskytonight.vercel.app/',
          'startDate': '2021-06-14',
          'coupleNames': 'Sam + Alex = us/2',
          'canary': meta['canary'],
          'canaryIv': meta['canaryIv'],
        },
      },
    );
    final link = vault.buildInviteLink()!;
    expect(link.startsWith(defaultInviteBaseUrl), isTrue);
    addInvite(link, {
      'peerId': device.peerId,
      'salt': salt,
      'options': {'baseUrl': defaultInviteBaseUrl, 'startDate': '2021-06-14', 'coupleNames': 'Sam & Alex ✨'},
    });
    addInvite((await vault.buildInviteLinkWithProof())!, null);

    final backup = await BackupService(store: store, vault: vault).exportBackup(dartPassphrase);
    expect(backup.fileName, matches(RegExp(r'^our-space-\d{4}-\d{2}-\d{2}\.vault$')));

    final ownerId = derivePersonSlots(key).first;
    final worker = FakeMailboxWorker(token: 'interop-token-0123456789');
    final mailbox = Mailbox(
      store: store,
      config: MailboxConfig.resolve(
        url: 'https://mailbox.interop.test/',
        token: 'interop-token-0123456789',
        origin: 'https://sameskytonight.vercel.app',
      ),
      client: worker,
    );
    final published = await mailbox.publish(key: key, ownerId: ownerId);
    expect(published.ok, isTrue);
    expect(published.uploaded, liveCount + tombstones.length);
    expect(worker.calls.last, 'PUT /m/${deriveMailboxId(key)}/$ownerId/manifest');

    writeBuildJson('dart_sealed.json', {
      'generatedBy': 'mobile/test/interop_seal_for_web_test.dart',
      'passphrase': dartPassphrase,
      'keyBits': bufferToBase64(key.rawBytes),
      'vaultMeta': meta,
      'expectedConfig': {'coupleNames': 'Sam & Alex ✨', 'startDate': '2021-06-14'},
      'derived': {
        'mailboxId': deriveMailboxId(key),
        'personSlots': derivePersonSlots(key),
        'questionOrder': buildQuestionOrder(key).map((q) => q.id).toList(),
        'recordKeys': [
          for (final id in ['letter-apart-1', 'ans-2026-09-a/b+c=d', 'ñ✨ unicode id', 'x', ownerId])
            {'id': id, 'key': recordKey(id)},
        ],
      },
      'rows': rowsOut,
      'tampered': tamperedOut,
      'manifest': {'plain': manifest, 'sealed': sealedManifest.toJson()},
      'blob': {'plain': bufferToBase64(photo), 'packed': bufferToBase64(encryptBlob(photo, key))},
      'timeLocks': timeLocks,
      'texts': texts,
      'invites': invites,
      'backup': {
        'passphrase': dartPassphrase,
        'container': jsonParse(backup.contents),
        'expectedAdded': liveCount,
      },
      'mailbox': {
        'ownerId': ownerId,
        'kv': worker.kvDump(),
        'expectedApplied': liveCount + tombstones.length,
        'liveIds': liveIds,
        'samples': samples,
        'tombstones': tombstones,
      },
    });

    await store.close();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
