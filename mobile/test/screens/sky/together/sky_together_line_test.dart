import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/presentation/home_shell.dart';
import 'package:our_space_mobile/presentation/screens/daily/daily_question_card.dart';
import 'package:our_space_mobile/presentation/screens/sky/sky_copy.dart';
import 'package:our_space_mobile/presentation/screens/sky/sky_page.dart';
import 'package:our_space_mobile/presentation/screens/sky/together/sky_together_copy.dart';
import 'package:our_space_mobile/presentation/screens/sky/together/sky_together_fx.dart';
import 'package:our_space_mobile/presentation/screens/sky/together/sky_together_scope.dart';
import 'package:our_space_mobile/presentation/sky/sky.dart';

import '../../../support/fake_sky_together.dart';
import '../../../widgets/harness.dart' show recordHaptics, usePhoneSize;
import '../../love/love_harness.dart';
import '../sky_map_link_test.dart' show loadSkyFonts;
import 'sky_together_flow_test.dart' show Phones;

Future<Phones> homeWith(
  WidgetTester tester, {
  required double width,
  required double text,
  String partner = 'Alex',
  double inset = 24,
}) async {
  usePhoneSize(tester, top: inset);
  tester.view.physicalSize = Size(width * 3, 844 * 3);
  tester.platformDispatcher.textScaleFactorTestValue = text;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
    disableAnimations: true,
    reduceMotion: true,
  );
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  await loadSkyFonts(tester);
  final space = await coupleSpace(tester, partner: partner);
  final phones = Phones(space, FakeSkyPair())..tester = tester;
  await pumpNight(tester, space, shell: SkyTogetherScope(link: phones.pair.a, child: const HomeShell()));
  await untilFound(tester, find.byKey(DailyKeys.card));
  await phones.meet();
  return phones;
}

void main() {
  setUp(recordHaptics);

  for (final partner in ['Alexandria', 'Christopher']) {
    testWidgets('waiting for $partner at bigger text on a small phone wraps under the moon instead of being cut', (
      tester,
    ) async {
      final phones = await homeWith(tester, width: 360, text: 1.3, partner: partner);
      phones.a.press();
      await phones.run(const Duration(milliseconds: 600));
      final line = find.text(SkyTogetherCopy.waiting(partner));
      expect(line, findsOneWidget);
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: line, matching: find.byType(RichText)),
      );
      expect(paragraph.didExceedMaxLines, isFalse);
      final rect = tester.getRect(line);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(360));
      expect(rect.height, greaterThan(paragraph.preferredLineHeight * 1.5));
      await phones.close();
    });
  }

  List<Rect> titleBoxes(WidgetTester tester) {
    final bar = find.descendant(of: find.byType(OurSkyPage), matching: find.byType(SkyTopBar)).first;
    final title = find.descendant(of: bar, matching: find.text(SkyHomeCopy.title(true)));
    final paragraph = tester.renderObject<RenderParagraph>(find.descendant(of: title, matching: find.byType(RichText)));
    final length = paragraph.text.toPlainText().length;
    return [
      for (final box in paragraph.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: length)))
        box.toRect().shift(paragraph.localToGlobal(Offset.zero)),
    ];
  }

  for (final (width, inset, partner) in [
    (390.0, 24.0, 'Alex'),
    (390.0, 44.0, 'Alex'),
    (390.0, 48.0, 'Alexandria'),
    (360.0, 44.0, 'Christopher'),
  ]) {
    testWidgets('at bigger text by night the waiting line keeps clear of the title, $width wide, inset $inset, $partner', (
      tester,
    ) async {
      final phones = await homeWith(tester, width: width, text: 1.3, partner: partner, inset: inset);
      phones.a.press();
      await phones.run(const Duration(milliseconds: 600));
      final line = find.text(SkyTogetherCopy.waiting(partner));
      final rect = tester.getRect(line);
      final boxes = titleBoxes(tester);
      expect(boxes, hasLength(greaterThan(1)));
      for (final box in boxes) {
        expect(box.overlaps(rect), isFalse, reason: 'title $box against line $rect');
      }
      expect(rect.right, lessThanOrEqualTo(width));
      final paragraph = tester.renderObject<RenderParagraph>(find.descendant(of: line, matching: find.byType(RichText)));
      expect(paragraph.didExceedMaxLines, isFalse);
      await phones.close();
    });
  }

  testWidgets('at everyday text the waiting line still sits on one line under the moon', (tester) async {
    final phones = await homeWith(tester, width: 390, text: 1, partner: 'Alexandria');
    phones.a.press();
    await phones.run(const Duration(milliseconds: 600));
    final line = find.text(SkyTogetherCopy.waiting('Alexandria'));
    final rect = tester.getRect(line);
    final paragraph = tester.renderObject<RenderParagraph>(find.descendant(of: line, matching: find.byType(RichText)));
    expect(rect.height, lessThan(paragraph.preferredLineHeight * 1.5));
    expect(rect.right, closeTo(SkyTogetherSpot.lineMax, 0.5));
    expect(rect.left, lessThan(SkyTogetherSpot.lineColumn));
    await phones.close();
  });
}
