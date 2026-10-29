import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/presentation/app_shell.dart';
import 'package:our_space_mobile/presentation/home_shell.dart';
import 'package:our_space_mobile/presentation/screens/sky/sky_map_plan.dart';
import 'package:our_space_mobile/presentation/screens/sky/sky_night_sheet.dart';
import 'package:our_space_mobile/presentation/screens/sky/sky_page.dart';
import 'package:our_space_mobile/presentation/screens/sky/sky_sheet_layout.dart';
import 'package:our_space_mobile/presentation/screens/sky/together/sky_drawn.dart';
import 'package:our_space_mobile/presentation/screens/sky/together/sky_drawn_watch.dart';
import 'package:our_space_mobile/presentation/screens/sky/together/sky_keepsakes.dart';
import 'package:our_space_mobile/presentation/sky/sky.dart';

import '../../../widgets/harness.dart' show recordHaptics, usePhoneSize;
import '../../love/love_harness.dart';

SkyDrawing kite(String owner) {
  SkyDrawnStar star(String id, double x, double y, int at) =>
      SkyDrawnStar(id: id, x: x, y: y, by: owner, at: at, gen: 0);
  return SkyDrawing(
    stars: [star('a', 0.3, 0.1, 1), star('b', 0.6, 0.4, 2), star('c', 0.3, 0.7, 3), star('d', 0.1, 0.4, 4)],
    lines: [
      SkyDrawnLine(from: 'a', to: 'b', by: owner, at: 5, gen: 0),
      SkyDrawnLine(from: 'b', to: 'c', by: owner, at: 6, gen: 0),
      SkyDrawnLine(from: 'c', to: 'd', by: owner, at: 7, gen: 0),
    ],
  );
}

int daysAgo(int days) => DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch;

Future<SkyDrawingRecord> drew(WidgetTester tester, OurSpace space, String name, {required int at}) => real(
  tester,
  () => space.skyDrawings.finish(
    space.vault.requireKey(),
    id: space.skyDrawings.newId(),
    drawing: kite(space.identity.myOwnerId!),
    name: name,
    at: at,
  ),
);

Future<SkyDrawingRecord> stillDrawing(WidgetTester tester, OurSpace space) => real(
  tester,
  () => space.skyDrawings.saveProgress(
    space.vault.requireKey(),
    id: space.skyDrawings.newId(),
    drawing: kite(space.identity.myOwnerId!),
  ),
);

Finder homeMarks() => find.descendant(of: find.byType(OurSkyPage), matching: find.byType(SkyKeepsakeMark));

List<SkyKeepsakeMark> marks(WidgetTester tester) => tester.widgetList<SkyKeepsakeMark>(homeMarks()).toList();

Future<void> untilMarks(WidgetTester tester, int count) => until(tester, () => homeMarks().evaluate().length == count);

Rect onHome(WidgetTester tester, Finder finder) => tester.getRect(finder.first);

bool crosses(Rect a, Rect b) {
  final both = a.intersect(b);
  return both.width > 0.5 && both.height > 0.5;
}

