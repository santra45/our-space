import 'dart:async';

import '../crypto/js_compat.dart';

abstract class PeerClock {
  int now();

  Timer after(Duration delay, void Function() callback);

  Timer every(Duration interval, void Function() callback);
}

class SystemPeerClock implements PeerClock {
  const SystemPeerClock([this._now = systemNow]);

  final NowFn _now;

  @override
  int now() => _now();

  @override
  Timer after(Duration delay, void Function() callback) => Timer(delay, callback);

  @override
  Timer every(Duration interval, void Function() callback) => Timer.periodic(interval, (_) => callback());
}
