import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:our_space_mobile/core/engine/crypto/aes_gcm.dart';
import 'package:our_space_mobile/core/engine/crypto/base64.dart';
import 'package:our_space_mobile/core/engine/crypto/derived_ids.dart';
import 'package:our_space_mobile/core/engine/crypto/envelope.dart';
import 'package:our_space_mobile/core/engine/domain/sky_drawings.dart';
import 'package:our_space_mobile/core/engine/p2p/peer_sync_engine.dart';
import 'package:our_space_mobile/core/engine/storage/tables.dart';
import 'package:our_space_mobile/core/engine/storage/vault_store.dart';
import 'package:our_space_mobile/core/engine/sync/mailbox.dart';
import 'package:our_space_mobile/models/sky_drawing_record.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fake_mailbox_worker.dart';
import 'support/harness.dart';

const String her = 'owner-aaaa1111';
const String him = 'owner-bbbb2222';

const List<String> tablesBefore = [
  'memories',
  'milestones',
  'dateIdeas',
  'letters',
  'bucketList',
  'loveBursts',
  'dailyAnswers',
  'people',
];

SkyDrawnStar star(String id, double x, double y, {String by = her, int at = 100}) =>
    SkyDrawnStar(id: id, x: x, y: y, by: by, at: at, gen: 0);

SkyDrawing kite() => SkyDrawing(
  stars: [star('a', 0.2, 0.2), star('b', 0.6, 0.4, by: him, at: 120)],
  lines: [SkyDrawnLine(from: 'a', to: 'b', by: him, at: 130, gen: 0)],
);

