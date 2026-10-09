import 'dart:isolate';
import 'dart:typed_data';

import '../../../models/memory_record.dart';
import '../crypto/aes_gcm.dart';
import '../crypto/base64.dart';
import '../crypto/envelope.dart';
import '../crypto/js_compat.dart';
import '../domain/date_helpers.dart';
import '../domain/limits.dart';
import '../storage/tables.dart';
import '../storage/vault_store.dart';
import 'table_repository.dart';

class PhotoTooLargeError implements Exception {
  PhotoTooLargeError(this.bytes);
  final int bytes;

  static int get limitMb => (maxImageBlobBytes / (1024 * 1024)).round();

  String get message {
    final mb = (bytes / (1024 * 1024)).toStringAsFixed(1);
    return 'Could not save this memory: the compressed photo is still ${mb}MB, over the ${limitMb}MB limit, so it would never reach your partner. Try a smaller image.';
  }

  @override
  String toString() => message;
}

class PhotoUnreadableError implements Exception {
  String get message => 'This photo could not be unlocked.';
  @override
  String toString() => message;
}

const String defaultMemoryCaption = 'Precious moment 💕';

int _dateSortKey(MemoryRecord record) {
  final date = record.date;
  if (date == null || date.isEmpty) return 0;
  return parseLocalDate(date)?.millisecondsSinceEpoch ?? 0;
}

Uint8List _openPhoto((Row, VaultKey) input) {
  final (row, key) = input;
  final plain = decryptRecord(row, key, table: memoriesTable);
  if (plain['_binaryTampered'] == true || plain['_headerTampered'] == true) {
    throw PhotoUnreadableError();
  }
  final blob = row['imageBlob'];
  if (blob == null) throw PhotoUnreadableError();
  return decryptBlob(binaryBytes(blob), key);
}

Uint8List _sealPhoto((List<int>, VaultKey) input) => encryptBlob(input.$1, input.$2);

class MemoriesRepository extends TableRepository<MemoryRecord> {
  MemoriesRepository({required super.store, required super.vault}) : super(table: memoriesTable);

  @override
  bool get readsBlobsLazily => true;

  @override
  MemoryRecord? fromPlain(Map<String, Object?> plain, Row row) {
    final fields = stripInternalFields(plain)..remove('imageBlob');
    return MemoryRecord(fields, hasPhoto: row['imageBlob'] != null);
  }

  @override
  int compare(MemoryRecord a, MemoryRecord b) {
    final byDate = _dateSortKey(b) - _dateSortKey(a);
    if (byDate != 0) return byDate;
    return b.updatedAt - a.updatedAt;
  }

  String newMemoryId() => 'mem-${store.now().toRadixString(36)}-${generateUrlSafeNonce(6)}';

  Future<Row> add({
    required List<int> photo,
    required String mime,
    required String date,
    String caption = '',
  }) async {
    final key = requireKey();
    final imageBlob = photo.length > 256 * 1024
        ? await Isolate.run(() => _sealPhoto((photo, key)))
        : _sealPhoto((photo, key));
    if (imageBlob.length > maxImageBlobBytes) {
      throw PhotoTooLargeError(imageBlob.length);
    }
    final trimmed = jsTrim(caption);
    return store.putEncrypted(
      memoriesTable,
      {
        'id': newMemoryId(),
        'date': date,
        'caption': trimmed.isNotEmpty ? trimmed : defaultMemoryCaption,
        'mime': mime,
        'imageBlob': imageBlob,
        'updatedAt': stamp(),
        'deleted': false,
      },
      key,
    );
  }

  Future<Uint8List?> loadPhoto(String id) async {
    final key = requireKey();
    final row = await store.getRow(memoriesTable, id);
    if (row == null || row['deleted'] == true) return null;
    final blob = row['imageBlob'];
    if (blob == null) return null;
    try {
      if (binaryBytes(blob).length > 256 * 1024) {
        return await Isolate.run(() => _openPhoto((row, key)));
      }
      return _openPhoto((row, key));
    } catch (_) {
      throw PhotoUnreadableError();
    }
  }
}
