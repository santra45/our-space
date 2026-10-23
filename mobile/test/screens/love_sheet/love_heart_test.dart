import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/presentation/screens/love/widgets/love_heart.dart';
import 'package:our_space_mobile/presentation/sky/sky.dart';
import 'package:our_space_mobile/presentation/widgets/app_haptics.dart';

import '../../widgets/harness.dart' show recordHaptics, recordedHaptics, usePhoneSize;
import 'love_sheet_harness.dart' show heartHost, labelled;

class _Calls {
  int starts = 0;
  int cancels = 0;
  int hints = 0;
  int sends = 0;
}

Widget _heart(_Calls calls, {bool enabled = true}) => LoveHeart(
      semanticLabel: 'Send love to Alex',
      semanticHint: 'Hold to send',
      enabled: enabled,
      onHoldStart: () => calls.starts++,
      onHoldCancel: () => calls.cancels++,
      onHint: () => calls.hints++,
      onSend: () => calls.sends++,
    );

LoveHeartPainter _painter(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(
    find.descendant(of: find.byType(LoveHeart), matching: find.byType(CustomPaint)),
  );
  return paint.painter! as LoveHeartPainter;
}

Future<void> _hold(WidgetTester tester, Duration length) async {
  final gesture = await tester.startGesture(tester.getCenter(labelled('Send love to Alex')));
  await tester.pump();
  await tester.pump(length);
  await tester.pump();
  await gesture.up();
  await tester.pump();
}

void main() {
  setUp(recordHaptics);

  testWidgets('holding the heart until it fills sends once and plays the burst', (tester) async {
    usePhoneSize(tester);
    final calls = _Calls();
    await tester.pumpWidget(heartHost(_heart(calls)));
    await tester.pump();
    expect(tester.getSize(find.byType(LoveHeart)), const Size(LoveHeart.width, LoveHeart.height));

    final gesture = await tester.startGesture(tester.getCenter(labelled('Send love to Alex')));
    await tester.pump();
    expect(calls.starts, 1);
    expect(recordedHaptics, [HapticKind.tick]);
    await tester.pump(LoveHeart.holdDuration ~/ 2);
    expect(_painter(tester).hold.value, closeTo(0.5, 0.05));
    expect(calls.sends, 0);
    await tester.pump(LoveHeart.holdDuration ~/ 2 + const Duration(milliseconds: 20));
    await tester.pump();
    expect(calls.sends, 1);
    await tester.pump(const Duration(milliseconds: 60));
    expect(_painter(tester).burst.value, greaterThan(0));
    await gesture.up();
    await tester.pump();
    expect(calls.hints, 0);
    expect(calls.cancels, 0);

    await tester.pump(SkyMotion.burst ~/ 2);
    expect(_painter(tester).burst.value, inInclusiveRange(0.3, 0.7));
    await tester.pump(SkyMotion.burst);
    expect(_painter(tester).burst.value, 1);
    expect(_painter(tester).hold.value, 0);
    expect(calls.sends, 1);
  });

  testWidgets('a quick tap nudges with a hint instead of sending', (tester) async {
    usePhoneSize(tester);
    final calls = _Calls();
    await tester.pumpWidget(heartHost(_heart(calls)));
    await tester.pump();

    await tester.tap(labelled('Send love to Alex'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(calls.hints, 1);
    expect(calls.sends, 0);
    expect(_painter(tester).nudge.value, greaterThan(0));
    await tester.pump(const Duration(seconds: 1));
    expect(_painter(tester).hold.value, 0);

    await _hold(tester, LoveHeart.holdDuration ~/ 2);
    expect(calls.hints, 2);
    expect(calls.sends, 0);
  });

  testWidgets('sliding the finger away lets go without a hint', (tester) async {
    usePhoneSize(tester);
    final calls = _Calls();
    await tester.pumpWidget(heartHost(_heart(calls)));
    await tester.pump();

    final gesture = await tester.startGesture(tester.getCenter(labelled('Send love to Alex')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    expect(calls.cancels, 1);
    await tester.pump(LoveHeart.holdDuration);
    await gesture.up();
    await tester.pump();
    expect(calls.sends, 0);
    expect(calls.hints, 0);
  });

  testWidgets('a resting heart ignores touches', (tester) async {
    usePhoneSize(tester);
    final calls = _Calls();
    await tester.pumpWidget(heartHost(_heart(calls, enabled: false)));
    await tester.pump();

    await _hold(tester, LoveHeart.holdDuration * 2);
    expect(calls.starts, 0);
    expect(calls.sends, 0);
    expect(calls.hints, 0);
    expect(recordedHaptics, isEmpty);
    final semantics = tester.widget<Semantics>(labelled('Send love to Alex'));
    expect(semantics.properties.enabled, isFalse);
    expect(semantics.properties.onTap, isNull);
  });

  testWidgets('a screen reader tap or long press sends straight away', (tester) async {
    usePhoneSize(tester);
    final calls = _Calls();
    await tester.pumpWidget(heartHost(_heart(calls), animations: false));
    await tester.pump();

    final semantics = tester.widget<Semantics>(labelled('Send love to Alex'));
    expect(semantics.properties.button, isTrue);
    expect(semantics.properties.hint, 'Hold to send');
    semantics.properties.onTap!();
    await tester.pump();
    semantics.properties.onLongPress!();
    await tester.pump();
    expect(calls.sends, 2);
    expect(_painter(tester).burst.value, 0);
  });

  testWidgets('the hold still takes its full time when motion is reduced', (tester) async {
    usePhoneSize(tester);
    final calls = _Calls();
    await tester.pumpWidget(heartHost(_heart(calls), animations: false));
    await tester.pump();
    expect(_painter(tester).live, isFalse);

    final gesture = await tester.startGesture(tester.getCenter(labelled('Send love to Alex')));
    await tester.pump();
    await tester.pump(LoveHeart.holdDuration ~/ 3);
    expect(calls.sends, 0);
    await tester.pump(LoveHeart.holdDuration);
    await tester.pump();
    expect(calls.sends, 1);
    expect(_painter(tester).burst.value, 0);
    expect(_painter(tester).hold.value, 0);
    await gesture.up();
    await tester.pump();
  });

  testWidgets('the heart paints with night and day colours', (tester) async {
    usePhoneSize(tester);
    final calls = _Calls();
    await tester.pumpWidget(heartHost(_heart(calls)));
    await tester.pump(const Duration(milliseconds: 400));
    expect(_painter(tester).tokens.isNight, isTrue);
    expect(_painter(tester).live, isTrue);
    expect(_painter(tester).idle.value, greaterThan(0));

    await tester.pumpWidget(heartHost(_heart(calls), tokens: SkyTokens.day));
    await tester.pump(const Duration(milliseconds: 400));
    expect(_painter(tester).tokens.isDay, isTrue);
    await _hold(tester, LoveHeart.holdDuration + const Duration(milliseconds: 40));
    await tester.pump(SkyMotion.burst ~/ 2);
    expect(calls.sends, 1);
    expect(tester.takeException(), isNull);
  });

  test('the heart path matches the duotone icon outline', () {
    final bounds = LoveShapes.heart.getBounds();
    expect(bounds.left, closeTo(2.5, 0.01));
    expect(bounds.right, closeTo(21.5, 0.01));
    expect(bounds.top, closeTo(3.5, 0.3));
    expect(bounds.bottom, closeTo(20.5, 0.01));
    expect(LoveHeart.sparks, hasLength(26));
    expect(LoveHeart.floats, hasLength(5));
  });
}
