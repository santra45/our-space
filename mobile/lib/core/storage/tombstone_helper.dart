import '../constants/app_constants.dart';

/// Last-Write-Wins (LWW) conflict resolution and Monotonic Clock synchronization helper.
/// Exactly mirrors the determinism and attack defenses of peerSync.js and db/index.js.
class TombstoneHelper {
  TombstoneHelper._();

  static int _syncClockFloor = 0;

  /// Returns a strictly monotonic timestamp guaranteed to be >= local clock and past sync history.
  static int getSyncSafeTimestamp() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _syncClockFloor = now > _syncClockFloor ? now : _syncClockFloor + 1;
    return _syncClockFloor;
  }

  /// Updates the monotonic clock floor upon receiving incoming remote records.
  static void bumpSyncClockFloor(int remoteTimestamp) {
    if (remoteTimestamp > _syncClockFloor &&
        remoteTimestamp <= DateTime.now().millisecondsSinceEpoch + maxClockSkewMs) {
      _syncClockFloor = remoteTimestamp;
    }
  }

  /// Determines whether an incoming record should overwrite the existing local record.
  ///
  /// INVARIANTS:
  /// 1. Higher `updatedAt` wins.
  /// 2. Tie-break 1: If equal `updatedAt`, deletion (tombstone) beats an edit.
  /// 3. Tie-break 2: Lexicographical comparison of authenticated fingerprint (v|ciphertext|iv).
  static bool incomingWins(
    Map<String, dynamic>? existing,
    Map<String, dynamic> incoming,
  ) {
    if (existing == null) return true;

    final int localAt = (existing['updatedAt'] as num?)?.toInt() ?? -1;
    final int remoteAt = (incoming['updatedAt'] as num?)?.toInt() ?? 0;

    if (remoteAt > localAt) return true;
    if (remoteAt < localAt) return false;

    // Tie-break 1: Deletion is never resurrected by a same-instant edit
    final bool localDeleted =
        existing['deleted'] == 1 || existing['deleted'] == true;
    final bool remoteDeleted =
        incoming['deleted'] == 1 || incoming['deleted'] == true;

    if (localDeleted != remoteDeleted) {
      return remoteDeleted;
    }

    // Tie-break 2: Lexicographic fingerprint comparison
    return _fingerprint(incoming).compareTo(_fingerprint(existing)) > 0;
  }

  /// Validates that an incoming timestamp is not dangerously skewed into the future.
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
