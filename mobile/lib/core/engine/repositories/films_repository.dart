import 'dart:math' as math;

import '../../../models/film_record.dart';
import '../crypto/envelope.dart';
import '../crypto/js_compat.dart';
import '../storage/tables.dart';
import '../storage/vault_store.dart';
import 'table_repository.dart';

const int filmTitleLimit = 80;

class FilmsRepository extends TableRepository<FilmRecord> {
  FilmsRepository({required super.store, required super.vault}) : super(table: watchedFilmsTable);

  @override
  FilmRecord? fromPlain(Map<String, Object?> plain, Row row) {
    final record = FilmRecord(stripInternalFields(plain));
    return jsTrim(record.title).isEmpty ? null : record;
  }

  @override
  int compare(FilmRecord a, FilmRecord b) {
    final byDay = b.watchedAt.compareTo(a.watchedAt);
    return byDay != 0 ? byDay : a.id.compareTo(b.id);
  }

  Future<Row?> keep({required String id, required String title, required int togetherMs}) async {
    final row = await store.getRow(table, id);
    if (row?['deleted'] == true) return null;
    final snapshot = await load();
    if (!snapshot.unlocked) return null;
    FilmRecord? existing;
    for (final item in snapshot.items) {
      if (item.id == id) existing = item;
    }
    final name = existing?.title ?? _fit(title);
    if (name.isEmpty) return null;
    return write({
      'id': id,
      'title': name,
      'watchedAt': existing?.watchedAt ?? store.now(),
      'togetherMs': math.max(existing?.togetherMs ?? 0, togetherMs),
      'updatedAt': stamp(),
      'deleted': false,
    });
  }

  Future<Row?> rename(FilmRecord film, String title) async {
    final name = _fit(title);
    if (name.isEmpty) return null;
    return write({...film.toFields(), 'title': name, 'updatedAt': stamp(), 'deleted': false});
  }

  Future<Row?> remove(String id) => delete(id);

  String _fit(String value) {
    final clean = jsTrim(value);
    return clean.runes.length <= filmTitleLimit ? clean : String.fromCharCodes(clean.runes.take(filmTitleLimit));
  }
}

class FilmLinesRepository extends TableRepository<FilmLineRecord> {
  FilmLinesRepository({required super.store, required super.vault}) : super(table: watchedFilmLinesTable);

  @override
  FilmLineRecord? fromPlain(Map<String, Object?> plain, Row row) {
    final record = FilmLineRecord(stripInternalFields(plain));
    return record.film.isEmpty || jsTrim(record.text).isEmpty ? null : record;
  }

  @override
  int compare(FilmLineRecord a, FilmLineRecord b) {
    final byFilmTime = a.posMs.compareTo(b.posMs);
    if (byFilmTime != 0) return byFilmTime;
    final bySaid = a.at.compareTo(b.at);
    return bySaid != 0 ? bySaid : a.id.compareTo(b.id);
  }

  Future<Row?> keep({
    required String id,
    required String film,
    required String text,
    required String by,
    required int posMs,
    required int at,
  }) async {
    if (await store.getRow(table, id) != null) return null;
    return write({
      'id': id,
      'film': film,
      'text': text,
      'by': by,
      'posMs': posMs,
      'at': at,
      'updatedAt': stamp(),
      'deleted': false,
    });
  }

  Future<List<FilmLineRecord>> ofFilm(String film) async {
    return [for (final line in await list()) if (line.film == film) line];
  }

  Future<void> removeFilm(String film) async {
    for (final line in await ofFilm(film)) {
      await delete(line.id);
    }
  }
}
