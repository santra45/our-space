import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine/crypto/aes_gcm.dart';
import 'package:our_space_mobile/core/engine/crypto/base64.dart';
import 'package:our_space_mobile/core/engine/p2p/peer_sync_engine.dart';

import 'support/engine_harness.dart';
import 'support/fake_clock.dart';
import 'support/fake_peer.dart';
import 'support/solo.dart';

const Map<String, Object?> presence = {
  'v': 1,
  'k': 'presence',
  'here': true,
  'night': true,
  'owner': 'owner-aaaa1111',
  'tag': 'tagaaaa1',
  't': 1760000000000,
};

int warnings(EngineSide side) => side.statuses.where((s) => s.warning != null || s.error != null).length;

void main() {
  test('SKY_TOGETHER is on the allowlist next to the existing types, which stay as they were', () {
    expect(skyTogetherMessageType, 'SKY_TOGETHER');
    expect(allowedPeerMessageTypes, {
      'CHALLENGE',
      'CHALLENGE_RESPONSE',
      'CHALLENGE_ACK',
      'SYNC_MANIFEST',
      'SYNC_REQUEST_RECORDS',
      'SYNC_RECORDS_BATCH',
      'SYNC_COMPLETE',
      'SYNC_ERROR',
      'LIVE_RECORD_BROADCAST',
      'SYNC_CONFIG',
      'PING',
      'PONG',
      'SKY_TOGETHER',
    });
  });

  test('a SKY_TOGETHER event goes sealed from one app engine to the other and nothing else notices', () async {
    final key = VaultKey.fromBits(randomBytes(32));
    final clock = FakePeerClock();
    final network = FakeNetwork();
    final a = await EngineSide.open('A', 'love-skyaaaaaaaaaaa', key, endpoints: network.create, clock: clock);
    final b = await EngineSide.open('B', 'love-skybbbbbbbbbbb', key, endpoints: network.create, clock: clock);
    final heardByA = <Object?>[];
    final heardByB = <Object?>[];
    a.engine.addSkyTogetherListener(heardByA.add);
    b.engine.addSkyTogetherListener(heardByB.add);

    expect(await a.engine.sendSkyTogether(presence), isFalse);

    await a.init();
    await b.init();
    await a.engine.connectToPartner(b.peerId);
    await waitFor(
      () => a.engine.isAuthorized && b.engine.isAuthorized && !a.engine.isSyncing && !b.engine.isSyncing,
      reason: 'the two phones to pair',
    );
    await settle();
    expect(heardByB, isEmpty);
    final quietA = warnings(a);
    final quietB = warnings(b);
    final updatesB = b.updates.length;

    expect(await a.engine.sendSkyTogether(presence), isTrue);
    await waitFor(() => heardByB.isNotEmpty, reason: 'the event to land');
    expect(heardByB.single, presence);

    final sealed = (a.engine.activeConnection! as FakeLink).sent.last;
    final onTheWire = jsonEncode(sealed);
    expect(onTheWire.contains('presence'), isFalse);
    expect(onTheWire.contains('owner-aaaa1111'), isFalse);
    expect(openSealed(sealed, key), {'type': 'SKY_TOGETHER', 'event': presence});

    expect(await b.engine.sendSkyTogether({'v': 1, 'k': 'cursor', 'x': 0.5, 'y': 0.25, 'down': true}), isTrue);
    await waitFor(() => heardByA.isNotEmpty, reason: 'the reply to land');
    expect(heardByA.single, {'v': 1, 'k': 'cursor', 'x': 0.5, 'y': 0.25, 'down': true});

    await settle();
    expect(warnings(a), quietA);
    expect(warnings(b), quietB);
    expect(b.updates.length, updatesB);
    expect(a.engine.isAuthorized && b.engine.isAuthorized, isTrue);

    a.engine.closeConnection();
    await waitFor(() => b.saw('peer_closed'), reason: 'the partner to notice');
    expect(await a.engine.sendSkyTogether(presence), isFalse);
    expect(await b.engine.sendSkyTogether(presence), isFalse);

    await a.close();
    await b.close();
  });

  test('an engine drops a live type that is not on its allowlist, the way an older build drops SKY_TOGETHER', () async {
    final solo = await Solo.open();
    final heard = <Object?>[];
    solo.side.engine.addSkyTogetherListener(heard.add);
    final link = await solo.authorizedWith(partnerId);
    final before = warnings(solo.side);
    final sentBefore = link.sent.length;

    await solo.deliver(link, {'type': 'SKY_TOGETHER_NEXT', 'event': presence});
    await solo.deliver(link, {'type': 'sky_together', 'event': presence});
    await solo.deliver(link, {'event': presence});

    expect(heard, isEmpty);
    expect(warnings(solo.side), before);
    expect(link.sent.length, sentBefore);
    expect(solo.side.engine.isAuthorized, isTrue);

    await solo.deliver(link, {'type': 'SKY_TOGETHER', 'event': presence});
    expect(heard.single, presence);
    expect(warnings(solo.side), before);
    expect(link.sent.length, sentBefore);
    await solo.close();
  });

  test('a SKY_TOGETHER event before the handshake, or one that is not an object, is dropped quietly', () async {
    final solo = await Solo.open();
    final heard = <Object?>[];
    solo.side.engine.addSkyTogetherListener(heard.add);
    await solo.init();
    final link = await solo.accept(partnerId);

    await solo.deliver(link, {'type': 'SKY_TOGETHER', 'event': presence});
    expect(heard, isEmpty);
    expect(solo.side.engine.isAuthorized, isFalse);
    expect(await solo.side.engine.sendSkyTogether(presence), isFalse);
    expect(solo.sentTypes(link), isNot(contains('SKY_TOGETHER')));

    await solo.deliver(link, {'type': 'CHALLENGE', 'nonce': 'n' * 24});
    final counter = solo.lastSent(link, 'CHALLENGE_RESPONSE')['counterNonce'] as String;
    await solo.deliver(link, {'type': 'CHALLENGE_ACK', 'echo': counter});
    await waitFor(() => solo.side.engine.isAuthorized, reason: 'authorization');
    final before = warnings(solo.side);

    for (final odd in <Object?>['text', 7, null, true, const ['a', 'b']]) {
      await solo.deliver(link, {'type': 'SKY_TOGETHER', 'event': odd});
    }
    expect(heard, isEmpty);
    expect(warnings(solo.side), before);
    expect(solo.side.engine.isAuthorized, isTrue);
    await solo.close();
  });

  test('sending is refused when the event is too big, and a listener that throws harms nobody', () async {
    final solo = await Solo.open();
    final heard = <Object?>[];
    solo.side.engine.addSkyTogetherListener((_) => throw StateError('boom'));
    solo.side.engine.addSkyTogetherListener(heard.add);
    final link = await solo.authorizedWith(partnerId);
    final before = warnings(solo.side);
    final sentBefore = link.sent.length;

    expect(await solo.side.engine.sendSkyTogether({'v': 1, 'k': 'pad', 'pad': 'x' * maxSkyTogetherChars}), isFalse);
    expect(link.sent.length, sentBefore);

    expect(await solo.side.engine.sendSkyTogether(presence), isTrue);
    expect(solo.lastSent(link, 'SKY_TOGETHER')['event'], presence);

    await solo.deliver(link, {'type': 'SKY_TOGETHER', 'event': presence});
    expect(heard.single, presence);
    expect(warnings(solo.side), before);

    void listener(Object? event) => heard.add('again');
    solo.side.engine.addSkyTogetherListener(listener);
    solo.side.engine.removeSkyTogetherListener(listener);
    await solo.deliver(link, {'type': 'SKY_TOGETHER', 'event': presence});
    expect(heard, [presence, presence]);
    await solo.close();
  });
}
