import '../storage/vault_store.dart';

abstract class PeerRecordSource {
  Future<Map<String, List<Map<String, Object?>>>> getManifest();

  Future<Map<String, Object?>?> getRow(String table, String id);

  Future<IncomingCommit> commit(List<IncomingRow> staged);
}

class VaultStorePeerRecords implements PeerRecordSource {
  const VaultStorePeerRecords(this.store);

  final VaultStore store;

  @override
  Future<Map<String, List<Map<String, Object?>>>> getManifest() => store.getManifest();

  @override
  Future<Map<String, Object?>?> getRow(String table, String id) => store.getRow(table, id);

  @override
  Future<IncomingCommit> commit(List<IncomingRow> staged) => store.commitIncomingRows(staged);
}

bool isStorageFullError(Object error) {
  final text = error.toString().toLowerCase();
  return text.contains('sqlite_full') ||
      text.contains('disk is full') ||
      text.contains('no space left') ||
      text.contains('quotaexceedederror') ||
      text.contains('notenoughspaceerror');
}
