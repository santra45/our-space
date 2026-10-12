import 'plain_record.dart';

class MilestoneRecord extends PlainRecord {
  MilestoneRecord(super.fields);

  String get title => readString(fields['title']) ?? '';

  String? get date => readString(fields['date']);
}
