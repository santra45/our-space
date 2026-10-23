import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/presentation/screens/lock/lock_screen.dart';
import 'package:our_space_mobile/presentation/sky/sky.dart';
import 'package:our_space_mobile/presentation/space_scope.dart';

import '../../support/harness.dart';
import '../../widgets/harness.dart' show usePhoneSize;

const String lockPassphrase = 'correct horse battery staple 2026';
const int lockIterations = 1000;

Future<OurSpace> openLockSpace({QuickUnlockPlatform? quickUnlock}) {
  final dir = Directory.systemTemp.createTempSync('our_space_lock_');
  return OurSpace.open(
    databaseFactory: testDatabaseFactory(),
    databasePath: '${dir.path}${Platform.pathSeparator}space.sqlite',
    useEnvironmentMailbox: false,
    autoSync: false,
    quickUnlockPlatform: quickUnlock,
  );
}

Finder lockField(String hint) => find.descendant(
  of: find.byWidgetPredicate((widget) => widget is LockField && widget.hint == hint),
  matching: find.byType(TextField),
);

SkyButton lockButton(WidgetTester tester, String label) =>
    tester.widget<SkyButton>(find.ancestor(of: find.text(label), matching: find.byType(SkyButton)));

bool lockButtonEnabled(WidgetTester tester, String label) => lockButton(tester, label).enabled;

bool touchEnabled(WidgetTester tester) => tester.widget<LockTouchButton>(find.byType(LockTouchButton)).enabled;

Future<T> lockReal<T>(WidgetTester tester, Future<T> Function() body) async => (await tester.runAsync(body)) as T;

Future<void> lockUntil(WidgetTester tester, bool Function() done, {int tries = 1500}) async {
  for (var i = 0; i < tries && !done(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
  expect(done(), isTrue);
}

Future<void> lockUntilFound(WidgetTester tester, Finder finder) =>
    lockUntil(tester, () => finder.evaluate().isNotEmpty);

Future<void> lockReveal(WidgetTester tester, Finder finder) async {
  unawaited(Scrollable.ensureVisible(tester.element(finder), alignment: 0.5));
  await tester.pump();
}

Future<void> lockType(WidgetTester tester, Finder finder, String text) async {
  await lockReveal(tester, finder);
  await tester.enterText(finder, text);
  await tester.pump();
}

Future<void> lockPress(WidgetTester tester, Finder finder) async {
  await lockReveal(tester, finder);
  await tester.tap(finder);
  await tester.pump();
}

Future<void> lockSettle(WidgetTester tester, {int frames = 6}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void calmLock(WidgetTester tester) {
  usePhoneSize(tester);
  tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
    disableAnimations: true,
    reduceMotion: true,
  );
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

Widget lockApp(OurSpace space, {SkyTokens tokens = SkyTokens.night, Invite? invite, bool installed = false}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: SkyThemes.legacy(tokens),
    home: SpaceScope(
      space: space,
      child: LockScreen(invite: invite, installed: installed),
    ),
  );
}

Future<void> pumpLock(
  WidgetTester tester,
  OurSpace space, {
  SkyTokens tokens = SkyTokens.night,
  Invite? invite,
  bool installed = false,
}) async {
  await tester.pumpWidget(lockApp(space, tokens: tokens, invite: invite, installed: installed));
  await tester.pump();
}

Future<void> closeLock(WidgetTester tester, OurSpace space) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
  await lockReal(tester, space.close);
}
