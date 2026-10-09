import '../../../models/bucket_list_record.dart';
import '../crypto/base64.dart';
import '../crypto/envelope.dart';
import '../crypto/js_compat.dart';
import '../data/web_data.dart';
import '../storage/tables.dart';
import '../storage/vault_store.dart';
import 'table_repository.dart';

String defaultBucketItemId(int index) => 'bkt-default-${index + 1}';

class BucketListRepository extends TableRepository<BucketListRecord> {
  BucketListRepository({required super.store, required super.vault}) : super(table: bucketListTable);

  Future<bool>? _seedInFlight;

  @override
  BucketListRecord? fromPlain(Map<String, Object?> plain, Row row) => BucketListRecord(stripInternalFields(plain));

  @override
  int compare(BucketListRecord a, BucketListRecord b) {
    if (a.completed != b.completed) return a.completed ? 1 : -1;
    final byCreated = a.createdAt - b.createdAt;
    if (byCreated != 0) return byCreated;
    return a.id.compareTo(b.id);
  }

  String newItemId() => 'bkt-${randomUuidV4()}';

  Future<bool> seedDefaultsIfEmpty() {
    final running = _seedInFlight;
    if (running != null) return running;
    final future = _seed().whenComplete(() => _seedInFlight = null);
    _seedInFlight = future;
    return future;
  }

  Future<bool> _seed() async {
    final key = requireKey();
    if (await store.countLive(bucketListTable) > 0) return false;
    final rows = <Row>[];
    for (var index = 0; index < defaultBucketItems.length; index++) {
      final item = defaultBucketItems[index];
      rows.add(encryptRecord(
        {
          'id': defaultBucketItemId(index),
          'text': item.text,
          'category': item.category,
          'completed': false,
          'completedAt': null,
          'createdAt': index,
          'updatedAt': stamp(),
          'deleted': false,
        },
        key,
        table: bucketListTable,
        now: store.now,
      ));
    }
    return store.addRowsIfTableEmpty(bucketListTable, rows);
  }

  Future<Row?> add({required String text, required String category}) async {
    final trimmed = jsTrim(text);
    if (trimmed.isEmpty) return null;
    return write({
      'id': newItemId(),
      'text': trimmed,
      'category': category,
      'completed': false,
      'completedAt': null,
      'createdAt': store.now(),
      'updatedAt': stamp(),
      'deleted': false,
    });
  }

  Future<Row> toggleComplete(BucketListRecord item) {
    final nowCompleted = !item.completed;
    return write({
      ...item.toFields(),
      'completed': nowCompleted,
      'completedAt': nowCompleted ? store.now() : null,
      'updatedAt': stamp(),
    });
  }

  Future<Row?> edit(BucketListRecord item, {required String text, required String category}) async {
    final trimmed = jsTrim(text);
    if (trimmed.isEmpty) return null;
    return write({
      ...item.toFields(),
      'text': trimmed,
      'category': category,
      'updatedAt': stamp(),
    });
  }
}
