import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/presentation/app_shell.dart';
import 'package:our_space_mobile/presentation/home_shell.dart';
import 'package:our_space_mobile/presentation/screens/daily/daily_copy.dart';
import 'package:our_space_mobile/presentation/screens/daily/daily_question_card.dart';
import 'package:our_space_mobile/presentation/screens/sky/sky_constellations.dart';
import 'package:our_space_mobile/presentation/screens/sky/sky_map_detail.dart';
import 'package:our_space_mobile/presentation/screens/sky/sky_map_page.dart';
import 'package:our_space_mobile/presentation/screens/sky/sky_map_plan.dart';
import 'package:our_space_mobile/presentation/screens/sky/sky_night_sheet.dart';
import 'package:our_space_mobile/presentation/screens/sky/sky_page.dart';
import 'package:our_space_mobile/presentation/screens/us/us_page.dart';
import 'package:our_space_mobile/presentation/sky/sky.dart';

import '../../widgets/harness.dart' show recordHaptics, usePhoneSize;
import '../love/love_harness.dart';

String starsLabel(WidgetTester tester) =>
    tester.widget<SkyPressable>(find.byKey(SkyPageKeys.starsStat)).semanticLabel ?? '';

Future<void> homeWith(WidgetTester tester, int stars) async {
  await untilFound(tester, find.byKey(DailyKeys.card));
  await until(tester, () => starsLabel(tester) == '$stars ${stars == 1 ? 'star' : 'stars'} joined');
}

Future<void> openMapFromHome(WidgetTester tester) async {
  await tester.tap(find.byKey(SkyPageKeys.starsStat));
  await settleRoute(tester);
  expect(find.byType(SkyMapPage), findsOneWidget);
}

Future<void> back(WidgetTester tester) async {
  await tester.tap(semanticsLabelled('Back').hitTestable().first);
  await settleRoute(tester);
}

String dayOf(int daysAgo) =>
    DateTime.now().subtract(Duration(days: daysAgo)).toUtc().toIso8601String().substring(0, 10);

double entranceOpacity(WidgetTester tester, Finder finder) => tester
    .widget<FadeTransition>(find.ancestor(of: finder, matching: find.byType(FadeTransition)).first)
    .opacity
    .value;

