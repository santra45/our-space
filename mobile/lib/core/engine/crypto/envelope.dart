import 'dart:convert';
import 'dart:typed_data';

import 'aes_gcm.dart';
import 'base64.dart';
import 'js_compat.dart';
import 'pbkdf2.dart';

const int recordSchemaVersion = 2;

const List<String> plaintextRecordFields = ['id', 'updatedAt', 'deleted'];

const Set<String> internalRecordFields = {
  'v',
  'ciphertext',
  'iv',
  '_del',
  '_schemaVersion',
  '_headerTampered',
  '_binaryTampered',
  '_binaryUnverified',
  '_tableTampered',
  '_tableUnverified',
  '_bin',
  '_tbl',
};

const String binaryDigestField = '_bin';
const String tableBindingField = '_tbl';

class RecordError implements Exception {
  RecordError(this.message);
  final String message;
  @override
  String toString() => message;
}

class SealedText {
  const SealedText({required this.ciphertext, required this.iv});
  final String ciphertext;
  final String iv;

  Map<String, Object?> toJson() => {'ciphertext': ciphertext, 'iv': iv};
}

List<int>? _aadBytes(Object? additionalData) {
  if (additionalData == null) return null;
  if (additionalData is String) return utf8Bytes(additionalData);
  if (additionalData is List<int>) return additionalData;
  throw ArgumentError('additionalData must be a String or bytes');
}

SealedText encryptText(String plainText, VaultKey key, [Object? additionalData]) {
  final iv = randomBytes(ivLengthBytes);
  final sealed = aesGcmSeal(key, iv, utf8Bytes(plainText), aad: _aadBytes(additionalData));
  return SealedText(ciphertext: bufferToBase64(sealed), iv: bufferToBase64(iv));
}

String decryptText(String ciphertextBase64, String ivBase64, VaultKey key, [Object? additionalData]) {
  final iv = base64ToBuffer(ivBase64);
  final sealed = base64ToBuffer(ciphertextBase64);
  final clear = aesGcmOpen(key, iv, sealed, aad: _aadBytes(additionalData));
  return utf8.decode(clear, allowMalformed: true);
}

SealedText encryptJson(Object? data, VaultKey key) => encryptText(jsonStringify(data), key);

Object? decryptJson(String ciphertextBase64, String ivBase64, VaultKey key) =>
    jsonParse(decryptText(ciphertextBase64, ivBase64, key));

String digestBinaryValue(Object value) => bufferToBase64(sha256Bytes(binaryBytes(value)));

class _BinaryCheck {
  const _BinaryCheck(this.tampered, this.unverified);
  final bool tampered;
  final bool unverified;
}

_BinaryCheck _verifyBinaryDigests(Map<String, Object?> record, Object? digestMap) {
  final attached = <String>[];
  record.forEach((field, value) {
    if (isBinaryValue(value)) attached.add(field);
  });

  final map = digestMap is Map ? digestMap : null;
  if (map == null) {
    return _BinaryCheck(false, attached.isNotEmpty);
  }

  for (final field in attached) {
    final expected = map[field];
    if (expected is! String || expected.isEmpty) return const _BinaryCheck(true, false);
    if (digestBinaryValue(record[field]!) != expected) return const _BinaryCheck(true, false);
  }
  for (final field in map.keys) {
    if (!attached.contains(field)) return const _BinaryCheck(true, false);
  }
  return const _BinaryCheck(false, false);
}

Map<String, Object?> encryptRecord(
  Map<String, Object?> plainFields,
  VaultKey key, {
  String? table,
  NowFn now = systemNow,
}) {
  final id = plainFields['id'];
  if (id is! String || id.isEmpty) {
    throw RecordError('encryptRecord: a string `id` is required');
  }

  final updatedAtValue = plainFields['updatedAt'];
  final num updatedAt = isFiniteNumber(updatedAtValue) ? updatedAtValue as num : now();
  final deleted = plainFields['deleted'] == true;

  final binary = <String, Object>{};
  final payload = <String, Object?>{};

  plainFields.forEach((field, value) {
    if (internalRecordFields.contains(field)) return;
    if (isBinaryValue(value)) {
      binary[field] = value!;
      return;
    }
    payload[field] = value;
  });

  payload['id'] = id;
  payload['updatedAt'] = updatedAt;
  payload['deleted'] = deleted;

  final digests = <String, Object?>{};
  binary.forEach((field, value) {
    digests[field] = digestBinaryValue(value);
  });
  payload[binaryDigestField] = digests;

  if (table != null && table.isNotEmpty) {
    payload[tableBindingField] = table;
  }

  final sealed = encryptJson(payload, key);

  final row = <String, Object?>{
    'id': id,
    'updatedAt': updatedAt,
    'deleted': deleted,
    'v': recordSchemaVersion,
    'ciphertext': sealed.ciphertext,
    'iv': sealed.iv,
  };
  binary.forEach((field, value) {
    row[field] = binaryBytes(value);
  });
  return row;
}

