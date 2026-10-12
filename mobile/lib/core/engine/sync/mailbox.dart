import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../crypto/aes_gcm.dart';
import '../crypto/base64.dart';
import '../crypto/derived_ids.dart';
import '../crypto/envelope.dart';
import '../crypto/js_compat.dart';
import '../domain/limits.dart';
import '../storage/tables.dart';
import '../storage/vault_store.dart';
import 'manifest_diff.dart';

const List<String> mailboxWireFields = ['id', 'updatedAt', 'deleted', 'v', 'ciphertext', 'iv'];

final List<String> mailboxTextTables = syncedTables.where((name) => name != memoriesTable).toList();

class MailboxConfig {
  const MailboxConfig({required this.url, required this.token, this.origin});

  final String url;
  final String token;
  final String? origin;

  static const String environmentUrl = String.fromEnvironment('VITE_MAILBOX_URL');
  static const String environmentToken = String.fromEnvironment('VITE_MAILBOX_TOKEN');
  static const String environmentOrigin = String.fromEnvironment(
    'VITE_MAILBOX_ORIGIN',
    defaultValue: 'https://sameskytonight.vercel.app',
  );

  static MailboxConfig? fromEnvironment() =>
      resolve(url: environmentUrl, token: environmentToken, origin: environmentOrigin);

  static MailboxConfig? resolve({String? url, String? token, String? origin}) {
    if (url == null || url.isEmpty || token == null || token.isEmpty) return null;
    return MailboxConfig(
      url: url.replaceAll(RegExp(r'/+$'), ''),
      token: token,
      origin: (origin == null || origin.isEmpty) ? null : origin,
    );
  }
}

String recordKey(Object? id) => toUrlSafeBase64(bufferToBase64(utf8Bytes(id.toString())));

Map<String, Object?> toMailboxWire(String table, Map<String, Object?> row) {
  final wire = <String, Object?>{};
  for (final field in mailboxWireFields) {
    if (row.containsKey(field)) wire[field] = row[field];
  }
  final blob = row['imageBlob'];
  if (table == memoriesTable && blob != null && isBinaryValue(blob)) {
    wire['imageBlobBase64'] = bufferToBase64(binaryBytes(blob));
  }
  return wire;
}

bool sameManifest(Object? previous, Map<String, Object?> next) {
  final prev = previous is Map ? asStringMap(previous) : null;
  if (prev == null) return false;
  final tables = <String>{...prev.keys, ...next.keys};
  for (final table in tables) {
    final before = prev[table] is List ? prev[table] as List : const <Object?>[];
    final after = next[table] is List ? next[table] as List : const <Object?>[];
    if (before.length != after.length) return false;
    final versions = <Object?, Object?>{};
    for (final e in before) {
      final entry = e is Map ? e : null;
      if (entry == null) return false;
      versions[entry['id']] = entry['updatedAt'];
    }
    for (final e in after) {
      final entry = e is Map ? e : null;
      if (entry == null) return false;
      if (!versions.containsKey(entry['id']) || versions[entry['id']] != entry['updatedAt']) return false;
    }
  }
  return true;
}

class PublishResult {
  const PublishResult({
    required this.ok,
    this.uploaded = 0,
    this.skipped = 0,
    this.reason,
    this.unchanged = false,
  });

  final bool ok;
  final int uploaded;
  final int skipped;
  final String? reason;
  final bool unchanged;

  Map<String, Object?> toJson() => {
        'ok': ok,
        'uploaded': uploaded,
        'skipped': skipped,
        if (reason != null) 'reason': reason,
        if (unchanged) 'unchanged': true,
      };
}

class CollectResult {
  const CollectResult({
    required this.ok,
    this.applied = 0,
    this.fetched = 0,
    this.reason,
    this.totals,
  });

  final bool ok;
  final int applied;
  final int fetched;
  final String? reason;
  final MergeStats? totals;

  Map<String, Object?> toJson() => {
        'ok': ok,
        'applied': applied,
        'fetched': fetched,
        if (reason != null) 'reason': reason,
        if (totals != null) 'totals': totals!.toJson(),
      };
}

class MailboxSyncResult {
  const MailboxSyncResult({
    required this.collected,
    required this.published,
    required this.applied,
    required this.uploaded,
  });

  final List<CollectResult> collected;
  final PublishResult published;
  final int applied;
  final int uploaded;
}

class Mailbox {
  Mailbox({
    required this.store,
    this.config,
    http.Client? client,
    this.requestTimeout = const Duration(seconds: 60),
  }) : _client = client ?? http.Client();

  final VaultStore store;
  final MailboxConfig? config;
  final http.Client _client;
  final Duration requestTimeout;

  void Function(String code, String message)? onWarning;

  bool get isEnabled => config != null;

  Future<http.Response> _request(MailboxConfig cfg, String method, String path, [String? body]) async {
    final headers = <String, String>{'Authorization': 'Bearer ${cfg.token}'};
    if (body != null) headers['Content-Type'] = 'application/octet-stream';
    final origin = cfg.origin;
    if (origin != null) headers['Origin'] = origin;
    final request = http.Request(method, Uri.parse('${cfg.url}$path'));
    request.headers.addAll(headers);
    if (body != null) request.bodyBytes = utf8.encode(body);
    final streamed = await _client.send(request).timeout(requestTimeout);
    return http.Response.fromStream(streamed).timeout(requestTimeout);
  }

  bool _ok(http.Response response) => response.statusCode >= 200 && response.statusCode < 300;

