import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/presentation/app_shell.dart';
import 'package:our_space_mobile/presentation/home_shell.dart';
import 'package:our_space_mobile/presentation/screens/daily/daily_copy.dart';
import 'package:our_space_mobile/presentation/screens/daily/daily_question_card.dart';
import 'package:our_space_mobile/presentation/screens/letters/letter_shelf.dart';
import 'package:our_space_mobile/presentation/screens/letters/letters_page.dart';
import 'package:our_space_mobile/presentation/screens/settings/settings_page.dart';
import 'package:our_space_mobile/presentation/screens/sky/sky_copy.dart';
import 'package:our_space_mobile/presentation/screens/sky/sky_days.dart';
import 'package:our_space_mobile/presentation/screens/sky/sky_heart_plan.dart';
import 'package:our_space_mobile/presentation/screens/sky/sky_page.dart';
import 'package:our_space_mobile/presentation/screens/sky/sky_sheet_layout.dart';
import 'package:our_space_mobile/presentation/screens/us/us_page.dart';
import 'package:our_space_mobile/presentation/sky/sky.dart';

import '../../widgets/harness.dart' show recordHaptics, usePhoneSize;
import '../love/love_harness.dart';

HeartConstellation homeHeart(WidgetTester tester) =>
    tester.widget<SkyBackdrop>(find.byKey(SkyPageKeys.canvas)).scene.heart!;

SkyScene homeScene(WidgetTester tester) => tester.widget<SkyBackdrop>(find.byKey(SkyPageKeys.canvas)).scene;

String statLabel(WidgetTester tester, Key key) =>
    tester.widget<SkyPressable>(find.byKey(key)).semanticLabel ?? '';

Future<void> waitForCard(WidgetTester tester) => untilFound(tester, find.byKey(DailyKeys.card));

Future<void> backToSky(WidgetTester tester) async {
  await tester.tap(find.descendant(of: find.byKey(ShellKeys.dock), matching: find.text('Sky')));
  await tester.pump();
  await tester.pump();
}

