import 'aes_gcm.dart';
import 'envelope.dart';
import 'js_compat.dart';

const String vaultCanaryToken = 'SWEETHEART_CANARY_VALIDATION_TOKEN';

class SealedCanary {
  const SealedCanary({required this.canary, required this.canaryIv});
  final String canary;
  final String canaryIv;
}

SealedCanary createCanary(
  VaultKey key, {
  String? coupleNames,
  String? startDate,
  num? createdAt,
  num? updatedAt,
  NowFn now = systemNow,
}) {
  final sealed = encryptJson({
    'token': vaultCanaryToken,
    'coupleNames': (coupleNames == null || coupleNames.isEmpty) ? 'Us' : coupleNames,
    'startDate': (startDate == null || startDate.isEmpty) ? '' : startDate,
    'createdAt': isFiniteNumber(createdAt) ? createdAt : now(),
    'updatedAt': isFiniteNumber(updatedAt) ? updatedAt : 0,
  }, key);
  return SealedCanary(canary: sealed.ciphertext, canaryIv: sealed.iv);
}

Map<String, Object?>? readCanary(VaultKey key, Map<String, Object?>? meta) {
  if (meta == null) return null;
  final canary = meta['canary'];
  final canaryIv = meta['canaryIv'];
  if (canary is! String || canaryIv is! String) return null;
  try {
    final payload = asStringMap(decryptJson(canary, canaryIv, key));
    if (payload == null || payload['token'] != vaultCanaryToken) return null;
    return payload;
  } catch (_) {
    return null;
  }
}
