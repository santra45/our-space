import 'dart:typed_data';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../constants/app_constants.dart';

/// Native SQLite Database persistence for Our Space 💕.
/// Replaces Dexie/IndexedDB with identical Schema v2 semantics.
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'our_space_vault.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        // Vault metadata table
        await db.execute('''
          CREATE TABLE vaultMeta (
            id TEXT PRIMARY KEY NOT NULL,
            salt TEXT NOT NULL,
            canary TEXT NOT NULL,
            canaryIv TEXT NOT NULL,
            kdfIterations INTEGER NOT NULL DEFAULT $pbkdf2IterationsCurrent,
            createdAt INTEGER NOT NULL,
            updatedAt INTEGER NOT NULL
          );
        ''');

        // Synced tables with Schema v2 authenticated envelopes
        for (final table in syncedTables) {
          final isMemories = table == 'memories';
          final blobCol = isMemories ? ', imageBlob BLOB' : '';

          await db.execute('''
            CREATE TABLE $table (
              id TEXT PRIMARY KEY NOT NULL,
              updatedAt INTEGER NOT NULL,
              deleted INTEGER NOT NULL DEFAULT 0,
              v INTEGER NOT NULL DEFAULT 2,
              iv TEXT NOT NULL,
              ciphertext TEXT NOT NULL,
              _bin TEXT,
              _tbl TEXT
              $blobCol
            );
          ''');

          await db.execute('''
            CREATE INDEX idx_${table}_sync ON $table(updatedAt, deleted);
          ''');
        }
      },
    );
  }

  // --------------------------------------------------------------------------
  // Vault Meta operations
  // --------------------------------------------------------------------------

  Future<Map<String, dynamic>?> getVaultMeta() async {
    final db = await database;
    final results = await db.query('vaultMeta', where: 'id = ?', whereArgs: ['config']);
    if (results.isEmpty) return null;
    return results.first;
  }

  Future<void> saveVaultMeta(Map<String, dynamic> meta) async {
    final db = await database;
    await db.insert(
      'vaultMeta',
      {
        'id': 'config',
        'salt': meta['salt'],
        'canary': meta['canary'],
        'canaryIv': meta['canaryIv'],
        'kdfIterations': meta['kdfIterations'] ?? pbkdf2IterationsCurrent,
        'createdAt': meta['createdAt'] ?? DateTime.now().millisecondsSinceEpoch,
        'updatedAt': meta['updatedAt'] ?? DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // --------------------------------------------------------------------------
  // Envelope CRUD operations
  // --------------------------------------------------------------------------

  /// Reads a single envelope by ID.
  Future<Map<String, dynamic>?> getRecord(String table, String id) async {
    final db = await database;
    final results = await db.query(table, where: 'id = ?', whereArgs: [id]);
    if (results.isEmpty) return null;
    return results.first;
  }

  /// Lists all non-deleted envelopes from a table.
  Future<List<Map<String, dynamic>>> getActiveRecords(String table) async {
    final db = await database;
    return await db.query(
      table,
      where: 'deleted = 0',
      orderBy: 'updatedAt DESC',
    );
  }

  /// Saves or updates an authenticated envelope.
  Future<void> putEnvelope(
    String table,
    Map<String, dynamic> envelope, {
    Uint8List? imageBlob,
  }) async {
    final db = await database;
    final data = Map<String, dynamic>.from(envelope);
    if (table == 'memories' && imageBlob != null) {
      data['imageBlob'] = imageBlob;
    }

    await db.insert(
      table,
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Soft deletes a record by updating tombstone flag and incrementing updatedAt.
  Future<void> softDelete(String table, String id, int updatedAt) async {
    final db = await database;
    await db.update(
      table,
      {
        'deleted': 1,
        'updatedAt': updatedAt,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Returns manifest summary of (id, updatedAt, deleted) across all synced tables for replication.
  Future<Map<String, List<Map<String, dynamic>>>> getManifest() async {
    final db = await database;
    final Map<String, List<Map<String, dynamic>>> manifest = {};

    for (final table in syncedTables) {
      final rows = await db.query(
        table,
        columns: ['id', 'updatedAt', 'deleted'],
      );
      manifest[table] = rows;
    }

    return manifest;
  }

  /// Destroys all database contents (Hard Reset).
  Future<void> wipeDatabase() async {
    final db = await database;
    for (final table in syncedTables) {
      await db.delete(table);
    }
    await db.delete('vaultMeta');
  }
}
