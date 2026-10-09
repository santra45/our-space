import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as std_crypto;
import 'package:http/http.dart' as http;
import '../constants/app_constants.dart';
import '../crypto/crypto_engine.dart';
import '../storage/app_database.dart';
import '../storage/tombstone_helper.dart';

const String mailboxIdContext = 'our-space/mailbox/id/v1';

class MailboxService {
  MailboxService._();
  static final MailboxService instance = MailboxService._();

  String? _mailboxUrl;
  String? _mailboxToken;

  void configure({String? url, String? token}) {
    if (url != null && url.isNotEmpty && token != null && token.isNotEmpty) {
      _mailboxUrl = url.replaceAll(RegExp(r'/+$'), '');
      _mailboxToken = token;
    } else {
      _mailboxUrl = null;
      _mailboxToken = null;
    }
  }

  bool get isConfigured => _mailboxUrl != null && _mailboxToken != null;

  Future<String> deriveMailboxId(Uint8List vaultKey) async {
    final fixedIv = Uint8List(ivLengthBytes);
    final contextBytes = Uint8List.fromList(utf8.encode(mailboxIdContext));

    final encrypted = await CryptoEngine.instance.encryptBytes(
      contextBytes,
      vaultKey,
      iv: fixedIv,
    );

    final sealedBytes = base64Decode(encrypted['ciphertext']!);
    final digest = std_crypto.sha256.convert(sealedBytes);

    return digest.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  String recordKey(String id) {
    final bytes = utf8.encode(id);
    return base64Encode(bytes)
        .replaceAll('+', '-')
        .replaceAll('/', '_')
        .replaceAll('=', '');
  }

  Future<int> publish(Uint8List vaultKey) async {
    if (!isConfigured) return 0;

    final mailboxId = await deriveMailboxId(vaultKey);
    final manifest = await AppDatabase.instance.getManifest();

    int uploadedCount = 0;

    for (final table in syncedTables) {
      final rows = await AppDatabase.instance.getActiveRecords(table);
      for (final row in rows) {
        final id = row['id'] as String;
        final rKey = recordKey(id);

        final response = await http.put(
          Uri.parse('$_mailboxUrl/m/$mailboxId/$rKey'),
          headers: {
            'Authorization': 'Bearer $_mailboxToken',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(row),
        );

        if (response.statusCode == 200 || response.statusCode == 201) {
          uploadedCount++;
        }
      }
    }

    final encryptedManifest = await CryptoEngine.instance.encryptJSON(manifest, vaultKey);
    await http.put(
      Uri.parse('$_mailboxUrl/m/$mailboxId/manifest'),
      headers: {
        'Authorization': 'Bearer $_mailboxToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(encryptedManifest),
    );

    return uploadedCount;
  }

  Future<int> collect(Uint8List vaultKey) async {
    if (!isConfigured) return 0;

    final mailboxId = await deriveMailboxId(vaultKey);

    final manifestResponse = await http.get(
      Uri.parse('$_mailboxUrl/m/$mailboxId/manifest'),
      headers: {
        'Authorization': 'Bearer $_mailboxToken',
      },
    );

    if (manifestResponse.statusCode != 200) return 0;

    final encryptedManifest = jsonDecode(manifestResponse.body) as Map<String, dynamic>;
    final remoteManifest = await CryptoEngine.instance.decryptJSON(
      encryptedManifest['ciphertext'] as String,
      encryptedManifest['iv'] as String,
      vaultKey,
    );

    int appliedCount = 0;

    for (final table in syncedTables) {
      final remoteRows = (remoteManifest[table] as List<dynamic>?) ?? [];
      for (final r in remoteRows) {
        final remoteItem = r as Map<String, dynamic>;
        final id = remoteItem['id'] as String;
        final remoteUpdatedAt = (remoteItem['updatedAt'] as num?)?.toInt() ?? 0;

        final localRecord = await AppDatabase.instance.getRecord(table, id);
        final wantsRemote = localRecord == null ||
            TombstoneHelper.incomingWins(localRecord, remoteItem);

        if (wantsRemote) {
          final rKey = recordKey(id);
          final recResponse = await http.get(
            Uri.parse('$_mailboxUrl/m/$mailboxId/$rKey'),
            headers: {
              'Authorization': 'Bearer $_mailboxToken',
            },
          );

          if (recResponse.statusCode == 200) {
            final envelope = jsonDecode(recResponse.body) as Map<String, dynamic>;
            await AppDatabase.instance.putEnvelope(table, envelope);
            TombstoneHelper.bumpSyncClockFloor(remoteUpdatedAt);
            appliedCount++;
          }
        }
      }
    }

    return appliedCount;
  }
}
