import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/main.dart';
import 'package:our_space_mobile/presentation/home_shell.dart';
import 'package:our_space_mobile/presentation/widgets/our_widgets.dart';

import '../../support/harness.dart';
import '../../widgets/harness.dart' show recordHaptics, usePhoneSize;

const String testPassphrase = 'correct horse battery staple 2026';

Future<T> real<T>(WidgetTester tester, Future<T> Function() body) async => (await tester.runAsync(body)) as T;

Future<void> until(WidgetTester tester, bool Function() done, {int tries = 1500}) async {
  for (var i = 0; i < tries && !done(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
  expect(done(), isTrue);
}

Future<void> untilFound(WidgetTester tester, Finder finder) => until(tester, () => finder.evaluate().isNotEmpty);

Future<void> untilGone(WidgetTester tester, Finder finder) => until(tester, () => finder.evaluate().isEmpty);

void calm(WidgetTester tester) {
  recordHaptics();
  usePhoneSize(tester);
  tester.view.physicalSize = const Size(1290, 2796);
  tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
    disableAnimations: true,
    reduceMotion: true,
  );
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

Future<OurSpace> openReadySpace() async {
  final dir = Directory.systemTemp.createTempSync('our_space_capsule_');
  final space = await OurSpace.open(
    databaseFactory: testDatabaseFactory(),
    databasePath: '${dir.path}${Platform.pathSeparator}space.sqlite',
    useEnvironmentMailbox: false,
    autoSync: false,
  );
  await space.vault.create(passphrase: testPassphrase, coupleNames: 'Sam & Alex', iterations: 1000);
  await space.identity.createCouple(myName: 'Sam', myPronoun: 'he', partnerName: 'Alex', partnerPronoun: 'she');
  return space;
}

Future<OurSpace> openStrangerSpace() async {
  final dir = Directory.systemTemp.createTempSync('our_space_stranger_');
  final space = await OurSpace.open(
    databaseFactory: testDatabaseFactory(),
    databasePath: '${dir.path}${Platform.pathSeparator}space.sqlite',
    useEnvironmentMailbox: false,
    autoSync: false,
  );
  await space.vault.create(passphrase: 'a completely different passphrase', iterations: 1000);
  return space;
}

Future<void> openTab(WidgetTester tester, OurSpace space, String label) async {
  await tester.pumpWidget(OurSpaceApp(openSpace: () async => space));
  await tester.pump();
  await untilFound(tester, find.byType(HomeShell));
  await tester.tap(find.descendant(of: find.byType(OurBottomNav), matching: find.text(label)));
  await tester.pump();
  await tester.pump();
}

Future<void> settleRoutes(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Finder fieldWithHint(String hint) => find.descendant(
      of: find.byWidgetPredicate((widget) => widget is OurTextField && widget.hint == hint),
      matching: find.byType(TextField),
    );

Finder iconButton(String label) =>
    find.byWidgetPredicate((widget) => widget is OurIconButton && widget.semanticLabel == label);

Future<void> reveal(WidgetTester tester, Finder finder) async {
  unawaited(Scrollable.ensureVisible(tester.element(finder), alignment: 0.5));
  await tester.pump();
}

Future<void> press(WidgetTester tester, Finder finder) async {
  await reveal(tester, finder);
  await tester.tap(finder);
  await tester.pump();
}

Future<void> typeInto(WidgetTester tester, Finder finder, String text) async {
  await reveal(tester, finder);
  await tester.enterText(finder, text);
  await tester.pump();
}

bool buttonEnabled(WidgetTester tester, String label) {
  final button = tester.widget<BouncyButton>(find.ancestor(of: find.text(label), matching: find.byType(BouncyButton)));
  return button.isEnabled;
}

String inDays(int days) => toLocalDateInput(DateTime.now().add(Duration(days: days)));
