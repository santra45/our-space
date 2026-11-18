import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../crypto/aes_gcm.dart';
import '../crypto/envelope.dart';
import '../domain/daily_question.dart' show dayKey;
import '../storage/local_settings.dart';
import '../storage/tables.dart';
import '../storage/vault_store.dart';

const String awayFeedKey = 'our_space_away';
const String lettersWrittenHereKey = 'lettersWrittenHere';
const int awayFeedLimit = 50;
const int awayMergeMs = 30 * 60 * 1000;

enum AwayKind { letter, opened, polaroid, love, dream, done, answer, countdown }

const Set<AwayKind> _mergingKinds = {AwayKind.letter, AwayKind.polaroid, AwayKind.love, AwayKind.dream, AwayKind.countdown};

@immutable
class AwayEntry {
  const AwayEntry({
    required this.id,
    required this.kind,
    required this.recordId,
    required this.at,
    this.count = 1,
    this.read = false,
  });

  final String id;
  final AwayKind kind;
  final String recordId;
  final int at;
  final int count;
  final bool read;

  AwayEntry copyWith({int? at, int? count, bool? read}) => AwayEntry(
        id: id,
        kind: kind,
        recordId: recordId,
        at: at ?? this.at,
        count: count ?? this.count,
        read: read ?? this.read,
      );

  Map<String, Object?> toJson() => {'id': id, 'k': kind.name, 'r': recordId, 'at': at, 'n': count, 'read': read};

  static AwayEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final kindName = raw['k'];
    final recordId = raw['r'];
    final at = raw['at'];
    final count = raw['n'];
    if (id is! String || kindName is! String || recordId is! String || at is! int) return null;
    AwayKind? kind;
    for (final value in AwayKind.values) {
      if (value.name == kindName) kind = value;
    }
    if (kind == null) return null;
    return AwayEntry(
      id: id,
      kind: kind,
      recordId: recordId,
      at: at,
      count: count is int && count > 0 ? count : 1,
      read: raw['read'] == true,
    );
  }
}

class AwayFeed extends ChangeNotifier {
  AwayFeed({
    required this.store,
    required this._key,
    required this._myOwnerIds,
    required this._myBurstId,
  }) {
    _entries = _readEntries(store.settings);
    _sub = store.incoming.listen(_onIncoming);
  }

  final VaultStore store;
  final VaultKey? Function() _key;
  final Set<String> Function() _myOwnerIds;
  final String Function() _myBurstId;

  late List<AwayEntry> _entries;
  late final StreamSubscription<IncomingChange> _sub;
  final StreamController<AwayEntry> _arrivals = StreamController<AwayEntry>.broadcast();
  bool _disposed = false;
  int _counter = 0;

  List<AwayEntry> get entries => List.unmodifiable(_entries);

  int get unread => _entries.where((entry) => !entry.read).length;

  Stream<AwayEntry> get arrivals => _arrivals.stream;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  static List<AwayEntry> _readEntries(LocalSettings settings) {
    final raw = settings.getItem(awayFeedKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return [for (final item in decoded) ?AwayEntry.fromJson(item)];
    } catch (_) {
      return [];
    }
  }

