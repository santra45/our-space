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

final List<String> mailboxTextTables = syncedTables
    .where((name) => name != memoriesTable && !appOnlyTables.contains(name))
    .toList();

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
    final versions = <Object?, (Object?, bool)>{};
    for (final e in before) {
      final entry = e is Map ? e : null;
      if (entry == null) return false;
      versions[entry['id']] = (entry['updatedAt'], entry['deleted'] == true);
    }
    for (final e in after) {
      final entry = e is Map ? e : null;
      if (entry == null) return false;
      if (versions[entry['id']] != (entry['updatedAt'], entry['deleted'] == true)) return false;
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

  String? get failure {
    for (final result in collected) {
      if (!result.ok) return result.reason ?? 'collect-failed';
    }
    if (!published.ok && published.reason != 'no-owner') return published.reason ?? 'publish-failed';
    return null;
  }

  bool get ok => failure == null;
}

typedef _ManifestRead = ({Map<String, Object?>? manifest, String? failure});

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

  String _failureFor(http.Response response) {
    final status = response.statusCode;
    if (status == 401 || status == 403) return 'unauthorized';
    return 'http-$status';
  }

  Future<_ManifestRead> _readManifest(MailboxConfig cfg, String base, VaultKey key) async {
    http.Response response;
    try {
      response = await _request(cfg, 'GET', '$base/manifest');
    } catch (_) {
      return (manifest: null, failure: 'offline');
    }
    if (response.statusCode == 404) return (manifest: null, failure: null);
    if (!_ok(response)) return (manifest: null, failure: _failureFor(response));
    try {
      final sealed = asStringMap(jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true)));
      final ciphertext = sealed?['ciphertext'];
      final iv = sealed?['iv'];
      if (ciphertext is! String || iv is! String) return (manifest: null, failure: 'unreadable');
      final manifest = decryptJson(ciphertext, iv, key);
      if (manifest is! Map) return (manifest: null, failure: 'unreadable');
      return (manifest: asStringMap(manifest), failure: null);
    } catch (_) {
      return (manifest: null, failure: 'unreadable');
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

    final read = await _readManifest(cfg, base, key);
    final readFailure = read.failure;
    if (readFailure != null && readFailure != 'unreadable') {
      return PublishResult(ok: false, reason: readFailure);
    }
    final published = read.manifest;
    final local = await store.getManifest();
    final confirmed = <String, Object?>{};
    var uploaded = 0;
    var skipped = 0;
    var failed = 0;

    final tables = includePhotos ? [...mailboxTextTables, memoriesTable] : mailboxTextTables;

    for (final table in tables) {
      final entries = local[table] ?? const <Map<String, Object?>>[];
      final already = <Object?, (Object?, bool)>{};
      final publishedEntries = published?[table];
      if (publishedEntries is List) {
        for (final e in publishedEntries) {
          if (e is Map) already[e['id']] = (e['updatedAt'], e['deleted'] == true);
        }
      }
      final confirmedEntries = <Map<String, Object?>>[];
      confirmed[table] = confirmedEntries;

      for (final entry in entries) {
        if (already[entry['id']] == (entry['updatedAt'], entry['deleted'] == true)) {
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
            failed++;
            continue;
          }
          uploaded++;
          confirmedEntries.add(entry);
        } catch (_) {
          skipped++;
          failed++;
        }
      }
    }

    if (!includePhotos && published != null && published[memoriesTable] != null) {
      confirmed[memoriesTable] = published[memoriesTable];
    }

    final partial = failed > 0 ? 'partial' : null;

    if (uploaded == 0 && sameManifest(published, confirmed)) {
      return PublishResult(ok: failed == 0, reason: partial, uploaded: uploaded, skipped: skipped, unchanged: true);
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

    return PublishResult(ok: failed == 0, reason: partial, uploaded: uploaded, skipped: skipped);
  }

  Future<CollectResult> collect({required VaultKey? key, required String? partnerId}) async {
    final cfg = config;
    if (cfg == null) return const CollectResult(ok: false, reason: 'disabled');
    if (key == null) return const CollectResult(ok: false, reason: 'locked');
    if (partnerId == null || partnerId.isEmpty) return const CollectResult(ok: false, reason: 'no-partner');

    final mailboxId = deriveMailboxId(key);
    final base = '/m/$mailboxId/$partnerId';

    final read = await _readManifest(cfg, base, key);
    final readFailure = read.failure;
    if (readFailure != null) return CollectResult(ok: false, reason: readFailure);
    final remote = read.manifest;
    if (remote == null) return const CollectResult(ok: true, reason: 'nothing-published');

    final diff = await diffAgainstLocal(remote, store);
    if (diff.sawFutureTimestamp) onWarning?.call('clock_skew', clockSkewWarning);
    if (diff.wanted.isEmpty) return const CollectResult(ok: true);

    final tables = <String, List<Object?>>{};
    var fetched = 0;
    var failed = 0;

    for (final wanted in diff.wanted) {
      http.Response response;
      try {
        response = await _request(cfg, 'GET', '$base/rec/${wanted.table}/${recordKey(wanted.id)}');
      } catch (_) {
        failed++;
        continue;
      }
      if (response.statusCode == 404) continue;
      if (!_ok(response)) {
        failed++;
        continue;
      }
      Object? record;
      try {
        record = jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true));
      } catch (_) {
        continue;
      }
      tables.putIfAbsent(wanted.table, () => <Object?>[]).add(record);
      fetched++;
    }

    final partial = failed > 0 ? 'partial' : null;

    if (fetched == 0) return CollectResult(ok: failed == 0, reason: partial);

    final plan = await store.planBackupMerge(tables, key);
    final result = await store.applyBackupMerge(plan);

    return CollectResult(
      ok: failed == 0,
      applied: result.totalWritten,
      fetched: fetched,
      reason: partial,
      totals: plan.totals,
    );
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

  Future<bool> registerPush({
    required VaultKey? key,
    required String? ownerId,
    required String device,
    required String address,
  }) async {
    final cfg = config;
    if (cfg == null || key == null || ownerId == null || ownerId.isEmpty) return false;
    try {
      final path = '/m/${deriveMailboxId(key)}/$ownerId/push/$device';
      return _ok(await _request(cfg, 'PUT', path, jsonEncode({'token': address})));
    } catch (_) {
      return false;
    }
  }

  Future<bool> forgetPush({required VaultKey? key, required String? ownerId, required String device}) async {
    final cfg = config;
    if (cfg == null || key == null || ownerId == null || ownerId.isEmpty) return false;
    try {
      return _ok(await _request(cfg, 'DELETE', '/m/${deriveMailboxId(key)}/$ownerId/push/$device'));
    } catch (_) {
      return false;
    }
  }

  void close() => _client.close();
}
