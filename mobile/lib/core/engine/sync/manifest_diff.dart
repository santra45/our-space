import '../crypto/js_compat.dart';
import '../storage/tables.dart';
import '../storage/vault_store.dart';

const int maxRequestsPerSession = 5000;

const String clockSkewWarning =
    "Your partner's device clock looks far ahead of yours, so some of their items were not accepted. Check the date and time settings on both phones.";

class WantedRecord {
  const WantedRecord(this.table, this.id);
  final String table;
  final String id;

  Map<String, Object?> toJson() => {'table': table, 'id': id};
}

class ManifestDiff {
  const ManifestDiff(this.wanted, this.sawFutureTimestamp);
  final List<WantedRecord> wanted;
  final bool sawFutureTimestamp;
}

Future<ManifestDiff> diffAgainstLocal(Object? remoteManifest, VaultStore store) async {
  final remote = remoteManifest is Map ? asStringMap(remoteManifest) : null;
  if (remote == null) return const ManifestDiff([], false);

  final localManifest = await store.getManifest();
  final requests = <WantedRecord>[];
  final now = store.now();
  var sawFutureTimestamp = false;

  for (final entry in remote.entries) {
    final table = entry.key;
    final remoteItems = entry.value;
    if (!syncedTables.contains(table) || remoteItems is! List) continue;
    if (remoteItems.length > maxRecordsPerTable) continue;

    final localMap = <String, (num, bool)>{};
    for (final item in localManifest[table] ?? const <Map<String, Object?>>[]) {
      localMap[item['id'] as String] = (item['updatedAt'] as num, item['deleted'] == true);
    }

    for (final raw in remoteItems) {
      final item = raw is Map ? asStringMap(raw) : null;
      if (item == null) continue;
      final id = item['id'];
      if (id is! String || id.length > 128) continue;
      final updatedAt = item['updatedAt'];
      if (!isFiniteNumber(updatedAt) || (updatedAt as num) < 0) continue;
      if (updatedAt > now + maxClockSkewMs) {
        sawFutureTimestamp = true;
        continue;
      }

      final local = localMap[id];
      final wantsRemote = local == null ||
          updatedAt > local.$1 ||
          (updatedAt == local.$1 && item['deleted'] == true && !local.$2);

      if (wantsRemote) {
        requests.add(WantedRecord(table, id));
        if (requests.length >= maxRequestsPerSession) break;
      }
    }
    if (requests.length >= maxRequestsPerSession) break;
  }

  return ManifestDiff(requests, sawFutureTimestamp);
}
