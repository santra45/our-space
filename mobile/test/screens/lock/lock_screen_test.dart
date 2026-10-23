import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/presentation/screens/lock/lock_screen.dart';
import 'package:our_space_mobile/presentation/sky/sky.dart';

import '../../support/fake_quick_unlock.dart';
import '../../widgets/harness.dart' show recordHaptics;
import 'lock_harness.dart';

Finder labelled(String label) =>
    find.byWidgetPredicate((widget) => widget is Semantics && widget.properties.label == label);

SkyScene skyOf(WidgetTester tester) => tester.widget<SkyCanvas>(find.byType(SkyCanvas)).scene;

Future<OurSpace> lockedSpace(WidgetTester tester, {FakeQuickUnlock? quick}) async {
  final space = await lockReal(tester, () => openLockSpace(quickUnlock: quick));
  await lockReal(tester, () async {
    await space.vault.create(passphrase: lockPassphrase, coupleNames: 'Qalbi & Farhu', iterations: lockIterations);
    if (quick != null) {
      await space.quickUnlock.refresh();
      expect((await space.quickUnlock.enable(lockPassphrase)).ok, isTrue);
    }
  });
  space.vault.lock();
  return space;
}

void main() {
  setUp(recordHaptics);

  testWidgets('the touch view follows the drawing at night', (tester) async {
    calmLock(tester);
    final space = await lockedSpace(tester, quick: FakeQuickUnlock());
    await pumpLock(tester, space);
    await lockUntilFound(tester, find.text(LockCopy.quickButton));

    final weekday = DateFormat('EEEE').format(DateTime.now());
    expect(find.text(LockCopy.kicker(night: true, weekday: weekday).toUpperCase()), findsOneWidget);
    expect(find.text(LockCopy.title), findsOneWidget);
    expect(find.text(LockCopy.tagline), findsOneWidget);
    expect(find.byType(LockTouchButton), findsOneWidget);
    expect(find.text(LockCopy.usePassphrase), findsOneWidget);
    expect(labelled(LockCopy.footer), findsOneWidget);
    expect(find.text(LockCopy.moreWays), findsNothing);
    expect(lockField(LockCopy.unlockHint), findsNothing);

    final heart = skyOf(tester).heart!;
    expect(heart.dim, LockMetrics.heartDim);
    expect(heart.presence, isFalse);
    expect(skyOf(tester).moon, isNotNull);
    expect(skyOf(tester).skyline, isNotNull);
    expect(touchEnabled(tester), isTrue);
    await closeLock(tester, space);
  });

  testWidgets('by day the kicker and the ring follow the day sky', (tester) async {
    calmLock(tester);
    final space = await lockedSpace(tester, quick: FakeQuickUnlock());
    await pumpLock(tester, space, tokens: SkyTokens.day);
    await lockUntilFound(tester, find.text(LockCopy.quickButton));

    final weekday = DateFormat('EEEE').format(DateTime.now());
    expect(find.text(LockCopy.kicker(night: false, weekday: weekday).toUpperCase()), findsOneWidget);
    final face = tester
        .widgetList<Container>(find.descendant(of: find.byType(LockTouchButton), matching: find.byType(Container)))
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .firstWhere((d) => d.shape == BoxShape.circle && (d.color != null || d.gradient != null));
    expect(face.color, SkyTokens.white);
    final title = tester.widget<Text>(find.text(LockCopy.title));
    expect(title.style?.color, SkyTokens.day.title);
    await closeLock(tester, space);
  });

  testWidgets('a quick unlock that fails says so softly and the passphrase stays one tap away', (tester) async {
    calmLock(tester);
    final fake = FakeQuickUnlock();
    final space = await lockedSpace(tester, quick: fake);
    await pumpLock(tester, space);
    await lockUntilFound(tester, find.text(LockCopy.quickButton));

    fake.failNext = 'failed';
    await lockPress(tester, find.text(LockCopy.quickButton));
    await lockUntilFound(tester, find.text(QuickUnlockCopy.didNotWork));
    expect(space.vault.isUnlocked, isFalse);
    expect(touchEnabled(tester), isTrue);

    fake.failNext = 'unsupported';
    await lockPress(tester, find.text(LockCopy.quickButton));
    await lockUntilFound(tester, find.text(QuickUnlockCopy.cannot));
    expect(find.text(QuickUnlockCopy.didNotWork), findsNothing);

    await lockPress(tester, find.text(LockCopy.usePassphrase));
    expect(find.text(QuickUnlockCopy.cannot), findsNothing);
    expect(lockField(LockCopy.unlockHint), findsOneWidget);
    expect(find.text(LockCopy.useTouch), findsOneWidget);

    await lockType(tester, lockField(LockCopy.unlockHint), lockPassphrase);
    await lockPress(tester, find.text(LockCopy.unlockButton));
    await lockUntil(tester, () => space.vault.isUnlocked);
    await closeLock(tester, space);
  });

  testWidgets('the passphrase field rises above the keyboard', (tester) async {
    calmLock(tester);
    addTearDown(tester.view.resetViewInsets);
    const keyboard = 320.0;
    final space = await lockedSpace(tester, quick: FakeQuickUnlock());
    await pumpLock(tester, space);
    await lockUntilFound(tester, find.text(LockCopy.quickButton));

    await lockPress(tester, find.text(LockCopy.usePassphrase));
    expect(lockField(LockCopy.unlockHint), findsOneWidget);
    final titleBefore = tester.getRect(find.text(LockCopy.title));

    tester.view.viewInsets = const FakeViewPadding(bottom: keyboard * 3);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final screen = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(tester.getRect(lockField(LockCopy.unlockHint)).bottom, lessThanOrEqualTo(screen - keyboard));
    expect(tester.getRect(find.text(LockCopy.title)), titleBefore);
    await closeLock(tester, space);
  });

  test('the keyboard takes its room from the empty sky, not from the form', () {
    const open = LockMetrics(size: Size(390, 844), topInset: 24, bottomInset: 16);
    const typing = LockMetrics(size: Size(390, 844), topInset: 24, bottomInset: 16, keyboard: 320);
    expect(typing.brandHeight, open.brandHeight);
    expect(typing.bodyMinHeight, open.bodyMinHeight - 320);
    expect(typing.footerGap, SkySpace.lg);
    expect(open.footerGap, 64);
    expect(typing, isNot(open));
  });

  testWidgets('more ways in leads to joining, a saved copy or starting over, and back again', (tester) async {
    calmLock(tester);
    final space = await lockedSpace(tester);
    await pumpLock(tester, space);
    await lockUntilFound(tester, find.text(LockCopy.unlockIntro));

    await lockPress(tester, find.text(LockCopy.moreWays));
    await lockSettle(tester);
    expect(find.text(LockCopy.moreTitle), findsOneWidget);
    expect(find.text(LockCopy.moreJoin), findsOneWidget);
    expect(find.text(LockCopy.moreRestore), findsOneWidget);
    expect(find.text(LockCopy.moreStartOverHint), findsOneWidget);

    await lockPress(tester, find.text(LockCopy.moreJoin));
    await lockSettle(tester);
    expect(find.text(LockCopy.moreTitle), findsNothing);
    expect(find.text(LockCopy.joinTitle), findsOneWidget);
    expect(find.text(LockCopy.dangerLabel.toUpperCase()), findsOneWidget);
    expect(lockField(LockCopy.inviteHint), findsOneWidget);
    expect(lockButtonEnabled(tester, LockCopy.joinButton), isFalse);
    await lockType(tester, lockField(LockCopy.joinHint), lockPassphrase);
    expect(lockButtonEnabled(tester, LockCopy.joinButton), isFalse);
    expect(lockButton(tester, LockCopy.joinButton).variant, SkyButtonVariant.danger);

    await lockPress(tester, find.text(LockCopy.goBack));
    expect(find.text(LockCopy.unlockIntro), findsOneWidget);

    await lockPress(tester, find.text(LockCopy.moreWays));
    await lockSettle(tester);
    await lockPress(tester, find.text(LockCopy.moreRestore));
    await lockSettle(tester);
    expect(find.text(LockCopy.restoreTitle), findsOneWidget);
    expect(find.text(LockCopy.chooseFile), findsOneWidget);
    await lockPress(tester, find.text(LockCopy.cancel));
    expect(find.text(LockCopy.unlockIntro), findsOneWidget);

    await lockPress(tester, find.text(LockCopy.moreWays));
    await lockSettle(tester);
    await lockPress(tester, find.text(LockCopy.moreStartOver));
    await lockSettle(tester);
    expect(find.text(LockCopy.setupTitle), findsOneWidget);
    expect(find.text(LockCopy.dangerLabel.toUpperCase()), findsOneWidget);
    expect(find.text(LockCopy.replaceButton), findsOneWidget);
    expect(find.text(LockCopy.freshTitle), findsNothing);
    expect(find.text(LockCopy.segmentStart), findsNothing);
    await lockPress(tester, find.text(LockCopy.goBack));
    expect(find.text(LockCopy.unlockIntro), findsOneWidget);
    expect(space.vault.isUnlocked, isFalse);
    await closeLock(tester, space);
  });

  testWidgets('an invite for this same space joins safely without erasing anything', (tester) async {
    calmLock(tester);
    final space = await lockedSpace(tester);
    final invite = parseInvite(space.vault.buildInviteLink()!)!;
    await pumpLock(tester, space, invite: invite);
    await lockUntilFound(tester, find.text(LockCopy.inviteHere));
    expect(find.textContaining(LockCopy.inviteElsewhereLead, findRichText: true), findsNothing);

    await lockPress(tester, find.text(LockCopy.moreWays));
    await lockSettle(tester);
    await lockPress(tester, find.text(LockCopy.moreJoin));
    await lockSettle(tester);
    expect(find.text(LockCopy.joinInvited), findsOneWidget);
    expect(find.text(LockCopy.inviteSameSpace), findsOneWidget);
    expect(find.text(LockCopy.dangerLabel.toUpperCase()), findsNothing);
    expect(lockField(LockCopy.inviteHint), findsNothing);

    await lockType(tester, lockField(LockCopy.joinHint), 'too short');
    await lockPress(tester, find.text(LockCopy.joinButton));
    expect(find.text(LockCopy.unlockTooShort()), findsOneWidget);

    await lockType(tester, lockField(LockCopy.joinHint), 'a different passphrase for sure');
    await lockPress(tester, find.text(LockCopy.joinButton));
    await lockUntilFound(tester, find.text(LockCopy.incorrectPassphrase));
    expect(space.vault.isUnlocked, isFalse);
    await closeLock(tester, space);
  });

  testWidgets('an invite for another space warns before anything is replaced', (tester) async {
    calmLock(tester);
    final space = await lockedSpace(tester);
    final invite = parseInvite(buildInviteUrl('love-abc123xyz', 'EBESExQVFhcYGRobHB0eHw=='))!;
    await pumpLock(tester, space, invite: invite);
    await lockUntilFound(tester, find.textContaining(LockCopy.inviteElsewhereLead, findRichText: true));
    expect(find.text(LockCopy.inviteHere), findsNothing);
    expect(skyOf(tester).heart, isNull);
    expect(lockField(LockCopy.unlockHint), findsOneWidget);
    await closeLock(tester, space);
  });

  testWidgets('a fresh phone switches between starting and joining, and picks a start date', (tester) async {
    calmLock(tester);
    final space = await lockReal(tester, openLockSpace);
    await pumpLock(tester, space);
    await lockUntilFound(tester, find.text(LockCopy.setupTitle));
    expect(skyOf(tester).heart, isNull);

    await lockPress(tester, find.text(LockCopy.freshAction));
    expect(find.text(LockCopy.joinTitle), findsOneWidget);
    await lockPress(tester, find.text(LockCopy.segmentStart));
    expect(find.text(LockCopy.setupTitle), findsOneWidget);

    final now = DateTime.now();
    await lockPress(tester, find.text(LockDateField.format(startOfLocalDay(now))));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(DatePickerDialog), matching: find.text('1')).first);
    await tester.pump();
    await tester.tap(find.text('OK'));
    await tester.pump(const Duration(milliseconds: 400));
    final first = DateTime(now.year, now.month, 1);
    expect(find.text(LockDateField.format(first)), findsOneWidget);

    await lockType(tester, lockField(LockCopy.namesHint), 'Qalbi & Farhu');
    await lockType(tester, lockField(LockCopy.setupHint), lockPassphrase);
    await lockPress(tester, find.text(LockCopy.createButton));
    await lockUntil(tester, () => space.vault.isUnlocked);
    expect(space.vault.config!.startDate, toLocalDateInput(first));
    expect(space.vault.config!.coupleNames, 'Qalbi & Farhu');
    await closeLock(tester, space);
  });

  testWidgets('the boot screen waits gently and offers a retry when the space will not open', (tester) async {
    calmLock(tester);
    await tester.pumpWidget(MaterialApp(theme: SkyThemes.legacy(SkyTokens.night), home: const LockScreenBoot()));
    await tester.pump();
    expect(find.text(LockCopy.checking), findsOneWidget);
    expect(find.byType(SkySpinner), findsOneWidget);
    expect(find.text(LockCopy.title), findsOneWidget);

    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: SkyThemes.legacy(SkyTokens.day),
        home: LockScreenBoot(failed: true, onRetry: () => retries++),
      ),
    );
    await tester.pump();
    expect(find.text(LockCopy.unreadableTitle), findsOneWidget);
    expect(find.text(LockCopy.unreadableBody), findsOneWidget);
    await lockPress(tester, find.text(LockCopy.tryAgain));
    expect(retries, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
