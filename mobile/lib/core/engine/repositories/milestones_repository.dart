import '../../../models/milestone_record.dart';
import '../crypto/base64.dart';
import '../crypto/envelope.dart';
import '../domain/date_helpers.dart';
import '../storage/tables.dart';
import '../storage/vault_store.dart';
import 'table_repository.dart';

int _milestoneSortKey(MilestoneRecord record) {
  final date = record.date;
  if (date == null || date.isEmpty) return 0;
  return parseLocalDate(date)?.millisecondsSinceEpoch ?? 0;
}

class MilestonesRepository extends TableRepository<MilestoneRecord> {
  MilestonesRepository({required super.store, required super.vault}) : super(table: milestonesTable);

  @override
  MilestoneRecord? fromPlain(Map<String, Object?> plain, Row row) => MilestoneRecord(stripInternalFields(plain));

  @override
  int compare(MilestoneRecord a, MilestoneRecord b) => _milestoneSortKey(b) - _milestoneSortKey(a);

  String newMilestoneId() => 'ms-${randomUuidV4()}';

  Future<Row> add({required String title, required String date}) {
    return write({
      'id': newMilestoneId(),
      'title': title,
      'date': date,
      'updatedAt': stamp(),
      'deleted': false,
    });
  }

  Future<Row> update(MilestoneRecord milestone, {required String title, required String date}) {
    return write({
      ...milestone.toFields(),
      'title': title,
      'date': date,
      'updatedAt': stamp(),
    });
  }
}
