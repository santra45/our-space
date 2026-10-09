import 'dart:typed_data';

import '../../../models/daily_answers_record.dart';
import '../crypto/aes_gcm.dart';
import '../crypto/derived_ids.dart';
import '../crypto/js_compat.dart';
import '../crypto/pbkdf2.dart';
import '../data/web_data.dart';
import '../storage/tables.dart';
import '../storage/vault_store.dart';

const String answerTable = dailyAnswersTable;

const int maxAnswerLength = 2000;

final List<DailyQuestion> allQuestions = [
  for (final batch in questionBatches) ...batch.questions,
];

DailyQuestion? findQuestion(Object? id) {
  for (final question in allQuestions) {
    if (question.id == id) return question;
  }
  return null;
}

String dayKey([int? when]) {
  final ms = when ?? systemNow();
  return toJsIsoString(ms).substring(0, 10);
}

String monthKey(String dayKeyString) => jsSlice(dayKeyString, 0, 7);

int dayIndex([int? when]) {
  final ms = when ?? systemNow();
  return (ms / 86400000).floor();
}

DateTime? dateFromDayKey(Object? day) {
  if (day is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day)) return null;
  final parts = day.split('-').map(int.parse).toList();
  return DateTime.utc(parts[0], parts[1], parts[2], 12);
}

int Function() _randomStream(Uint8List seed) {
  final values = <int>[];
  var counter = 0;
  return () {
    if (values.isEmpty) {
      final block = Uint8List(seed.length + 4);
      block.setRange(0, seed.length, seed);
      ByteData.sublistView(block).setUint32(seed.length, counter++, Endian.big);
      final digest = sha256Bytes(block);
      final view = ByteData.sublistView(digest);
      for (var i = 0; i < digest.length; i += 4) {
        values.add(view.getUint32(i, Endian.big));
      }
    }
    return values.removeLast();
  };
}

List<T> _shuffled<T>(List<T> items, Uint8List seed) {
  final out = List<T>.from(items);
  final next = _randomStream(seed);
  for (var i = out.length - 1; i > 0; i--) {
    final j = next() % (i + 1);
    final swap = out[i];
    out[i] = out[j];
    out[j] = swap;
  }
  return out;
}

List<DailyQuestion> buildQuestionOrder(VaultKey key, [List<QuestionBatch>? batches]) {
  final seed = deriveQuestionSeed(key);
  final order = <DailyQuestion>[];
  for (final batch in batches ?? questionBatches) {
    order.addAll(_shuffled(batch.questions, seed));
  }
  return order;
}

QuestionOfTheDay getQuestionForDay(VaultKey key, [int? when, List<QuestionBatch>? batches]) {
  final order = buildQuestionOrder(key, batches);
  final length = order.length;
  final index = ((dayIndex(when) % length) + length) % length;
  return QuestionOfTheDay(question: order[index], day: dayKey(when), index: index);
}

String answerRecordId(String monthKeyString, String ownerId) => 'ans-$monthKeyString-$ownerId';

String _sanitizeAnswerText(Object? text) {
  final trimmed = jsTrim(text == null ? '' : text.toString());
  return jsSlice(trimmed, 0, maxAnswerLength);
}

String? _ownerOf(Map<String, Object?>? row) {
  if (row == null) return null;
  if (row['_headerTampered'] == true || row['_tableTampered'] == true) return null;
  final ownerId = row['ownerId'];
  final month = row['month'];
  if (ownerId is! String || ownerId.isEmpty) return null;
  if (month is! String || month.isEmpty) return null;
  if (row['id'] != answerRecordId(month, ownerId)) return null;
  return ownerId;
}

Set<String> _mineIds(String? ownerId, Iterable<String>? ownerIds) {
  final ids = <String>{};
  for (final id in ownerIds ?? const <String>[]) {
    if (id.isNotEmpty) ids.add(id);
  }
  if (ownerId != null && ownerId.isNotEmpty) ids.add(ownerId);
  return ids;
}

bool _isAnswer(Object? entry) {
  if (entry is! Map) return false;
  final text = entry['text'];
  return text is String && text.isNotEmpty;
}

Map<String, Map<String, Object?>> _foldAnswers(
  Iterable<Map<String, Object?>> rows,
  bool Function(String owner) predicate,
) {
  final out = <String, Map<String, Object?>>{};
  for (final row in rows) {
    final owner = _ownerOf(row);
    if (owner == null || !predicate(owner)) continue;
    final answers = row['answers'];
    if (answers is! Map) continue;
    answers.forEach((dayValue, entryValue) {
      if (!_isAnswer(entryValue)) return;
      final day = dayValue.toString();
      final entry = asStringMap(entryValue)!;
      final previous = out[day];
      if (previous == null || numOrZero(entry['answeredAt']) >= numOrZero(previous['answeredAt'])) {
        out[day] = entry;
      }
    });
  }
  return out;
}

