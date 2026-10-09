import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import '../constants/app_constants.dart';
import '../crypto/crypto_engine.dart';

abstract class PeerMessageType {
  static const String authChallenge = 'AUTH_CHALLENGE';
  static const String authResponse = 'AUTH_RESPONSE';
  static const String authSuccess = 'AUTH_SUCCESS';
  static const String manifestAdvertise = 'MANIFEST_ADVERTISE';
  static const String syncRequestRecords = 'SYNC_REQUEST_RECORDS';
  static const String syncRecordsBatch = 'SYNC_RECORDS_BATCH';
  static const String syncComplete = 'SYNC_COMPLETE';
  static const String heartbeat = 'HEARTBEAT';
  static const String loveBurst = 'LOVE_BURST';
}

class PeerProtocol {
  PeerProtocol._();

  static Future<Map<String, dynamic>> packFrame(
    Map<String, dynamic> message,
    Uint8List vaultKey,
  ) async {
    final payloadEncrypted = await CryptoEngine.instance.encryptJSON(message, vaultKey);

    return {
      'protocol': protocolId,
      'payload': {
        'ciphertext': payloadEncrypted['ciphertext']!,
        'iv': payloadEncrypted['iv']!,
      },
    };
  }

  static Future<Map<String, dynamic>> unpackFrame(
    Map<String, dynamic> frame,
    Uint8List vaultKey,
  ) async {
    if (frame['protocol'] != protocolId) {
      throw FormatException('Unsupported sync protocol: ${frame['protocol']}');
    }

    final payload = frame['payload'] as Map<String, dynamic>?;
    if (payload == null) {
      throw const FormatException('Malformed frame: missing payload.');
    }

    final ciphertext = payload['ciphertext'] as String?;
    final iv = payload['iv'] as String?;
    if (ciphertext == null || iv == null) {
      throw const FormatException('Malformed frame: payload missing ciphertext or iv.');
    }

    return await CryptoEngine.instance.decryptJSON(ciphertext, iv, vaultKey);
  }

  static String computeChallengeResponse(String challengeNonce, Uint8List vaultKey) {
    final hmac = Hmac(sha256, vaultKey);
    final digest = hmac.convert(utf8.encode('our-space/auth-v2|$challengeNonce'));
    return base64Encode(digest.bytes);
  }

  static bool verifyChallengeResponse(
    String challengeNonce,
    String responseBase64,
    Uint8List vaultKey,
  ) {
    final expected = computeChallengeResponse(challengeNonce, vaultKey);
    return expected == responseBase64;
  }
}
