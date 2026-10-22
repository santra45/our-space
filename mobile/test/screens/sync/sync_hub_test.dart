import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/main.dart';
import 'package:our_space_mobile/presentation/files/vault_files.dart';
import 'package:our_space_mobile/presentation/app_shell.dart';
import 'package:our_space_mobile/presentation/home_shell.dart';
import 'package:our_space_mobile/presentation/screens/settings/settings_page.dart';
import 'package:our_space_mobile/presentation/screens/sync/backup_dialogs.dart';
import 'package:our_space_mobile/presentation/screens/sync/invite_qr.dart';
import 'package:our_space_mobile/presentation/screens/sync/peer_link.dart';
import 'package:our_space_mobile/presentation/screens/sync/qr_scanner.dart';
import 'package:our_space_mobile/presentation/screens/sync/sync_hub.dart';
import 'package:our_space_mobile/presentation/widgets/our_widgets.dart';

import '../../support/fake_mailbox_worker.dart';
import '../../widgets/harness.dart' show recordHaptics, recordedHaptics;
import 'hub_harness.dart';

void main() {
  final systemPicker = VaultFiles.picker;
  final systemSaver = VaultFiles.saver;
  final systemShare = SyncHubShare.share;
  final systemCopy = SyncHubShare.copy;
  final systemCamera = QrCamera.builder;

  setUp(recordHaptics);

  tearDown(() {
    VaultFiles.picker = systemPicker;
    VaultFiles.saver = systemSaver;
    SyncHubShare.share = systemShare;
    SyncHubShare.copy = systemCopy;
    QrCamera.builder = systemCamera;
  });

  testWidgets('shows the web hub with the invite QR when there is no direct link yet', (tester) async {
    calm(tester);
    final space = await openUnlockedSpace(tester);
    await openHub(tester, space);

    for (final text in [
      SyncHubCopy.subtitle,
      SyncHubCopy.waiting,
      'your partner\'s App',
      SyncHubCopy.waitingForSync,
      SyncHubCopy.lastConnected,
      SyncHubCopy.notYetPaired,
      'YOUR DEVICE PAIRING QR',
      SyncHubCopy.shareLink,
      SyncHubCopy.connectTitle,
      SyncHubCopy.scan,
      SyncHubCopy.pair,
      SyncHubCopy.recognise,
      BackupCopy.sectionTitle,
      BackupCopy.saveCopy,
      BackupCopy.bringInCopy,
    ]) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
    expect(find.text(SyncHubCopy.mailboxReady), findsNothing);
    expect(find.text(SyncHubCopy.syncNow), findsNothing);
    expect(find.text(SyncHubCopy.partnerLabel), findsNothing);
    expect(find.text('WHO IS WHO'), findsNothing);
    expect(find.text(space.device.peerId), findsOneWidget);
    expect(fieldWithHint(SyncHubCopy.pasteHint), findsOneWidget);

    final qr = tester.widget<InviteQr>(find.byType(InviteQr));
    expect(qr.size, 190);
    expect(qr.margin, 2);
    expect(qr.dark, AppColors.slate800);
    expect(qr.data, space.vault.buildInviteLink());
    final invite = parseInvite(qr.data)!;
    expect(invite.partnerPeerId, space.device.peerId);
    expect(invite.salt, space.vault.salt);
    expect(invite.coupleNames, 'Sam & Alex');
    expect(invite.startDate, '2021-06-14');

    await real(tester, () => space.vault.updateSettings(coupleNames: 'Us two'));
    await tester.pump();
    expect(parseInvite(tester.widget<InviteQr>(find.byType(InviteQr)).data)!.coupleNames, 'Us two');

    await tester.tap(find.byType(OurCloseButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(SyncHubCopy.title), findsNothing);
    expect(recordedHaptics, contains(HapticKind.tap));
  });

  testWidgets('shares the pairing link, falls back to copying it, and copies the code', (tester) async {
    calm(tester);
    final space = await openUnlockedSpace(tester);
    final shared = <String>[];
    final copied = <String>[];
    var shareWorks = true;
    var copyWorks = true;
    SyncHubShare.share = ({required title, required text, required url}) async {
      shared.add('$title|$text|$url');
      return shareWorks;
    };
    SyncHubShare.copy = (text) async {
      if (!copyWorks) throw StateError('no clipboard');
      copied.add(text);
    };
    await openHub(tester, space);
    final link = space.vault.buildInviteLink()!;

    await press(tester, find.text(SyncHubCopy.shareLink));
    expect(shared.single, '${SyncHubCopy.shareTitle}|${SyncHubCopy.shareText}|$link');
    expect(recordedHaptics, containsAllInOrder([HapticKind.tick, HapticKind.tap, HapticKind.celebration]));
    expect(copied, isEmpty);

    shareWorks = false;
    await press(tester, find.text(SyncHubCopy.shareLink));
    expect(copied, [link]);
    expect(find.text(SyncHubCopy.linkCopied), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2600));
    expect(find.text(SyncHubCopy.linkCopied), findsNothing);
    expect(find.text(SyncHubCopy.shareLink), findsOneWidget);

    copyWorks = false;
    await press(tester, find.text(SyncHubCopy.shareLink));
    expect(find.text(SyncHubCopy.couldNotCopy), findsOneWidget);

    copyWorks = true;
    await press(tester, find.text(space.device.peerId));
    expect(copied.last, space.device.peerId);
    expect(find.text(SyncHubCopy.copiedId), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2100));
    expect(find.text(SyncHubCopy.copiedId), findsNothing);
  });

  testWidgets('pairing input reads codes and links like the web', (tester) async {
    calm(tester);
    final space = await openUnlockedSpace(tester);
    final peer = FakePeerLink();
    await openHub(tester, space, peer: peer);

    await press(tester, find.text(SyncHubCopy.pair));
    expect(peer.calls, isEmpty);
    expect(find.text(SyncHubCopy.notAnInvite), findsNothing);

    await type(tester, fieldWithHint(SyncHubCopy.pasteHint), 'not a pairing code!');
    await press(tester, find.text(SyncHubCopy.pair));
    expect(find.text(SyncHubCopy.notAnInvite), findsOneWidget);
    expect(peer.calls, isEmpty);

    final partner = await real(tester, openHubSpace);
    await real(tester, () => partner.vault.create(passphrase: passphrase, iterations: fastIterations));
    final partnerLink = partner.vault.buildInviteLink()!;
    await type(tester, fieldWithHint(SyncHubCopy.pasteHint), '  $partnerLink  ');
    await press(tester, find.text(SyncHubCopy.pair));
    expect(find.text(SyncHubCopy.notAnInvite), findsNothing);
    expect(peer.calls, ['connect:${partner.device.peerId}']);

    await type(tester, fieldWithHint(SyncHubCopy.pasteHint), 'love-abcdefgh');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pump();
    expect(peer.calls.last, 'connect:love-abcdefgh');
  });

  testWidgets('pairing hands the code to the phone-to-phone link and shows what it says back', (tester) async {
    calm(tester);
    final space = await openUnlockedSpace(tester);
    await openHub(tester, space);
    await type(tester, fieldWithHint(SyncHubCopy.pasteHint), 'love-abcdefgh');
    await press(tester, find.text(SyncHubCopy.pair));
    await untilFound(tester, find.text('We could not reach love-abcdefgh. Check they have Our Space open, then try again.'));

    expect(space.peer.partnerId, 'love-abcdefgh');
    expect(find.text('love-abcdefgh'), findsNWidgets(2));
    expect(find.text(SyncHubCopy.tryAgain), findsOneWidget);
    expect(space.sync.status.reason, isNull);

    await press(tester, find.text(SyncHubCopy.dismiss));
    expect(space.peer.syncError, isNull);
    expect(find.text(SyncHubCopy.tryAgain), findsNothing);
    await settle(tester);
  });

  testWidgets('scans a partner QR through the camera hook', (tester) async {
    calm(tester);
    final space = await openUnlockedSpace(tester);
    final peer = FakePeerLink();
    QrCameraHandlers? handlers;
    QrCamera.builder = (context, given) {
      handlers = given;
      return const ColoredBox(color: AppColors.black, child: SizedBox.expand());
    };
    await openHub(tester, space, peer: peer);

    await press(tester, find.text(SyncHubCopy.scan));
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

    await press(tester, find.text(SyncHubCopy.scan));
    handlers!.onError();
    await tester.pump();
    expect(find.text(QrScannerCopy.cameraError), findsOneWidget);
    final closes = find.byType(OurCloseButton);
    await tester.tap(closes.last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(QrScannerCopy.cameraError), findsNothing);
    expect(find.text(SyncHubCopy.title), findsOneWidget);
    expect(peer.calls, hasLength(1));
  });

  testWidgets('the direct link state drives the status panel like the web', (tester) async {
    calm(tester);
    final space = await openUnlockedSpace(tester);
    final now = DateTime.now().millisecondsSinceEpoch;
    final peer = FakePeerLink(const PeerLinkView(
      myPeerId: 'love-fromthelink',
      partnerId: 'love-partnerphone',
      authorized: true,
      route: PeerRoute.direct,
    ));
    await openHub(tester, space, peer: peer);

    expect(find.text(SyncHubCopy.connected), findsOneWidget);
    expect(find.text(SyncHubCopy.howConnected), findsOneWidget);
    expect(find.text(SyncHubCopy.direct), findsOneWidget);
    expect(find.text(SyncHubCopy.activeNow), findsOneWidget);
    expect(find.text(SyncHubCopy.connectedNow), findsOneWidget);
    expect(find.text(SyncHubCopy.partnerLabel), findsOneWidget);
    expect(find.text('love-partnerphone'), findsOneWidget);
    expect(find.text(SyncHubCopy.reconnect), findsNothing);
    expect(find.text('love-fromthelink'), findsOneWidget);
    expect(parseInvite(tester.widget<InviteQr>(find.byType(InviteQr)).data)!.partnerPeerId, 'love-fromthelink');

    await press(tester, find.text(SyncHubCopy.syncNow));
    expect(peer.calls, ['syncNow']);

    peer.state = const PeerLinkView(partnerId: 'love-partnerphone', authorized: true, route: PeerRoute.relayed);
    await tester.pump();
    expect(find.text(SyncHubCopy.relayed), findsOneWidget);
    expect(find.text(SyncHubCopy.notSureBody), findsNothing);

    peer.state = const PeerLinkView(partnerId: 'love-partnerphone', authorized: true, syncing: true);
    await tester.pump();
    expect(find.text(SyncHubCopy.notSure), findsOneWidget);
    expect(find.text(SyncHubCopy.notSureBody), findsOneWidget);
    expect(find.text(SyncHubCopy.syncingWithPartner), findsOneWidget);

    peer.state = PeerLinkView(partnerId: 'love-partnerphone', connecting: true, lastConnectedAt: now - 5 * 60000);
    await tester.pump();
    expect(find.text(SyncHubCopy.connecting), findsOneWidget);
    expect(find.text('5m ago'), findsOneWidget);
    expect(find.text(SyncHubCopy.waitingForSync), findsOneWidget);
    await press(tester, find.text(SyncHubCopy.reconnect));
    expect(peer.calls.last, 'reconnect');

    await press(tester, find.text(SyncHubCopy.unpair));
    expect(find.text(SyncHubCopy.unpairConfirm), findsOneWidget);
    await press(tester, find.text('Cancel').last);
    expect(peer.calls.last, 'reconnect');
    await press(tester, find.text(SyncHubCopy.unpair));
    await press(tester, find.text('OK'));
    expect(peer.calls.last, 'unpair');

    peer.state = const PeerLinkView(handshaking: true);
    await tester.pump();
    expect(find.text(SyncHubCopy.handshaking), findsOneWidget);
    expect(find.text(SyncHubCopy.partnerLabel), findsNothing);

    peer.state = const PeerLinkView(
      partnerId: 'love-partnerphone',
      error: PeerLinkError(text: 'Your passphrases do not match.', code: PeerLinkError.passphraseMismatch),
    );
    await tester.pump();
    expect(find.text('Your passphrases do not match.'), findsOneWidget);
    expect(find.text(SyncHubCopy.passphraseMismatchHelp), findsOneWidget);
    await press(tester, find.text(SyncHubCopy.tryAgain));
    expect(peer.calls.last, 'reconnect');
    await press(tester, find.text(SyncHubCopy.dismiss));
    expect(peer.calls.last, 'clearError');

    peer.state = const PeerLinkView(error: PeerLinkError(text: 'Lost them for a moment.'));
    await tester.pump();
    expect(find.text(SyncHubCopy.tryAgain), findsNothing);
    expect(find.text(SyncHubCopy.passphraseMismatchHelp), findsNothing);
  });

  testWidgets('shows the partner presence and sync warnings from the engine', (tester) async {
    calm(tester);
    final space = await openUnlockedSpace(tester);
    await real(tester, () => space.identity.createCouple(myName: 'Sam', partnerName: 'Alex'));
    await openHub(tester, space);
    expect(find.text('Alex\'s App'), findsOneWidget);
    expect(find.text(SyncHubCopy.waitingForSync), findsOneWidget);

    space.mailbox.onWarning!('clock_skew', 'Your phone clock looks a little off.');
    await tester.pump();
    expect(find.text('Your phone clock looks a little off.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 8));
    expect(find.text('Your phone clock looks a little off.'), findsNothing);
  });

  testWidgets('the mailbox panel checks for things on demand', (tester) async {
    calm(tester);
    final worker = FakeMailboxWorker(token: 'test-token');
    final space = await openUnlockedSpace(
      tester,
      mailbox: const MailboxConfig(
          url: 'https://mailbox.test', token: 'test-token', origin: 'https://sameskytonight.vercel.app'),
      client: worker,
    );
    await real(tester, () => space.identity.createCouple(myName: 'Sam', partnerName: 'Alex'));
    await openHub(tester, space);
    expect(find.text(SyncHubCopy.mailboxReady), findsOneWidget);
    expect(find.text(SyncHubCopy.mailboxBody), findsOneWidget);
    expect(space.sync.status.state, MailboxRunState.idle);

    await press(tester, find.text(SyncHubCopy.checkNow));
    await until(tester, () => space.sync.status.state == MailboxRunState.ok);
    await settle(tester);
    expect(space.sync.status.reason, 'manual');
    expect(worker.calls, isNotEmpty);
    expect(find.text(SyncHubCopy.mailboxReady), findsOneWidget);
    expect(recordedHaptics, contains(HapticKind.tap));
  });

  testWidgets('the mailbox panel says when it is checking or could not check', (tester) async {
    calm(tester);
    var checks = 0;
    Future<void> show(MailboxRunState state) => tester.pumpWidget(
          MaterialApp(home: Scaffold(body: MailboxPanel(state: state, onCheck: () => checks++))),
        );

    await show(MailboxRunState.syncing);
    expect(find.text(SyncHubCopy.mailboxChecking), findsOneWidget);
    expect(find.text(SyncHubCopy.mailboxBody), findsOneWidget);
    await tester.tap(find.text(SyncHubCopy.checkNow));
    expect(checks, 0);

    await show(MailboxRunState.failed);
    expect(find.text(SyncHubCopy.mailboxFailed), findsOneWidget);
    expect(find.text(SyncHubCopy.mailboxFailedBody), findsOneWidget);
    expect(find.text(SyncHubCopy.mailboxBody), findsNothing);
    await tester.tap(find.text(SyncHubCopy.checkNow));
    expect(checks, 1);

    await show(MailboxRunState.ok);
    expect(find.text(SyncHubCopy.mailboxReady), findsOneWidget);
    expect(find.text(SyncHubCopy.mailboxBody), findsOneWidget);
  });

  testWidgets('saves a copy only with the passphrase that opens the space', (tester) async {
    calm(tester);
    final space = await openUnlockedSpace(tester);
    await real(tester, () => space.milestones.add(title: 'First date', date: '2021-06-14'));
    final saved = <BackupFile>[];
    var accept = false;
    VaultFiles.saver = (file) async {
      saved.add(file);
      return accept;
    };
    await openHub(tester, space);

    await press(tester, find.text(BackupCopy.saveCopy));
    expect(find.text(BackupCopy.exportTitle), findsOneWidget);
    expect(find.text(BackupCopy.exportDescription), findsOneWidget);
    final field = fieldWithHint(BackupCopy.passphraseHint);
    final again = fieldWithHint(BackupCopy.confirmHint);

    await type(tester, field, 'short');
    expect(find.text(BackupCopy.tooShort()), findsOneWidget);
    await type(tester, field, 'a different passphrase entirely');
    expect(find.text(BackupCopy.tooShort()), findsNothing);
    await type(tester, again, 'a different passphrase');
    expect(find.text(BackupCopy.mismatch), findsOneWidget);
    await press(tester, find.text(BackupCopy.exportSubmit));
    expect(saved, isEmpty);

    await type(tester, again, 'a different passphrase entirely');
    await press(tester, find.text(BackupCopy.exportSubmit));
    await untilFound(tester, find.text(BackupMessages.wrongPassphrase));
    expect(saved, isEmpty);

    await press(tester, find.bySemanticsLabel(BackupCopy.showPassphrase));
    expect(find.bySemanticsLabel(BackupCopy.hidePassphrase), findsOneWidget);
    await type(tester, field, passphrase);
    await type(tester, again, passphrase);
    await press(tester, find.text(BackupCopy.exportSubmit));
    await until(tester, () => saved.isNotEmpty);
    await tester.pump();
    expect(find.text(BackupCopy.exportTitle), findsOneWidget);
    expect(find.text(BackupMessages.wrongPassphrase), findsNothing);

    accept = true;
    await press(tester, find.text(BackupCopy.exportSubmit));
    await untilFound(tester, find.text(BackupMessages.saved));
    await settle(tester);
    expect(find.text(BackupCopy.exportTitle), findsNothing);
    expect(recordedHaptics.last, HapticKind.celebration);
    expect(saved.last.fileName, matches(RegExp(r'^our-space-\d{4}-\d{2}-\d{2}\.vault$')));
    final opened = await real(
      tester,
      () => space.backup.openContainer(space.backup.parseBackupFile(saved.last.contents), passphrase),
    );
    expect(((opened['tables'] as Map)['milestones'] as List), hasLength(1));

    await press(tester, find.text(BackupCopy.saveCopy));
    expect(find.text(BackupMessages.saved), findsNothing);
    await press(tester, find.text(BackupCopy.cancel));
    expect(find.text(BackupCopy.exportTitle), findsNothing);
  });

  testWidgets('brings in a copy after showing exactly what would change', (tester) async {
    calm(tester);
    final source = await openUnlockedSpace(tester);
    final rescue = await real(tester, () => source.backup.exportRescueBackup(passphrase));
    final phone = await real(tester, openHubSpace);
    await real(tester, () async {
      final opened = await phone.backup.openContainer(phone.backup.parseBackupFile(rescue.contents), passphrase);
      final restored = await phone.vault.restoreFromBackup(opened['tables'], passphrase);
      expect(restored.ok, isTrue);
    });
    await real(tester, () => source.milestones.add(title: 'First date', date: '2021-06-14'));
    final withMilestone = await real(tester, () => source.backup.exportBackup(passphrase));

    PickedVaultFile? next;
    VaultFiles.picker = () async => next;
    await openHub(tester, phone);

    next = PickedVaultFile(name: 'huge.vault', size: maxBackupFileBytes + 1, bytes: Uint8List(0));
    await press(tester, find.text(BackupCopy.bringInCopy));
    expect(find.text(BackupMessages.tooBig(maxBackupFileBytes + 1)), findsOneWidget);

    next = PickedVaultFile(name: 'notes.txt', size: 5, bytes: Uint8List.fromList(utf8.encode('hello')));
    await press(tester, find.text(BackupCopy.bringInCopy));
    expect(find.text(BackupMessages.notOurFile), findsOneWidget);
    expect(find.text(BackupMessages.tooBig(maxBackupFileBytes + 1)), findsNothing);

    next = const PickedVaultFile(name: 'lost.vault', size: 10, bytes: null);
    await press(tester, find.text(BackupCopy.bringInCopy));
    expect(find.text(BackupCopy.couldNotRead), findsOneWidget);

    next = pickedFrom(withMilestone);
    await press(tester, find.text(BackupCopy.bringInCopy));
    expect(find.text(BackupCopy.importTitle), findsOneWidget);
    expect(find.text(BackupCopy.importDescription), findsOneWidget);
    expect(fieldWithHint(BackupCopy.confirmHint), findsNothing);
    await type(tester, fieldWithHint(BackupCopy.passphraseHint), 'not the passphrase it was saved with');
    await press(tester, find.text(BackupCopy.importSubmit));
    await untilFound(tester, find.text(BackupMessages.couldNotOpen));

    await type(tester, fieldWithHint(BackupCopy.passphraseHint), passphrase);
    await press(tester, find.text(BackupCopy.importSubmit));
    await untilFound(tester, find.text(BackupCopy.previewTitle));
    expect(find.text(BackupCopy.previewIntro), findsOneWidget);
    expect(find.text('ADDED'), findsOneWidget);
    expect(find.text('UPDATED'), findsOneWidget);
    expect(find.text(BackupCopy.nothingRemoved), findsOneWidget);
    expect(find.text(BackupCopy.foreignTitle.toUpperCase()), findsNothing);
    await press(tester, find.text(BackupCopy.add(1)));
    await untilFound(tester, find.text('Added 1 thing.'));
    expect(find.text(BackupCopy.previewTitle), findsNothing);
    expect(recordedHaptics.last, HapticKind.celebration);
    final milestones = await real(tester, () => phone.milestones.list());
    expect(milestones.map((m) => m.title), ['First date']);

    final added = await real(tester, () => source.milestones.list());
    await real(tester, () => source.milestones.delete(added.single.id));
    final withDelete = await real(tester, () => source.backup.exportBackup(passphrase));
    next = pickedFrom(withDelete);
    await press(tester, find.text(BackupCopy.bringInCopy));
    expect(find.text('Added 1 thing.'), findsNothing);
    await type(tester, fieldWithHint(BackupCopy.passphraseHint), passphrase);
    await press(tester, find.text(BackupCopy.importSubmit));
    await untilFound(tester, find.text(BackupCopy.previewTitle));
    expect(find.text(BackupCopy.willRemove(1)), findsOneWidget);
    expect(find.text(BackupCopy.acknowledge(1)), findsOneWidget);
    await press(tester, find.text(BackupCopy.addRemoving(1)));
    expect(find.text(BackupCopy.previewTitle), findsOneWidget);
    await press(tester, find.text(BackupCopy.acknowledge(1)));
    expect(tester.widget<AckBox>(find.byType(AckBox)).checked, isTrue);
    recordedHaptics.clear();
    await press(tester, find.text(BackupCopy.addRemoving(1)));
    await untilFound(
        tester, find.text('Added 1 thing. 1 of them removed something you had — those are gone for good.'));
    expect(recordedHaptics, isNot(contains(HapticKind.celebration)));
    expect(await real(tester, () => phone.milestones.list()), isEmpty);

    final stranger = await real(tester, openHubSpace);
    await real(tester, () => stranger.vault.create(passphrase: passphrase, iterations: fastIterations));
    await real(tester, () => stranger.milestones.add(title: 'Not ours', date: '2020-01-01'));
    final foreign = await real(tester, () => stranger.backup.exportBackup(passphrase));
    next = pickedFrom(foreign);
    await press(tester, find.text(BackupCopy.bringInCopy));
    await type(tester, fieldWithHint(BackupCopy.passphraseHint), passphrase);
    await press(tester, find.text(BackupCopy.importSubmit));
    await untilFound(tester, find.text(BackupCopy.previewTitle));
    expect(find.text(BackupCopy.foreignTitle.toUpperCase()), findsOneWidget);
    expect(find.text(BackupCopy.foreignBody), findsOneWidget);
    expect(find.textContaining('left out'), findsOneWidget);
    expect(find.text(BackupCopy.whyBody), findsNothing);
    await press(tester, find.text(BackupCopy.why));
    expect(find.text(BackupCopy.whyBody), findsOneWidget);
    await press(tester, find.text(BackupCopy.nothingToAdd));
    expect(find.text(BackupCopy.previewTitle), findsOneWidget);
    await press(tester, find.text(BackupCopy.cancel));
    expect(find.text(BackupCopy.previewTitle), findsNothing);
    expect(find.text(SyncHubCopy.title), findsOneWidget);
  });

  testWidgets('opens from settings, and locking closes the hub, settings and every sheet above them', (tester) async {
    calm(tester);
    final space = await openUnlockedSpace(tester);
    await real(tester, () => space.identity.createCouple(myName: 'Sam', partnerName: 'Alex'));
    await tester.pumpWidget(OurSpaceApp(openSpace: () async => space, shell: const HomeShell(pageBuilder: avatarTab)));
    await tester.pump();
    await untilFound(tester, find.byKey(ShellKeys.avatar));
    await tester.tap(find.byKey(ShellKeys.avatar));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(SettingsPage), findsOneWidget);
    await tester.tap(find.byKey(SettingsPage.phonesKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(SyncHubCopy.title), findsOneWidget);
    expect(find.byType(InviteQr), findsOneWidget);

    await press(tester, find.text(BackupCopy.saveCopy));
    expect(find.text(BackupCopy.exportTitle), findsOneWidget);
    space.vault.lock();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(BackupCopy.exportTitle), findsNothing);
    expect(find.text(SyncHubCopy.title), findsNothing);
    expect(find.byType(SettingsPage), findsNothing);
    expect(find.text('Locked'), findsOneWidget);
  });

  test('the invite link carries the couple settings like the web', () async {
    final space = await openHubSpace();
    expect(syncHubInviteLink(myPeerId: 'love-abcdefgh', vault: space.vault), isNull);
    await space.vault.create(
      passphrase: passphrase,
      coupleNames: 'Sam & Alex',
      startDate: '2021-06-14',
      iterations: fastIterations,
    );
    expect(syncHubInviteLink(myPeerId: null, vault: space.vault), isNull);
    expect(syncHubInviteLink(myPeerId: '', vault: space.vault), isNull);
    final link = syncHubInviteLink(myPeerId: space.device.peerId, vault: space.vault)!;
    expect(link, space.vault.buildInviteLink());
    final invite = parseInvite(syncHubInviteLink(myPeerId: 'love-abcdefgh', vault: space.vault))!;
    expect(invite.partnerPeerId, 'love-abcdefgh');
    expect(invite.salt, space.vault.salt);
    expect(invite.startDate, '2021-06-14');
    expect(invite.coupleNames, 'Sam & Alex');
    while (space.identity.status == IdentityStatus.loading || space.identity.status == IdentityStatus.locked) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    await space.close();
  });
}
