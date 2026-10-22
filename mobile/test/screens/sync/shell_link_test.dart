import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/main.dart';
import 'package:our_space_mobile/presentation/app_shell.dart';
import 'package:our_space_mobile/presentation/home_shell.dart';
import 'package:our_space_mobile/presentation/screens/settings/settings_page.dart';
import 'package:our_space_mobile/presentation/screens/sync/peer_link.dart';
import 'package:our_space_mobile/presentation/vault_gate.dart';
import 'package:our_space_mobile/presentation/widgets/app_haptics.dart';
import 'package:provider/provider.dart';

import '../../widgets/harness.dart' show recordHaptics, recordedHaptics;
import 'hub_harness.dart';

Widget presencePage(BuildContext context, SkyTab tab) {
  final presence = SkyShellScope.of(context).presence;
  return Center(child: Text('presence:${presence.label ?? 'none'}:${presence.sentence}'));
}

Future<void> pumpShell(WidgetTester tester, OurSpace space, FakePeerLink peer) async {
  await tester.pumpWidget(
    OurSpaceApp(
      openSpace: () async => space,
      gate: (context, shell) => ChangeNotifierProvider<PeerLink>.value(
        value: peer,
        child: VaultGate(shell: shell),
      ),
      shell: const HomeShell(pageBuilder: presencePage),
    ),
  );
  await tester.pump();
  await untilFound(tester, find.byKey(ShellKeys.dock));
}

Finder labelled(String label) =>
    find.byWidgetPredicate((widget) => widget is Semantics && widget.properties.label == label);

Finder noticeText(String text) => find.descendant(of: find.byKey(ShellKeys.notices), matching: find.text(text));

void main() {
  setUp(recordHaptics);

  test('presence reads here now when linked, then the last time they were seen', () {
    expect(const PartnerPresence.here(partnerName: 'Alex').label, 'here now');
    expect(const PartnerPresence.here(partnerName: 'Alex').sentence, 'Alex is here now');
    expect(const PartnerPresence.seen(partnerName: 'Alex', lastSeen: '5m ago').label, 'seen 5m ago');
    expect(const PartnerPresence.seen(partnerName: 'Alex', lastSeen: 'Yesterday').label, 'seen yesterday');
    expect(const PartnerPresence.seen(lastSeen: 'Just now').label, 'seen just now');
    expect(const PartnerPresence.seen(partnerName: 'Alex', lastSeen: 'Jun 14').sentence, 'Alex was here on Jun 14');
    expect(const PartnerPresence.seen(partnerName: 'Alex', lastSeen: 'Jun 14').label, 'seen on Jun 14');
    expect(const PartnerPresence.seen(partnerName: 'Alex', lastSeen: '2h ago').sentence, 'Alex was here 2h ago');
    expect(const PartnerPresence.unknown().label, isNull);
    expect(const PartnerPresence.unknown().sentence, 'Just the two of you');
  });

  testWidgets('the shell shows who is here, the link hiccups, and asks before connecting a new phone', (tester) async {
    calm(tester);
    final space = await openUnlockedSpace(tester);
    await real(tester, () => space.identity.createCouple(myName: 'Sam', partnerName: 'Alex'));
    final peer = FakePeerLink();
    await pumpShell(tester, space, peer);

    expect(find.text('presence:none:Just the two of you'), findsOneWidget);

    peer.state = const PeerLinkView(partnerId: 'love-partnerphone', connecting: true);
    await tester.pump();
    expect(find.text('presence:none:Just the two of you'), findsOneWidget);

    peer.state = const PeerLinkView(partnerId: 'love-partnerphone', authorized: true, route: PeerRoute.direct);
    await tester.pump();
    expect(find.text('presence:here now:Alex is here now'), findsOneWidget);

    peer.state = const PeerLinkView(
      partnerId: 'love-partnerphone',
      error: PeerLinkError(
        text: 'We could not reach love-partnerphone. Check they have Our Space open, then try again.',
      ),
    );
    await tester.pump();
    expect(
      noticeText('We could not reach love-partnerphone. Check they have Our Space open, then try again.'),
      findsOneWidget,
    );
    expect(noticeText(ShellCopy.openSettings), findsOneWidget);
    await tester.tap(find.descendant(of: find.byKey(ShellKeys.notices), matching: labelled(ShellCopy.dismiss)));
    await tester.pump();
    expect(peer.calls, ['clearError']);

    await tester.tap(noticeText(ShellCopy.openSettings));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(SettingsPage), findsOneWidget);
    await tester.tap(labelled('Back'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(SettingsPage), findsNothing);

    peer.state = const PeerLinkView(pendingInvite: PendingPeerInvite(peerId: 'love-newphone1', fromLink: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(JoinRequestCopy.title), findsOneWidget);
    expect(find.text(JoinRequestCopy.fromLink), findsOneWidget);
    expect(find.text('love-newphone1'), findsOneWidget);
    expect(find.text(JoinRequestCopy.caution), findsOneWidget);
    recordedHaptics.clear();
    await tester.tap(find.text(JoinRequestCopy.connect));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(peer.calls.last, 'confirmInvite');
    expect(recordedHaptics, contains(HapticKind.tap));
    expect(find.text(JoinRequestCopy.title), findsNothing);

    peer.state = const PeerLinkView(pendingInvite: PendingPeerInvite(peerId: 'love-savedphone', fromLink: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(JoinRequestCopy.saved), findsOneWidget);
    await tester.tap(find.text(JoinRequestCopy.notNow));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(peer.calls.last, 'declineInvite');
    expect(find.text(JoinRequestCopy.title), findsNothing);

    peer.state = PeerLinkView.offline;
    await tester.pump();
    await settle(tester);
  });

  testWidgets('the partner last seen time reaches the pages through the shell scope', (tester) async {
    calm(tester);
    final space = await openUnlockedSpace(tester);
    await real(tester, () => space.identity.createCouple(myName: 'Sam', partnerName: 'Alex'));
    final peer = FakePeerLink();
    await pumpShell(tester, space, peer);
    final identity = tester.element(find.byType(HomeShell)).read<IdentityController>();
    final now = DateTime.now().millisecondsSinceEpoch;
    final presence = partnerPresenceFor(identity, now: now);
    expect(presence.kind, identity.partnerLastActive == null ? PresenceKind.unknown : PresenceKind.seen);
    expect(partnerPresenceFor(identity, now: now, together: true).isHere, isTrue);
    expect(partnerPresenceFor(identity, now: now, together: true).partnerName, 'Alex');
    await settle(tester);
  });
}
