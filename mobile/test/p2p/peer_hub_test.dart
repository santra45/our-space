import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/core/engine/p2p/peer_hub.dart';

import '../support/harness.dart';
import 'support/engine_harness.dart';
import 'support/fake_peer.dart';
import 'support/solo.dart' show seal;

const String passphrase = 'correct horse battery staple 2026';

class Phone {
  Phone._(this.space, this.notices, this.subscription);

  static Future<Phone> open(FakeNetwork network) async {
    final dir = Directory.systemTemp.createTempSync('our_space_p2p_');
    final space = await OurSpace.open(
      databaseFactory: testDatabaseFactory(),
      databasePath: '${dir.path}${Platform.pathSeparator}space.sqlite',
      useEnvironmentMailbox: false,
      autoSync: false,
      peerToPeer: true,
      peerEndpoints: network.create,
    );
    final notices = <SyncNotice>[];
    final subscription = space.sync.notices.listen(notices.add);
    return Phone._(space, notices, subscription);
  }

  final OurSpace space;
  final List<SyncNotice> notices;
  final StreamSubscription<SyncNotice> subscription;

  PeerSyncHub get hub => space.peer;

  List<String> get texts => [for (final n in notices) n.text];

  Future<void> close() async {
    await subscription.cancel();
    await space.close();
  }
}

Future<(Phone, Phone)> pairedPhones(FakeNetwork network) async {
  final a = await Phone.open(network);
  final b = await Phone.open(network);
  expect((await a.space.vault.create(passphrase: passphrase, coupleNames: 'Ash & Bee', iterations: 1000)).ok, isTrue);
  await waitFor(() => a.hub.myPeerId != null, reason: 'the first phone to reach the server');
  final link = a.space.vault.buildInviteLink()!;
  final invite = parseInvite(link)!;
  expect(invite.partnerPeerId, a.hub.myPeerId);

  b.hub.acceptInvite(invite);
  final joined = await b.space.vault.joinWithSalt(
    passphrase: passphrase,
    salt: invite.salt!,
    startDate: invite.startDate,
    coupleNames: invite.coupleNames,
    iterations: 1000,
  );
  expect(joined.ok, isTrue);
  await waitFor(() => b.hub.pendingInvite != null, reason: 'the invite to wait for a yes');
  return (a, b);
}

