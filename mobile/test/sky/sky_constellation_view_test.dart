import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/presentation/sky/sky.dart';

Widget host(Widget child, {Size size = const Size(160, 120)}) => MediaQuery(
  data: const MediaQueryData(disableAnimations: true),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: Theme(
      data: ThemeData(extensions: const [SkyTokens.night]),
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox.fromSize(size: size, child: child),
      ),
    ),
  ),
);

void main() {
  test('fits any shape into a small box, scaled like the home sky', () {
    const size = Size(160, 120);
    for (final shape in ConstellationShape.values) {
      final fitted = SkyConstellationView.fit(SkyConstellation(shape: shape), size);
      final k = SkyConstellationView.scaleFor(size);
      final bounds = Rect.fromPoints(fitted.bounds.topLeft * k, fitted.bounds.bottomRight * k);
      expect(bounds.left, greaterThanOrEqualTo(-1e-6), reason: shape.name);
      expect(bounds.top, greaterThanOrEqualTo(-1e-6), reason: shape.name);
      expect(bounds.right, lessThanOrEqualTo(160 + 1e-6), reason: shape.name);
      expect(bounds.bottom, lessThanOrEqualTo(120 + 1e-6), reason: shape.name);
      expect(fitted.shape, shape);
    }
  });

  testWidgets('draws a finished constellation on its own layer and hands back the star you touch', (tester) async {
    final touched = <int>[];
    const moon = SkyConstellation(shape: ConstellationShape.moon, complete: true);
    await tester.pumpWidget(host(SkyConstellationView(constellation: moon, onStar: touched.add)));
    expect(
      find.descendant(of: find.byType(SkyConstellationView), matching: find.byType(RepaintBoundary)),
      findsWidgets,
    );
    final painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<SkyLivePainter>()
        .single;
    expect(painter.scene.constellation?.shape, ConstellationShape.moon);
    expect(painter.scene.constellation?.presence, isFalse);
    expect(painter.time.still, isTrue);

    const size = Size(160, 120);
    final k = SkyConstellationView.scaleFor(size);
    final fitted = SkyConstellationView.fit(moon, size);
    final partner = fitted.pointAt(moon.partner) * k;
    await tester.tapAt(partner + const Offset(3, 2));
    expect(touched, [moon.partner]);
    expect(SkyConstellationView.starAt(moon, size, partner), moon.partner);
    expect(SkyConstellationView.starAt(moon, size, const Offset(-80, -80)), isNull);
    expect(tester.takeException(), isNull);
  });
}
