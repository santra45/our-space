import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/main.dart';
import 'package:our_space_mobile/presentation/files/vault_files.dart';
import 'package:our_space_mobile/presentation/home_shell.dart';
import 'package:our_space_mobile/presentation/screens/lock/lock_screen.dart';
import 'package:our_space_mobile/presentation/space_scope.dart';
import 'package:our_space_mobile/presentation/vault_gate.dart';
import 'package:our_space_mobile/presentation/widgets/our_widgets.dart';

import '../support/harness.dart';
import '../widgets/harness.dart' show recordHaptics, recordedHaptics, usePhoneSize;

const String passphrase = 'correct horse battery staple 2026';
const int fastIterations = 1000;

Future<OurSpace> openTestSpace() {
  final dir = Directory.systemTemp.createTempSync('our_space_app_');
  return OurSpace.open(
    databaseFactory: testDatabaseFactory(),
    databasePath: '${dir.path}${Platform.pathSeparator}space.sqlite',
    useEnvironmentMailbox: false,
    autoSync: false,
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

Finder fieldWithHint(String hint) => find.descendant(
      of: find.byWidgetPredicate((widget) => widget is OurTextField && widget.hint == hint),
      matching: find.byType(TextField),
    );

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

bool enabledButton(WidgetTester tester, String label) {
  final button = tester.widget<BouncyButton>(find.ancestor(of: find.text(label), matching: find.byType(BouncyButton)));
  return button.isEnabled;
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
    await untilFound(tester, find.text('Setup Your Private Space'));

    expect(find.text('Create New Space'), findsOneWidget);
    expect(find.text('Join Partner\'s Space'), findsOneWidget);
    expect(find.text('This makes a brand-new, empty space.'), findsOneWidget);
    expect(find.text('Locked with your passphrase. Only you two can open it.'), findsOneWidget);
    expect(find.text('Bring back a copy you saved'), findsOneWidget);

    await type(tester, fieldWithHint('e.g. Romeo & Juliet'), 'Sam & Alex');
    await type(tester, fieldWithHint('Create a shared secret phrase (min 16 chars)...'), 'too short');
    await press(tester, find.text('Create a New Space 💕'));
    expect(
      find.text('Please choose a memorable secret passphrase of at least 16 characters.'),
      findsOneWidget,
    );

    await type(tester, fieldWithHint('Create a shared secret phrase (min 16 chars)...'), passphrase);
    await press(tester, find.text('Create a New Space 💕'));
    await until(tester, () => space.vault.isUnlocked);
    await untilFound(tester, find.byType(HomeShell));

    expect(find.text('Sam & Alex'), findsOneWidget);
    for (final label in ['Love', 'Memories', 'Dates', 'Letters', 'Bucket']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Just for us 💕'), findsOneWidget);
    expect(recordedHaptics, contains(HapticKind.celebration));
    expect(space.vault.config!.coupleNames, 'Sam & Alex');

    await tester.tap(find.byType(HeaderLockButton));
    await tester.pump();
    await tester.pump();
    expect(space.vault.isUnlocked, isFalse);
    expect(find.text('Locked'), findsOneWidget);
    expect(find.text('Enter the passphrase you two share to open your memories and notes.'), findsOneWidget);
    expect(enabledButton(tester, 'Unlock Our Space 💕'), isFalse);

    final unlockField = fieldWithHint('Enter your secret passphrase (min 16 chars)...');
    await type(tester, unlockField, 'short one');
    await press(tester, find.text('Unlock Our Space 💕'));
    expect(find.text('Passphrase must be at least 16 characters.'), findsOneWidget);

    await type(tester, unlockField, 'this is not the passphrase at all');
    await press(tester, find.text('Unlock Our Space 💕'));
    await untilFound(tester, find.text('Incorrect passphrase! Please double-check and try again.'));
    expect(space.vault.isUnlocked, isFalse);

    await type(tester, unlockField, passphrase);
    expect(find.text('Incorrect passphrase! Please double-check and try again.'), findsNothing);
    await press(tester, find.text('Unlock Our Space 💕'));
    await until(tester, () => space.vault.isUnlocked);
    await untilFound(tester, find.byType(HomeShell));
    expect(find.text('Sam & Alex'), findsOneWidget);
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
    await untilFound(tester, find.text('Something went wrong opening your space'));
    expect(find.text('Nothing was lost — try again.'), findsOneWidget);
    expect(find.textContaining('disk said no'), findsNothing);

    await press(tester, find.text('Try again'));
    await untilFound(tester, find.text('Setup Your Private Space'));
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
    await untilFound(tester, find.text('Setup Your Private Space'));

    await press(tester, find.text('Join Partner\'s Space'));
    expect(find.text('Join Partner\'s Space 💕'), findsOneWidget);
    expect(find.text('Use your partner’s invite link to join their space.'), findsOneWidget);

    await type(tester, fieldWithHint('Enter the secret phrase you both agreed on...'), passphrase);
    await press(tester, find.text('Pair & Enter Our Space 💕'));
    expect(
      find.text('Please paste your partner’s invite link — the one they sent you, or the QR code you scanned.'),
      findsOneWidget,
    );

    await type(tester, fieldWithHint('Paste link (e.g. https://...#connect=...)'), link);
    expect(find.text('Found your partner\'s invite! Enter the passphrase you both chose.'), findsOneWidget);

    await press(tester, find.text('Pair & Enter Our Space 💕'));
    await until(tester, () => phone.vault.isUnlocked);
    await untilFound(tester, find.byType(HomeShell));

    expect(phone.vault.salt, partner.vault.salt);
    expect(find.text('Sam & Alex'), findsOneWidget);
    expect(find.text(VaultMessages.pairedUnverified), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(VaultWarningBanner), matching: find.byType(GestureDetector)).last);
    await tester.pump();
    expect(find.text(VaultMessages.pairedUnverified), findsNothing);
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
    await untilFound(tester, find.text('Locked'));
    await press(tester, find.text('Start over with a brand new space (erases this one)'));

    expect(find.text('THIS ERASES EVERYTHING ON THIS PHONE'), findsOneWidget);
    await type(
        tester, fieldWithHint('Create a shared secret phrase (min 16 chars)...'), 'a brand new shared passphrase');
    expect(enabledButton(tester, 'Erase & Start Fresh'), isFalse);

    await type(tester, fieldWithHint('Passphrase for this file (at least 16)'), 'short');
    await press(tester, find.text('Save a copy'));
    expect(find.text('Pick a passphrase with at least 16 characters.'), findsOneWidget);

    await type(tester, fieldWithHint('Passphrase for this file (at least 16)'), 'a rescue passphrase for the file');
    await press(tester, find.text('Save a copy'));
    await untilFound(tester, find.text('Saved. That passphrase opens it. 💕'));
    expect(saved?.fileName, startsWith('our-space-rescue-'));

    await type(tester, fieldWithHint(destroyConfirmationPhrase), 'erase our memories');
    expect(enabledButton(tester, 'Erase & Start Fresh'), isTrue);
    final oldSalt = space.vault.salt;
    await press(tester, find.text('Erase & Start Fresh'));
    await until(tester, () => space.vault.isUnlocked);
    expect(space.vault.salt, isNot(oldSalt));
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
    await untilFound(tester, find.text('Setup Your Private Space'));
    await press(tester, find.text('Bring back a copy you saved'));
    expect(find.text('Bring back a saved copy'), findsOneWidget);

    await press(tester, find.text('Choose the file you saved'));
    await untilFound(tester, find.text(file.fileName));
    await type(tester, fieldWithHint('Passphrase for this file'), passphrase);
    await press(tester, find.text('Open this file'));
    await untilFound(tester, find.text('Bring everything back'));
    expect(
      find.text(
        'There is nothing here to replace. Anything left over from an older space on this phone is tidied away first — it cannot be opened any more anyway.',
      ),
      findsOneWidget,
    );

    await press(tester, find.text('Bring everything back'));
    await until(tester, () => phone.vault.isUnlocked);
    await untilFound(tester, find.byType(HomeShell));
    expect(phone.vault.salt, source.vault.salt);
    final restored = await real(tester, () => phone.milestones.list());
    expect(restored.map((m) => m.title), ['First date']);
  });

  testWidgets('header shows sync warnings and notices, and locking closes open sheets', (tester) async {
    calm(tester);
    final space = await real(tester, openTestSpace);
    await real(
        tester, () => space.vault.create(passphrase: passphrase, coupleNames: 'Us two', iterations: fastIterations));
    await pumpApp(tester, () async => space);
    await untilFound(tester, find.byType(HomeShell));
    expect(find.text('Us two'), findsOneWidget);

    space.mailbox.onWarning!('clock_skew', 'Your phone clock looks a little off.');
    await tester.pump();
    expect(
      find.descendant(of: find.byType(OurHeader), matching: find.text('Your phone clock looks a little off.')),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 8));
    expect(find.text('Your phone clock looks a little off.'), findsNothing);

    final toast = find.descendant(
      of: find.byType(OurHeader),
      matching: find.text('Saved 💕 your partner will see it the moment you two connect.'),
    );
    unawaited(space.sync.sendLoveBurst());
    await untilFound(tester, toast);
    await tester.pump(const Duration(seconds: 5));
    expect(toast, findsNothing);

    await tester.tap(find.byType(SyncStatusPill));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Pair & Sync Hub'), findsOneWidget);

    space.mailbox.onWarning!('clock_skew', 'Your phone clock looks a little off.');
    space.vault.lock();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Pair & Sync Hub'), findsNothing);
    expect(find.text('Locked'), findsOneWidget);
    final notices = tester.element(find.byType(LockScreen)).read<AppNotices>();
    expect(notices.syncWarning, isNull);
  });

  testWidgets('app lifecycle tells the engine when she leaves and comes back', (tester) async {
    calm(tester);
    final space = await real(tester, openTestSpace);
    await pumpApp(tester, () async => space);
    await untilFound(tester, find.text('Setup Your Private Space'));
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

  test('header presence follows the partner last-seen time like the web', () async {
    final space = await openTestSpace();
    expect(headerPresenceFor(space.identity).text, 'Just for us 💕');
    await space.close();
  });
}
