import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:our_space_mobile/core/engine/crypto/base64.dart';
import 'package:our_space_mobile/core/engine/crypto/js_compat.dart';
import 'package:our_space_mobile/core/engine/storage/vault_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

bool _ffiReady = false;

DatabaseFactory testDatabaseFactory() {
  if (!_ffiReady) {
    sqfliteFfiInit();
    _ffiReady = true;
  }
  return databaseFactoryFfiNoIsolate;
}

int _storeCounter = 0;

Future<VaultStore> openTestStore({NowFn now = systemNow}) async {
  final dir = Directory.systemTemp.createTempSync('our_space_test_');
  _storeCounter++;
  return VaultStore.open(
    factory: testDatabaseFactory(),
    path: '${dir.path}${Platform.pathSeparator}vault_$_storeCounter.sqlite',
    now: now,
  );
}

Map<String, Object?> readFixture(String name) {
  final file = File('test/fixtures/$name');
  if (!file.existsSync()) {
    throw StateError('Missing test/fixtures/$name. Run "node tool/interop.mjs" from the mobile folder first.');
  }
  return asStringMap(jsonDecode(file.readAsStringSync()))!;
}

Object? fromFixtureValue(Object? value) {
  if (value is Map) {
    if (value.length == 1 && value.containsKey(r'$bytes')) {
      return base64ToBuffer(value[r'$bytes'] as String);
    }
    final out = <String, Object?>{};
    value.forEach((key, entry) => out[key.toString()] = fromFixtureValue(entry));
    return out;
  }
  if (value is List) return value.map(fromFixtureValue).toList();
  return value;
}

Object? toFixtureValue(Object? value) {
  if (value is Uint8List) return {r'$bytes': bufferToBase64(value)};
  if (value is Map) {
    final out = <String, Object?>{};
    value.forEach((key, entry) => out[key.toString()] = toFixtureValue(entry));
    return out;
  }
  if (value is List) return value.map(toFixtureValue).toList();
  return value;
}

Map<String, Object?> rowFromFixture(Map<String, Object?> wire) {
  final row = Map<String, Object?>.from(fromFixtureValue(wire) as Map);
  final blob = row.remove('imageBlobBase64');
  if (blob is String) row['imageBlob'] = base64ToBuffer(blob);
  return row;
}

Map<String, Object?> rowToFixture(Map<String, Object?> row) {
  final out = <String, Object?>{};
  row.forEach((key, value) {
    if (key == 'imageBlob' && value is Uint8List) {
      out['imageBlobBase64'] = bufferToBase64(value);
      return;
    }
    out[key] = toFixtureValue(value);
  });
  return out;
}

void writeBuildJson(String name, Object? data) {
  final dir = Directory('build/interop');
  dir.createSync(recursive: true);
  File('${dir.path}/$name').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(data));
}
