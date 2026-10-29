import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/presentation/screens/sky/together/sky_drawn.dart';
import 'package:our_space_mobile/presentation/sky/sky_theme.dart';
import 'package:our_space_mobile/presentation/sky/sky_tokens.dart';

const String her = 'owner-aaaa1111';

class CountingCanvas implements Canvas {
  int circles = 0;
  int lines = 0;
  final List<Offset> centers = [];
  final List<Paint> paints = [];

  @override
  void drawCircle(Offset c, double radius, Paint paint) {
    circles++;
    centers.add(c);
    paints.add(paint);
  }

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) {
    lines++;
    paints.add(paint);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

SkyDrawnStar star(String id, double x, double y, {int at = 1}) =>
    SkyDrawnStar(id: id, x: x, y: y, by: her, at: at, gen: 0);

SkyDrawing kite() => SkyDrawing(
  stars: [star('a', 0.2, 0.2, at: 1), star('b', 0.4, 0.6, at: 2), star('c', 0.3, 0.9, at: 3), star('gone', 0.9, 0.9, at: 4)],
  lines: [
    SkyDrawnLine(from: 'a', to: 'b', by: her, at: 5, gen: 0),
    SkyDrawnLine(from: 'b', to: 'c', by: her, at: 6, gen: 0),
    SkyDrawnLine(from: 'c', to: 'gone', by: her, at: 7, gen: 0),
  ],
  removed: ['gone'],
);

SkyDrawingRecord record(String id, {bool finished = true, int createdAt = 100, int updatedAt = 100}) =>
    SkyDrawingRecord.tryParse(
      SkyDrawingRecord.fieldsFor(
        id: id,
        drawing: kite(),
        startedAt: 1,
        updatedAt: updatedAt,
        name: finished ? 'Kite $id' : '',
        finished: finished,
        createdAt: finished ? createdAt : null,
        night: finished ? '2026-10-28' : null,
      ),
    )!;

void main() {
  group('sketch', () {
    test('a sketch keeps only what shows, in order, with lines as pairs of points', () {
      final sketch = SkyDrawnSketch.of(kite());
      const a = SkyDrawnArt.aspect;
      expect(sketch.points, [const Offset(0.2 * a, 0.2), const Offset(0.4 * a, 0.6), const Offset(0.3 * a, 0.9)]);
      expect(sketch.links, [(0, 1), (1, 2)]);
      expect(sketch.bounds, const Rect.fromLTRB(0.2 * a, 0.2, 0.4 * a, 0.9));
      expect(sketch, SkyDrawnSketch.of(kite()));
      expect(SkyDrawnSketch.empty.isEmpty, isTrue);
      expect(SkyDrawnSketch.of(SkyDrawing.empty), SkyDrawnSketch.empty);
    });

    test('fitted to its own shape it fills a small box, centred, and keeps its proportions', () {
      final sketch = SkyDrawnSketch.of(kite());
      const box = Rect.fromLTWH(10, 20, 100, 60);
      final frame = SkyDrawnArt.frameOf(box, sketch);
      final placed = [for (final p in sketch.points) SkyDrawnArt.place(frame, p)];
      final inner = box.deflate(60 * SkyDrawnArt.padding);
      for (final p in placed) {
        expect(inner.inflate(0.001).contains(p), isTrue, reason: '$p');
      }
      expect(frame.width, closeTo(frame.height, 1e-9));
      final top = placed.map((p) => p.dy).reduce((a, b) => a < b ? a : b);
      final bottom = placed.map((p) => p.dy).reduce((a, b) => a > b ? a : b);
      expect(top, closeTo(inner.top, 1e-6));
      expect(bottom, closeTo(inner.bottom, 1e-6));
      final left = placed.map((p) => p.dx).reduce((a, b) => a < b ? a : b);
      final right = placed.map((p) => p.dx).reduce((a, b) => a > b ? a : b);
      expect((left + right) / 2, closeTo(box.center.dx, 1e-6));
      expect(SkyDrawnArt.unitOf(frame, placed[1]).dx, closeTo(0.4 * SkyDrawnArt.aspect, 1e-9));
      expect(SkyDrawnArt.unitOf(frame, placed[1]).dy, closeTo(0.6, 1e-9));
    });

    test('a single star sits in the middle instead of blowing up', () {
      final sketch = SkyDrawnSketch.of(SkyDrawing(stars: [star('a', 0.7, 0.1)]));
      const box = Rect.fromLTWH(0, 0, 50, 50);
      final frame = SkyDrawnArt.frameOf(box, sketch);
      final p = SkyDrawnArt.place(frame, sketch.points.single);
      expect(p.dx, closeTo(25, 1e-9));
      expect(p.dy, closeTo(25, 1e-9));
      expect(frame.width, lessThan(400));
    });

    test('on the patch the whole tall patch maps to the middle of the space, as tall as it fits', () {
      final sketch = SkyDrawnSketch.of(kite());
      const box = Rect.fromLTWH(0, 0, 390, 600);
      final frame = SkyDrawnArt.frameOf(box, sketch, fit: SkyDrawnFit.patch);
      final area = SkyDrawnArt.patchIn(box);
      expect(area.width, closeTo(390, 1e-9));
      expect(area.height, closeTo(390 / SkyDrawnArt.aspect, 1e-9));
      expect(area.center.dx, closeTo(box.center.dx, 1e-9));
      expect(area.center.dy, closeTo(box.center.dy, 1e-9));
      final unitFrame = SkyDrawnArt.unitFrame(frame);
      for (final (got, want) in [
        (unitFrame.left, area.left),
        (unitFrame.top, area.top),
        (unitFrame.width, area.width),
        (unitFrame.height, area.height),
      ]) {
        expect(got, closeTo(want, 1e-9));
      }
      final middle = SkyDrawnArt.place(frame, const Offset(0.5 * SkyDrawnArt.aspect, 0.5));
      expect(middle.dx, closeTo(195, 1e-9));
      expect(middle.dy, closeTo(300, 1e-9));
      final corner = SkyDrawnArt.unitOf(SkyDrawnArt.unitFrame(frame), area.bottomRight);
      expect(corner.dx, closeTo(1, 1e-9));
      expect(corner.dy, closeTo(1, 1e-9));
      final wide = SkyDrawnArt.patchIn(const Rect.fromLTWH(0, 0, 600, 400));
      expect(wide.height, 400);
      expect(wide.width, closeTo(400 * SkyDrawnArt.aspect, 1e-9));
    });
  });

  group('art', () {
    test('by night: fine lines and small glowing stars; by day: soft contrails and bright puffs', () {
      final sketch = SkyDrawnSketch.of(kite());
      const box = Rect.fromLTWH(0, 0, 160, 160);
      final night = CountingCanvas();
      SkyDrawnArt.paint(night, box, sketch, style: SkyDrawnStyle.night);
      expect(night.lines, 2);
      expect(night.circles, 9);
      final day = CountingCanvas();
      SkyDrawnArt.paint(day, box, sketch, style: SkyDrawnStyle.day);
      expect(day.lines, 6);
      expect(day.circles, 9);
      expect(day.paints.any((p) => p.maskFilter != null), isTrue);
    });

    test('opacity fades everything, and nothing is painted when there is nothing to show', () {
      final sketch = SkyDrawnSketch.of(kite());
      const box = Rect.fromLTWH(0, 0, 160, 160);
      final full = CountingCanvas();
      SkyDrawnArt.paint(full, box, sketch, style: SkyDrawnStyle.night);
      final faint = CountingCanvas();
      SkyDrawnArt.paint(faint, box, sketch, style: SkyDrawnStyle.night, opacity: 0.25);
      for (var i = 0; i < full.paints.length; i++) {
        expect(faint.paints[i].color.a, closeTo(full.paints[i].color.a * 0.25, 0.01));
      }
      for (final (opacity, s, b) in [
        (0.0, sketch, box),
        (1.0, SkyDrawnSketch.empty, box),
        (1.0, sketch, Rect.zero),
      ]) {
        final none = CountingCanvas();
        SkyDrawnArt.paint(none, b, s, style: SkyDrawnStyle.day, opacity: opacity);
        expect(none.circles + none.lines, 0);
      }
    });

    test('a bigger box draws bigger stars, within limits', () {
      expect(SkyDrawnArt.scaleOf(const Rect.fromLTWH(0, 0, 40, 40)), 0.35);
      expect(SkyDrawnArt.scaleOf(const Rect.fromLTWH(0, 0, 160, 300)), 1);
      expect(SkyDrawnArt.scaleOf(const Rect.fromLTWH(0, 0, 2000, 2000)), 2.4);
    });

    test('the painter repaints only when what it shows changes', () {
      final sketch = SkyDrawnSketch.of(kite());
      final a = SkyDrawnPainter(sketch: sketch, style: SkyDrawnStyle.night);
      expect(a.shouldRepaint(SkyDrawnPainter(sketch: SkyDrawnSketch.of(kite()), style: SkyDrawnStyle.night)), isFalse);
      expect(a.shouldRepaint(SkyDrawnPainter(sketch: sketch, style: SkyDrawnStyle.day)), isTrue);
      expect(a.shouldRepaint(SkyDrawnPainter(sketch: sketch, style: SkyDrawnStyle.night, opacity: 0.3)), isTrue);
      expect(a.shouldRepaint(SkyDrawnPainter(sketch: SkyDrawnSketch.empty, style: SkyDrawnStyle.night)), isTrue);
    });

    testWidgets('the view paints behind its own repaint boundary, in the sky of the moment, with an optional label',
        (tester) async {
      Future<SkyDrawnPainter> pumpIn(SkyMode mode, {String? label}) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: SkyThemes.material(SkyTokens.of(mode)),
            home: Center(
              child: SizedBox(
                width: 80,
                height: 80,
                child: SkyDrawnView(sketch: SkyDrawnSketch.of(kite()), opacity: 0.3, semanticLabel: label),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final paint = tester.widget<CustomPaint>(
          find.descendant(of: find.byType(SkyDrawnView), matching: find.byType(CustomPaint)),
        );
        expect(
          find.descendant(of: find.byType(SkyDrawnView), matching: find.byType(RepaintBoundary)),
          findsOneWidget,
        );
        return paint.painter! as SkyDrawnPainter;
      }

      expect((await pumpIn(SkyMode.night)).style, SkyDrawnStyle.night);
      final day = await pumpIn(SkyMode.day, label: 'Our kite');
      expect(day.style, SkyDrawnStyle.day);
      expect(day.opacity, 0.3);
      expect(find.bySemanticsLabel('Our kite'), findsOneWidget);
    });
  });

  group('shelf', () {
    test('finished drawings are listed newest first, with the one unfinished drawing apart', () {
      final shelf = SkyDrawnShelf.of([
        record('sky-old', createdAt: 100),
        record('sky-new', createdAt: 300),
        record('sky-mid', createdAt: 200),
        record('sky-open', finished: false, updatedAt: 50),
        record('sky-open-older', finished: false, updatedAt: 40),
      ]);
      expect(shelf.finished.map((r) => r.id), ['sky-new', 'sky-mid', 'sky-old']);
      expect(shelf.unfinished!.id, 'sky-open');
      expect(shelf.recent(2).map((r) => r.id), ['sky-new', 'sky-mid']);
      expect(shelf.byId('sky-mid')!.name, 'Kite sky-mid');
      expect(shelf.byId('sky-open'), same(shelf.unfinished));
      expect(shelf.byId('nope'), isNull);
      expect(shelf.isEmpty, isFalse);
      expect(SkyDrawnShelf.empty.isEmpty, isTrue);
      expect(SkyDrawnShelf.of(const []).isEmpty, isTrue);
    });

    test('the same moment falls back to the latest change, then the id', () {
      final shelf = SkyDrawnShelf.of([
        record('sky-a', createdAt: 100, updatedAt: 5),
        record('sky-b', createdAt: 100, updatedAt: 9),
        record('sky-c', createdAt: 100, updatedAt: 9),
      ]);
      expect(shelf.finished.map((r) => r.id), ['sky-c', 'sky-b', 'sky-a']);
    });
  });
}