  Future<Map<String, Object?>?> _readManifest(MailboxConfig cfg, String base, VaultKey key) async {
    http.Response response;
    try {
      response = await _request(cfg, 'GET', '$base/manifest');
    } catch (_) {
      return null;
    }
    if (!_ok(response)) return null;
    try {
      final sealed = asStringMap(jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true)));
      final ciphertext = sealed?['ciphertext'];
      final iv = sealed?['iv'];
      if (ciphertext is! String || iv is! String) return null;
      final manifest = decryptJson(ciphertext, iv, key);
      if (manifest is! Map) return null;
      return asStringMap(manifest);
    } catch (_) {
      return null;
    }
  }

  Future<PublishResult> publish({
    required VaultKey? key,
    required String? ownerId,
    bool includePhotos = true,
  }) async {
    final cfg = config;
    if (cfg == null) return const PublishResult(ok: false, reason: 'disabled');
    if (key == null) return const PublishResult(ok: false, reason: 'locked');
    if (ownerId == null || ownerId.isEmpty) return const PublishResult(ok: false, reason: 'no-owner');

    final mailboxId = deriveMailboxId(key);
    final base = '/m/$mailboxId/$ownerId';

    final published = await _readManifest(cfg, base, key);
    final local = await store.getManifest();
    final confirmed = <String, Object?>{};
    var uploaded = 0;
    var skipped = 0;

    final tables = includePhotos ? [...mailboxTextTables, memoriesTable] : mailboxTextTables;

    for (final table in tables) {
      final entries = local[table] ?? const <Map<String, Object?>>[];
      final already = <Object?, Object?>{};
      final publishedEntries = published?[table];
      if (publishedEntries is List) {
        for (final e in publishedEntries) {
          if (e is Map) already[e['id']] = e['updatedAt'];
        }
      }
      final confirmedEntries = <Map<String, Object?>>[];
      confirmed[table] = confirmedEntries;

      for (final entry in entries) {
        if (already.containsKey(entry['id']) && already[entry['id']] == entry['updatedAt']) {
          confirmedEntries.add(entry);
          continue;
        }

        final row = await store.getRow(table, entry['id'] as String);
        if (row == null) continue;

        String body;
        try {
          body = jsonStringify(toMailboxWire(table, row));
        } catch (_) {
          skipped++;
          continue;
        }

        if (body.length > maxMailboxObjectBytes) {
          skipped++;
          continue;
        }

        try {
          final response = await _request(cfg, 'PUT', '$base/rec/$table/${recordKey(entry['id'])}', body);
          if (!_ok(response)) {
            skipped++;
            continue;
          }
          uploaded++;
          confirmedEntries.add(entry);
        } catch (_) {
          skipped++;
        }
      }
    }

    if (!includePhotos && published != null && published[memoriesTable] != null) {
      confirmed[memoriesTable] = published[memoriesTable];
    }

    if (uploaded == 0 && sameManifest(published, confirmed)) {
      return PublishResult(ok: true, uploaded: uploaded, skipped: skipped, unchanged: true);
    }

    try {
      final sealed = encryptJson(confirmed, key);
      final response = await _request(cfg, 'PUT', '$base/manifest', jsonStringify(sealed.toJson()));
      if (!_ok(response)) {
        return PublishResult(ok: false, reason: 'manifest-failed', uploaded: uploaded, skipped: skipped);
      }
    } catch (_) {
      return PublishResult(ok: false, reason: 'offline', uploaded: uploaded, skipped: skipped);
    }

    return PublishResult(ok: true, uploaded: uploaded, skipped: skipped);
  }

  Future<CollectResult> collect({required VaultKey? key, required String? partnerId}) async {
    final cfg = config;
    if (cfg == null) return const CollectResult(ok: false, reason: 'disabled');
    if (key == null) return const CollectResult(ok: false, reason: 'locked');
    if (partnerId == null || partnerId.isEmpty) return const CollectResult(ok: false, reason: 'no-partner');

    final mailboxId = deriveMailboxId(key);
    final base = '/m/$mailboxId/$partnerId';

    final remote = await _readManifest(cfg, base, key);
    if (remote == null) return const CollectResult(ok: true, reason: 'nothing-published');

    final diff = await diffAgainstLocal(remote, store);
    if (diff.sawFutureTimestamp) onWarning?.call('clock_skew', clockSkewWarning);
    if (diff.wanted.isEmpty) return const CollectResult(ok: true);

    final tables = <String, List<Object?>>{};
    var fetched = 0;

    for (final wanted in diff.wanted) {
      try {
        final response = await _request(cfg, 'GET', '$base/rec/${wanted.table}/${recordKey(wanted.id)}');
        if (!_ok(response)) continue;
        final record = jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true));
        tables.putIfAbsent(wanted.table, () => <Object?>[]).add(record);
        fetched++;
      } catch (_) {}
    }

    if (fetched == 0) return const CollectResult(ok: true);

    final plan = await store.planBackupMerge(tables, key);
    final result = await store.applyBackupMerge(plan);

    return CollectResult(ok: true, applied: result.totalWritten, fetched: fetched, totals: plan.totals);
  }

  Future<MailboxSyncResult> sync({
    required VaultKey? key,
    required String? ownerId,
    required List<String?> slots,
    bool includePhotos = true,
  }) async {
    final collected = <CollectResult>[];
    for (final slot in slots) {
      if (slot == null || slot.isEmpty) continue;
      collected.add(await collect(key: key, partnerId: slot));
    }

    final published = (ownerId != null && ownerId.isNotEmpty)
        ? await publish(key: key, ownerId: ownerId, includePhotos: includePhotos)
        : const PublishResult(ok: false, reason: 'no-owner');

    return MailboxSyncResult(
      collected: collected,
      published: published,
      applied: collected.fold(0, (sum, r) => sum + r.applied),
      uploaded: published.uploaded,
    );
  }

  void close() => _client.close();
}
