import 'plain_record.dart';

class LetterRecord extends PlainRecord {
  LetterRecord(super.fields, {required this.lockDate, required this.lockBoundary});

  final String? lockDate;

  final int? lockBoundary;

  bool isLockedAt(int now) => lockDate != null && lockBoundary != null && now < lockBoundary!;

  bool get isLocked => isLockedAt(DateTime.now().millisecondsSinceEpoch);

  String get title => readString(fields['title']) ?? '';

  String? get unlockDate => readString(fields['unlockDate']);

  bool get isOpened => fields['isOpened'] == true;

  int? get openedAt => readInt(fields['openedAt']);

  int? get createdAt => readInt(fields['createdAt']);

  String? get content => readString(fields['content']);

  Map<String, Object?>? get sealedContent {
    final value = fields['sealedContent'];
    if (value is Map) {
      return value.map((key, entry) => MapEntry(key.toString(), entry));
    }
    return null;
  }

  bool get isSealed {
    final value = fields['sealedContent'];
    return value != null && value != false && value != '' && value != 0;
  }

  int get writtenAt => createdAt ?? updatedAt;
}
