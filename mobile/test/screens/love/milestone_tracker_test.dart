import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/presentation/screens/countdown/constellation.dart';
import 'package:our_space_mobile/presentation/screens/countdown/live_love_counter.dart';
import 'package:our_space_mobile/presentation/screens/countdown/milestone_copy.dart';
import 'package:our_space_mobile/presentation/screens/countdown/upcoming_milestones.dart';
import 'package:our_space_mobile/presentation/screens/us/us_copy.dart';
import 'package:our_space_mobile/presentation/screens/us/us_keys.dart';
import 'package:our_space_mobile/presentation/sky/sky.dart';
import 'package:our_space_mobile/presentation/widgets/app_haptics.dart';

import '../us/us_harness.dart';

Finder step(Key key) => find.byKey(key);

Finder momentStep(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(ConstellationStep));

double topOf(WidgetTester tester, Finder finder) => tester.getTopLeft(finder).dy;

void main() {
  group('milestone copy', () {
    test('hidden moments are counted like before', () {
      expect(
        MilestoneCopy.hidden(1),
        '1 moment could not be opened with your passphrase, so it is hidden for now.',
      );
      expect(
        MilestoneCopy.hidden(3),
        '3 moments could not be opened with your passphrase, so they are hidden for now.',
      );
      expect(MilestoneCopy.notice(error: '', unreadable: 0), isNull);
      expect(MilestoneCopy.notice(error: '', unreadable: 2), MilestoneCopy.hidden(2));
      expect(MilestoneCopy.notice(error: MilestoneCopy.saveFailed, unreadable: 2), MilestoneCopy.saveFailed);
    });

    test('counts days, months and years in plain words', () {
      expect(MilestoneCopy.inDays(0), 'today');
      expect(MilestoneCopy.inDays(1), 'tomorrow');
      expect(MilestoneCopy.inDays(72), 'in 72 days');
      expect(MilestoneCopy.months(1), 'One month');
      expect(MilestoneCopy.months(6), 'Six months');
      expect(MilestoneCopy.years(1), 'First year');
      expect(MilestoneCopy.years(4), 'Four years');
      expect(MilestoneCopy.years(14), '14 years');
      expect(MilestoneCopy.hundred(1500), 'Day 1500');
      expect(MilestoneCopy.today(28), 'Today · day 28');
      expect(MilestoneCopy.todayLit(29), 'Star 29 lit, you both answered');
      expect(MilestoneCopy.todayWaiting(night: true), "Tonight's star is waiting");
      expect(MilestoneCopy.todayWaiting(night: false), "Today's star is waiting");
      expect(MilestoneCopy.todayStar(lit: true, stars: 29, night: true), MilestoneCopy.todayLit(29));
      expect(MilestoneCopy.todayStar(lit: false, stars: 28, night: false), MilestoneCopy.todayWaiting(night: false));
      expect(MilestoneCopy.todayStar(lit: null, stars: 3, night: true), MilestoneCopy.todayNote);
      expect(MilestoneCopy.clock(1, 1, 1), 'Together 1 day, 1 hour and 1 minute');
      expect(MilestoneCopy.clock(28, 14, 32), 'Together 28 days, 14 hours and 32 minutes');
      expect(MilestoneCopy.dayWord(1), 'day');
      expect(MilestoneCopy.dayWord(28), 'days');
      expect(twoDigitCount(7), '07');
      expect(twoDigitCount(42), '42');
    });

    test('dates read like a person would say them', () {
      final now = DateTime(2025, 10, 23);
      expect(UsDates.long(DateTime(2025, 9, 25), now), '25 September');
      expect(UsDates.long(DateTime(2021, 6, 14), now), '14 June 2021');
      expect(UsDates.short(DateTime(2025, 10, 2), now), '2 Oct');
      expect(UsDates.short(DateTime(2021, 6, 14), now), '14 Jun 2021');
      expect(UsDates.full(DateTime(2025, 9, 25)), '25 September 2025');
    });
  });

  group('upcoming milestones', () {
    test('a new couple sees one month, day 100 and the first year, soonest first', () {
      final items = upcomingMilestones('2025-09-25', DateTime(2025, 10, 23, 14, 32));
      expect(items.map((item) => item.title), ['One month', 'Day 100', 'First year']);
      expect(items.map((item) => item.when), ['in 2 days', 'in 72 days', 'in 337 days']);
      expect(items.map((item) => item.icon), [SkyIcons.moon, SkyIcons.star, SkyIcons.sparkle]);
    });

    test('the month count keeps the day, or the last day of a short month', () {
      expect(monthsAfter(DateTime(2025, 1, 31), 1), DateTime(2025, 2, 28));
      expect(monthsAfter(DateTime(2024, 1, 31), 1), DateTime(2024, 2, 29));
      expect(monthsAfter(DateTime(2025, 11, 15), 3), DateTime(2026, 2, 15));
      final items = upcomingMilestones('2025-01-31', DateTime(2025, 2, 10));
      expect(items.first.title, 'One month');
      expect(items.first.daysLeft, 18);
      final later = upcomingMilestones('2025-01-31', DateTime(2025, 3, 1));
      expect(later.first.title, 'Two months');
      expect(later.first.daysLeft, 30);
    });

    test('after the first year only the anniversary and the next hundred remain', () {
      final items = upcomingMilestones('2021-06-14', DateTime(2025, 6, 14, 10));
      expect(items.map((item) => item.kind), [UpcomingKind.anniversary, UpcomingKind.hundred]);
      expect(items.first.title, 'Four years');
      expect(items.first.when, 'today');
      expect(items.first.isToday, isTrue);
      expect(items.last.title, 'Day 1500');
      expect(items.last.when, 'in 39 days');
    });

    test('a month mark and the start of a hundred can both be today', () {
      final items = upcomingMilestones('2025-09-25', DateTime(2025, 10, 25, 8));
      expect(items.first.title, 'One month');
      expect(items.first.when, 'today');
    });

    test('nothing to count without a start date', () {
      expect(upcomingMilestones('', DateTime(2025, 6, 14)), isEmpty);
      expect(upcomingMilestones(null, DateTime(2025, 6, 14)), isEmpty);
    });
  });

  group('live love counter', () {
    testWidgets('ticks every second from the start date', (tester) async {
      var now = DateTime(2025, 10, 12, 9, 7, 5).millisecondsSinceEpoch;
      final counter = LiveLoveCounter(clock: () => now);
      var ticks = 0;
      counter.addListener(() => ticks++);

      counter.track(null);
      expect(counter.value.totalDays, 0);
      expect(counter.ticking, isFalse);

      counter.track(usStartDate);
      final first = calculateLoveDuration(usStartDate, now: now);
      expect(counter.value.totalDays, first.totalDays);
      expect(counter.value.seconds, 5);
      expect(counter.ticking, isTrue);

      now += 1000;
      await tester.pump(const Duration(seconds: 1));
      expect(ticks, 1);
      expect(counter.value.seconds, 6);

      counter.track(usStartDate);
      expect(counter.value.seconds, 6);
      expect(ticks, 1);

      counter.track('2021-06-15');
      expect(counter.value.totalDays, first.totalDays - 1);

      counter.dispose();
      expect(counter.ticking, isFalse);
    });
  });

  testWidgets("today on our constellation says whether tonight's star is lit yet", (tester) async {
    calm(tester);
    final space = await usSpace(tester);
    await pumpUs(tester, space);
    final today = find.byKey(UsKeys.todayStep);
    await untilFound(tester, find.descendant(of: today, matching: find.textContaining('star is waiting')));

    await drive(tester, () async {
      final key = space.vault.key;
      await space.dailyQuestion.saveAnswer(key, ownerId: space.identity.myOwnerId, questionId: null, text: 'Mine');
      await space.dailyQuestion.saveAnswer(
        key,
        ownerId: space.identity.partner!.personId,
        questionId: null,
        text: 'Theirs',
      );
    });
    await untilFound(tester, find.descendant(of: today, matching: find.text(MilestoneCopy.todayLit(1))));
    expect(find.textContaining('star is waiting'), findsNothing);
    await rest(tester, space);
  });

  testWidgets('the counter ticks live, with the days in gold and the next milestones beside it', (tester) async {
    calm(tester);
    var now = DateTime(2025, 10, 12, 9, 7, 5).millisecondsSinceEpoch;
    final space = await usSpace(tester);
    await pumpUs(tester, space, clock: () => now);
    await untilFound(tester, find.text('TOGETHER, AND COUNTING'));

    final duration = calculateLoveDuration(usStartDate, now: now);
    expect(find.text('${duration.totalDays}'), findsOneWidget);
    expect(find.text(twoDigitCount(duration.hours)), findsOneWidget);
    expect(find.text(twoDigitCount(duration.minutes)), findsOneWidget);
    expect(find.text('05'), findsOneWidget);
    expect(find.text('days'), findsOneWidget);
    expect(find.text(MilestoneCopy.and), findsOneWidget);
    for (final label in ['HRS', 'MIN', 'SEC']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('THE TWO OF US'), findsOneWidget);
    expect(find.descendant(of: find.byKey(UsKeys.since), matching: find.text('Since 14 June 2021')), findsOneWidget);
    expect(find.text('Us'), findsWidgets);
    final gold = tester.widget<Text>(find.text('${duration.totalDays}')).style!;
    expect(gold.color, SkyTokens.night.gold);
    expect(gold.fontStyle, FontStyle.italic);
    expect(labelled(MilestoneCopy.clock(duration.totalDays, duration.hours, duration.minutes)), findsOneWidget);

    final upcoming = upcomingMilestones(usStartDate, DateTime.fromMillisecondsSinceEpoch(now));
    expect(upcoming.map((item) => item.title), ['Day 1600', 'Five years']);
    for (final item in upcoming) {
      expect(find.text(item.title), findsOneWidget);
      expect(find.text(item.when), findsOneWidget);
      expect(labelled('${item.title}, ${item.when}'), findsOneWidget);
    }
    expect(find.text(MilestoneCopy.today(duration.totalDays)), findsOneWidget);

    now += 1000;
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('06'), findsOneWidget);
    expect(find.text('05'), findsNothing);

    now = DateTime(2025, 6, 14, 10).millisecondsSinceEpoch;
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Four years'), findsOneWidget);
    expect(find.text('today'), findsOneWidget);
    expect(find.text('Day 1500'), findsOneWidget);
    expect(find.text('in 39 days'), findsOneWidget);
    await rest(tester, space);
  });

  testWidgets('with no start date it counts from today', (tester) async {
    calm(tester);
    final now = DateTime(2025, 10, 12, 18, 30).millisecondsSinceEpoch;
    final space = await usSpace(tester);
    await real(tester, () => space.vault.updateSettings(startDate: ''));
    expect(space.vault.config?.startDate, '');

    await pumpUs(tester, space, clock: () => now);
    await untilFound(tester, find.text('TOGETHER, AND COUNTING'));
    expect(find.text('0'), findsOneWidget);
    expect(find.text('18'), findsOneWidget);
    expect(find.text('30'), findsOneWidget);
    expect(find.text('Since 12 October 2025'), findsOneWidget);
    expect(find.text(MilestoneCopy.beganNote('12 Oct')), findsOneWidget);
    expect(find.text('One month'), findsOneWidget);
    await rest(tester, space);
  });

  testWidgets('the day we began is changed from the counter', (tester) async {
    calm(tester);
    final now = DateTime(2025, 10, 12, 9).millisecondsSinceEpoch;
    final space = await usSpace(tester);
    await pumpUs(tester, space, clock: () => now);
    await untilFound(tester, find.text('Since 14 June 2021'));

    await pressAndSettle(tester, find.byKey(UsKeys.hero));
    expect(find.text(MilestoneCopy.dayTitle), findsOneWidget);
    expect(find.text(MilestoneCopy.dayMessage), findsOneWidget);
    expect(labelled('${MilestoneCopy.dayField}, 14 June 2021'), findsOneWidget);
    expect(find.text('14 June 2021'), findsOneWidget);

    await pressAndSettle(tester, find.text(MilestoneCopy.notNow));
    expect(find.text(MilestoneCopy.dayTitle), findsNothing);
    expect(space.vault.config?.startDate, usStartDate);

    await pressAndSettle(tester, find.byKey(UsKeys.hero));
    await pickDay(tester, UsKeys.togetherDate, '20');
    expect(find.text('20 June 2021'), findsOneWidget);
    expect(space.vault.config?.startDate, usStartDate);

    recordedHaptics.clear();
    await press(tester, find.byKey(UsKeys.togetherSave));
    await until(tester, () => space.vault.config?.startDate == '2021-06-20');
    await settleRoutes(tester);
    await untilFound(tester, find.text('Since 20 June 2021'));
    expect(find.text(MilestoneCopy.dayTitle), findsNothing);
    expect(recordedHaptics, contains(HapticKind.celebration));
    final duration = calculateLoveDuration('2021-06-20', now: now);
    expect(find.text('${duration.totalDays}'), findsOneWidget);
    expect(find.text(MilestoneCopy.beganNote('20 Jun 2021')), findsOneWidget);
    await rest(tester, space);
  });

  testWidgets('the day we began is also changed from where it all began', (tester) async {
    calm(tester);
    final space = await usSpace(tester);
    await pumpUs(tester, space);
    await untilFound(tester, find.byKey(UsKeys.beganStep));
    expect(find.text(MilestoneCopy.began), findsOneWidget);
    expect(find.text(MilestoneCopy.beganNote('14 Jun 2021')), findsOneWidget);
    expect(labelled(MilestoneCopy.changeDay), findsNWidgets(2));

    await pressAndSettle(tester, find.byKey(UsKeys.beganStep));
    expect(find.text(MilestoneCopy.dayTitle), findsOneWidget);
    await pickDay(tester, UsKeys.togetherDate, '1');
    await press(tester, find.byKey(UsKeys.togetherSave));
    await until(tester, () => space.vault.config?.startDate == '2021-06-01');
    await settleRoutes(tester);
    await untilFound(tester, find.text(MilestoneCopy.beganNote('1 Jun 2021')));
    await rest(tester, space);
  });

  testWidgets('moments are added, changed and removed in our constellation', (tester) async {
    calm(tester);
    final space = await usSpace(tester);
    await real(tester, () => space.milestones.add(title: 'First date', date: '2021-06-14'));

    await pumpUs(tester, space);
    await untilFound(tester, find.text('First date'));
    expect(find.text(MilestoneCopy.constellation), findsOneWidget);
    expect(find.text('14 Jun 2021'), findsOneWidget);
    expect(find.byKey(UsKeys.emptyStep), findsNothing);
    expect(topOf(tester, find.byKey(UsKeys.todayStep)), lessThan(topOf(tester, momentStep('First date'))));
    expect(topOf(tester, momentStep('First date')), lessThan(topOf(tester, find.byKey(UsKeys.beganStep))));

    await pressAndSettle(tester, find.text(MilestoneCopy.addMoment));
    expect(find.text(MilestoneCopy.newTitle), findsOneWidget);
    final today = DateTime.now();
    expect(find.text(UsDates.full(today)), findsOneWidget);
    expect(buttonEnabled(tester, UsKeys.momentSave), isFalse);
    await press(tester, find.byKey(UsKeys.momentSave));
    expect(find.text(MilestoneCopy.newTitle), findsOneWidget);
    expect(await drive(tester, space.milestones.list), hasLength(1));

    recordedHaptics.clear();
    await typeInto(tester, fieldIn(UsKeys.momentTitle), '  Moved in together  ');
    expect(buttonEnabled(tester, UsKeys.momentSave), isTrue);
    await press(tester, find.byKey(UsKeys.momentSave));
    await untilFound(tester, find.text('Moved in together'));
    await settleRoutes(tester);
    expect(find.text(MilestoneCopy.newTitle), findsNothing);
    expect(recordedHaptics, contains(HapticKind.celebration));
    expect(find.text(UsDates.short(today, today)), findsWidgets);
    expect(topOf(tester, momentStep('Moved in together')), lessThan(topOf(tester, momentStep('First date'))));

    final stored = await drive(tester, space.milestones.list);
    expect(stored.map((m) => m.title), ['Moved in together', 'First date']);
    expect(stored.first.date, toLocalDateInput(today));
    final firstDate = stored.last;

    await pressAndSettle(tester, find.byKey(UsKeys.moment(firstDate.id)));
    expect(find.text(MilestoneCopy.editTitle), findsOneWidget);
    expect(fieldText(tester, UsKeys.momentTitle), 'First date');
    expect(find.text('14 June 2021'), findsOneWidget);
    expect(find.byKey(UsKeys.momentRemove), findsOneWidget);

    await tester.tapAt(const Offset(20, 40));
    await settleRoutes(tester);
    expect(find.text(MilestoneCopy.editTitle), findsNothing);

    await pressAndSettle(tester, find.byKey(UsKeys.moment(firstDate.id)));
    await typeInto(tester, fieldIn(UsKeys.momentTitle), 'Our very first date');
    await pickDay(tester, UsKeys.momentDate, '15');
    expect(find.text('15 June 2021'), findsOneWidget);
    recordedHaptics.clear();
    await press(tester, find.byKey(UsKeys.momentSave));
    await until(tester, () => recordedHaptics.contains(HapticKind.celebration));
    await settleRoutes(tester);
    expect(find.text(MilestoneCopy.editTitle), findsNothing);
    await untilFound(tester, find.descendant(of: momentStep('Our very first date'), matching: find.text('15 Jun 2021')));
    expect(find.text('14 Jun 2021'), findsNothing);
    final edited = await drive(tester, () => space.milestones.readPlain(firstDate.id));
    expect(edited?['title'], 'Our very first date');
    expect(edited?['date'], '2021-06-15');

    await pressAndSettle(tester, find.byKey(UsKeys.moment(firstDate.id)));
    await pressAndSettle(tester, find.byKey(UsKeys.momentRemove));
    expect(find.text(MilestoneCopy.confirmRemove), findsOneWidget);
    expect(find.text(MilestoneCopy.confirmRemoveNote), findsOneWidget);
    await pressAndSettle(tester, find.text(MilestoneCopy.keep));
    expect(find.text(MilestoneCopy.editTitle), findsOneWidget);
    expect(find.text('Our very first date'), findsWidgets);

    recordedHaptics.clear();
    await pressAndSettle(tester, find.byKey(UsKeys.momentRemove));
    await pressAndSettle(tester, find.text(MilestoneCopy.confirmRemoveYes));
    await untilGone(tester, find.text('Our very first date'));
    expect(find.text(MilestoneCopy.editTitle), findsNothing);
    expect(recordedHaptics, contains(HapticKind.tap));
    expect((await drive(tester, space.milestones.list)).map((m) => m.title), ['Moved in together']);

    await pressAndSettle(tester, find.byKey(UsKeys.moment(stored.first.id)));
    await pressAndSettle(tester, find.byKey(UsKeys.momentRemove));
    await pressAndSettle(tester, find.text(MilestoneCopy.confirmRemoveYes));
    await untilFound(tester, find.byKey(UsKeys.emptyStep));
    expect(find.text(MilestoneCopy.emptyTitle), findsOneWidget);
    expect(find.text(MilestoneCopy.emptyNote), findsOneWidget);
    await rest(tester, space);
  });

  testWidgets('a moment without a title still shines with a gentle name', (tester) async {
    calm(tester);
    final space = await usSpace(tester);
    await real(tester, () => space.milestones.add(title: '', date: '2022-02-02'));
    await pumpUs(tester, space);
    await untilFound(tester, find.text(MilestoneCopy.fallbackTitle));
    expect(find.text('2 Feb 2022'), findsOneWidget);
    await rest(tester, space);
  });

  testWidgets('moments another passphrase sealed are counted, not shown', (tester) async {
    calm(tester);
    final space = await usSpace(tester);
    final stranger = await strangerSpace(tester);
    final key = stranger.vault.requireKey();
    for (final id in ['ms-stranger-1', 'ms-stranger-2']) {
      await real(
        tester,
        () => space.store.putEncrypted(
          milestonesTable,
          {'id': id, 'title': 'Not ours', 'date': '2020-01-01', 'updatedAt': 1, 'deleted': false},
          key,
        ),
      );
    }

    await pumpUs(tester, space);
    await untilFound(tester, find.text(MilestoneCopy.hidden(2)));
    expect(find.text('Not ours'), findsNothing);
    expect(find.byKey(UsKeys.emptyStep), findsOneWidget);
    await rest(tester, space);
  });
}
