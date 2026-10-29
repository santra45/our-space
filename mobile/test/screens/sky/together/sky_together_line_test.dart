import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/presentation/home_shell.dart';
import 'package:our_space_mobile/presentation/screens/daily/daily_question_card.dart';
import 'package:our_space_mobile/presentation/screens/sky/together/sky_together_copy.dart';
import 'package:our_space_mobile/presentation/screens/sky/together/sky_together_scope.dart';

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
}
