import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine/crypto/aes_gcm.dart';
import 'package:our_space_mobile/core/engine/crypto/base64.dart';
import 'package:our_space_mobile/core/engine/crypto/envelope.dart';
import 'package:our_space_mobile/core/engine/crypto/js_compat.dart';
import 'package:our_space_mobile/core/engine/domain/sky_drawings.dart';
import 'package:our_space_mobile/core/engine/p2p/peer_sync_engine.dart';
import 'package:our_space_mobile/core/engine/p2p/sky_together_wire.dart';
import 'package:our_space_mobile/core/engine/storage/tables.dart';
import 'package:our_space_mobile/models/sky_drawing_record.dart';

import '../support/harness.dart';
import 'support/engine_harness.dart';
import 'support/fake_clock.dart';
import 'support/fake_peer.dart';
import 'support/solo.dart';

SkyDrawing kite() => SkyDrawing(
  stars: [
    const SkyDrawnStar(id: 'a', x: 0.2, y: 0.2, by: 'owner-aaaa1111', at: 100, gen: 0),
    const SkyDrawnStar(id: 'b', x: 0.7, y: 0.6, by: 'owner-bbbb2222', at: 120, gen: 0),
  ],
  lines: [SkyDrawnLine(from: 'a', to: 'b', by: 'owner-aaaa1111', at: 130, gen: 0)],
);

void main() {
  test('the fullest drawing still fits in one live state event', () {
    String id(String prefix, int i) => '$prefix${i.toString().padLeft(12, '0')}';
    const owner = 'owner-0123456789abcdef';
    final stars = [
      for (var i = 0; i < skyDrawingKeptStars; i++)
        SkyDrawnStar(id: id('s-', i), x: 0.1234, y: 0.5678, by: owner, at: 1760000000000 + i, gen: 7),
    ];
    final full = SkyDrawing(
      gen: 7,
      stars: stars,
      lines: [
        for (var i = 0; i < skyDrawingKeptLines; i++)
          SkyDrawnLine(from: stars[i % 60].id, to: stars[(i + 1 + i ~/ 60) % 60].id, by: owner, at: 1760000001000 + i, gen: 7),
      ],
      removed: [for (var i = 0; i < skyDrawingKeptRemoved; i++) id('r-', i)],
    );
    expect(full.stars.length, skyDrawingKeptStars);
    expect(full.lines.length, skyDrawingKeptLines);
    expect(full.removed.length, skyDrawingKeptRemoved);
    final wire = SkyStateEvent(drawing: id('sky-', 1), state: full).toWire();
    expect(jsonStringify(wire).length, lessThan(maxSkyTogetherChars));
    expect(SkyTogetherEvent.fromWire(wire), SkyStateEvent(drawing: id('sky-', 1), state: full));
  });

  test('the manifest a partner sees is exactly as before until there is a drawing to share', () async {
    final solo = await Solo.open();
    final link = await solo.authorizedWith(partnerId);
    final first = solo.lastSent(link, 'SYNC_MANIFEST')['manifest'] as Map;
    expect(first.keys.toList(), webSyncedTables);

    await SkyDrawingService(store: solo.side.store).saveProgress(solo.key, id: 'sky-1', drawing: kite());
    expect(await solo.side.engine.syncNow(), isTrue);
    await settle();
    final second = solo.lastSent(link, 'SYNC_MANIFEST')['manifest'] as Map;
    expect(second.keys.toList(), syncedTables);
    expect((second[skyDrawingsTable] as List).single, containsPair('id', 'sky-1'));
    await solo.close();
  });

  test('a partner without drawings asking for one gets it, and a manifest naming drawings is read like any other', () async {
    final solo = await Solo.open();
    final link = await solo.authorizedWith(partnerId);
    await SkyDrawingService(store: solo.side.store).saveProgress(solo.key, id: 'sky-1', drawing: kite());

    await solo.deliver(link, {
      'type': 'SYNC_MANIFEST',
      'sessionId': 'session-sky-0001',
      'manifest': {
        skyDrawingsTable: [
          {'id': 'sky-2', 'updatedAt': solo.clock.now(), 'deleted': false},
        ],
        'skyDrawingsNext': [
          {'id': 'sky-3', 'updatedAt': solo.clock.now(), 'deleted': false},
        ],
      },
      'wantReciprocal': false,
    });
    final asked = solo.lastSent(link, 'SYNC_REQUEST_RECORDS');
    expect(asked['requests'], [
      {'table': skyDrawingsTable, 'id': 'sky-2'},
    ]);
    await solo.close();
  });

  test('two app engines bring each other the drawings they lack in a normal sync', () async {
    final key = VaultKey.fromBits(randomBytes(32));
    final clock = FakePeerClock();
    final network = FakeNetwork();
    final a = await EngineSide.open('A', 'love-drawaaaaaaaaaa', key, endpoints: network.create, clock: clock);
    final b = await EngineSide.open('B', 'love-drawbbbbbbbbbb', key, endpoints: network.create, clock: clock);
    await SkyDrawingService(store: a.store).finish(key, id: 'sky-from-a', drawing: kite(), name: 'Our kite', at: clock.now());
    await SkyDrawingService(store: b.store).saveProgress(key, id: 'sky-from-b', drawing: kite());

    await a.init();
    await b.init();
    await a.engine.connectToPartner(b.peerId);
    await waitFor(
      () => a.saw('sync_complete') && b.saw('sync_complete') && !a.engine.isSyncing && !b.engine.isSyncing,
      reason: 'the first sync',
    );
    await settle();

    for (final side in [a, b]) {
      final kept = await SkyDrawingService(store: side.store).list(key);
      expect(kept.map((r) => r.id).toSet(), {'sky-from-a', 'sky-from-b'}, reason: side.name);
      expect(kept.firstWhere((r) => r.id == 'sky-from-a').name, 'Our kite');
      final row = (await side.store.getRow(skyDrawingsTable, 'sky-from-a'))!;
      expect(decryptRecord(row, key, table: skyDrawingsTable)['_tableTampered'], isFalse);
    }
    expect(a.statuses.where((s) => s.warning != null), isEmpty);
    expect(b.statuses.where((s) => s.warning != null), isEmpty);

    await a.close();
    await b.close();
  });
}
