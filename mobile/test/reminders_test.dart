import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/core/engine/reminders/reminders.dart' show parseReminderDate, reminderQuestionDays;

import 'p2p/support/engine_harness.dart' show waitFor;
import 'support/harness.dart';

class FakeReminders implements ReminderPlatform {
  final List<List<PlannedReminder>> plans = [];
  final StreamController<String> taps = StreamController<String>.broadcast();
  bool allowed = true;
  int asks = 0;
  String? launch;

  List<PlannedReminder> get last => plans.isEmpty ? const [] : plans.last;

  @override
  Future<int> plan(List<PlannedReminder> reminders) async {
    plans.add(List.of(reminders));
    return reminders.length;
  }

  @override
  Future<bool> canNotify() async => allowed;

  @override
  Future<void> askPermission() async {
    asks++;
  }

  @override
  Future<String?> takeRoute() async {
    final route = launch;
    launch = null;
    return route;
  }

  @override
  Stream<String> get opened => taps.stream;
}

int at(int y, int m, int d, int h, [int min = 0]) => DateTime(y, m, d, h, min).millisecondsSinceEpoch;

String ymd(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

void main() {
  final morning = DateTime(2026, 11, 18, 10);

  group('planning', () {
    test('nothing is planned until a kind is switched on', () {
      expect(
        planReminders(ReminderInputs(
          now: morning,
          enabled: const {},
          letters: const [(id: 'let-1', date: '2026-11-25')],
          startDate: '2021-06-14',
        )),
        isEmpty,
      );
    });

    test("today's question waits for the evening, skips a day already answered, and never lands in the past", () {
      final plan = planReminders(ReminderInputs(now: morning, enabled: const {ReminderKind.question}));
      expect(plan, hasLength(reminderQuestionDays));
      expect(plan.first.at, at(2026, 11, 18, 21));
      expect(plan.first.id, 'q-${dayKey(at(2026, 11, 18, 21))}');
      expect(plan.first.title, ReminderCopy.questionTitle);
      expect(plan.first.route, ReminderRoutes.daily);
      expect(plan[1].at, at(2026, 11, 19, 21));

      final answered = planReminders(ReminderInputs(
        now: morning,
        enabled: const {ReminderKind.question},
        answeredDays: {dayKey(at(2026, 11, 18, 21))},
      ));
      expect(answered.first.at, at(2026, 11, 19, 21));
      expect(answered, hasLength(reminderQuestionDays - 1));

      final late = planReminders(ReminderInputs(
        now: DateTime(2026, 11, 18, 22),
        enabled: const {ReminderKind.question},
        questionMinutes: 20 * 60 + 30,
      ));
      expect(late.first.at, at(2026, 11, 19, 20, 30));
    });

    test('a sealed letter rings the morning it opens, and only letters ahead of today count', () {
      final plan = planReminders(ReminderInputs(
        now: morning,
        enabled: const {ReminderKind.letters},
        letters: const [
          (id: 'let-soon', date: '2026-11-25'),
          (id: 'let-gone', date: '2026-11-01'),
          (id: 'let-far', date: '2027-09-01'),
          (id: 'let-odd', date: 'someday'),
        ],
      ));
      expect(plan.map((r) => r.id), ['l-let-soon']);
      expect(plan.single.at, at(2026, 11, 25, 9));
      expect(plan.single.route, 'letters/let-soon');
      expect(plan.single.title, ReminderCopy.letterTitle);
    });

    test('a countdown day rings once that morning, however many moments share it', () {
      final plan = planReminders(ReminderInputs(
        now: morning,
        enabled: const {ReminderKind.countdown},
        countdowns: const [
          (id: 'ms-1', date: '2026-12-01'),
          (id: 'ms-2', date: '2026-12-01'),
          (id: 'ms-3', date: '2026-11-18'),
        ],
      ));
      expect(plan.map((r) => r.id), ['c-2026-12-01']);
      expect(plan.single.at, at(2026, 12, 1, 9));
      expect(plan.single.body, ReminderCopy.countdownBody);
    });

    test('monthsaries count from the day it began, turn into years, and fit short months', () {
      final months = planReminders(ReminderInputs(
        now: morning,
        enabled: const {ReminderKind.together},
        startDate: '2021-06-14',
      ));
      expect(months.single.at, at(2026, 12, 14, 9));
      expect(months.single.title, '66 months together today');
      expect(months.single.body, ReminderCopy.monthsaryBody);

      final years = planReminders(ReminderInputs(
        now: morning,
        enabled: const {ReminderKind.together},
        startDate: '2021-12-20',
      ));
      expect(years.map((r) => r.title), contains('5 years together today'));
      expect(years.firstWhere((r) => r.title.contains('year')).body, ReminderCopy.anniversaryBody);

      final short = planReminders(ReminderInputs(
        now: DateTime(2026, 2, 1, 8),
        enabled: const {ReminderKind.together},
        startDate: '2024-01-31',
      ));
      expect(short.first.at, at(2026, 2, 28, 9));
      expect(short.first.title, '25 months together today');

      expect(
        planReminders(ReminderInputs(now: morning, enabled: const {ReminderKind.together}, startDate: '')),
        isEmpty,
      );
    });

    test('on this day picks the oldest polaroid from that date and never one from this year', () {
      final plan = planReminders(ReminderInputs(
        now: morning,
        enabled: const {ReminderKind.memories},
        memories: const [
          (id: 'mem-recent', date: '2025-11-20'),
          (id: 'mem-oldest', date: '2023-11-20'),
          (id: 'mem-now', date: '2026-11-21'),
          (id: 'mem-today', date: '2024-11-18'),
        ],
      ));
      expect(plan.map((r) => r.id), ['m-11-20']);
      expect(plan.single.at, at(2026, 11, 20, 10));
      expect(plan.single.body, '3 years ago today.');
      expect(plan.single.route, 'memories/mem-oldest');
    });

    test('dates are read strictly', () {
      expect(parseReminderDate('2026-02-30'), isNull);
      expect(parseReminderDate('2026-2-3'), isNull);
      expect(parseReminderDate(null), isNull);
      expect(parseReminderDate('2026-02-28'), DateTime(2026, 2, 28));
    });
  });

  group('the service', () {
    late OurSpace space;
    late FakeReminders platform;

    setUp(() async {
      platform = FakeReminders();
      final dir = Directory.systemTemp.createTempSync('our_space_reminders_');
      space = await OurSpace.open(
        databaseFactory: testDatabaseFactory(),
        databasePath: '${dir.path}${Platform.pathSeparator}space.sqlite',
        useEnvironmentMailbox: false,
        autoSync: false,
        peerToPeer: false,
        reminderPlatform: platform,
      );
      final created = await space.vault.create(
        passphrase: 'correct horse battery staple 2026',
        coupleNames: 'Sam & Alex',
        startDate: '2021-06-14',
        iterations: 1000,
      );
      expect(created.ok, isTrue);
    });

    tearDown(() async => space.close());

    test('switching kinds on plans them from the vault, and switching all off clears the phone', () async {
      final reminders = space.reminders;
      expect(reminders.available, isTrue);
      expect(reminders.enabled, isEmpty);
      final soon = DateTime.now().add(const Duration(days: 10));
      final written = await space.letters.writeLetter(title: 'For later', content: 'Open me then', unlockDate: ymd(soon));
      await space.milestones.add(title: 'Flight', date: ymd(DateTime.now().add(const Duration(days: 5))));

      await reminders.setOn(ReminderKind.letters, true);
      expect(platform.last.map((r) => r.id), ['l-${written!['id']}']);
      expect(platform.last.single.at, at(soon.year, soon.month, soon.day, 9));

      await reminders.setOn(ReminderKind.countdown, true);
      expect(platform.last.map((r) => r.id.substring(0, 2)).toSet(), {'l-', 'c-'});
      expect(reminders.enabled, {ReminderKind.letters, ReminderKind.countdown});

      await space.store.settings.setItem('lettersWrittenHere', '["${written['id']}"]');
      await reminders.replan();
      expect(platform.last.map((r) => r.id.substring(0, 2)), ['c-']);

      await reminders.setOn(ReminderKind.letters, false);
      await reminders.setOn(ReminderKind.countdown, false);
      expect(platform.last, isEmpty);
      final plansAfterOff = platform.plans.length;
      await reminders.replan();
      expect(platform.plans.length, plansAfterOff);
    });

    test('a locked vault keeps what is planned, and a change to a letter plans again on its own', () async {
      final reminders = space.reminders;
      await reminders.setOn(ReminderKind.letters, true);
      final before = platform.plans.length;
      final soon = DateTime.now().add(const Duration(days: 3));
      await space.letters.writeLetter(title: 'Soon', content: 'Hello', unlockDate: ymd(soon));
      await waitFor(() => platform.plans.length > before && platform.last.isNotEmpty, reason: 'the replan');
      expect(platform.last.single.route, startsWith('letters/'));

      space.vault.lock();
      final locked = platform.plans.length;
      await reminders.replan();
      expect(platform.plans.length, locked);
    });

    test('turning one on asks for notifications when the phone has them off', () async {
      platform.allowed = false;
      await space.reminders.refreshAllowed();
      expect(space.reminders.allowed, isFalse);
      expect(await space.reminders.askToNotify(), isFalse);
      expect(platform.asks, 1);
      platform.allowed = true;
      expect(await space.reminders.askToNotify(), isTrue);
      expect(platform.asks, 1);
      expect(space.reminders.allowed, isTrue);
    });
  });
}