class DailyQuestionService {
  DailyQuestionService({required this.store});

  final VaultStore store;

  Future<List<Map<String, Object?>>> _readAllRows(VaultKey key) async {
    try {
      return await store.listDecrypted(answerTable, key);
    } catch (_) {
      return [];
    }
  }

  QuestionOfTheDay questionForDay(VaultKey key, [int? when]) => getQuestionForDay(key, when);

  Future<Map<String, Object?>> saveAnswer(
    VaultKey? key, {
    required String? ownerId,
    Iterable<String>? ownerIds,
    required String? questionId,
    required String text,
    int? when,
    Future<int> Function()? timestamp,
  }) async {
    if (key == null) throw StoreError('saveAnswer: vault is locked');
    if (ownerId == null || ownerId.isEmpty) throw StoreError('saveAnswer: missing owner id');

    final body = _sanitizeAnswerText(text);
    if (body.isEmpty) throw StoreError('saveAnswer: nothing to save');

    final day = dayKey(when);
    final month = monthKey(day);
    final ids = _mineIds(ownerId, ownerIds);

    final rows = await _readAllRows(key);
    final answers = _foldAnswers(rows.where((row) => row['month'] == month), ids.contains);
    answers[day] = {'questionId': questionId, 'text': body, 'answeredAt': store.now()};

    return store.putEncrypted(
      answerTable,
      {
        'id': answerRecordId(month, ownerId),
        'ownerId': ownerId,
        'month': month,
        'answers': answers,
        'updatedAt': timestamp == null ? store.now() : await timestamp(),
      },
      key,
    );
  }

  Future<DayAnswers> readDay(
    VaultKey? key, {
    required String? ownerId,
    Iterable<String>? ownerIds,
    int? when,
  }) async {
    final day = dayKey(when);
    if (key == null || ownerId == null || ownerId.isEmpty) {
      return DayAnswers(day: day, mine: null, partnerAnswer: null, partnerHasAnswered: false);
    }
    final month = monthKey(day);
    final ids = _mineIds(ownerId, ownerIds);
    final rows = (await _readAllRows(key)).where((row) => row['month'] == month).toList();

    final mine = _foldAnswers(rows, ids.contains)[day];
    final theirs = _foldAnswers(rows, (owner) => !ids.contains(owner))[day];

    return DayAnswers(
      day: day,
      mine: mine == null ? null : DailyAnswerEntry(mine),
      partnerHasAnswered: theirs != null,
      partnerAnswer: (mine != null && theirs != null) ? DailyAnswerEntry(theirs) : null,
    );
  }

  Future<List<AnsweredDay>> listAnswered(
    VaultKey? key, {
    required String? ownerId,
    Iterable<String>? ownerIds,
    int? limit,
  }) async {
    if (key == null || ownerId == null || ownerId.isEmpty) return [];
    final ids = _mineIds(ownerId, ownerIds);
    final rows = await _readAllRows(key);
    final mineByDay = _foldAnswers(rows, ids.contains);
    final theirsByDay = _foldAnswers(rows, (owner) => !ids.contains(owner));

    final out = <AnsweredDay>[];
    mineByDay.forEach((day, mine) {
      final theirs = theirsByDay[day];
      final mineQuestion = mine['questionId'];
      final questionId = (mineQuestion is String && mineQuestion.isNotEmpty) ? mineQuestion : theirs?['questionId'];
      out.add(AnsweredDay(
        day: day,
        question: findQuestion(questionId),
        mine: DailyAnswerEntry(mine),
        theirs: theirs == null ? null : DailyAnswerEntry(theirs),
      ));
    });
    out.sort((a, b) => b.day.compareTo(a.day));
    return limit == null ? out : out.take(limit).toList();
  }

  Future<List<ArchiveDay>> listArchive(
    VaultKey? key, {
    required String? ownerId,
    Iterable<String>? ownerIds,
    int? limit,
  }) async {
    if (key == null || ownerId == null || ownerId.isEmpty) return [];
    final ids = _mineIds(ownerId, ownerIds);
    final rows = await _readAllRows(key);
    final mineByDay = _foldAnswers(rows, ids.contains);
    final theirsByDay = _foldAnswers(rows, (owner) => !ids.contains(owner));

    final days = <String>{...mineByDay.keys, ...theirsByDay.keys};
    final out = <ArchiveDay>[];
    for (final day in days) {
      final mine = mineByDay[day];
      final theirs = theirsByDay[day];
      final mineQuestion = mine?['questionId'];
      final questionId = (mineQuestion is String && mineQuestion.isNotEmpty) ? mineQuestion : theirs?['questionId'];
      out.add(ArchiveDay(
        day: day,
        question: findQuestion(questionId),
        mine: mine == null ? null : DailyAnswerEntry(mine),
        theirs: (mine != null && theirs != null) ? DailyAnswerEntry(theirs) : null,
        partnerHasAnswered: theirs != null,
        missed: mine == null && theirs != null,
      ));
    }
    out.sort((a, b) => b.day.compareTo(a.day));
    return limit == null ? out : out.take(limit).toList();
  }

