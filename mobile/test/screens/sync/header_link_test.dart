import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/main.dart';
import 'package:our_space_mobile/presentation/home_shell.dart';
import 'package:our_space_mobile/presentation/screens/sync/peer_link.dart';
import 'package:our_space_mobile/presentation/vault_gate.dart';
import 'package:our_space_mobile/presentation/widgets/our_widgets.dart';
import 'package:provider/provider.dart';

import '../../widgets/harness.dart' show recordHaptics, recordedHaptics;
import 'hub_harness.dart';

SyncPillState pill(WidgetTester tester) => tester.widget<SyncStatusPill>(find.byType(SyncStatusPill)).state;

Future<void> pumpHeader(WidgetTester tester, OurSpace space, FakePeerLink peer) async {
  await tester.pumpWidget(OurSpaceApp(
    openSpace: () async => space,
    gate: (context, shell) => ChangeNotifierProvider<PeerLink>.value(value: peer, child: VaultGate(shell: shell)),
    shell: const HomeShell(pageBuilder: blankTab, particles: false),
  ));
  await tester.pump();
  await untilFound(tester, find.byType(SyncStatusPill));
}

void main() {
  setUp(recordHaptics);

  test('the header pill follows the web order: hiccup, route, checking, pairing, then tap to pair', () {
    expect(syncPillFor(PeerLinkView.offline), SyncPillState.idle);
    expect(syncPillFor(const PeerLinkView(connecting: true)), SyncPillState.pairing);
    expect(syncPillFor(const PeerLinkView(handshaking: true, connecting: true)), SyncPillState.checking);
    expect(syncPillFor(const PeerLinkView(authorized: true)), SyncPillState.connected);
    expect(syncPillFor(const PeerLinkView(authorized: true, route: PeerRoute.direct)), SyncPillState.direct);
    expect(syncPillFor(const PeerLinkView(authorized: true, route: PeerRoute.relayed)), SyncPillState.relayed);
    expect(
      syncPillFor(const PeerLinkView(authorized: true, route: PeerRoute.direct, error: PeerLinkError(text: 'Oops'))),
      SyncPillState.error,
    );
  });

  testWidgets('the header shows the live link, its hiccups and asks before connecting to a new phone', (tester) async {
    calm(tester);
    final space = await openUnlockedSpace(tester);
    await real(tester, () => space.identity.createCouple(myName: 'Sam', partnerName: 'Alex'));
    final peer = FakePeerLink();
    await pumpHeader(tester, space, peer);

    expect(pill(tester), SyncPillState.idle);
    expect(find.text('Just for us 💕'), findsOneWidget);

    peer.state = const PeerLinkView(partnerId: 'love-partnerphone', connecting: true);
    await tester.pump();
    expect(pill(tester), SyncPillState.pairing);

    peer.state = const PeerLinkView(partnerId: 'love-partnerphone', handshaking: true);
    await tester.pump();
    expect(pill(tester), SyncPillState.checking);

    peer.state = const PeerLinkView(partnerId: 'love-partnerphone', authorized: true, route: PeerRoute.direct);
    await tester.pump();
    expect(pill(tester), SyncPillState.direct);
    expect(find.text('Alex active now 💕'), findsOneWidget);

    peer.state = const PeerLinkView(
      partnerId: 'love-partnerphone',
      error: PeerLinkError(text: 'We could not reach love-partnerphone. Check they have Our Space open, then try again.'),
    );
    await tester.pump();
    expect(pill(tester), SyncPillState.error);
    expect(find.text('We could not reach love-partnerphone. Check they have Our Space open, then try again.'),
        findsOneWidget);
    expect(find.text('Open the Pair & Sync hub'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(HeaderSyncErrorBanner), matching: find.byType(LucideIcon)).last);
    await tester.pump();
    expect(peer.calls, ['clearError']);

    peer.state = const PeerLinkView(pendingInvite: PendingPeerInvite(peerId: 'love-newphone1', fromLink: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Connect to this device?'), findsOneWidget);
    expect(find.text('A link is asking to connect to the phone below.'), findsOneWidget);
    expect(find.text('love-newphone1'), findsOneWidget);
    expect(find.text('Only connect if you know who sent you this link.'), findsOneWidget);
    recordedHaptics.clear();
    await tester.tap(find.text('Connect'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(peer.calls.last, 'confirmInvite');
    expect(recordedHaptics, [HapticKind.tap]);
    expect(find.text('Connect to this device?'), findsNothing);

    peer.state = const PeerLinkView(pendingInvite: PendingPeerInvite(peerId: 'love-savedphone', fromLink: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('There is a saved phone here we have not connected to before.'), findsOneWidget);
    await tester.tap(find.text('Not now'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(peer.calls.last, 'declineInvite');
    expect(find.text('Connect to this device?'), findsNothing);

    peer.state = PeerLinkView.offline;
    await tester.pump();
    await settle(tester);
  });
}
