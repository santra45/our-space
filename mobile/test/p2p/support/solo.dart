import 'dart:convert';

import 'package:our_space_mobile/core/engine/crypto/aes_gcm.dart';
import 'package:our_space_mobile/core/engine/crypto/base64.dart';
import 'package:our_space_mobile/core/engine/crypto/envelope.dart';

import 'engine_harness.dart';
import 'fake_clock.dart';
import 'fake_peer.dart';

const String partnerId = 'love-partner00000000';
const String myId = 'love-phone000000000';

Map<String, Object?> seal(Map<String, Object?> message, VaultKey key) => {
      'protocol': 'SWEETHEART_V2',
      'payload': encryptJson(message, key).toJson(),
    };

Map<String, Object?> openSealed(Object? envelope, VaultKey key) {
  final map = (envelope as Map).cast<String, Object?>();
  final payload = (map['payload'] as Map).cast<String, Object?>();
  return (jsonDecode(decryptText(payload['ciphertext'] as String, payload['iv'] as String, key)) as Map)
      .cast<String, Object?>();
}

class Solo {
  Solo._(this.side, this.network, this.clock);

  static Future<Solo> open({
    String peerId = myId,
    VaultKey? key,
    Map<String, String> settings = const {},
    bool autoOpenServer = true,
  }) async {
    final clock = FakePeerClock();
    final network = FakeNetwork()
      ..deliverDials = false
      ..autoOpenServer = autoOpenServer;
    final side = await EngineSide.open(
      'phone',
      peerId,
      key ?? VaultKey.fromBits(randomBytes(32)),
      endpoints: network.create,
      clock: clock,
      settings: settings,
    );
    return Solo._(side, network, clock);
  }

  final EngineSide side;
  final FakeNetwork network;
  final FakePeerClock clock;

  VaultKey get key => side.key;

  FakeEndpoint get endpoint => network.created.last;

  Future<void> init() async {
    await side.init();
  }

  Future<FakeLink> accept(String from, {bool open = true, FakeRoute? route}) async {
    final link = FakeLink(from, owner: side.peerId, route: route);
    endpoint.incoming(link);
    if (open) link.openNow();
    await settle();
    return link;
  }

  Future<FakeLink> dial(String to, {bool open = true}) async {
    await side.engine.connectToPartner(to);
    final link = endpoint.dialed.last;
    if (open) link.openNow();
    await settle();
    return link;
  }

  Future<void> deliver(FakeLink link, Map<String, Object?> message, {VaultKey? as}) async {
    link.receive(seal(message, as ?? key));
    await settle();
  }

  List<Map<String, Object?>> sent(FakeLink link) => [for (final envelope in link.sent) openSealed(envelope, key)];

  List<String> sentTypes(FakeLink link) => [for (final m in sent(link)) m['type'] as String];

  Map<String, Object?> lastSent(FakeLink link, String type) => sent(link).lastWhere((m) => m['type'] == type);

  Future<FakeLink> authorizedWith(String from, {FakeRoute? route}) async {
    await init();
    final link = await accept(from, route: route);
    await deliver(link, {'type': 'CHALLENGE', 'nonce': 'n' * 24});
    final counter = lastSent(link, 'CHALLENGE_RESPONSE')['counterNonce'] as String;
    await deliver(link, {'type': 'CHALLENGE_ACK', 'echo': counter});
    await waitFor(() => side.engine.isAuthorized && !side.engine.isSyncing || sentTypes(link).contains('SYNC_MANIFEST'),
        reason: 'authorization');
    await settle();
    return link;
  }

  Future<void> advance(int ms) async {
    clock.advance(Duration(milliseconds: ms));
    await settle();
  }

  Future<void> close() => side.close();
}
