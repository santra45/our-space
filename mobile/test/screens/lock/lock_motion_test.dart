import 'dart:async';
import 'dart:typed_data';

import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/presentation/screens/lock/lock_screen.dart';
import 'package:our_space_mobile/presentation/sky/sky.dart';
import 'package:our_space_mobile/presentation/widgets/app_haptics.dart';

import '../../support/fake_quick_unlock.dart';
import '../../widgets/harness.dart' show recordHaptics, recordedHaptics, usePhoneSize;
import 'lock_harness.dart';

class SlowQuickUnlock extends FakeQuickUnlock {
  final Completer<void> gate = Completer<void>();

  @override
  Future<Uint8List> open(SealedSecret sealed, Uint8List aad, QuickUnlockPrompt prompt) async {
    await gate.future;
    return super.open(sealed, aad, prompt);
  }
}

HeartConstellation? heartOf(WidgetTester tester) => tester.widget<SkyCanvas>(find.byType(SkyCanvas)).scene.heart;

Future<OurSpace> lockedSpace(WidgetTester tester, {FakeQuickUnlock? quick}) async {
  final space = await lockReal(tester, () => openLockSpace(quickUnlock: quick));
  await lockReal(tester, () async {
    await space.vault.create(passphrase: lockPassphrase, iterations: lockIterations);
    if (quick != null) {
      await space.quickUnlock.refresh();
      expect((await space.quickUnlock.enable(lockPassphrase)).ok, isTrue);
    }
  });
  space.vault.lock();
  return space;
}

Future<void> frames(WidgetTester tester, Duration total) async {
  const step = Duration(milliseconds: 50);
  for (var spent = Duration.zero; spent < total; spent += step) {
    await tester.pump(step);
  }
}

void main() {
  setUp(recordHaptics);

  testWidgets('changing how she opens it slides on a shared axis with a light tick', (tester) async {
    usePhoneSize(tester);
    final space = await lockedSpace(tester, quick: FakeQuickUnlock());
    await pumpLock(tester, space);
    await lockUntilFound(tester, find.text(LockCopy.quickButton));
    await frames(tester, const Duration(milliseconds: 600));
    expect(find.ancestor(of: find.text(LockCopy.quickButton), matching: find.byType(SkyPressable)), findsOneWidget);

    recordedHaptics.clear();
    await tester.tap(find.text(LockCopy.usePassphrase));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(recordedHaptics, contains(HapticKind.tick));
    expect(find.byType(SharedAxisTransition), findsWidgets);
    expect(find.byType(LockTouchButton), findsOneWidget);
    await frames(tester, const Duration(milliseconds: 600));
    expect(find.byType(LockTouchButton), findsNothing);
    expect(lockField(LockCopy.unlockHint), findsOneWidget);
    await closeLock(tester, space);
  });

  testWidgets('with reduced motion the views swap without sliding', (tester) async {
    calmLock(tester);
    final space = await lockedSpace(tester, quick: FakeQuickUnlock());
    await pumpLock(tester, space);
    await lockUntilFound(tester, find.text(LockCopy.quickButton));
    await tester.tap(find.text(LockCopy.usePassphrase));
    await tester.pump();
    expect(find.byType(SharedAxisTransition), findsNothing);
    expect(find.byType(LockTouchButton), findsNothing);
    expect(lockField(LockCopy.unlockHint), findsOneWidget);
    await closeLock(tester, space);
  });

  testWidgets('the ring shows it is opening while the touch is checked', (tester) async {
    usePhoneSize(tester);
    final fake = SlowQuickUnlock();
    final space = await lockedSpace(tester, quick: fake);
    await pumpLock(tester, space);
    await lockUntilFound(tester, find.text(LockCopy.quickButton));
    expect(
      find.descendant(of: find.byType(LockTouchButton), matching: find.byType(CircularProgressIndicator)),
      findsNothing,
    );

    await tester.tap(find.text(LockCopy.quickButton));
    await tester.pump();
    expect(touchEnabled(tester), isFalse);
    expect(
      find.descendant(of: find.byType(LockTouchButton), matching: find.byType(CircularProgressIndicator)),
      findsOneWidget,
    );
    await frames(tester, const Duration(milliseconds: 200));
    expect(find.text(LockCopy.opening), findsOneWidget);
    expect(space.vault.isUnlocked, isFalse);
    fake.gate.complete();
    await lockUntil(tester, () => space.vault.isUnlocked);
    await closeLock(tester, space);
  });

  testWidgets('the heart fades away behind the longer forms and comes back after', (tester) async {
    usePhoneSize(tester);
    final space = await lockedSpace(tester);
    await pumpLock(tester, space);
    await lockUntilFound(tester, find.text(LockCopy.unlockIntro));
    await frames(tester, const Duration(milliseconds: 600));
    expect(heartOf(tester)!.dim, LockMetrics.heartDim);

    await tester.tap(find.text(LockCopy.moreWays));
    await frames(tester, const Duration(milliseconds: 700));
    expect(find.text(LockCopy.moreTitle), findsOneWidget);
    await tester.tap(find.text(LockCopy.moreStartOver));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final fading = heartOf(tester);
    expect(fading == null || fading.dim < LockMetrics.heartDim, isTrue);
    await frames(tester, const Duration(milliseconds: 700));
    expect(find.text(LockCopy.moreTitle), findsNothing);
    expect(find.text(LockCopy.setupTitle), findsOneWidget);
    expect(heartOf(tester), isNull);

    await lockPress(tester, find.text(LockCopy.goBack));
    await frames(tester, const Duration(milliseconds: 700));
    expect(heartOf(tester)!.dim, LockMetrics.heartDim);
    expect(find.text(LockCopy.unlockIntro), findsOneWidget);
    await closeLock(tester, space);
  });

  testWidgets('switching between starting and joining slides the gold pill across', (tester) async {
    usePhoneSize(tester);
    final space = await lockReal(tester, openLockSpace);
    await pumpLock(tester, space);
    await lockUntilFound(tester, find.text(LockCopy.setupTitle));
    await frames(tester, const Duration(milliseconds: 600));
    final align = find.descendant(of: find.byType(LockSegmented<LockMode>), matching: find.byType(AnimatedAlign));
    expect(tester.widget<AnimatedAlign>(align).alignment, const Alignment(-1, 0));

    await tester.tap(find.text(LockCopy.segmentJoin));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(tester.widget<AnimatedAlign>(align).alignment, const Alignment(1, 0));
    expect(find.byType(SharedAxisTransition), findsWidgets);
    await frames(tester, const Duration(milliseconds: 600));
    expect(find.text(LockCopy.joinTitle), findsOneWidget);
    expect(find.text(LockCopy.setupTitle), findsNothing);
    await closeLock(tester, space);
  });
}
