import 'dart:async';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../crypto/aes_gcm.dart';
import '../crypto/base64.dart';
import '../crypto/envelope.dart';
import '../crypto/js_compat.dart';
import '../crypto/kdf.dart';
import '../domain/limits.dart';
import 'local_settings.dart';
import 'merge_rules.dart';
import 'sync_clock.dart';
import 'tables.dart';

typedef Row = Map<String, Object?>;

class TableWrite {
  const TableWrite(this.table, this.fields);
  final String table;
  final Map<String, Object?> fields;
}

class SealedWrite {
  const SealedWrite(this.table, this.row);
  final String table;
  final Row row;
}

class VaultIdentityRead {
  const VaultIdentityRead({required this.ok, this.meta, this.error});
  final bool ok;
  final Map<String, Object?>? meta;
  final Object? error;
}

class MergeStats {
  int total = 0;
  int added = 0;
  int updated = 0;
  int deleted = 0;
  int stale = 0;
  int invalid = 0;
  int undecryptable = 0;
  int tampered = 0;
  int unauthenticated = 0;
  int unverifiable = 0;
  int unverifiableNewer = 0;

  void bump(String verdict) {
    switch (verdict) {
      case 'undecryptable':
        undecryptable++;
      case 'tampered':
        tampered++;
      default:
        invalid++;
    }
  }

  void addAll(MergeStats other) {
    added += other.added;
    updated += other.updated;
    deleted += other.deleted;
    stale += other.stale;
    invalid += other.invalid;
    undecryptable += other.undecryptable;
    tampered += other.tampered;
    unauthenticated += other.unauthenticated;
    unverifiable += other.unverifiable;
    unverifiableNewer += other.unverifiableNewer;
  }

  Map<String, int> toJson({bool includeTotal = false}) => {
        if (includeTotal) 'total': total,
        'added': added,
        'updated': updated,
        'deleted': deleted,
        'stale': stale,
        'invalid': invalid,
        'undecryptable': undecryptable,
        'tampered': tampered,
        'unauthenticated': unauthenticated,
        'unverifiable': unverifiable,
        'unverifiableNewer': unverifiableNewer,
      };
}

class MergePlan {
  MergePlan._(this.writes, this.perTable, this.totals, this.skippedTables, this.key);
  final List<SealedWrite> writes;
  final Map<String, MergeStats> perTable;
  final MergeStats totals;
  final List<String> skippedTables;
  final VaultKey key;
}

class MergeResult {
  const MergeResult(this.written, this.supersededSincePreview, this.refusedSincePreview);
  final Map<String, int> written;
  final int supersededSincePreview;
  final int refusedSincePreview;

  int get totalWritten => written.values.fold(0, (sum, n) => sum + n);
}

class StoreError implements Exception {
  StoreError(this.message);
  final String message;
  @override
  String toString() => message;
}

const int _bulkWriteChunk = 100;

class VaultStore {
  VaultStore._(this._db, this.settings, this.clock, this._now);

  static const String defaultFileName = 'our_space.sqlite';

