import 'dart:async';

import '../crypto/aes_gcm.dart';
import '../crypto/envelope.dart';
import '../storage/vault_store.dart';
import '../vault/vault_service.dart';

class TableSnapshot<T> {
  const TableSnapshot({required this.items, required this.unreadable, required this.unlocked});

  final List<T> items;
  final int unreadable;
  final bool unlocked;
}

class RepositoryError implements Exception {
  RepositoryError(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract class TableRepository<T> {
  TableRepository({required this.store, required this.vault, required this.table});

  final VaultStore store;
  final VaultService vault;
  final String table;

  final Map<String, T?> _cache = {};
  VaultKey? _cacheOwner;

  T? fromPlain(Map<String, Object?> plain, Row row);

  int compare(T a, T b);

  bool get readsBlobsLazily => false;

  VaultKey requireKey() {
    final key = vault.key;
    if (key == null) throw RepositoryError('Our Space is locked.');
    return key;
  }

  int stamp() => store.clock.next();

  void _syncCacheOwner(VaultKey? key) {
    if (!identical(_cacheOwner, key)) {
      _cache.clear();
      _cacheOwner = key;
    }
  }

  Future<TableSnapshot<T>> load() async {
    final key = vault.key;
    _syncCacheOwner(key);
    if (key == null) return TableSnapshot<T>(items: const [], unreadable: 0, unlocked: false);

    final rows = await store.allRows(table, includeBlobs: !readsBlobsLazily);
    final seen = <String>{};
    final items = <T>[];
    var unreadable = 0;

    for (final row in rows) {
      if (row['deleted'] == true) continue;
      final cacheKey = '${row['id']}::${row['updatedAt']}::${row['iv'] ?? ''}';
      seen.add(cacheKey);

      if (_cache.containsKey(cacheKey)) {
        final cached = _cache[cacheKey];
        if (cached == null) {
          unreadable++;
        } else {
          items.add(cached);
        }
        continue;
      }

      Row source = row;
      if (readsBlobsLazily) {
        final full = await store.getRow(table, row['id'] as String);
        if (full == null) continue;
        source = full;
      }

      Map<String, Object?> plain;
      try {
        plain = decryptRecord(source, key, table: table);
      } catch (_) {
        unreadable++;
        _cache[cacheKey] = null;
        continue;
      }
      if (plain['_headerTampered'] == true) {
        unreadable++;
        _cache[cacheKey] = null;
        continue;
      }
      if (plain['deleted'] == true) continue;

      final item = fromPlain(plain, source);
      _cache[cacheKey] = item;
      if (item == null) {
        unreadable++;
        continue;
      }
      items.add(item);
    }

    _cache.removeWhere((cacheKey, _) => !seen.contains(cacheKey));
    items.sort(compare);
    return TableSnapshot<T>(items: items, unreadable: unreadable, unlocked: true);
  }

  Future<List<T>> list() async => (await load()).items;

  Stream<TableSnapshot<T>> watch() {
    late StreamController<TableSnapshot<T>> controller;
    StreamSubscription<void>? subscription;
    var running = false;
    var dirty = false;

    Future<void> refresh() async {
      if (running) {
        dirty = true;
        return;
      }
      running = true;
      try {
        do {
          dirty = false;
          try {
            final snapshot = await load();
            if (!controller.isClosed) controller.add(snapshot);
          } catch (err, stack) {
            if (!controller.isClosed) controller.addError(err, stack);
          }
        } while (dirty && !controller.isClosed);
      } finally {
        running = false;
      }
    }

    void onVault() {
      unawaited(refresh());
    }

    controller = StreamController<TableSnapshot<T>>(
      onListen: () {
        subscription = store.watchTable(table).listen((_) => unawaited(refresh()));
        vault.addListener(onVault);
      },
      onCancel: () async {
        vault.removeListener(onVault);
        await subscription?.cancel();
      },
    );
    return controller.stream;
  }

  Future<Map<String, Object?>?> readPlain(String id) async {
    final key = requireKey();
    final plain = await store.getDecrypted(table, id, key);
    if (plain == null) return null;
    if (plain['deleted'] == true || plain['_headerTampered'] == true) return null;
    return plain;
  }

  Future<Row> write(Map<String, Object?> fields) => store.putEncrypted(table, fields, requireKey());

  Future<Row?> delete(String id) => store.softDelete(table, id, requireKey());
}