  Set<String> _writtenHere() {
    final raw = store.settings.getItem(lettersWrittenHereKey);
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return {for (final id in decoded) if (id is String) id};
    } catch (_) {}
    return const {};
  }

  void _onIncoming(IncomingChange change) {
    if (_disposed) return;
    final key = _key();
    if (key == null) return;
    final kind = _classify(change, key);
    if (kind == null) return;
    _add(kind.$1, change.row['id'] as String? ?? '', kind.$2);
  }

  Map<String, Object?>? _open(Row? row, VaultKey key, String table) {
    if (row == null) return null;
    try {
      return decryptRecord(row, key, table: table);
    } catch (_) {
      return null;
    }
  }

  (AwayKind, int)? _classify(IncomingChange change, VaultKey key) {
    final row = change.row;
    if (row['deleted'] == true || row['deleted'] == 1) return null;
    final id = row['id'];
    if (id is! String) return null;
    switch (change.table) {
      case lettersTable:
        if (change.isNew) return _writtenHere().contains(id) ? null : (AwayKind.letter, 1);
        if (!_writtenHere().contains(id)) return null;
        final now = _open(row, key, lettersTable);
        final before = _open(change.previous, key, lettersTable);
        if (now?['isOpened'] == true && before?['isOpened'] != true) return (AwayKind.opened, 1);
        return null;
      case memoriesTable:
        return change.isNew ? (AwayKind.polaroid, 1) : null;
      case milestonesTable:
        return change.isNew ? (AwayKind.countdown, 1) : null;
      case bucketListTable:
        if (change.isNew) return (AwayKind.dream, 1);
        final now = _open(row, key, bucketListTable);
        final before = _open(change.previous, key, bucketListTable);
        if (now?['completed'] == true && before?['completed'] != true) return (AwayKind.done, 1);
        return null;
      case dailyAnswersTable:
        final now = _open(row, key, dailyAnswersTable);
        if (now == null) return null;
        final owner = now['ownerId'];
        if (owner is! String || _myOwnerIds().contains(owner)) return null;
        final today = dayKey(store.now());
        final answers = now['answers'];
        if (answers is! Map || answers[today] == null) return null;
        final before = change.isNew ? null : _open(change.previous, key, dailyAnswersTable);
        final earlier = before?['answers'];
        if (earlier is Map && earlier[today] != null) return null;
        return (AwayKind.answer, 1);
      case loveBurstsTable:
        if (id == _myBurstId()) return null;
        final now = _open(row, key, loveBurstsTable);
        final count = now?['count'];
        if (count is! num) return null;
        final before = change.isNew ? null : _open(change.previous, key, loveBurstsTable);
        final earlier = before?['count'];
        final added = count.floor() - (earlier is num ? earlier.floor() : 0);
        return added > 0 ? (AwayKind.love, added) : null;
    }
    return null;
  }

  void _add(AwayKind kind, String recordId, int count) {
    final now = store.now();
    AwayEntry entry;
    final latest = _entries.isEmpty ? null : _entries.first;
    if (latest != null &&
        !latest.read &&
        latest.kind == kind &&
        _mergingKinds.contains(kind) &&
        now - latest.at < awayMergeMs) {
      entry = latest.copyWith(at: now, count: latest.count + count);
      _entries = [entry, ..._entries.skip(1)];
    } else {
      entry = AwayEntry(
        id: '${now.toRadixString(36)}-${(_counter++).toRadixString(36)}',
        kind: kind,
        recordId: recordId,
        at: now,
        count: count,
      );
      _entries = [entry, ..._entries].take(awayFeedLimit).toList();
    }
    _save();
    notifyListeners();
    if (!_arrivals.isClosed) _arrivals.add(entry);
  }

  void markRead(String id) {
    if (!_entries.any((entry) => entry.id == id && !entry.read)) return;
    _entries = [for (final entry in _entries) entry.id == id ? entry.copyWith(read: true) : entry];
    _save();
    notifyListeners();
  }

  void markAllRead() {
    if (unread == 0) return;
    _entries = [for (final entry in _entries) entry.read ? entry : entry.copyWith(read: true)];
    _save();
    notifyListeners();
  }

  void clear() {
    if (_entries.isEmpty) return;
    _entries = [];
    _save();
    notifyListeners();
  }

  void _save() {
    if (_entries.isEmpty) {
      unawaited(store.settings.removeItem(awayFeedKey));
      return;
    }
    unawaited(store.settings.setItem(awayFeedKey, jsonEncode([for (final entry in _entries) entry.toJson()])));
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_sub.cancel());
    unawaited(_arrivals.close());
    super.dispose();
  }
}
