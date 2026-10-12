import 'dart:async';
import 'dart:convert';

import 'package:our_space_mobile/core/engine/crypto/aes_gcm.dart';
import 'package:our_space_mobile/core/engine/crypto/base64.dart';
import 'package:our_space_mobile/core/engine/p2p/peer_endpoint.dart';
import 'package:our_space_mobile/core/engine/p2p/peer_records.dart';
import 'package:our_space_mobile/core/engine/p2p/peer_status.dart';
import 'package:our_space_mobile/core/engine/p2p/peer_sync_engine.dart';
import 'package:our_space_mobile/core/engine/storage/tables.dart';
import 'package:our_space_mobile/core/engine/storage/vault_store.dart';

import '../../support/harness.dart';
import 'fake_clock.dart';

Future<void> settle([int rounds = 30]) async {
  for (var i = 0; i < rounds; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> waitFor(bool Function() done, {String reason = 'condition', Duration timeout = const Duration(seconds: 20)}) async {
  final deadline = DateTime.now().add(timeout);
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Timed out waiting for $reason');
    }
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

VaultKey keyFromBase64(String value) => VaultKey.fromBits(base64ToBuffer(value));

class EngineSide {
  EngineSide._(this.name, this.peerId, this.key, this.store, this.engine, this.clock);

  static Future<EngineSide> open(
    String name,
    String peerId,
    VaultKey key, {
    required PeerEndpointFactory endpoints,
    required FakePeerClock clock,
    String Function(int bytes)? nonce,
    Map<String, String> settings = const {},
  }) async {
    final store = await openTestStore(now: clock.now);
    for (final entry in settings.entries) {
      await store.settings.setItem(entry.key, entry.value);
    }
    final engine = PeerSyncEngine(
      records: VaultStorePeerRecords(store),
      settings: store.settings,
      endpointFactory: endpoints,
      clock: clock,
      nonce: nonce ?? (bytes) => generateSecureNonce(bytes),
      observeRemote: (stamp) {
        final at = stamp.floor();
        if (at > store.clock.observedRemoteMax) store.clock.observedRemoteMax = at;
      },
    );
    final side = EngineSide._(name, peerId, key, store, engine, clock);
    engine.addStatusListener(side.statuses.add);
    engine.addDataListener(side.updates.add);
    engine.addConfigListener(side.configs.add);
    return side;
  }

  final String name;
  final String peerId;
  final VaultKey key;
  final VaultStore store;
  final PeerSyncEngine engine;
  final FakePeerClock clock;
  final List<PeerStatus> statuses = [];
  final List<PeerDataUpdate> updates = [];
  final List<PeerConfigUpdate> configs = [];

  Future<String> init() => engine.init(key, peerId);

  Iterable<String> get codes => statuses.map((s) => s.code ?? '');

  bool saw(String code) => statuses.any((s) => s.code == code);

  PeerStatus? last(String code) {
    for (final status in statuses.reversed) {
      if (status.code == code) return status;
    }
    return null;
  }

  Future<void> seed(Map<String, Object?> tables) async {
    for (final entry in tables.entries) {
      for (final raw in entry.value as List) {
        final row = rowFromFixture((raw as Map).cast<String, Object?>());
        await store.putRow(entry.key, row);
      }
    }
  }

  Future<Map<String, Object?>> dump() async {
    final out = <String, Object?>{};
    for (final table in syncedTables) {
      final rows = await store.allRows(table);
      out[table] = [
        for (final row in rows)
          {
            for (final entry in rowToFixture(row).entries)
              if (!entry.key.startsWith('_') && entry.value != null) entry.key: entry.value,
          },
      ];
    }
    return out;
  }

  Future<void> close() async {
    engine.destroy();
    await store.close();
  }
}

String canonicalJson(Object? value) {
  Object? sort(Object? v) {
    if (v is Map) {
      final keys = v.keys.map((k) => k.toString()).toList()..sort();
      return {for (final k in keys) k: sort(v[k])};
    }
    if (v is List) return v.map(sort).toList();
    if (v is double && v == v.truncateToDouble()) return v.toInt();
    return v;
  }

  return jsonEncode(sort(value));
}
