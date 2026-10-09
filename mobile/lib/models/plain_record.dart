abstract class PlainRecord {
  PlainRecord(Map<String, Object?> fields) : fields = Map<String, Object?>.unmodifiable(fields);

  final Map<String, Object?> fields;

  String get id => fields['id'] as String;

  int get updatedAt => readInt(fields['updatedAt']) ?? 0;

  bool get deleted => fields['deleted'] == true;

  Map<String, Object?> toFields() => Map<String, Object?>.from(fields);
}

int? readInt(Object? value) {
  if (value is int) return value;
  if (value is double && value.isFinite) return value.floor();
  return null;
}

String? readString(Object? value) => value is String ? value : null;
