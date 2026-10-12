import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine/p2p/peer_status.dart';
import 'package:our_space_mobile/core/engine/storage/tables.dart';

import 'support/engine_harness.dart';
import 'support/fake_clock.dart';
import 'support/fake_peer.dart';
import 'support/fixtures.dart';

List<String> describe(Iterable<Object?> statuses) => [
      for (final raw in statuses)
        () {
          final status = raw is PeerStatus ? raw.fields : (raw as Map).cast<String, Object?>();
          final message = status['message'];
          final warning = status['warning'];
          final error = status['error'];
          return '${status['state']}:${status['code']}'
              '${message is String ? ' «$message»' : ''}'
              '${warning is String ? ' !$warning' : ''}'
              '${error is String ? ' ×$error' : ''}';
        }(),
    ];

List<String> fromChannelOpen(List<String> lines) {
  final start = lines.indexWhere((line) => line.startsWith('handshaking:channel_open'));
  return start < 0 ? lines : lines.sublist(start);
}

void expectSameStory(List<String> ours, List<String> web) {
  expect(ours.take(3).toList(), web.take(3).toList());
  expect(ours.sublist(ours.length - 2), web.sublist(web.length - 2));
  List<String> messages(List<String> lines) =>
      [for (final line in lines) if (line.contains('«')) line.substring(line.indexOf('«'))]..sort();
  expect(messages(ours), messages(web));
  expect(ours.length, web.length);
}

void main() {
  final fixture = readP2pFixture('web_peer_session.json');
  final peers = (fixture['peers'] as Map).cast<String, String>();
  final configs = (fixture['configs'] as Map).cast<String, Object?>();
  final start = (fixture['start'] as Map).cast<String, Object?>();
  final end = (fixture['end'] as Map).cast<String, Object?>();
  final webStatuses = (fixture['statuses'] as Map).cast<String, Object?>();

  test('two phones sync the captured web session to the same end state, with the same statuses', () async {
    final key = keyFromBase64(fixture['keyBase64'] as String);
    final clock = FakePeerClock();
    final network = FakeNetwork();
    final a = await EngineSide.open('A', peers['A']!, key, endpoints: network.create, clock: clock);
    final b = await EngineSide.open('B', peers['B']!, key, endpoints: network.create, clock: clock);
    await a.seed((start['A'] as Map).cast<String, Object?>());
    await b.seed((start['B'] as Map).cast<String, Object?>());

    a.engine.addStatusListener((status) {
      if (status.state == 'authorized') a.engine.syncVaultConfig((configs['A'] as Map).cast<String, Object?>());
    });
    b.engine.addStatusListener((status) {
      if (status.state == 'authorized') b.engine.syncVaultConfig((configs['B'] as Map).cast<String, Object?>());
    });

    expect(await a.init(), peers['A']);
    expect(await b.init(), peers['B']);
    await a.engine.connectToPartner(peers['B']);

    await waitFor(
      () => a.saw('sync_complete') && b.saw('sync_complete') && !a.engine.isSyncing && !b.engine.isSyncing,
      reason: 'the first sync',
    );
    await settle();

    expect(a.engine.isAuthorized && b.engine.isAuthorized, isTrue);
    expect(a.engine.linkState, PeerLinkState.authorised);
    expect(a.configs.single.coupleNames, 'Bee & Ash');
    expect(b.configs.single.coupleNames, 'Ash & Bee');
    expect(b.configs.single.startDate, '2024-02-14');
    expect(b.configs.single.updatedAt, 1760000000050);
    expect(a.updates.single.count, 3);
    expect(b.updates.single.count, 5);

    final burst = ((end['A'] as Map)[loveBurstsTable] as List)
        .cast<Map<String, Object?>>()
        .firstWhere((row) => row['id'] == 'burst-device-a');
    await a.seed({
      loveBurstsTable: [burst],
    });
    final row = await a.store.getRow(loveBurstsTable, 'burst-device-a');
    expect(await a.engine.broadcastLiveRecord(loveBurstsTable, row), isTrue);
    await waitFor(() => b.updates.any((u) => u.single), reason: 'the live burst');
    expect(b.updates.last.table, loveBurstsTable);

    final pongsBefore = b.engine.lastPongAt;
    await a.engine.heartbeatTick();
    await settle();
    expect(b.engine.lastPongAt, greaterThanOrEqualTo(pongsBefore));

    expect(await a.engine.syncNow(), isTrue);
    await waitFor(() => !a.engine.isSyncing && !b.engine.isSyncing && a.codes.where((c) => c == 'sync_complete').length == 2,
        reason: 'the manual sync');
    await settle();

    a.engine.closeConnection();
    await waitFor(() => b.saw('peer_closed'), reason: 'the partner to notice');

    expect(canonicalJson(await a.dump()), canonicalJson(end['A']));
    expect(canonicalJson(await b.dump()), canonicalJson(end['B']));

    await a.close();
    await b.close();

    expectSameStory(fromChannelOpen(describe(a.statuses)), describe(webStatuses['A'] as List));
    expectSameStory(fromChannelOpen(describe(b.statuses)), describe(webStatuses['B'] as List));
  });
}
