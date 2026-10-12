import 'dart:async';

import '../crypto/base64.dart';
import '../storage/local_settings.dart';

final RegExp deviceTagPattern = RegExp(r'^[A-Za-z0-9_-]{8,64}$');

final RegExp peerIdPattern = RegExp(r'^[a-zA-Z0-9_-]{4,64}$');

const String _base32Alphabet = '0123456789abcdefghjkmnpqrstvwxyz';

String generatePeerId() {
  final bytes = randomBytes(10);
  var value = 0;
  var bits = 0;
  final out = StringBuffer('love-');
  for (final byte in bytes) {
    value = (value << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      out.write(_base32Alphabet[(value >> bits) & 31]);
      value &= (1 << bits) - 1;
    }
  }
  if (bits > 0) {
    out.write(_base32Alphabet[(value << (5 - bits)) & 31]);
  }
  return out.toString();
}

class DeviceIdentity {
  DeviceIdentity(this._settings);

  static const String storageKey = 'sweetheart_device_owner_v1';
  static const String legacyKey = 'sweetheart_burst_owner_v1';
  static const String peerIdKey = 'sweetheart_device_peer_id';

  final LocalSettings _settings;
  String? _cached;

  String get deviceId {
    final cached = _cached;
    if (cached != null) return cached;

    final current = _settings.getItem(storageKey);
    if (current != null && deviceTagPattern.hasMatch(current)) {
      return _cached = current;
    }

    final legacy = _settings.getItem(legacyKey);
    if (legacy != null && deviceTagPattern.hasMatch(legacy)) {
      _cached = legacy;
      unawaited(_settings.setItem(storageKey, legacy));
      return legacy;
    }

    final fresh = generateUrlSafeNonce(12);
    _cached = fresh;
    unawaited(_settings.setItem(storageKey, fresh));
    return fresh;
  }

  String get peerId {
    final stored = _settings.getItem(peerIdKey);
    if (stored != null && peerIdPattern.hasMatch(stored)) return stored;
    final fresh = generatePeerId();
    unawaited(_settings.setItem(peerIdKey, fresh));
    return fresh;
  }
}
