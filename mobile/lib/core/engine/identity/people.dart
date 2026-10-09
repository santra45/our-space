import 'dart:async';

import '../../../models/person_record.dart';
import '../crypto/aes_gcm.dart';
import '../crypto/derived_ids.dart' as ids;
import '../crypto/js_compat.dart';
import '../storage/local_settings.dart';
import '../storage/tables.dart';
import '../storage/vault_store.dart';
import 'device_id.dart';

const int maxNameLength = 40;
const int _maxDeviceTags = 8;
const String defaultPronoun = 'they';
const String personIdStorageKey = 'sweetheart_person_id_v1';

const Map<String, PronounSet> pronounSets = {
  'she': PronounSet(subject: 'she', object: 'her', possessive: 'her', independent: 'hers', has: 'has', isVerb: 'is'),
  'he': PronounSet(subject: 'he', object: 'him', possessive: 'his', independent: 'his', has: 'has', isVerb: 'is'),
  'they': PronounSet(
    subject: 'they',
    object: 'them',
    possessive: 'their',
    independent: 'theirs',
    has: 'have',
    isVerb: 'are',
  ),
};

const List<String> pronouns = ['she', 'he', 'they'];

typedef Stamp = FutureOr<int> Function();

List<String> derivePersonSlots(VaultKey key) => ids.derivePersonSlots(key);

String personRecordId(String personId) => 'person-$personId';

String presenceRecordId(String personId) => 'presence-$personId';

final RegExp _whitespaceRun = RegExp(r'\s+');

String sanitizeName(Object? value) {
  if (value is! String) return '';
  return jsTrim(jsSlice(jsTrim(value.replaceAll(_whitespaceRun, ' ')), 0, maxNameLength));
}

String sanitizePronoun(Object? value) => value is String && pronounSets.containsKey(value) ? value : defaultPronoun;

List<String> sanitizeDeviceIds(Object? value) {
  if (value is! List) return [];
  final out = <String>[];
  for (final tag in value) {
    if (tag is! String || !deviceTagPattern.hasMatch(tag)) continue;
    if (out.contains(tag)) continue;
    out.add(tag);
    if (out.length >= _maxDeviceTags) break;
  }
  return out;
}

Person? toPerson(Map<String, Object?>? row) {
  if (row == null) return null;
  if (row['_headerTampered'] == true || row['_tableTampered'] == true) return null;
  final personId = row['personId'];
  if (personId is! String || !deviceTagPattern.hasMatch(personId)) return null;
  if (row['id'] != personRecordId(personId)) return null;
  return Person(
    personId: personId,
    name: sanitizeName(row['name']),
    pronoun: sanitizePronoun(row['pronoun']),
    deviceIds: sanitizeDeviceIds(row['deviceIds']),
    lastActiveAt: finiteIntOrNull(row['lastActiveAt']),
    createdAt: finiteIntOrNull(row['createdAt']) ?? 0,
    updatedAt: finiteIntOrNull(row['updatedAt']) ?? 0,
  );
}

Presence? toPresence(Map<String, Object?>? row) {
  if (row == null) return null;
  if (row['_headerTampered'] == true || row['_tableTampered'] == true) return null;
  final personId = row['personId'];
  if (personId is! String || !deviceTagPattern.hasMatch(personId)) return null;
  if (row['id'] != presenceRecordId(personId)) return null;
  final lastActiveAt = finiteIntOrNull(row['lastActiveAt']);
  if (lastActiveAt == null) return null;
  return Presence(personId: personId, lastActiveAt: lastActiveAt);
}

String nameOf(Person? person, [String fallback = 'your partner']) {
  final name = person == null ? '' : sanitizeName(person.name);
  return name.isNotEmpty ? name : fallback;
}

PronounSet grammarOf(Person? person) => pronounSets[sanitizePronoun(person?.pronoun)]!;

String possessiveOf(Person? person, [String fallback = 'your partner']) {
  final name = nameOf(person, fallback);
  return RegExp(r's$', caseSensitive: false).hasMatch(name) ? "$name'" : "$name's";
}

Set<String> ownerIdsFor(Person? person) {
  final out = <String>{};
  if (person == null) return out;
  out.add(person.personId);
  out.addAll(person.deviceIds);
  return out;
}

class PeopleService {
  PeopleService({
    required this.store,
    required this.settings,
    required this.device,
  });

  final VaultStore store;
  final LocalSettings settings;
  final DeviceIdentity device;

  String? _cachedPersonId;

  Future<int> _stamp(Stamp? timestamp) async => timestamp == null ? store.now() : await timestamp();

