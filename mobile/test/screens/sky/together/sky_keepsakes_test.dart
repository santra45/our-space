import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/presentation/screens/sky/sky_constellation_plan.dart';
import 'package:our_space_mobile/presentation/screens/sky/together/sky_drawn.dart';
import 'package:our_space_mobile/presentation/screens/sky/together/sky_drawn_placement.dart';
import 'package:our_space_mobile/presentation/screens/sky/together/sky_keepsakes.dart';
import 'package:our_space_mobile/presentation/screens/sky/together/sky_together_fx.dart';
import 'package:our_space_mobile/presentation/screens/sky/together/sky_together_home.dart';
import 'package:our_space_mobile/presentation/screens/sky/together/sky_together_layer.dart';
import 'package:our_space_mobile/presentation/sky/sky.dart';

const String her = 'owner-aaaa1111';
const Size homeSky = Size(390, 484);
const double sheetTop = 404;
const Rect letterTip = Rect.fromLTWH(140, 152, 170, 27);
const Size gateLine = Size(220, 18);

class RecordingCanvas implements Canvas {
  final List<(Offset, double, Paint)> circles = [];
  final List<(Offset, Offset, Paint)> lines = [];

  @override
  void drawCircle(Offset c, double radius, Paint paint) => circles.add((c, radius, paint));

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) => lines.add((p1, p2, paint));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

SkyDrawnStar star(String id, double x, double y, {int at = 1}) =>
    SkyDrawnStar(id: id, x: x, y: y, by: her, at: at, gen: 0);

SkyDrawing kite() => SkyDrawing(
  stars: [star('a', 0.3, 0.1, at: 1), star('b', 0.6, 0.4, at: 2), star('c', 0.3, 0.7, at: 3), star('d', 0.1, 0.4, at: 4)],
  lines: [
    SkyDrawnLine(from: 'a', to: 'b', by: her, at: 5, gen: 0),
    SkyDrawnLine(from: 'b', to: 'c', by: her, at: 6, gen: 0),
    SkyDrawnLine(from: 'c', to: 'd', by: her, at: 7, gen: 0),
    SkyDrawnLine(from: 'd', to: 'a', by: her, at: 8, gen: 0),
  ],
);

SkyDrawingRecord kept(int n) => SkyDrawingRecord.tryParse(
  SkyDrawingRecord.fieldsFor(
    id: 'sky-$n',
    drawing: kite(),
    startedAt: n * 10,
    updatedAt: n * 10 + 1,
    name: 'Kite $n',
    finished: true,
    createdAt: n * 10 + 1,
    night: '2026-10-${(n % 20 + 1).toString().padLeft(2, '0')}',
  ),
)!;

List<SkyDrawingRecord> newestFirst(int count) => [for (var n = count; n >= 1; n--) kept(n)];

bool overlapsCircle(Rect rect, Offset centre, double radius) {
  final nearest = Offset(centre.dx.clamp(rect.left, rect.right), centre.dy.clamp(rect.top, rect.bottom));
  return (nearest - centre).distance < radius;
}

bool overlaps(Rect a, Rect b) => a.overlaps(b) && a.intersect(b).width > 0 && a.intersect(b).height > 0;

class Home {
  Home({required this.shape, required this.night, required this.topBar, required this.letters});

  final ConstellationShape shape;
  final bool night;
  final double topBar;
  final bool letters;

  late final SkyConstellation constellation = SkyConstellationPlan.home(
    stars: shape.index * SkyConstellation.count + 6,
    litToday: false,
    presence: false,
  );

  late final List<Rect> labels = SkyConstellationPlan.labelAreas(
    constellation,
    me: true,
    partner: true,
    partnerChip: true,
  );

  late final Rect tonightTip = SkyConstellationPlan.tipRect(
    constellation.pointAt(constellation.gap!),
    SkyConstellationPlan.tipFor(constellation.pointAt(constellation.gap!), constellation: constellation, avoid: labels),
  );

  late final List<Rect> extra = [...labels, tonightTip, if (letters) letterTip];