void main() {
  setUp(recordHaptics);

  group('the heart lights one star for every day you both answered', () {
    test('the order touches every point once and closes the heart at the design gap', () {
      expect(SkyHeartPlan.order, hasLength(HeartConstellation.count));
      expect(SkyHeartPlan.order.toSet(), hasLength(HeartConstellation.count));
      expect(SkyHeartPlan.order.take(2), [24, 5]);
      expect(SkyHeartPlan.order.last, 10);
    });

    test('lit stars follow the count, tonight waits in the next gap', () {
      final design = SkyHeartPlan.home(stars: 28, litToday: false, presence: true);
      expect(design.gap, 10);
      expect(design.unlit, isEmpty);
      expect(design.complete, isFalse);
      expect(design.presence, isTrue);

      final early = SkyHeartPlan.home(stars: 5, litToday: false, presence: false);
      expect(early.gap, SkyHeartPlan.order[5]);
      expect(early.unlit, hasLength(23));
      expect([for (var i = 0; i < 29; i++) if (early.isLit(i)) i], unorderedEquals(SkyHeartPlan.order.take(5)));

      final first = SkyHeartPlan.home(stars: 0, litToday: false, presence: false);
      expect(first.gap, 24);
      expect(first.unlit, hasLength(28));

      final lit = SkyHeartPlan.home(stars: 6, litToday: true, presence: false);
      expect(lit.gap, isNull);
      expect(lit.unlit, hasLength(23));
      expect(SkyHeartPlan.tonightIndex(stars: 6, litToday: true), isNull);
      expect(SkyHeartPlan.tonightIndex(stars: 6, litToday: false), SkyHeartPlan.order[6]);
    });

    test('past 29 the heart stays full and tonight waits beside it', () {
      for (final stars in [29, 40]) {
        final heart = SkyHeartPlan.home(stars: stars, litToday: false, presence: false);
        expect(heart.complete, isTrue);
        expect(heart.gap, isNull);
        expect(heart.unlit, isEmpty);
        expect(SkyHeartPlan.tonightAside(stars: stars, litToday: false), isTrue);
        expect(SkyHeartPlan.tonightAside(stars: stars, litToday: true), isFalse);
      }
      expect(SkyHeartPlan.tonightAside(stars: 28, litToday: false), isFalse);
    });

    test('the reveal bursts the star that was just lit', () {
      final design = SkyHeartPlan.reveal(stars: 29);
      expect(design.gap, 10);
      expect(design.complete, isTrue);
      expect(design.burst, isTrue);
      expect(design.presence, isFalse);
      expect(design.unlit, isEmpty);

      final early = SkyHeartPlan.reveal(stars: 5);
      expect(early.gap, SkyHeartPlan.order[4]);
      expect(early.unlit, hasLength(24));
      expect(SkyHeartPlan.reveal(stars: 0).gap, SkyHeartPlan.order.first);
      expect(SkyHeartPlan.reveal(stars: 31).gap, SkyHeartPlan.order[1]);
    });

    test('the tooltip sits beside the gap like the design and avoids names and lit stars', () {
      final design = SkyHeartPlan.home(stars: 28, litToday: false, presence: true);
      final gap = design.pointAt(design.gap!);
      expect(SkyHeartPlan.tipFor(gap, heart: design), SkyHeartPlan.right);
      expect(SkyHeartPlan.tipRect(gap, SkyHeartPlan.right).right, lessThanOrEqualTo(390));

      for (var stars = 0; stars < 29; stars++) {
        final heart = SkyHeartPlan.home(stars: stars, litToday: false, presence: true);
        final at = heart.pointAt(heart.gap!);
        final labels = SkyHeartPlan.labelAreas(heart, me: true, partner: true, partnerChip: true);
        final size = SkyHeartPlan.tipSizeFor("Tonight's star", SkyHomeCopy.answerToLight);
        final placement = SkyHeartPlan.tipFor(at, heart: heart, avoid: labels, size: size);
        final rect = SkyHeartPlan.tipRect(at, placement, size);
        expect(rect.left, greaterThanOrEqualTo(0), reason: '$stars');
        expect(rect.right, lessThanOrEqualTo(390), reason: '$stars');
        final cost = SkyHeartPlan.tipCost(at, placement, size: size, heart: heart, avoid: labels);
        for (final other in [SkyHeartPlan.right, SkyHeartPlan.left, SkyHeartPlan.above, SkyHeartPlan.belowFar]) {
          expect(
            cost,
            lessThanOrEqualTo(SkyHeartPlan.tipCost(at, other, size: size, heart: heart, avoid: labels)),
            reason: '$stars',
          );
        }
      }
    });
  });

  group('days together and the next milestone', () {
    test('the day number counts from the first day', () {
      final start = DateTime(2026, 9, 25);
      expect(SkyDays.dayNumber(start, DateTime(2026, 10, 22, 21, 30)), 28);
      expect(SkyDays.dayNumber(start, DateTime(2026, 9, 25, 23)), 1);
      expect(SkyDays.dayNumber(start, DateTime(2026, 9, 1)), 1);
      expect(SkyDays.startOf('2026-09-25'), start);
      expect(SkyDays.startOf(''), isNull);
      expect(SkyDays.startOf(null), isNull);
    });

    test('the nearest milestone wins: a week, a month, a hundred days or a year', () {
      SkyMilestone next(DateTime start, DateTime now) => SkyDays.next(start, now);
      final month = next(DateTime(2026, 9, 25), DateTime(2026, 10, 22, 22));
      expect(month.name, 'one month');
      expect(month.daysLeft, 3);

      final week = next(DateTime(2026, 10, 20), DateTime(2026, 10, 22));
      expect(week.name, 'one week');
      expect(week.daysLeft, 5);

      final short = next(DateTime(2026, 1, 31), DateTime(2026, 2, 27));
      expect(short.name, 'one month');
      expect(short.date, DateTime(2026, 2, 28));
      expect(short.daysLeft, 1);

      final year = next(DateTime(2025, 10, 22), DateTime(2026, 10, 22, 8));
      expect(year.name, 'one year');
      expect(year.daysLeft, 0);

      final months = next(DateTime(2025, 6, 1), DateTime(2026, 2, 1));
      expect(months.name, 'eight months');
      expect(months.daysLeft, 0);

      final hundred = next(DateTime(2024, 1, 1), DateTime(2024, 4, 5));
      expect(hundred.name, '100 days');
      expect(hundred.daysLeft, 5);

      final later = next(DateTime(2023, 3, 10), DateTime(2024, 12, 1));
      expect(later.name, '700 days');
      expect(later.daysLeft, 68);

      final second = next(DateTime(2023, 3, 10), DateTime(2025, 3, 1));
      expect(second.name, 'two years');
      expect(second.daysLeft, 9);
    });

    test('the home copy reads warmly by night and by day', () {
      expect(SkyHomeCopy.kicker(night: true, dayNumber: 28, weekday: 'Wednesday'), 'Night 28 · Wednesday');
      expect(SkyHomeCopy.kicker(night: false, dayNumber: 28, weekday: 'Wednesday'), 'Day 28 · Wednesday');
      expect(SkyHomeCopy.kicker(night: true, weekday: 'Wednesday'), 'Tonight · Wednesday');
      expect(SkyHomeCopy.title(true), 'Our sky, tonight');
      expect(SkyHomeCopy.title(false), 'Our sky, today');
      expect(SkyHomeCopy.dayOfForever(28), 'Day 28 of forever');
      expect(SkyHomeCopy.starsLabel(1), 'star joined');
      expect(SkyHomeCopy.starsLabel(28), 'stars joined');
      expect(SkyHomeCopy.letters(0), 'No letters');
      expect(SkyHomeCopy.letters(1), '1 letter');
      expect(SkyHomeCopy.letters(3), '3 letters');
      final soon = SkyMilestone(kind: SkyMilestoneKind.month, count: 1, date: DateTime(2026), daysLeft: 2);
      expect(SkyHomeCopy.milestoneValue(soon, night: true), '2 nights');
      expect(SkyHomeCopy.milestoneValue(soon, night: false), '2 days');
      expect(SkyHomeCopy.milestoneLabel(soon), 'to one month');
      final one = SkyMilestone(kind: SkyMilestoneKind.year, count: 2, date: DateTime(2026), daysLeft: 1);
      expect(SkyHomeCopy.milestoneValue(one, night: true), '1 night');
      final now = SkyMilestone(kind: SkyMilestoneKind.hundred, count: 300, date: DateTime(2026), daysLeft: 0);
      expect(SkyHomeCopy.milestoneValue(now, night: true), 'Tonight');
      expect(SkyHomeCopy.milestoneValue(now, night: false), 'Today');
      expect(SkyHomeCopy.milestoneLabel(now), '300 days together');
    });
  });

  group('the sheet rises with its content', () {
    Future<double> topOf(WidgetTester tester, double sheet) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SingleChildScrollView(
            child: SkySheetLayout(
              viewport: 600,
              minTop: 400,
              maxTop: 444,
              child: SizedBox(key: const Key('sheet'), height: sheet),
            ),
          ),
        ),
      );
      return tester.getTopLeft(find.byKey(const Key('sheet'))).dy;
    }

    testWidgets('short content fills down to the bottom, tall content rises then scrolls', (tester) async {
      expect(await topOf(tester, 100), 444);
      expect(tester.getSize(find.byKey(const Key('sheet'))).height, 156);
      expect(await topOf(tester, 180), 420);
      expect(await topOf(tester, 300), 400);
      expect(tester.getSize(find.byType(SkySheetLayout)).height, 700);
    });
  });

  testWidgets('the sky shows tonight, the day count, the stars and tonight\'s question', (tester) async {
    calm(tester);
    final space = await coupleSpace(tester);
    await bothAnswered(tester, space, 3);
    await partnerAnswers(tester, space, 'Already mine');
    await pumpNight(tester, space);
    await waitForCard(tester);

    final now = DateTime.now();
    final start = SkyDays.startOf(startDate)!;
    final day = SkyDays.dayNumber(start, now);
    expect(find.text('NIGHT $day · ${DateFormat('EEEE').format(now).toUpperCase()}'), findsOneWidget);
    expect(find.text('Our sky, tonight'), findsOneWidget);
    expect(find.text("TONIGHT'S QUESTION"), findsOneWidget);
    expect(find.text('Day $day of forever'), findsOneWidget);
    expect(find.byKey(ShellKeys.avatar), findsOneWidget);
    expect(find.byKey(SkyPageKeys.myName), findsOneWidget);
    expect(find.text('Sam'), findsOneWidget);
    expect(find.text('Alex'), findsWidgets);
    expect(find.text(ShellCopy.hereNow), findsNothing);

    expect(statLabel(tester, SkyPageKeys.starsStat), '3 stars joined');
    final milestone = SkyDays.next(start, now);
    expect(
      statLabel(tester, SkyPageKeys.milestoneStat),
      '${SkyHomeCopy.milestoneValue(milestone, night: true)} ${SkyHomeCopy.milestoneLabel(milestone)}',
    );
    expect(statLabel(tester, SkyPageKeys.lettersStat), 'No letters waiting to open');

    final heart = homeHeart(tester);
    expect(heart.gap, SkyHeartPlan.order[3]);
    expect(heart.unlit, hasLength(25));
    expect(heart.presence, isFalse);
    expect(homeScene(tester).shootingStar, isNull);
    expect(find.byKey(SkyPageKeys.letterTip), findsNothing);
    expect(find.byKey(SkyPageKeys.tonightTip), findsOneWidget);
    expect(find.text(SkyHomeCopy.answerToLight), findsOneWidget);
    expect(tester.widget<DailyStatusRow>(find.byType(DailyStatusRow)).status.strong, 'Alex answered');

    await tester.tap(find.byKey(SkyPageKeys.tonightTip));
    await settleRoute(tester);
    expect(find.byKey(DailyKeys.sheet), findsOneWidget);
    await press(tester, iconButton(DailyCopy.close));
    await settleRoute(tester);
    await settle(tester, space);
  });

  testWidgets('by day the same sky speaks of today', (tester) async {
    calm(tester);
    final space = await coupleSpace(tester);
    await pumpLove(
      tester,
      space,
      shell: Theme(data: SkyThemes.legacy(SkyTokens.day), child: const HomeShell()),
    );
    await waitForCard(tester);
    final day = SkyDays.dayNumber(SkyDays.startOf(startDate)!, DateTime.now());
    expect(find.textContaining('DAY $day · '), findsOneWidget);
    expect(find.text('Our sky, today'), findsOneWidget);
    expect(find.text("TODAY'S QUESTION"), findsOneWidget);
    expect(find.text("Light today's star"), findsOneWidget);
    expect(find.text("Today's star"), findsOneWidget);
    await settle(tester, space);
  });

  testWidgets('a waiting letter falls from the sky and leads to Letters', (tester) async {
    calm(tester);
    final space = await coupleSpace(tester);
    final row = await drive(
      tester,
      () => space.letters.writeLetter(title: 'Open when you miss me', content: 'I miss you too'),
    );
    await drive(
      tester,
      () => space.letters.writeLetter(
        title: 'For our anniversary',
        content: 'Not yet',
        unlockDate: toLocalDateInput(DateTime.now().add(const Duration(days: 30))),
      ),
    );
    await pumpNight(tester, space);
    await waitForCard(tester);
    await untilFound(tester, find.byKey(SkyPageKeys.letterTip));
    expect(find.text(SkyHomeCopy.letterFell), findsOneWidget);
    expect(homeScene(tester).shootingStar, isNotNull);
    expect(statLabel(tester, SkyPageKeys.lettersStat), '1 letter waiting to open');

    await tester.tap(find.byKey(SkyPageKeys.letterTip));
    await tester.pump();
    await tester.pump();
    expect(find.byType(LettersPage), findsOneWidget);
    expect(find.byType(OurSkyPage), findsNothing);

    await backToSky(tester);
    await waitForCard(tester);
    await drive(tester, () => space.letters.markOpened(row!['id'] as String));
    await untilGone(tester, find.byKey(SkyPageKeys.letterTip));
    await until(tester, () => statLabel(tester, SkyPageKeys.lettersStat) == 'No letters waiting to open');
    expect(homeScene(tester).shootingStar, isNull);
    await settle(tester, space);
  });

  testWidgets('a letter written on this phone does not fall from her own sky', (tester) async {
    calm(tester);
    final space = await coupleSpace(tester);
    final settings = space.store.settings;
    final mine = await drive(tester, () => space.letters.writeLetter(title: 'For you', content: 'Hello you'));
    await drive(tester, () => LettersWrittenHere.remember(settings, mine!['id'] as String));
    await pumpNight(tester, space);
    await waitForCard(tester);
    expect(find.byKey(SkyPageKeys.letterTip), findsNothing);
    expect(homeScene(tester).shootingStar, isNull);
    expect(statLabel(tester, SkyPageKeys.lettersStat), 'No letters waiting to open');

    final another = await drive(tester, () => space.letters.writeLetter(title: 'Again', content: 'Still you'));
    await untilFound(tester, find.byKey(SkyPageKeys.letterTip));
    await drive(tester, () => LettersWrittenHere.remember(settings, another!['id'] as String));
    await untilGone(tester, find.byKey(SkyPageKeys.letterTip));
    expect(statLabel(tester, SkyPageKeys.lettersStat), 'No letters waiting to open');
    expect(homeScene(tester).shootingStar, isNull);
    await settle(tester, space);
  });

  testWidgets('the stats lead to every day so far, our story and the letters', (tester) async {
    calm(tester);
    final space = await coupleSpace(tester);
    await pumpNight(tester, space);
    await waitForCard(tester);

    await tester.tap(find.byKey(SkyPageKeys.starsStat));
    await settleRoute(tester);
    await untilFound(tester, find.text('EVERY DAY SO FAR'));
    await press(tester, iconButton(DailyCopy.close));
    await settleRoute(tester);

    await tester.tap(find.byKey(SkyPageKeys.milestoneStat));
    await tester.pump();
    await tester.pump();
    expect(find.byType(UsPage), findsOneWidget);

    await backToSky(tester);
    await waitForCard(tester);
    await tester.tap(find.byKey(SkyPageKeys.lettersStat));
    await tester.pump();
    await tester.pump();
    expect(find.byType(LettersPage), findsOneWidget);
    await backToSky(tester);
    await settle(tester, space);
  });

  testWidgets('past 29 stars the heart stays full and the true count shows', (tester) async {
    calm(tester);
    final space = await coupleSpace(tester);
    await bothAnswered(tester, space, 30);
    await pumpNight(tester, space);
    await waitForCard(tester);
    await until(tester, () => statLabel(tester, SkyPageKeys.starsStat) == '30 stars joined');

    final heart = homeHeart(tester);
    expect(heart.complete, isTrue);
    expect(heart.gap, isNull);
    expect(heart.unlit, isEmpty);
    expect(find.byKey(SkyPageKeys.tonightAside), findsOneWidget);
    expect(find.byKey(SkyPageKeys.tonightTip), findsOneWidget);
    await settle(tester, space);
  });

  testWidgets('once you both answered tonight\'s star is lit and the tooltip goes', (tester) async {
    calm(tester);
    final space = await coupleSpace(tester);
    await bothAnswered(tester, space, 2);
    await iAnswer(tester, space, 'Mine tonight');
    await pumpNight(tester, space);
    await waitForCard(tester);
    expect(find.text(SkyHomeCopy.almostLit), findsOneWidget);
    expect(homeHeart(tester).gap, SkyHeartPlan.order[2]);

    await partnerAnswers(tester, space, 'Hers tonight');
    await until(tester, () => statLabel(tester, SkyPageKeys.starsStat) == '3 stars joined');
    final heart = homeHeart(tester);
    expect(heart.gap, isNull);
    expect(heart.unlit, hasLength(26));
    expect(find.byKey(SkyPageKeys.tonightTip), findsNothing);
    expect(find.byKey(SkyPageKeys.tonightAside), findsNothing);
    await settle(tester, space);
  });

  testWidgets('with motion on, the sky, the sheet and the reveal move without errors', (tester) async {
    usePhoneSize(tester);
    final space = await coupleSpace(tester);
    await partnerAnswers(tester, space, 'Waiting for you');
    await drive(tester, () => space.letters.writeLetter(title: 'Hello', content: 'Hello you'));
    await nightSky(tester, space);
    await pumpLove(tester, space);
    await untilFound(tester, find.byType(HomeShell));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    await waitForCard(tester);
    await untilFound(tester, find.byKey(SkyPageKeys.letterTip));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(tester.hasRunningAnimations, isTrue);

    await reveal(tester, find.byKey(DailyKeys.action));
    await tester.tap(find.byKey(DailyKeys.action));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byKey(DailyKeys.sheet), findsOneWidget);
    await tester.enterText(fieldWithHint(DailyCopy.placeholder), 'Your voice');
    await tester.pump();
    await tester.tap(find.byKey(DailyKeys.submit));
    await until(tester, () => find.byKey(DailyKeys.reveal).evaluate().isNotEmpty);
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text("Tonight's star is lit"), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(semanticsLabelled('Back'));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byKey(DailyKeys.reveal), findsNothing);
    expect(tester.takeException(), isNull);
    await settle(tester, space);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('her partner\'s ring and here now show only when the partner is really here', (tester) async {
    calm(tester);
    final space = await coupleSpace(tester);
    await pumpNight(
      tester,
      space,
      shell: const SkyShell(
        presence: PartnerPresence.here(partnerName: 'Alex'),
        myName: 'Sam',
        partnerName: 'Alex',
      ),
    );
    await waitForCard(tester);
    expect(find.text(ShellCopy.hereNow), findsOneWidget);
    expect(homeHeart(tester).presence, isTrue);
    expect(find.byKey(SkyPageKeys.presenceRing), findsOneWidget);
    expect(find.byKey(SkyPageKeys.partnerName), findsOneWidget);

    await tester.tap(find.byKey(ShellKeys.avatar));
    await settleRoute(tester);
    expect(find.byType(SettingsPage), findsOneWidget);
    await settle(tester, space);
  });
}