  static Future<VaultStore> open({
    DatabaseFactory? factory,
    String? path,
    NowFn now = systemNow,
  }) async {
    final dbFactory = factory ?? databaseFactory;
    final location = path ?? p.join(await dbFactory.getDatabasesPath(), defaultFileName);
    final db = await dbFactory.openDatabase(
      location,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = OFF');
        },
        onCreate: (db, version) async {
          await _createSchema(db);
        },
      ),
    );
    final settings = await LocalSettings.load(db);
    final clock = SyncClock(settings, now: now);
    return VaultStore._(db, settings, clock, now);
  }

  static Future<void> _createSchema(Database db) async {
    await db.execute(
      'CREATE TABLE IF NOT EXISTS "$vaultMetaTable" ('
      'id TEXT PRIMARY KEY, salt TEXT, canary TEXT, canaryIv TEXT, '
      'kdfIterations NUMERIC, updatedAt NUMERIC)',
    );
    for (final table in syncedTables) {
      await db.execute(
        'CREATE TABLE IF NOT EXISTS "$table" ('
        'id TEXT PRIMARY KEY, updatedAt NUMERIC, deleted INTEGER NOT NULL DEFAULT 0, '
        'del INTEGER NOT NULL DEFAULT 0, v NUMERIC, ciphertext TEXT, iv TEXT, imageBlob BLOB)',
      );
      await db.execute('CREATE INDEX IF NOT EXISTS "${table}_updatedAt" ON "$table" (updatedAt)');
      await db.execute('CREATE INDEX IF NOT EXISTS "${table}_del" ON "$table" (del)');
    }
    await db.execute(
      'CREATE TABLE IF NOT EXISTS "${LocalSettings.tableName}" (key TEXT PRIMARY KEY, value TEXT)',
    );
  }

  final Database _db;
  final LocalSettings settings;
  final SyncClock clock;
  final NowFn _now;

  final StreamController<Set<String>> _changes = StreamController<Set<String>>.broadcast();
  final StreamController<String> _localWrites = StreamController<String>.broadcast();

  Stream<Set<String>> get changes => _changes.stream;

  Stream<String> get localWrites => _localWrites.stream;

  void _noteLocal(Iterable<String> tables) {
    if (_localWrites.isClosed) return;
    for (final table in tables.toSet()) {
      _localWrites.add(table);
    }
  }

  Stream<void> watchTable(String table) {
    late StreamController<void> controller;
    StreamSubscription<Set<String>>? subscription;
    controller = StreamController<void>(
      onListen: () {
        controller.add(null);
        subscription = changes.listen((tables) {
          if (tables.contains(table)) controller.add(null);
        });
      },
      onCancel: () async {
        await subscription?.cancel();
      },
    );
    return controller.stream;
  }

  void _emit(Iterable<String> tables) {
    final set = tables.toSet();
    if (set.isEmpty || _changes.isClosed) return;
    _changes.add(set);
  }

  int now() => _now();

  Future<void> close() async {
    await _changes.close();
    await _localWrites.close();
    await _db.close();
  }

  void _checkTable(String table) {
    if (!syncedTables.contains(table)) {
      throw StoreError('unknown table "$table"');
    }
  }

  Row _fromSql(Map<String, Object?> sql) {
    final row = <String, Object?>{
      'id': sql['id'],
      'updatedAt': sql['updatedAt'],
      'deleted': sql['deleted'] == 1,
      'v': sql['v'],
      'ciphertext': sql['ciphertext'],
      'iv': sql['iv'],
    };
    final blob = sql['imageBlob'];
    if (blob is Uint8List) {
      row['imageBlob'] = blob;
    } else if (blob is List<int>) {
      row['imageBlob'] = Uint8List.fromList(blob);
    }
    row['_del'] = sql['del'];
    return row;
  }

  Map<String, Object?> _toSql(Row row) {
    final deleted = row['deleted'] == true;
    final blob = row['imageBlob'];
    return {
      'id': row['id'],
      'updatedAt': row['updatedAt'] is num ? row['updatedAt'] : null,
      'deleted': deleted ? 1 : 0,
      'del': deleted ? 1 : 0,
      'v': row['v'] is num ? row['v'] : null,
      'ciphertext': row['ciphertext'] is String ? row['ciphertext'] : null,
      'iv': row['iv'] is String ? row['iv'] : null,
      'imageBlob': isBinaryValue(blob) ? binaryBytes(blob!) : null,
    };
  }

  Future<Row?> getRow(String table, String id) async {
    _checkTable(table);
    final rows = await _db.query('"$table"', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return _fromSql(rows.first);
  }

  Future<List<Row?>> bulkGet(String table, List<String> ids) async {
    _checkTable(table);
    final found = <String, Row>{};
    for (var offset = 0; offset < ids.length; offset += 500) {
      final chunk = ids.sublist(offset, offset + 500 > ids.length ? ids.length : offset + 500);
      if (chunk.isEmpty) continue;
      final placeholders = List.filled(chunk.length, '?').join(',');
      final rows = await _db.query('"$table"', where: 'id IN ($placeholders)', whereArgs: chunk);
      for (final sql in rows) {
        final row = _fromSql(sql);
        found[row['id'] as String] = row;
      }
    }
    return [for (final id in ids) found[id]];
  }

  Future<List<Row>> allRows(String table, {bool includeBlobs = true}) async {
    _checkTable(table);
    final rows = includeBlobs
        ? await _db.query('"$table"', orderBy: 'id')
        : await _db.query(
            '"$table"',
            columns: ['id', 'updatedAt', 'deleted', 'del', 'v', 'ciphertext', 'iv'],
            orderBy: 'id',
          );
    return rows.map(_fromSql).toList();
  }

  Future<int> countLive(String table) async {
    _checkTable(table);
    final result = await _db.rawQuery('SELECT COUNT(*) AS n FROM "$table" WHERE del = 0');
    return (result.first['n'] as int?) ?? 0;
  }

  Future<void> putRow(String table, Row row) async {
    _checkTable(table);
    await _db.insert('"$table"', _toSql(row), conflictAlgorithm: ConflictAlgorithm.replace);
    _emit([table]);
  }

  Future<void> putRows(List<SealedWrite> writes) async {
    if (writes.isEmpty) return;
    for (final write in writes) {
      _checkTable(write.table);
    }
    await _db.transaction((txn) async {
      final batch = txn.batch();
      for (final write in writes) {
        batch.insert('"${write.table}"', _toSql(write.row), conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
    _emit(writes.map((w) => w.table));
  }

  Future<bool> addRowsIfTableEmpty(String table, List<Row> rows) async {
    _checkTable(table);
    var added = false;
    await _db.transaction((txn) async {
      final live = await txn.rawQuery('SELECT COUNT(*) AS n FROM "$table" WHERE del = 0');
      if (((live.first['n'] as int?) ?? 0) > 0) return;
      for (final row in rows) {
        final existing = await txn.query('"$table"', columns: ['id'], where: 'id = ?', whereArgs: [row['id']]);
        if (existing.isNotEmpty) continue;
        await txn.insert('"$table"', _toSql(row));
        added = true;
      }
    });
    if (added) {
      _emit([table]);
      _noteLocal([table]);
    }
    return added;
  }

  Future<void> clearTable(String table) async {
    _checkTable(table);
    await _db.delete('"$table"');
    _emit([table]);
  }

  Future<void> clearSyncedTables() async {
    for (final table in syncedTables) {
      try {
        await _db.delete('"$table"');
      } catch (_) {}
    }
    _emit(syncedTables);
  }

  Future<Map<String, Object?>?> getVaultMeta() async {
    final rows = await _db.query('"$vaultMetaTable"', where: 'id = ?', whereArgs: ['config'], limit: 1);
    if (rows.isEmpty) return null;
    final row = rows.first;
    return {
      'id': row['id'],
      'salt': row['salt'],
      'canary': row['canary'],
      'canaryIv': row['canaryIv'],
      'kdfIterations': row['kdfIterations'],
      'updatedAt': row['updatedAt'],
    };
  }

  Future<void> putVaultMeta(Map<String, Object?> meta) async {
    await _db.insert(
      '"$vaultMetaTable"',
      {
        'id': 'config',
        'salt': meta['salt'],
        'canary': meta['canary'],
        'canaryIv': meta['canaryIv'],
        'kdfIterations': meta['kdfIterations'] is num ? meta['kdfIterations'] : null,
        'updatedAt': meta['updatedAt'] is num ? meta['updatedAt'] : null,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _emit([vaultMetaTable]);
  }

  Future<VaultIdentityRead> readVaultIdentity() async {
    try {
      final meta = await getVaultMeta();
      final salt = meta?['salt'];
      return VaultIdentityRead(ok: true, meta: (salt is String && salt.isNotEmpty) ? meta : null);
    } catch (err) {
      return VaultIdentityRead(ok: false, error: err);
    }
  }

  Future<void> restoreVaultIdentity(Map<String, Object?> metaRow) async {
    await putVaultMeta({
      'salt': metaRow['salt'],
      'canary': metaRow['canary'],
      'canaryIv': metaRow['canaryIv'],
      'kdfIterations': isFiniteNumber(metaRow['kdfIterations'])
          ? metaRow['kdfIterations']
          : pbkdf2IterationsCurrent,
      'updatedAt': isFiniteNumber(metaRow['updatedAt']) ? metaRow['updatedAt'] : 0,
    });
  }

  Future<Map<String, List<Map<String, Object?>>>> getManifest() async {
    final manifest = <String, List<Map<String, Object?>>>{};
    for (final table in syncedTables) {
      final rows = await _db.query('"$table"', columns: ['id', 'updatedAt', 'del'], orderBy: 'id');
      manifest[table] = [
        for (final row in rows)
          {
            'id': row['id'],
            'updatedAt': isFiniteNumber(row['updatedAt']) ? row['updatedAt'] : 0,
            'deleted': row['del'] == 1,
          },
      ];
    }
    return manifest;
  }

  Future<Row> putEncrypted(String table, Map<String, Object?> plainFields, VaultKey? key) async {
    if (!syncedTables.contains(table)) {
      throw StoreError('putEncrypted: unknown table "$table"');
    }
    if (key == null) throw StoreError('putEncrypted: vault is locked');
    final row = encryptRecord(plainFields, key, table: table, now: _now);
    await putRow(table, row);
    row['_del'] = row['deleted'] == true ? 1 : 0;
    _noteLocal([table]);
    return row;
  }

  Future<List<SealedWrite>> putEncryptedMany(List<TableWrite> entries, VaultKey? key) async {
    if (key == null) throw StoreError('putEncryptedMany: vault is locked');
    final sealed = <SealedWrite>[];
    for (final entry in entries) {
      if (!syncedTables.contains(entry.table)) {
        throw StoreError('putEncryptedMany: unknown table "${entry.table}"');
      }
      final row = encryptRecord(entry.fields, key, table: entry.table, now: _now);
      sealed.add(SealedWrite(entry.table, row));
    }
    if (sealed.isEmpty) return sealed;
    await putRows(sealed);
    for (final entry in sealed) {
      entry.row['_del'] = entry.row['deleted'] == true ? 1 : 0;
    }
    _noteLocal(sealed.map((entry) => entry.table));
    return sealed;
  }

  Future<Map<String, Object?>?> getDecrypted(String table, String id, VaultKey? key) async {
    if (key == null) throw StoreError('getDecrypted: vault is locked');
    final row = await getRow(table, id);
    if (row == null) return null;
    return decryptRecord(row, key, table: table);
  }

  Future<List<Map<String, Object?>>> listDecrypted(
    String table,
    VaultKey? key, {
    bool includeDeleted = false,
  }) async {
    if (key == null) throw StoreError('listDecrypted: vault is locked');
    final rows = await allRows(table);
    final out = <Map<String, Object?>>[];
    for (final row in rows) {
      if (!includeDeleted && row['deleted'] == true) continue;
      try {
        out.add(decryptRecord(row, key, table: table));
      } catch (_) {}
    }
    return out;
  }

  Future<Row?> softDelete(String table, String id, VaultKey? key, {int Function()? timestamp}) async {
    final existing = await getRow(table, id);
    if (existing == null) return null;
    if (key == null) {
      throw StoreError('softDelete requires the vault key to write a replicable tombstone.');
    }
    final stamp = (timestamp ?? clock.next)();
    final previous = existing['updatedAt'];
    final floor = (previous is num && previous != 0 && !previous.isNaN ? previous : 0) + 1;
    final updatedAt = stamp > floor ? stamp : floor;
    final row = encryptRecord({'id': id, 'updatedAt': updatedAt, 'deleted': true}, key, table: table, now: _now);
    await putRow(table, row);
    row['_del'] = 1;
    _noteLocal([table]);
    return row;
  }

  Future<Map<String, Object?>> exportRawDataForBackup() async {
    final tables = <String, Object?>{};
    final meta = await getVaultMeta();
    tables[vaultMetaTable] = meta == null ? <Object?>[] : [meta];
    for (final table in syncedTables) {
      final rows = await allRows(table);
      tables[table] = [
        for (final row in rows) _exportRow(table, row),
      ];
    }
    return {
      'version': 2,
      'exportedAt': toJsIsoString(_now()),
      'tables': tables,
    };
  }

  Map<String, Object?> _exportRow(String table, Row row) {
    final clone = Map<String, Object?>.from(row);
    if (table == memoriesTable && clone['imageBlob'] != null) {
      clone['imageBlobBase64'] = bufferToBase64(binaryBytes(clone['imageBlob']!));
      clone.remove('imageBlob');
    }
    return clone;
  }

  Row? sanitizeImportedRecord(String table, Object? record) {
    final source = record is Map ? asStringMap(record) : null;
    if (source == null) return null;
    final id = source['id'];
    if (id is! String || id.isEmpty || id.length > 128) return null;
    final updatedAt = source['updatedAt'];
    if (source.containsKey('updatedAt') && updatedAt != null && !isFiniteNumber(updatedAt)) return null;
    if (source.containsKey('updatedAt') && updatedAt == null) return null;
    if (isFiniteNumber(updatedAt)) {
      final at = updatedAt as num;
      if (at < 0) return null;
      if (at > _now() + maxClockSkewMs) return null;
    }
    if (source['v'] != recordSchemaVersion) return null;

    const common = ['id', 'updatedAt', 'deleted', 'v', 'ciphertext', 'iv', '_del'];
    final allowed = {...common, ...(binaryFieldsByTable[table] ?? const <String>[])};
    final out = <String, Object?>{};
    source.forEach((field, value) {
      if (!allowed.contains(field)) return;
      out[field] = value;
    });

    out['updatedAt'] = isFiniteNumber(updatedAt) ? updatedAt : 0;
    out['deleted'] = source['deleted'] == true;
    out['_del'] = out['deleted'] == true ? 1 : 0;

    final blobBase64 = source['imageBlobBase64'];
    if (table == memoriesTable && blobBase64 is String) {
      try {
        final bytes = base64ToBuffer(blobBase64);
        if (bytes.length > maxImageBlobBytes) return null;
        out['imageBlob'] = bytes;
      } catch (_) {
        return null;
      }
    } else if (out.containsKey('imageBlob')) {
      final blob = out['imageBlob'];
      Uint8List bytes;
      if (blob is Uint8List) {
        bytes = blob;
      } else if (blob is ByteBuffer) {
        bytes = blob.asUint8List();
      } else if (blob is List) {
        if (blob.length > maxImageBlobBytes) return null;
        if (blob.any((b) => b is! int)) return null;
        bytes = Uint8List.fromList(blob.cast<int>());
      } else {
        return null;
      }
      if (bytes.length > maxImageBlobBytes) return null;
      out['imageBlob'] = bytes;
    }
    return out;
  }

  String _verifyRowIntegrity(Row row, VaultKey key, String table) {
    if (!recordHasAuthenticatedHeader(row)) return 'undecryptable';
    try {
      final plain = decryptRecord(row, key, table: table);
      if (plain['_headerTampered'] == true ||
          plain['_binaryTampered'] == true ||
          plain['_tableTampered'] == true) {
        return 'tampered';
      }
      if (plain['_binaryUnverified'] == true || plain['_tableUnverified'] == true) {
        return 'unverified';
      }
      return 'ok';
    } catch (_) {
      return 'undecryptable';
    }
  }

  Future<MergePlan> planBackupMerge(Object? tables, VaultKey? key) async {
    final map = tables is Map ? asStringMap(tables) : null;
    if (map == null) {
      throw StoreError('Invalid backup table payload');
    }
    if (key == null) {
      throw StoreError('Cannot verify a backup while the vault is locked.');
    }

    final perTable = <String, MergeStats>{};
    final skippedTables = <String>[];
    final writes = <SealedWrite>[];
    final totals = MergeStats();

    for (final entry in map.entries) {
      final tableName = entry.key;
      final records = entry.value;
      if (!importableTables.contains(tableName) || records is! List) {
        skippedTables.add(tableName);
        continue;
      }
      if (records.length > maxRecordsPerTable) {
        throw StoreError(
          'Backup rejected: "$tableName" contains ${records.length} records (limit $maxRecordsPerTable).',
        );
      }

      final stats = MergeStats()..total = records.length;
      final candidates = <(Row, bool)>[];
      for (final record in records) {
        final row = sanitizeImportedRecord(tableName, record);
        if (row == null) {
          stats.invalid++;
          continue;
        }
        final verdict = _verifyRowIntegrity(row, key, tableName);
        if (verdict != 'ok' && verdict != 'unverified') {
          stats.bump(verdict);
          continue;
        }
        candidates.add((row, verdict == 'ok'));
      }

      for (var offset = 0; offset < candidates.length; offset += _bulkWriteChunk) {
        final end = offset + _bulkWriteChunk > candidates.length ? candidates.length : offset + _bulkWriteChunk;
        final chunk = candidates.sublist(offset, end);
        final existingRows = await bulkGet(tableName, [for (final c in chunk) c.$1['id'] as String]);
        for (var i = 0; i < chunk.length; i++) {
          final existing = existingRows[i];
          final (row, verified) = chunk[i];

          if (!recordHasAuthenticatedHeader(row)) {
            stats.unauthenticated++;
            continue;
          }

          if (existing == null) {
            if (row['deleted'] == true) {
              stats.invalid++;
              continue;
            }
            stats.added++;
            writes.add(SealedWrite(tableName, row));
            continue;
          }

          if (!verified) {
            stats.unauthenticated++;
            stats.unverifiable++;
            if (incomingWins(existing, row)) stats.unverifiableNewer++;
            continue;
          }

          if (!incomingWins(existing, row)) {
            stats.stale++;
            continue;
          }

          if (row['deleted'] == true && existing['deleted'] != true) {
            stats.deleted++;
          } else {
            stats.updated++;
          }
          writes.add(SealedWrite(tableName, row));
        }
      }

      perTable[tableName] = stats;
      totals.addAll(stats);
    }

    return MergePlan._(writes, perTable, totals, skippedTables, key);
  }

  Future<MergeResult> applyBackupMerge(MergePlan plan) async {
    final written = <String, int>{};
    var superseded = 0;
    var refused = 0;
    if (plan.writes.isEmpty) return MergeResult(written, superseded, refused);

    final verified = <SealedWrite>{};
    for (final entry in plan.writes) {
      if (_verifyRowIntegrity(entry.row, plan.key, entry.table) == 'ok') verified.add(entry);
    }

    final tableNames = <String>[];
    for (final entry in plan.writes) {
      if (!tableNames.contains(entry.table)) tableNames.add(entry.table);
    }

    final touched = <String>{};
    await _db.transaction((txn) async {
      for (final name in tableNames) {
        final entries = plan.writes.where((entry) => entry.table == name).toList();
        for (var offset = 0; offset < entries.length; offset += _bulkWriteChunk) {
          final end = offset + _bulkWriteChunk > entries.length ? entries.length : offset + _bulkWriteChunk;
          final chunk = entries.sublist(offset, end);
          final ids = [for (final entry in chunk) entry.row['id'] as String];
          final placeholders = List.filled(ids.length, '?').join(',');
          final found = <String, Row>{};
          for (final sql in await txn.query('"$name"', where: 'id IN ($placeholders)', whereArgs: ids)) {
            final row = _fromSql(sql);
            found[row['id'] as String] = row;
          }
          final stillWins = <Row>[];
          for (final entry in chunk) {
            final existing = found[entry.row['id']];
            final row = entry.row;
            if (!recordHasAuthenticatedHeader(row)) {
              superseded++;
              refused++;
              continue;
            }
            if (existing == null) {
              stillWins.add(row);
              continue;
            }
            if (!verified.contains(entry)) {
              superseded++;
              refused++;
              continue;
            }
            if (incomingWins(existing, row)) {
              stillWins.add(row);
              continue;
            }
            superseded++;
          }
          for (final row in stillWins) {
            await txn.insert('"$name"', _toSql(row), conflictAlgorithm: ConflictAlgorithm.replace);
          }
          if (stillWins.isNotEmpty) touched.add(name);
          written[name] = (written[name] ?? 0) + stillWins.length;
        }
      }
    });
    _emit(touched);
    return MergeResult(written, superseded, refused);
  }
}

Map<String, Object?>? readBackupVaultIdentity(Object? tables) {
  final map = tables is Map ? asStringMap(tables) : null;
  final rows = map?[vaultMetaTable];
  if (rows is! List) return null;
  Map<String, Object?>? row;
  for (final entry in rows) {
    final candidate = entry is Map ? asStringMap(entry) : null;
    if (candidate != null && candidate['id'] == 'config' && candidate['salt'] is String) {
      row = candidate;
      break;
    }
  }
  if (row == null) return null;
  if (row['canary'] is! String || row['canaryIv'] is! String) return null;
  return {
    'salt': row['salt'],
    'canary': row['canary'],
    'canaryIv': row['canaryIv'],
    'kdfIterations': isFiniteNumber(row['kdfIterations']) ? row['kdfIterations'] : pbkdf2IterationsCurrent,
    'updatedAt': isFiniteNumber(row['updatedAt']) ? row['updatedAt'] : 0,
  };
}

String compareVaultIdentity(Map<String, Object?>? backupIdentity, VaultIdentityRead? localRead) {
  if (localRead == null || !localRead.ok) return 'unknown';
  if (localRead.meta == null) return 'no-local-vault';
  if (backupIdentity == null || backupIdentity['salt'] is! String) return 'unknown';
  return backupIdentity['salt'] == localRead.meta!['salt'] ? 'same' : 'foreign';
}
