import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:our_space_mobile/core/engine/crypto/aes_gcm.dart';
import 'package:our_space_mobile/core/engine/crypto/base64.dart';
import 'package:our_space_mobile/core/engine/crypto/derived_ids.dart';
import 'package:our_space_mobile/core/engine/crypto/envelope.dart';
import 'package:our_space_mobile/core/engine/crypto/js_compat.dart';
import 'package:our_space_mobile/core/engine/crypto/kdf.dart';
import 'package:our_space_mobile/core/engine/storage/tables.dart';
import 'package:our_space_mobile/core/engine/storage/vault_store.dart';
import 'package:our_space_mobile/core/engine/sync/mailbox.dart';

import 'support/fake_mailbox_worker.dart';
import 'support/harness.dart';

const String token = 'test-token-for-the-mailbox';
const String origin = 'https://sameskytonight.vercel.app';

Mailbox mailboxFor(VaultStore store, http.Client client, {String tokenValue = token, String? originValue = origin}) =>
    Mailbox(
      store: store,
      config: MailboxConfig.resolve(url: 'https://mailbox.example.workers.dev//', token: tokenValue, origin: originValue),
      client: client,
    );

void main() {
  final fixture = readFixture('web_sealed.json');

  group('the fake worker enforces the real worker routes', () {
    test('auth, origin, shapes and size', () async {
      final worker = FakeMailboxWorker(token: token);
      final id = 'a' * 64;
      Future<int> call(String method, String path, {String? auth, String? from, List<int>? body}) async {
        final request = http.Request(method, Uri.parse('https://w.dev$path'));
        if (auth != null) request.headers['Authorization'] = auth;
        if (from != null) request.headers['Origin'] = from;
        if (body != null) request.bodyBytes = body;
        return (await worker.send(request)).statusCode;
      }

      expect(await call('GET', '/m/$id/person-slot-aaaa/manifest', auth: 'Bearer $token', from: origin), 404);
      expect(await call('PUT', '/m/$id/person-slot-aaaa/manifest', auth: 'Bearer $token', from: origin, body: [1]), 204);
      expect(await call('GET', '/m/$id/person-slot-aaaa/manifest', auth: 'Bearer $token', from: origin), 200);
      expect(await call('GET', '/m/$id/person-slot-aaaa/manifest', auth: 'Bearer nope', from: origin), 401);
      expect(await call('GET', '/m/$id/person-slot-aaaa/manifest', auth: 'Bearer $token', from: 'https://evil.example'), 403);
      expect(await call('GET', '/m/$id/person-slot-aaaa/manifest', auth: 'Bearer $token'), 403);
      expect(await call('DELETE', '/m/$id/person-slot-aaaa/manifest', auth: 'Bearer $token', from: origin), 405);
      expect(await call('GET', '/m/$id', auth: 'Bearer $token', from: origin), 404);
      expect(await call('GET', '/m/${'z' * 64}/person-slot-aaaa/manifest', auth: 'Bearer $token', from: origin), 404);
      expect(await call('GET', '/m/$id/person-slot-aaaa/rec/letters/../../x', auth: 'Bearer $token', from: origin), 404);
      expect(
        await call('PUT', '/m/$id/person-slot-aaaa/manifest',
            auth: 'Bearer $token', from: origin, body: List.filled(16 * 1024 * 1024 + 1, 0)),
        413,
      );
    });
  });

  group('Dart to Dart', () {
    late VaultKey key;
    late VaultStore his;
    late VaultStore her;
    late FakeMailboxWorker worker;
    var clock = 1700000000000;
    const hisBox = 'his-person-mailbox';
    const herBox = 'her-person-mailbox';

    setUp(() async {
      key = await deriveKeyFromPassphrase('my-super-secret-couple-passphrase-2026', generateSalt(), iterations: 2000);
      his = await openTestStore();
      her = await openTestStore();
      worker = FakeMailboxWorker(token: token);
    });

    tearDown(() async {
      await his.close();
      await her.close();
    });

    test('disabled, locked and ownerless runs are no-ops', () async {
      final off = Mailbox(store: his, config: null, client: worker);
      expect((await off.publish(key: key, ownerId: hisBox)).reason, 'disabled');
      expect((await off.collect(key: key, partnerId: hisBox)).reason, 'disabled');
      expect(MailboxConfig.resolve(url: 'https://x.dev'), isNull);
      final on = mailboxFor(his, worker);
      expect((await on.publish(key: null, ownerId: hisBox)).reason, 'locked');
      expect((await on.publish(key: key, ownerId: null)).reason, 'no-owner');
      expect((await on.collect(key: key, partnerId: '')).reason, 'no-partner');
      expect(worker.calls, isEmpty);
    });

    test('publish uploads records first, then a sealed manifest; collect applies them', () async {
      await his.putEncrypted(lettersTable, {
        'id': 'letter-apart-1',
        'title': 'While you were asleep',
        'content': 'I wrote this at 3am.',
        'updatedAt': clock += 1000,
      }, key);
      await his.putEncrypted(bucketListTable, {
        'id': 'bucket-apart-1',
        'text': 'Actually be in the same country',
        'updatedAt': clock += 1000,
      }, key);

      final pub = await mailboxFor(his, worker).publish(key: key, ownerId: hisBox);
      expect(pub.ok, isTrue);
      expect(pub.uploaded, 2);
      final mailboxId = deriveMailboxId(key);
      expect(worker.calls.first, 'GET /m/$mailboxId/$hisBox/manifest');
      expect(worker.calls.last, 'PUT /m/$mailboxId/$hisBox/manifest');
      expect(
        worker.calls,
        contains('PUT /m/$mailboxId/$hisBox/rec/letters/${recordKey('letter-apart-1')}'),
      );

      final kv = worker.kvDump();
      final manifestBody = kv['$mailboxId/$hisBox/manifest']!;
      expect(manifestBody.contains('letter-apart-1'), isFalse);
      expect((jsonDecode(manifestBody) as Map).keys.toList(), ['ciphertext', 'iv']);
      final letterBody = kv['$mailboxId/$hisBox/rec/letters/${recordKey('letter-apart-1')}']!;
      expect(letterBody.contains('3am'), isFalse);
      expect((jsonDecode(letterBody) as Map).keys.toSet(), {'id', 'updatedAt', 'deleted', 'v', 'ciphertext', 'iv'});

      final got = await mailboxFor(her, worker).collect(key: key, partnerId: hisBox);
      expect(got.ok, isTrue);
      expect(got.fetched, 2);
      expect(got.applied, 2);
      expect((await her.getDecrypted(lettersTable, 'letter-apart-1', key))!['content'], 'I wrote this at 3am.');

      worker.calls.clear();
      final again = await mailboxFor(her, worker).collect(key: key, partnerId: hisBox);
      expect(again.applied, 0);
      expect(again.fetched, 0);
      expect(worker.calls.length, 1);

      worker.calls.clear();
      final republish = await mailboxFor(his, worker).publish(key: key, ownerId: hisBox);
      expect(republish.uploaded, 0);
      expect(republish.unchanged, isTrue);
      expect(worker.calls.any((c) => c.startsWith('PUT ')), isFalse);
    });

    test('edits travel, and tombstones travel and stay dead', () async {
      await his.putEncrypted(lettersTable, {'id': 'l1', 'title': 'a', 'content': 'first', 'updatedAt': clock += 1000}, key);
      await mailboxFor(his, worker).publish(key: key, ownerId: hisBox);
      await mailboxFor(her, worker).collect(key: key, partnerId: hisBox);

      await his.putEncrypted(lettersTable, {'id': 'l1', 'title': 'a', 'content': 'edited', 'updatedAt': clock += 1000}, key);
      final edited = await mailboxFor(his, worker).publish(key: key, ownerId: hisBox);
      expect(edited.uploaded, 1);
      expect((await mailboxFor(her, worker).collect(key: key, partnerId: hisBox)).applied, 1);
      expect((await her.getDecrypted(lettersTable, 'l1', key))!['content'], 'edited');

      await his.softDelete(lettersTable, 'l1', key, timestamp: () => clock += 1000);
      expect((await mailboxFor(his, worker).publish(key: key, ownerId: hisBox)).uploaded, 1);
      final wire = jsonDecode(worker.kvDump()['${deriveMailboxId(key)}/$hisBox/rec/letters/${recordKey('l1')}']!) as Map;
      expect(wire['deleted'], isTrue);

      expect((await mailboxFor(her, worker).collect(key: key, partnerId: hisBox)).applied, 1);
      final dead = await her.getDecrypted(lettersTable, 'l1', key);
      expect(dead!['deleted'], isTrue);
      expect(dead.containsKey('content'), isFalse);
      expect((await mailboxFor(her, worker).collect(key: key, partnerId: hisBox)).applied, 0);
    });

    test('photos travel with their sealed bytes, and can be held back', () async {
      await his.putEncrypted(memoriesTable, {
        'id': 'mem-1',
        'date': '2026-01-01',
        'caption': 'us',
        'mime': 'image/webp',
        'imageBlob': encryptBlob(utf8.encode('photo bytes'), key),
        'updatedAt': clock += 1000,
      }, key);
      await his.putEncrypted(milestonesTable, {'id': 'ms-1', 'title': 'x', 'updatedAt': clock += 1000}, key);

      final textOnly = await mailboxFor(his, worker).publish(key: key, ownerId: hisBox, includePhotos: false);
      expect(textOnly.uploaded, 1);
      final full = await mailboxFor(his, worker).publish(key: key, ownerId: hisBox);
      expect(full.uploaded, 1);
      final wire = jsonDecode(worker.kvDump()['${deriveMailboxId(key)}/$hisBox/rec/memories/${recordKey('mem-1')}']!) as Map;
      expect(wire.containsKey('imageBlobBase64'), isTrue);

      expect((await mailboxFor(her, worker).collect(key: key, partnerId: hisBox)).applied, 2);
      final row = await her.getRow(memoriesTable, 'mem-1');
      expect(utf8.decode(decryptBlob(row!['imageBlob'] as List<int>, key)), 'photo bytes');
    });

    test('a forged record and a dangling manifest entry are refused quietly', () async {
      await his.putEncrypted(lettersTable, {'id': 'real', 'updatedAt': clock += 1000}, key);
      await mailboxFor(his, worker).publish(key: key, ownerId: hisBox);

      final mailboxId = deriveMailboxId(key);
      final evil = VaultKey.fromBits(randomBytes(32));
      final forged = encryptRecord({'id': 'forged', 'title': 'Forged', 'updatedAt': clock}, evil, table: lettersTable);
      worker.objects['$mailboxId/$hisBox/rec/letters/${recordKey('forged')}'] = utf8.encode(jsonStringify(forged));
      final manifest = await his.getManifest();
      manifest[lettersTable]!.add({'id': 'forged', 'updatedAt': clock, 'deleted': false});
      manifest[lettersTable]!.add({'id': 'missing', 'updatedAt': clock, 'deleted': false});
      worker.objects['$mailboxId/$hisBox/manifest'] = utf8.encode(jsonStringify(encryptJson(manifest, key).toJson()));

      final got = await mailboxFor(her, worker).collect(key: key, partnerId: hisBox);
      expect(got.ok, isTrue);
      expect(got.applied, 1);
      expect(await her.getRow(lettersTable, 'forged'), isNull);
      expect(got.totals!.undecryptable, 1);
    });

    test('an empty mailbox is not an error, and a bad token or offline fails the publish', () async {
      final empty = await mailboxFor(his, worker).collect(key: key, partnerId: herBox);
      expect(empty.ok, isTrue);
      expect(empty.reason, 'nothing-published');

      await his.putEncrypted(lettersTable, {'id': 'x', 'updatedAt': 1}, key);
      final badToken = await mailboxFor(his, worker, tokenValue: 'wrong').publish(key: key, ownerId: hisBox);
      expect(badToken.ok, isFalse);
      final noOrigin = await mailboxFor(his, worker, originValue: '').publish(key: key, ownerId: hisBox);
      expect(noOrigin.ok, isFalse);

      worker.offline = true;
      final offline = await mailboxFor(his, worker).publish(key: key, ownerId: hisBox);
      expect(offline.ok, isFalse);
      expect(offline.reason, 'offline');
      worker.offline = false;
    });

    test('sync collects every slot first, then publishes', () async {
      await his.putEncrypted(milestonesTable, {'id': 'his-ms', 'updatedAt': clock += 1000}, key);
      await mailboxFor(his, worker).publish(key: key, ownerId: hisBox);
      await her.putEncrypted(milestonesTable, {'id': 'her-ms', 'updatedAt': clock += 1000}, key);

      worker.calls.clear();
      final result = await mailboxFor(her, worker).sync(key: key, ownerId: herBox, slots: [hisBox, herBox, null]);
      expect(result.collected.length, 2);
      expect(result.applied, 1);
      expect(result.uploaded, 2);
      expect(worker.calls.last.endsWith('/$herBox/manifest'), isTrue);
      expect(worker.calls.first.endsWith('/$hisBox/manifest'), isTrue);

      final noOwner = await mailboxFor(her, worker).sync(key: key, ownerId: null, slots: [hisBox]);
      expect(noOwner.published.reason, 'no-owner');
    });
  });

  group('web to Dart', () {
    test('Dart collects what the web published through the real worker', () async {
      final webKey = await deriveKeyFromPassphrase(
        fixture['passphrase'] as String,
        fixture['salt'] as String,
        iterations: fixture['kdfIterations'] as int,
      );
      final box = asStringMap(fixture['mailbox'])!;
      final config = asStringMap(box['config'])!;
      final worker = FakeMailboxWorker.fromKvDump(asStringMap(box['kv'])!, token: config['token'] as String);
      final store = await openTestStore();

      final tombstones = (box['tombstones'] as List).cast<Map>();
      for (final t in tombstones) {
        await store.putRow(t['table'] as String, rowFromFixture(asStringMap(t['liveRow'])!));
      }

      final mailbox = Mailbox(
        store: store,
        config: MailboxConfig.resolve(url: config['url'] as String, token: config['token'] as String, origin: box['origin'] as String),
        client: worker,
      );
      final got = await mailbox.collect(key: webKey, partnerId: box['ownerId'] as String);
      expect(got.ok, isTrue);

      final liveIds = asStringMap(box['liveIds'])!;
      final liveCount = liveIds.values.fold<int>(0, (n, list) => n + (list as List).length);
      expect(got.applied, liveCount + tombstones.length);

      for (final table in syncedTables) {
        final have = (await store.allRows(table)).where((r) => r['deleted'] != true).map((r) => r['id']).toList()..sort();
        expect(have, liveIds[table], reason: table);
      }
      for (final t in tombstones) {
        final row = await store.getRow(t['table'] as String, t['id'] as String);
        expect(row!['deleted'], isTrue);
      }

      final webRows = asStringMap(fixture['rows'])!;
      for (final table in syncedTables) {
        for (final entry in (webRows[table] as List).cast<Map>()) {
          final expected = asStringMap(fromFixtureValue(entry['expected']))!;
          if (expected['deleted'] == true) continue;
          final opened = await store.getDecrypted(table, expected['id'] as String, webKey);
          expect(jsonDeepEquals(opened, expected), isTrue, reason: '$table/${expected['id']}');
        }
      }

      final republish = await mailbox.publish(key: webKey, ownerId: derivePersonSlots(webKey)[1]);
      expect(republish.ok, isTrue);
      await store.close();
    });
  });
}
