import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine/crypto/base64.dart';
import 'package:our_space_mobile/core/engine/crypto/envelope.dart';
import 'package:our_space_mobile/core/engine/p2p/peer_endpoint.dart';
import 'package:our_space_mobile/core/engine/p2p/peer_framing.dart';
import 'package:our_space_mobile/core/engine/storage/tables.dart';

import '../support/harness.dart';
import 'support/engine_harness.dart';
import 'support/fake_clock.dart';
import 'support/fake_peer.dart';
import 'support/fixtures.dart';

class WebPeer {
  WebPeer._(this.process) {
    process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(_line);
    process.stderr.transform(utf8.decoder).listen(stderr.write);
  }

  static Future<WebPeer?> start() async {
    try {
      final process = await Process.start('node', ['test/p2p/tool/web_peer_bridge.mjs']);
      final peer = WebPeer._(process);
      unawaited(process.exitCode.then((_) {
        if (!peer._hello.isCompleted) peer._hello.complete(false);
      }));
      final hello = await peer._hello.future.timeout(const Duration(seconds: 20), onTimeout: () => false);
      if (!hello) {
        process.kill();
        return null;
      }
      return peer;
    } on ProcessException {
      return null;
    }
  }

  final Process process;
  final Completer<bool> _hello = Completer<bool>();
  final List<Map<String, Object?>> statuses = [];
  final List<Map<String, Object?>> events = [];
  final List<String> errors = [];
  final List<Uint8List> frames = [];
  bool ready = false;
  bool closed = false;
  Map<String, Object?>? lastDump;
  void Function(Uint8List frame)? onFrame;
  void Function()? onClosed;

  void _line(String line) {
    final message = (jsonDecode(line) as Map).cast<String, Object?>();
    if (message['hello'] == true && !_hello.isCompleted) _hello.complete(true);
    if (message['ready'] == true) ready = true;
    if (message['status'] is Map) statuses.add((message['status'] as Map).cast<String, Object?>());
    if (message['event'] is String) events.add(message);
    if (message['error'] is String) errors.add(message['error'] as String);
    if (message['dump'] is Map) lastDump = (message['dump'] as Map).cast<String, Object?>();
    if (message['closed'] == true) {
      closed = true;
      onClosed?.call();
    }
    final frame = message['frame'];
    if (frame is String) {
      final bytes = Uint8List.fromList(base64.decode(frame));
      frames.add(bytes);
      onFrame?.call(bytes);
    }
  }

  void send(Map<String, Object?> command) => process.stdin.writeln(jsonEncode(command));

  bool saw(String code) => statuses.any((s) => s['code'] == code);

  int count(String code) => statuses.where((s) => s['code'] == code).length;

  Future<Map<String, Object?>> dump() async {
    lastDump = null;
    send({'cmd': 'dump'});
    await waitFor(() => lastDump != null, reason: 'the web dump');
    return lastDump!;
  }

  Future<void> exit() async {
    send({'cmd': 'exit'});
    await process.exitCode.timeout(const Duration(seconds: 10), onTimeout: () {
      process.kill();
      return -1;
    });
  }
}

class BridgeLink implements PeerLink {
  BridgeLink(this.peer, this.web) {
    web.onFrame = _receive;
    web.onClosed = () => close(fromRemote: true);
  }

  @override
  final String peer;
  final WebPeer web;
  final PeerFraming _framing = PeerFraming();
  final List<Uint8List> sentFrames = [];
  bool _open = false;

  @override
  PeerRoute? get route => null;
  @override
  void Function()? onOpen;
  @override
  void Function(Object? data)? onData;
  @override
  void Function()? onClose;
  @override
  void Function(Object error)? onError;

  @override
  bool get open => _open;

  void openNow() {
    _open = true;
    onOpen?.call();
  }

  void _receive(Uint8List frame) {
    if (!_open) return;
    final result = _framing.decode(frame);
    if (result.kind == PeerFrameKind.message) onData?.call(result.data);
    if (result.kind == PeerFrameKind.close) close();
  }

  @override
  void send(Object? data) {
    if (!_open) return;
    for (final frame in _framing.encode(data)) {
      sentFrames.add(frame);
      web.send({'cmd': 'frame', 'frame': base64.encode(frame)});
    }
  }

  @override
  void close({bool fromRemote = false}) {
    if (!_open) return;
    _open = false;
    onClose?.call();
    if (!fromRemote) web.send({'cmd': 'remote-close'});
  }
}

