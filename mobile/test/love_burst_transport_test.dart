import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';

import 'p2p/support/engine_harness.dart';
import 'p2p/support/fake_peer.dart';
import 'support/fake_mailbox_worker.dart';
import 'support/harness.dart';

const String passphrase = 'correct horse battery staple 2026';
const String token = 'love-burst-mailbox-token';

Future<OurSpace> openPhone({FakeMailboxWorker? worker, FakeNetwork? network}) {
  final dir = Directory.systemTemp.createTempSync('our_space_burst_');
  return OurSpace.open(
    databaseFactory: testDatabaseFactory(),
    databasePath: '${dir.path}${Platform.pathSeparator}space.sqlite',
    useEnvironmentMailbox: false,
    mailboxConfig: worker == null
        ? null
        : const MailboxConfig(url: 'https://mailbox.test', token: token, origin: 'https://sameskytonight.vercel.app'),
    httpClient: worker,
    autoSync: false,
    peerToPeer: network != null,
    peerEndpoints: network?.create,
  );
}

Future<void> settled(OurSpace space) =>
    waitFor(() => space.identity.status != IdentityStatus.loading, reason: 'the people to load');

void main() {
  test('a love burst waits in the mailbox and lands when the partner next checks', () async {
    final worker = FakeMailboxWorker(token: token);
    final ash = await openPhone(worker: worker);
    final bee = await openPhone(worker: worker);
    expect((await ash.vault.create(passphrase: passphrase, coupleNames: 'Ash & Bee', iterations: 1000)).ok, isTrue);
    expect(await ash.identity.createCouple(myName: 'Ash', partnerName: 'Bee'), isTrue);
    await ash.sync.syncNow();

    expect((await bee.vault.joinWithSalt(passphrase: passphrase, salt: ash.vault.salt!, iterations: 1000)).ok, isTrue);
    await bee.sync.syncNow();
    await waitFor(() => bee.identity.status == IdentityStatus.unclaimed, reason: 'the names to arrive');
    final mine = bee.identity.everyone.firstWhere((person) => person.name == 'Bee');
    expect(await bee.identity.claimPerson(mine.personId), isTrue);

    final arrived = <SyncNotice>[];
    final listening = bee.sync.notices.listen(arrived.add);
    final bursts = <int>[];
    final counting = bee.sync.loveBurstArrivals.listen(bursts.add);

    expect(await ash.sync.sendLoveBurst(), isTrue);
    expect(ash.sync.lastNotice, 'Saved 💕 Bee will see it the moment you two connect.');
    await ash.sync.syncNow();
    await bee.sync.syncNow();

    await waitFor(() => arrived.any((n) => n.kind == SyncNoticeKind.loveBurst), reason: 'the love burst');
    expect(arrived.lastWhere((n) => n.kind == SyncNoticeKind.loveBurst).text,
        'Ash sent you a love burst while you were away 💕');
    expect(bursts, [1]);

    await listening.cancel();
    await counting.cancel();
    await settled(ash);
    await settled(bee);
    await ash.close();
    await bee.close();
  });

  test('a love burst flies straight across a live phone-to-phone link', () async {
    final network = FakeNetwork();
    final ash = await openPhone(network: network);
    final bee = await openPhone(network: network);
    expect((await ash.vault.create(passphrase: passphrase, coupleNames: 'Ash & Bee', iterations: 1000)).ok, isTrue);
    await waitFor(() => ash.peer.myPeerId != null, reason: 'the first phone to reach the server');
    final invite = parseInvite(ash.vault.buildInviteLink())!;
    expect((await bee.vault.joinWithSalt(passphrase: passphrase, salt: invite.salt!, iterations: 1000)).ok, isTrue);
    bee.peer.acceptInvite(invite);
    await waitFor(() => bee.peer.pendingInvite != null, reason: 'the invite to wait for a yes');
    bee.peer.confirmPendingInvite();
    await waitFor(() => ash.peer.isAuthorized && bee.peer.isAuthorized, reason: 'pairing');
    await waitFor(() => !ash.peer.engine.isSyncing && !bee.peer.engine.isSyncing, reason: 'the first sync');

    final arrived = <SyncNotice>[];
    final listening = bee.sync.notices.listen(arrived.add);
    expect(await ash.sync.sendLoveBurst(), isTrue);
    expect(ash.sync.lastNotice, 'Love burst sent to your partner! 💕');
    await waitFor(() => arrived.any((n) => n.kind == SyncNoticeKind.loveBurst), reason: 'the love burst');
    expect(arrived.lastWhere((n) => n.kind == SyncNoticeKind.loveBurst).text, 'your partner sent you a love burst! 💕');

    await listening.cancel();
    await settled(ash);
    await settled(bee);
    await ash.close();
    await bee.close();
  });
}
