import 'dart:convert';

import '../crypto/base64.dart';
import '../crypto/js_compat.dart';

final RegExp peerIdRegex = RegExp(r'^[a-zA-Z0-9_-]{4,64}$');

const int _ivBytes = 12;
const int _minCompositeIdLength = 8;
const int _maxFieldLength = 2048;
const int _maxCoupleNamesLength = 120;

const String defaultInviteBaseUrl = String.fromEnvironment(
  'OUR_SPACE_WEB_URL',
  defaultValue: 'https://sameskytonight.vercel.app/',
);

class Invite {
  const Invite({
    required this.partnerPeerId,
    required this.salt,
    required this.startDate,
    required this.coupleNames,
    required this.canary,
    required this.canaryIv,
  });

  final String partnerPeerId;
  final String? salt;
  final String? startDate;
  final String? coupleNames;
  final String? canary;
  final String? canaryIv;

  bool get canJoin => salt != null;

  Map<String, Object?> toJson() => {
        'partnerPeerId': partnerPeerId,
        'salt': salt,
        'startDate': startDate,
        'coupleNames': coupleNames,
        'canary': canary,
        'canaryIv': canaryIv,
      };
}

String? _canonicalBase64(Object? value, [int? byteLength]) {
  if (value is! String || value.isEmpty || value.length > _maxFieldLength) return null;
  if (!isValidBase64(value, byteLength)) return null;
  try {
    return bufferToBase64(base64ToBuffer(value));
  } catch (_) {
    return null;
  }
}

String? _cleanSalt(Object? value) {
  if (value is! String) return null;
  final trimmed = jsTrim(value);
  if (!isValidSalt(trimmed)) return null;
  return _canonicalBase64(trimmed, 16);
}

bool _parseableIsoDate(String value) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) return false;
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  return month >= 1 && month <= 12 && day >= 1 && day <= 31;
}

String? _cleanStartDate(Object? value) {
  if (value is! String) return null;
  final trimmed = jsTrim(value);
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(trimmed)) return null;
  return _parseableIsoDate(trimmed) ? trimmed : null;
}

String? _cleanCoupleNames(Object? value) {
  if (value is! String) return null;
  final trimmed = jsTrim(jsSlice(value, 0, _maxCoupleNamesLength));
  return trimmed.isEmpty ? null : trimmed;
}

String? _toUrlSafe(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return toUrlSafeBase64(value);
}

Invite? _buildInvite(Object? peerId, {Object? salt, Object? startDate, Object? coupleNames, Object? canary, Object? canaryIv}) {
  final id = peerId is String ? jsTrim(peerId) : '';
  if (!peerIdRegex.hasMatch(id)) return null;

  final cleanCanary = _canonicalBase64(canary);
  final cleanCanaryIv = _canonicalBase64(canaryIv, _ivBytes);
  final hasProof = cleanCanary != null && cleanCanaryIv != null;

  return Invite(
    partnerPeerId: id,
    salt: _cleanSalt(salt),
    startDate: _cleanStartDate(startDate),
    coupleNames: _cleanCoupleNames(coupleNames),
    canary: hasProof ? cleanCanary : null,
    canaryIv: hasProof ? cleanCanaryIv : null,
  );
}

class FormParams {
  FormParams._(this._pairs);

  factory FormParams.parse(String input) {
    var text = input;
    if (text.startsWith('?')) text = text.substring(1);
    final pairs = <MapEntry<String, String>>[];
    for (final piece in text.split('&')) {
      if (piece.isEmpty) continue;
      final eq = piece.indexOf('=');
      final rawName = eq < 0 ? piece : piece.substring(0, eq);
      final rawValue = eq < 0 ? '' : piece.substring(eq + 1);
      pairs.add(MapEntry(_decode(rawName), _decode(rawValue)));
    }
    return FormParams._(pairs);
  }

  FormParams() : _pairs = [];

  final List<MapEntry<String, String>> _pairs;

  String? get(String name) {
    for (final pair in _pairs) {
      if (pair.key == name) return pair.value;
    }
    return null;
  }

