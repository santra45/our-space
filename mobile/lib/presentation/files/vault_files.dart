import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../../core/engine.dart';

class PickedVaultFile {
  const PickedVaultFile({required this.name, required this.size, required this.bytes});

  final String name;
  final int size;
  final Uint8List? bytes;

  bool get tooBig => size > maxBackupFileBytes;

  String? readText() {
    final data = bytes;
    if (data == null) return null;
    try {
      return utf8.decode(data);
    } catch (_) {
      return null;
    }
  }
}

typedef VaultFilePicker = Future<PickedVaultFile?> Function();
typedef VaultFileSaver = Future<bool> Function(BackupFile file);

abstract final class VaultFiles {
  static VaultFilePicker picker = _pickWithSystem;
  static VaultFileSaver saver = _saveWithSystem;

  static Future<PickedVaultFile?> pick() => picker();

  static Future<bool> save(BackupFile file) => saver(file);

  static Future<PickedVaultFile?> _pickWithSystem() async {
    final result = await FilePicker.pickFiles(type: FileType.any, withData: true);
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.first;
    return PickedVaultFile(name: file.name, size: file.size, bytes: file.bytes);
  }

  static Future<bool> _saveWithSystem(BackupFile file) async {
    final saved = await FilePicker.saveFile(
      fileName: file.fileName,
      bytes: Uint8List.fromList(utf8.encode(file.contents)),
    );
    return saved != null;
  }
}
