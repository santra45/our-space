import 'dart:typed_data';
import 'crypto_engine.dart';
import '../constants/app_constants.dart';

const String binaryDigestField = '_bin';
const String tableBindingField = '_tbl';

const Set<String> _internalRecordFields = {
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

class DecryptedRecordResult {
  final Map<String, dynamic> data;
  final bool isHeaderTampered;
  final bool isBinaryTampered;
  final bool isBinaryUnverified;
  final bool isTableTampered;
  final bool isTableUnverified;

  DecryptedRecordResult({
    required this.data,
    required this.isHeaderTampered,
    required this.isBinaryTampered,
    required this.isBinaryUnverified,
    required this.isTableTampered,
    required this.isTableUnverified,
  });

  String get id => data['id'] as String;
  int get updatedAt => (data['updatedAt'] as num?)?.toInt() ?? 0;
  bool get deleted => data['deleted'] == true;
}

class RecordEnvelope {
  RecordEnvelope._();

  static Future<Map<String, dynamic>> encryptRecord(
    Map<String, dynamic> plainFields,
    Uint8List keyBytes, {
    String? table,
    Uint8List? imageBytes,
  }) async {
    final String id = plainFields['id'] as String;
    final int updatedAt = (plainFields['updatedAt'] as num?)?.toInt() ??
        DateTime.now().millisecondsSinceEpoch;
    final bool deleted = plainFields['deleted'] == true;

    final Map<String, dynamic> payload = {};
    for (final entry in plainFields.entries) {
      if (_internalRecordFields.contains(entry.key)) continue;
      payload[entry.key] = entry.value;
    }

    payload['id'] = id;
    payload['updatedAt'] = updatedAt;
    payload['deleted'] = deleted;

    final Map<String, String> digests = {};
    if (imageBytes != null && imageBytes.isNotEmpty) {
      digests['imageBlob'] = CryptoEngine.instance.digestBytes(imageBytes);
    }
    payload[binaryDigestField] = digests;

    if (table != null && table.isNotEmpty) {
      payload[tableBindingField] = table;
    }

    final encrypted = await CryptoEngine.instance.encryptJSON(payload, keyBytes);

    return {
      'id': id,
      'updatedAt': updatedAt,
      'deleted': deleted ? 1 : 0,
      'v': recordSchemaVersion,
      'ciphertext': encrypted['ciphertext']!,
      'iv': encrypted['iv']!,
      '_bin': digests.isNotEmpty ? CryptoEngine.instance.digestBytes(imageBytes!) : null,
      '_tbl': table,
    };
  }

  static Future<DecryptedRecordResult> decryptRecord(
    Map<String, dynamic> record,
    Uint8List keyBytes, {
    String? table,
    Uint8List? imageBytes,
  }) async {
    final v = record['v'] as int?;
    final ciphertext = record['ciphertext'] as String?;
    final iv = record['iv'] as String?;

    if (v != recordSchemaVersion || ciphertext == null || iv == null) {
      throw ArgumentError('decryptRecord: not a valid schema v2 sealed record.');
    }

    final payload = await CryptoEngine.instance.decryptJSON(ciphertext, iv, keyBytes);

    final String outerId = record['id'] as String;
    final int outerUpdatedAt = (record['updatedAt'] as num?)?.toInt() ?? 0;
    final bool outerDeleted = record['deleted'] == 1 || record['deleted'] == true;

    final String? innerId = payload['id'] as String?;
    final int? innerUpdatedAt = (payload['updatedAt'] as num?)?.toInt();
    final bool? innerDeleted = payload['deleted'] as bool?;

    bool binaryTampered = false;
    bool binaryUnverified = false;

    final rawDigestMap = payload[binaryDigestField];
    if (rawDigestMap is Map) {
      final expectedDigest = rawDigestMap['imageBlob'] as String?;
      if (imageBytes != null && imageBytes.isNotEmpty) {
        if (expectedDigest == null || expectedDigest.isEmpty) {
          binaryTampered = true;
        } else {
          final actualDigest = CryptoEngine.instance.digestBytes(imageBytes);
          if (actualDigest != expectedDigest) {
            binaryTampered = true;
          }
        }
      } else if (expectedDigest != null && expectedDigest.isNotEmpty) {
        binaryTampered = true;
      }
    } else {
      if (imageBytes != null && imageBytes.isNotEmpty) {
        binaryUnverified = true;
      }
    }

    final String? sealedTable = payload[tableBindingField] as String?;
    final bool tableUnverified = sealedTable == null || sealedTable.isEmpty;
    final bool tableTampered =
        table != null && sealedTable != null && sealedTable != table;

    final bool headerTampered = (innerId != null && innerId != outerId) ||
        (innerUpdatedAt != null && innerUpdatedAt != outerUpdatedAt) ||
        (innerDeleted != null && innerDeleted != outerDeleted) ||
        binaryTampered ||
        tableTampered;

    final Map<String, dynamic> out = {};
    for (final entry in payload.entries) {
      if (_internalRecordFields.contains(entry.key)) continue;
      out[entry.key] = entry.value;
    }

    out['id'] = innerId ?? outerId;
    out['updatedAt'] = innerUpdatedAt ?? outerUpdatedAt;
    out['deleted'] = innerDeleted ?? outerDeleted;

    return DecryptedRecordResult(
      data: out,
      isHeaderTampered: headerTampered,
      isBinaryTampered: binaryTampered,
      isBinaryUnverified: binaryUnverified,
      isTableTampered: tableTampered,
      isTableUnverified: tableUnverified,
    );
  }
}
