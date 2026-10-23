import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/presentation/screens/settings/settings_page.dart';
import 'package:our_space_mobile/presentation/screens/sync/peer_link.dart';
import 'package:our_space_mobile/presentation/screens/sync/together_now.dart';
import 'package:our_space_mobile/presentation/widgets/app_haptics.dart';

import '../../support/fake_mailbox_worker.dart';
import '../../widgets/harness.dart' show recordHaptics, recordedHaptics;
import 'hub_harness.dart';

Finder inSheet(Finder finder) =>
    find.descendant(of: find.byType(TogetherNowSheet), matching: finder);

Future<void> openSheet(WidgetTester tester) => tapRow(tester, SettingsPage.connectionKey);

void main() {
  setUp(recordHaptics);

  test('the sentence follows the link, from waiting to together', () {
    final now = DateTime(2026, 10, 22, 12).millisecondsSinceEpoch;
    expect(togetherSentence(PeerLinkView.offline), TogetherNowCopy.notJoined);
    expect(togetherSentence(const PeerLinkView(partnerId: 'love-partnerphone')), TogetherNowCopy.waiting);
    expect(
      togetherSentence(PeerLinkView(partnerId: 'love-partnerphone', lastConnectedAt: now - 5 * 60000), now: now),
      'Last together 5m ago',
    );
    expect(
      togetherSentence(PeerLinkView(partnerId: 'love-partnerphone', lastConnectedAt: now - 30 * 3600000), now: now),
      'Last together yesterday',
    );
    expect(togetherSentence(const PeerLinkView(connecting: true)), TogetherNowCopy.reaching);
    expect(togetherSentence(const PeerLinkView(handshaking: true)), TogetherNowCopy.makingSure);
    expect(togetherSentence(const PeerLinkView(authorized: true)), TogetherNowCopy.together);
    expect(TogetherNowCopy.partnerPhone('your partner'), 'Your partner\'s phone');
    expect(TogetherNowCopy.partnerPhone(''), 'Their phone');
  });

  testWidgets('the link state drives the row and the details like the old hub did', (tester) async {
    calm(tester);
    final space = await openUnlockedSpace(tester);
    final now = DateTime.now().millisecondsSinceEpoch;
    final peer = FakePeerLink(
      const PeerLinkView(
        myPeerId: 'love-fromthelink',
        partnerId: 'love-partnerphone',
        authorized: true,
        route: PeerRoute.direct,
      ),
    );
    await openSettingsPage(tester, space, peer: peer);
    expect(find.text(TogetherNowCopy.together), findsOneWidget);

    await openSheet(tester);
    expect(inSheet(find.text(TogetherNowCopy.together)), findsOneWidget);
    expect(inSheet(find.text(TogetherNowCopy.howTitle)), findsOneWidget);
    expect(inSheet(find.text(TogetherNowCopy.direct)), findsOneWidget);
    expect(inSheet(find.text(TogetherNowCopy.hereNow)), findsOneWidget);
    expect(inSheet(find.text(TogetherNowCopy.rightNow)), findsOneWidget);
    expect(inSheet(find.text(TogetherNowCopy.theirCode)), findsOneWidget);
    expect(inSheet(find.text('love-partnerphone')), findsOneWidget);
    expect(inSheet(find.text(TogetherNowCopy.reachAgain)), findsNothing);

    await press(tester, inSheet(find.text(TogetherNowCopy.catchUp)));
    expect(peer.calls, ['syncNow']);

    peer.state = const PeerLinkView(partnerId: 'love-partnerphone', authorized: true, route: PeerRoute.relayed);
    await tester.pump();
    expect(inSheet(find.text(TogetherNowCopy.helper)), findsOneWidget);
    expect(inSheet(find.text(TogetherNowCopy.notSureBody)), findsNothing);

    peer.state = const PeerLinkView(partnerId: 'love-partnerphone', authorized: true, syncing: true);
    await tester.pump();
    expect(inSheet(find.text(TogetherNowCopy.notSure)), findsOneWidget);
    expect(inSheet(find.text(TogetherNowCopy.notSureBody)), findsOneWidget);
    expect(inSheet(find.text(TogetherNowCopy.catchingUp('your partner'))), findsOneWidget);

    peer.state = PeerLinkView(partnerId: 'love-partnerphone', connecting: true, lastConnectedAt: now - 5 * 60000);
    await tester.pump();
    expect(inSheet(find.text(TogetherNowCopy.reaching)), findsOneWidget);
    expect(inSheet(find.text('5m ago')), findsOneWidget);
    expect(inSheet(find.text(TogetherNowCopy.notHereYet)), findsOneWidget);
    expect(inSheet(find.text(TogetherNowCopy.howTitle)), findsNothing);
    await press(tester, inSheet(find.text(TogetherNowCopy.reachAgain)));
    expect(peer.calls.last, 'reconnect');

    await press(tester, inSheet(find.text(TogetherNowCopy.forget)));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(TogetherNowCopy.forgetTitle), findsOneWidget);
    expect(find.text(TogetherNowCopy.forgetBody), findsOneWidget);
    await press(tester, find.text(TogetherNowCopy.keep));
    await tester.pump(const Duration(milliseconds: 500));
    expect(peer.calls.last, 'reconnect');
    await press(tester, inSheet(find.text(TogetherNowCopy.forget)));
    await tester.pump(const Duration(milliseconds: 500));
    await press(tester, find.text(TogetherNowCopy.forgetConfirm));
    await tester.pump(const Duration(milliseconds: 500));
    expect(peer.calls.last, 'unpair');

    peer.state = const PeerLinkView(handshaking: true);
    await tester.pump();
    expect(inSheet(find.text(TogetherNowCopy.makingSure)), findsOneWidget);
    expect(inSheet(find.text(TogetherNowCopy.theirCode)), findsNothing);
    expect(inSheet(find.text(TogetherNowCopy.forget)), findsNothing);

    peer.state = const PeerLinkView(
      partnerId: 'love-partnerphone',
      error: PeerLinkError(text: 'Your passphrases do not match.', code: PeerLinkError.passphraseMismatch),
    );
    await tester.pump();
    expect(inSheet(find.text('Your passphrases do not match.')), findsOneWidget);
    expect(inSheet(find.text(TogetherNowCopy.mismatchHelp)), findsOneWidget);
    await press(tester, inSheet(find.text(TogetherNowCopy.tryAgain)));
    expect(peer.calls.last, 'reconnect');
    await press(tester, inSheet(find.text(TogetherNowCopy.dismiss)));
    expect(peer.calls.last, 'clearError');

    peer.state = const PeerLinkView(error: PeerLinkError(text: 'Lost them for a moment.'));
    await tester.pump();
    expect(inSheet(find.text(TogetherNowCopy.tryAgain)), findsNothing);
    expect(inSheet(find.text(TogetherNowCopy.mismatchHelp)), findsNothing);
    await closeTopModal(tester);
    expect(find.byType(TogetherNowSheet), findsNothing);
  });

  testWidgets('errors also show on the settings page with a way to try again', (tester) async {
    calm(tester);
    final space = await openUnlockedSpace(tester);
    final peer = FakePeerLink(
      const PeerLinkView(
        partnerId: 'love-partnerphone',
        error: PeerLinkError(text: 'Your passphrases do not match.', code: PeerLinkError.passphraseMismatch),
      ),
    );
    await openSettingsPage(tester, space, peer: peer);
    expect(find.text('Your passphrases do not match.'), findsOneWidget);
    expect(find.text(TogetherNowCopy.mismatchHelp), findsOneWidget);
    await press(tester, find.text(TogetherNowCopy.tryAgain));
    expect(peer.calls, ['reconnect']);
    await press(tester, find.text(TogetherNowCopy.dismiss));
    expect(peer.calls.last, 'clearError');
    expect(recordedHaptics, contains(HapticKind.tap));
  });

  testWidgets('shows when they were last here and the little warnings from the engine', (tester) async {
    calm(tester);
    final space = await openUnlockedSpace(tester);
    await real(tester, () => space.identity.createCouple(myName: 'Sam', partnerName: 'Alex'));
    await openSettingsPage(tester, space);
    await openSheet(tester);
    expect(inSheet(find.text('Alex\'s phone')), findsOneWidget);
    expect(inSheet(find.text(TogetherNowCopy.notHereYet)), findsOneWidget);
    expect(inSheet(find.text(TogetherNowCopy.notYet)), findsOneWidget);

    space.mailbox.onWarning!('clock_skew', 'Your phone clock looks a little off.');
    await tester.pump();
    expect(find.text('Your phone clock looks a little off.'), findsNWidgets(2));
    await tester.pump(const Duration(seconds: 8));
    expect(find.text('Your phone clock looks a little off.'), findsNothing);
  });

  testWidgets('the apart panel checks for things on demand', (tester) async {
    calm(tester);
    final worker = FakeMailboxWorker(token: 'test-token');
    final space = await openUnlockedSpace(
      tester,
      mailbox: const MailboxConfig(
        url: 'https://mailbox.test',
        token: 'test-token',
        origin: 'https://sameskytonight.vercel.app',
      ),
      client: worker,
    );
    await real(tester, () => space.identity.createCouple(myName: 'Sam', partnerName: 'Alex'));
    await openSettingsPage(tester, space);
    await openSheet(tester);
    expect(find.text(TogetherNowCopy.apartReady), findsOneWidget);
    expect(find.text(TogetherNowCopy.apartBody), findsOneWidget);
    expect(space.sync.status.state, MailboxRunState.idle);

    await press(tester, find.text(TogetherNowCopy.checkNow));
    await until(tester, () => space.sync.status.state == MailboxRunState.ok);
    await settle(tester);
    expect(space.sync.status.reason, 'manual');
    expect(worker.calls, isNotEmpty);
    expect(find.text(TogetherNowCopy.apartReady), findsOneWidget);
    expect(recordedHaptics, contains(HapticKind.tap));
  });

  testWidgets('the apart panel says when it is checking or could not check', (tester) async {
    calm(tester);
    var checks = 0;
    Future<void> show(MailboxRunState state) => tester.pumpWidget(
          MaterialApp(home: Scaffold(body: ApartPanel(state: state, onCheck: () => checks++))),
        );

    await show(MailboxRunState.syncing);
    expect(find.text(TogetherNowCopy.apartChecking), findsOneWidget);
    expect(find.text(TogetherNowCopy.apartBody), findsOneWidget);
    await tester.tap(find.text(TogetherNowCopy.checkNow));
    expect(checks, 0);

    await show(MailboxRunState.failed);
    expect(find.text(TogetherNowCopy.apartFailed), findsOneWidget);
    expect(find.text(TogetherNowCopy.apartFailedBody), findsOneWidget);
    expect(find.text(TogetherNowCopy.apartBody), findsNothing);
    await tester.tap(find.text(TogetherNowCopy.checkNow));
    expect(checks, 1);

    await show(MailboxRunState.ok);
    expect(find.text(TogetherNowCopy.apartReady), findsOneWidget);
    expect(find.text(TogetherNowCopy.apartBody), findsOneWidget);
  });
}