  void set(String name, String value) {
    final index = _pairs.indexWhere((pair) => pair.key == name);
    if (index < 0) {
      _pairs.add(MapEntry(name, value));
      return;
    }
    _pairs[index] = MapEntry(name, value);
    for (var i = _pairs.length - 1; i > index; i--) {
      if (_pairs[i].key == name) _pairs.removeAt(i);
    }
  }

  @override
  String toString() => _pairs.map((pair) => '${_encode(pair.key)}=${_encode(pair.value)}').join('&');

  static int _hex(int c) {
    if (c >= 0x30 && c <= 0x39) return c - 0x30;
    if (c >= 0x41 && c <= 0x46) return c - 0x41 + 10;
    if (c >= 0x61 && c <= 0x66) return c - 0x61 + 10;
    return -1;
  }

  static String _decode(String input) {
    final bytes = utf8.encode(input.replaceAll('+', ' '));
    final out = <int>[];
    for (var i = 0; i < bytes.length; i++) {
      final b = bytes[i];
      if (b == 0x25 && i + 2 < bytes.length) {
        final hi = _hex(bytes[i + 1]);
        final lo = _hex(bytes[i + 2]);
        if (hi >= 0 && lo >= 0) {
          out.add(hi * 16 + lo);
          i += 2;
          continue;
        }
      }
      out.add(b);
    }
    return utf8.decode(out, allowMalformed: true);
  }

  static bool _unreserved(int b) =>
      (b >= 0x30 && b <= 0x39) ||
      (b >= 0x41 && b <= 0x5A) ||
      (b >= 0x61 && b <= 0x7A) ||
      b == 0x2A ||
      b == 0x2D ||
      b == 0x2E ||
      b == 0x5F;

  static String _encode(String input) {
    final out = StringBuffer();
    for (final b in utf8.encode(input)) {
      if (b == 0x20) {
        out.write('+');
      } else if (_unreserved(b)) {
        out.writeCharCode(b);
      } else {
        out.write('%');
        out.write(b.toRadixString(16).toUpperCase().padLeft(2, '0'));
      }
    }
    return out.toString();
  }
}

Invite? _fromParams(FormParams params) => _buildInvite(
      params.get('connect'),
      salt: params.get('salt'),
      startDate: params.get('start'),
      coupleNames: params.get('names'),
      canary: params.get('canary'),
      canaryIv: params.get('civ'),
    );

String buildInviteUrl(
  String? peerId,
  String? salt, {
  String? baseUrl,
  String? startDate,
  String? coupleNames,
  String? canary,
  String? canaryIv,
}) {
  final base = (baseUrl == null || baseUrl.isEmpty) ? defaultInviteBaseUrl : baseUrl;
  final params = FormParams();
  if (peerId != null && peerId.isNotEmpty) params.set('connect', peerId);
  if (salt != null && salt.isNotEmpty) params.set('salt', _toUrlSafe(salt) ?? salt);
  if (startDate != null && startDate.isNotEmpty) params.set('start', startDate);
  if (coupleNames != null && coupleNames.isNotEmpty) params.set('names', coupleNames);
  if (canary != null && canary.isNotEmpty && canaryIv != null && canaryIv.isNotEmpty) {
    params.set('canary', _toUrlSafe(canary) ?? canary);
    params.set('civ', _toUrlSafe(canaryIv) ?? canaryIv);
  }
  return '$base#$params';
}

Invite? parseInvite(Object? input) {
  if (input is! String || input.isEmpty) return null;
  final text = jsTrim(input);
  if (text.isEmpty) return null;

  if (text.contains('#')) {
    final parsed = _fromParams(FormParams.parse(text.substring(text.indexOf('#') + 1)));
    if (parsed != null) return parsed;
  }

  if (text.contains('connect=')) {
    final cleanQuery = text.startsWith('?') ? text.substring(1) : text;
    final parsed = _fromParams(FormParams.parse(cleanQuery));
    if (parsed != null) return parsed;
  }

  if (text.contains('.') && !text.startsWith('http')) {
    final separator = text.indexOf('.');
    final idPart = jsTrim(text.substring(0, separator));
    final saltPart = jsTrim(text.substring(separator + 1));
    if (idPart.length >= _minCompositeIdLength && _cleanSalt(saltPart) != null) {
      final parsed = _buildInvite(idPart, salt: saltPart);
      if (parsed != null) return parsed;
    }
  }

  return _buildInvite(text);
}
