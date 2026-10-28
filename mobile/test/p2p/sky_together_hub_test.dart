import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';

import 'peer_hub_test.dart' show Phone, pairedPhones;
import 'support/engine_harness.dart';
import 'support/fake_peer.dart';
import 'support/solo.dart' show openSealed;

Future<void> waitUntil(Future<bool> Function() done, {required String reason}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (!await done()) {
    if (DateTime.now().isAfter(deadline)) throw StateError('Timed out waiting for $reason');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

SkyDrawing oneStar(String owner, String id) =>
    SkyDrawing(stars: [SkyDrawnStar(id: id, x: 0.5, y: 0.5, by: owner, at: 1760000000000, gen: 0)]);

Future<(Phone, Phone)> linkedPhones(FakeNetwork network) async {
  final (a, b) = await pairedPhones(network);
  b.hub.confirmPendingInvite();
  await waitFor(() => a.hub.isAuthorized && b.hub.isAuthorized, reason: 'pairing');
  await waitFor(() => !a.hub.engine.isSyncing && !b.hub.engine.isSyncing, reason: 'the first sync');
  return (a, b);
}

void main() {
  test('two phones on the live link see each other here, and lose it in the background or when the link drops',
      () async {
    final network = FakeNetwork();
    final (a, b) = await linkedPhones(network);
    final skyA = a.hub.skyTogether;
    final skyB = b.hub.skyTogether;

    await waitFor(() => skyA.partnerHere && skyB.partnerHere, reason: 'both to be here');
    expect(skyA.linked && skyB.linked, isTrue);
    expect(skyA.partnerSpeaksSky && skyB.partnerSpeaksSky, isTrue);
    expect(skyA.partnerOwner, skyB.owner);
    expect(skyB.partnerOwner, skyA.owner);
    expect(skyA.owner, a.space.identity.myOwnerId ?? a.space.device.deviceId);
    expect({skyA.isLeader, skyB.isLeader}, {true, false});
    await waitFor(() => skyA.samples.isNotEmpty && skyB.samples.isNotEmpty, reason: 'the shared clock');
    expect((skyA.sharedNow() - skyB.sharedNow()).abs(), lessThan(1000));

    final heardByB = <SkyTogetherEvent>[];
    final sub = skyB.events.listen(heardByB.add);
    expect(await skyA.sendOpen('sky-hub-1', at: skyA.sharedNow() + 400), isTrue);
    await waitFor(() => heardByB.any((e) => e is SkyOpenEvent), reason: 'the door to open on the other phone');
    expect(heardByB.whereType<SkyOpenEvent>().single.drawing, 'sky-hub-1');

    b.space.sync.onBackground();
    expect(skyB.here, isFalse);
    await waitFor(() => !skyA.partnerHere, reason: 'the goodbye');
    expect(skyA.linked, isTrue);
    b.space.sync.onForeground();
    await waitFor(() => skyA.partnerHere, reason: 'the return');

    expect(a.texts.where((t) => t.startsWith('Synced')), isEmpty);
    expect(b.notices.where((n) => n.kind == SyncNoticeKind.warning), isEmpty);

    a.hub.disconnect();
    await waitFor(() => !skyB.linked && !skyB.partnerHere && !skyA.linked, reason: 'the link to drop');
    expect(skyA.partnerSpeaksSky, isFalse);
    expect(await skyA.sendOpen('sky-hub-1', at: 1), isFalse);

    await sub.cancel();
    await a.close();
    await b.close();
  });

  test('a locked phone is not here, and locking the vault ends presence on the other side', () async {
    final network = FakeNetwork();
    final (a, b) = await linkedPhones(network);
    await waitFor(() => a.hub.skyTogether.partnerHere, reason: 'presence');

    b.space.vault.lock();
    expect(b.hub.skyTogether.linked, isFalse);
    await waitFor(() => !a.hub.skyTogether.partnerHere && !a.hub.skyTogether.linked, reason: 'the lock to end presence');

    await a.close();
    await b.close();
  });

  test('a drawing kept on one phone reaches the other live and quietly, but never goes live to a partner who cannot draw',
      () async {
    final network = FakeNetwork();
    final (a, b) = await linkedPhones(network);
    final skyA = a.hub.skyTogether;
    await waitFor(() => skyA.partnerSpeaksSky && b.hub.skyTogether.partnerSpeaksSky, reason: 'both to speak sky');
    final key = a.space.vault.key!;

    await a.space.skyDrawings.saveProgress(key, id: 'sky-live', drawing: oneStar(skyA.owner!, 's-1'));
    await waitUntil(() async => await b.space.skyDrawings.find(b.space.vault.key, 'sky-live') != null,
        reason: 'the drawing to arrive live');
    expect((await b.space.skyDrawings.find(b.space.vault.key, 'sky-live'))!.drawing.visibleStars.single.id, 's-1');
    await settle(40);
    expect(b.texts.where((t) => t.startsWith('Synced')), isEmpty);
    expect(b.notices.where((n) => n.kind == SyncNoticeKind.warning), isEmpty);

    b.hub.skyTogether.dispose();
    a.hub.disconnect();
    await waitFor(() => !a.hub.isAuthorized && !b.hub.isAuthorized, reason: 'the link to drop');
    a.hub.reconnectToPartner();
    await waitFor(() => a.hub.isAuthorized && b.hub.isAuthorized, reason: 'the link to come back');
    await waitFor(() => !a.hub.engine.isSyncing && !b.hub.engine.isSyncing, reason: 'the sync after it');
    await settle(40);
    expect(skyA.linked, isTrue);
    expect(skyA.partnerSpeaksSky, isFalse);

    final link = a.hub.engine.activeConnection! as FakeLink;
    final before = link.sent.length;
    await a.space.skyDrawings.saveProgress(key, id: 'sky-quiet', drawing: oneStar(skyA.owner!, 's-2'));
    await a.space.milestones.add(title: 'Still live', date: '2024-05-01');
    await waitUntil(() async => (await b.space.milestones.list()).any((m) => m.title == 'Still live'),
        reason: 'the milestone to arrive live');
    final live = [
      for (final envelope in link.sent.skip(before))
        if (openSealed(envelope, key) case {'type': 'LIVE_RECORD_BROADCAST', 'record': {'table': final String table}}) table,
    ];
    expect(live, contains(milestonesTable));
    expect(live, isNot(contains(skyDrawingsTable)));
    expect(await b.space.skyDrawings.find(b.space.vault.key, 'sky-quiet'), isNull);
    expect(a.notices.where((n) => n.kind == SyncNoticeKind.warning), isEmpty);
    expect(b.notices.where((n) => n.kind == SyncNoticeKind.warning), isEmpty);

    await a.close();
    await b.close();
  });
}
