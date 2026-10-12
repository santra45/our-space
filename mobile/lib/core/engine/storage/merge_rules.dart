import '../crypto/envelope.dart';
import '../crypto/js_compat.dart';

String rowFingerprint(Map<String, Object?> row) {
  final v = row['v'];
  final version = (v == null || v == 0 || v == false || v == '') ? recordSchemaVersion : v;
  final ciphertext = row['ciphertext'];
  final iv = row['iv'];
  return [
    _jsString(version),
    (ciphertext is String && ciphertext.isNotEmpty) ? ciphertext : '',
    (iv is String && iv.isNotEmpty) ? iv : '',
  ].join('|');
}

String _jsString(Object? value) {
  if (value is double && value == value.truncateToDouble() && value.abs() < 1e21) {
    return value.toInt().toString();
  }
  return value.toString();
}

int _compareCodeUnits(String a, String b) {
  final length = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < length; i++) {
    final diff = a.codeUnitAt(i) - b.codeUnitAt(i);
    if (diff != 0) return diff;
  }
  return a.length - b.length;
}

bool incomingWins(Map<String, Object?>? existing, Map<String, Object?> incoming) {
  if (existing == null) return true;

  final localUpdatedAt = existing['updatedAt'];
  final num localAt = isFiniteNumber(localUpdatedAt) ? localUpdatedAt as num : -1;
  final remoteValue = incoming['updatedAt'];
  final num remoteAt = remoteValue is num ? remoteValue : double.nan;

  if (remoteAt > localAt) return true;
  if (remoteAt < localAt) return false;

  final localDeleted = existing['deleted'] == true;
  final remoteDeleted = incoming['deleted'] == true;
  if (localDeleted != remoteDeleted) return remoteDeleted;

  return _compareCodeUnits(rowFingerprint(incoming), rowFingerprint(existing)) > 0;
}
