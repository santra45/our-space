import 'dart:convert';
import 'dart:typed_data';

typedef NowFn = int Function();

int systemNow() => DateTime.now().millisecondsSinceEpoch;

bool isFiniteNumber(Object? value) => value is num && value.isFinite;

num? finiteOrNull(Object? value) => isFiniteNumber(value) ? value as num : null;

int? finiteIntOrNull(Object? value) {
  if (value is int) return value;
  if (value is double && value.isFinite) return value.floor();
  return null;
}

num numOrZero(Object? value) {
  if (value is num && !value.isNaN && value != 0) return value;
  return 0;
}

bool isBinaryValue(Object? value) => value is Uint8List || value is ByteBuffer;

Uint8List binaryBytes(Object value) {
  if (value is Uint8List) return value;
  if (value is ByteBuffer) return value.asUint8List();
  throw ArgumentError('not a binary value');
}

const Set<int> _jsWhitespace = {
  0x0009,
  0x000A,
  0x000B,
  0x000C,
  0x000D,
  0x0020,
  0x00A0,
  0x1680,
  0x2000,
  0x2001,
  0x2002,
  0x2003,
  0x2004,
  0x2005,
  0x2006,
  0x2007,
  0x2008,
  0x2009,
  0x200A,
  0x2028,
  0x2029,
  0x202F,
  0x205F,
  0x3000,
  0xFEFF,
};

bool isJsWhitespace(int codeUnit) => _jsWhitespace.contains(codeUnit);

String jsTrim(String value) {
  var start = 0;
  var end = value.length;
  while (start < end && isJsWhitespace(value.codeUnitAt(start))) {
    start++;
  }
  while (end > start && isJsWhitespace(value.codeUnitAt(end - 1))) {
    end--;
  }
  return value.substring(start, end);
}

String jsSlice(String value, int start, [int? end]) {
  final length = value.length;
  var from = start < 0 ? (length + start).clamp(0, length) : start.clamp(0, length);
  var to = end == null ? length : (end < 0 ? (length + end).clamp(0, length) : end.clamp(0, length));
  if (to < from) to = from;
  return value.substring(from, to);
}

Object? jsonSafe(Object? value) {
  if (value is double) return value.isFinite ? value : null;
  if (value is Map) {
    final out = <String, Object?>{};
    value.forEach((key, entry) {
      out[key.toString()] = jsonSafe(entry);
    });
    return out;
  }
  if (value is List) return value.map(jsonSafe).toList();
  return value;
}

String jsonStringify(Object? value) => jsonEncode(jsonSafe(value));

Object? jsonParse(String text) => jsonDecode(text);

Map<String, Object?>? asStringMap(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return value.map((key, entry) => MapEntry(key.toString(), entry));
  }
  return null;
}

Object? deepCopyJson(Object? value) {
  if (value is Map) {
    final out = <String, Object?>{};
    value.forEach((key, entry) {
      out[key.toString()] = deepCopyJson(entry);
    });
    return out;
  }
  if (value is List) return value.map(deepCopyJson).toList();
  if (value is Uint8List) return Uint8List.fromList(value);
  return value;
}

bool jsonDeepEquals(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key)) return false;
      if (!jsonDeepEquals(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!jsonDeepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Uint8List && b is Uint8List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
  if (a is num && b is num) return a == b;
  return a == b;
}

String twoDigits(int value) => value.toString().padLeft(2, '0');

String toJsIsoString(int millisecondsSinceEpoch) {
  final d = DateTime.fromMillisecondsSinceEpoch(millisecondsSinceEpoch, isUtc: true);
  final year = d.year >= 0 && d.year <= 9999
      ? d.year.toString().padLeft(4, '0')
      : (d.year < 0 ? '-' : '+') + d.year.abs().toString().padLeft(6, '0');
  return '$year-${twoDigits(d.month)}-${twoDigits(d.day)}T${twoDigits(d.hour)}:'
      '${twoDigits(d.minute)}:${twoDigits(d.second)}.${d.millisecond.toString().padLeft(3, '0')}Z';
}

String hexOf(List<int> bytes) {
  final buffer = StringBuffer();
  for (final byte in bytes) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

Uint8List utf8Bytes(String value) => Uint8List.fromList(utf8.encode(value));