bool recordHasAuthenticatedHeader(Map<String, Object?>? record) {
  if (record == null) return false;
  final ciphertext = record['ciphertext'];
  final iv = record['iv'];
  return record['v'] == recordSchemaVersion &&
      ciphertext is String &&
      ciphertext.isNotEmpty &&
      iv is String &&
      iv.isNotEmpty;
}

Map<String, Object?> decryptRecord(Map<String, Object?> record, VaultKey key, {String? table}) {
  final ciphertext = record['ciphertext'];
  final iv = record['iv'];
  final isEnvelope = record['v'] == recordSchemaVersion && ciphertext is String && iv is String;
  if (!isEnvelope) {
    throw RecordError('decryptRecord: not a sealed record');
  }

  final decoded = decryptJson(ciphertext, iv, key);
  final payload = asStringMap(decoded);
  if (payload == null) {
    throw RecordError('decryptRecord: envelope payload is not an object');
  }

  final out = <String, Object?>{};
  payload.forEach((field, value) {
    if (internalRecordFields.contains(field)) return;
    out[field] = value;
  });
  record.forEach((field, value) {
    if (isBinaryValue(value)) out[field] = binaryBytes(value!);
  });

  final innerUpdatedAt = finiteOrNull(payload['updatedAt']);
  final innerDeletedValue = payload['deleted'];
  final bool? innerDeleted = innerDeletedValue is bool ? innerDeletedValue : null;

  final payloadId = payload['id'];
  out['id'] = payloadId is String ? payloadId : record['id'];
  out['updatedAt'] = innerUpdatedAt ?? record['updatedAt'];
  out['deleted'] = innerDeleted ?? (record['deleted'] == true);

  final binaryCheck = _verifyBinaryDigests(record, payload[binaryDigestField]);

  final sealedTableValue = payload[tableBindingField];
  final String? sealedTable =
      sealedTableValue is String && sealedTableValue.isNotEmpty ? sealedTableValue : null;
  final String? expectedTable = table != null && table.isNotEmpty ? table : null;

  final tableTampered = expectedTable != null && sealedTable != null && sealedTable != expectedTable;
  final recordUpdatedAt = record['updatedAt'];

  out['_schemaVersion'] = recordSchemaVersion;
  out['_binaryTampered'] = binaryCheck.tampered;
  out['_binaryUnverified'] = binaryCheck.unverified;
  out['_tableUnverified'] = sealedTable == null;
  out['_tableTampered'] = tableTampered;
  out['_headerTampered'] = (payloadId is String && payloadId != record['id']) ||
      (innerUpdatedAt != null && !(recordUpdatedAt is num && recordUpdatedAt == innerUpdatedAt)) ||
      (innerDeleted != null && innerDeleted != (record['deleted'] == true)) ||
      binaryCheck.tampered ||
      tableTampered;

  return out;
}

Map<String, Object?> stripInternalFields(Map<String, Object?> record) {
  final out = <String, Object?>{};
  record.forEach((field, value) {
    if (field.startsWith('_')) return;
    out[field] = value;
  });
  return out;
}

bool isTamperedRecord(Map<String, Object?>? record) =>
    record == null ||
    record['_headerTampered'] == true ||
    record['_binaryTampered'] == true ||
    record['_tableTampered'] == true;

Uint8List encryptBlob(List<int> plainBytes, VaultKey key) {
  final iv = randomBytes(ivLengthBytes);
  final sealed = aesGcmSeal(key, iv, plainBytes);
  final packed = Uint8List(ivLengthBytes + sealed.length);
  packed.setRange(0, ivLengthBytes, iv);
  packed.setRange(ivLengthBytes, packed.length, sealed);
  return packed;
}

Uint8List decryptBlob(List<int> packedData, VaultKey key) {
  if (packedData.length < ivLengthBytes + gcmTagLengthBytes) {
    throw CryptoFailure('Invalid encrypted blob: buffer too small');
  }
  final iv = packedData.sublist(0, ivLengthBytes);
  final sealed = packedData.sublist(ivLengthBytes);
  return aesGcmOpen(key, iv, sealed);
}
