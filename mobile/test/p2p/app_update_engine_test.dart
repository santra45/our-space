import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine/crypto/aes_gcm.dart';
import 'package:our_space_mobile/core/engine/crypto/base64.dart';
import 'package:our_space_mobile/core/engine/crypto/envelope.dart';
import 'package:our_space_mobile/core/engine/p2p/peer_sync_engine.dart';

import '../support/fake_app_update.dart' show randomApk;
import 'support/engine_harness.dart';
import 'support/fake_clock.dart';
import 'support/fake_peer.dart';
import 'support/solo.dart';

int warnings(EngineSide side) => side.statuses.where((s) => s.warning != null || s.error != null).length;

Map<String, Object?> piece(List<int> sealed) => {'protocol': appPieceProtocolId, 'payload': Uint8List.fromList(sealed)};

void main() {
  test('an update note rides sealed, and a piece rides sealed as raw bytes, both only once the phones trust each other',
      () async {
    final key = VaultKey.fromBits(randomBytes(32));
    final clock = FakePeerClock();
    final network = FakeNetwork();
    final a = await EngineSide.open('A', 'love-updaaaaaaaaaaa', key, endpoints: network.create, clock: clock);
    final b = await EngineSide.open('B', 'love-updbbbbbbbbbbb', key, endpoints: network.create, clock: clock);
    final notes = <Object?>[];
    final pieces = <Uint8List>[];
    b.engine.addAppUpdateListener(notes.add);
    b.engine.addAppPieceListener(pieces.add);
    final big = randomApk(300 * 1024, seed: 3);
    final small = randomApk(900, seed: 4);

    expect(await a.engine.sendAppUpdate({'k': 'hello', 'code': 2450, 'serves': true}), isFalse);
    expect(await a.engine.sendAppPiece(small), isFalse);

    await a.init();
    await b.init();
    await a.engine.connectToPartner(b.peerId);
    await waitFor(
      () => a.engine.isAuthorized && b.engine.isAuthorized && !a.engine.isSyncing && !b.engine.isSyncing,
      reason: 'the two phones to pair',
    );
    await settle();
    final quietA = warnings(a);
    final quietB = warnings(b);

    expect(await a.engine.sendAppUpdate({'k': 'hello', 'code': 2450, 'serves': true}), isTrue);
    await waitFor(() => notes.isNotEmpty, reason: 'the note');
    expect(notes.single, {'k': 'hello', 'code': 2450, 'serves': true});

    expect(await a.engine.sendAppPiece(small), isTrue);
    expect(await a.engine.sendAppPiece(big), isTrue);
    await waitFor(() => pieces.length == 2, reason: 'both pieces');
    expect(pieces[0], small);
    expect(pieces[1], big);

    final wire = (a.engine.activeConnection! as FakeLink).sent.last as Map;
    expect(wire['protocol'], appPieceProtocolId);
    final sealed = wire['payload'] as Uint8List;
    expect(sealed.length, big.length + ivLengthBytes + gcmTagLengthBytes);
    expect(sealed.sublist(ivLengthBytes, ivLengthBytes + 64), isNot(big.sublist(0, 64)));
    expect(decryptBlob(sealed, key), big);

    expect(await a.engine.sendAppPiece(Uint8List(0)), isFalse);
    expect(await a.engine.sendAppPiece(Uint8List(maxAppPieceBytes + 1)), isFalse);
    expect(await a.engine.sendAppUpdate({'k': 'pad', 'pad': 'x' * maxAppUpdateChars}), isFalse);

    await settle();
    expect(warnings(a), quietA);
    expect(warnings(b), quietB);
    expect(a.engine.isAuthorized && b.engine.isAuthorized, isTrue);

    a.engine.closeConnection();
    await waitFor(() => b.saw('peer_closed'), reason: 'the partner to notice');
    expect(await a.engine.sendAppPiece(small), isFalse);
    expect(await a.engine.sendAppUpdate({'k': 'hello', 'code': 2450, 'serves': true}), isFalse);

    await a.close();
    await b.close();
  });

  test('a piece before the handshake, under the wrong key, or of the wrong shape is dropped without a fuss', () async {
    final solo = await Solo.open();
    final pieces = <Uint8List>[];
    final notes = <Object?>[];
    solo.side.engine.addAppPieceListener(pieces.add);
    solo.side.engine.addAppUpdateListener(notes.add);
    await solo.init();
    final link = await solo.accept(partnerId);
    final plain = randomApk(1000, seed: 5);

    link.receive(piece(encryptBlob(plain, solo.key)));
    await solo.deliver(link, {'type': 'APP_UPDATE', 'event': {'k': 'hello', 'code': 2450}});
    await settle();
    expect(pieces, isEmpty);
    expect(notes, isEmpty);
    expect(solo.side.engine.isAuthorized, isFalse);

    await solo.deliver(link, {'type': 'CHALLENGE', 'nonce': 'n' * 24});
    final counter = solo.lastSent(link, 'CHALLENGE_RESPONSE')['counterNonce'] as String;
    await solo.deliver(link, {'type': 'CHALLENGE_ACK', 'echo': counter});
    await waitFor(() => solo.side.engine.isAuthorized, reason: 'authorization');
    await settle();
    final before = warnings(solo.side);

    link.receive(piece(encryptBlob(plain, VaultKey.fromBits(randomBytes(32)))));
    link.receive(piece([1, 2, 3]));
    link.receive({'protocol': appPieceProtocolId, 'payload': 'not bytes'});
    link.receive({'protocol': appPieceProtocolId});
    for (final odd in <Object?>['text', 7, null, const ['a']]) {
      await solo.deliver(link, {'type': 'APP_UPDATE', 'event': odd});
    }
    await settle();
    expect(pieces, isEmpty);
    expect(notes, isEmpty);
    expect(warnings(solo.side), before);
    expect(solo.side.engine.isAuthorized, isTrue);

    link.receive(piece(encryptBlob(plain, solo.key)));
    await solo.deliver(link, {'type': 'APP_UPDATE', 'event': {'k': 'hello', 'code': 2450}});
    await settle();
    expect(pieces.single, plain);
    expect(notes.single, {'k': 'hello', 'code': 2450});
    expect(warnings(solo.side), before);
    await solo.close();
  });
}
