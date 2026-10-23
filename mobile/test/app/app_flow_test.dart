import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/main.dart';
import 'package:our_space_mobile/presentation/app_shell.dart';
import 'package:our_space_mobile/presentation/files/vault_files.dart';
import 'package:our_space_mobile/presentation/home_shell.dart';
import 'package:our_space_mobile/presentation/screens/lock/lock_screen.dart';
import 'package:our_space_mobile/presentation/screens/settings/settings_page.dart';
import 'package:our_space_mobile/presentation/sky/sky.dart';
import 'package:our_space_mobile/presentation/space_scope.dart';
import 'package:our_space_mobile/presentation/vault_gate.dart';
import 'package:our_space_mobile/presentation/widgets/app_haptics.dart';

import '../screens/lock/lock_harness.dart' show lockButtonEnabled, lockField, touchEnabled;
import '../support/fake_quick_unlock.dart';
import '../support/harness.dart';
import '../widgets/harness.dart' show recordHaptics, recordedHaptics, usePhoneSize;

const String passphrase = 'correct horse battery staple 2026';
const int fastIterations = 1000;

Future<OurSpace> openTestSpace({QuickUnlockPlatform? quickUnlock}) {
  final dir = Directory.systemTemp.createTempSync('our_space_app_');
  return OurSpace.open(
    databaseFactory: testDatabaseFactory(),
    databasePath: '${dir.path}${Platform.pathSeparator}space.sqlite',
    useEnvironmentMailbox: false,
    autoSync: false,
    quickUnlockPlatform: quickUnlock,
  );
}

Future<T> real<T>(WidgetTester tester, Future<T> Function() body) async => (await tester.runAsync(body)) as T;

