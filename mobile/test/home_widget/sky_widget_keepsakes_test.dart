import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/main.dart';
import 'package:our_space_mobile/presentation/home_shell.dart';
import 'package:our_space_mobile/presentation/home_widget/sky_widget_host.dart';
import 'package:our_space_mobile/presentation/screens/sky/sky_page.dart';
import 'package:our_space_mobile/presentation/screens/sky/together/sky_drawn_map.dart';
import 'package:our_space_mobile/presentation/screens/sky/together/sky_keepsakes.dart';
import 'package:our_space_mobile/presentation/sky/sky.dart';

import '../screens/love/love_harness.dart';
import '../screens/sky/together/sky_keepsakes_home_test.dart' show daysAgo, drew;
import '../support/harness.dart';
import 'sky_widget_host_test.dart' show RecordingHost, StubArt;

const List<String> secrets = ['Moonlit paper kite', 'Our secret chai'];

Future<void> quietly(WidgetTester tester, {int rounds = 10}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
}

void main() {
  testWidgets('the ones we drew show on home and in the map, yet the widget and everything outside the vault never hear of them', (
    tester,
  ) async {
    calm(tester);
    final dir = Directory.systemTemp.createTempSync('our_space_drawn_');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });
    final space = await real(
      tester,
      () => OurSpace.open(
        databaseFactory: testDatabaseFactory(),
        databasePath: '${dir.path}${Platform.pathSeparator}space.sqlite',
        useEnvironmentMailbox: false,
        autoSync: false,
      ),
    );
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
    await bothAnswered(tester, space, 3);
    await drew(tester, space, secrets[0], at: daysAgo(2));

    final host = RecordingHost();
    await nightSky(tester, space);
    await tester.pumpWidget(
      OurSpaceApp(
        openSpace: () async => space,
        shell: const HomeShell(),
        skyWidget: SkyWidgetPublisher(host: host, art: const StubArt()),
      ),
    );
    await untilFound(tester, find.byType(HomeShell));
    await tester.pump(SkyMotion.dayNight);
    await untilFound(tester, find.byKey(SkyPageKeys.starsStat));
    await until(tester, () => find.byType(SkyKeepsakeMark).evaluate().length == 1 && host.updates > 0);
    await quietly(tester);
    final saved = Map<String, Object?>.of(host.saved);
    final images = Map.of(host.images);
    final updates = host.updates;
    expect(saved, isNotEmpty);

    await drew(tester, space, secrets[1], at: daysAgo(1));
    await until(tester, () => find.byType(SkyKeepsakeMark).evaluate().length == 2);
    await tester.tap(find.byKey(SkyPageKeys.starsStat));
    await settleRoute(tester);
    await until(tester, () => find.byType(SkyDrawnTile).evaluate().length == 2);
    await quietly(tester);

    expect(host.updates, updates);
    expect(host.saved, saved);
    expect(host.images.keys, images.keys);
    for (final value in host.saved.values) {
      for (final secret in secrets) {
        expect('$value'.toLowerCase().contains(secret.toLowerCase()), isFalse, reason: '$value');
        expect('$value'.contains('kite') || '$value'.contains('chai'), isFalse, reason: '$value');
      }
    }

    await tester.pumpWidget(const SizedBox());
    await quietly(tester, rounds: 25);

    var plain = false;
    for (final file in dir.listSync(recursive: true).whereType<File>()) {
      final text = latin1.decode(file.readAsBytesSync());
      plain = plain || text.contains(SkyModeController.followsTimeKey);
      for (final secret in secrets) {
        expect(text.contains(secret), isFalse, reason: '${file.path} holds "$secret" in the open');
        expect(text.contains(String.fromCharCodes(utf8.encode(secret))), isFalse);
      }
    }
    expect(plain, isTrue, reason: 'the open settings were read from disk');
  });
}
