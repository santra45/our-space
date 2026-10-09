import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine/crypto/aes_gcm.dart';
import 'package:our_space_mobile/core/engine/crypto/base64.dart';
import 'package:our_space_mobile/core/engine/crypto/envelope.dart';
import 'package:our_space_mobile/core/engine/storage/tables.dart';
import 'package:our_space_mobile/core/engine/storage/vault_store.dart';

import 'support/harness.dart';

void main() {
  late VaultStore store;
  late VaultKey key;
  var clock = 1700000000000;

  setUp(() async {
    clock = 1700000000000;
    store = await openTestStore(now: () => clock);
    key = VaultKey.fromBits(randomBytes(32));
  });

  tearDown(() async {
    await store.close();
  });

  test('every row is sealed at rest, photos included', () async {
    final photo = Uint8List.fromList(utf8.encode('PRETEND-THIS-IS-A-WEBP-PHOTO' * 20));
    await store.putEncrypted(memoriesTable, {
      'id': 'mem-1',
      'date': '2026-02-14',
      'caption': 'secret caption words',
      'mime': 'image/webp',
      'imageBlob': encryptBlob(photo, key),
      'updatedAt': 5,
      'deleted': false,
    }, key);

    final raw = await store.getRow(memoriesTable, 'mem-1');
    expect(raw, isNotNull);
    expect(raw!.keys.toSet(), {'id', 'updatedAt', 'deleted', 'v', 'ciphertext', 'iv', 'imageBlob', '_del'});
    expect(jsonEncode({...raw, 'imageBlob': null}).contains('secret caption'), isFalse);
    final blob = raw['imageBlob'] as Uint8List;
    expect(latin1.decode(blob, allowInvalid: true).contains('PRETEND'), isFalse);
    expect(decryptBlob(blob, key), photo);

    final plain = await store.getDecrypted(memoriesTable, 'mem-1', key);
    expect(plain!['caption'], 'secret caption words');
    expect(plain['_headerTampered'], isFalse);
    expect(plain['_binaryTampered'], isFalse);
  });

  test('soft delete writes a sealed tombstone that wins over the old row', () async {
    await store.putEncrypted(lettersTable, {'id': 'let-1', 'title': 'Hi', 'content': 'words', 'updatedAt': 10}, key);
    final tombstone = await store.softDelete(lettersTable, 'let-1', key, timestamp: () => 3);
    expect(tombstone!['deleted'], isTrue);
    expect(tombstone['updatedAt'], 11);

    final plain = await store.getDecrypted(lettersTable, 'let-1', key);
    expect(plain!['deleted'], isTrue);
    expect(plain.containsKey('content'), isFalse);
    expect(plain.containsKey('title'), isFalse);
    expect(await store.listDecrypted(lettersTable, key), isEmpty);
    expect((await store.listDecrypted(lettersTable, key, includeDeleted: true)).length, 1);

    final manifest = await store.getManifest();
    expect(manifest[lettersTable], [
      {'id': 'let-1', 'updatedAt': 11, 'deleted': true},
    ]);
    expect(await store.softDelete(lettersTable, 'missing', key), isNull);
  });

  test('putEncryptedMany is all or nothing', () async {
    await expectLater(
      store.putEncryptedMany([
        TableWrite(milestonesTable, {'id': 'ms-1', 'title': 'a', 'updatedAt': 1}),
        const TableWrite('nope', {'id': 'x'}),
      ], key),
      throwsA(isA<StoreError>()),
    );
    expect(await store.getRow(milestonesTable, 'ms-1'), isNull);

    final sealed = await store.putEncryptedMany([
      TableWrite(milestonesTable, {'id': 'ms-1', 'title': 'a', 'updatedAt': 1}),
      TableWrite(peopleTable, {'id': 'person-x', 'updatedAt': 2}),
    ], key);
    expect(sealed.length, 2);
    expect(await store.getRow(milestonesTable, 'ms-1'), isNotNull);
    expect(await store.getRow(peopleTable, 'person-x'), isNotNull);
  });

  test('the manifest lists every synced table, ids, versions and tombstones', () async {
    await store.putEncrypted(bucketListTable, {'id': 'b', 'updatedAt': 7}, key);
    await store.putEncrypted(bucketListTable, {'id': 'a', 'updatedAt': 9, 'deleted': true}, key);
    final manifest = await store.getManifest();
    expect(manifest.keys.toList(), syncedTables);
    expect(manifest[bucketListTable], [
      {'id': 'a', 'updatedAt': 9, 'deleted': true},
      {'id': 'b', 'updatedAt': 7, 'deleted': false},
    ]);
    expect(manifest[memoriesTable], isEmpty);
  });

  test('a merge applies only newer, authenticated rows and keeps tombstones', () async {
    final other = await openTestStore(now: () => clock);
    final old = encryptRecord({'id': 'ms-1', 'title': 'old', 'updatedAt': 100}, key, table: milestonesTable);
    await store.putRow(milestonesTable, old);

    final newer = encryptRecord({'id': 'ms-1', 'title': 'new', 'updatedAt': 200}, key, table: milestonesTable);
    final stale = encryptRecord({'id': 'ms-2', 'title': 'x', 'updatedAt': 50}, key, table: milestonesTable);
    final unknownTombstone = encryptRecord({'id': 'ms-3', 'updatedAt': 60, 'deleted': true}, key, table: milestonesTable);
    final wrongTable = encryptRecord({'id': 'ms-4', 'updatedAt': 70}, key, table: lettersTable);
    final forged = encryptRecord({'id': 'ms-5', 'updatedAt': 80}, VaultKey.fromBits(randomBytes(32)), table: milestonesTable);
    final headerLie = Map<String, Object?>.from(encryptRecord({'id': 'ms-6', 'updatedAt': 90}, key, table: milestonesTable))
      ..['updatedAt'] = 91;
    await store.putRow(milestonesTable, encryptRecord({'id': 'ms-2', 'title': 'kept', 'updatedAt': 75}, key, table: milestonesTable));

    final plan = await store.planBackupMerge({
      milestonesTable: [newer, stale, unknownTombstone, wrongTable, forged, headerLie],
      'vaultMeta': [],
    }, key);
    expect(plan.totals.updated, 1);
    expect(plan.totals.stale, 1);
    expect(plan.totals.invalid, 1);
    expect(plan.totals.tampered, 2);
    expect(plan.totals.undecryptable, 1);
    expect(plan.skippedTables, ['vaultMeta']);

    final result = await store.applyBackupMerge(plan);
    expect(result.totalWritten, 1);
    expect((await store.getDecrypted(milestonesTable, 'ms-1', key))!['title'], 'new');
    expect((await store.getDecrypted(milestonesTable, 'ms-2', key))!['title'], 'kept');
    expect(await store.getRow(milestonesTable, 'ms-3'), isNull);
    await other.close();
  });

  test('change streams fire for local writes and merges', () async {
    final seen = <Set<String>>[];
    final local = <String>[];
    final sub = store.changes.listen(seen.add);
    final localSub = store.localWrites.listen(local.add);
    await store.putEncrypted(loveBurstsTable, {'id': 'burst-a', 'count': 1, 'updatedAt': 1}, key);
    final row = encryptRecord({'id': 'burst-b', 'count': 2, 'updatedAt': 2}, key, table: loveBurstsTable);
    final plan = await store.planBackupMerge({loveBurstsTable: [row]}, key);
    await store.applyBackupMerge(plan);
    await Future<void>.delayed(Duration.zero);
    expect(seen.where((tables) => tables.contains(loveBurstsTable)).length, 2);
    expect(local, [loveBurstsTable]);
    await sub.cancel();
    await localSub.cancel();
  });

  test('local settings survive reopening the store', () async {
    await store.settings.setItem('sweetheart_device_owner_v1', 'device-tag-123');
    expect(store.settings.getItem('sweetheart_device_owner_v1'), 'device-tag-123');
  });
}
