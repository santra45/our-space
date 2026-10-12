import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/presentation/screens/countdown/live_love_counter.dart';
import 'package:our_space_mobile/presentation/screens/countdown/milestone_copy.dart';
import 'package:our_space_mobile/presentation/screens/countdown/milestone_tracker.dart';
import 'package:our_space_mobile/presentation/space_scope.dart';
import 'package:our_space_mobile/presentation/widgets/our_widgets.dart';

import '../../widgets/harness.dart' show recordHaptics, recordedHaptics;
import 'love_harness.dart';

const String titleHint = 'e.g. First kiss, moved in together...';
const String sendBurst = 'Send Love Burst 💕';
const String sendingBurst = 'Sending Love... 💕';

Widget trackerShell(int Function() clock) => OurScaffold(
      particles: false,
      body: OurPage(children: [MilestoneTracker(clock: clock)]),
    );

Finder plainText(String text) => find.byWidgetPredicate(
      (widget) =>
          widget is Text &&
          (widget.data ?? widget.textSpan?.toPlainText() ?? '').replaceAll('￼', ' ') == text,
    );

Finder addButton() => find.byWidgetPredicate((widget) => widget is OurIconButton && widget.icon == AppIcons.plus);

Finder within(Finder parent, Finder child) => find.descendant(of: parent, matching: child);

Future<void> pickDay(WidgetTester tester, Finder field, String day) async {
  await press(tester, field);
  await settleRoute(tester);
  await tester.tap(find.text(day));
  await tester.pump();
  await tester.tap(find.text('OK'));
  await settleRoute(tester);
}

