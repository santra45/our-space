import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine/crypto/aes_gcm.dart';
import 'package:our_space_mobile/core/engine/crypto/base64.dart';
import 'package:our_space_mobile/core/engine/crypto/envelope.dart';
import 'package:our_space_mobile/core/engine/crypto/js_compat.dart';
import 'package:our_space_mobile/core/engine/p2p/peer_endpoint.dart';
import 'package:our_space_mobile/core/engine/p2p/peer_status.dart';
import 'package:our_space_mobile/core/engine/p2p/peer_sync_engine.dart';
import 'package:our_space_mobile/core/engine/storage/tables.dart';

import 'support/engine_harness.dart';
import 'support/fake_peer.dart';
import 'support/solo.dart';

const int base = 1760000000000;

Map<String, Object?> wire(Map<String, Object?> row) {
  final out = <String, Object?>{};
  for (final field in ['id', 'updatedAt', 'deleted', 'v', 'ciphertext', 'iv']) {
    if (row[field] != null) out[field] = row[field];
  }
  final blob = row['imageBlob'];
  if (blob != null) out['imageBlobBase64'] = bufferToBase64(binaryBytes(blob));
  return out;
}

Map<String, Object?> sealedRow(VaultKey key, String table, Map<String, Object?> fields) =>
    encryptRecord(fields, key, table: table);

