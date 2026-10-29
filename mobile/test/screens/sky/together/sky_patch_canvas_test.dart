import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/presentation/screens/sky/together/sky_drawn.dart';
import 'package:our_space_mobile/presentation/screens/sky/together/sky_patch_art.dart';
import 'package:our_space_mobile/presentation/screens/sky/together/sky_patch_canvas.dart';
import 'package:our_space_mobile/presentation/screens/sky/together/sky_patch_session.dart';
import 'package:our_space_mobile/presentation/screens/sky/together/sky_together_layer.dart';
import 'package:our_space_mobile/presentation/sky/sky.dart';

import '../../../support/fake_sky_together.dart';
import '../../../widgets/harness.dart';
import 'sky_drawn_test.dart' show CountingCanvas;

class LayerCanvas extends CountingCanvas {
  final List<Rect?> layers = [];

  @override
  void saveLayer(Rect? bounds, Paint paint) => layers.add(bounds);
}

void main() {
  testWidgets('the patch only remembers the stars and lines on show, however many the partner sends', (tester) async {
    final pair = FakeSkyPair();
    pair.settle();
    final session = SkyPatchSession(link: pair.a, id: 'sky-test', haptic: (_) {});
    await pumpHost(
      tester,
      SizedBox(width: 360, height: 600, child: SkyPatchCanvas(session: session, partner: 'Alex')),
    );
    final owner = pair.ownerB!;
    int remembered() => (tester.state(find.byType(SkyPatchCanvas)) as dynamic).remembered as int;

    for (var i = 0; i < 120; i++) {
      final star = SkyDrawnStar(id: 'p$i', x: (i % 11) / 11 + 0.04, y: (i ~/ 11) / 11 + 0.04, by: owner, at: 5000 - i, gen: 0);
      pair.injectEvent(pair.a, SkyOpEvent(drawing: session.id, op: SkyAddStar(star)));
      await tester.pump();
    }
    expect(session.drawing.visibleStars, hasLength(skyDrawingMaxStars));
    expect(remembered(), skyDrawingMaxStars);

    final shown = [for (final star in session.drawing.visibleStars) star.id];
    var at = 9000;
    for (var i = 0; i < shown.length && at > 8900; i++) {
      for (var j = i + 1; j < shown.length && at > 8900; j++) {
        final line = SkyDrawnLine(from: shown[i], to: shown[j], by: owner, at: at--, gen: 0);
        pair.injectEvent(pair.a, SkyOpEvent(drawing: session.id, op: SkyLink(line)));
        await tester.pump();
      }
    }
    expect(session.drawing.visibleLines, hasLength(skyDrawingMaxLines));
    expect(remembered(), skyDrawingMaxStars + skyDrawingMaxLines);

    pair.injectEvent(pair.a, SkyOpEvent(drawing: session.id, op: const SkyStartOver(1)));
    await tester.pump();
    expect(session.drawing.isBlank, isTrue);
    expect(remembered(), 0);

    await tester.pumpWidget(const SizedBox());
    session.dispose();
    pair.dispose();
  });

  testWidgets('on a narrow phone a tap a finger width off your own star still takes it away', (tester) async {
    tester.view.physicalSize = const Size(1080, 2220);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final pair = FakeSkyPair();
    pair.settle();
    final session = SkyPatchSession(link: pair.a, id: 'sky-test', haptic: (_) {});
    await pumpHost(
      tester,
      SizedBox(width: 360, height: 600, child: SkyPatchCanvas(session: session, partner: 'Alex')),
    );
    final star = session.placeStar(0.5, 0.5)!;
    await tester.pump();
    final box = tester.getRect(find.byKey(SkyTogetherKeys.star(star.id)));
    expect(box.width, greaterThanOrEqualTo(44));
    await tester.tapAt(box.center + const Offset(21.5, 0));
    await tester.pump();
    expect(session.drawing.visibleStars, isEmpty);

    await tester.pumpWidget(const SizedBox());
    session.dispose();
    pair.dispose();
  });

  testWidgets('the patch fills the tall open sky, so a tap near its top or bottom places a star right there', (tester) async {
    final pair = FakeSkyPair();
    pair.settle();
    final session = SkyPatchSession(link: pair.a, id: 'sky-test', haptic: (_) {});
    await pumpHost(
      tester,
      SizedBox(width: 354, height: 521, child: SkyPatchCanvas(session: session, partner: 'Alex')),
    );
    final canvas = tester.getRect(find.byType(SkyPatchCanvas));
    final patch = SkyPatchFeel.frameOf(canvas.size).shift(canvas.topLeft);
    expect(patch.width, closeTo(canvas.width, 0.5));
    expect(patch.height / patch.width, closeTo(1 / SkyDrawnArt.aspect, 1e-6));
    expect(canvas.height - patch.height, lessThan(20));

    for (final at in [Offset(canvas.center.dx - 60, canvas.top + 20), Offset(canvas.center.dx + 60, canvas.bottom - 20)]) {
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 400));
    }
    expect(session.drawing.visibleStars, hasLength(2));
    for (final star in session.drawing.visibleStars) {
      final px = Offset(patch.left + star.x * patch.width, patch.top + star.y * patch.height);
      final nearest = [
        Offset(canvas.center.dx - 60, canvas.top + 20),
        Offset(canvas.center.dx + 60, canvas.bottom - 20),
      ].map((p) => (p - px).distance).reduce((a, b) => a < b ? a : b);
      expect(nearest, lessThan(24));
    }

    await tester.pumpWidget(const SizedBox());
    session.dispose();
    pair.dispose();
  });

  testWidgets('the partner name on the comet follows text size, is laid out once, and only fades in its own small layer', (
    tester,
  ) async {
    final small = SkyPatchLivePainter.tagFor('Alex', night: true, tokens: SkyTokens.night, scaler: TextScaler.noScaling);
    final large = SkyPatchLivePainter.tagFor(
      'Alex',
      night: true,
      tokens: SkyTokens.night,
      scaler: const TextScaler.linear(1.5),
    );
    expect(large.height, greaterThan(small.height));
    large.dispose();

    SkyPatchLive live(double alpha) => SkyPatchLive(
      night: true,
      k: 1,
      motion: false,
      head: const Offset(100, 200),
      cometAlpha: alpha,
      name: 'Alex',
      tag: small,
    );
    final full = LayerCanvas();
    SkyPatchLivePainter(live: ValueNotifier(live(1)), tokens: SkyTokens.night).paint(full, const Size(360, 600));
    expect(full.layers, isEmpty);
    final fading = LayerCanvas();
    SkyPatchLivePainter(live: ValueNotifier(live(0.5)), tokens: SkyTokens.night).paint(fading, const Size(360, 600));
    expect(fading.layers, hasLength(1));
    final bounds = fading.layers.single!;
    expect(bounds.contains(const Offset(112, 178) + Offset(small.width / 2, small.height / 2)), isTrue);
    expect(bounds.width, lessThan(small.width + 2 * SkyPatchLivePainter.tagBleed + 1));
    small.dispose();

    final pair = FakeSkyPair();
    pair.settle();
    final session = SkyPatchSession(link: pair.a, id: 'sky-test', haptic: (_) {});
    await pumpHost(
      tester,
      SizedBox(width: 360, height: 600, child: SkyPatchCanvas(session: session, partner: 'Alex')),
    );
    TextPainter? shown() {
      final paints = tester.widgetList<CustomPaint>(
        find.descendant(of: find.byType(SkyPatchCanvas), matching: find.byType(CustomPaint)),
      );
      final painter = paints.map((p) => p.painter).whereType<SkyPatchLivePainter>().single;
      return painter.live.value.tag;
    }

    final first = shown();
    expect(first, isNotNull);
    session.placeStar(0.4, 0.4);
    await tester.pump();
    session.placeStar(0.6, 0.6);
    await tester.pump();
    expect(shown(), same(first));

    await tester.pumpWidget(const SizedBox());
    session.dispose();
    pair.dispose();
  });
}
