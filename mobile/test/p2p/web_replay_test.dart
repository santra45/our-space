import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine/crypto/aes_gcm.dart';
import 'package:our_space_mobile/core/engine/crypto/envelope.dart';
import 'package:our_space_mobile/core/engine/p2p/binary_pack.dart';
import 'package:our_space_mobile/core/engine/p2p/peer_framing.dart';
import 'package:our_space_mobile/core/engine/storage/tables.dart';

import 'support/engine_harness.dart';
import 'support/fake_clock.dart';
import 'support/fake_peer.dart';
import 'support/fixtures.dart';

class Entry {
  Entry(this.from, this.bytes, this.close);
  final String from;
  final Uint8List? bytes;
  final bool close;
}

List<Entry> readTranscript(Map<String, Object?> fixture) => [
      for (final raw in (fixture['transcript'] as List).cast<Map>())
        Entry(
          raw['from'] as String,
          raw['frame'] is String ? Uint8List.fromList(base64.decode(raw['frame'] as String)) : null,
          raw['close'] == true,
        ),
    ];

class Decoded {
  Decoded(this.json, this.message, this.frameLengths);
  final String json;
  final Map<String, Object?> message;
  final List<int> frameLengths;
}

List<Decoded> decodeFrames(Iterable<Uint8List> frames, VaultKey key) {
  final framing = PeerFraming();
  final out = <Decoded>[];
  var lengths = <int>[];
  for (final frame in frames) {
    lengths.add(frame.length);
    final result = framing.decode(frame);
    if (result.kind != PeerFrameKind.message) continue;
    final envelope = (result.data as Map).cast<String, Object?>();
    expect(envelope.keys.toList(), ['protocol', 'payload']);
    expect(envelope['protocol'], 'SWEETHEART_V2');
    final payload = (envelope['payload'] as Map).cast<String, Object?>();
    expect(payload.keys.toList(), ['ciphertext', 'iv']);
    final json = decryptText(payload['ciphertext'] as String, payload['iv'] as String, key);
    out.add(Decoded(json, (jsonDecode(json) as Map).cast<String, Object?>(), lengths));
    lengths = <int>[];
  }
  return out;
}

String withoutClock(String json) => json.replaceAll(RegExp(r'"t":\d+'), '"t":0');

Map<int, List<String>> noncesFor(List<Decoded> messages) {
  final out = <int, List<String>>{16: [], 9: []};
  for (final decoded in messages) {
    final message = decoded.message;
    switch (message['type']) {
      case 'CHALLENGE':
        out[16]!.add(message['nonce'] as String);
      case 'CHALLENGE_RESPONSE':
        out[16]!.add(message['counterNonce'] as String);
      case 'SYNC_MANIFEST':
        out[9]!.add(message['sessionId'] as String);
    }
  }
  return out;
}