void main() {
  group('pairing and timeouts', () {
    test('a dialer that never answers fails after 30 seconds with the web message', () async {
      final solo = await Solo.open();
      await solo.init();
      final link = await solo.dial(partnerId);
      expect(solo.sentTypes(link), ['CHALLENGE']);
      expect(solo.side.engine.linkState, PeerLinkState.connected);

      await solo.advance(29999);
      expect(solo.side.saw('auth_timeout'), isFalse);
      await solo.advance(1);

      final status = solo.side.last('auth_timeout')!;
      expect(status.state, 'auth_failed');
      expect(status.error, 'Authentication timed out after 30 seconds. Your partner never completed the secure handshake.');
      expect(link.closed, isTrue);
      expect(solo.side.engine.linkState, PeerLinkState.disconnected);
      await solo.close();
    });

    test('a channel that never opens gives the direct-connection advice after 15 seconds', () async {
      final solo = await Solo.open();
      await solo.init();
      final link = await solo.dial(partnerId, open: false);
      expect(solo.side.last('dialing')!.state, 'connecting');
      expect(solo.side.engine.linkState, PeerLinkState.connecting);
      await solo.advance(15000);
      final status = solo.side.last('ice_failed')!;
      expect(status.state, 'ice_failed');
      expect(status.error, openTimeoutMessage);
      expect(link.closed, isTrue);
      await solo.close();
    });

    test('a stranger who never finishes is dropped quietly once a partner is known', () async {
      final solo = await Solo.open(settings: {knownPartnerKey: partnerId});
      await solo.init();
      final link = await solo.accept('love-stranger0000');
      await solo.advance(11999);
      expect(link.closed, isFalse);
      await solo.advance(1);
      expect(link.closed, isTrue);
      final warning = solo.side.last('stranger_auth_timeout')!;
      expect(warning.warning, 'Someone else tried to pair and did not finish. We disconnected them.');
      expect(solo.side.saw('auth_timeout'), isFalse);
      await solo.close();
    });

    test('a short challenge or a wrong echo stops pairing', () async {
      final solo = await Solo.open();
      await solo.init();
      final link = await solo.accept(partnerId);
      await solo.deliver(link, {'type': 'SYNC_MANIFEST', 'sessionId': 'abcdefghij', 'manifest': {}});
      expect(link.sent, isEmpty);
      await solo.deliver(link, {'type': 'CHALLENGE', 'nonce': 'short'});
      expect(solo.side.last('bad_challenge')!.error, 'Something went wrong while pairing. Try again.');
      expect(solo.side.last('bad_challenge')!.state, 'auth_failed');

      final dialed = await solo.dial(partnerId);
      expect(solo.sentTypes(dialed), ['CHALLENGE']);
      await solo.deliver(dialed, {'type': 'CHALLENGE_RESPONSE', 'echo': 'not-my-nonce-at-all', 'counterNonce': 'c' * 24});
      final replay = solo.side.last('challenge_replay')!;
      expect(replay.state, 'auth_failed');
      expect(replay.error, 'Pairing did not go through. Try again.');
      expect(dialed.closed, isTrue);
      await solo.close();
    });

    test('a frame sealed with another passphrase before pairing means the passphrases differ', () async {
      final solo = await Solo.open();
      await solo.init();
      final link = await solo.accept(partnerId);
      await solo.deliver(link, {'type': 'CHALLENGE', 'nonce': 'n' * 24}, as: VaultKey.fromBits(randomBytes(32)));
      final status = solo.side.last('passphrase_mismatch')!;
      expect(status.state, 'auth_failed');
      expect(status.error, 'Your passphrases do not match. Check you both typed exactly the same one.');
      await solo.close();
    });

    test('an out of date web build is asked to update', () async {
      final solo = await Solo.open();
      await solo.init();
      final link = await solo.accept(partnerId);
      link.receive({
        'protocol': 'SWEETHEART_V1',
        'payload': {'ciphertext': 'x', 'iv': 'y'},
      });
      await settle();
      expect(solo.side.last('version_mismatch')!.error, 'Their Our Space is out of date. Update it on both phones so you can sync.');
      await solo.close();
    });
  });

  group('heartbeat', () {
    test('pings every 15 seconds and answers pings', () async {
      final solo = await Solo.open();
      final link = await solo.authorizedWith(partnerId);
      expect(solo.side.engine.linkState, isIn([PeerLinkState.syncing, PeerLinkState.authorised]));
      await solo.advance(15000);
      expect(solo.sentTypes(link).where((t) => t == 'PING'), hasLength(1));
      await solo.deliver(link, {'type': 'PING', 't': base});
      expect(solo.sentTypes(link).last, 'PONG');
      await solo.close();
    });

    test('gives up after 50 seconds of silence', () async {
      final solo = await Solo.open();
      final link = await solo.authorizedWith(partnerId);
      await solo.advance(45000);
      expect(solo.side.saw('peer_unresponsive'), isFalse);
      await solo.advance(15000);
      expect(solo.side.last('peer_unresponsive')!.error, 'Lost them - their phone stopped responding. Tap to reconnect.');
      expect(link.closed, isTrue);
      await solo.close();
    });

    test('anything readable from the partner keeps the link alive', () async {
      final solo = await Solo.open();
      final link = await solo.authorizedWith(partnerId);
      for (var i = 0; i < 5; i++) {
        await solo.advance(14000);
        await solo.deliver(link, {'type': 'PONG', 't': base});
      }
      expect(solo.side.saw('peer_unresponsive'), isFalse);
      expect(solo.side.engine.isAuthorized, isTrue);
      await solo.close();
    });

    test('four unreadable frames are skipped and the fifth closes the link', () async {
      final solo = await Solo.open();
      final link = await solo.authorizedWith(partnerId);
      final stranger = VaultKey.fromBits(randomBytes(32));
      for (var i = 0; i < 4; i++) {
        await solo.deliver(link, {'type': 'PING', 't': base}, as: stranger);
      }
      final warnings = solo.side.statuses.where((s) => s.code == 'corrupt_frame').toList();
      expect(warnings, hasLength(4));
      expect(warnings.first.warning, 'Something came through that we could not read, so we skipped it.');
      await solo.deliver(link, {'type': 'PING', 't': base}, as: stranger);
      expect(solo.side.last('corrupt_stream')!.error,
          'Too much came through that we could not read, so we closed the connection. Tap to reconnect.');
      await solo.close();
    });
  });

  group('who may connect', () {
    test('a paired phone turns everyone else away', () async {
      final solo = await Solo.open();
      await solo.authorizedWith(partnerId);
      final other = await solo.accept('love-other000000');
      expect(other.closed, isTrue);
      expect(solo.side.last('unknown_peer_rejected')!.warning, 'Someone else tried to connect. We said no.');
      expect(solo.side.engine.isAuthorized, isTrue);
      await solo.close();
    });

    test('a second stranger waits, then may take a stalled slot after 3 seconds', () async {
      final solo = await Solo.open();
      await solo.init();
      final first = await solo.accept('love-stranger0001');
      final second = await solo.accept('love-stranger0002');
      expect(second.closed, isTrue);
      expect(first.closed, isFalse);
      expect(solo.side.last('unknown_peer_rejected')!.warning,
          'Someone else tried to connect while you were pairing. We said no.');
      await solo.advance(3000);
      final third = await solo.accept('love-stranger0003');
      expect(first.closed, isTrue);
      expect(third.closed, isFalse);
      expect(solo.side.engine.activeConnection?.peer, 'love-stranger0003');
      await solo.close();
    });

    test('when both phones dial at once the lower id keeps its own call', () async {
      final low = await Solo.open(peerId: 'love-aaaaaaaa0000');
      await low.init();
      final mine = await low.dial('love-zzzzzzzz0000', open: false);
      final theirs = await low.accept('love-zzzzzzzz0000', open: false);
      expect(theirs.closed, isTrue);
      expect(mine.closed, isFalse);
      await low.close();

      final high = await Solo.open(peerId: 'love-zzzzzzzz0000');
      await high.init();
      final ours = await high.dial('love-aaaaaaaa0000', open: false);
      final incoming = await high.accept('love-aaaaaaaa0000', open: false);
      expect(ours.closed, isTrue);
      expect(incoming.closed, isFalse);
      expect(high.side.engine.activeConnection, same(incoming));
      await high.close();
    });

    test('a phone retrying too fast is asked to wait', () async {
      final solo = await Solo.open();
      await solo.init();
      final first = await solo.accept('love-stranger0001');
      first.close();
      await settle();
      final again = await solo.accept('love-stranger0001');
      expect(again.closed, isTrue);
      expect(solo.side.last('peer_rate_limited')!.warning, 'A phone is retrying too fast, so we asked it to wait a moment.');
      await solo.close();
    });

    test('a crowd of unknown phones pauses pairing for a minute', () async {
      final solo = await Solo.open();
      await solo.init();
      for (var i = 0; i < 6; i++) {
        final link = await solo.accept('love-crowd00000$i');
        expect(link.closed, isFalse);
        link.close();
        await settle();
      }
      final seventh = await solo.accept('love-crowd000007');
      expect(seventh.closed, isTrue);
      expect(solo.side.last('pairing_flood')!.warning,
          'A few unknown phones are trying to connect, so pairing is paused for a minute. This does not affect your partner.');
      await solo.advance(60001);
      final later = await solo.accept('love-crowd000008');
      expect(later.closed, isFalse);
      await solo.close();
    });
  });

  group('sync sessions', () {
    test('unknown sessions, repeats and out of order batches are refused like the web', () async {
      final solo = await Solo.open();
      final link = await solo.authorizedWith(partnerId);
      final ours = solo.lastSent(link, 'SYNC_MANIFEST');
      final sessionId = ours['sessionId'] as String;
      expect(sessionId, hasLength(12));
      expect(ours['wantReciprocal'], isFalse);

      await solo.deliver(link, {'type': 'SYNC_REQUEST_RECORDS', 'sessionId': 'nope-nope-nope', 'requests': []});
      expect(solo.lastSent(link, 'SYNC_ERROR'), {
        'type': 'SYNC_ERROR',
        'sessionId': 'nope-nope-nope',
        'code': 'unknown_session',
        'message': 'No such sync session',
        'fatal': true,
      });

      await solo.deliver(link, {'type': 'SYNC_REQUEST_RECORDS', 'sessionId': sessionId, 'requests': []});
      expect(solo.lastSent(link, 'SYNC_RECORDS_BATCH'), {
        'type': 'SYNC_RECORDS_BATCH',
        'sessionId': sessionId,
        'seq': 0,
        'records': [],
        'final': true,
      });
      await solo.deliver(link, {'type': 'SYNC_REQUEST_RECORDS', 'sessionId': sessionId, 'requests': []});
      expect(solo.lastSent(link, 'SYNC_ERROR')['code'], 'duplicate_request');

      await solo.deliver(link, {
        'type': 'SYNC_MANIFEST',
        'sessionId': 'remote-session-1',
        'manifest': {
          lettersTable: [
            {'id': 'let-x', 'updatedAt': base, 'deleted': false},
          ],
        },
        'wantReciprocal': false,
      });
      expect(solo.lastSent(link, 'SYNC_REQUEST_RECORDS'), {
        'type': 'SYNC_REQUEST_RECORDS',
        'sessionId': 'remote-session-1',
        'requests': [
          {'table': lettersTable, 'id': 'let-x'},
        ],
      });
      await solo.deliver(link, {'type': 'SYNC_RECORDS_BATCH', 'sessionId': 'remote-session-1', 'seq': 1, 'records': [], 'final': true});
      expect(solo.lastSent(link, 'SYNC_ERROR')['code'], 'out_of_order');
      expect(solo.side.last('out_of_order')!.warning, 'Things arrived out of order, so we stopped. Try again.');

      await solo.deliver(link, {'type': 'SYNC_MANIFEST', 'sessionId': 'short', 'manifest': {}});
      expect(solo.lastSent(link, 'SYNC_ERROR')['code'], 'bad_session');
      await solo.deliver(link, {'type': 'SYNC_MANIFEST', 'sessionId': 'remote-session-2', 'manifest': []});
      expect(solo.lastSent(link, 'SYNC_ERROR')['code'], 'manifest_rejected');
      expect(solo.side.last('manifest_rejected')!.warning, 'Something came through that we could not read. Try again.');
      await solo.close();
    });

    test('a manifest with nothing new is answered with an empty completion', () async {
      final solo = await Solo.open();
      final link = await solo.authorizedWith(partnerId);
      await solo.deliver(link, {
        'type': 'SYNC_MANIFEST',
        'sessionId': 'remote-session-9',
        'manifest': {lettersTable: []},
        'wantReciprocal': true,
      });
      expect(solo.lastSent(link, 'SYNC_COMPLETE'), {
        'type': 'SYNC_COMPLETE',
        'sessionId': 'remote-session-9',
        'applied': 0,
        'rejected': 0,
        'unverifiable': 0,
      });
      await solo.close();
    });

    test('a session left hanging for two minutes is stopped', () async {
      final solo = await Solo.open();
      final link = await solo.authorizedWith(partnerId);
      expect(solo.side.engine.isSyncing, isTrue);
      for (var i = 0; i < 8; i++) {
        await solo.advance(14000);
        await solo.deliver(link, {'type': 'PONG', 't': base});
      }
      expect(solo.side.saw('sync_timeout'), isFalse);
      await solo.advance(8000);
      expect(solo.side.last('sync_timeout')!.error, 'That took too long, so we stopped. Nothing was lost - try again.');
      await solo.close();
    });

    test('our partner\'s completion and errors read the way the web shows them', () async {
      final solo = await Solo.open();
      final link = await solo.authorizedWith(partnerId);
      final sessionId = solo.lastSent(link, 'SYNC_MANIFEST')['sessionId'];
      await solo.deliver(link, {'type': 'SYNC_COMPLETE', 'sessionId': sessionId, 'applied': 2, 'rejected': 0, 'unverifiable': 1});
      final done = solo.side.last('sync_complete')!;
      expect(done.message, 'Sent 2 updates to your partner!');
      expect(done.fields['sent'], 2);
      expect(solo.side.last('records_unverifiable_remote')!.warning,
          "Your partner's phone could not verify 1 of your change and did not apply it. Make sure both phones are on the same version of Our Space, then unlock this vault again and sync.");

      await solo.deliver(link, {'type': 'SYNC_ERROR', 'sessionId': 'x' * 10, 'code': 'record_too_large'});
      expect(solo.side.last('record_too_large')!.warning,
          "Some items on your partner's device are too large to transfer and were skipped.");
      await solo.deliver(link, {'type': 'SYNC_ERROR', 'code': 'odd', 'message': 'Batch arrived out of order'});
      expect(solo.side.last('odd')!.warning, 'Your partner reported a sync problem: Batch arrived out of order');
      await solo.deliver(link, {'type': 'SYNC_ERROR'});
      expect(solo.side.last('sync_error')!.warning, 'Your partner reported a sync problem.');
      await solo.close();
    });

    test('syncNow needs a paired link and returns true once one is up', () async {
      final solo = await Solo.open();
      await solo.init();
      expect(await solo.side.engine.syncNow(), isFalse);
      final link = await solo.authorizedWith(partnerId);
      expect(await solo.side.engine.syncNow(), isTrue);
      expect(solo.sentTypes(link).where((t) => t == 'SYNC_MANIFEST'), hasLength(2));
      expect(solo.lastSent(link, 'SYNC_MANIFEST')['wantReciprocal'], isTrue);
      await solo.close();
    });
  });

  group('records from the partner', () {
    test('newest wins, tombstones win ties, and bad rows are counted as skipped', () async {
      final solo = await Solo.open();
      final key = solo.key;
      final store = solo.side.store;
      await store.putRow(lettersTable, sealedRow(key, lettersTable, {'id': 'tie-live', 'title': 'Kept', 'updatedAt': base}));
      await store.putRow(lettersTable, sealedRow(key, lettersTable, {'id': 'tie-dead', 'updatedAt': base, 'deleted': true}));
      await store.putRow(lettersTable, sealedRow(key, lettersTable, {'id': 'newer-here', 'title': 'Mine', 'updatedAt': base + 50}));

      final link = await solo.authorizedWith(partnerId);
      final incoming = [
        sealedRow(key, lettersTable, {'id': 'tie-live', 'updatedAt': base, 'deleted': true}),
        sealedRow(key, lettersTable, {'id': 'tie-dead', 'title': 'Back', 'updatedAt': base}),
        sealedRow(key, lettersTable, {'id': 'newer-here', 'title': 'Theirs', 'updatedAt': base + 10}),
        sealedRow(key, lettersTable, {'id': 'fresh', 'title': 'New', 'updatedAt': base + 5}),
        sealedRow(key, lettersTable, {'id': 'wrong-table', 'title': 'x', 'updatedAt': base + 6}),
        {...sealedRow(key, lettersTable, {'id': 'old-v', 'updatedAt': base + 7}), 'v': 1},
      ];
      await solo.deliver(link, {
        'type': 'SYNC_MANIFEST',
        'sessionId': 'remote-session-1',
        'manifest': {
          lettersTable: [for (final row in incoming) {'id': row['id'], 'updatedAt': row['updatedAt'], 'deleted': row['deleted']}],
        },
        'wantReciprocal': false,
      });
      final requested = (solo.lastSent(link, 'SYNC_REQUEST_RECORDS')['requests'] as List).map((r) => (r as Map)['id']).toList();
      expect(requested, ['tie-live', 'fresh', 'wrong-table', 'old-v']);

      await solo.deliver(link, {
        'type': 'SYNC_RECORDS_BATCH',
        'sessionId': 'remote-session-1',
        'seq': 0,
        'records': [
          {'table': lettersTable, 'data': wire(incoming[0])},
          {'table': lettersTable, 'data': wire(incoming[1])},
          {'table': lettersTable, 'data': wire(incoming[2])},
          {'table': lettersTable, 'data': wire(incoming[3])},
          {'table': bucketListTable, 'data': wire(incoming[4])},
          {'table': lettersTable, 'data': wire(incoming[5])},
          {'table': 'vaultMeta', 'data': wire(incoming[3])},
        ],
        'final': true,
      });
      expect(solo.lastSent(link, 'SYNC_COMPLETE'), {
        'type': 'SYNC_COMPLETE',
        'sessionId': 'remote-session-1',
        'applied': 2,
        'rejected': 3,
        'unverifiable': 0,
      });
      expect((await store.getRow(lettersTable, 'tie-live'))!['deleted'], isTrue);
      expect((await store.getRow(lettersTable, 'tie-dead'))!['deleted'], isTrue);
      expect((await store.getDecrypted(lettersTable, 'newer-here', key))!['title'], 'Mine');
      expect((await store.getDecrypted(lettersTable, 'fresh', key))!['title'], 'New');
      expect(await store.getRow(bucketListTable, 'wrong-table'), isNull);
      expect(solo.side.last('records_rejected')!.warning, '3 item(s) from your partner could not be read and were skipped.');
      expect(solo.side.updates.single.count, 2);
      expect(store.clock.observedRemoteMax, base + 10);
      await solo.close();
    });

    test('far-future rows are refused once with the clock advice', () async {
      final solo = await Solo.open();
      final key = solo.key;
      final link = await solo.authorizedWith(partnerId);
      final future = sealedRow(key, lettersTable, {'id': 'future', 'updatedAt': solo.clock.now() + 2 * 86400000});
      await solo.deliver(link, {
        'type': 'LIVE_RECORD_BROADCAST',
        'record': {'table': lettersTable, 'data': wire(future)},
      });
      expect(solo.side.last('clock_skew')!.warning,
          "Your partner's device clock looks far ahead of yours, so some of their items were not accepted. Check the date and time settings on both phones.");
      expect(solo.side.last('future_timestamp')!.warning, 'One update could not be read, so we skipped it.');
      await solo.deliver(link, {
        'type': 'SYNC_MANIFEST',
        'sessionId': 'remote-session-3',
        'manifest': {
          lettersTable: [
            {'id': 'future', 'updatedAt': solo.clock.now() + 2 * 86400000, 'deleted': false},
          ],
        },
      });
      expect(solo.side.statuses.where((s) => s.code == 'clock_skew'), hasLength(1));
      expect(solo.lastSent(link, 'SYNC_COMPLETE')['sessionId'], 'remote-session-3');
      await solo.close();
    });

    test('a live record from the partner lands and is announced once', () async {
      final solo = await Solo.open();
      final key = solo.key;
      final link = await solo.authorizedWith(partnerId);
      final burst = sealedRow(key, loveBurstsTable, {'id': 'burst-partner', 'count': 3, 'lastSentAt': base, 'updatedAt': base});
      await solo.deliver(link, {
        'type': 'LIVE_RECORD_BROADCAST',
        'record': {'table': loveBurstsTable, 'data': wire(burst)},
      });
      expect(solo.side.updates.single.single, isTrue);
      expect(solo.side.updates.single.table, loveBurstsTable);
      await solo.deliver(link, {
        'type': 'LIVE_RECORD_BROADCAST',
        'record': {'table': loveBurstsTable, 'data': wire(burst)},
      });
      expect(solo.side.updates, hasLength(1));
      await solo.close();
    });

    test('big photos go out in batches under 512 KB, each chunked like PeerJS', () async {
      final solo = await Solo.open();
      final key = solo.key;
      for (var i = 0; i < 3; i++) {
        await solo.side.store.putRow(
          memoriesTable,
          sealedRow(key, memoriesTable, {
            'id': 'mem-$i',
            'caption': 'Big $i',
            'imageBlob': randomBytes(200000),
            'updatedAt': base + i,
          }),
        );
      }
      final link = await solo.authorizedWith(partnerId);
      final sessionId = solo.lastSent(link, 'SYNC_MANIFEST')['sessionId'];
      final framesBefore = link.frames.length;
      await solo.deliver(link, {
        'type': 'SYNC_REQUEST_RECORDS',
        'sessionId': sessionId,
        'requests': [
          for (var i = 0; i < 3; i++) {'table': memoriesTable, 'id': 'mem-$i'},
        ],
      });
      final batches = solo.sent(link).where((m) => m['type'] == 'SYNC_RECORDS_BATCH').toList();
      expect([for (final b in batches) b['seq']], [0, 1, 2]);
      expect([for (final b in batches) b['final']], [false, false, true]);
      expect([for (final b in batches) (b['records'] as List).length], [1, 1, 1]);
      final record = ((batches.first['records'] as List).first as Map)['data'] as Map;
      expect(record.keys.toList(), ['id', 'updatedAt', 'deleted', 'v', 'ciphertext', 'iv', 'imageBlobBase64']);
      expect(link.frames.length - framesBefore, greaterThan(3 * 20));
      expect(link.frames.every((f) => f.length <= 16300 + 64), isTrue);
      await solo.close();
    });
  });

  group('couple settings over the channel', () {
    test('settings go out trimmed and come in checked', () async {
      final solo = await Solo.open();
      final link = await solo.authorizedWith(partnerId);
      expect(
        await solo.side.engine.syncVaultConfig({'coupleNames': 'A' * 130, 'startDate': '14/02/2024', 'updatedAt': base}),
        isTrue,
      );
      expect(solo.lastSent(link, 'SYNC_CONFIG'), {
        'type': 'SYNC_CONFIG',
        'config': {'coupleNames': 'A' * 120, 'startDate': '', 'updatedAt': base},
      });

      await solo.deliver(link, {'type': 'SYNC_CONFIG', 'config': 'nope'});
      expect(solo.side.last('bad_config')!.warning, 'We could not read their details. Try again.');
      await solo.deliver(link, {
        'type': 'SYNC_CONFIG',
        'config': {'coupleNames': '', 'startDate': 'never'},
      });
      expect(solo.side.last('bad_config')!.warning, 'Nothing to update from their side.');
      await solo.deliver(link, {
        'type': 'SYNC_CONFIG',
        'config': {'coupleNames': 'Ash & Bee', 'startDate': '2024-02-14', 'updatedAt': solo.clock.now() + 3 * 86400000},
      });
      final config = solo.side.configs.single;
      expect(config.coupleNames, 'Ash & Bee');
      expect(config.startDate, '2024-02-14');
      expect(config.updatedAt, 0);
      await solo.close();
    });

    test('nothing is sent before pairing', () async {
      final solo = await Solo.open();
      await solo.init();
      expect(await solo.side.engine.syncVaultConfig({'coupleNames': 'Us'}), isFalse);
      await solo.close();
    });
  });

  group('signalling', () {
    test('a taken id is retried once after 1.2 seconds, then replaced with a fresh one', () async {
      final solo = await Solo.open(autoOpenServer: false);
      String? opened;
      final pending = solo.side.engine.init(solo.key, myId).then((id) => opened = id);
      await settle();
      expect(solo.network.created, hasLength(1));
      (solo.network.created.single as FakeEndpoint).serverError(PeerError.unavailableId);
      await solo.advance(1199);
      expect(solo.network.created, hasLength(1));
      await solo.advance(1);
      expect(solo.network.created, hasLength(2));
      expect((solo.network.created.last as FakeEndpoint).requestedId, myId);
      (solo.network.created.last as FakeEndpoint).serverError(PeerError.unavailableId);
      await settle();
      expect(solo.network.created, hasLength(3));
      final fresh = (solo.network.created.last as FakeEndpoint).requestedId;
      expect(fresh, isNot(myId));
      expect(fresh, startsWith('love-'));
      expect(solo.side.store.settings.getItem(localPeerIdKey), fresh);
      (solo.network.created.last as FakeEndpoint).serverOpen();
      await pending;
      expect(opened, fresh);
      expect(solo.side.last('peer_ready')!.peerId, fresh);
      await solo.close();
    });

    test('a missing partner and a dropped server read like the web', () async {
      final solo = await Solo.open();
      await solo.init();
      await solo.dial(partnerId, open: false);
      solo.endpoint.serverError(PeerError.peerUnavailable);
      final missing = solo.side.last('peer-unavailable')!;
      expect(missing.state, 'error');
      expect(missing.error, 'Cannot find their phone. Ask them to open Our Space and leave it on screen.');
      expect(solo.side.engine.activeConnection, isNull);

      solo.endpoint.serverError(PeerError.network);
      expect(solo.side.last('network')!.error, 'Trouble with the connection. Check your internet and try again.');
      solo.endpoint.serverError(PeerError.serverError);
      expect(solo.side.last('server-error')!.error, 'Could not reach your partner right now.');
      await solo.close();
    });

    test('server trouble while paired is only a warning', () async {
      final solo = await Solo.open();
      await solo.authorizedWith(partnerId);
      solo.endpoint.serverError(PeerError.network);
      final warning = solo.side.last('signalling_network')!;
      expect(warning.warning, 'Trouble with the connection. Check your internet and try again.');
      expect(warning.errorType, 'network');
      expect(solo.side.engine.isAuthorized, isTrue);
      await solo.close();
    });

    test('a dropped server connection is retried at once, then with growing pauses', () async {
      final solo = await Solo.open();
      await solo.init();
      final endpoint = solo.endpoint;
      endpoint.drop();
      expect(endpoint.reconnects, 1);
      endpoint.drop();
      expect(endpoint.reconnects, 1);
      await solo.advance(1000);
      expect(endpoint.reconnects, 2);
      endpoint.drop();
      await solo.advance(1999);
      expect(endpoint.reconnects, 2);
      await solo.advance(1);
      expect(endpoint.reconnects, 3);
      endpoint.serverOpen();
      endpoint.drop();
      expect(endpoint.reconnects, 4);
      await solo.close();
    });

    test('coming back to the app reconnects the server and checks on the partner', () async {
      final solo = await Solo.open();
      final link = await solo.authorizedWith(partnerId);
      final endpoint = solo.endpoint;
      endpoint.drop();
      endpoint.drop();
      final before = endpoint.reconnects;
      solo.side.engine.onForeground();
      await settle();
      expect(endpoint.reconnects, before + 1);
      expect(solo.sentTypes(link).last, 'PING');
      await solo.close();
    });
  });

  group('route', () {
    Map<String, Object?> pair(String type) => {
          'id': 'pair',
          'type': 'candidate-pair',
          'nominated': true,
          'localCandidateId': 'local',
          'remoteCandidateId': 'remote',
        };

    test('reports a direct route', () async {
      final route = FakeRoute(stats: [
        pair('host'),
        {'id': 'local', 'type': 'local-candidate', 'candidateType': 'host'},
        {'id': 'remote', 'type': 'remote-candidate', 'candidateType': 'srflx'},
      ]);
      final solo = await Solo.open();
      await solo.authorizedWith(partnerId, route: route);
      final update = solo.side.last('route_update')!;
      expect(update.connectionType, 'direct');
      expect(update.isDirect, isTrue);
      await solo.close();
    });

    test('reports a relayed route', () async {
      final route = FakeRoute(stats: [
        pair('relay'),
        {'id': 'local', 'type': 'local-candidate', 'candidateType': 'relay'},
        {'id': 'remote', 'type': 'remote-candidate', 'candidateType': 'host'},
      ]);
      final solo = await Solo.open();
      await solo.authorizedWith(partnerId, route: route);
      expect(solo.side.last('route_update')!.connectionType, 'relayed');
      await solo.close();
    });

    test('an ICE failure after pairing gives the no-relay advice without a second disconnect', () async {
      final route = FakeRoute();
      final solo = await Solo.open();
      final link = await solo.authorizedWith(partnerId, route: route);
      route.emit('failed');
      await settle();
      final failed = solo.side.last('ice_failed')!;
      expect(failed.error, iceFailureMessage);
      expect(link.closed, isTrue);
      expect(solo.side.saw('peer_closed'), isFalse);
      await solo.close();
    });
  });

  test('broadcasts skip unknown tables and nothing goes out before pairing', () async {
    final solo = await Solo.open();
    await solo.init();
    final seen = <String>[];
    solo.side.engine.addLocalRecordListener((table, id) => seen.add('$table/$id'));
    expect(await solo.side.engine.broadcastLiveRecord('vaultMeta', {'id': 'config'}), isFalse);
    expect(await solo.side.engine.broadcastLiveRecord(lettersTable, {'id': 'x'}), isFalse);
    expect(seen, ['$lettersTable/x']);
    await solo.close();
  });

  test('destroy forgets the key and says so', () async {
    final solo = await Solo.open();
    await solo.authorizedWith(partnerId);
    final endpoint = solo.endpoint;
    solo.side.engine.destroy();
    expect(solo.side.engine.cryptoKey, isNull);
    expect(solo.side.engine.peer, isNull);
    expect(endpoint.destroyed, isTrue);
    expect(solo.side.statuses.last.code, 'destroyed');
    expect(solo.side.engine.linkState, PeerLinkState.disconnected);
    await solo.side.store.close();
  });
}
