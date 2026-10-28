import '../../../models/sky_drawing_record.dart';
import '../crypto/aes_gcm.dart';
import '../crypto/base64.dart';
import '../storage/tables.dart';
import '../storage/vault_store.dart';

class SkyDrawingService {
  SkyDrawingService({required this.store});

  final VaultStore store;

  Stream<void> watch() => store.watchTable(skyDrawingsTable);

  String newId() => 'sky-${generateUrlSafeNonce(12)}';

  static SkyDrawingRecord? _read(Map<String, Object?> row) {
    if (row['_headerTampered'] == true || row['_tableTampered'] == true) return null;
    return SkyDrawingRecord.tryParse(row);
  }

  Future<List<SkyDrawingRecord>> list(VaultKey? key) async {
    if (key == null) return const [];
    List<Map<String, Object?>> rows;
    try {
      rows = await store.listDecrypted(skyDrawingsTable, key);
    } catch (_) {
      return const [];
    }
    return [
      for (final row in rows)
        if (_read(row) case final record?) record,
    ];
  }

  Future<SkyDrawingRecord?> find(VaultKey? key, String id) async {
    if (key == null || skyId(id) == null) return null;
    try {
      final row = await store.getDecrypted(skyDrawingsTable, id, key);
      return row == null ? null : _read(row);
    } catch (_) {
      return null;
    }
  }

  static SkyDrawingRecord? pickUnfinished(Iterable<SkyDrawingRecord> records) {
    SkyDrawingRecord? best;
    for (final record in records) {
      if (record.finished || record.deleted) continue;
      if (best == null ||
          record.updatedAt > best.updatedAt ||
          (record.updatedAt == best.updatedAt && record.id.compareTo(best.id) < 0)) {
        best = record;
      }
    }
    return best;
  }

  Future<SkyDrawingRecord?> unfinished(VaultKey? key) async => pickUnfinished(await list(key));

  Future<String> idToOpen(VaultKey? key) async => (await unfinished(key))?.id ?? newId();

  Future<SkyDrawingRecord> saveProgress(
    VaultKey? key, {
    required String id,
    required SkyDrawing drawing,
    int? startedAt,
  }) async {
    if (key == null) throw StoreError('saveProgress: vault is locked');
    if (skyId(id) == null) throw StoreError('saveProgress: that drawing id cannot be kept');
    final existing = await find(key, id);
    if (existing != null && existing.finished) return existing;
    final merged = existing == null ? drawing : existing.drawing.merge(drawing);
    if (existing != null && merged == existing.drawing) return existing;
    final fields = SkyDrawingRecord.fieldsFor(
      id: id,
      drawing: merged,
      startedAt: existing?.startedAt ?? startedAt ?? store.now(),
      updatedAt: store.clock.next(),
    );
    await store.putEncrypted(skyDrawingsTable, fields, key);
    return SkyDrawingRecord.tryParse(fields)!;
  }

  Future<SkyDrawingRecord> finish(
    VaultKey? key, {
    required String id,
    required SkyDrawing drawing,
    required String name,
    int? at,
  }) async {
    if (key == null) throw StoreError('finish: vault is locked');
    if (skyId(id) == null) throw StoreError('finish: that drawing id cannot be kept');
    final clean = cleanSkyName(name);
    if (clean.isEmpty) throw StoreError('finish: a name is needed');
    final existing = await find(key, id);
    if (existing != null && existing.finished) return existing;
    final kept = (existing == null ? drawing : existing.drawing.merge(drawing)).settled();
    if (kept.isBlank) throw StoreError('finish: nothing is drawn yet');
    final when = at ?? store.now();
    final fields = SkyDrawingRecord.fieldsFor(
      id: id,
      drawing: kept,
      name: clean,
      finished: true,
      startedAt: existing?.startedAt ?? when,
      createdAt: when,
      night: skyNightOf(when),
      updatedAt: store.clock.next(),
    );
    await store.putEncrypted(skyDrawingsTable, fields, key);
    return SkyDrawingRecord.tryParse(fields)!;
  }

  Future<bool> remove(VaultKey? key, String id) async {
    if (key == null || skyId(id) == null) return false;
    return await store.softDelete(skyDrawingsTable, id, key) != null;
  }
}