void main() {
  setUp(recordHaptics);

  group('milestone copy', () {
    test('hidden milestones are counted like the web', () {
      expect(
        MilestoneCopy.hidden(1),
        '1 milestone could not be opened with your passphrase, so it is hidden for now.',
      );
      expect(
        MilestoneCopy.hidden(3),
        '3 milestones could not be opened with your passphrase, so they are hidden for now.',
      );
      expect(MilestoneCopy.notice(error: '', unreadable: 0), isNull);
      expect(MilestoneCopy.notice(error: '', unreadable: 2), MilestoneCopy.hidden(2));
      expect(MilestoneCopy.notice(error: MilestoneCopy.saveFailed, unreadable: 2), MilestoneCopy.saveFailed);
      expect(MilestoneCopy.since('Jun 14, 2021'), 'Since Jun 14, 2021 (Tap to edit)');
      expect(twoDigitCount(7), '07');
      expect(twoDigitCount(42), '42');
    });
  });

  group('live love counter', () {
    testWidgets('ticks every second from the start date, like useLiveCounter', (tester) async {
      var now = DateTime(2025, 10, 12, 9, 7, 5).millisecondsSinceEpoch;
      final counter = LiveLoveCounter(clock: () => now);
      var ticks = 0;
      counter.addListener(() => ticks++);

      counter.track(null);
      expect(counter.value.totalDays, 0);
      expect(counter.ticking, isFalse);

      counter.track(startDate);
      final first = calculateLoveDuration(startDate, now: now);
      expect(counter.value.totalDays, first.totalDays);
      expect(counter.value.seconds, 5);
      expect(counter.ticking, isTrue);

      now += 1000;
      await tester.pump(const Duration(seconds: 1));
      expect(ticks, 1);
      expect(counter.value.seconds, 6);

      counter.track(startDate);
      expect(counter.value.seconds, 6);
      expect(ticks, 1);

      counter.track('2021-06-15');
      expect(counter.value.totalDays, first.totalDays - 1);

      counter.dispose();
      expect(counter.ticking, isFalse);
    });
  });

  testWidgets('the together card counts live and shows the next anniversary and 100-day mark', (tester) async {
    calm(tester);
    var now = DateTime(2025, 10, 12, 9, 7, 5).millisecondsSinceEpoch;
    final space = await coupleSpace(tester);

    await pumpLove(tester, space, shell: trackerShell(() => now));
    await untilFound(tester, find.text('TOGETHER FOREVER'));

    final duration = calculateLoveDuration(startDate, now: now);
    expect(find.text('${duration.totalDays}'), findsOneWidget);
    expect(find.text('Days'), findsOneWidget);
    expect(find.text(twoDigitCount(duration.hours)), findsOneWidget);
    expect(find.text(twoDigitCount(duration.minutes)), findsOneWidget);
    expect(find.text('05'), findsOneWidget);
    for (final label in ['HOURS', 'MINUTES', 'SECONDS']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Since Jun 14, 2021 (Tap to edit)'), findsOneWidget);
    expect(find.text(sendBurst), findsOneWidget);

    final next = calculateNextMilestone(startDate, DateTime.fromMillisecondsSinceEpoch(now))!;
    expect(find.text('ANNIVERSARY'), findsOneWidget);
    expect(plainText('${next.anniversary.daysLeft} days left'), findsOneWidget);
    expect(find.text('Year ${next.anniversary.year} Celebration'), findsOneWidget);
    expect(find.text('DAY ${next.hundredDay.milestone}'), findsOneWidget);
    expect(plainText('${next.hundredDay.daysLeft} days left'), findsOneWidget);
    expect(find.text('Next 100-day milestone'), findsOneWidget);

    now += 1000;
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('06'), findsOneWidget);
    expect(find.text('05'), findsNothing);

    now = DateTime(2025, 6, 14, 10).millisecondsSinceEpoch;
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Today! 🎉'), findsOneWidget);
    expect(find.text('Year 4 Celebration'), findsOneWidget);
    expect(find.text('DAY 1500'), findsOneWidget);
    expect(plainText('39 days left'), findsOneWidget);
    await settle(tester, space);
  });

  testWidgets('with no start date it counts from today', (tester) async {
    calm(tester);
    final now = DateTime(2025, 10, 12, 18, 30).millisecondsSinceEpoch;
    final space = await coupleSpace(tester);
    await real(tester, () => space.vault.updateSettings(startDate: ''));
    expect(space.vault.config?.startDate, '');

    await pumpLove(tester, space, shell: trackerShell(() => now));
    await untilFound(tester, find.text('TOGETHER FOREVER'));
    expect(find.text('0'), findsOneWidget);
    expect(find.text('Since Oct 12, 2025 (Tap to edit)'), findsOneWidget);
    expect(find.text('18'), findsOneWidget);
    expect(find.text('30'), findsOneWidget);
    await settle(tester, space);
  });

  testWidgets('the start date can be changed from the card', (tester) async {
    calm(tester);
    final now = DateTime(2025, 10, 12, 9).millisecondsSinceEpoch;
    final space = await coupleSpace(tester);

    await pumpLove(tester, space, shell: trackerShell(() => now));
    await untilFound(tester, find.text('Since Jun 14, 2021 (Tap to edit)'));

    await press(tester, find.text('Since Jun 14, 2021 (Tap to edit)'));
    expect(recordedHaptics, contains(HapticKind.tap));
    expect(find.text('06/14/2021'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);

    await press(tester, find.text('Cancel'));
    expect(find.text('06/14/2021'), findsNothing);
    expect(find.text('Since Jun 14, 2021 (Tap to edit)'), findsOneWidget);

    await press(tester, find.text('Since Jun 14, 2021 (Tap to edit)'));
    await pickDay(tester, find.text('06/14/2021'), '20');
    expect(find.text('06/20/2021'), findsOneWidget);

    recordedHaptics.clear();
    await press(tester, find.text('Save'));
    await until(tester, () => space.vault.config?.startDate == '2021-06-20');
    await untilFound(tester, find.text('Since Jun 20, 2021 (Tap to edit)'));
    expect(find.text('06/20/2021'), findsNothing);
    expect(recordedHaptics, contains(HapticKind.celebration));
    final duration = calculateLoveDuration('2021-06-20', now: now);
    expect(find.text('${duration.totalDays}'), findsOneWidget);
    await settle(tester, space);
  });

  testWidgets('a love burst is sent once and the button rests for a second', (tester) async {
    calm(tester);
    final now = DateTime(2025, 10, 12, 9).millisecondsSinceEpoch;
    final space = await coupleSpace(tester);

    await pumpLove(tester, space, shell: trackerShell(() => now));
    await untilFound(tester, find.text(sendBurst));
    final notices = tester.element(find.byType(MilestoneTracker)).read<AppNotices>();

    await press(tester, find.text(sendBurst));
    expect(recordedHaptics, contains(HapticKind.celebration));
    expect(find.text(sendingBurst), findsOneWidget);
    expect(buttonEnabled(tester, sendingBurst), isFalse);

    await until(tester, () => notices.toast.message == 'Saved 💕 Alex will see it the moment you two connect.');
    await tester.pump(const Duration(milliseconds: 1100));
    expect(find.text(sendBurst), findsOneWidget);
    expect(buttonEnabled(tester, sendBurst), isTrue);

    final bursts = await drive(tester, () => space.store.listDecrypted(loveBurstsTable, space.vault.requireKey()));
    expect(bursts, hasLength(1));
    await tester.pump(const Duration(seconds: 5));
    await settle(tester, space);
  });

  testWidgets('milestones are added, edited and removed in the Love tab', (tester) async {
    calm(tester);
    final space = await coupleSpace(tester);
    await real(tester, () => space.milestones.add(title: 'First date', date: '2021-06-14'));

    await pumpLove(tester, space);
    await untilFound(tester, find.text('Relationship Milestones'));
    await untilFound(tester, find.text('First date'));
    expect(find.text('Jun 14, 2021'), findsOneWidget);

    await press(tester, addButton());
    expect(recordedHaptics, contains(HapticKind.tap));
    final today = DateTime.now();
    expect(fieldWithHint(titleHint), findsOneWidget);
    expect(find.text(formatInputDate(today)), findsOneWidget);

    await press(tester, find.text('Add'));
    expect(fieldWithHint(titleHint), findsOneWidget);
    expect(await drive(tester, space.milestones.list), hasLength(1));

    recordedHaptics.clear();
    await type(tester, fieldWithHint(titleHint), '  Moved in together  ');
    await press(tester, find.text('Add'));
    await untilFound(tester, find.text('Moved in together'));
    expect(fieldWithHint(titleHint), findsNothing);
    expect(recordedHaptics, contains(HapticKind.celebration));
    expect(find.text(formatDatePretty(toLocalDateInput(today))), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Moved in together')).dy,
      lessThan(tester.getTopLeft(find.text('First date')).dy),
    );

    final stored = await drive(tester, space.milestones.list);
    expect(stored.map((m) => m.title), ['Moved in together', 'First date']);
    expect(stored.first.date, toLocalDateInput(today));
    final firstDate = stored.last;

    final row = find.byKey(ValueKey<String>(firstDate.id));
    await press(tester, within(row, iconButton('Edit milestone')));
    expect(find.text('Edit Milestone'), findsOneWidget);
    expect(tester.widget<TextField>(fieldWithHint(titleHint)).controller?.text, 'First date');
    expect(find.text('06/14/2021'), findsOneWidget);

    recordedHaptics.clear();
    await press(tester, within(row, find.text('Cancel')));
    expect(find.text('Edit Milestone'), findsNothing);
    expect(recordedHaptics, contains(HapticKind.tap));

    await press(tester, within(row, iconButton('Edit milestone')));
    await type(tester, fieldWithHint(titleHint), 'Our very first date');
    await press(tester, within(row, find.text('Save')));
    await untilFound(tester, find.text('Our very first date'));
    expect(find.text('Edit Milestone'), findsNothing);
    final edited = await drive(tester, () => space.milestones.readPlain(firstDate.id));
    expect(edited?['title'], 'Our very first date');
    expect(edited?['date'], '2021-06-14');

    recordedHaptics.clear();
    await press(tester, within(row, iconButton('Delete milestone')));
    await settleRoute(tester);
    expect(find.text('Delete this milestone?'), findsOneWidget);
    expect(recordedHaptics, isNot(contains(HapticKind.tap)));
    await press(tester, find.text('Cancel'));
    await settleRoute(tester);
    expect(find.text('Our very first date'), findsOneWidget);

    await press(tester, within(row, iconButton('Delete milestone')));
    await settleRoute(tester);
    await press(tester, find.text('OK'));
    await settleRoute(tester);
    await untilGone(tester, find.text('Our very first date'));
    expect(recordedHaptics, contains(HapticKind.tap));
    expect((await drive(tester, space.milestones.list)).map((m) => m.title), ['Moved in together']);

    final otherRow = find.byKey(ValueKey<String>(stored.first.id));
    await press(tester, within(otherRow, iconButton('Delete milestone')));
    await settleRoute(tester);
    await press(tester, find.text('OK'));
    await settleRoute(tester);
    await untilFound(tester, find.text('No milestones yet. Tap + to add your first one!'));
    await settle(tester, space);
  });

  testWidgets('milestones another passphrase sealed are counted, not shown', (tester) async {
    calm(tester);
    final space = await coupleSpace(tester);
    final stranger = await strangerKey(tester);
    for (final id in ['ms-stranger-1', 'ms-stranger-2']) {
      await real(
        tester,
        () => space.store.putEncrypted(
          milestonesTable,
          {'id': id, 'title': 'Not ours', 'date': '2020-01-01', 'updatedAt': 1, 'deleted': false},
          stranger,
        ),
      );
    }

    await pumpLove(tester, space);
    await untilFound(
      tester,
      find.text('2 milestones could not be opened with your passphrase, so they are hidden for now.'),
    );
    expect(find.text('Not ours'), findsNothing);
    expect(find.text('No milestones yet. Tap + to add your first one!'), findsOneWidget);
    await settle(tester, space);
  });
}