Future<void> replay(String role) async {
  final fixture = readP2pFixture('web_peer_session.json');
  final peers = (fixture['peers'] as Map).cast<String, String>();
  final configs = (fixture['configs'] as Map).cast<String, Object?>();
  final start = (fixture['start'] as Map).cast<String, Object?>();
  final end = (fixture['end'] as Map).cast<String, Object?>();
  final marks = (fixture['marks'] as Map).cast<String, Object?>();
  final key = keyFromBase64(fixture['keyBase64'] as String);
  final other = role == 'A' ? 'B' : 'A';
  final transcript = readTranscript(fixture);

  final webOurs = decodeFrames([for (final e in transcript) if (e.from == role && e.bytes != null) e.bytes!], key);
  final nonces = noncesFor(webOurs);

  final clock = FakePeerClock();
  final network = FakeNetwork()..deliverDials = false;
  final side = await EngineSide.open(
    role,
    peers[role]!,
    key,
    endpoints: network.create,
    clock: clock,
    nonce: (bytes) => nonces[bytes]!.removeAt(0),
  );
  await side.seed((start[role] as Map).cast<String, Object?>());
  side.engine.addStatusListener((status) {
    if (status.state == 'authorized') {
      side.engine.syncVaultConfig((configs[role] as Map).cast<String, Object?>());
    }
  });
  await side.init();

  late FakeLink link;
  if (role == 'B') {
    link = FakeLink(peers['A']!, owner: role);
    (network.created.single as FakeEndpoint).incoming(link);
  } else {
    await side.engine.connectToPartner(peers['B']);
    link = (network.created.single as FakeEndpoint).dialed.single;
  }
  link.openNow();

  final burst = ((end['A'] as Map)[loveBurstsTable] as List)
      .cast<Map<String, Object?>>()
      .firstWhere((row) => row['id'] == 'burst-device-a');
  final actions = <int, Future<void> Function()>{
    marks['afterSync'] as int: () async {
      await side.seed({
        loveBurstsTable: [burst],
      });
      await side.engine.broadcastLiveRecord(loveBurstsTable, await side.store.getRow(loveBurstsTable, 'burst-device-a'));
    },
    marks['afterBroadcast'] as int: () => side.engine.heartbeatTick(),
    marks['afterPing'] as int: () async {
      await side.engine.syncNow();
    },
    marks['afterManualSync'] as int: () async => side.engine.closeConnection(),
  };

  var ourBefore = 0;
  for (var i = 0; i < transcript.length; i++) {
    final entry = transcript[i];
    if (role == 'A' && actions.containsKey(i)) {
      final needed = ourBefore;
      await waitFor(() => link.frames.length >= needed, reason: 'our frames before mark $i');
      await settle();
      await actions[i]!();
    }
    if (entry.from == role) {
      if (entry.bytes != null) ourBefore++;
      continue;
    }
    final needed = ourBefore;
    await waitFor(() => link.frames.length >= needed, reason: 'our frame $needed before entry $i');
    if (entry.close) {
      link.close();
    } else {
      link.receiveFrame(entry.bytes!);
    }
    await settle(5);
  }
  await waitFor(() => link.frames.length >= ourBefore, reason: 'all our frames');
  await settle();

  final ours = decodeFrames(link.frames, key);
  expect(ours.length, webOurs.length);
  expect(
    ([for (final d in ours) withoutClock(d.json)]..sort()),
    ([for (final d in webOurs) withoutClock(d.json)]..sort()),
  );
  expect(
    ([for (final d in ours) d.frameLengths.join(',')]..sort()),
    ([for (final d in webOurs) d.frameLengths.join(',')]..sort()),
  );
  expect(link.frames.length, ourBefore);
  expect(canonicalJson(await side.dump()), canonicalJson(end[role]));
  expect(side.saw('authorized'), isTrue);
  expect(side.engine.isAuthorized, isFalse);
  expect(other, isNot(role));
  await side.close();
}

void main() {
  test('the phone answers a web dialer frame for frame and ends with the web partner\'s data', () => replay('B'));

  test('the phone dials a web partner frame for frame and ends with the web dialer\'s data', () => replay('A'));

  test('a web phone with another passphrase is refused the way the web refuses it', () async {
    final fixture = readP2pFixture('web_peer_mismatch.json');
    final keys = (fixture['keyBase64'] as Map).cast<String, String>();
    final peers = (fixture['peers'] as Map).cast<String, String>();
    final transcript = readTranscript(fixture);
    final webB = ((fixture['statuses'] as Map)['B'] as List).cast<Map>();

    final clock = FakePeerClock();
    final network = FakeNetwork()..deliverDials = false;
    final side = await EngineSide.open('B', peers['B']!, keyFromBase64(keys['B']!), endpoints: network.create, clock: clock);
    await side.init();
    final link = FakeLink(peers['A']!, owner: 'B');
    (network.created.single as FakeEndpoint).incoming(link);
    link.openNow();
    link.receiveFrame(transcript.firstWhere((e) => e.from == 'A' && e.bytes != null).bytes!);
    await settle();

    expect(link.closed, isTrue);
    expect(link.frames, isEmpty);
    final mismatch = side.last('passphrase_mismatch')!;
    final web = webB.firstWhere((s) => s['code'] == 'passphrase_mismatch');
    expect(mismatch.state, web['state']);
    expect(mismatch.error, web['error']);
    expect(side.codes.toList().sublist(side.codes.toList().indexOf('channel_open')),
        ['channel_open', 'peer_closed', 'passphrase_mismatch']);
    await side.close();
  });

  test('web frames unpack with the same BinaryPack shape the phone sends', () {
    final fixture = readP2pFixture('web_peer_session.json');
    final transcript = readTranscript(fixture);
    final first = binaryUnpack(transcript.first.bytes!) as Map;
    expect(first.keys.toList(), ['protocol', 'payload']);
    final chunk = transcript.map((e) => e.bytes).whereType<Uint8List>().map(binaryUnpack).whereType<Map>().firstWhere(
          (m) => m.containsKey('__peerData'),
        );
    expect(chunk.keys.toList(), ['__peerData', 'n', 'data', 'total']);
    expect((chunk['data'] as Uint8List).length, chunkedMtu);
  });
}
