import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/main.dart';
import 'package:our_space_mobile/presentation/home_shell.dart';
import 'package:our_space_mobile/presentation/sky/sky.dart';
import 'package:our_space_mobile/presentation/widgets/our_widgets.dart';

import '../../support/harness.dart';
import '../../widgets/harness.dart' show usePhoneSize;

const String passphrase = 'correct horse battery staple 2026';
const String otherPassphrase = 'a completely different passphrase';
const int fastIterations = 1000;
const String startDate = '2021-06-14';

Future<OurSpace> openLoveSpace() {
  final dir = Directory.systemTemp.createTempSync('our_space_love_');
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

Future<void> settle(WidgetTester tester, OurSpace space) async {
  await drive(tester, space.milestones.list);
  await tester.pump();
}

Future<void> untilFound(WidgetTester tester, Finder finder) => until(tester, () => finder.evaluate().isNotEmpty);

Future<void> untilGone(WidgetTester tester, Finder finder) => until(tester, () => finder.evaluate().isEmpty);

Finder fieldWithHint(String hint) => find.descendant(
      of: find.byWidgetPredicate(
        (widget) => (widget is OurTextField && widget.hint == hint) || (widget is SkyTextField && widget.hint == hint),
      ),
      matching: find.byType(TextField),
    );

Finder iconButton(String label) => find.byWidgetPredicate(
      (widget) =>
          (widget is OurIconButton && widget.semanticLabel == label) ||
          (widget is SkyIconButton && widget.semanticLabel == label),
    );

Finder semanticsLabelled(String label) =>
    find.byWidgetPredicate((widget) => widget is Semantics && widget.properties.label == label);

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

Future<void> settleRoute(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

bool buttonEnabled(WidgetTester tester, String label) {
  final sky = find.ancestor(of: find.text(label), matching: find.byType(SkyButton));
  if (sky.evaluate().isNotEmpty) return tester.widget<SkyButton>(sky).enabled;
  final button = tester.widget<BouncyButton>(find.ancestor(of: find.text(label), matching: find.byType(BouncyButton)));
  return button.isEnabled;
}

void calm(WidgetTester tester) {
  usePhoneSize(tester);
  tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
    disableAnimations: true,
    reduceMotion: true,
  );
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

Future<OurSpace> coupleSpace(WidgetTester tester) async {
  final space = await real(tester, openLoveSpace);
  await real(
    tester,
    () => space.vault.create(
      passphrase: passphrase,
      coupleNames: 'Sam & Alex',
      startDate: startDate,
      iterations: fastIterations,
    ),
  );
  await real(tester, () => space.identity.createCouple(myName: 'Sam', partnerName: 'Alex', partnerPronoun: 'she'));
  await real(tester, space.identity.refresh);
  expect(space.identity.status, IdentityStatus.ready);
  expect(space.identity.partnerName, 'Alex');
  return space;
}

Future<VaultKey> strangerKey(WidgetTester tester) async {
  final stranger = await real(tester, openLoveSpace);
  await real(tester, () => stranger.vault.create(passphrase: otherPassphrase, iterations: fastIterations));
  return stranger.vault.requireKey();
}

Future<void> pumpLove(WidgetTester tester, OurSpace space, {Widget? shell}) async {
  await tester.pumpWidget(OurSpaceApp(openSpace: () async => space, shell: shell ?? const HomeShell()));
  await tester.pump();
}

Future<void> nightSky(WidgetTester tester, OurSpace space) =>
    real(tester, () => space.store.settings.setItem(SkyModeController.followsTimeKey, '0'));

Future<void> pumpNight(WidgetTester tester, OurSpace space, {Widget? shell}) async {
  await nightSky(tester, space);
  await pumpLove(tester, space, shell: shell);
  await untilFound(tester, find.byType(shell?.runtimeType ?? HomeShell));
  await tester.pump(SkyMotion.dayNight + const Duration(milliseconds: 100));
}

Future<void> iAnswer(WidgetTester tester, OurSpace space, String text, {int? when}) async {
  final key = space.vault.requireKey();
  final question = space.dailyQuestion.questionForDay(key, when).question.id;
  await drive(
    tester,
    () => space.dailyQuestion.saveAnswer(
      key,
      ownerId: space.identity.myOwnerId,
      ownerIds: space.identity.myOwnerIds,
      questionId: question,
      text: text,
      when: when,
    ),
  );
}

Future<void> bothAnswered(WidgetTester tester, OurSpace space, int days, {int from = 1}) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  for (var i = from; i < from + days; i++) {
    final when = now - i * 86400000;
    await iAnswer(tester, space, 'Mine $i', when: when);
    await partnerAnswers(tester, space, 'Theirs $i', when: when);
  }
}

Future<void> partnerAnswers(
  WidgetTester tester,
  OurSpace space,
  String text, {
  int? when,
  String? questionId,
}) async {
  final key = space.vault.requireKey();
  final partnerId = space.identity.partner!.personId;
  final question = questionId ?? space.dailyQuestion.questionForDay(key, when).question.id;
  await drive(
    tester,
    () => space.dailyQuestion.saveAnswer(key, ownerId: partnerId, questionId: question, text: text, when: when),
  );
}
