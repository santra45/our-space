import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine/crypto/aes_gcm.dart';
import 'package:our_space_mobile/core/engine/crypto/js_compat.dart';
import 'package:our_space_mobile/core/engine/crypto/kdf.dart';
import 'package:our_space_mobile/core/engine/domain/daily_question.dart';
import 'package:our_space_mobile/core/engine/domain/date_helpers.dart';
import 'package:our_space_mobile/core/engine/domain/love_bursts.dart';
import 'package:our_space_mobile/core/engine/identity/device_id.dart';
import 'package:our_space_mobile/core/engine/identity/people.dart';
import 'package:our_space_mobile/core/engine/identity/people_repair.dart';
import 'package:our_space_mobile/core/engine/storage/local_settings.dart';
import 'package:our_space_mobile/core/engine/storage/tables.dart';
import 'package:our_space_mobile/core/engine/storage/vault_store.dart';
import 'package:our_space_mobile/models/daily_answers_record.dart';
import 'package:our_space_mobile/models/person_record.dart';

import 'support/harness.dart';

Map<String, Object?>? _entry(DailyAnswerEntry? entry) => entry?.toJson();

void main() {
  final fixture = readFixture('web_sealed.json');
  late VaultKey key;
  late VaultStore store;

  setUpAll(() async {
    key = await deriveKeyFromPassphrase(
      fixture['passphrase'] as String,
      fixture['salt'] as String,
      iterations: fixture['kdfIterations'] as int,
    );
  });

  setUp(() async {
    store = await openTestStore();
  });

  tearDown(() async {
    await store.close();
  });

  group('daily question', () {
    final domain = asStringMap(fixture['dailyDomain'])!;

    Future<DailyQuestionService> seeded() async {
      for (final row in (domain['rows'] as List).cast<Map>()) {
        await store.putEncrypted(dailyAnswersTable, asStringMap(row)!, key);
      }
      return DailyQuestionService(store: store);
    }

    test('day keys and indexes are UTC days, like the web', () {
      for (final vector in (fixture['dayVectors'] as List).cast<Map>()) {
        final when = vector['when'] as int;
        expect(dayKey(when), vector['dayKey'], reason: '$when');
        expect(monthKey(dayKey(when)), vector['monthKey'], reason: '$when');
        expect(dayIndex(when), vector['dayIndex'], reason: '$when');
      }
      expect(dateFromDayKey('2026-10-09')!.toUtc().hour, 12);
      expect(dateFromDayKey('nope'), isNull);
    });

    test('readDay folds every device of mine and hides their answer until I answer', () async {
      final service = await seeded();
      for (final vector in (domain['readDay'] as List).cast<Map>()) {
        final result = await service.readDay(
          key,
          ownerId: domain['ownerId'] as String,
          ownerIds: (domain['ownerIds'] as List).cast<String>(),
          when: vector['when'] as int,
        );
        expect(
          {
            'day': result.day,
            'mine': _entry(result.mine),
            'partnerHasAnswered': result.partnerHasAnswered,
            'partnerAnswer': _entry(result.partnerAnswer),
          },
          vector['result'],
        );
      }
    });

    test('listArchive and listAnswered match the web', () async {
      final service = await seeded();
      final archive = await service.listArchive(
        key,
        ownerId: domain['ownerId'] as String,
        ownerIds: (domain['ownerIds'] as List).cast<String>(),
      );
      expect(
        archive
            .map((d) => {
                  'day': d.day,
                  'question': d.question?.toJson(),
                  'mine': _entry(d.mine),
                  'theirs': _entry(d.theirs),
                  'partnerHasAnswered': d.partnerHasAnswered,
                  'missed': d.missed,
                })
            .toList(),
        domain['archive'],
      );

      final answered = await service.listAnswered(
        key,
        ownerId: domain['ownerId'] as String,
        ownerIds: (domain['ownerIds'] as List).cast<String>(),
      );
      expect(
        answered
            .map((d) => {
                  'day': d.day,
                  'question': d.question?.toJson(),
                  'mine': _entry(d.mine),
                  'theirs': _entry(d.theirs),
                })
            .toList(),
        domain['answered'],
      );

      final slots = (asStringMap(fixture['identity'])!['slots'] as List).cast<String>();
      final theirs = await service.listArchive(key, ownerId: slots[1], limit: 2);
      expect(
        theirs
            .map((d) => {
                  'day': d.day,
                  'question': d.question?.toJson(),
                  'mine': _entry(d.mine),
                  'theirs': _entry(d.theirs),
                  'partnerHasAnswered': d.partnerHasAnswered,
                  'missed': d.missed,
                })
            .toList(),
        domain['theirArchive'],
      );
    });

    test('the answer swap plan matches the web', () async {
      final service = await seeded();
      final slots = (asStringMap(fixture['identity'])!['slots'] as List).cast<String>();
      final swap = asStringMap(domain['swap'])!;
      final plan = await service.planAnswerSwap(
        key,
        personA: slots[0],
        personB: slots[1],
        since: swap['since'] as int,
        timestamp: () async => 777,
      );
      expect(jsonDeepEquals(plan.rows, swap['rows']), isTrue, reason: '${plan.rows}');
    });

    test('saving an answer keeps the rest of the month and trims the text', () async {
      final service = await seeded();
      final slots = (asStringMap(fixture['identity'])!['slots'] as List).cast<String>();
      final when = DateTime.utc(2026, 10, 10, 9).millisecondsSinceEpoch;
      final row = await service.saveAnswer(
        key,
        ownerId: slots[0],
        ownerIds: ['old-device-tag'],
        questionId: 'b1-010',
        text: '   hello there   ',
        when: when,
      );
      final opened = await store.getDecrypted(dailyAnswersTable, row['id'] as String, key);
      final answers = asStringMap(opened!['answers'])!;
      expect(answers.keys.toSet(), {'2026-10-07', '2026-10-08', '2026-10-09', '2026-10-10'});
      expect(asStringMap(answers['2026-10-10'])!['text'], 'hello there');
      expect(asStringMap(answers['2026-10-09'])!['text'], 'mine from old device');
      await expectLater(
        service.saveAnswer(key, ownerId: slots[0], questionId: 'b1-010', text: '   ', when: when),
        throwsA(isA<StoreError>()),
      );
    });
  });

  group('identity', () {
    final identity = asStringMap(fixture['identity'])!;

    Future<void> seed() async {
      for (final row in (identity['rows'] as List).cast<Map>()) {
        await store.putEncrypted(peopleTable, asStringMap(row)!, key);
      }
    }

    test('listPeople cleans, merges presence and sorts like the web', () async {
      await seed();
      final settings = LocalSettings.memory();
      final service = PeopleService(store: store, settings: settings, device: DeviceIdentity(settings));
      final everyone = await service.listPeople(key);
      expect(everyone.map((p) => p.toJson()).toList(), identity['people']);
    });

    test('resolveIdentity follows the web precedence rule for every case', () async {
      await seed();
      for (final c in (identity['cases'] as List).cast<Map>()) {
        final hint = c['hint'] as String?;
        final settings = LocalSettings.memory({if (hint != null) personIdStorageKey: hint});
        final service = PeopleService(store: store, settings: settings, device: DeviceIdentity(settings));
        final result = await service.resolveIdentity(key, deviceId: c['deviceId'] as String);
        expect(result.status.name, c['status'], reason: '$c');
        expect(result.me?.personId, c['me'], reason: '$c');
        expect(result.partner?.personId, c['partner'], reason: '$c');
        expect(settings.getItem(personIdStorageKey), c['hintAfter'], reason: '$c');
      }
    });

    test('names, possessives and grammar match the web', () {
      for (final vector in (fixture['sanitizeNames'] as List).cast<Map>()) {
        expect(sanitizeName(vector['input']), vector['output'], reason: '${vector['input']}');
        final person = Person(
          personId: 'p' * 8,
          name: sanitizeName(vector['input']),
          pronoun: 'they',
          deviceIds: const [],
          lastActiveAt: null,
          createdAt: 0,
          updatedAt: 0,
        );
        expect(possessiveOf(person), vector['possessive'], reason: '${vector['input']}');
      }
      expect(grammarOf(null).subject, 'they');
      expect(nameOf(null, 'you'), 'you');
    });

    test('creating a couple, claiming the other person, then swapping back', () async {
      final settings = LocalSettings.memory();
      final device = DeviceIdentity(settings);
      final service = PeopleService(store: store, settings: settings, device: device);
      var tick = 1000;
      final created = await service.createCouple(
        key,
        mineName: 'Sam',
        minePronoun: 'he',
        theirsName: 'Alex',
        theirsPronoun: 'she',
        timestamp: () => tick += 10,
      );
      expect(created.identity.status, IdentityStatus.ready);
      expect(created.identity.me!.name, 'Sam');
      expect(created.identity.me!.deviceIds, [device.deviceId]);
      expect(created.identity.partner!.name, 'Alex');
      expect(created.identity.me!.personId, derivePersonSlots(key)[0]);

      final otherSettings = LocalSettings.memory();
      final other = PeopleService(store: store, settings: otherSettings, device: DeviceIdentity(otherSettings));
      final before = await other.resolveIdentity(key);
      expect(before.status, IdentityStatus.unclaimed);
      await other.claimPerson(key, personId: derivePersonSlots(key)[1], timestamp: () => tick += 10);
      final after = await other.resolveIdentity(key);
      expect(after.me!.name, 'Alex');
      expect(after.partner!.name, 'Sam');

      expect(await service.touchPersonActive(key, personId: created.identity.me!.personId), isNull);

      final repair = PeopleRepair(store: store, people: service, answers: DailyQuestionService(store: store));
      final swapped = await repair.swapUsBack(key, timestamp: () async => tick += 10);
      expect(swapped.holderId, derivePersonSlots(key)[1]);
      final mineNow = await service.resolveIdentity(key);
      expect(mineNow.me!.personId, derivePersonSlots(key)[1]);
      expect(mineNow.me!.name, 'Sam');
      expect(mineNow.partner!.name, 'Alex');
    });
  });

  group('love bursts', () {
    test('describeBursts matches the web copy', () {
      for (final vector in (fixture['burstVectors'] as List).cast<Map>()) {
        expect(
          describeBursts(vector['total'] as int, vector['connected'] as bool, vector['name'] as String?),
          vector['text'],
        );
      }
    });

    test('sending counts up, and the other phone sees only new ones', () async {
      final mineSettings = LocalSettings.memory();
      final mine = LoveBurstService(store: store, settings: mineSettings, device: DeviceIdentity(mineSettings));
      final theirSettings = LocalSettings.memory();
      final theirs = LoveBurstService(store: store, settings: theirSettings, device: DeviceIdentity(theirSettings));

      await mine.sendLoveBurst(key);
      expect((await theirs.collectUnseenBursts(key)).total, 0);
      await mine.sendLoveBurst(key);
      await mine.sendLoveBurst(key);
      final unseen = await theirs.collectUnseenBursts(key);
      expect(unseen.total, 2);
      await theirs.markBurstsSeen(unseen.records);
      expect((await theirs.collectUnseenBursts(key)).total, 0);
      expect((await mine.collectUnseenBursts(key)).total, 0);
      final row = await store.getDecrypted(loveBurstsTable, mine.ownBurstRecordId, key);
      expect(row!['count'], 3);
    });
  });

  group('dates', () {
    test('formatting matches the web', () {
      final t0 = 1760000000000;
      for (final vector in (fixture['dateVectors'] as List).cast<Map>()) {
        final kind = vector['kind'] as String;
        final input = vector['input'];
        final output = switch (kind) {
          'formatDatePretty' => formatDatePretty(input as String),
          'formatLastSeen' => formatLastSeen(input as int, now: t0),
          _ => formatLastConnected(input as int, now: t0),
        };
        expect(output, vector['output'], reason: '$kind $input');
      }
    });

    test('milestones, durations and time remaining', () {
      final now = DateTime(2026, 10, 9, 12);
      final next = calculateNextMilestone('2021-06-14', now)!;
      expect(next.anniversary.year, 6);
      expect(next.anniversary.date, DateTime(2027, 6, 14));
      expect(next.hundredDay.milestone % 100, 0);
      final sameDay = calculateNextMilestone('2025-10-09', now)!;
      expect(sameDay.anniversary.daysLeft, 0);
      expect(sameDay.anniversary.year, 1);
      final fresh = calculateNextMilestone('2026-10-01', now)!;
      expect(fresh.anniversary.date.year, 2027);
      expect(fresh.hundredDay.milestone, 100);

      final duration = calculateLoveDuration('2026-10-08', now: DateTime(2026, 10, 9, 13, 2, 3).millisecondsSinceEpoch);
      expect(duration.totalDays, 1);
      expect(duration.hours, 13);
      expect(duration.minutes, 2);
      expect(duration.seconds, 3);

      final base = DateTime(2026, 10, 9).millisecondsSinceEpoch;
      expect(formatTimeRemaining('2026-10-11', now: base), '2d 0h left');
      expect(formatTimeRemaining('2026-10-09', now: base), 'Unlocked');
      expect(formatTimeRemaining('2026-10-10', now: base + 3600000 * 23 + 60000 * 30), '30m left');
      expect(formatTimeRemaining('2026-10-10', now: base + 3600000 * 21 + 60000 * 30), '2h 30m left');
      expect(isDateLocked('2099-01-01'), isTrue);
      expect(isDateLocked(''), isFalse);
      expect(isValidDateInput('2026-02-30'), isTrue);
      expect(isValidDateInput('2026-13-01'), isFalse);
      expect(toLocalDateInput(DateTime(2026, 3, 4)), '2026-03-04');
    });
  });
}
