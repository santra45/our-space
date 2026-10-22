import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/main.dart';
import 'package:our_space_mobile/presentation/app_shell.dart';
import 'package:our_space_mobile/presentation/home_shell.dart';
import 'package:our_space_mobile/presentation/screens/countdown/live_love_counter.dart';
import 'package:our_space_mobile/presentation/screens/us/us_page.dart';
import 'package:our_space_mobile/presentation/sky/sky.dart';

import '../../support/harness.dart';
import '../../widgets/harness.dart' show recordHaptics, usePhoneSize;

export '../../widgets/harness.dart' show recordedHaptics;

const String usPassphrase = 'correct horse battery staple 2026';
const String strangerPassphrase = 'a completely different passphrase';
const String usStartDate = '2021-06-14';

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

Future<T> drive<T>(WidgetTester tester, Future<T> Function() body) async {
  late T value;
  Object? failure;
  var done = false;
  body().then(
    (result) {
      value = result;
      done = true;
    },
    onError: (Object error) {
      failure = error;
      done = true;
    },
  );
  await until(tester, () => done);
  if (failure != null) throw failure!;
  return value;
}

void calm(WidgetTester tester) {
  recordHaptics();
  usePhoneSize(tester);
  tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
    disableAnimations: true,
    reduceMotion: true,
  );
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

Future<OurSpace> _openSpace(String prefix) {
  final dir = Directory.systemTemp.createTempSync(prefix);
  return OurSpace.open(
    databaseFactory: testDatabaseFactory(),
    databasePath: '${dir.path}${Platform.pathSeparator}space.sqlite',
    useEnvironmentMailbox: false,
    autoSync: false,
  );
}

Future<OurSpace> usSpace(WidgetTester tester, {String startDate = usStartDate}) async {
  final space = await real(tester, () => _openSpace('our_space_us_'));
  await real(
    tester,
    () => space.vault.create(
      passphrase: usPassphrase,
      coupleNames: 'Sam & Alex',
      startDate: startDate,
      iterations: 1000,
    ),
  );
  await real(
    tester,
    () => space.identity.createCouple(myName: 'Sam', myPronoun: 'he', partnerName: 'Alex', partnerPronoun: 'she'),
  );
  await real(tester, space.identity.refresh);
  return space;
}

Future<OurSpace> strangerSpace(WidgetTester tester) async {
  final space = await real(tester, () => _openSpace('our_space_us_stranger_'));
  await real(tester, () => space.vault.create(passphrase: strangerPassphrase, iterations: 1000));
  return space;
}

Widget usShell({UsSection section = UsSection.story, LoveClock? clock, bool day = false}) {
  return HomeShell(
    initialTab: SkyTab.us,
    pageBuilder: (context, tab) {
      if (tab != SkyTab.us) return skyTabPage(context, tab);
      final page = UsPage(initialSection: section, clock: clock);
      if (!day) return page;
      return Theme(data: SkyThemes.legacy(SkyTokens.day), child: page);
    },
  );
}

Future<void> pumpUs(
  WidgetTester tester,
  OurSpace space, {
  UsSection section = UsSection.story,
  LoveClock? clock,
  bool day = false,
}) async {
  await real(tester, () => space.store.settings.setItem(SkyModeController.followsTimeKey, '0'));
  await tester.pumpWidget(
    OurSpaceApp(
      openSpace: () async => space,
      shell: usShell(section: section, clock: clock, day: day),
    ),
  );
  await tester.pump();
  await untilFound(tester, find.byType(UsPage));
  await tester.pump(SkyMotion.dayNight + const Duration(milliseconds: 100));
}

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

Future<void> settleRoutes(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> pressAndSettle(WidgetTester tester, Finder finder) async {
  await press(tester, finder);
  await settleRoutes(tester);
}

Finder labelled(String label) =>
    find.byWidgetPredicate((widget) => widget is Semantics && widget.properties.label == label);

Finder fieldIn(Key key) => find.descendant(of: find.byKey(key), matching: find.byType(TextField));

Finder within(Finder parent, Finder child) => find.descendant(of: parent, matching: child);

Finder inSheet(Finder child) => find.descendant(of: find.byType(SkySheet), matching: child);

String fieldText(WidgetTester tester, Key key) => tester.widget<TextField>(fieldIn(key)).controller?.text ?? '';

bool buttonEnabled(WidgetTester tester, Key key) => tester.widget<SkyButton>(find.byKey(key)).enabled;

Future<void> pickDay(WidgetTester tester, Key field, String day) async {
  await pressAndSettle(tester, find.byKey(field));
  await tester.tap(find.descendant(of: find.byType(DatePickerDialog), matching: find.text(day)));
  await tester.pump();
  await tester.tap(find.text('OK'));
  await settleRoutes(tester);
}

Future<void> rest(WidgetTester tester, OurSpace space) async {
  await drive(tester, space.milestones.list);
  await tester.pump();
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
}
