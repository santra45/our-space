import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../domain/daily_question.dart';
import '../identity/identity_controller.dart';
import '../repositories/letters_repository.dart';
import '../repositories/memories_repository.dart';
import '../repositories/milestones_repository.dart';
import '../storage/local_settings.dart';
import '../storage/tables.dart';
import '../storage/vault_store.dart';
import '../sync/away_feed.dart' show lettersWrittenHereKey;
import '../vault/vault_service.dart';
import 'reminder_platform.dart';

enum ReminderKind { question, letters, countdown, together, memories }

const String reminderSettingsPrefix = 'our_space_reminder_';
const String reminderQuestionAtKey = 'our_space_reminder_question_at';
const int defaultQuestionMinutes = 21 * 60;
const int reminderQuestionDays = 7;
const int reminderHorizonDays = 45;
const int reminderLetterHorizonDays = 120;
const int reminderMorningMinutes = 9 * 60;
const int reminderMemoryMinutes = 10 * 60;
const Duration reminderReplanDelay = Duration(seconds: 2);

const Set<String> _watchedTables = {lettersTable, milestonesTable, memoriesTable, dailyAnswersTable};

abstract final class ReminderCopy {
  static const String questionTitle = "Today's question is still waiting";
  static const String questionBody = 'Answer it whenever you are ready.';
  static const String letterTitle = 'A letter just opened for you';
  static const String letterBody = 'It has been waiting for today.';
  static const String countdownTitle = 'Today is the day';
  static const String countdownBody = 'The one you have been counting down to.';
  static const String monthsaryBody = 'Happy monthsary, you two.';
  static const String anniversaryBody = 'Happy anniversary, you two.';
  static const String memoryTitle = 'A memory from this day';

  static String monthsTitle(int months) => months == 1 ? '1 month together today' : '$months months together today';

  static String yearsTitle(int years) => years == 1 ? '1 year together today' : '$years years together today';

  static String memoryBody(int years) => years == 1 ? '1 year ago today.' : '$years years ago today.';
}

abstract final class ReminderRoutes {
  static const String daily = 'daily';
  static const String us = 'us';
  static const String countdown = 'us/countdown';
  static String letter(String id) => 'letters/$id';
  static String memory(String id) => 'memories/$id';
}

@immutable
class ReminderInputs {
  const ReminderInputs({
    required this.now,
    required this.enabled,
    this.questionMinutes = defaultQuestionMinutes,
    this.answeredDays = const {},
    this.letters = const [],
    this.countdowns = const [],
    this.startDate,
    this.memories = const [],
  });

  final DateTime now;
  final Set<ReminderKind> enabled;
  final int questionMinutes;
  final Set<String> answeredDays;
  final List<({String id, String date})> letters;
  final List<({String id, String date})> countdowns;
  final String? startDate;
  final List<({String id, String date})> memories;
}

DateTime? parseReminderDate(String? value) {
  if (value == null) return null;
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value.trim());
  if (match == null) return null;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  final date = DateTime(year, month, day);
  if (date.month != month || date.day != day) return null;
  return date;
}

DateTime _at(DateTime day, int minutes) => DateTime(day.year, day.month, day.day, minutes ~/ 60, minutes % 60);

int _daysIn(int year, int month) => DateTime(year, month + 1, 0).day;