  String? get localPersonId {
    final cached = _cachedPersonId;
    if (cached != null) return cached;
    final stored = settings.getItem(personIdStorageKey);
    if (stored != null && deviceTagPattern.hasMatch(stored)) {
      _cachedPersonId = stored;
      return stored;
    }
    return null;
  }

  bool setLocalPersonId(String personId) {
    if (!deviceTagPattern.hasMatch(personId)) return false;
    _cachedPersonId = personId;
    unawaited(settings.setItem(personIdStorageKey, personId));
    return true;
  }

  void clearLocalPersonId() {
    _cachedPersonId = null;
    unawaited(settings.removeItem(personIdStorageKey));
  }

  void forgetCachedPersonId() {
    _cachedPersonId = null;
  }

  Future<List<Person>> listPeople(VaultKey? key) async {
    if (key == null) return [];
    List<Map<String, Object?>> rows;
    try {
      rows = await store.listDecrypted(peopleTable, key);
    } catch (_) {
      return [];
    }

    final people = <Person>[];
    final presence = <String, int>{};
    for (final row in rows) {
      final person = toPerson(row);
      if (person != null) {
        people.add(person);
        continue;
      }
      final seen = toPresence(row);
      if (seen != null) presence[seen.personId] = seen.lastActiveAt;
    }

    for (var i = 0; i < people.length; i++) {
      final person = people[i];
      final fromPresence = presence[person.personId] ?? 0;
      final fromPerson = person.lastActiveAt ?? 0;
      final latest = fromPresence > fromPerson ? fromPresence : fromPerson;
      people[i] = latest == 0 ? person.copyWith(clearLastActive: true) : person.copyWith(lastActiveAt: latest);
    }

    people.sort((a, b) {
      final byCreated = a.createdAt - b.createdAt;
      if (byCreated != 0) return byCreated;
      return a.personId.compareTo(b.personId) < 0 ? -1 : 1;
    });
    return people;
  }

  Future<Identity> resolveIdentity(VaultKey? key, {String? deviceId}) async {
    if (key == null) return Identity.locked;
    final device = deviceId ?? this.device.deviceId;

    final people = await listPeople(key);
    if (people.isEmpty) {
      return Identity(status: IdentityStatus.empty, people: people, me: null, partner: null);
    }

    final hinted = localPersonId;
    Person? me;
    if (hinted != null) {
      for (final p in people) {
        if (p.personId == hinted) {
          me = p;
          break;
        }
      }
    }
    final listing = people.where((p) => p.deviceIds.contains(device)).toList();

    if (me == null) {
      me = listing.isNotEmpty ? listing.first : null;
      if (me != null) setLocalPersonId(me.personId);
    }

    if (me != null &&
        listing.length == 1 &&
        listing.first.personId != me.personId &&
        me.deviceIds.isNotEmpty &&
        !me.deviceIds.contains(device)) {
      me = listing.first;
      setLocalPersonId(me.personId);
    }

    if (me == null) {
      return Identity(status: IdentityStatus.unclaimed, people: people, me: null, partner: null);
    }

    Person? partner;
    for (final p in people) {
      if (p.personId != me.personId) {
        partner = p;
        break;
      }
    }
    return Identity(status: IdentityStatus.ready, people: people, me: me, partner: partner);
  }

  Future<Map<String, Object?>> savePerson(
    VaultKey? key, {
    required String personId,
    String? name,
    String? pronoun,
    String? addDeviceId,
    Stamp? timestamp,
  }) async {
    if (key == null) throw StoreError('savePerson: vault is locked');
    if (!deviceTagPattern.hasMatch(personId)) {
      throw StoreError('savePerson: bad person id');
    }

    final id = personRecordId(personId);
    Person? existing;
    try {
      existing = toPerson(await store.getDecrypted(peopleTable, id, key));
    } catch (_) {
      existing = null;
    }

    final deviceIds = sanitizeDeviceIds([
      ...?existing?.deviceIds,
      if (addDeviceId != null && addDeviceId.isNotEmpty) addDeviceId,
    ]);

    final resolvedName = name != null ? sanitizeName(name) : (existing?.name ?? '');
    final resolvedPronoun = pronoun != null ? sanitizePronoun(pronoun) : (existing?.pronoun ?? defaultPronoun);
    final createdAt = (existing != null && existing.createdAt != 0) ? existing.createdAt : store.now();

    return store.putEncrypted(
      peopleTable,
      {
        'id': id,
        'personId': personId,
        'name': resolvedName,
        'pronoun': resolvedPronoun,
        'deviceIds': deviceIds,
        'createdAt': createdAt,
        'updatedAt': await _stamp(timestamp),
      },
      key,
    );
  }

