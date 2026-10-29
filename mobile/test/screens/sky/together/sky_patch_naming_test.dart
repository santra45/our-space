import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/presentation/screens/sky/together/sky_patch_naming.dart';
import 'package:our_space_mobile/presentation/screens/sky/together/sky_patch_page.dart';
import 'package:our_space_mobile/presentation/screens/sky/together/sky_patch_session.dart';
import 'package:our_space_mobile/presentation/screens/sky/together/sky_together_copy.dart';
import 'package:our_space_mobile/presentation/screens/sky/together/sky_together_layer.dart';
import 'package:our_space_mobile/presentation/sky/sky.dart';

import '../../../support/fake_sky_together.dart';
import '../../../widgets/harness.dart';

TextEditingValue typed(String text) =>
    TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));

void main() {
  group('the name field', () {
    const family = '\u{1F468}‍\u{1F469}‍\u{1F467}‍\u{1F466}';
    const limit = SkyNameLimit();

    test('keeps what was typed when it fits, so the partner sees and keeps the very same name', () {
      final text = 'Our $family night under the big bright';
      expect(text.runes.length, lessThanOrEqualTo(skyDrawingMaxName));
      final out = limit.formatEditUpdate(TextEditingValue.empty, typed(text));
      expect(out.text, text);
      expect(cleanSkyName(out.text), text);
    });

    test('stops at forty characters on a whole emoji, never through the middle of one', () {
      final text = 'Our $family night under the big bright sky';
      expect(text.runes.length, greaterThan(skyDrawingMaxName));
      final out = limit.formatEditUpdate(TextEditingValue.empty, typed(text));
      expect(out.text.runes.length, lessThanOrEqualTo(skyDrawingMaxName));
      expect(text.startsWith(out.text), isTrue);
      expect(cleanSkyName(out.text), out.text.trim());
      expect(out.selection.extentOffset, out.text.length);

      final full = '${'a' * 36}$family';
      final cut = limit.formatEditUpdate(TextEditingValue.empty, typed(full));
      expect(cut.text, 'a' * 36);
      expect(skyHasLoneSurrogate(cut.text), isFalse);
    });
  });

  group('the naming screen', () {
    late FakeSkyPair pair;
    late SkyPatchSession session;

    setUp(() {
      pair = FakeSkyPair();
      pair.settle();
      session = SkyPatchSession(link: pair.a, id: 'sky-test', haptic: (_) {});
      final one = session.placeStar(0.3, 0.3)!;
      final two = session.placeStar(0.7, 0.6)!;
      session.join(one.id, two.id);
    });

    tearDown(() {
      session.dispose();
      pair.dispose();
    });

    Future<void> pumpNaming(
      WidgetTester tester, {
      required Size size,
      double text = 1,
      double keyboard = 0,
      bool motion = false,
    }) async {
      tester.view.physicalSize = size * 3;
      tester.view.devicePixelRatio = 3;
      tester.view.padding = const FakeViewPadding(top: 24 * 3, bottom: 16 * 3);
      tester.view.viewPadding = const FakeViewPadding(top: 24 * 3, bottom: 16 * 3);
      tester.view.viewInsets = FakeViewPadding(bottom: keyboard * 3);
      tester.platformDispatcher.textScaleFactorTestValue = text;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpHost(tester, SkyPatchPage(session: session, partner: 'Alexandria'), animations: motion, scaffold: false);
      await tester.pump(const Duration(seconds: 1));
    }

    for (final (size, text, keyboard) in [
      (const Size(360, 740), 1.3, 320.0),
      (const Size(360, 640), 1.0, 320.0),
      (const Size(360, 640), 1.3, 280.0),
      (const Size(360, 640), 1.3, 320.0),
      (const Size(393, 851), 1.3, 320.0),
    ]) {
      testWidgets('the one naming it fits on a ${size.width.round()}x${size.height.round()} phone at $text with a ${keyboard.round()} keyboard', (tester) async {
        session.finishDrawing();
        await pumpNaming(tester, size: size, text: text, keyboard: keyboard);
        expect(tester.takeException(), isNull);
        expect(find.byType(TextField), findsOneWidget);
        final field = tester.getRect(find.byType(TextField));
        expect(field.bottom, lessThanOrEqualTo(size.height - keyboard + 0.5));
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets('a roomy phone still shows the drawing above the name while typing', (tester) async {
      session.finishDrawing();
      await pumpNaming(tester, size: const Size(393, 851), keyboard: 300);
      expect(find.byType(SkyPatchStill), findsOneWidget);
      expect(tester.getSize(find.byType(SkyPatchStill)).height, greaterThan(80));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('while it is being kept, back to drawing is neither read out nor pressable', (tester) async {
      final handle = tester.ensureSemantics();
      pair.ownerA = 'owner-cccc3333';
      expect(session.leader, isFalse);
      session.finishDrawing();
      session.changeIt();
      await pumpNaming(tester, size: const Size(393, 851));
      expect(find.semantics.byLabel(SkyTogetherCopy.backToDrawing), findsOne);

      pair.injectEvent(pair.a, SkyNameEvent(drawing: session.id, text: 'Kite', rev: 99));
      await tester.pump();
      expect(session.typer, isFalse);
      expect(await session.agree(), isTrue);
      expect(session.step, SkyPatchStep.saving);
      await tester.pump();
      expect(find.semantics.byLabel(SkyTogetherCopy.backToDrawing), findsNothing);
      await tester.tap(find.byType(SkyBackButton), warnIfMissed: false);
      await tester.pump();
      expect(session.step, SkyPatchStep.saving);
      handle.dispose();
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the caret blinks twice a second without keeping the phone drawing every frame', (tester) async {
      session.finishDrawing();
      tester.view.physicalSize = const Size(393, 851) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await pumpHost(tester, SkyPatchNaming(session: session, partner: 'Alex'), animations: true, scaffold: false);
      await tester.pump(const Duration(seconds: 2));
      double caret() => tester
          .widget<Opacity>(find.descendant(of: find.byKey(SkyTogetherKeys.skyName), matching: find.byType(Opacity)))
          .opacity;
      expect(tester.binding.transientCallbackCount, 0);
      final before = caret();
      await tester.pump(const Duration(milliseconds: 500));
      expect(caret(), isNot(before));
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pump(const Duration(milliseconds: 500));
      expect(caret(), before);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the one watching hears the name once when their partner pauses, not every letter', (tester) async {
      tester.view.physicalSize = const Size(393, 851) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final pair = FakeSkyPair();
      pair.settle();
      final session = SkyPatchSession(link: pair.a, id: 'sky-heard', haptic: (_) {});
      addTearDown(pair.dispose);
      addTearDown(session.dispose);
      await pumpHost(tester, SkyPatchNaming(session: session, partner: 'Alex'), scaffold: false);
      var rev = 0;
      for (final text in ['O', 'Ou', 'Our', 'Our k', 'Our ki', 'Our kite']) {
        pair.injectEvent(pair.a, SkyNameEvent(drawing: session.id, text: text, rev: ++rev));
        pair.advance(const Duration(milliseconds: 150));
        await tester.pump(const Duration(milliseconds: 150));
      }
      expect(session.typer, isFalse);
      expect(session.name, 'Our kite');
      expect(tester.takeAnnouncements(), isEmpty);
      await tester.pump(SkyPatchNaming.idle);
      await tester.pump();
      final heard = tester.takeAnnouncements();
      expect(heard, hasLength(1));
      expect(heard.single.message, 'Our kite');
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeAnnouncements(), isEmpty);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