List<PlannedReminder> planReminders(ReminderInputs input) {
  final now = input.now;
  final today = DateTime(now.year, now.month, now.day);
  final horizon = today.add(const Duration(days: reminderHorizonDays));
  final out = <PlannedReminder>[];

  bool upcoming(DateTime at, DateTime limit) => at.isAfter(now) && at.isBefore(limit);

  if (input.enabled.contains(ReminderKind.question)) {
    for (var offset = 0; offset < reminderQuestionDays; offset++) {
      final at = _at(today.add(Duration(days: offset)), input.questionMinutes);
      if (!at.isAfter(now)) continue;
      final day = dayKey(at.millisecondsSinceEpoch);
      if (input.answeredDays.contains(day)) continue;
      out.add(PlannedReminder(
        id: 'q-$day',
        at: at.millisecondsSinceEpoch,
        title: ReminderCopy.questionTitle,
        body: ReminderCopy.questionBody,
        route: ReminderRoutes.daily,
      ));
    }
  }

  if (input.enabled.contains(ReminderKind.letters)) {
    final limit = today.add(const Duration(days: reminderLetterHorizonDays));
    for (final letter in input.letters) {
      final day = parseReminderDate(letter.date);
      if (day == null) continue;
      final at = _at(day, reminderMorningMinutes);
      if (!upcoming(at, limit)) continue;
      out.add(PlannedReminder(
        id: 'l-${letter.id}',
        at: at.millisecondsSinceEpoch,
        title: ReminderCopy.letterTitle,
        body: ReminderCopy.letterBody,
        route: ReminderRoutes.letter(letter.id),
      ));
    }
  }

  if (input.enabled.contains(ReminderKind.countdown)) {
    final days = <String>{};
    for (final moment in input.countdowns) {
      final day = parseReminderDate(moment.date);
      if (day == null || !days.add(moment.date)) continue;
      final at = _at(day, reminderMorningMinutes);
      if (!upcoming(at, horizon)) continue;
      out.add(PlannedReminder(
        id: 'c-${moment.date}',
        at: at.millisecondsSinceEpoch,
        title: ReminderCopy.countdownTitle,
        body: ReminderCopy.countdownBody,
        route: ReminderRoutes.countdown,
      ));
    }
  }

  final start = parseReminderDate(input.startDate);
  if (input.enabled.contains(ReminderKind.together) && start != null) {
    for (var months = 1; months < 12 * 100; months++) {
      final year = start.year + (start.month - 1 + months) ~/ 12;
      final month = (start.month - 1 + months) % 12 + 1;
      final day = start.day > _daysIn(year, month) ? _daysIn(year, month) : start.day;
      final at = _at(DateTime(year, month, day), reminderMorningMinutes);
      if (!at.isBefore(horizon)) break;
      if (!at.isAfter(now)) continue;
      final years = months % 12 == 0 ? months ~/ 12 : 0;
      out.add(PlannedReminder(
        id: 't-$year-$month',
        at: at.millisecondsSinceEpoch,
        title: years > 0 ? ReminderCopy.yearsTitle(years) : ReminderCopy.monthsTitle(months),
        body: years > 0 ? ReminderCopy.anniversaryBody : ReminderCopy.monthsaryBody,
        route: ReminderRoutes.us,
      ));
    }
  }

  if (input.enabled.contains(ReminderKind.memories)) {
    final byDay = <String, ({String id, int year})>{};
    for (final memory in input.memories) {
      final date = parseReminderDate(memory.date);
      if (date == null) continue;
      final key = '${date.month}-${date.day}';
      final earliest = byDay[key];
      if (earliest == null || date.year < earliest.year) byDay[key] = (id: memory.id, year: date.year);
    }
    for (var offset = 0; offset < reminderHorizonDays; offset++) {
      final day = today.add(Duration(days: offset));
      final found = byDay['${day.month}-${day.day}'];
      if (found == null || found.year >= day.year) continue;
      final at = _at(day, reminderMemoryMinutes);
      if (!at.isAfter(now)) continue;
      out.add(PlannedReminder(
        id: 'm-${day.month}-${day.day}',
        at: at.millisecondsSinceEpoch,
        title: ReminderCopy.memoryTitle,
        body: ReminderCopy.memoryBody(day.year - found.year),
        route: ReminderRoutes.memory(found.id),
      ));
    }
  }

  out.sort((a, b) => a.at.compareTo(b.at));
  return out;
}

