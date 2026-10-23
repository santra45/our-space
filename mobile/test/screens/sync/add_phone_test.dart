import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/presentation/screens/settings/widgets/sheet_parts.dart';
import 'package:our_space_mobile/presentation/screens/sync/add_phone_page.dart';
import 'package:our_space_mobile/presentation/screens/sync/invite_qr.dart';
import 'package:our_space_mobile/presentation/screens/sync/notice_copy.dart';
import 'package:our_space_mobile/presentation/screens/sync/peer_link.dart';
import 'package:our_space_mobile/presentation/screens/sync/qr_scanner.dart';
import 'package:our_space_mobile/presentation/screens/sync/together_now.dart';
import 'package:our_space_mobile/presentation/sky/sky.dart';
import 'package:our_space_mobile/presentation/theme/app_colors.dart';
import 'package:our_space_mobile/presentation/widgets/app_haptics.dart';

import '../../widgets/harness.dart' show recordHaptics, recordedHaptics;
import 'hub_harness.dart';

Finder closeButton() =>
    find.byWidgetPredicate((widget) => widget is SkyIconButton && widget.semanticLabel == SheetCopy.close);

void main() {
  final systemShare = InviteShare.share;
  final systemCopy = InviteShare.copy;
  final systemCamera = QrCamera.builder;

  setUp(recordHaptics);

  tearDown(() {
    InviteShare.share = systemShare;
    InviteShare.copy = systemCopy;
    QrCamera.builder = systemCamera;
  });

  testWidgets('shows the invite code to scan, her code and the ways to bring their phone in', (tester) async {
    calm(tester);
    final space = await openUnlockedSpace(tester);
    await openAddPhonePage(tester, space);

    for (final text in [
      AddPhoneCopy.kicker.toUpperCase(),
      AddPhoneCopy.intro,
      AddPhoneCopy.codeTitle.toUpperCase(),
      AddPhoneCopy.shareLink,
      AddPhoneCopy.haveTheirs,
      AddPhoneCopy.scan,
      AddPhoneCopy.connect,
      AddPhoneCopy.recognise,
      TogetherNowCopy.notJoined,
    ]) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
    expect(find.text(space.device.peerId), findsOneWidget);
    expect(fieldWithHint(AddPhoneCopy.pasteHint), findsOneWidget);

    final qr = tester.widget<InviteQr>(find.byType(InviteQr));
    expect(qr.size, InviteQr.webSize);
    expect(qr.margin, InviteQr.webMargin);
    expect(qr.dark, AddPhonePage.qrInk);
    expect(qr.data, space.vault.buildInviteLink());
    final invite = parseInvite(qr.data)!;
    expect(invite.partnerPeerId, space.device.peerId);
    expect(invite.salt, space.vault.salt);
    expect(invite.coupleNames, 'Sam & Alex');
    expect(invite.startDate, '2021-06-14');

    await real(tester, () => space.vault.updateSettings(coupleNames: 'Us two'));
    await tester.pump();
    expect(parseInvite(tester.widget<InviteQr>(find.byType(InviteQr)).data)!.coupleNames, 'Us two');
  });

  testWidgets('sends the link, falls back to copying it, and copies her code', (tester) async {
    calm(tester);
    final space = await openUnlockedSpace(tester);
    final shared = <String>[];
    final copied = <String>[];
    var shareWorks = true;
    var copyWorks = true;
    InviteShare.share = ({required title, required text, required url}) async {
      shared.add('$title|$text|$url');
      return shareWorks;
    };
    InviteShare.copy = (text) async {
      if (!copyWorks) throw StateError('no clipboard');
      copied.add(text);
    };
    await openAddPhonePage(tester, space);
    final link = space.vault.buildInviteLink()!;

    await press(tester, find.text(AddPhoneCopy.shareLink));
    expect(shared.single, '${AddPhoneCopy.shareTitle}|${AddPhoneCopy.shareText}|$link');
    expect(recordedHaptics, containsAllInOrder([HapticKind.tick, HapticKind.tap, HapticKind.celebration]));
    expect(copied, isEmpty);

    shareWorks = false;
    await press(tester, find.text(AddPhoneCopy.shareLink));
    expect(copied, [link]);
    expect(find.text(AddPhoneCopy.linkCopied), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2600));
    expect(find.text(AddPhoneCopy.linkCopied), findsNothing);
    expect(find.text(AddPhoneCopy.shareLink), findsOneWidget);

    copyWorks = false;
    await press(tester, find.text(AddPhoneCopy.shareLink));
    expect(find.text(AddPhoneCopy.couldNotCopy), findsOneWidget);

    copyWorks = true;
    await press(tester, find.text(space.device.peerId));
    expect(copied.last, space.device.peerId);
    expect(find.text(AddPhoneCopy.copied), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2100));
    expect(find.text(AddPhoneCopy.copied), findsNothing);
  });

  testWidgets('the paste box reads codes and links like the web', (tester) async {
    calm(tester);
    final space = await openUnlockedSpace(tester);
    final peer = FakePeerLink();
    await openAddPhonePage(tester, space, peer: peer);

    await press(tester, find.text(AddPhoneCopy.connect));
    expect(peer.calls, isEmpty);
    expect(find.text(AddPhoneCopy.notAnInvite), findsNothing);

    await type(tester, fieldWithHint(AddPhoneCopy.pasteHint), 'not a pairing code!');
    await press(tester, find.text(AddPhoneCopy.connect));
    expect(find.text(AddPhoneCopy.notAnInvite), findsOneWidget);
    expect(peer.calls, isEmpty);

    final partner = await real(tester, openHubSpace);
    await real(tester, () => partner.vault.create(passphrase: passphrase, iterations: fastIterations));
    final partnerLink = partner.vault.buildInviteLink()!;
    await type(tester, fieldWithHint(AddPhoneCopy.pasteHint), '  $partnerLink  ');
    await press(tester, find.text(AddPhoneCopy.connect));
    expect(find.text(AddPhoneCopy.notAnInvite), findsNothing);
    expect(peer.calls, ['connect:${partner.device.peerId}']);

    await type(tester, fieldWithHint(AddPhoneCopy.pasteHint), 'love-abcdefgh');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pump();
    expect(peer.calls.last, 'connect:love-abcdefgh');
  });

  testWidgets('connecting hands the code to their phone and shows what comes back', (tester) async {
    calm(tester);
    final space = await openUnlockedSpace(tester);
    await openAddPhonePage(tester, space);
    await type(tester, fieldWithHint(AddPhoneCopy.pasteHint), 'love-abcdefgh');
    await press(tester, find.text(AddPhoneCopy.connect));
    await untilFound(tester, find.text(NoticeCopy.cannotReach(space.identity.partnerName)));

    expect(space.peer.partnerId, 'love-abcdefgh');
    expect(find.text(TogetherNowCopy.tryAgain), findsOneWidget);
    expect(space.sync.status.reason, isNull);

    await press(tester, find.text(TogetherNowCopy.dismiss));
    expect(space.peer.syncError, isNull);
    expect(find.text(TogetherNowCopy.tryAgain), findsNothing);
    await settle(tester);
  });

  testWidgets('scans their code through the camera hook', (tester) async {
    calm(tester);
    final space = await openUnlockedSpace(tester);
    final peer = FakePeerLink();
    QrCameraHandlers? handlers;
    QrCamera.builder = (context, given) {
      handlers = given;
      return const ColoredBox(color: AppColors.black, child: SizedBox.expand());
    };
    await openAddPhonePage(tester, space, peer: peer);

    await press(tester, find.text(AddPhoneCopy.scan));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(QrScannerCopy.subtitle), findsOneWidget);
    expect(find.text(QrScannerCopy.footer), findsOneWidget);
    expect(handlers, isNotNull);

    handlers!.onCode('not a pairing code!');
    await tester.pump();
    expect(find.text(QrScannerCopy.subtitle), findsOneWidget);
    expect(peer.calls, isEmpty);

    final partner = await real(tester, openHubSpace);
    await real(tester, () => partner.vault.create(passphrase: passphrase, iterations: fastIterations));
    recordedHaptics.clear();
    handlers!.onCode('  ${partner.vault.buildInviteLink()!}  ');
    handlers!.onCode(partner.vault.buildInviteLink()!);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(QrScannerCopy.subtitle), findsNothing);
    expect(peer.calls, ['connect:${partner.device.peerId}']);
    expect(recordedHaptics.where((kind) => kind == HapticKind.celebration), hasLength(2));

    await press(tester, find.text(AddPhoneCopy.scan));
    await tester.pump(const Duration(milliseconds: 500));
    handlers!.onError();
    await tester.pump();
    expect(find.text(QrScannerCopy.cameraError), findsOneWidget);
    await tester.tap(closeButton());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(QrScannerCopy.cameraError), findsNothing);
    expect(find.text(AddPhoneCopy.title), findsOneWidget);
    expect(peer.calls, hasLength(1));
  });

  testWidgets('a scanned code that is not an invite says so', (tester) async {
    calm(tester);
    final space = await openUnlockedSpace(tester);
    final peer = FakePeerLink();
    QrCameraHandlers? handlers;
    QrCamera.builder = (context, given) {
      handlers = given;
      return const SizedBox.expand();
    };
    await openAddPhonePage(tester, space, peer: peer);
    await press(tester, find.text(AddPhoneCopy.scan));
    await tester.pump(const Duration(milliseconds: 500));
    expect(handlers, isNotNull);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
    navigator.pop('not a pairing code!');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(AddPhoneCopy.notAnInviteQr), findsOneWidget);
    expect(peer.calls, isEmpty);
  });

  test('the invite link carries the couple settings like the web', () async {
    final space = await openHubSpace();
    expect(inviteLinkFor(myPeerId: 'love-abcdefgh', vault: space.vault), isNull);
    await space.vault.create(
      passphrase: passphrase,
      coupleNames: 'Sam & Alex',
      startDate: '2021-06-14',
      iterations: fastIterations,
    );
    expect(inviteLinkFor(myPeerId: null, vault: space.vault), isNull);
    expect(inviteLinkFor(myPeerId: '', vault: space.vault), isNull);
    expect(inviteLinkFor(myPeerId: space.device.peerId, vault: space.vault), space.vault.buildInviteLink());
    final invite = parseInvite(inviteLinkFor(myPeerId: 'love-abcdefgh', vault: space.vault))!;
    expect(invite.partnerPeerId, 'love-abcdefgh');
    expect(invite.salt, space.vault.salt);
    expect(invite.startDate, '2021-06-14');
    expect(invite.coupleNames, 'Sam & Alex');
    while (space.identity.status == IdentityStatus.loading || space.identity.status == IdentityStatus.locked) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    await space.close();
  });

  testWidgets('a share that throws still falls back to copying the link', (tester) async {
    calm(tester);
    final space = await openUnlockedSpace(tester);
    final copied = <String>[];
    InviteShare.share = ({required title, required text, required url}) async => throw StateError('no share sheet');
    InviteShare.copy = (text) async => copied.add(text);
    await openAddPhonePage(tester, space);
    await press(tester, find.text(AddPhoneCopy.shareLink));
    expect(copied, [space.vault.buildInviteLink()]);
    expect(find.text(AddPhoneCopy.linkCopied), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2600));
  });

  testWidgets('their phone status sits on the page and opens the details', (tester) async {
    calm(tester);
    final space = await openUnlockedSpace(tester);
    final peer = FakePeerLink(
      const PeerLinkView(myPeerId: 'love-fromthelink', partnerId: 'love-partnerphone', authorized: true),
    );
    await openAddPhonePage(tester, space, peer: peer);
    expect(find.text('love-fromthelink'), findsOneWidget);
    expect(parseInvite(tester.widget<InviteQr>(find.byType(InviteQr)).data)!.partnerPeerId, 'love-fromthelink');
    expect(find.text(TogetherNowCopy.together), findsOneWidget);

    await press(tester, find.text(TogetherNowCopy.together));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(TogetherNowCopy.sheetIntro), findsOneWidget);
    expect(find.text('love-partnerphone'), findsOneWidget);
  });
}
