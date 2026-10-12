import 'dart:convert';

import '../../../models/love_burst_record.dart';
import '../crypto/aes_gcm.dart';
import '../crypto/js_compat.dart';
import '../identity/device_id.dart';
import '../storage/local_settings.dart';
import '../storage/tables.dart';
import '../storage/vault_store.dart';

const String loveBurstTable = loveBurstsTable;
const String burstSeenStorageKey = 'sweetheart_burst_seen_v1';
const int manyBursts = 99;

String describeBursts(int total, bool wasConnected, [String? name]) {
  if (total <= 0) return '';
  final trimmed = name == null ? '' : jsTrim(name);
  final who = trimmed.isNotEmpty ? trimmed : 'Your partner';
  final many = total > manyBursts ? '$manyBursts+' : '$total';
  final what = total == 1 ? 'a love burst' : '$many love bursts';
  return wasConnected ? '$who sent you $what! 💕' : '$who sent you $what while you were away 💕';
}

class LoveBurstService {
  LoveBurstService({required this.store, required this.settings, required this.device});

  final VaultStore store;
  final LocalSettings settings;
  final DeviceIdentity device;

  String get burstOwnerId => device.deviceId;

  String get ownBurstRecordId => 'burst-$burstOwnerId';

  Map<String, Object?>? _readSeenCounts() {
    try {
      final raw = settings.getItem(burstSeenStorageKey);
      if (raw == null || raw.isEmpty) return null;
      final parsed = jsonDecode(raw);
      if (parsed is! Map) return null;
      final counts = parsed['counts'];
      if (counts is! Map) return null;
      return asStringMap(counts);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeSeenCounts(Map<String, Object?> counts) =>
      settings.setItem(burstSeenStorageKey, jsonStringify({'counts': counts}));

  Future<void> markBurstsSeen(Iterable<BurstCount> records) async {
    final counts = _readSeenCounts() ?? <String, Object?>{};
    for (final record in records) {
      final previous = isFiniteNumber(counts[record.id]) ? counts[record.id] as num : 0;
      counts[record.id] = previous > record.count ? previous : record.count;
    }
    await _writeSeenCounts(counts);
  }

  Future<Map<String, Object?>> sendLoveBurst(VaultKey? key, {Future<int> Function()? timestamp}) async {
    if (key == null) throw StoreError('sendLoveBurst: vault is locked');
    final id = ownBurstRecordId;

    var current = 0;
    try {
      final existing = await store.getDecrypted(loveBurstTable, id, key);
      final count = existing?['count'];
      if (isFiniteNumber(count) && (count as num) > 0) current = count.floor();
    } catch (_) {
      current = 0;
    }

    return store.putEncrypted(
      loveBurstTable,
      {
        'id': id,
        'count': current + 1,
        'lastSentAt': store.now(),
        'updatedAt': timestamp == null ? store.clock.next() : await timestamp(),
      },
      key,
    );
  }

  Future<UnseenBursts> collectUnseenBursts(VaultKey? key) async {
    if (key == null) return UnseenBursts.empty;
    final mine = ownBurstRecordId;

    List<Map<String, Object?>> rows;
    try {
      rows = await store.listDecrypted(loveBurstTable, key);
    } catch (_) {
      return UnseenBursts.empty;
    }

    final theirs = rows.where((row) {
      final id = row['id'];
      final count = row['count'];
      return id is String &&
          id != mine &&
          isFiniteNumber(count) &&
          (count as num) > 0 &&
          row['_headerTampered'] != true &&
          row['_tableTampered'] != true;
    }).toList();

    final seen = _readSeenCounts();
    if (seen == null) {
      await _writeSeenCounts({
        for (final row in theirs) row['id'] as String: (row['count'] as num).floor(),
      });
      return UnseenBursts.empty;
    }

    var total = 0;
    var lastSentAt = 0;
    final records = <BurstCount>[];
    for (final row in theirs) {
      final before = isFiniteNumber(seen[row['id']]) ? seen[row['id']] as num : 0;
      final count = (row['count'] as num).floor();
      final delta = count - before;
      records.add(BurstCount(id: row['id'] as String, count: count));
      if (delta <= 0) continue;
      total += delta.floor();
      final sentAt = row['lastSentAt'];
      if (isFiniteNumber(sentAt) && (sentAt as num) > lastSentAt) {
        lastSentAt = sentAt.floor();
      }
    }
    return UnseenBursts(total: total, lastSentAt: lastSentAt, records: records);
  }
}
