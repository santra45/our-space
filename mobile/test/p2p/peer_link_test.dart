import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/core/engine/p2p/peer_hub.dart' show pairedPartnerKey;
import 'package:our_space_mobile/presentation/screens/sync/peer_link.dart';

import '../support/harness.dart';
import 'support/engine_harness.dart';
import 'support/fake_peer.dart';

const String passphrase = 'correct horse battery staple 2026';

Future<OurSpace> openPhone(FakeNetwork network) {
  final dir = Directory.systemTemp.createTempSync('our_space_link_');
  return OurSpace.open(
    databaseFactory: testDatabaseFactory(),
    databasePath: '${dir.path}${Platform.pathSeparator}space.sqlite',
    useEnvironmentMailbox: false,
    autoSync: false,
    peerToPeer: true,
    peerEndpoints: network.create,
  );
}

Future<void> settleSpace(OurSpace space) =>
    waitFor(() => space.identity.status != IdentityStatus.loading, reason: 'the people to load');

void main() {
  test('the Sync Hub link mirrors the phone-to-phone hub, and an invite remembered after joining waits for a yes',
      () async {
    final network = FakeNetwork();
    final a = await openPhone(network);
    final b = await openPhone(network);
    expect((await a.vault.create(passphrase: passphrase, coupleNames: 'Ash & Bee', iterations: 1000)).ok, isTrue);
    await waitFor(() => a.peer.myPeerId != null, reason: 'the first phone to reach the server');
    final invite = parseInvite(a.vault.buildInviteLink())!;

    final link = HubPeerLink(b.peer);
    var heard = 0;
    link.addListener(() => heard++);
    expect(link.state.myPeerId, isNull);
    expect(link.state.authorized, isFalse);
    expect(link.state.pendingInvite, isNull);

    final joined = await b.vault.joinWithSalt(
      passphrase: passphrase,
      salt: invite.salt!,
      startDate: invite.startDate,
      coupleNames: invite.coupleNames,
      iterations: 1000,
    );
    expect(joined.ok, isTrue);
    b.peer.acceptInvite(invite);
    expect(b.store.settings.getItem(pairedPartnerKey), a.peer.myPeerId);

    await waitFor(() => link.state.pendingInvite != null, reason: 'the invite to wait for a yes');
    expect(heard, greaterThan(0));
    expect(link.state.pendingInvite!.peerId, a.peer.myPeerId);
    expect(link.state.pendingInvite!.fromLink, isTrue);
    expect(link.state.partnerId, a.peer.myPeerId);
    expect(link.state.myPeerId, b.peer.myPeerId);
    expect(link.state.lastConnectedAt, isNull);

    link.confirmInvite();
    await waitFor(() => link.state.authorized && a.peer.isAuthorized, reason: 'pairing');
    await waitFor(() => !link.state.syncing && !b.peer.engine.isSyncing, reason: 'the first sync');
    final paired = link.state;
    expect(paired.pendingInvite, isNull);
    expect(paired.handshaking, isFalse);
    expect(paired.connecting, isFalse);
    expect(paired.route, isNull);
    expect(paired.error, isNull);
    expect(paired.lastConnectedAt, isNotNull);

    link.connect('no!');
    expect(link.state.error!.code, 'bad_peer_id');
    expect(link.state.error!.text,
        '“no!” is not a usable pairing code. Ask your partner to re-share their code or invite link.');
    link.clearError();
    expect(link.state.error, isNull);

    final arrived = <SyncNotice>[];
    final listening = a.sync.notices.listen(arrived.add);
    expect(await b.sync.sendLoveBurst(), isTrue);
    await waitFor(() => arrived.any((n) => n.kind == SyncNoticeKind.loveBurst), reason: 'the love burst');
    await listening.cancel();

    link.unpair();
    expect(link.state.partnerId, isNull);
    await waitFor(() => !link.state.authorized, reason: 'the unpair to close the link');

    link.dispose();
    final before = heard;
    b.peer.clearSyncError();
    expect(heard, before);

    await settleSpace(a);
    await settleSpace(b);
    await a.close();
    await b.close();
  });

  test('an invite remembered once the phone is already online is offered straight away', () async {
    final network = FakeNetwork();
    final phone = await openPhone(network);
    expect((await phone.vault.create(passphrase: passphrase, iterations: 1000)).ok, isTrue);
    await waitFor(() => phone.peer.myPeerId != null, reason: 'the phone to reach the server');
    expect(phone.peer.pendingInvite, isNull);

    phone.peer.acceptInvite(parseInvite('love-someone-new')!);
    expect(phone.peer.pendingInvite!.peerId, 'love-someone-new');
    expect(phone.peer.pendingInvite!.fromLink, isTrue);
    expect(phone.peer.partnerId, 'love-someone-new');

    phone.peer.declinePendingInvite();
    expect(phone.peer.pendingInvite, isNull);
    expect(phone.peer.partnerId, isNull);
    await waitFor(() => phone.store.settings.getItem(pairedPartnerKey) == null, reason: 'the declined phone to be forgotten');

    phone.peer.acceptInvite(parseInvite(phone.peer.myPeerId)!);
    expect(phone.peer.pendingInvite, isNull);

    await settleSpace(phone);
    await phone.close();
  });
}
