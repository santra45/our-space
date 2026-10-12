import 'dart:async';

import 'package:our_space_mobile/core/engine/p2p/peer_clock.dart';

class FakeTimer implements Timer {
  FakeTimer(this._clock, this.dueAt, this.interval, this.callback, this.order);

  final FakePeerClock _clock;
  int dueAt;
  final int? interval;
  final void Function() callback;
  final int order;
  bool _active = true;
  int _tick = 0;

  @override
  bool get isActive => _active;

  @override
  int get tick => _tick;

  @override
  void cancel() {
    _active = false;
    _clock._timers.remove(this);
  }
}

class FakePeerClock implements PeerClock {
  FakePeerClock([this._now = 1760000000000]);

  int _now;
  int _order = 0;
  final List<FakeTimer> _timers = [];

  @override
  int now() => _now;

  set nowValue(int value) => _now = value;

  int get pendingTimers => _timers.length;

  @override
  Timer after(Duration delay, void Function() callback) {
    final timer = FakeTimer(this, _now + delay.inMilliseconds, null, callback, _order++);
    _timers.add(timer);
    return timer;
  }

  @override
  Timer every(Duration interval, void Function() callback) {
    final ms = interval.inMilliseconds < 1 ? 1 : interval.inMilliseconds;
    final timer = FakeTimer(this, _now + ms, ms, callback, _order++);
    _timers.add(timer);
    return timer;
  }

  void advance(Duration by) {
    final target = _now + by.inMilliseconds;
    while (true) {
      final due = _timers.where((t) => t.isActive && t.dueAt <= target).toList()
        ..sort((a, b) => a.dueAt != b.dueAt ? a.dueAt.compareTo(b.dueAt) : a.order.compareTo(b.order));
      if (due.isEmpty) break;
      final timer = due.first;
      _now = timer.dueAt;
      final interval = timer.interval;
      if (interval != null) {
        timer.dueAt += interval;
        timer._tick++;
      } else {
        timer._active = false;
        _timers.remove(timer);
      }
      timer.callback();
    }
    _now = target;
  }
}
