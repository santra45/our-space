import '../constants/app_constants.dart';

class TombstoneHelper {
  TombstoneHelper._();

  static int _syncClockFloor = 0;

  static int getSyncSafeTimestamp() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _syncClockFloor = now > _syncClockFloor ? now : _syncClockFloor + 1;
    return _syncClockFloor;
  }

  static void bumpSyncClockFloor(int remoteTimestamp) {
    if (remoteTimestamp > _syncClockFloor &&
        remoteTimestamp <= DateTime.now().millisecondsSinceEpoch + maxClockSkewMs) {
      _syncClockFloor = remoteTimestamp;
    }
  }

  static bool incomingWins(
    Map<String, dynamic>? existing,
    Map<String, dynamic> incoming,
  ) {
    if (existing == null) return true;

    final int localAt = (existing['updatedAt'] as num?)?.toInt() ?? -1;
    final int remoteAt = (incoming['updatedAt'] as num?)?.toInt() ?? 0;

    if (remoteAt > localAt) return true;
    if (remoteAt < localAt) return false;

    final bool localDeleted =
        existing['deleted'] == 1 || existing['deleted'] == true;
    final bool remoteDeleted =
        incoming['deleted'] == 1 || incoming['deleted'] == true;

    if (localDeleted != remoteDeleted) {
      return remoteDeleted;
    }

    return _fingerprint(incoming).compareTo(_fingerprint(existing)) > 0;
  }

  static bool isValidTimestamp(int timestamp, [int? now]) {
    final current = now ?? DateTime.now().millisecondsSinceEpoch;
    if (timestamp < 0) return false;
    if (timestamp > current + maxClockSkewMs) return false;
    return true;
  }

  static String _fingerprint(Map<String, dynamic> row) {
    final parts = [
      (row['v'] ?? recordSchemaVersion).toString(),
      (row['ciphertext'] as String?) ?? '',
      (row['iv'] as String?) ?? '',
    ];
    return parts.join('|');
  }
}
