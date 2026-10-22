import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/engine/storage/local_settings.dart';

enum MemoryAuthor { me, partner, unknown }

typedef MarksClock = int Function();

int _systemNow() => DateTime.now().millisecondsSinceEpoch;

class MemoryMarks extends ChangeNotifier {
  MemoryMarks(this._settings, {MarksClock? now, this.capacity = 2000}) : _now = now ?? _systemNow {
    _load();
  }

  static const String storageKey = 'memoryMarks';

  static final Expando<MemoryMarks> _shared = Expando<MemoryMarks>('MemoryMarks');

  static MemoryMarks of(LocalSettings settings) => _shared[settings] ??= MemoryMarks(settings);

  final LocalSettings _settings;
  final MarksClock _now;
  final int capacity;
  int? _since;
  final LinkedHashSet<String> _mine = LinkedHashSet<String>();
  final LinkedHashSet<String> _seen = LinkedHashSet<String>();
  int _pending = 0;
  int _pendingFrom = 0;

  int? get since => _since;
  bool get tracking => _since != null;
  bool get adding => _pending > 0;

  static int? createdAt(String id) {
    if (!id.startsWith('mem-')) return null;
    final rest = id.substring(4);
    final dash = rest.indexOf('-');
    if (dash <= 0) return null;
    final value = int.tryParse(rest.substring(0, dash), radix: 36);
    if (value == null || value <= 0) return null;
    return value;
  }

  void _load() {
    final raw = _settings.getItem(storageKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final since = decoded['since'];
      if (since is int && since > 0) _since = since;
      final mine = decoded['mine'];
      if (mine is List) _mine.addAll(mine.whereType<String>());
      final seen = decoded['seen'];
      if (seen is List) _seen.addAll(seen.whereType<String>());
    } catch (_) {
      _since = null;
      _mine.clear();
      _seen.clear();
    }
  }

  void _trim(LinkedHashSet<String> ids) {
    while (ids.length > capacity) {
      ids.remove(ids.first);
    }
  }

  void _save() {
    _trim(_mine);
    _trim(_seen);
    final payload = jsonEncode({'since': _since, 'mine': _mine.toList(), 'seen': _seen.toList()});
    unawaited(_settings.setItem(storageKey, payload).catchError((Object _) {}));
  }

  void start() {
    if (_since != null) return;
    _since = _now();
    _save();
  }

  bool _arrivedLater(String id) {
    final since = _since;
    final created = createdAt(id);
    return since != null && created != null && created >= since;
  }

  bool _waiting(String id) {
    if (_pending <= 0) return false;
    final created = createdAt(id);
    return created == null || created >= _pendingFrom;
  }

  MemoryAuthor authorOf(String id, {bool knowsPartner = true}) {
    if (_mine.contains(id)) return MemoryAuthor.me;
    if (!knowsPartner || !_arrivedLater(id) || _waiting(id)) return MemoryAuthor.unknown;
    return MemoryAuthor.partner;
  }

  bool isNew(String id) => !_mine.contains(id) && _arrivedLater(id) && !_waiting(id) && !_seen.contains(id);

  void markSeen(Iterable<String> ids) {
    var changed = false;
    for (final id in ids) {
      if (_seen.add(id)) changed = true;
    }
    if (changed) _save();
  }

  void beginAdd() {
    if (_pending == 0) _pendingFrom = _now();
    _pending++;
  }

  void endAdd(String? id) {
    if (_pending > 0) _pending--;
    if (id != null && id.isNotEmpty) {
      _mine.add(id);
      _seen.add(id);
      _save();
    }
    notifyListeners();
  }
}
