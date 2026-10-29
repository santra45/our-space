import '../../../models/date_idea_record.dart';
import '../crypto/base64.dart';
import '../crypto/envelope.dart';
import '../crypto/js_compat.dart';
import '../data/web_data.dart';
import '../storage/tables.dart';
import '../storage/vault_store.dart';
import 'table_repository.dart';

const int dateIdeaTitleLimit = 80;
const int dateIdeaDescLimit = 240;

class DateIdeasRepository extends TableRepository<DateIdeaRecord> {
  DateIdeasRepository({required super.store, required super.vault}) : super(table: dateIdeasTable);

  @override
  bool keeps(Row row) => row['id'] != rouletteStateId;

  @override
  DateIdeaRecord? fromPlain(Map<String, Object?> plain, Row row) {
    final record = DateIdeaRecord(stripInternalFields(plain));
    return jsTrim(record.title).isEmpty ? null : record;
  }

  @override
  int compare(DateIdeaRecord a, DateIdeaRecord b) {
    final byPlace = _place(a.id).compareTo(_place(b.id));
    if (byPlace != 0) return byPlace;
    final byCreated = a.createdAt.compareTo(b.createdAt);
    if (byCreated != 0) return byCreated;
    return a.id.compareTo(b.id);
  }

  int _place(String id) {
    final index = defaultDateIdeas.indexWhere((idea) => idea.id == id);
    return index < 0 ? defaultDateIdeas.length : index;
  }

  @override
  Future<TableSnapshot<DateIdeaRecord>> load() async {
    final snapshot = await super.load();
    if (!snapshot.unlocked) return snapshot;
    final touched = {for (final row in await store.allRows(table, includeBlobs: false)) row['id']};
    final present = {for (final item in snapshot.items) item.id};
    final items = [
      ...snapshot.items,
      for (final idea in defaultDateIdeas)
        if (!touched.contains(idea.id) && !present.contains(idea.id)) DateIdeaRecord.builtIn(idea),
    ]..sort(compare);
    return TableSnapshot<DateIdeaRecord>(items: items, unreadable: snapshot.unreadable, unlocked: true);
  }

  String newIdeaId() => 'date-${randomUuidV4()}';

  Future<Row?> add({required String title, required String desc, required String category}) async {
    final cleanTitle = _fit(title, dateIdeaTitleLimit);
    if (cleanTitle.isEmpty) return null;
    return write({
      'id': newIdeaId(),
      'title': cleanTitle,
      'desc': _fit(desc, dateIdeaDescLimit),
      'category': category,
      'createdAt': store.now(),
      'updatedAt': stamp(),
      'deleted': false,
    });
  }

  Future<Row?> edit(
    DateIdeaRecord idea, {
    required String title,
    required String desc,
    required String category,
  }) async {
    final cleanTitle = _fit(title, dateIdeaTitleLimit);
    if (cleanTitle.isEmpty || idea.id == rouletteStateId) return null;
    return write({
      ...idea.toFields(),
      'title': cleanTitle,
      'desc': _fit(desc, dateIdeaDescLimit),
      'category': category,
      'updatedAt': stamp(),
      'deleted': false,
    });
  }

  Future<Row?> remove(String id) async {
    if (id == rouletteStateId) return null;
    final removed = await delete(id);
    if (removed != null) return removed;
    return store.putEncrypted(table, {'id': id, 'updatedAt': stamp(), 'deleted': true}, requireKey());
  }

  String _fit(String value, int limit) {
    final trimmed = jsTrim(value);
    final cap = limit * 4;
    final runes = trimmed.runes;
    return runes.length <= cap ? trimmed : jsTrim(String.fromCharCodes(runes.take(cap)));
  }
}
