import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../../core/engine.dart';
import 'daily_copy.dart';

@immutable
class DailyCatchUp {
  const DailyCatchUp({required this.day, required this.question});

  final String day;
  final DailyQuestion question;
}

class DailyQuestionModel extends ChangeNotifier {
  DailyQuestionModel(this.space);

  static const int archiveLimit = 120;

  final OurSpace space;
  final TextEditingController draft = TextEditingController();

  QuestionOfTheDay? _today;
  DayAnswers? _day;
  bool _saving = false;
  String _error = '';
  bool _showArchive = false;
  List<ArchiveDay> _archive = const [];
  DailyCatchUp? _catchUp;
  int _stars = 0;
  bool _failed = false;

  VaultKey? _key;
  String? _ownerId;
  Set<String> _ownerIds = const {};
  StreamSubscription<void>? _changes;
  int _generation = 0;
  bool _disposed = false;

  QuestionOfTheDay? get today => _today;
  DayAnswers? get day => _day;
  bool get saving => _saving;
  String get error => _error;
  bool get showArchive => _showArchive;
  List<ArchiveDay> get archive => _archive;
  DailyCatchUp? get catchUp => _catchUp;
  int get stars => _stars;
  bool get failed => _failed && _key != null;
  bool get loading => _key != null && _today == null && !_failed;

  bool get visible => _key != null && _today != null;
  bool get answered => _day?.mine != null;
  bool get partnerWaiting => (_day?.partnerHasAnswered ?? false) && !answered;
  bool get bothIn => answered && _day?.partnerAnswer != null;

  void bind({required VaultKey? key, required String ownerId, required Set<String> ownerIds}) {
    final changed = !identical(key, _key) || ownerId != _ownerId || !setEquals(ownerIds, _ownerIds);
    _key = key;
    _ownerId = ownerId;
    _ownerIds = Set<String>.unmodifiable(ownerIds);
    if (_changes == null) {
      _changes = space.watchTable(dailyAnswersTable).listen((_) => unawaited(refresh()));
      return;
    }
    if (changed) unawaited(refresh());
  }

  Future<void> refresh() async {
    final key = _key;
    final ownerId = _ownerId;
    if (key == null || ownerId == null || _disposed) return;
    final ticket = ++_generation;
    try {
      final question = space.dailyQuestion.questionForDay(key);
      final day = await space.dailyQuestion.readDay(key, ownerId: ownerId, ownerIds: _ownerIds);
      var stars = _stars;
      try {
        final answered = await space.dailyQuestion.listAnswered(key, ownerId: ownerId, ownerIds: _ownerIds);
        stars = answered.where((entry) => entry.theirs != null).length;
      } catch (_) {}
      if (_disposed || ticket != _generation) return;
      _today = question;
      _day = day;
      _stars = stars;
      _failed = false;
    } catch (_) {
      if (_disposed || ticket != _generation) return;
      _today = null;
      _failed = true;
    }
    notifyListeners();
  }

  Future<void> retry() async {
    if (_disposed) return;
    _failed = false;
    notifyListeners();
    await refresh();
  }

  Future<void> loadArchive() async {
    List<ArchiveDay> next;
    try {
      next = await space.dailyQuestion.listArchive(
        _key,
        ownerId: _ownerId,
        ownerIds: _ownerIds,
        limit: archiveLimit,
      );
    } catch (_) {
      next = const [];
    }
    if (_disposed) return;
    _archive = next;
    notifyListeners();
  }

  Future<void> openArchive() async {
    _showArchive = true;
    notifyListeners();
    await loadArchive();
  }

  void closeArchive() {
    _showArchive = false;
    notifyListeners();
  }

  void startCatchUp(ArchiveDay entry) {
    final question = entry.question;
    if (question == null) return;
    draft.clear();
    _error = '';
    _catchUp = DailyCatchUp(day: entry.day, question: question);
    notifyListeners();
  }

  void leaveCatchUp() {
    _catchUp = null;
    draft.clear();
    _error = '';
    notifyListeners();
  }

  void resetSheet() {
    if (_disposed || (!_showArchive && _catchUp == null)) return;
    _showArchive = false;
    _catchUp = null;
    notifyListeners();
  }

  Future<bool> save({VoidCallback? onSaved}) async {
    final catchUp = _catchUp;
    final today = _today;
    final questionId = catchUp?.question.id ?? today?.question.id;
    if (_saving || draft.text.trim().isEmpty || questionId == null) return false;

    _saving = true;
    _error = '';
    notifyListeners();
    var saved = false;
    try {
      await space.dailyQuestion.saveAnswer(
        _key,
        ownerId: _ownerId,
        ownerIds: _ownerIds,
        questionId: questionId,
        text: draft.text,
        when: catchUp == null ? null : dateFromDayKey(catchUp.day)?.millisecondsSinceEpoch,
        timestamp: space.store.clock.stamp,
      );
      if (_disposed) return false;
      saved = true;
      draft.clear();
      onSaved?.call();
      if (catchUp != null) {
        _catchUp = null;
        notifyListeners();
        await loadArchive();
      }
      await refresh();
    } catch (_) {
      if (_disposed) return false;
      if (!saved) _error = DailyCopy.saveFailed;
    } finally {
      if (!_disposed) {
        _saving = false;
        notifyListeners();
      }
    }
    return saved;
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_changes?.cancel());
    draft.dispose();
    super.dispose();
  }
}
