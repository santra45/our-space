import '../../../models/person_record.dart';
import '../crypto/aes_gcm.dart';
import '../domain/daily_question.dart';
import '../storage/tables.dart';
import '../storage/vault_store.dart';
import 'people.dart';

int? tradedPlacesAt(List<Person> people) {
  if (people.length != 2) return null;
  final a = people[0].updatedAt;
  final b = people[1].updatedAt;
  final at = a > b ? a : b;
  return at > 0 ? at : null;
}

List<String> orphansAnsweringAlongside(
  Map<String, AnswerSpan> spans, {
  required List<String> holderIds,
  required Set<String> claimed,
}) {
  String? first;
  String? last;
  for (final id in holderIds) {
    final span = spans[id];
    if (span == null) continue;
    if (first == null || span.first.compareTo(first) < 0) first = span.first;
    if (last == null || span.last.compareTo(last) > 0) last = span.last;
  }
  if (first == null || last == null) return [];

  final out = <String>[];
  spans.forEach((owner, span) {
    if (claimed.contains(owner)) return;
    if (span.last.compareTo(first!) > 0 && span.first.compareTo(last!) < 0) out.add(owner);
  });
  return out;
}

class SwapResult {
  const SwapResult({
    required this.people,
    required this.answers,
    required this.holderId,
    required this.since,
    required this.adopted,
  });

  final List<Map<String, Object?>> people;
  final List<Map<String, Object?>> answers;
  final String? holderId;
  final int since;
  final List<String> adopted;
}

class PeopleRepair {
  PeopleRepair({required this.store, required this.people, required this.answers});

  final VaultStore store;
  final PeopleService people;
  final DailyQuestionService answers;

  Future<SwapResult> swapUsBack(VaultKey? key, {String? deviceId, Future<int> Function()? timestamp}) async {
    if (key == null) throw StoreError('swapUsBack: vault is locked');
    final device = deviceId ?? people.device.deviceId;
    Future<int> stamp() async => timestamp == null ? store.now() : await timestamp();

    final everyone = await people.listPeople(key);
    if (everyone.length != 2) throw StoreError('swapUsBack: needs exactly two people');
    final a = everyone[0];
    final b = everyone[1];
    final since = tradedPlacesAt(everyone);
    if (since == null) throw StoreError('swapUsBack: cannot tell when you traded places');

    final answerPlan = await answers.planAnswerSwap(
      key,
      personA: a.personId,
      personB: b.personId,
      since: since,
      timestamp: timestamp,
    );

    final devices = <String, List<String>>{
      a.personId: [...b.deviceIds],
      b.personId: [...a.deviceIds],
    };
    String? holderId;
    if (devices[a.personId]!.contains(device)) {
      holderId = a.personId;
    } else if (devices[b.personId]!.contains(device)) {
      holderId = b.personId;
    }

    var adopted = <String>[];
    if (holderId != null) {
      final partnerId = holderId == a.personId ? b.personId : a.personId;
      adopted = orphansAnsweringAlongside(
        await answers.answerSpans(key, rows: answerPlan.after),
        holderIds: [holderId, ...devices[holderId]!],
        claimed: {a.personId, b.personId, ...a.deviceIds, ...b.deviceIds},
      );
      devices[partnerId] = [...devices[partnerId]!, ...adopted];
    }

    final entries = <TableWrite>[
      for (final fields in answerPlan.rows) TableWrite(answerTable, fields),
    ];

    for (final pair in [
      [a, b],
      [b, a],
    ]) {
      final target = pair[0];
      final source = pair[1];
      entries.add(TableWrite(peopleTable, {
        'id': personRecordId(target.personId),
        'personId': target.personId,
        'name': source.name,
        'pronoun': source.pronoun,
        'deviceIds': devices[target.personId],
        'createdAt': target.createdAt != 0 ? target.createdAt : store.now(),
        'updatedAt': await stamp(),
      }));
    }

    final lastSeen = <String, int>{};
    for (final person in everyone) {
      try {
        final row = toPresence(await store.getDecrypted(peopleTable, presenceRecordId(person.personId), key));
        if (row != null) lastSeen[person.personId] = row.lastActiveAt;
      } catch (_) {}
    }
    for (final pair in [
      [a, b],
      [b, a],
    ]) {
      final target = pair[0];
      final source = pair[1];
      final seen = lastSeen[source.personId];
      if (seen == null) continue;
      entries.add(TableWrite(peopleTable, {
        'id': presenceRecordId(target.personId),
        'personId': target.personId,
        'lastActiveAt': seen,
        'updatedAt': await stamp(),
      }));
    }

    final sealed = await store.putEncryptedMany(entries, key);
    if (holderId != null) people.setLocalPersonId(holderId);

    return SwapResult(
      people: sealed.where((entry) => entry.table == peopleTable).map((entry) => entry.row).toList(),
      answers: sealed.where((entry) => entry.table == answerTable).map((entry) => entry.row).toList(),
      holderId: holderId,
      since: since,
      adopted: adopted,
    );
  }
}
