import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/main.dart';
import 'package:our_space_mobile/presentation/app_shell.dart';
import 'package:our_space_mobile/presentation/deep_links.dart';
import 'package:our_space_mobile/presentation/home_shell.dart';
import 'package:our_space_mobile/presentation/widgets/our_widgets.dart';

import '../../support/fake_mailbox_worker.dart';
import '../../support/harness.dart';
import '../../widgets/harness.dart' show usePhoneSize;

const String passphrase = 'correct horse battery staple 2026';
const String otherPassphrase = 'a different couple and their phrase';
const int fastIterations = 1000;
const String mailboxToken = 'people-mailbox-token-2026';
const MailboxConfig testMailbox = MailboxConfig(
  url: 'https://mailbox.test',
  token: mailboxToken,
  origin: 'https://sameskytonight.vercel.app',
);

Future<OurSpace> openPeopleSpace({FakeMailboxWorker? worker}) {
  final dir = Directory.systemTemp.createTempSync('our_space_people_');
  return OurSpace.open(
    databaseFactory: testDatabaseFactory(),
    databasePath: '${dir.path}${Platform.pathSeparator}space.sqlite',
    mailboxConfig: worker == null ? null : testMailbox,
    useEnvironmentMailbox: false,
    httpClient: worker,
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

Future<void> settleIdentity(WidgetTester tester, OurSpace space) => real(tester, () async {
      while (space.identity.status == IdentityStatus.loading || space.identity.status == IdentityStatus.locked) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });

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

BouncyButton buttonLabelled(WidgetTester tester, String label) =>
    tester.widget<BouncyButton>(find.ancestor(of: find.text(label), matching: find.byType(BouncyButton)));

void calm(WidgetTester tester) {
  usePhoneSize(tester);
  tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
    disableAnimations: true,
    reduceMotion: true,
  );
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

Widget blankTab(BuildContext context, SkyTab tab) => const SizedBox.shrink();

Future<void> pumpOurSpace(WidgetTester tester, OurSpace space, {InviteInbox? inbox}) async {
  final links = inbox ?? InviteInbox();
  await tester.pumpWidget(OurSpaceApp(
    openSpace: () async => space,
    gate: (context, shell) => InviteLinkGate(shell: shell, inbox: links),
    shell: const HomeShell(pageBuilder: blankTab),
  ));
  await tester.pump();
}
