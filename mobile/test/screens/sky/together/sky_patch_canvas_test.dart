import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/presentation/screens/sky/together/sky_patch_canvas.dart';
import 'package:our_space_mobile/presentation/screens/sky/together/sky_patch_session.dart';
import 'package:our_space_mobile/presentation/screens/sky/together/sky_together_layer.dart';

import '../../../support/fake_sky_together.dart';
import '../../../widgets/harness.dart';

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
}