void expectQuietPlaces(WidgetTester tester, {required bool night}) {
  final canvas = onHome(tester, find.byKey(SkyPageKeys.canvas));
  final scene = tester.widget<SkyBackdrop>(find.byKey(SkyPageKeys.canvas)).scene;
  final k = scene.scaleFor(canvas.size);
  final figure = scene.constellation!;
  final top = onHome(tester, find.descendant(of: find.byType(OurSkyPage), matching: find.byType(SkyTopBar)));
  final sheet = onHome(tester, find.byType(SkyPanel));
  final dock = onHome(tester, find.byKey(ShellKeys.dock));
  final body = night ? scene.moon! : SkyKeepsakePlan.sun;
  final named = [
    for (final key in [SkyPageKeys.myName, SkyPageKeys.partnerName, SkyPageKeys.tonightTip, SkyPageKeys.letterTip])
      if (find.byKey(key).evaluate().isNotEmpty) onHome(tester, find.byKey(key)),
  ];
  final shown = marks(tester);
  expect(shown, isNotEmpty);
  for (final mark in shown) {
    final rect = tester.getRect(find.byWidget(mark));
    final why = '${mark.spot.record.name} at $rect';
    expect(canvas.contains(rect.topLeft) && canvas.contains(rect.bottomRight), isTrue, reason: why);
    expect(rect.top, greaterThanOrEqualTo(top.bottom), reason: 'under the top bar: $why');
    expect(rect.bottom, lessThanOrEqualTo(sheet.top), reason: 'above the sheet and stats: $why');
    expect(crosses(rect, dock), isFalse, reason: 'off the dock: $why');
    expect(crosses(rect, canvas.topLeft & Size(canvas.width, 0)), isFalse);
    final heart = Rect.fromPoints(
      canvas.topLeft + figure.bounds.topLeft * k,
      canvas.topLeft + figure.bounds.bottomRight * k,
    );
    expect(crosses(rect, heart.inflate(10 * k)), isFalse, reason: 'off the constellation: $why');
    final centre = canvas.topLeft + body * k;
    final nearest = Offset(centre.dx.clamp(rect.left, rect.right), centre.dy.clamp(rect.top, rect.bottom));
    expect((nearest - centre).distance, greaterThanOrEqualTo((night ? 46 : 44) * k), reason: 'off the moon or sun: $why');
    for (final area in named) {
      expect(crosses(rect, area), isFalse, reason: 'off $area: $why');
    }
    expect(mark.style, night ? SkyDrawnStyle.night : SkyDrawnStyle.day);
  }
}

