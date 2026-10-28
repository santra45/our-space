import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../../core/engine.dart';

enum SkyGatePhase { idle, holdingAlone, partnerHolding, together, opening, open }

abstract final class SkyHeartbeat {
  static const int periodMs = 1300;
  static const int dubMs = 180;
  static const double fadeMs = 170;

  static int beatOf(int shared) => (shared / periodMs).floor();

  static int beatAt(int beat) => beat * periodMs;

  static int nextAfter(int shared) => beatAt(beatOf(shared) + 1);

  static List<int> between(int after, int until) {
    if (until <= after) return const [];
    final out = <int>[];
    for (var beat = beatOf(after) + 1; beatAt(beat) <= until; beat++) {
      out.add(beatAt(beat));
      if (out.length >= 64) break;
    }
    return out;
  }

  static double glow(int shared) {
    final since = shared - beatAt(beatOf(shared));
    final lub = math.exp(-since / fadeMs);
    final dub = since < dubMs ? 0.0 : 0.7 * math.exp(-(since - dubMs) / fadeMs);
    return math.min(1, lub + dub);
  }
}

@immutable
class SkyGateOpen {
  const SkyGateOpen({required this.at});

  final int at;

  @override
  bool operator ==(Object other) => other is SkyGateOpen && other.at == at;

  @override
  int get hashCode => at.hashCode;
}

class SkyGate {
  SkyGate({this.holdMs = 10000, this.leadMs = 400, this.graceMs = 1500});

  final int holdMs;
  final int leadMs;
  final int graceMs;

  int? _mine;
  int? _myReleasedAt;
  int? _theirs;
  int _theirSeq = 0;
  String? _drawing;
  int? _openAt;

  bool get holding => _mine != null;

  bool get partnerHolding => _theirs != null;

  int? get myPressAt => _mine;

  int? get partnerPressAt => _theirs;

  int? get overlapStart {
    final mine = _mine;
    final theirs = _theirs;
    if (mine == null || theirs == null) return null;
    return math.max(mine, theirs);
  }

  bool get decided => _openAt != null;

  String? get drawing => _drawing;

  int? get openAt => _openAt;

  SkyGatePhase phaseAt(int now) {
    final openAt = _openAt;
    if (openAt != null) return now >= openAt ? SkyGatePhase.open : SkyGatePhase.opening;
    if (_mine != null && _theirs != null) return SkyGatePhase.together;
    if (_mine != null) return SkyGatePhase.holdingAlone;
    if (_theirs != null) return SkyGatePhase.partnerHolding;
    return SkyGatePhase.idle;
  }

  double progressAt(int now) {
    if (_openAt != null) return 1;
    final start = overlapStart;
    if (start == null) return 0;
    return ((now - start) / holdMs).clamp(0.0, 1.0);
  }

  bool pulsing(int now) => phaseAt(now) == SkyGatePhase.together;

  List<int> beatsBetween(int after, int now) => pulsing(now) ? SkyHeartbeat.between(after, now) : const [];

  void press(int at) {
    if (_openAt != null) return;
    _mine = at;
    _myReleasedAt = null;
  }

  void release(int at) {
    if (_openAt != null || _mine == null) return;
    _mine = null;
    _myReleasedAt = at;
  }

  void partnerPress(int at, int seq) {
    if (_openAt != null) return;
    _theirs = at;
    _theirSeq = seq;
  }

  void partnerRelease(int at, int seq) {
    if (_openAt != null || _theirs == null) return;
    if (seq != _theirSeq) return;
    _theirs = null;
  }

  void hear(SkyHoldEvent event) {
    if (event.down) {
      partnerPress(event.at, event.seq);
    } else {
      partnerRelease(event.at, event.seq);
    }
  }

  void partnerLost(int now) {
    _theirs = null;
    _theirSeq = 0;
    final openAt = _openAt;
    if (openAt != null && now < openAt) {
      _openAt = null;
      _drawing = null;
    }
  }

  SkyGateOpen? due(int now, {required bool? leader}) {
    if (leader != true || _openAt != null) return null;
    final start = overlapStart;
    if (start == null) return null;
    final target = start + holdMs;
    if (now < target - leadMs) return null;
    return SkyGateOpen(at: math.max(target, now));
  }

  void commit(String drawing, int at) {
    _drawing = drawing;
    _openAt = at;
  }

  bool accept(String drawing, int at, int now) {
    final current = _drawing;
    if (current != null && _openAt != null) {
      if (current == drawing) return true;
      if (drawing.compareTo(current) < 0) {
        _drawing = drawing;
        _openAt = at;
      }
      return true;
    }
    final releasedAt = _myReleasedAt;
    final justLetGo = releasedAt != null && now - releasedAt <= graceMs;
    if (_mine == null && !justLetGo) return false;
    _drawing = drawing;
    _openAt = at;
    return true;
  }

  void cancel(String drawing) {
    if (_drawing != drawing) return;
    _drawing = null;
    _openAt = null;
  }

  void reset() {
    _mine = null;
    _myReleasedAt = null;
    _theirs = null;
    _theirSeq = 0;
    _drawing = null;
    _openAt = null;
  }
}