void main() {
  group('where the new table sits', () {
    test('it comes last, after every table the website knows, and the lists built from it follow', () {
      expect(skyDrawingsTable, 'skyDrawings');
      expect(syncedTables, [...tablesBefore, skyDrawingsTable]);
      expect(webSyncedTables, tablesBefore);
      expect(importableTables, {...tablesBefore, skyDrawingsTable});
      expect(exportedTables, [vaultMetaTable, ...tablesBefore, skyDrawingsTable]);
      expect(mailboxTextTables, [...tablesBefore.where((t) => t != memoriesTable), skyDrawingsTable]);
      expect(allowedPeerTables, {...tablesBefore, skyDrawingsTable});
      expect(binaryFieldsByTable.containsKey(skyDrawingsTable), isFalse);
      expect(wireFieldsFor(skyDrawingsTable), {'id', 'updatedAt', 'deleted', 'v', 'ciphertext', 'iv'});
    });
  });

  group('the store', () {
    late VaultStore store;
    late VaultKey key;
    late SkyDrawingService drawings;
    var clock = 1760000000000;

    setUp(() async {
      store = await openTestStore(now: () => clock);
      key = VaultKey.fromBits(randomBytes(32));
      drawings = SkyDrawingService(store: store);
    });

    tearDown(() => store.close());

    test('a phone that already had a vault gains the table the next time it opens, and keeps everything else', () async {
      final dir = Directory.systemTemp.createTempSync('our_space_old_vault_');
      final path = '${dir.path}${Platform.pathSeparator}old.sqlite';
      final factory = testDatabaseFactory();
      final old = await factory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            await db.execute(
              'CREATE TABLE "vaultMeta" (id TEXT PRIMARY KEY, salt TEXT, canary TEXT, canaryIv TEXT, kdfIterations NUMERIC, updatedAt NUMERIC)',
            );
            for (final table in tablesBefore) {
              await db.execute(
                'CREATE TABLE "$table" (id TEXT PRIMARY KEY, updatedAt NUMERIC, deleted INTEGER NOT NULL DEFAULT 0, '
                'del INTEGER NOT NULL DEFAULT 0, v NUMERIC, ciphertext TEXT, iv TEXT, imageBlob BLOB)',
              );
            }
            await db.execute('CREATE TABLE "localSettings" (key TEXT PRIMARY KEY, value TEXT)');
          },
        ),
      );
      final letter = encryptRecord({'id': 'let-1', 'title': 'Before', 'updatedAt': 5}, key, table: lettersTable);
      await old.insert('"$lettersTable"', {
        'id': 'let-1',
        'updatedAt': 5,
        'deleted': 0,
        'del': 0,
        'v': letter['v'],
        'ciphertext': letter['ciphertext'],
        'iv': letter['iv'],
      });
      expect(
        (await old.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'skyDrawings'")),
        isEmpty,
      );
      await old.close();

      final reopened = await VaultStore.open(factory: factory, path: path, now: () => clock);
      final manifest = await reopened.getManifest();
      expect(manifest.keys.toList(), syncedTables);
      expect(manifest[skyDrawingsTable], isEmpty);
      expect((await reopened.getDecrypted(lettersTable, 'let-1', key))!['title'], 'Before');
      final saved = await SkyDrawingService(store: reopened).saveProgress(key, id: 'sky-old-phone', drawing: kite());
      expect(saved.drawing, kite());
      await reopened.close();

      final again = await VaultStore.open(factory: factory, path: path, now: () => clock);
      expect((await SkyDrawingService(store: again).list(key)).single.id, 'sky-old-phone');
      await again.close();
    });

    test('a drawing is sealed like every other record, bound to its table', () async {
      await drawings.finish(key, id: 'sky-1', drawing: kite(), name: 'Our kite', at: clock);
      final row = (await store.getRow(skyDrawingsTable, 'sky-1'))!;
      expect(row['v'], recordSchemaVersion);
      expect(row['ciphertext'], isA<String>());
      expect(row.toString().contains('Our kite'), isFalse);
      expect(row.toString().contains(her), isFalse);
      expect(recordHasAuthenticatedHeader(row), isTrue);
      final opened = decryptRecord(row, key, table: skyDrawingsTable);
      expect(opened['_tableTampered'], isFalse);
      expect(opened['name'], 'Our kite');
      expect(decryptRecord(row, key, table: lettersTable)['_tableTampered'], isTrue);

      await store.putRow(skyDrawingsTable, encryptRecord({'id': 'sky-forged', 'name': 'x', 'updatedAt': 9}, key, table: lettersTable));
      expect((await drawings.list(key)).map((r) => r.id), ['sky-1']);
    });

    test('progress merges with what is kept, writes nothing when nothing is new, and reopens the same drawing', () async {
      expect(await drawings.unfinished(key), isNull);
      final fresh = await drawings.idToOpen(key);
      expect(skyIdPattern.hasMatch(fresh), isTrue);
      expect(fresh, isNot(await drawings.idToOpen(key)));

      final first = SkyDrawing(stars: [star('a', 0.2, 0.2)]);
      final saved = await drawings.saveProgress(key, id: 'sky-1', drawing: first, startedAt: 42);
      expect(saved.startedAt, 42);
      expect(saved.finished, isFalse);
      final stamp = (await store.getRow(skyDrawingsTable, 'sky-1'))!['updatedAt'];

      final again = await drawings.saveProgress(key, id: 'sky-1', drawing: first, startedAt: 99);
      expect((await store.getRow(skyDrawingsTable, 'sky-1'))!['updatedAt'], stamp);
      expect(again.startedAt, 42);

      final other = SkyDrawing(stars: [star('b', 0.7, 0.7, by: him)]);
      final merged = await drawings.saveProgress(key, id: 'sky-1', drawing: other);
      expect(merged.drawing.visibleStars.map((s) => s.id), ['a', 'b']);
      expect(merged.startedAt, 42);
      expect((await store.getRow(skyDrawingsTable, 'sky-1'))!['updatedAt'] as num, greaterThan(stamp as num));

      expect((await drawings.unfinished(key))!.id, 'sky-1');
      expect(await drawings.idToOpen(key), 'sky-1');
      expect((await drawings.find(key, 'sky-1'))!.drawing, merged.drawing);
      expect(await drawings.find(key, 'missing'), isNull);
      expect(await drawings.find(null, 'sky-1'), isNull);
      expect(await drawings.list(null), isEmpty);
      await expectLater(drawings.saveProgress(null, id: 'sky-1', drawing: first), throwsA(isA<StoreError>()));
      await expectLater(drawings.saveProgress(key, id: 'bad id', drawing: first), throwsA(isA<StoreError>()));
    });

    test('finishing keeps only what shows, with its name and night, and is never undone by late progress', () async {
      final drawing = kite().apply(SkyRemove(['gone'], gen: 0)).apply(SkyAddStar(star('c', 0.9, 0.9, at: 140)));
      await drawings.saveProgress(key, id: 'sky-1', drawing: drawing, startedAt: 7);
      await expectLater(drawings.finish(key, id: 'sky-1', drawing: drawing, name: '   '), throwsA(isA<StoreError>()));
      await expectLater(
        drawings.finish(key, id: 'sky-empty', drawing: SkyDrawing.empty, name: 'Nothing'),
        throwsA(isA<StoreError>()),
      );

      final at = DateTime(2026, 10, 29, 1, 30).millisecondsSinceEpoch;
      final done = await drawings.finish(key, id: 'sky-1', drawing: SkyDrawing.empty, name: '  Our   kite ', at: at);
      expect(done.finished, isTrue);
      expect(done.name, 'Our kite');
      expect(done.createdAt, at);
      expect(done.night, '2026-10-28');
      expect(done.startedAt, 7);
      expect(done.drawing.removed, isEmpty);
      expect(done.drawing.visibleStars.map((s) => s.id), ['a', 'b', 'c']);
      expect(await drawings.unfinished(key), isNull);

      final late = await drawings.saveProgress(key, id: 'sky-1', drawing: SkyDrawing(stars: [star('d', 0.5, 0.9)]));
      expect(late.finished, isTrue);
      expect(late.drawing.visibleStars.length, 3);
      final twice = await drawings.finish(key, id: 'sky-1', drawing: drawing, name: 'Another name');
      expect(twice.name, 'Our kite');

      expect(await drawings.remove(key, 'sky-1'), isTrue);
      expect(await drawings.list(key), isEmpty);
      expect((await store.getRow(skyDrawingsTable, 'sky-1'))!['deleted'], isTrue);
      expect(await drawings.remove(key, 'missing'), isFalse);
      expect(await drawings.remove(null, 'sky-1'), isFalse);
    });

    test('when two unfinished drawings ever meet, the same one is picked on both phones', () async {
      final a = SkyDrawingRecord.tryParse(
        SkyDrawingRecord.fieldsFor(id: 'sky-a', drawing: kite(), startedAt: 1, updatedAt: 50),
      )!;
      final b = SkyDrawingRecord.tryParse(
        SkyDrawingRecord.fieldsFor(id: 'sky-b', drawing: kite(), startedAt: 1, updatedAt: 60),
      )!;
      final c = SkyDrawingRecord.tryParse(
        SkyDrawingRecord.fieldsFor(id: 'sky-c', drawing: kite(), startedAt: 1, updatedAt: 60),
      )!;
      expect(SkyDrawingService.pickUnfinished([a, b, c])!.id, 'sky-b');
      expect(SkyDrawingService.pickUnfinished([c, b, a])!.id, 'sky-b');
      expect(SkyDrawingService.pickUnfinished(const []), isNull);
    });

    test('the manifest lists drawings and tombstones next to the other tables', () async {
      await drawings.saveProgress(key, id: 'sky-1', drawing: kite());
      await drawings.saveProgress(key, id: 'sky-2', drawing: kite());
      await drawings.remove(key, 'sky-2');
      final manifest = await store.getManifest();
      expect(manifest.keys.toList(), syncedTables);
      expect([for (final e in manifest[skyDrawingsTable]!) (e['id'], e['deleted'])], [('sky-1', false), ('sky-2', true)]);
    });

    test('a backup carries the drawings and brings them back, and leaves the other tables as they were', () async {
      await drawings.finish(key, id: 'sky-1', drawing: kite(), name: 'Our kite', at: clock);
      await store.putEncrypted(lettersTable, {'id': 'let-1', 'title': 'Hi', 'updatedAt': 10}, key);
      final backup = await store.exportRawDataForBackup();
      final tables = backup['tables'] as Map<String, Object?>;
      expect(tables.keys.toList(), exportedTables);
      expect((tables[skyDrawingsTable] as List).single, isA<Map<String, Object?>>());

      final other = await openTestStore(now: () => clock);
      final plan = await other.planBackupMerge(jsonDecode(jsonEncode(tables)), key);
      expect(plan.skippedTables, [vaultMetaTable]);
      expect(plan.perTable[skyDrawingsTable]!.added, 1);
      expect(plan.perTable[lettersTable]!.added, 1);
      final result = await other.applyBackupMerge(plan);
      expect(result.written, {lettersTable: 1, skyDrawingsTable: 1});
      final back = (await SkyDrawingService(store: other).list(key)).single;
      expect(back.name, 'Our kite');
      expect(back.drawing, kite());

      final future = await other.planBackupMerge({'skyDrawings2': <Object?>[], ...tables}, key);
      expect(future.skippedTables, containsAll(['skyDrawings2', vaultMetaTable]));
      await other.close();
    });

    test('the mailbox carries drawings like any other words, and the old text tables still go first', () async {
      final worker = FakeMailboxWorker(token: 'test-token-for-the-mailbox');
      Mailbox box(VaultStore s, http.Client client) => Mailbox(
        store: s,
        config: MailboxConfig.resolve(
          url: 'https://mailbox.example.workers.dev',
          token: 'test-token-for-the-mailbox',
          origin: 'https://sameskytonight.vercel.app',
        ),
        client: client,
      );
      Future<Map<String, Object?>> sealedManifest() async {
        final raw = worker.kvDump()['${deriveMailboxId(key)}/his-person-mailbox/manifest']!;
        final sealed = jsonDecode(raw) as Map<String, Object?>;
        return (decryptJson(sealed['ciphertext'] as String, sealed['iv'] as String, key) as Map).cast<String, Object?>();
      }

      await store.putEncrypted(lettersTable, {'id': 'let-1', 'title': 'Hi', 'updatedAt': 10}, key);
      final before = await box(store, worker).publish(key: key, ownerId: 'his-person-mailbox', includePhotos: false);
      expect(before.uploaded, 1);
      expect((await sealedManifest()).keys.toList(), webSyncedTables.where((t) => t != memoriesTable).toList());

      await drawings.finish(key, id: 'sky-1', drawing: kite(), name: 'Our kite', at: clock);
      worker.calls.clear();
      final published = await box(store, worker).publish(key: key, ownerId: 'his-person-mailbox', includePhotos: false);
      expect(published.ok, isTrue);
      expect(published.uploaded, 1);
      expect((await sealedManifest()).keys.toList(), mailboxTextTables);
      final puts = [for (final c in worker.calls) if (c.startsWith('PUT') && c.contains('/rec/')) c];
      expect(puts.single, contains('/rec/skyDrawings/'));
      final body = worker.kvDump().entries.firstWhere((e) => e.key.contains('/rec/skyDrawings/')).value;
      expect(body.contains('Our kite'), isFalse);
      expect((jsonDecode(body) as Map).keys.toSet(), {'id', 'updatedAt', 'deleted', 'v', 'ciphertext', 'iv'});

      final other = await openTestStore(now: () => clock);
      final got = await box(other, worker).collect(key: key, partnerId: 'his-person-mailbox');
      expect(got.ok, isTrue);
      expect(got.applied, 2);
      expect((await SkyDrawingService(store: other).list(key)).single.name, 'Our kite');
      await other.close();
    });
  });
}