Future<void> live(String phoneRole) async {
  final web = await WebPeer.start();
  if (web == null) {
    markTestSkipped('node or the web node_modules are not available here');
    return;
  }
  final fixture = readP2pFixture('web_peer_session.json');
  final peers = (fixture['peers'] as Map).cast<String, String>();
  final configs = (fixture['configs'] as Map).cast<String, Object?>();
  final start = (fixture['start'] as Map).cast<String, Object?>();
  final webRole = phoneRole == 'A' ? 'B' : 'A';
  final key = keyFromBase64(fixture['keyBase64'] as String);

  final clock = FakePeerClock(DateTime.now().millisecondsSinceEpoch);
  final network = FakeNetwork()..deliverDials = false;
  final phone = await EngineSide.open(phoneRole, peers[phoneRole]!, key, endpoints: network.create, clock: clock);
  await phone.seed((start[phoneRole] as Map).cast<String, Object?>());
  phone.engine.addStatusListener((status) {
    if (status.state == 'authorized') phone.engine.syncVaultConfig((configs[phoneRole] as Map).cast<String, Object?>());
  });
  await phone.init();

  web.send({
    'cmd': 'init',
    'role': phoneRole == 'A' ? 'responder' : 'initiator',
    'key': fixture['keyBase64'],
    'myId': peers[webRole],
    'partnerId': peers[phoneRole],
    'seed': start[webRole],
    'config': configs[webRole],
  });
  await waitFor(() => web.ready, reason: 'the web side to start');

  final link = BridgeLink(peers[webRole]!, web);
  if (phoneRole == 'B') {
    network.created.single.incoming(link);
  } else {
    network.created.single.connector = (_) => link;
    await phone.engine.connectToPartner(peers['B']);
  }
  web.send({'cmd': 'open'});
  link.openNow();

  await waitFor(
    () => phone.saw('sync_complete') && web.saw('sync_complete') && !phone.engine.isSyncing && web.count('sync_started') <= web.count('sync_complete'),
    reason: 'both sides to finish the first sync',
    timeout: const Duration(seconds: 60),
  );
  await settle(50);
  expect(web.errors, isEmpty);
  expect(phone.engine.isAuthorized, isTrue);
  expect(web.saw('authorized'), isTrue);

  final webDump = await web.dump();
  expect(canonicalJson(await phone.dump()), canonicalJson(webDump));
  expect((webDump[memoriesTable] as List).single, isA<Map>());
  expect(((webDump[memoriesTable] as List).single as Map)['imageBlobBase64'], isA<String>());

  expect(phone.configs.single.coupleNames, (configs[webRole] as Map)['coupleNames']);
  expect(web.events.firstWhere((e) => e['event'] == 'config-synced')['coupleNames'], (configs[phoneRole] as Map)['coupleNames']);

  final photo = randomBytes(60000);
  final mine = await phone.store.putEncrypted(
    memoriesTable,
    {'id': 'mem-from-$phoneRole', 'caption': 'Sent live', 'imageBlob': photo, 'updatedAt': clock.now()},
    key,
  );
  expect(await phone.engine.broadcastLiveRecord(memoriesTable, mine), isTrue);
  await waitFor(() => web.events.any((e) => e['event'] == 'data-updated' && e['single'] == true), reason: 'the web side to take the live photo');
  expect(link.sentFrames.where((f) => f.length > 16000).length, greaterThanOrEqualTo(5));

  final letter = encryptRecord(
    {'id': 'let-from-web', 'title': 'From the website', 'content': 'Hi love', 'updatedAt': clock.now()},
    key,
    table: lettersTable,
  );
  web.send({'cmd': 'broadcast', 'table': lettersTable, 'row': rowToFixture(letter)});
  await waitFor(() => phone.updates.any((u) => u.single && u.table == lettersTable), reason: 'the web letter to land');
  expect((await phone.store.getDecrypted(lettersTable, 'let-from-web', key))!['title'], 'From the website');

  web.send({'cmd': 'sync'});
  await waitFor(() => web.count('sync_complete') >= 2, reason: 'a manual web sync');
  await settle(50);
  expect(canonicalJson(await phone.dump()), canonicalJson(await web.dump()));

  link.close();
  await waitFor(() => web.saw('peer_closed'), reason: 'the web side to see the phone leave');
  expect(web.errors, isEmpty);
  await phone.close();
  await web.exit();
}

void main() {
  test('the real peerSync.js dials the phone, and both end with the same memories', () => live('B'), timeout: const Timeout(Duration(minutes: 2)));

  test('the phone dials the real peerSync.js, and both end with the same memories', () => live('A'), timeout: const Timeout(Duration(minutes: 2)));
}
