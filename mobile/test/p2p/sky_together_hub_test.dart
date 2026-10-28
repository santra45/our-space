import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';

import 'peer_hub_test.dart' show Phone, pairedPhones;
import 'support/engine_harness.dart';
import 'support/fake_peer.dart';

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
}