  Future<Map<String, Object?>> _writePresence(VaultKey key, String personId, Stamp? timestamp) async {
    return store.putEncrypted(
      peopleTable,
      {
        'id': presenceRecordId(personId),
        'personId': personId,
        'lastActiveAt': store.now(),
        'updatedAt': await _stamp(timestamp),
      },
      key,
    );
  }

  Future<Map<String, Object?>?> touchPersonActive(
    VaultKey? key, {
    required String? personId,
    int minIntervalMs = 5 * 60 * 1000,
    Stamp? timestamp,
  }) async {
    if (key == null || personId == null || !deviceTagPattern.hasMatch(personId)) return null;

    Presence? existing;
    try {
      existing = toPresence(await store.getDecrypted(peopleTable, presenceRecordId(personId), key));
    } catch (_) {
      existing = null;
    }

    if (existing != null && store.now() - existing.lastActiveAt < minIntervalMs) {
      return null;
    }
    return _writePresence(key, personId, timestamp);
  }

  Future<CoupleCreated> createCouple(
    VaultKey? key, {
    required String mineName,
    String? minePronoun,
    required String theirsName,
    String? theirsPronoun,
    String? deviceId,
    Stamp? timestamp,
  }) async {
    if (key == null) throw StoreError('createCouple: vault is locked');
    final device = deviceId ?? this.device.deviceId;
    final slots = derivePersonSlots(key);
    final minePersonId = slots[0];
    final theirsPersonId = slots[1];

    final mineRow = await savePerson(
      key,
      personId: minePersonId,
      name: mineName,
      pronoun: minePronoun,
      addDeviceId: device,
      timestamp: timestamp,
    );
    final theirsRow = await savePerson(
      key,
      personId: theirsPersonId,
      name: theirsName,
      pronoun: theirsPronoun,
      timestamp: timestamp,
    );
    final presenceRow = await _writePresence(key, minePersonId, timestamp);

    setLocalPersonId(minePersonId);

    final identity = await resolveIdentity(key, deviceId: device);
    return CoupleCreated(identity: identity, rows: [mineRow, theirsRow, presenceRow]);
  }

  Future<List<Map<String, Object?>>> _releaseDeviceFromOthers(
    VaultKey key, {
    required String deviceId,
    required String keepPersonId,
    Stamp? timestamp,
  }) async {
    final people = await listPeople(key);
    final rows = <Map<String, Object?>>[];
    for (final person in people) {
      if (person.personId == keepPersonId) continue;
      if (!person.deviceIds.contains(deviceId)) continue;
      final remaining = person.deviceIds.where((tag) => tag != deviceId).toList();
      rows.add(await store.putEncrypted(
        peopleTable,
        {
          'id': personRecordId(person.personId),
          'personId': person.personId,
          'name': person.name,
          'pronoun': person.pronoun,
          'deviceIds': remaining,
          'createdAt': person.createdAt != 0 ? person.createdAt : store.now(),
          'updatedAt': await _stamp(timestamp),
        },
        key,
      ));
    }
    return rows;
  }

  Future<List<Map<String, Object?>>> claimPerson(
    VaultKey? key, {
    required String personId,
    String? deviceId,
    Stamp? timestamp,
  }) async {
    if (key == null) throw StoreError('claimPerson: vault is locked');
    final device = deviceId ?? this.device.deviceId;
    final released = await _releaseDeviceFromOthers(
      key,
      deviceId: device,
      keepPersonId: personId,
      timestamp: timestamp,
    );
    final row = await savePerson(key, personId: personId, addDeviceId: device, timestamp: timestamp);
    final presenceRow = await _writePresence(key, personId, timestamp);
    setLocalPersonId(personId);
    return [...released, row, presenceRow];
  }

  Future<Map<String, Object?>?> ensureDeviceClaimed(VaultKey? key, {String? deviceId, Stamp? timestamp}) async {
    if (key == null) return null;
    final device = deviceId ?? this.device.deviceId;
    final identity = await resolveIdentity(key, deviceId: device);
    final me = identity.me;
    if (identity.status != IdentityStatus.ready || me == null) return null;
    if (me.deviceIds.contains(device)) return null;
    return savePerson(key, personId: me.personId, addDeviceId: device, timestamp: timestamp);
  }
}

class CoupleCreated {
  const CoupleCreated({required this.identity, required this.rows});

  final Identity identity;
  final List<Map<String, Object?>> rows;
}
