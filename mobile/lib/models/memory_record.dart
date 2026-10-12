import 'plain_record.dart';

class MemoryRecord extends PlainRecord {
  MemoryRecord(super.fields, {required this.hasPhoto});

  static const String legacyImageMime = 'image/webp';

  final bool hasPhoto;

  String? get date => readString(fields['date']);

  String get caption => readString(fields['caption']) ?? '';

  String? get mime => readString(fields['mime']);

  String get mimeOrDefault => (mime == null || mime!.isEmpty) ? legacyImageMime : mime!;

  int get rotationDegrees {
    var hash = 0;
    for (final unit in id.codeUnits) {
      hash += unit;
    }
    return (hash % 5) - 2;
  }
}
