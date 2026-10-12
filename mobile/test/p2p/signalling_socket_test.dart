import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine/p2p/peer_endpoint.dart';
import 'package:our_space_mobile/core/engine/p2p/peerjs.dart';
import 'package:our_space_mobile/core/engine/p2p/signal_socket.dart';
import 'package:our_space_mobile/core/engine/storage/tables.dart';

import 'support/engine_harness.dart';
import 'support/fake_clock.dart';
import 'support/fixtures.dart';
import 'support/local_peer_server.dart';

PeerEndpointFactory throughServer(LocalPeerServer server, LoopbackRtc rtc) => (id, iceServers) => PeerJsPeer(
      id,
      options: PeerJsOptions(host: '127.0.0.1', port: server.port, secure: false, iceServers: iceServers),
      connector: IoSignalSocket.connect,
      rtcFactory: rtc.create,
    );

void main() {
  final fixture = readP2pFixture('web_peer_session.json');
  final peers = (fixture['peers'] as Map).cast<String, String>();
  final start = (fixture['start'] as Map).cast<String, Object?>();

  test('two phones meet through a PeerJS server over real WebSockets and sync', () async {
    final server = await LocalPeerServer.start();
    final rtc = LoopbackRtc();
    final key = keyFromBase64(fixture['keyBase64'] as String);
    final now = DateTime.now().millisecondsSinceEpoch;
    final a = await EngineSide.open('A', peers['A']!, key, endpoints: throughServer(server, rtc), clock: FakePeerClock(now));
    final b = await EngineSide.open('B', peers['B']!, key, endpoints: throughServer(server, rtc), clock: FakePeerClock(now));
    await a.seed((start['A'] as Map).cast<String, Object?>());
    await b.seed((start['B'] as Map).cast<String, Object?>());

    expect(await a.init(), peers['A']);
    expect(await b.init(), peers['B']);
    final first = server.connections.first;
    expect(first.queryParameters['key'], 'peerjs');
    expect(first.queryParameters['id'], peers['A']);
    expect(first.queryParameters['token'], matches(RegExp(r'^[0-9a-z]{11}$')));
    expect(first.queryParameters['version'], '1.5.5');

    await a.engine.connectToPartner(peers['B']);
    await waitFor(
      () => a.saw('sync_complete') && b.saw('sync_complete') && !a.engine.isSyncing && !b.engine.isSyncing,
      reason: 'the sync through the server',
    );
    await settle();

    expect(canonicalJson(await a.dump()), canonicalJson(await b.dump()));
    final memories = (await a.dump())[memoriesTable] as List;
    expect(memories, hasLength(1));
    expect(b.saw('route_update'), isTrue);
    expect(b.last('route_update')!.connectionType, 'direct');

    final types = server.relayed.map((m) => m['type']).toSet();
    expect(types, containsAll(['OFFER', 'ANSWER', 'CANDIDATE']));
    final offer = server.relayed.firstWhere((m) => m['type'] == 'OFFER');
    expect(offer['src'], peers['A']);
    expect(offer['dst'], peers['B']);

    a.engine.closeConnection();
    await waitFor(() => b.saw('peer_closed'), reason: 'the partner to see the close');

    await a.close();
    await b.close();
    await server.close();
  });

  test('a taken id is retried, then replaced, and a missing partner is reported, all over the socket', () async {
    final server = await LocalPeerServer.start();
    final rtc = LoopbackRtc();
    final now = DateTime.now().millisecondsSinceEpoch;
    final key = keyFromBase64(fixture['keyBase64'] as String);
    final holder = await EngineSide.open('H', 'love-taken000000', key, endpoints: throughServer(server, rtc), clock: FakePeerClock(now));
    await holder.init();

    final clock = FakePeerClock(now);
    final late = await EngineSide.open('L', 'love-taken000000', key, endpoints: throughServer(server, rtc), clock: clock);
    String? opened;
    final pending = late.engine.init(key, 'love-taken000000').then((id) => opened = id);
    await waitFor(() => server.connections.length == 2, reason: 'the second connection');
    await waitFor(() => late.engine.peer?.destroyed ?? false, reason: 'the taken id');
    clock.advance(const Duration(milliseconds: 1200));
    await waitFor(() => server.connections.length == 3, reason: 'the retry with the same id');
    expect(server.connections[2].queryParameters['id'], 'love-taken000000');
    await pending.timeout(const Duration(seconds: 10));
    expect(opened, isNot('love-taken000000'));
    expect(opened, startsWith('love-'));
    expect(server.clients.keys, containsAll(['love-taken000000', opened]));

    await late.engine.connectToPartner('love-nobody00000');
    await waitFor(() => late.saw('peer-unavailable'), reason: 'the missing partner');
    expect(late.last('peer-unavailable')!.error, 'Cannot find their phone. Ask them to open Our Space and leave it on screen.');

    await holder.close();
    await late.close();
    await server.close();
  });

  test('losing the server is reported and the phone comes back with the same id', () async {
    final server = await LocalPeerServer.start();
    final rtc = LoopbackRtc();
    final key = keyFromBase64(fixture['keyBase64'] as String);
    final phone = await EngineSide.open(
      'P',
      peers['A']!,
      key,
      endpoints: throughServer(server, rtc),
      clock: FakePeerClock(DateTime.now().millisecondsSinceEpoch),
    );
    await phone.init();
    expect(phone.statuses.where((s) => s.code == 'peer_ready'), hasLength(1));

    await server.dropAll();
    await waitFor(() => phone.saw('network'), reason: 'the network error');
    expect(phone.last('network')!.error, 'Trouble with the connection. Check your internet and try again.');
    await waitFor(() => phone.statuses.where((s) => s.code == 'peer_ready').length == 2, reason: 'the reconnect');
    expect(server.connections.last.queryParameters['id'], peers['A']);
    expect(phone.engine.peer!.open, isTrue);

    await phone.close();
    await server.close();
  });
}