Future<void> until(WidgetTester tester, bool Function() done, {int tries = 1500}) async {
  for (var i = 0; i < tries && !done(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
  expect(done(), isTrue);
}

Future<void> untilFound(WidgetTester tester, Finder finder) => until(tester, () => finder.evaluate().isNotEmpty);

Finder fieldWithHint(String hint) => lockField(hint);

Future<void> reveal(WidgetTester tester, Finder finder) async {
  unawaited(Scrollable.ensureVisible(tester.element(finder), alignment: 0.5));
  await tester.pump();
}

Future<void> type(WidgetTester tester, Finder finder, String text) async {
  await reveal(tester, finder);
  await tester.enterText(finder, text);
  await tester.pump();
}

Future<void> press(WidgetTester tester, Finder finder) async {
  await reveal(tester, finder);
  await tester.tap(finder);
  await tester.pump();
}

bool enabledButton(WidgetTester tester, String label) => lockButtonEnabled(tester, label);

Future<void> drain(WidgetTester tester) async {
  for (var i = 0; i < 25; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
}

Finder labelled(String label) =>
    find.byWidgetPredicate((widget) => widget is Semantics && widget.properties.label == label);

Finder inNotices(String text) => find.descendant(of: find.byKey(ShellKeys.notices), matching: find.text(text));

Future<void> openSettingsPage(WidgetTester tester) async {
  await tester.tap(find.byKey(ShellKeys.avatar));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  expect(find.byType(SettingsPage), findsOneWidget);
}

Future<void> lockFromSettings(WidgetTester tester) async {
  await openSettingsPage(tester);
  await press(tester, find.byKey(ShellKeys.lockNow));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> pumpApp(WidgetTester tester, Future<OurSpace> Function() open) async {
  await tester.pumpWidget(OurSpaceApp(openSpace: open));
  await tester.pump();
}

void main() {
  final systemPicker = VaultFiles.picker;
  final systemSaver = VaultFiles.saver;

  setUp(recordHaptics);

  tearDown(() {
    VaultFiles.picker = systemPicker;
    VaultFiles.saver = systemSaver;
  });

  void calm(WidgetTester tester) {
    usePhoneSize(tester);
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
      disableAnimations: true,
      reduceMotion: true,
    );
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }

  test('lock screen picks the web default mode', () {
    expect(defaultLockMode(VaultCheckState.present), LockMode.unlock);
    expect(defaultLockMode(VaultCheckState.checking), isNull);
    expect(defaultLockMode(VaultCheckState.unreadable), isNull);
    expect(defaultLockMode(VaultCheckState.absent), LockMode.setup);
    expect(defaultLockMode(VaultCheckState.absent, inviteHasSalt: true), LockMode.join);
    expect(defaultLockMode(VaultCheckState.absent, installed: true), LockMode.join);
  });

  test('rescue copies open with the passphrase they were saved with', () async {
    final space = await openTestSpace();
    await space.vault.create(passphrase: passphrase, iterations: fastIterations);
    await space.milestones.add(title: 'First date', date: '2021-06-14');

    await expectLater(
      space.backup.exportRescueBackup('too short'),
      throwsA(
          isA<BackupFailure>().having((f) => f.message, 'message', 'Pick a passphrase with at least 16 characters.')),
    );

    space.vault.lock();
    final file = await space.backup.exportRescueBackup('a rescue passphrase for the file');
    expect(file.fileName, matches(RegExp(r'^our-space-rescue-\d{4}-\d{2}-\d{2}\.vault$')));
    final container = space.backup.parseBackupFile(file.contents);
    final opened = await space.backup.openContainer(container, 'a rescue passphrase for the file');
    final identity = readBackupVaultIdentity(opened['tables']);
    expect(identity?['salt'], space.vault.salt);
    expect((opened['tables'] as Map)['milestones'], hasLength(1));
    await space.close();
  });

  testWidgets('boots into setup on a fresh phone, creates a space, locks and unlocks', (tester) async {
    calm(tester);
    final space = await real(tester, openTestSpace);
    await pumpApp(tester, () async => space);
    await untilFound(tester, find.text(LockCopy.setupTitle));

    expect(find.text(LockCopy.segmentStart), findsOneWidget);
    expect(find.text(LockCopy.segmentJoin), findsOneWidget);
    expect(find.text(LockCopy.freshTitle), findsOneWidget);
    expect(labelled(LockCopy.footer), findsOneWidget);
    expect(find.text(LockCopy.moreRestore), findsOneWidget);
    expect(enabledButton(tester, LockCopy.createButton), isFalse);

    await type(tester, fieldWithHint(LockCopy.namesHint), 'Sam & Alex');
    await type(tester, fieldWithHint(LockCopy.setupHint), 'too short');
    await press(tester, find.text(LockCopy.createButton));
    expect(find.text(LockCopy.setupTooShort()), findsOneWidget);

    await type(tester, fieldWithHint(LockCopy.setupHint), passphrase);
    await press(tester, find.text(LockCopy.createButton));
    await until(tester, () => space.vault.isUnlocked);
    await untilFound(tester, find.byType(HomeShell));
    await untilFound(tester, find.text('Already did this on the other phone'));
    await press(tester, find.text('Already did this on the other phone'));

    for (final label in ['Sky', 'Letters', 'Memories', 'Us']) {
      expect(find.descendant(of: find.byKey(ShellKeys.dock), matching: find.text(label)), findsOneWidget);
    }
    expect(find.byType(SkyHereChip), findsNothing);
    expect(recordedHaptics, contains(HapticKind.celebration));
    expect(space.vault.config!.coupleNames, 'Sam & Alex');

    await openSettingsPage(tester);
    expect(find.text('Sam & Alex'), findsOneWidget);
    await press(tester, find.byKey(ShellKeys.lockNow));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(space.vault.isUnlocked, isFalse);
    expect(find.text('Locked'), findsOneWidget);
    expect(find.text(LockCopy.unlockIntro), findsOneWidget);
    expect(enabledButton(tester, LockCopy.unlockButton), isFalse);

    final unlockField = fieldWithHint(LockCopy.unlockHint);
    await type(tester, unlockField, 'short one');
    await press(tester, find.text(LockCopy.unlockButton));
    expect(find.text(LockCopy.unlockTooShort()), findsOneWidget);

    await type(tester, unlockField, 'this is not the passphrase at all');
    await press(tester, find.text(LockCopy.unlockButton));
    await untilFound(tester, find.text(LockCopy.incorrectPassphrase));
    expect(space.vault.isUnlocked, isFalse);

    await type(tester, unlockField, passphrase);
    expect(find.text(LockCopy.incorrectPassphrase), findsNothing);
    await press(tester, find.text(LockCopy.unlockButton));
    await until(tester, () => space.vault.isUnlocked);
    await untilFound(tester, find.byType(HomeShell));
    expect(find.byKey(ShellKeys.dock), findsOneWidget);
    expect(space.vault.config!.coupleNames, 'Sam & Alex');
  });

  testWidgets('a touch opens the space once it is set up, and the passphrase is always one tap away', (tester) async {
    calm(tester);
    final fake = FakeQuickUnlock();
    final space = await real(tester, () => openTestSpace(quickUnlock: fake));
    await real(tester, () async {
      await space.vault.create(passphrase: passphrase, coupleNames: 'Sam & Alex', iterations: fastIterations);
      await space.identity.createCouple(myName: 'Sam', partnerName: 'Alex');
      await space.quickUnlock.refresh();
      expect((await space.quickUnlock.enable(passphrase)).ok, isTrue);
    });
    space.vault.lock();
    await pumpApp(tester, () async => space);
    await untilFound(tester, find.text(LockCopy.quickButton));

    expect(find.text(LockCopy.usePassphrase), findsOneWidget);
    expect(fieldWithHint(LockCopy.unlockHint), findsNothing);

    fake.failNext = 'cancelled';
    await press(tester, find.text(LockCopy.quickButton));
    await until(tester, () => touchEnabled(tester));
    expect(space.vault.isUnlocked, isFalse);
    expect(find.text(QuickUnlockCopy.didNotWork), findsNothing);

    await press(tester, find.text(LockCopy.quickButton));
    await until(tester, () => space.vault.isUnlocked);
    await untilFound(tester, find.byType(HomeShell));
    expect(find.byKey(ShellKeys.dock), findsOneWidget);
    expect(space.identity.partnerName, 'Alex');
    expect(recordedHaptics, contains(HapticKind.celebration));

    await lockFromSettings(tester);
    await untilFound(tester, find.text(LockCopy.usePassphrase));
    await press(tester, find.text(LockCopy.usePassphrase));
    expect(find.text(LockCopy.unlockIntro), findsOneWidget);
    expect(fieldWithHint(LockCopy.unlockHint), findsOneWidget);
    expect(find.text(LockCopy.quickButton), findsNothing);

    await press(tester, find.text(LockCopy.useTouch));
    expect(find.text(LockCopy.quickButton), findsOneWidget);
    expect(fieldWithHint(LockCopy.unlockHint), findsNothing);
  });

  testWidgets('when the phone fingerprints change it says so and goes back to the passphrase', (tester) async {
    calm(tester);
    final fake = FakeQuickUnlock();
    final space = await real(tester, () => openTestSpace(quickUnlock: fake));
    await real(tester, () async {
      await space.vault.create(passphrase: passphrase, coupleNames: 'Sam & Alex', iterations: fastIterations);
      await space.quickUnlock.refresh();
      expect((await space.quickUnlock.enable(passphrase)).ok, isTrue);
    });
    space.vault.lock();
    await pumpApp(tester, () async => space);
    await untilFound(tester, find.text(LockCopy.quickButton));

    fake.failNext = 'stale';
    await press(tester, find.text(LockCopy.quickButton));
    await untilFound(tester, find.text(QuickUnlockCopy.needsSetupAgain));
    expect(space.vault.isUnlocked, isFalse);
    expect(find.text(LockCopy.quickButton), findsNothing);
    expect(find.text(LockCopy.useTouch), findsNothing);
    expect(fieldWithHint(LockCopy.unlockHint), findsOneWidget);
  });

  testWidgets('shows a gentle retry when the phone storage will not open', (tester) async {
    calm(tester);
    final space = await real(tester, openTestSpace);
    var attempts = 0;
    await pumpApp(tester, () async {
      attempts++;
      if (attempts == 1) throw StateError('disk said no');
      return space;
    });
    await untilFound(tester, find.text(LockCopy.unreadableTitle));
    expect(find.text(LockCopy.unreadableBody), findsOneWidget);
    expect(find.textContaining('disk said no'), findsNothing);

    await press(tester, find.text(LockCopy.tryAgain));
    await untilFound(tester, find.text(LockCopy.setupTitle));
    expect(attempts, 2);
  });

  testWidgets('joins the partner space from a pasted invite link', (tester) async {
    calm(tester);
    final partner = await real(tester, openTestSpace);
    await real(
        tester, () => partner.vault.create(passphrase: passphrase, coupleNames: 'Sam & Alex', startDate: '2021-06-14'));
    final link = partner.vault.buildInviteLink()!;

    final phone = await real(tester, openTestSpace);
    await pumpApp(tester, () async => phone);
    await untilFound(tester, find.text(LockCopy.setupTitle));

    await press(tester, find.text(LockCopy.segmentJoin));
    expect(find.text(LockCopy.joinTitle), findsOneWidget);
    expect(find.text(LockCopy.joinIntro), findsOneWidget);

    await type(tester, fieldWithHint(LockCopy.joinHint), passphrase);
    await press(tester, find.text(LockCopy.joinButton));
    expect(find.text(LockCopy.pasteInvite), findsOneWidget);

    await type(tester, fieldWithHint(LockCopy.inviteHint), link);
    expect(find.text(LockCopy.inviteFound), findsOneWidget);

    await press(tester, find.text(LockCopy.joinButton));
    await until(tester, () => phone.vault.isUnlocked);
    await untilFound(tester, find.byType(HomeShell));

    expect(phone.vault.salt, partner.vault.salt);
    expect(phone.vault.config!.coupleNames, 'Sam & Alex');
    expect(find.text(LockCopy.joinedUnverified), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(VaultWarningBanner), matching: labelled(VaultWarningBanner.dismissLabel)));
    await tester.pump();
    expect(find.text(LockCopy.joinedUnverified), findsNothing);
  });

  testWidgets('erasing an existing space needs the typed phrase and offers a rescue copy', (tester) async {
    calm(tester);
    final space = await real(tester, openTestSpace);
    await real(tester, () => space.vault.create(passphrase: passphrase, iterations: fastIterations));
    space.vault.lock();
    BackupFile? saved;
    VaultFiles.saver = (file) async {
      saved = file;
      return true;
    };

    await pumpApp(tester, () async => space);
    await untilFound(tester, find.text(LockCopy.unlockIntro));
    await press(tester, find.text(LockCopy.moreWays));
    await tester.pump(const Duration(milliseconds: 500));
    await press(tester, find.text(LockCopy.moreStartOver));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('THIS ERASES EVERYTHING ON THIS PHONE'), findsOneWidget);
    await type(tester, fieldWithHint(LockCopy.setupHint), 'a brand new shared passphrase');
    expect(enabledButton(tester, LockCopy.replaceButton), isFalse);

    await type(tester, fieldWithHint(LockCopy.saveFirstHint), 'short');
    await press(tester, find.text(LockCopy.saveFirstButton));
    expect(find.text('Pick a passphrase with at least 16 characters.'), findsOneWidget);

    await type(tester, fieldWithHint(LockCopy.saveFirstHint), 'a rescue passphrase for the file');
    await press(tester, find.text(LockCopy.saveFirstButton));
    await untilFound(tester, find.text('Saved. That passphrase opens it.'));
    expect(saved?.fileName, startsWith('our-space-rescue-'));

    await type(tester, fieldWithHint(destroyConfirmationPhrase), 'erase our memories');
    expect(enabledButton(tester, LockCopy.replaceButton), isTrue);
    final oldSalt = space.vault.salt;
    await press(tester, find.text(LockCopy.replaceButton));
    await until(tester, () => space.vault.isUnlocked);
    expect(space.vault.salt, isNot(oldSalt));
    await untilFound(tester, find.byKey(ShellKeys.dock));
    await drain(tester);
  });

  testWidgets('brings a saved copy back onto an empty phone', (tester) async {
    calm(tester);
    final source = await real(tester, openTestSpace);
    await real(tester, () => source.vault.create(passphrase: passphrase, iterations: fastIterations));
    await real(tester, () => source.milestones.add(title: 'First date', date: '2021-06-14'));
    final file = await real(tester, () => source.backup.exportRescueBackup(passphrase));
    VaultFiles.picker = () async => PickedVaultFile(
          name: file.fileName,
          size: file.contents.length,
          bytes: Uint8List.fromList(utf8.encode(file.contents)),
        );

    final phone = await real(tester, openTestSpace);
    await pumpApp(tester, () async => phone);
    await untilFound(tester, find.text(LockCopy.setupTitle));
    await press(tester, find.text(LockCopy.moreRestore));
    expect(find.text(LockCopy.restoreTitle), findsOneWidget);

    await press(tester, find.text(LockCopy.chooseFile));
    await untilFound(tester, find.text(file.fileName));
    await type(tester, fieldWithHint(LockCopy.filePassphraseHint), passphrase);
    await press(tester, find.text(LockCopy.openFile));
    await untilFound(tester, find.text(LockCopy.restoreButton));
    expect(find.text(LockCopy.nothingToReplace), findsOneWidget);

    await press(tester, find.text(LockCopy.restoreButton));
    await until(tester, () => phone.vault.isUnlocked);
    await untilFound(tester, find.byType(HomeShell));
    expect(phone.vault.salt, source.vault.salt);
    final restored = await real(tester, () => phone.milestones.list());
    expect(restored.map((m) => m.title), ['First date']);
  });

  testWidgets('the shell shows warnings and notices, and locking closes settings', (tester) async {
    calm(tester);
    final space = await real(tester, openTestSpace);
    await real(
        tester, () => space.vault.create(passphrase: passphrase, coupleNames: 'Us two', iterations: fastIterations));
    await pumpApp(tester, () async => space);
    await untilFound(tester, find.byType(HomeShell));
    await untilFound(tester, find.text('Already did this on the other phone'));
    await press(tester, find.text('Already did this on the other phone'));
    expect(find.byKey(ShellKeys.dock), findsOneWidget);

    space.mailbox.onWarning!('clock_skew', 'Your phone clock looks a little off.');
    await tester.pump();
    expect(inNotices('Your phone clock looks a little off.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 8));
    expect(find.text('Your phone clock looks a little off.'), findsNothing);

    final toast = inNotices('Saved. Your partner will see it the moment you two connect.');
    unawaited(space.sync.sendLoveBurst());
    await untilFound(tester, toast);
    await tester.pump(const Duration(seconds: 5));
    expect(toast, findsNothing);

    await openSettingsPage(tester);
    expect(find.text('Us two'), findsOneWidget);
    await press(tester, find.byKey(SettingsPage.phonesKey));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Open Our Space on the other phone, then scan this code or send them your link.'), findsOneWidget);

    space.mailbox.onWarning!('clock_skew', 'Your phone clock looks a little off.');
    space.vault.lock();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Open Our Space on the other phone, then scan this code or send them your link.'), findsNothing);
    expect(find.byType(SettingsPage), findsNothing);
    expect(find.text('Locked'), findsOneWidget);
    final notices = tester.element(find.byType(LockScreen)).read<AppNotices>();
    expect(notices.syncWarning, isNull);
  });

  testWidgets('app lifecycle tells the engine when she leaves and comes back', (tester) async {
    calm(tester);
    final space = await real(tester, openTestSpace);
    await pumpApp(tester, () async => space);
    await untilFound(tester, find.text(LockCopy.setupTitle));
    expect(space.identity.appInForeground, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(space.identity.appInForeground, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(space.identity.appInForeground, isTrue);
  });

  test('partner presence starts unknown until the partner has been seen', () async {
    final space = await openTestSpace();
    expect(partnerPresenceFor(space.identity).kind, PresenceKind.unknown);
    expect(partnerPresenceFor(space.identity).label, isNull);
    await space.close();
  });
}
