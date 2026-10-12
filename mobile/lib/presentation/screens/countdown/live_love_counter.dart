import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/engine.dart';

typedef LoveClock = int Function();

int systemClock() => DateTime.now().millisecondsSinceEpoch;

class LiveLoveCounter extends ChangeNotifier {
  LiveLoveCounter({LoveClock? clock, this.period = const Duration(seconds: 1)}) : _clock = clock ?? systemClock;

  final LoveClock _clock;
  final Duration period;

  String? _startDate;
  LoveDuration _value = LoveDuration.zero;
  Timer? _timer;
  bool _tracking = false;

  LoveDuration get value => _value;
  String? get startDate => _startDate;
  bool get ticking => _timer?.isActive ?? false;

  int now() => _clock();

  void track(String? startDate) {
    if (_tracking && startDate == _startDate) return;
    _tracking = true;
    _startDate = startDate;
    _value = calculateLoveDuration(startDate, now: _clock());
    _timer?.cancel();
    _timer = null;
    if (startDate == null || startDate.isEmpty) return;
    _timer = Timer.periodic(period, (_) => _tick());
  }

  void _tick() {
    _value = calculateLoveDuration(_startDate, now: _clock());
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}

String twoDigitCount(int value) => value.toString().padLeft(2, '0');