void main() {
  test('an invite waits for a yes, then the phones pair, sync, share settings and love bursts', () async {
    final network = FakeNetwork();
    final (a, b) = await pairedPhones(network);

    final pending = b.hub.pendingInvite!;
    expect(pending.peerId, a.hub.myPeerId);
    expect(pending.fromLink, isTrue);
    expect(b.hub.partnerId, a.hub.myPeerId);
    expect(b.hub.linkState, PeerLinkState.disconnected);

    final states = <PeerLinkState>[];
    final sub = b.hub.linkStates.listen(states.add);

    b.hub.confirmPendingInvite();
    await waitFor(() => a.hub.isAuthorized && b.hub.isAuthorized, reason: 'pairing');
    await waitFor(() => !a.space.sync.peer!.engine.isSyncing && !b.hub.engine.isSyncing, reason: 'the first sync');

    expect(b.hub.pendingInvite, isNull);
    expect(states, containsAllInOrder([PeerLinkState.connecting, PeerLinkState.connected]));
    expect(states.last, isIn([PeerLinkState.authorised, PeerLinkState.syncing]));
    expect(a.hub.partnerId, b.hub.myPeerId);
    expect(a.space.store.settings.getItem(pairedPartnerKey), b.hub.myPeerId);
    expect(b.space.store.settings.getItem(trustedPartnerKey), a.hub.myPeerId);
    expect(b.hub.lastConnectedAt, isNotNull);
    expect(b.hub.syncError, isNull);
    expect(b.hub.isRouteUnknown, isTrue);
    expect(b.space.sync.peerAuthorized, isTrue);

    await waitFor(() => b.space.vault.config?.coupleNames == 'Ash & Bee', reason: 'the couple names to arrive');
    expect(b.space.vault.config!.updatedAt, a.space.vault.config!.updatedAt);

    await a.space.milestones.add(title: 'First trip', date: '2024-05-01');
    await waitFor(() => b.texts.any((t) => t.startsWith('Synced 1 new item(s) from')), reason: 'the live milestone');
    final milestones = await b.space.milestones.list();
    expect(milestones.map((m) => m.title), contains('First trip'));

    expect(await a.space.sync.sendLoveBurst(), isTrue);
    await waitFor(() => a.texts.contains('Love burst sent to your partner! 💕'), reason: 'the sent notice');
    await waitFor(() => b.notices.any((n) => n.kind == SyncNoticeKind.loveBurst), reason: 'the love burst');
    expect(b.notices.lastWhere((n) => n.kind == SyncNoticeKind.loveBurst).text, 'your partner sent you a love burst! 💕');

    expect((await a.space.vault.updateSettings(coupleNames: 'Ash & Bee forever')).ok, isTrue);
    await waitFor(() => b.space.vault.config?.coupleNames == 'Ash & Bee forever', reason: 'the renamed couple');

    final link = a.hub.engine.activeConnection!;
    link.send(seal({'type': 'SYNC_ERROR', 'code': 'odd', 'message': 'No such sync session'}, a.space.vault.key!));
    await waitFor(() => b.notices.any((n) => n.text == 'Your partner reported a sync problem.'), reason: 'the plain problem notice');
    expect(b.texts.where((t) => t.contains('No such sync session')), isEmpty);
    expect(b.notices.lastWhere((n) => n.text == 'Your partner reported a sync problem.').kind, SyncNoticeKind.warning);

    b.space.vault.lock();
    expect(b.hub.myPeerId, isNull);
    expect(b.hub.linkState, PeerLinkState.disconnected);
    expect(b.hub.engine.cryptoKey, isNull);
    await waitFor(() => !a.hub.isAuthorized, reason: 'the other phone to notice');
    expect(a.hub.status.code, 'peer_closed');

    await sub.cancel();
    await a.close();
    await b.close();
  });

  test('a trusted partner is dialled once, 800 ms after unlocking', () async {
    final network = FakeNetwork();
    final (a, b) = await pairedPhones(network);
    b.hub.confirmPendingInvite();
    await waitFor(() => b.hub.isAuthorized, reason: 'pairing');
    await waitFor(() => !b.hub.engine.isSyncing && !a.hub.engine.isSyncing, reason: 'the first sync');

    b.space.vault.lock();
    await waitFor(() => !a.hub.isAuthorized, reason: 'the partner to drop');
    await Future<void>.delayed(const Duration(milliseconds: 2100));
    final endpointsBefore = network.created.length;
    expect((await b.space.vault.unlock(passphrase)).ok, isTrue);
    await waitFor(() => network.created.length > endpointsBefore, reason: 'a fresh server connection');
    final endpoint = network.created.last;
    expect(endpoint.requestedId, b.hub.engine.myPeerId ?? endpoint.requestedId);

    await waitFor(() => b.hub.isAuthorized, reason: 'the automatic reconnect');
    expect(endpoint.dialed, hasLength(1));
    expect(b.hub.pendingInvite, isNull);

    await a.close();
    await b.close();
  });

  test('pairing codes are checked, invites can be declined and partners unpaired, in the web words', () async {
    final network = FakeNetwork();
    final (a, b) = await pairedPhones(network);

    b.hub.connectToPartner('no!');
    expect(b.hub.syncError!.code, 'bad_peer_id');
    expect(b.hub.syncError!.text, '“no!” is not a usable pairing code. Ask your partner to re-share their code or invite link.');
    b.hub.clearSyncError();
    b.hub.connectToPartner(b.hub.myPeerId!);
    expect(b.hub.syncError!.code, 'bad_peer_id');
    b.hub.clearSyncError();

    b.hub.declinePendingInvite();
    expect(b.hub.pendingInvite, isNull);
    expect(b.hub.partnerId, isNull);
    expect(b.space.store.settings.getItem(pairedPartnerKey), isNull);

    b.hub.connectToPartner('  ${a.hub.myPeerId}  ');
    await waitFor(() => b.hub.isAuthorized, reason: 'pairing by code');
    expect(b.hub.partnerId, a.hub.myPeerId);

    b.hub.unpairPartner();
    expect(b.hub.partnerId, isNull);
    expect(b.space.store.settings.getItem(trustedPartnerKey), isNull);
    await waitFor(() => !b.hub.isAuthorized && !a.hub.isAuthorized, reason: 'the unpair to close the link');

    expect(await b.hub.syncNow(), isFalse);
    const couldNot = 'Could not start a sync right now. Check the connection and try again.';
    await waitFor(() => b.texts.contains(couldNot), reason: 'the sync warning');
    expect(b.notices.lastWhere((n) => n.text == couldNot).kind, SyncNoticeKind.warning);

    await a.close();
    await b.close();
  });

  test('a locked or untouched phone never reaches the server', () async {
    final network = FakeNetwork();
    final phone = await Phone.open(network);
    expect(network.created, isEmpty);
    expect(phone.hub.started, isFalse);
    expect(phone.space.sync.peerAuthorized, isFalse);
    await phone.close();

    final dir = Directory.systemTemp.createTempSync('our_space_p2p_off_');
    final quiet = await OurSpace.open(
      databaseFactory: testDatabaseFactory(),
      databasePath: '${dir.path}${Platform.pathSeparator}space.sqlite',
      useEnvironmentMailbox: false,
      autoSync: false,
      peerEndpoints: network.create,
    );
    expect((await quiet.vault.create(passphrase: passphrase, iterations: 1000)).ok, isTrue);
    await settle();
    expect(network.created, isEmpty);
    quiet.peer.start();
    await waitFor(() => quiet.peer.myPeerId != null, reason: 'a manual start');
    expect(quiet.peer.myPeerId, quiet.device.peerId);
    await quiet.close();
  });

  test('settings from the partner with a bad date are skipped with a warning, older ones quietly', () async {
    final network = FakeNetwork();
    final (a, b) = await pairedPhones(network);
    b.hub.confirmPendingInvite();
    await waitFor(() => b.hub.isAuthorized && a.hub.isAuthorized, reason: 'pairing');
    await waitFor(() => b.space.vault.config?.coupleNames == 'Ash & Bee', reason: 'the first settings');

    final key = a.space.vault.key!;
    final link = a.hub.engine.activeConnection!;
    link.send(seal({
      'type': 'SYNC_CONFIG',
      'config': {'coupleNames': 'Bad date', 'startDate': '2024-13-40', 'updatedAt': 1},
    }, key));
    await waitFor(() => b.texts.contains('We skipped a settings change from your partner — the date did not look right.'),
        reason: 'the bad date warning');
    expect(b.space.vault.config!.coupleNames, 'Ash & Bee');

    final before = b.space.vault.config!.updatedAt;
    link.send(seal({
      'type': 'SYNC_CONFIG',
      'config': {'coupleNames': 'Older', 'startDate': '2024-01-01', 'updatedAt': before - 1},
    }, key));
    link.send(seal({
      'type': 'SYNC_CONFIG',
      'config': {'coupleNames': 'From the future', 'startDate': '2024-01-01', 'updatedAt': DateTime.now().millisecondsSinceEpoch + 3 * 86400000},
    }, key));
    await settle(60);
    expect(b.space.vault.config!.coupleNames, 'Ash & Bee');
    expect(b.space.vault.config!.updatedAt, before);

    await a.close();
    await b.close();
  });
}
