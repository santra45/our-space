import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../models/person_record.dart';
import '../storage/tables.dart';
import '../storage/vault_store.dart';
import '../vault/vault_service.dart';
import 'people.dart';
import 'people_repair.dart';

class IdentityController extends ChangeNotifier {
  IdentityController({
    required this.store,
    required this.vault,
    required this.people,
    required this.repair,
  }) {
    vault.addListener(_onVault);
    _changes = store.changes.listen((tables) {
      if (tables.contains(peopleTable) && !_writing) unawaited(refresh());
    });
    _local = store.localWrites.listen((table) {
      if (table != peopleTable) unawaited(touchLastActive());
    });
  }

  final VaultStore store;
  final VaultService vault;
  final PeopleService people;
  final PeopleRepair repair;

  late final StreamSubscription<Set<String>> _changes;
  late final StreamSubscription<String> _local;

  Identity _identity = Identity.loading;
  bool _busy = false;
  bool _writing = false;
  Object? _lastKey;
  bool appInForeground = true;

  Identity get identity => _identity;
  IdentityStatus get status => _identity.status;
  List<Person> get everyone => _identity.people;
  Person? get me => _identity.me;
  Person? get partner => _identity.partner;
  bool get busy => _busy;

  String? get myOwnerId => me?.personId;
  Set<String> get myOwnerIds => ownerIdsFor(me);
  String get myName => nameOf(me, 'you');
  String get partnerName => nameOf(partner);
  String get partnerPossessive => possessiveOf(partner);
  PronounSet get partnerGrammar => grammarOf(partner);
  int? get partnerLastActive => partner?.lastActiveAt;

  int _stamp() => store.clock.next();

  void _onVault() {
    final key = vault.key;
    if (identical(key, _lastKey)) return;
    _lastKey = key;
    unawaited(refresh());
  }

  Future<void> refresh() async {
    final key = vault.key;
    if (key == null) {
      _identity = Identity.locked;
      notifyListeners();
      return;
    }
    try {
      var next = await people.resolveIdentity(key);
      _identity = next;
      notifyListeners();
      if (next.status == IdentityStatus.ready) {
        _writing = true;
        Map<String, Object?>? healed;
        try {
          healed = await people.ensureDeviceClaimed(key, timestamp: _stamp);
        } finally {
          _writing = false;
        }
        if (healed != null) {
          next = await people.resolveIdentity(key);
          _identity = next;
          notifyListeners();
        }
      }
    } catch (_) {
      _identity = const Identity(status: IdentityStatus.empty, people: [], me: null, partner: null);
      notifyListeners();
    }
  }

  Future<bool> _guarded(Future<void> Function() body) async {
    if (vault.key == null || _busy) return false;
    _busy = true;
    _writing = true;
    notifyListeners();
    try {
      await body();
      _writing = false;
      await refresh();
      return true;
    } catch (_) {
      return false;
    } finally {
      _writing = false;
      _busy = false;
      notifyListeners();
    }
  }

  Future<bool> createCouple({
    required String myName,
    String? myPronoun,
    required String partnerName,
    String? partnerPronoun,
  }) =>
      _guarded(() async {
        await people.createCouple(
          vault.key,
          mineName: myName,
          minePronoun: myPronoun,
          theirsName: partnerName,
          theirsPronoun: partnerPronoun,
          timestamp: _stamp,
        );
      });

  Future<bool> claimPerson(String personId) => _guarded(() async {
        await people.claimPerson(vault.key, personId: personId, timestamp: _stamp);
      });

  Future<bool> savePerson(String personId, {String? name, String? pronoun}) => _guarded(() async {
        await people.savePerson(vault.key, personId: personId, name: name, pronoun: pronoun, timestamp: _stamp);
      });

  Future<bool> swapUsBack() => _guarded(() async {
        await repair.swapUsBack(vault.key, timestamp: () async => _stamp());
      });

  Future<void> touchLastActive() async {
    final key = vault.key;
    final personId = myOwnerId;
    if (key == null || personId == null || !appInForeground) return;
    try {
      _writing = true;
      final row = await people.touchPersonActive(key, personId: personId, timestamp: _stamp);
      _writing = false;
      if (row != null) await refresh();
    } catch (_) {
    } finally {
      _writing = false;
    }
  }

  @override
  void dispose() {
    vault.removeListener(_onVault);
    unawaited(_changes.cancel());
    unawaited(_local.cancel());
    super.dispose();
  }
}
