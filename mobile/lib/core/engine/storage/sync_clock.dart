import 'dart:async';

import '../crypto/js_compat.dart';
import 'local_settings.dart';
import 'tables.dart';

class SyncClock {
  SyncClock(this._settings, {NowFn now = systemNow}) : _now = now;

  static const String storageKey = 'sweetheart_sync_clock';

  static const String rolledBackMessage =
      "This phone's date looks like it was changed. We have set syncing back to the current time.";

  final LocalSettings _settings;
  final NowFn _now;

  int observedRemoteMax = 0;
  int _lastIssuedStamp = 0;

  void Function(String code, String message)? onWarning;

  int next() {
    final now = _now();
    final ceiling = now + maxClockSkewMs;

    var floor = 0;
    final parsed = num.tryParse(_settings.getItem(storageKey) ?? '');
    if (parsed != null && parsed.isFinite && parsed > 0) floor = parsed.floor();

    if (floor > ceiling) {
      floor = now;
      onWarning?.call('clock_rolled_back', rolledBackMessage);
    }
    final remoteFloor = observedRemoteMax < ceiling ? observedRemoteMax : ceiling;

    var next = now;
    if (floor + 1 > next) next = floor + 1;
    if (remoteFloor + 1 > next) next = remoteFloor + 1;
    if (_lastIssuedStamp + 1 > next) next = _lastIssuedStamp + 1;
    _lastIssuedStamp = next;

    unawaited(_settings.setItem(storageKey, next.toString()));
    return next;
  }

  Future<int> stamp() async => next();

  void reset() {
    observedRemoteMax = 0;
  }
}