  late final List<Rect> avoid = SkyKeepsakePlan.avoid(
    sky: homeSky,
    constellation: constellation,
    topBarBottom: topBar,
    sheetTop: sheetTop,
    night: night,
    extra: extra,
    line: gateLine,
    streak: letters ? SkyScene.home.shootingStar : null,
  );

  late final List<Rect> slots = SkyKeepsakePlan.slots(sky: homeSky, avoid: avoid);

  void expectClear(Rect rect) {
    final why = '$rect on ${shape.title} ${night ? 'night' : 'day'} top $topBar';
    expect(rect.left, greaterThanOrEqualTo(0), reason: why);
    expect(rect.right, lessThanOrEqualTo(homeSky.width), reason: why);
    expect(rect.top, greaterThanOrEqualTo(topBar + SkyKeepsakePlan.topBarGap), reason: why);
    expect(rect.bottom, lessThanOrEqualTo(400), reason: why);
    expect(overlaps(rect, constellation.bounds.inflate(10)), isFalse, reason: 'over the constellation: $why');
    for (var i = 0; i < SkyConstellation.count; i++) {
      expect(rect.inflate(8).contains(constellation.pointAt(i)), isFalse, reason: 'star $i: $why');
    }
    if (night) {
      expect(overlapsCircle(rect, SkyScene.home.moon!, 46), isFalse, reason: 'over the moon: $why');
    } else {
      expect(overlapsCircle(rect, SkyKeepsakePlan.sun, 44), isFalse, reason: 'over the sun: $why');
    }
    for (final area in extra) {
      expect(overlaps(rect, area.inflate(4)), isFalse, reason: 'over $area: $why');
    }
    final line = SkyKeepsakePlan.lineArea(gateLine, night: night)!;
    expect(overlaps(rect, line), isFalse, reason: 'over the gate line: $why');
    if (letters) {
      expect(overlaps(rect, SkyKeepsakePlan.streakArea(SkyScene.home.shootingStar!)), isFalse, reason: why);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('where the ones we drew rest on home', () {
    for (final night in [true, false]) {
      for (final shape in ConstellationShape.values) {
        test('${shape.title} ${night ? 'by night' : 'by day'}: four quiet places on small and large phones, clear of everything', () {
          for (final topBar in [112.0, 138.0, 176.0]) {
            for (final letters in [false, true]) {
              final home = Home(shape: shape, night: night, topBar: topBar, letters: letters);
              expect(home.slots, hasLength(SkyKeepsakePlan.maxShown), reason: '${shape.title} top $topBar');
              for (final rect in home.slots) {
                expect(rect.size, const Size.square(SkyDrawnPlacement.size));
                home.expectClear(rect);
                final edge = math.min(rect.left, homeSky.width - rect.right);
                expect(edge, lessThan(60), reason: 'near an edge: $rect');
              }
              for (var i = 0; i < home.slots.length; i++) {
                for (var j = i + 1; j < home.slots.length; j++) {
                  expect(overlaps(home.slots[i], home.slots[j]), isFalse);
                }
              }
              final left = home.slots.where((r) => r.center.dx < homeSky.width / 2).length;
              expect(left, inInclusiveRange(1, 3), reason: 'scattered on both sides');
            }
          }
        });
      }
    }

    test('the same sky always gives the same places', () {
      final once = Home(shape: ConstellationShape.heart, night: true, topBar: 138, letters: true).slots;
      final again = Home(shape: ConstellationShape.heart, night: true, topBar: 138, letters: true).slots;
      expect(once, again);
    });

    test('a very tall top bar or a crowded sky leaves fewer places, never an overlap', () {
      final crowded = SkyKeepsakePlan.slots(
        sky: homeSky,
        avoid: const [Rect.fromLTWH(0, 0, 390, 380), Rect.fromLTWH(0, 0, 280, 484)],
      );
      expect(crowded, hasLength(1));
      expect(crowded.single.top, greaterThanOrEqualTo(380));
      expect(crowded.single.left, greaterThanOrEqualTo(280));
      expect(SkyKeepsakePlan.slots(sky: homeSky, avoid: [Offset.zero & homeSky]), isEmpty);
    });

    test('the invitation line sits under the moon at night and under the sun by day', () {
      final night = SkyKeepsakePlan.lineArea(const Size(160, 18), night: true)!;
      expect(night.top, SkyScene.home.moon!.dy + SkyKeepsakePlan.moonLineGap);
      expect(night.right, 372);
      final day = SkyKeepsakePlan.lineArea(const Size(160, 18), night: false)!;
      expect(day.top, SkyKeepsakePlan.sun.dy + SkyKeepsakePlan.sunLineGap);
      expect(day.center.dx, SkyKeepsakePlan.sun.dx);
      final wide = SkyKeepsakePlan.lineArea(const Size(500, 18), night: true)!;
      expect(wide.left, SkyKeepsakePlan.lineEdge);
      expect(SkyKeepsakePlan.lineArea(Size.zero, night: true), isNull);
      final measured = SkyKeepsakePlan.measureLine('Alex');
      final none = SkyKeepsakePlan.measureLine(null);
      expect(measured.width * measured.height, greaterThan(none.width * none.height));
      final bigger = SkyKeepsakePlan.measureLine('Alex', textScaler: const TextScaler.linear(1.5));
      expect(bigger.width * bigger.height, greaterThan(measured.width * measured.height));
      expect(bigger.width, lessThanOrEqualTo(SkyTogetherSpot.lineMax - SkyTogetherSpot.lineMin));
    });

    test('the room kept for the invitation covers the line home really shows at every step', () {
      for (final night in [true, false]) {
        for (final scale in [1.0, 1.3]) {
          final scaler = TextScaler.linear(scale);
          final room = SkyKeepsakePlan.lineArea(SkyKeepsakePlan.measureLine('Alex', textScaler: scaler), night: night)!;
          for (final stage in SkyTogetherStage.values.where((stage) => stage != SkyTogetherStage.off)) {
            final shown = SkyTogetherLine.rectFor(
              stage,
              night: night,
              partner: 'Alex',
              tokens: night ? SkyTokens.night : SkyTokens.day,
              scaler: scaler,
              scale: 1,
            )!;
            final why = '$stage, night $night, text $scale';
            expect(room.left, lessThanOrEqualTo(shown.left + 0.01), reason: why);
            expect(room.top, lessThanOrEqualTo(shown.top + 0.01), reason: why);
            expect(room.right, greaterThanOrEqualTo(shown.right - 0.01), reason: why);
            expect(room.bottom, greaterThanOrEqualTo(shown.bottom - 0.01), reason: why);
          }
        }
      }
      expect(SkyKeepsakePlan.bodyOf(night: true), SkyTogetherSpot.moon);
      expect(SkyKeepsakePlan.bodyOf(night: false), SkyTogetherSpot.sun);
    });
  });

  group('which drawings show and how faint', () {
    final slots = Home(shape: ConstellationShape.heart, night: true, topBar: 138, letters: false).slots;

    test('the newest is the brightest, older ones fade, and only four ever show', () {
      final spots = SkyKeepsakePlan.spots(finished: newestFirst(6), slots: slots);
      expect(spots.map((s) => s.id), ['sky-6', 'sky-5', 'sky-4', 'sky-3']);
      expect(spots.first.opacity, SkyDrawnPlacement.newestOpacity);
      expect(spots.first.strength, 1);
      for (var i = 1; i < spots.length; i++) {
        expect(spots[i].strength, lessThan(spots[i - 1].strength));
        expect(spots[i].strength, greaterThan(0.4));
      }
      expect(spots.map((s) => s.rect).toSet(), hasLength(4));
      expect(SkyKeepsakePlan.spots(finished: const [], slots: slots), isEmpty);
      expect(SkyKeepsakePlan.spots(finished: newestFirst(3), slots: const []), isEmpty);
    });

    test('a new drawing takes the oldest one\'s place, so the others stay just where they were', () {
      final before = {for (final s in SkyKeepsakePlan.spots(finished: newestFirst(4), slots: slots)) s.id: s};
      final after = {for (final s in SkyKeepsakePlan.spots(finished: newestFirst(5), slots: slots)) s.id: s};
      expect(after.keys.toSet(), {'sky-5', 'sky-4', 'sky-3', 'sky-2'});
      for (final id in ['sky-4', 'sky-3', 'sky-2']) {
        expect(after[id]!.rect, before[id]!.rect, reason: id);
        expect(after[id]!.tilt, before[id]!.tilt, reason: id);
      }
      expect(after['sky-5']!.rect, before['sky-1']!.rect);
      final first = SkyKeepsakePlan.spots(finished: newestFirst(1), slots: slots).single;
      expect(first.rect, slots.first);
      expect(first.tilt, SkyKeepsakePlan.tilts.first);
    });

    test('with fewer places only the newest show, each in its own place', () {
      final two = slots.take(2).toList();
      final spots = SkyKeepsakePlan.spots(finished: newestFirst(7), slots: two);
      expect(spots.map((s) => s.id), ['sky-7', 'sky-6']);
      expect(spots[0].rect, isNot(spots[1].rect));
    });
  });

  group('faint art', () {
    final sketch = SkyDrawnSketch.of(kite());

    test('a small tilt turns the drawing about its middle and keeps its lines', () {
      final turned = SkyKeepsakeArt.tilted(sketch, 90);
      expect(turned.links, sketch.links);
      expect(turned.bounds.center.dx, closeTo(sketch.bounds.center.dx, 1e-9));
      expect(turned.bounds.center.dy, closeTo(sketch.bounds.center.dy, 1e-9));
      expect(turned.bounds.width, closeTo(sketch.bounds.height, 1e-9));
      expect(identical(SkyKeepsakeArt.tilted(sketch, 0), sketch), isTrue);
      expect(SkyKeepsakeArt.tilted(SkyDrawnSketch.empty, 8).isEmpty, isTrue);
    });

    test('tilted or not, every star stays inside its small place', () {
      const box = Rect.fromLTWH(0, 0, 46, 46);
      for (final tilt in SkyKeepsakePlan.tilts) {
        for (final p in SkyKeepsakeArt.pointsIn(box, SkyKeepsakeArt.tilted(sketch, tilt))) {
          expect(box.contains(p), isTrue, reason: '$p at $tilt');
        }
      }
    });

    test('by night: fine gold lines and small stars, every third one white, with no blur', () {
      final canvas = RecordingCanvas();
      SkyKeepsakeArt.paint(canvas, const Rect.fromLTWH(0, 0, 46, 46), sketch, style: SkyDrawnStyle.night, scale: 2);
      expect(canvas.lines, hasLength(4));
      expect(canvas.lines.first.$3.strokeWidth, closeTo(1.4, 1e-6));
      expect(canvas.lines.first.$3.color.a, closeTo(0.30, 0.01));
      expect(canvas.circles, hasLength(8));
      final cores = [for (final c in canvas.circles) if (c.$2 == 1.35 * 2) c.$3.color];
      expect(cores, hasLength(4));
      expect(cores.map((c) => c.toARGB32() & 0xFFFFFF), [0xFFFFFF, 0xFFD98A, 0xFFD98A, 0xFFFFFF]);
      expect(cores.every((c) => (c.a - 0.62).abs() < 1e-3), isTrue);
      expect(canvas.circles.every((c) => c.$3.maskFilter == null), isTrue);
    });

    test('by day: soft contrails with a faint indigo shade and small puffs', () {
      final canvas = RecordingCanvas();
      SkyKeepsakeArt.paint(canvas, const Rect.fromLTWH(0, 0, 46, 46), sketch, style: SkyDrawnStyle.day);
      expect(canvas.lines, hasLength(12));
      final shade = canvas.lines.first.$3.color;
      expect(shade.a, closeTo(0.035, 1e-3));
      expect(shade.toARGB32() & 0xFFFFFF, SkyTokens.indigo.toARGB32() & 0xFFFFFF);
      expect(canvas.lines[1].$3.maskFilter, isNotNull);
      expect(canvas.circles.where((c) => c.$3.color == const Color(0xFFFFFFFF)), hasLength(4));
      expect(canvas.circles.length, greaterThan(4 * 6));
    });

    test('fainter means fainter, and nothing is drawn when there is nothing to see', () {
      final full = RecordingCanvas();
      final half = RecordingCanvas();
      SkyKeepsakeArt.paint(full, const Rect.fromLTWH(0, 0, 46, 46), sketch, style: SkyDrawnStyle.night);
      SkyKeepsakeArt.paint(half, const Rect.fromLTWH(0, 0, 46, 46), sketch, style: SkyDrawnStyle.night, opacity: 0.5);
      expect(half.lines.first.$3.color.a, closeTo(full.lines.first.$3.color.a / 2, 0.01));
      final none = RecordingCanvas();
      SkyKeepsakeArt.paint(none, const Rect.fromLTWH(0, 0, 46, 46), sketch, style: SkyDrawnStyle.night, opacity: 0);
      SkyKeepsakeArt.paint(none, const Rect.fromLTWH(0, 0, 46, 46), SkyDrawnSketch.empty, style: SkyDrawnStyle.day);
      SkyKeepsakeArt.paint(none, Rect.zero, sketch, style: SkyDrawnStyle.day);
      expect(none.circles, isEmpty);
      expect(none.lines, isEmpty);
    });

    test('the painter repaints only when something it shows changes', () {
      final a = SkyKeepsakePainter(sketch: sketch, style: SkyDrawnStyle.night, opacity: 0.5, scale: 1);
      expect(a.shouldRepaint(SkyKeepsakePainter(sketch: sketch, style: SkyDrawnStyle.night, opacity: 0.5, scale: 1)), isFalse);
      expect(a.shouldRepaint(SkyKeepsakePainter(sketch: sketch, style: SkyDrawnStyle.day, opacity: 0.5, scale: 1)), isTrue);
      expect(a.shouldRepaint(SkyKeepsakePainter(sketch: sketch, style: SkyDrawnStyle.night, opacity: 0.4, scale: 1)), isTrue);
      expect(a.shouldRepaint(SkyKeepsakePainter(sketch: sketch, style: SkyDrawnStyle.night, opacity: 0.5, scale: 2)), isTrue);
    });
  });

  group('the layer', () {
    Widget host({
      required ValueNotifier<double?> topBar,
      required List<SkyDrawingRecord> records,
      bool night = true,
      bool motion = false,
      VoidCallback? onSkyTap,
    }) {
      return MediaQuery(
        data: MediaQueryData(size: const Size(390, 844), disableAnimations: !motion),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Theme(
            data: SkyThemes.legacy(night ? SkyTokens.night : SkyTokens.day),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 390,
                height: 484,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onSkyTap,
                  child: SkyKeepsakes(
                    constellation: SkyScene.home.constellation!,
                    topBar: topBar,
                    sky: homeSky,
                    sheetTop: sheetTop,
                    records: records,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    List<SkyKeepsakeMark> marks(WidgetTester tester) =>
        tester.widgetList<SkyKeepsakeMark>(find.byType(SkyKeepsakeMark)).toList();

    double shown(WidgetTester tester, String id) {
      final mark = find.byWidgetPredicate((w) => w is SkyKeepsakeMark && w.spot.id == id && !w.leaving);
      final paint = tester.widget<CustomPaint>(find.descendant(of: mark, matching: find.byType(CustomPaint)));
      return (paint.painter! as SkyKeepsakePainter).opacity;
    }

    testWidgets('waits for the top bar, then shows each drawing faint in its place, never taking a tap or a voice', (
      tester,
    ) async {
      final topBar = ValueNotifier<double?>(null);
      addTearDown(topBar.dispose);
      var taps = 0;
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(host(topBar: topBar, records: newestFirst(3), onSkyTap: () => taps++));
      expect(find.byType(SkyKeepsakeMark), findsNothing);

      topBar.value = 138;
      await tester.pump();
      expect(marks(tester), hasLength(3));
      expect(find.descendant(of: find.byType(SkyKeepsakes), matching: find.byType(RepaintBoundary)), findsNWidgets(3));
      for (final mark in marks(tester)) {
        final rect = tester.getRect(find.byWidget(mark));
        expect(rect, mark.spot.rect);
        expect(rect.top, greaterThanOrEqualTo(138 + SkyKeepsakePlan.topBarGap));
        expect(mark.style, SkyDrawnStyle.night);
        expect(mark.target, mark.spot.strength);
      }
      expect(shown(tester, 'sky-3'), 1);

      await tester.tapAt(tester.getCenter(find.byWidget(marks(tester).first)));
      expect(taps, 1);
      expect(find.bySemanticsLabel(RegExp('Kite')), findsNothing);
      semantics.dispose();
    });

    testWidgets('by day the same drawings wear the day look and keep clear of the sun', (tester) async {
      final topBar = ValueNotifier<double?>(118);
      addTearDown(topBar.dispose);
      await tester.pumpWidget(host(topBar: topBar, records: newestFirst(2), night: false));
      await tester.pump();
      expect(marks(tester), hasLength(2));
      for (final mark in marks(tester)) {
        expect(mark.style, SkyDrawnStyle.day);
        expect(overlapsCircle(mark.spot.rect, SkyKeepsakePlan.sun, 44), isFalse);
      }
    });

    testWidgets('a new one fades into the oldest one\'s place while the others stay', (tester) async {
      final topBar = ValueNotifier<double?>(138);
      addTearDown(topBar.dispose);
      await tester.pumpWidget(host(topBar: topBar, records: newestFirst(4), motion: true));
      await tester.pump(SkyMotion.slow * 3);
      final before = {for (final m in marks(tester)) m.spot.id: tester.getRect(find.byWidget(m))};
      expect(before.keys.toSet(), {'sky-4', 'sky-3', 'sky-2', 'sky-1'});
      expect(shown(tester, 'sky-4'), 1);

      await tester.pumpWidget(host(topBar: topBar, records: newestFirst(5), motion: true));
      await tester.pump(SkyKeepsakes.arrival ~/ 3);
      expect(shown(tester, 'sky-5'), inExclusiveRange(0, 1));
      final leaving = find.byWidgetPredicate((w) => w is SkyKeepsakeMark && w.leaving);
      expect(tester.widget<SkyKeepsakeMark>(leaving).spot.id, 'sky-1');
      for (final id in ['sky-4', 'sky-3', 'sky-2']) {
        final mark = marks(tester).firstWhere((m) => m.spot.id == id && !m.leaving);
        expect(tester.getRect(find.byWidget(mark)), before[id]);
      }

      await tester.pump(SkyKeepsakes.arrival);
      await tester.pump();
      expect(shown(tester, 'sky-5'), 1);
      expect(find.byWidgetPredicate((w) => w is SkyKeepsakeMark && w.leaving), findsNothing);
      expect(marks(tester).map((m) => m.spot.id).toSet(), {'sky-5', 'sky-4', 'sky-3', 'sky-2'});
      expect(shown(tester, 'sky-4'), closeTo(SkyDrawnPlacement.opacityFor(1) / SkyDrawnPlacement.newestOpacity, 1e-9));
    });

    testWidgets('with motion off they simply appear and leave at once', (tester) async {
      final topBar = ValueNotifier<double?>(138);
      addTearDown(topBar.dispose);
      await tester.pumpWidget(host(topBar: topBar, records: newestFirst(1)));
      await tester.pump();
      expect(shown(tester, 'sky-1'), 1);
      await tester.pumpWidget(host(topBar: topBar, records: [kept(2)]));
      await tester.pump();
      expect(shown(tester, 'sky-2'), 1);
      expect(find.byWidgetPredicate((w) => w is SkyKeepsakeMark && w.spot.id == 'sky-1'), findsNothing);
      await tester.pumpWidget(host(topBar: topBar, records: const []));
      expect(find.byType(SkyKeepsakeMark), findsNothing);
    });
  });

  testWidgets('the top bar probe reports its height after layout and again when it changes', (tester) async {
    final heights = <double>[];
    Widget probe(double height) => Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SkyHeightProbe(onHeight: heights.add, child: SizedBox(width: 100, height: height)),
      ),
    );
    await tester.pumpWidget(probe(120));
    expect(heights, [120]);
    await tester.pumpWidget(probe(120));
    expect(heights, [120]);
    await tester.pumpWidget(probe(150));
    expect(heights, [120, 150]);
  });
}
