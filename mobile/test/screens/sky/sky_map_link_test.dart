import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/presentation/app_shell.dart';
import 'package:our_space_mobile/presentation/home_shell.dart';
import 'package:our_space_mobile/presentation/screens/countdown/milestone_copy.dart';
import 'package:our_space_mobile/presentation/screens/sky/sky_map_page.dart';
import 'package:our_space_mobile/presentation/screens/sky/sky_map_plan.dart';
import 'package:our_space_mobile/presentation/sky/sky.dart';

import '../../widgets/harness.dart';
import '../love/love_harness.dart';

Future<void> loadFont(String family, String asset) async {
  final loader = FontLoader(family)..addFont(rootBundle.load(asset));
  await loader.load();
}

Future<void> loadSkyFonts(WidgetTester tester) => real(tester, () async {
  await loadFont(SkyFonts.serif, 'assets/fonts/bodoni_moda/BodoniModa-Variable.ttf');
  await loadFont(SkyFonts.sans, 'assets/fonts/dm_sans/DMSans-Variable.ttf');
});

void main() {
  setUp(recordHaptics);

  testWidgets('the compact link is a star that still says sky map and is easy to tap', (tester) async {
    var taps = 0;
    await pumpHost(tester, SkyMapLink(compact: true, onTap: () => taps++));
    expect(find.text(SkyMapCopy.action), findsNothing);
    expect(find.byType(SkyIcon), findsOneWidget);
    expect(tester.widget<SkyPressable>(find.byType(SkyPressable)).semanticLabel, SkyMapCopy.action);
    final size = tester.getSize(find.byType(SkyMapLink));
    expect(size.width, greaterThanOrEqualTo(SkySizes.minTap));
    expect(size.height, greaterThanOrEqualTo(SkySizes.minTap));
    expect(size.width, lessThan(SkySizes.minTap + 1));
    await tester.tap(find.byType(SkyMapLink));
    await tester.pump(SkyMotion.fast);
    expect(taps, 1);

    await pumpHost(tester, SkyMapLink(onTap: () {}));
    expect(find.text(SkyMapCopy.action), findsOneWidget);
  });

  testWidgets('on a narrow phone our constellation title stays on one line beside its actions', (tester) async {
    calm(tester);
    tester.view.physicalSize = const Size(1080, 2400);
    await loadSkyFonts(tester);
    final space = await coupleSpace(tester);
    await bothAnswered(tester, space, 2);
    await pumpNight(tester, space, shell: const HomeShell(initialTab: SkyTab.us));
    await untilFound(tester, find.byKey(SkyMapKeys.fromUs));

    final header = find.ancestor(of: find.byKey(SkyMapKeys.fromUs), matching: find.byType(SkySectionHeader));
    final title = find.descendant(of: header, matching: find.text(MilestoneCopy.constellation));
    expect(title, findsOneWidget);
    final style = SkyType.headlineSmall;
    expect(tester.getSize(title).height, lessThan(style.fontSize! * style.height! * 1.5));
    expect(tester.getSize(find.byKey(SkyMapKeys.fromUs)).width, greaterThanOrEqualTo(SkySizes.minTap));
    expect(
      tester.getTopRight(title).dx,
      lessThanOrEqualTo(tester.getTopLeft(find.byKey(SkyMapKeys.fromUs)).dx + 1e-6),
    );
    await settle(tester, space);
  });
}