  Future<AnswerSwapPlan> planAnswerSwap(
    VaultKey? key, {
    required String personA,
    required String personB,
    required num since,
    Future<int> Function()? timestamp,
    List<Map<String, Object?>>? rows,
  }) async {
    if (key == null) throw StoreError('swapAnswersSince: vault is locked');
    if (personA.isEmpty || personB.isEmpty || personA == personB) {
      throw StoreError('swapAnswersSince: needs two different people');
    }
    if (!since.isFinite) throw StoreError('swapAnswersSince: needs the moment to split at');

    final otherOf = {personA: personB, personB: personA};
    final before = rows ?? await _readAllRows(key);

    final months = <String, Map<String, (Map<String, Object?>, Map<String, Object?>)>>{};
    for (final row in before) {
      final owner = _ownerOf(row);
      if (owner != personA && owner != personB) continue;
      final answers = row['answers'];
      if (answers is! Map) continue;

      final kept = <String, Object?>{};
      final moved = <String, Object?>{};
      answers.forEach((dayValue, entry) {
        if (!_isAnswer(entry)) return;
        final day = dayValue.toString();
        if (numOrZero((entry as Map)['answeredAt']) >= since) {
          moved[day] = entry;
        } else {
          kept[day] = entry;
        }
      });
      final month = row['month'] as String;
      months.putIfAbsent(month, () => {})[owner!] = (kept, moved);
    }

    final out = <Map<String, Object?>>[];
    for (final monthEntry in months.entries) {
      final month = monthEntry.key;
      final owners = monthEntry.value;
      final anythingMoves = owners.values.any((o) => o.$2.isNotEmpty);
      if (!anythingMoves) continue;

      for (final owner in [personA, personB]) {
        final own = owners[owner] ?? (<String, Object?>{}, <String, Object?>{});
        final arriving = owners[otherOf[owner]]?.$2 ?? const <String, Object?>{};

        final answers = Map<String, Object?>.from(own.$1);
        arriving.forEach((day, entry) {
          final previous = answers[day];
          if (previous == null ||
              numOrZero((entry as Map)['answeredAt']) >= numOrZero((previous as Map)['answeredAt'])) {
            answers[day] = entry;
          }
        });

        out.add({
          'id': answerRecordId(month, owner),
          'ownerId': owner,
          'month': month,
          'answers': answers,
          'updatedAt': timestamp == null ? store.now() : await timestamp(),
        });
      }
    }

    final replaced = out.map((row) => row['id']).toSet();
    final after = [
      ...before.where((row) => !replaced.contains(row['id'])),
      ...out,
    ];
    return AnswerSwapPlan(rows: out, after: after);
  }

  Future<List<Map<String, Object?>>> swapAnswersSince(
    VaultKey? key, {
    required String personA,
    required String personB,
    required num since,
    Future<int> Function()? timestamp,
  }) async {
    final plan = await planAnswerSwap(key, personA: personA, personB: personB, since: since, timestamp: timestamp);
    if (plan.rows.isEmpty) return [];
    final sealed = await store.putEncryptedMany(
      [for (final fields in plan.rows) TableWrite(answerTable, fields)],
      key,
    );
    return sealed.map((entry) => entry.row).toList();
  }

  Future<Map<String, AnswerSpan>> answerSpans(VaultKey? key, {List<Map<String, Object?>>? rows}) async {
    final spans = <String, AnswerSpan>{};
    if (key == null && rows == null) return spans;
    final source = rows ?? await _readAllRows(key!);
    for (final row in source) {
      final owner = _ownerOf(row);
      final answers = row['answers'];
      if (owner == null || answers is! Map) continue;
      answers.forEach((dayValue, entry) {
        if (!_isAnswer(entry)) return;
        final day = dayValue.toString();
        final span = spans[owner];
        if (span == null) {
          spans[owner] = AnswerSpan(day, day);
          return;
        }
        if (day.compareTo(span.first) < 0) span.first = day;
        if (day.compareTo(span.last) > 0) span.last = day;
      });
    }
    return spans;
  }
}

class AnswerSwapPlan {
  const AnswerSwapPlan({required this.rows, required this.after});

  final List<Map<String, Object?>> rows;
  final List<Map<String, Object?>> after;
}

class AnswerSpan {
  AnswerSpan(this.first, this.last);

  String first;
  String last;
}
