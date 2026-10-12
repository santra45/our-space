import 'plain_record.dart';

class BucketListRecord extends PlainRecord {
  BucketListRecord(super.fields);

  static const String defaultCategory = 'Romance';

  String get text => readString(fields['text']) ?? '';

  String get category => readString(fields['category']) ?? defaultCategory;

  bool get completed => fields['completed'] == true;

  int? get completedAt => readInt(fields['completedAt']);

  int get createdAt => readInt(fields['createdAt']) ?? 0;
}
