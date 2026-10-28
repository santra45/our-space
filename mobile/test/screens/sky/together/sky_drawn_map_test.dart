import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/presentation/screens/sky/sky_days.dart';
import 'package:our_space_mobile/presentation/screens/sky/sky_map_plan.dart';
import 'package:our_space_mobile/presentation/screens/sky/together/sky_drawn.dart';
import 'package:our_space_mobile/presentation/screens/sky/together/sky_drawn_map.dart';
import 'package:our_space_mobile/presentation/sky/sky.dart';

import '../../../widgets/harness.dart' show recordHaptics, usePhoneSize;
import '../../love/love_harness.dart';
import '../sky_map_page_test.dart' show MapHost, dayHost, expectWarmCopy;
import 'sky_keepsakes_home_test.dart' show daysAgo, drew;

DateTime get start => SkyDays.startOf(startDate)!;

SkyDrawingRecord made({required String name, required String night, int createdAt = 1000}) => SkyDrawingRecord.tryParse(
  SkyDrawingRecord.fieldsFor(
    id: 'sky-test',
    drawing: SkyDrawing(
      stars: [
        SkyDrawnStar(id: 'a', x: 0.2, y: 0.2, by: 'owner-aaaa1111', at: 1, gen: 0),
        SkyDrawnStar(id: 'b', x: 0.7, y: 0.6, by: 'owner-aaaa1111', at: 2, gen: 0),
      ],
      lines: [SkyDrawnLine(from: 'a', to: 'b', by: 'owner-aaaa1111', at: 3, gen: 0)],
    ),
    startedAt: 1,
    updatedAt: createdAt,
    name: name,
    finished: true,
    createdAt: createdAt,
    night: night,
  ),
)!;

Finder tiles() => find.byType(SkyDrawnTile);

List<SkyDrawnTile> shownTiles(WidgetTester tester) {
  final list = tester.widgetList<SkyDrawnTile>(tiles()).toList();
  list.sort((a, b) => tester.getRect(find.byWidget(a)).left.compareTo(tester.getRect(find.byWidget(b)).left));
  return list;
}

String semanticsOf(WidgetTester tester, Finder tile) => tester
    .widget<SkyPressable>(find.descendant(of: tile, matching: find.byType(SkyPressable)).first)
    .semanticLabel!;