class ReminderService extends ChangeNotifier {
  ReminderService({
    required this.store,
    required this.vault,
    required this.identity,
    required this.letters,
    required this.memories,
    required this.milestones,
    required this.dailyQuestion,
    this.platform,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    if (platform == null) return;
    _wasUnlocked = vault.isUnlocked;
    vault.addListener(_onVault);
    _changes = store.changes.listen(_onChanges);
    if (vault.isUnlocked) _soon();
  }

  final VaultStore store;
  final VaultService vault;
  final IdentityController identity;
  final LettersRepository letters;
  final MemoriesRepository memories;
  final MilestonesRepository milestones;
  final DailyQuestionService dailyQuestion;
  final ReminderPlatform? platform;
  final DateTime Function() _clock;

  StreamSubscription<Set<String>>? _changes;
  Timer? _timer;
  bool _disposed = false;
  bool _wasUnlocked = false;
  Future<void> _running = Future<void>.value();
  List<PlannedReminder> _planned = const [];
  bool? _allowed;

  bool get available => platform != null;
  List<PlannedReminder> get planned => _planned;
  bool? get allowed => _allowed;
  LocalSettings get _settings => store.settings;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  bool isOn(ReminderKind kind) => _settings.getItem('$reminderSettingsPrefix${kind.name}') == '1';

  Set<ReminderKind> get enabled => {for (final kind in ReminderKind.values) if (isOn(kind)) kind};

  int get questionMinutes {
    final raw = int.tryParse(_settings.getItem(reminderQuestionAtKey) ?? '');
    if (raw == null || raw < 0 || raw >= 24 * 60) return defaultQuestionMinutes;
    return raw;
  }

  Future<void> setOn(ReminderKind kind, bool on) async {
    final key = '$reminderSettingsPrefix${kind.name}';
    if (on) {
      await _settings.setItem(key, '1');
    } else {
      await _settings.removeItem(key);
    }
    notifyListeners();
    await replan();
  }

  Future<void> setQuestionMinutes(int minutes) async {
    if (minutes < 0 || minutes >= 24 * 60) return;
    await _settings.setItem(reminderQuestionAtKey, '$minutes');
    notifyListeners();
    await replan();
  }

  Future<bool> refreshAllowed() async {
    final platform = this.platform;
    if (platform == null) return false;
    final allowed = await platform.canNotify();
    if (_allowed != allowed) {
      _allowed = allowed;
      notifyListeners();
    }
    return allowed;
  }

  Future<bool> askToNotify() async {
    final platform = this.platform;
    if (platform == null) return false;
    if (await platform.canNotify()) return refreshAllowed();
    await platform.askPermission();
    return refreshAllowed();
  }

  void onForeground() {
    if (platform == null) return;
    unawaited(refreshAllowed());
    _soon();
  }

  void _onVault() {
    final unlocked = vault.isUnlocked;
    if (unlocked && !_wasUnlocked) _soon();
    _wasUnlocked = unlocked;
  }

  void _onChanges(Set<String> tables) {
    if (tables.any(_watchedTables.contains)) _soon();
  }

  void _soon() {
    if (_disposed) return;
    _timer?.cancel();
    _timer = Timer(reminderReplanDelay, () => unawaited(replan()));
  }

  Future<void> replan() {
    final run = _running.then((_) => _replan());
    _running = run.catchError((Object _) {});
    return _running;
  }

  Future<void> _replan() async {
    final platform = this.platform;
    if (platform == null || _disposed) return;
    final enabled = this.enabled;
    if (enabled.isEmpty) {
      if (_planned.isNotEmpty || _settings.getItem('${reminderSettingsPrefix}planned') == '1') {
        await platform.plan(const []);
        await _settings.removeItem('${reminderSettingsPrefix}planned');
        _planned = const [];
        notifyListeners();
      }
      return;
    }
    final key = vault.key;
    if (key == null) return;
    final now = _clock();
    final input = ReminderInputs(
      now: now,
      enabled: enabled,
      questionMinutes: questionMinutes,
      answeredDays: enabled.contains(ReminderKind.question) ? await _answeredToday(now) : const {},
      letters: enabled.contains(ReminderKind.letters) ? await _lettersToOpen(now) : const [],
      countdowns: enabled.contains(ReminderKind.countdown) ? await _countdowns() : const [],
      startDate: vault.config?.startDate,
      memories: enabled.contains(ReminderKind.memories) ? await _memories() : const [],
    );
    final next = planReminders(input);
    if (_disposed) return;
    await platform.plan(next);
    await _settings.setItem('${reminderSettingsPrefix}planned', '1');
    _planned = next;
    notifyListeners();
  }

  Future<Set<String>> _answeredToday(DateTime now) async {
    final at = _at(DateTime(now.year, now.month, now.day), questionMinutes).millisecondsSinceEpoch;
    try {
      final day = await dailyQuestion.readDay(
        vault.key,
        ownerId: identity.myOwnerId,
        ownerIds: identity.myOwnerIds,
        when: at,
      );
      return day.mine != null ? {dayKey(at)} : const {};
    } catch (_) {
      return const {};
    }
  }

  Set<String> _writtenHere() {
    final raw = _settings.getItem(lettersWrittenHereKey);
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return {for (final id in decoded) if (id is String) id};
    } catch (_) {}
    return const {};
  }

  Future<List<({String id, String date})>> _lettersToOpen(DateTime now) async {
    try {
      final mine = _writtenHere();
      final at = now.millisecondsSinceEpoch;
      return [
        for (final letter in await letters.list())
          if (!mine.contains(letter.id) && !letter.isOpened && letter.isLockedAt(at) && letter.lockDate != null)
            (id: letter.id, date: letter.lockDate!),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<List<({String id, String date})>> _countdowns() async {
    try {
      return [
        for (final moment in await milestones.list())
          if (moment.date != null) (id: moment.id, date: moment.date!),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<List<({String id, String date})>> _memories() async {
    try {
      return [
        for (final memory in await memories.list())
          if (memory.date != null) (id: memory.id, date: memory.date!),
      ];
    } catch (_) {
      return const [];
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    if (platform != null) vault.removeListener(_onVault);
    unawaited(_changes?.cancel());
    super.dispose();
  }
}