void main() {
  setUp(recordHaptics);

  testWidgets('the stars stat opens the map: the moon still growing first, the finished heart below', (tester) async {
    calm(tester);
    final space = await coupleSpace(tester);
    await bothAnswered(tester, space, 30);
    await pumpNight(tester, space);
    await homeWith(tester, 30);
    await openMapFromHome(tester);

    expect(find.text('30 STARS SO FAR'), findsOneWidget);
    expect(find.text('Still growing · 1 of 29'), findsOneWidget);
    expect(find.text('The Moon'), findsOneWidget);
    expect(find.byKey(SkyMapKeys.keepNote), findsNothing);
    expect(find.text(SkyMapCopy.finished.toUpperCase()), findsOneWidget);

    final series = ConstellationSeries.fromDays([for (var i = 30; i >= 1; i--) dayOf(i)], today: dayOf(0));
    final heart = series.chapter(0);
    final card = find.byKey(SkyMapKeys.constellation(0));
    expect(card, findsOneWidget);
    expect(
      tester.widget<SkyPressable>(find.descendant(of: card, matching: find.byType(SkyPressable)).first).semanticLabel,
      'Our first constellation · The Heart, ${StarNightCopy.range(heart)}, 29 nights',
    );
    expect(find.descendant(of: card, matching: find.text('29 nights')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.text(StarNightCopy.range(heart))), findsOneWidget);

    final growingTop = tester.getTopLeft(find.byKey(SkyMapKeys.growing)).dy;
    final everyDayTop = tester.getTopLeft(find.byKey(SkyMapKeys.everyDay)).dy;
    final heartTop = tester.getTopLeft(card).dy;
    expect(growingTop, lessThan(everyDayTop));
    expect(everyDayTop, lessThan(heartTop));

    await press(tester, card);
    await settleRoute(tester);
    expect(find.byType(SkyMapConstellationPage), findsOneWidget);
    expect(find.text('The Heart'), findsOneWidget);
    expect(find.byKey(SkyMapKeys.night(29)), findsOneWidget);
    expect(find.text('29 nights'), findsOneWidget);

    await back(tester);
    expect(find.byType(SkyMapConstellationPage), findsNothing);
    await press(tester, find.byKey(SkyMapKeys.growing));
    await settleRoute(tester);
    expect(find.text('The Moon'), findsOneWidget);
    expect(find.byKey(SkyMapKeys.night(30)), findsOneWidget);
    expect(find.byKey(SkyMapKeys.night(29)), findsNothing);
    await back(tester);
    await back(tester);
    expect(find.byType(SkyMapPage), findsNothing);
    expect(find.byType(OurSkyPage), findsOneWidget);
    await settle(tester, space);
  });

  testWidgets('the reveal offers the sky map when the 29th star finishes a constellation', (tester) async {
    calm(tester);
    final space = await coupleSpace(tester);
    await bothAnswered(tester, space, 28);
    await iAnswer(tester, space, 'Mine tonight');
    await partnerAnswers(tester, space, 'Hers tonight');
    await pumpNight(tester, space);
    await homeWith(tester, 29);

    await press(tester, find.byKey(DailyKeys.action));
    await settleRoute(tester);
    expect(find.byKey(DailyKeys.reveal), findsOneWidget);
    expect(find.text('Our first constellation is complete'), findsOneWidget);
    expect(find.text(SkyMapCopy.seeInMap), findsOneWidget);
    expect(find.byKey(DailyKeys.everyDay), findsOneWidget);
    expect(find.byKey(DailyKeys.sendLove), findsOneWidget);

    await press(tester, find.byKey(SkyMapKeys.fromReveal));
    await settleRoute(tester);
    expect(find.byType(SkyMapPage), findsOneWidget);
    expect(find.byKey(SkyMapKeys.growing), findsNothing);
    expect(find.byKey(SkyMapKeys.constellation(0)), findsOneWidget);
    expect(find.text('29 STARS SO FAR'), findsOneWidget);

    await back(tester);
    expect(find.byType(SkyMapPage), findsNothing);
    expect(find.byKey(DailyKeys.reveal), findsOneWidget);
    await back(tester);
    await settle(tester, space);
  });

  testWidgets('a star that finishes nothing keeps the reveal as it was', (tester) async {
    calm(tester);
    final space = await coupleSpace(tester);
    await bothAnswered(tester, space, 2);
    await iAnswer(tester, space, 'Mine tonight');
    await partnerAnswers(tester, space, 'Hers tonight');
    await pumpNight(tester, space);
    await homeWith(tester, 3);
    await press(tester, find.byKey(DailyKeys.action));
    await settleRoute(tester);
    expect(find.byKey(DailyKeys.reveal), findsOneWidget);
    expect(find.byKey(SkyMapKeys.fromReveal), findsNothing);
    expect(find.text("Tonight's star is lit"), findsOneWidget);
    await back(tester);
    await settle(tester, space);
  });

  testWidgets('our constellation on Us has a sky map action', (tester) async {
    calm(tester);
    final space = await coupleSpace(tester);
    await bothAnswered(tester, space, 4);
    await pumpNight(tester, space, shell: const HomeShell(initialTab: SkyTab.us));
    await untilFound(tester, find.byKey(SkyMapKeys.fromUs));
    final link = tester.getSize(find.byKey(SkyMapKeys.fromUs));
    expect(link.width, greaterThanOrEqualTo(SkySizes.minTap));
    expect(link.height, greaterThanOrEqualTo(SkySizes.minTap));
    expect(find.descendant(of: find.byKey(SkyMapKeys.fromUs), matching: find.text(SkyMapCopy.action)), findsOneWidget);

    await press(tester, find.byKey(SkyMapKeys.fromUs));
    await settleRoute(tester);
    expect(find.byType(SkyMapPage), findsOneWidget);
    await untilFound(tester, find.text('Still growing · 4 of 29'));
    await back(tester);
    expect(find.byType(SkyMapPage), findsNothing);
    expect(find.byType(UsPage), findsOneWidget);
    await settle(tester, space);
  });

  testWidgets('answering tonight from the map still shows the star being lit', (tester) async {
    calm(tester);
    final space = await coupleSpace(tester);
    await bothAnswered(tester, space, 1);
    await partnerAnswers(tester, space, 'Hers tonight');
    await pumpNight(tester, space);
    await homeWith(tester, 1);
    await openMapFromHome(tester);

    await press(tester, find.byKey(SkyMapKeys.everyDay));
    await settleRoute(tester);
    await untilFound(tester, find.text('EVERY DAY SO FAR'));
    await press(tester, find.text(DailyCopy.backToToday));
    await settleRoute(tester);
    await type(tester, fieldWithHint(DailyCopy.placeholder), 'Mine tonight');
    await press(tester, find.byKey(DailyKeys.submit));
    await untilFound(tester, find.byKey(DailyKeys.reveal));
    await settleRoute(tester);
    expect(find.text("Tonight's star is lit"), findsOneWidget);
    await back(tester);
    expect(find.byType(SkyMapPage), findsOneWidget);
    await until(tester, () => find.text('Still growing · 2 of 29').evaluate().isNotEmpty);
    await settle(tester, space);
  });

  testWidgets('a lit star in the large view opens its night and every day so far from there', (tester) async {
    calm(tester);
    final space = await coupleSpace(tester);
    await bothAnswered(tester, space, 3);
    await pumpNight(tester, space);
    await homeWith(tester, 3);
    await openMapFromHome(tester);
    await press(tester, find.byKey(SkyMapKeys.growing));
    await settleRoute(tester);

    final night = tester.widget<Semantics>(find.byKey(SkyMapKeys.night(2)));
    expect(night.properties.label, StarNightCopy.title(StarNight(number: 2, day: dayOf(2))));
    night.properties.onTap!();
    await settleRoute(tester);
    expect(find.byKey(StarNightKeys.sheet), findsOneWidget);
    expect(find.text('Mine 2'), findsOneWidget);
    await tester.tap(find.byKey(StarNightKeys.everyDay));
    await settleRoute(tester);
    await untilFound(tester, find.text('EVERY DAY SO FAR'));
    await press(tester, iconButton(DailyCopy.close));
    await settleRoute(tester);
    expect(find.byType(SkyMapConstellationPage), findsOneWidget);
    await settle(tester, space);
  });

  testWidgets('locking closes the map and the large view', (tester) async {
    calm(tester);
    final space = await coupleSpace(tester);
    await bothAnswered(tester, space, 2);
    await pumpNight(tester, space);
    await homeWith(tester, 2);
    await openMapFromHome(tester);
    await press(tester, find.byKey(SkyMapKeys.growing));
    await settleRoute(tester);
    expect(find.byType(SkyMapConstellationPage), findsOneWidget);

    space.vault.lock();
    await tester.pump();
    await settleRoute(tester);
    await settleRoute(tester);
    expect(find.byType(SkyMapConstellationPage), findsNothing);
    expect(find.byType(SkyMapPage), findsNothing);
    expect(find.text('Mine 1'), findsNothing);
  });

  testWidgets('with motion on, the map comes in one by one, a card gives under a finger and the large view fades in', (
    tester,
  ) async {
    usePhoneSize(tester);
    final space = await coupleSpace(tester);
    await bothAnswered(tester, space, 30);
    await nightSky(tester, space);
    await pumpLove(tester, space);
    await untilFound(tester, find.byType(HomeShell));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    await homeWith(tester, 30);

    await tester.tap(find.byKey(SkyPageKeys.starsStat));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final growing = entranceOpacity(tester, find.byKey(SkyMapKeys.growing));
    final finished = entranceOpacity(tester, find.byKey(SkyMapKeys.constellation(0)));
    expect(growing, greaterThan(finished));
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(entranceOpacity(tester, find.byKey(SkyMapKeys.constellation(0))), 1);
    expect(tester.takeException(), isNull);

    final card = find.byKey(SkyMapKeys.constellation(0));
    final gesture = await tester.startGesture(tester.getCenter(card));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final pressed = tester.widget<Transform>(find.descendant(of: card, matching: find.byType(Transform)).first);
    expect(pressed.transform.entry(0, 0), closeTo(0.98, 0.001));
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.byType(SkyMapConstellationPage), findsOneWidget);
    final fading = tester.widget<SkyBackdrop>(find.byKey(SkyMapKeys.canvas)).scene.constellation!.dim;
    expect(fading, lessThan(1));
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(tester.widget<SkyBackdrop>(find.byKey(SkyMapKeys.canvas)).scene.constellation!.dim, 1);
    expect(tester.takeException(), isNull);
    await settle(tester, space);
    await tester.pumpWidget(const SizedBox());
  });
}