void main() {
  setUp(recordHaptics);

  group('the words', () {
    test('a tile reads its night and short date, and its label says it was drawn together', () {
      final record = made(name: 'Our kite', night: '2021-06-26');
      final when = SkyDrawnWhen.of(record, start: start);
      expect(when.number, 12);
      expect(when.meta(night: true), 'Night 12 · 26 Jun');
      expect(when.meta(night: false), 'Day 12 · 26 Jun');
      expect(when.note(night: true), 'Night 12 · Saturday, 26 June');
      expect(when.semantics('Our kite', night: true), 'Our kite, drawn together, Night 12, 26 June');
      final undated = SkyDrawnWhen.of(record);
      expect(undated.meta(night: true), '26 Jun');
      expect(undated.note(night: false), 'Saturday, 26 June');
      expect(undated.semantics('Our kite', night: true), 'Our kite, drawn together, 26 June');
    });

    test('the large view names both of us, and asks for the moon or the sun', () {
      expect(SkyDrawnCopy.drawnBy('Qalbi', 'Farhu'), 'Drawn by Qalbi and Farhu');
      expect(SkyDrawnCopy.drawnBy(null, 'Farhu'), SkyDrawnCopy.together);
      expect(SkyDrawnCopy.another(night: true), 'Hold the moon together to draw another');
      expect(SkyDrawnCopy.another(night: false), 'Hold the sun together to draw another');
      expect(SkyDrawnCopy.emptyMessage(night: true), contains('hold the moon together'));
      expect(SkyDrawnCopy.emptyMessage(night: false), contains('hold the sun together'));
    });
  });

  group('our sky map', () {
    testWidgets('keeps a row of ones we drew, newest first, between every day and the finished constellations', (
      tester,
    ) async {
      calm(tester);
      final space = await coupleSpace(tester);
      await bothAnswered(tester, space, 30);
      final kite = await drew(tester, space, 'Our kite', at: daysAgo(9));
      final chai = await drew(tester, space, 'Midnight chai', at: daysAgo(5));
      final boat = await drew(tester, space, 'A very long name for a little paper boat', at: daysAgo(2));
      await pumpNight(tester, space, shell: const MapHost());
      await untilFound(tester, find.byKey(SkyDrawnKeys.row));
      await untilFound(tester, find.byKey(SkyMapKeys.finished));

      expect(find.text('ONES WE DREW'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(SkyDrawnKeys.count)).data, '3');
      expect(find.byKey(SkyDrawnKeys.empty), findsNothing);
      expect(shownTiles(tester).map((t) => t.record.id), [boat.id, chai.id, kite.id]);

      final row = tester.getRect(find.byKey(SkyDrawnKeys.row));
      expect(row.top, greaterThanOrEqualTo(tester.getRect(find.byKey(SkyMapKeys.everyDay)).bottom));
      expect(row.bottom, lessThanOrEqualTo(tester.getRect(find.byKey(SkyMapKeys.finished)).top));

      for (final record in [kite, chai, boat]) {
        final tile = find.byKey(SkyDrawnKeys.tile(record.id));
        final when = SkyDrawnWhen.of(record, start: start);
        expect(find.descendant(of: tile, matching: find.text(when.meta(night: true))), findsOneWidget);
        expect(semanticsOf(tester, tile), when.semantics(record.name, night: true));
        expect(tester.getSize(tile).width, SkyDrawnTile.width);
        final view = tester.widget<SkyDrawnView>(find.descendant(of: tile, matching: find.byType(SkyDrawnView)));
        expect(view.sketch, SkyDrawnSketch.of(record.drawing));
        expect(view.style, SkyDrawnStyle.night);
      }
      final long = tester.widget<Text>(find.text('A very long name for a little paper boat'));
      expect(long.maxLines, 1);
      expect(long.overflow, TextOverflow.ellipsis);
      expectWarmCopy(tester);
      await settle(tester, space);
    });

    testWidgets('with none drawn yet a calm note waits at the end, by night and by day', (tester) async {
      calm(tester);
      final space = await coupleSpace(tester);
      await bothAnswered(tester, space, 3);
      await pumpNight(tester, space, shell: const MapHost());
      await untilFound(tester, find.byKey(SkyDrawnKeys.empty));
      expect(find.text('ONES WE DREW'), findsOneWidget);
      expect(find.byKey(SkyDrawnKeys.count), findsNothing);
      expect(tiles(), findsNothing);
      expect(find.text(SkyDrawnCopy.emptyTitle), findsOneWidget);
      expect(find.text(SkyDrawnCopy.emptyMessage(night: true)), findsOneWidget);
      final note = tester.getRect(find.byKey(SkyDrawnKeys.row));
      expect(note.top, greaterThanOrEqualTo(tester.getRect(find.byKey(SkyMapKeys.keepNote)).bottom));
      expectWarmCopy(tester);
      await settle(tester, space);
    });

    testWidgets('by day the note speaks of the sun and the tiles keep their night windows', (tester) async {
      calm(tester);
      final space = await coupleSpace(tester);
      await bothAnswered(tester, space, 3);
      await pumpLove(tester, space, shell: dayHost());
      await untilFound(tester, find.byKey(SkyDrawnKeys.empty));
      expect(find.text(SkyDrawnCopy.emptyMessage(night: false)), findsOneWidget);

      final record = await drew(tester, space, 'Sunny kite', at: daysAgo(1));
      await untilFound(tester, find.byKey(SkyDrawnKeys.tile(record.id)));
      expect(find.byKey(SkyDrawnKeys.empty), findsNothing);
      final tile = find.byKey(SkyDrawnKeys.tile(record.id));
      expect(find.descendant(of: tile, matching: find.text(SkyDrawnWhen.of(record, start: start).meta(night: false))), findsOneWidget);
      final window = find.descendant(of: tile, matching: find.byType(SkyDrawnView));
      expect(tester.element(window).sky.isNight, isTrue);
      await settle(tester, space);
    });
  });

  group('one we drew, opened large', () {
    testWidgets('opens on the full night sky with its name, its night and both of us, then goes back', (tester) async {
      calm(tester);
      final space = await coupleSpace(tester);
      await bothAnswered(tester, space, 3);
      final record = await drew(tester, space, 'Our kite', at: daysAgo(2));
      await pumpNight(tester, space, shell: const MapHost());
      await untilFound(tester, find.byKey(SkyDrawnKeys.tile(record.id)));

      await press(tester, find.byKey(SkyDrawnKeys.tile(record.id)));
      await settleRoute(tester);
      await untilFound(tester, find.byKey(SkyDrawnKeys.detail));

      final when = SkyDrawnWhen.of(record, start: start);
      expect(find.text('Our kite'), findsOneWidget);
      expect(find.text('ONE WE DREW'), findsOneWidget);
      expect(find.text(when.note(night: true)), findsOneWidget);
      expect(find.text('Drawn by Sam and Alex'), findsOneWidget);
      expect(find.text('Hold the moon together to draw another'), findsOneWidget);
      expect(find.bySemanticsLabel(when.semantics('Our kite', night: true)), findsOneWidget);

      final scene = tester.widget<SkyBackdrop>(find.byKey(SkyDrawnKeys.canvas)).scene;
      expect(scene.constellation, isNull);
      expect(scene.stars, 90);
      expect(scene.seed, 11);
      final view = tester.widget<SkyDrawnView>(find.byKey(SkyDrawnKeys.drawing));
      expect(view.sketch, SkyDrawnSketch.of(record.drawing));
      expect(view.style, SkyDrawnStyle.night);
      expect(view.opacity, 1);
      final drawing = tester.getRect(find.byKey(SkyDrawnKeys.drawing));
      final status = tester.getRect(find.byKey(SkyDrawnKeys.status));
      final title = tester.getRect(find.text('Our kite'));
      expect(drawing.top, greaterThan(title.bottom));
      expect(drawing.bottom, lessThan(status.top));
      expectWarmCopy(tester);

      await press(tester, find.byType(SkyBackButton));
      await settleRoute(tester);
      expect(find.byKey(SkyDrawnKeys.detail), findsNothing);
      expect(find.byKey(SkyMapKeys.page), findsOneWidget);
      await settle(tester, space);
    });

    testWidgets('by day it wears the day sky with soft contrails and asks for the sun', (tester) async {
      calm(tester);
      final space = await coupleSpace(tester);
      final record = await drew(tester, space, 'Day kite', at: daysAgo(1));
      await pumpLove(tester, space, shell: dayHost());
      await untilFound(tester, find.byKey(SkyDrawnKeys.tile(record.id)));
      await press(tester, find.byKey(SkyDrawnKeys.tile(record.id)));
      await settleRoute(tester);
      await untilFound(tester, find.byKey(SkyDrawnKeys.detail));
      expect(tester.widget<SkyDrawnView>(find.byKey(SkyDrawnKeys.drawing)).style, SkyDrawnStyle.day);
      expect(find.text(SkyDrawnWhen.of(record, start: start).note(night: false)), findsOneWidget);
      expect(find.text('Hold the sun together to draw another'), findsOneWidget);
      await settle(tester, space);
    });

    testWidgets('fades in with motion on', (tester) async {
      usePhoneSize(tester);
      final space = await coupleSpace(tester);
      final record = await drew(tester, space, 'Slow kite', at: daysAgo(1));
      await nightSky(tester, space);
      await pumpLove(tester, space, shell: const MapHost());
      await untilFound(tester, find.byKey(SkyDrawnKeys.tile(record.id)));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.tap(find.byKey(SkyDrawnKeys.tile(record.id)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(tester.widget<SkyDrawnView>(find.byKey(SkyDrawnKeys.drawing)).opacity, lessThan(1));
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(tester.widget<SkyDrawnView>(find.byKey(SkyDrawnKeys.drawing)).opacity, 1);
      expect(tester.takeException(), isNull);
      await settle(tester, space);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('locking closes the large view and the map', (tester) async {
      calm(tester);
      final space = await coupleSpace(tester);
      final record = await drew(tester, space, 'Secret kite', at: daysAgo(1));
      await pumpNight(tester, space, shell: const MapHost());
      await untilFound(tester, find.byKey(SkyDrawnKeys.tile(record.id)));
      await press(tester, find.byKey(SkyDrawnKeys.tile(record.id)));
      await settleRoute(tester);
      await untilFound(tester, find.byKey(SkyDrawnKeys.detail));

      space.vault.lock();
      await tester.pump();
      await settleRoute(tester);
      await settleRoute(tester);
      expect(find.byKey(SkyDrawnKeys.detail), findsNothing);
      expect(find.text('Secret kite'), findsNothing);
    });
  });
}