void main() {
  setUp(recordHaptics);

  testWidgets('by night the four newest ones we drew rest faintly around the heart, clear of everything', (tester) async {
    calm(tester);
    final space = await coupleSpace(tester);
    await bothAnswered(tester, space, 3);
    for (var i = 1; i <= 5; i++) {
      await drew(tester, space, 'Kite $i', at: daysAgo(10 - i));
    }
    final open = await stillDrawing(tester, space);
    await pumpNight(tester, space);
    await untilFound(tester, find.byKey(SkyPageKeys.starsStat));
    await untilMarks(tester, 4);

    expect(marks(tester).map((m) => m.spot.record.name).toSet(), {'Kite 5', 'Kite 4', 'Kite 3', 'Kite 2'});
    expect(marks(tester).any((m) => m.spot.id == open.id), isFalse);
    expect(marks(tester).firstWhere((m) => m.spot.record.name == 'Kite 5').target, 1);
    expectQuietPlaces(tester, night: true);

    final semantics = tester.ensureSemantics();
    expect(find.bySemanticsLabel(RegExp('Kite')), findsNothing);
    semantics.dispose();

    await tester.tapAt(tester.getCenter(find.byWidget(marks(tester).first)));
    await settleRoute(tester);
    expect(find.byType(StarNightSheet), findsNothing);
    expect(find.byKey(SkyMapKeys.page), findsNothing);
    expect(homeMarks(), findsNWidgets(4));
    await settle(tester, space);
  });

  testWidgets('by day on a large phone they show as faint contrails, clear of the sun and the letter that fell', (
    tester,
  ) async {
    calm(tester);
    tester.view.physicalSize = const Size(1290, 2796);
    final space = await coupleSpace(tester);
    await bothAnswered(tester, space, 2);
    await drew(tester, space, 'Little boat', at: daysAgo(3));
    await drew(tester, space, 'Midnight chai', at: daysAgo(2));
    await drive(tester, () => space.letters.writeLetter(title: 'Open when you miss me', content: 'I miss you too'));
    await pumpLove(
      tester,
      space,
      shell: Theme(data: SkyThemes.legacy(SkyTokens.day), child: const HomeShell()),
    );
    await untilFound(tester, find.byKey(SkyPageKeys.starsStat));
    await untilMarks(tester, 2);
    await untilFound(tester, find.byKey(SkyPageKeys.letterTip));
    await tester.pump();
    expect(onHome(tester, find.byKey(SkyPageKeys.canvas)).width, 430);
    expectQuietPlaces(tester, night: false);
    await settle(tester, space);
  });

  testWidgets('on a small phone with bigger text they keep under the taller top bar', (tester) async {
    calm(tester);
    tester.view.physicalSize = const Size(1080, 2340);
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final space = await coupleSpace(tester);
    await bothAnswered(tester, space, 4);
    for (var i = 1; i <= 3; i++) {
      await drew(tester, space, 'Ours $i', at: daysAgo(6 - i));
    }
    await pumpNight(tester, space);
    await untilFound(tester, find.byKey(SkyPageKeys.starsStat));
    await until(tester, () => homeMarks().evaluate().isNotEmpty);
    await tester.pump();
    expect(onHome(tester, find.byKey(SkyPageKeys.canvas)).width, 360);
    expectQuietPlaces(tester, night: true);
    await settle(tester, space);
  });

  testWidgets('a drawing finished while home is open joins the others, and the current constellation keeps its glow', (
    tester,
  ) async {
    calm(tester);
    usePhoneSize(tester);
    final space = await coupleSpace(tester);
    await bothAnswered(tester, space, 2);
    await drew(tester, space, 'First', at: daysAgo(4));
    await pumpNight(tester, space);
    await untilFound(tester, find.byKey(SkyPageKeys.starsStat));
    await untilMarks(tester, 1);
    final first = tester.getRect(find.byWidget(marks(tester).single));
    final sceneBefore = tester.widget<SkyBackdrop>(find.byKey(SkyPageKeys.canvas)).scene;

    await drew(tester, space, 'Second', at: daysAgo(1));
    await untilMarks(tester, 2);
    final firstMark = marks(tester).firstWhere((m) => m.spot.record.name == 'First');
    expect(tester.getRect(find.byWidget(firstMark)), first);
    expect(firstMark.target, lessThan(1));
    expect(marks(tester).firstWhere((m) => m.spot.record.name == 'Second').target, 1);
    final sceneAfter = tester.widget<SkyBackdrop>(find.byKey(SkyPageKeys.canvas)).scene;
    expect(sceneAfter, sceneBefore);
    expect(sceneAfter.constellation!.dim, 1);
    expectQuietPlaces(tester, night: true);
    await settle(tester, space);
  });

  testWidgets('with nothing drawn yet home looks just as it did', (tester) async {
    calm(tester);
    final space = await coupleSpace(tester);
    await bothAnswered(tester, space, 2);
    await stillDrawing(tester, space);
    await pumpNight(tester, space);
    await untilFound(tester, find.byKey(SkyPageKeys.starsStat));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(homeMarks(), findsNothing);
    await settle(tester, space);
  });

  group('the watch', () {
    testWidgets('lists finished drawings newest first, skips the unfinished one, empties when locked and rests while hidden', (tester) async {
      final space = await coupleSpace(tester);
      final older = await drew(tester, space, 'Older', at: daysAgo(3));
      final newer = await drew(tester, space, 'Newer', at: daysAgo(1));
      await stillDrawing(tester, space);
      final watch = SkyDrawnWatch(service: space.skyDrawings, vault: space.vault);
      var heard = 0;
      watch.addListener(() => heard++);
      await until(tester, () => watch.loaded);
      expect(watch.finished.map((r) => r.id), [newer.id, older.id]);
      expect(watch.shelf.unfinished, isNotNull);

      final before = heard;
      await stillDrawing(tester, space);
      await until(tester, () => true);
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      }
      expect(heard, before);

      space.vault.lock();
      await until(tester, () => watch.finished.isEmpty);
      await real(tester, () => space.vault.unlock(passphrase));
      await until(tester, () => watch.finished.length == 2);

      watch.paused = true;
      final hidden = await drew(tester, space, 'Hidden', at: daysAgo(2));
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      }
      expect(watch.finished, hasLength(2));
      watch.paused = false;
      await until(tester, () => watch.finished.length == 3);
      expect(watch.finished.map((r) => r.id), contains(hidden.id));

      watch.dispose();
      final none = SkyDrawnWatch(service: null, vault: space.vault);
      expect(none.loaded, isTrue);
      expect(none.finished, isEmpty);
      none.dispose();
      unawaited(space.close());
    });
  });
}
