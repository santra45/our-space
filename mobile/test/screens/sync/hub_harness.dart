import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/presentation/app_shell.dart';
import 'package:our_space_mobile/presentation/files/vault_files.dart';
import 'package:our_space_mobile/presentation/screens/sync/peer_link.dart';
import 'package:our_space_mobile/presentation/screens/sync/sync_hub.dart';
import 'package:our_space_mobile/presentation/space_scope.dart';
import 'package:our_space_mobile/presentation/widgets/our_widgets.dart';
import 'package:provider/provider.dart';

import '../../support/harness.dart';
import '../../widgets/harness.dart' show usePhoneSize;

const String passphrase = 'correct horse battery staple 2026';
const int fastIterations = 1000;
const String openHubLabel = 'Open hub';

Future<OurSpace> openHubSpace({MailboxConfig? mailbox, http.Client? client, QuickUnlockPlatform? quickUnlock}) async {
  final dir = Directory.systemTemp.createTempSync('our_space_hub_');
  final space = await OurSpace.open(
    databaseFactory: testDatabaseFactory(),
    databasePath: '${dir.path}${Platform.pathSeparator}space.sqlite',
    useEnvironmentMailbox: false,
    mailboxConfig: mailbox,
    httpClient: client,
    autoSync: false,
    quickUnlockPlatform: quickUnlock,
  );
  await space.store.settings.setItem(DeviceIdentity.peerIdKey, space.device.peerId);
  return space;
}

Future<OurSpace> openUnlockedSpace(
  WidgetTester tester, {
  String coupleNames = 'Sam & Alex',
  String startDate = '2021-06-14',
  MailboxConfig? mailbox,
  http.Client? client,
  QuickUnlockPlatform? quickUnlock,
}) async {
  final space = await real(tester, () => openHubSpace(mailbox: mailbox, client: client, quickUnlock: quickUnlock));
  await real(
    tester,
    () => space.vault.create(
      passphrase: passphrase,
      coupleNames: coupleNames,
      startDate: startDate,
      iterations: fastIterations,
    ),
  );
  return space;
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

Future<void> settleIdentity(WidgetTester tester, OurSpace space) => until(
    tester, () => space.identity.status != IdentityStatus.loading && space.identity.status != IdentityStatus.locked);

const double testFontToRealWidth = 0.6;

void calm(WidgetTester tester) {
  usePhoneSize(tester);
  tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
    disableAnimations: true,
    reduceMotion: true,
  );
  tester.platformDispatcher.textScaleFactorTestValue = testFontToRealWidth;
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<void> settle(WidgetTester tester, {int rounds = 10}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 500));
}

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
  await tester.pump(const Duration(milliseconds: 500));
}

class FakePeerLink extends PeerLink {
  FakePeerLink([this._state = PeerLinkView.offline]);

  PeerLinkView _state;
  final List<String> calls = [];

  @override
  PeerLinkView get state => _state;

  set state(PeerLinkView next) {
    _state = next;
    notifyListeners();
  }

  @override
  void connect(String partnerPeerId) => calls.add('connect:$partnerPeerId');

  @override
  void reconnect() => calls.add('reconnect');

  @override
  void unpair() => calls.add('unpair');

  @override
  void syncNow() => calls.add('syncNow');

  @override
  void clearError() => calls.add('clearError');

  @override
  void confirmInvite() => calls.add('confirmInvite');

  @override
  void declineInvite() => calls.add('declineInvite');
}

Widget blankTab(BuildContext context, AppTab tab) => const SizedBox.shrink();

class Launcher extends StatelessWidget {
  const Launcher({super.key, this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child ??
          Center(
            child: TextButton(onPressed: () => showSyncHub(context), child: const Text(openHubLabel)),
          ),
    );
  }
}

Widget spaceApp(OurSpace space, {PeerLink? peer, Widget? home}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.lightTheme,
    builder: (context, navigator) {
      Widget child = navigator!;
      if (peer != null) child = ChangeNotifierProvider<PeerLink>.value(value: peer, child: child);
      return SpaceScope(space: space, child: child);
    },
    home: Launcher(child: home),
  );
}

Future<void> openHub(WidgetTester tester, OurSpace space, {PeerLink? peer}) async {
  await tester.pumpWidget(spaceApp(space, peer: peer));
  await tester.pump();
  await settleIdentity(tester, space);
  await tester.tap(find.text(openHubLabel));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  expect(find.text(SyncHubCopy.title), findsOneWidget);
}

PickedVaultFile pickedFrom(BackupFile file) {
  final bytes = Uint8List.fromList(utf8.encode(file.contents));
  return PickedVaultFile(name: file.fileName, size: bytes.length, bytes: bytes);
}

Future<void> closeTopModal(WidgetTester tester) async {
  final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
  navigator.pop();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}
