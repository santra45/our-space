import 'package:sqflite/sqflite.dart';

class LocalSettings {
  LocalSettings._(this._db, this._cache);

  static const String tableName = 'localSettings';

  static Future<LocalSettings> load(Database db) async {
    final rows = await db.query(tableName);
    final cache = <String, String>{};
    for (final row in rows) {
      final key = row['key'];
      final value = row['value'];
      if (key is String && value is String) cache[key] = value;
    }
    return LocalSettings._(db, cache);
  }

  static LocalSettings memory([Map<String, String>? seed]) =>
      LocalSettings._(null, Map<String, String>.from(seed ?? const {}));

  final Database? _db;
  final Map<String, String> _cache;

  String? getItem(String key) => _cache[key];

  Future<void> setItem(String key, String value) async {
    _cache[key] = value;
    final db = _db;
    if (db == null) return;
    await db.insert(
      tableName,
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> removeItem(String key) async {
    _cache.remove(key);
    final db = _db;
    if (db == null) return;
    await db.delete(tableName, where: 'key = ?', whereArgs: [key]);
  }

  Map<String, String> snapshot() => Map<String, String>.unmodifiable(_cache);
}
