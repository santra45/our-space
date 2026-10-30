import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/engine.dart';
import '../../../widgets/app_haptics.dart';
import 'sky_gate.dart';
import 'sky_patch_session.dart';

enum SkyTogetherStage { off, invite, alone, partnerHolding, together, opening }

VaultKey? _noKey() => null;

class SkyTogetherHome extends ChangeNotifier {
  SkyTogetherHome({
    required this.link,
    this.drawings,
    VaultKey? Function()? keyOf,
    this.haptic = skyAppHaptic,
    this.persistDelay = const Duration(milliseconds: 600),
    this.nameEvery = const Duration(milliseconds: 150),
  }) : _keyOf = keyOf ?? _noKey {
    link.addListener(_onLink);
    _events = link.events.listen(_hear);
    _watch = drawings?.watch().listen((_) {
      if (_session == null) unawaited(refreshUnfinished());
    });
    unawaited(refreshUnfinished());
    _stage = _stageNow();
  }

  final SkyTogetherLink link;
  final SkyDrawingService? drawings;
  final VaultKey? Function() _keyOf;
  final SkyHaptic haptic;
  final Duration persistDelay;
  final Duration nameEvery;
  final SkyGate gate = SkyGate();

  static const int touchGapMs = 350;
  static const int feltGapMs = 250;

  late final StreamSubscription<SkyTogetherEvent> _events;
  StreamSubscription<void>? _watch;
  SkyTogetherStage _stage = SkyTogetherStage.off;
  SkyPatchSession? _session;
  String? _unfinished;
  int? _lastTick;
  int? _lastTouch;
  int? _lastFelt;
  int _touchesSent = 0;
  int _touchesFelt = 0;
  bool _visible = true;
  bool _disposed = false;

  void Function(SkyPatchSession session)? onOpen;

  SkyTogetherStage get stage => _stage;

  SkyPatchSession? get session => _session;

  String? get unfinishedId => _unfinished;

  bool get holding => gate.holding;

  bool get partnerHolding => gate.partnerHolding;

  bool get needsTicks => gate.holding || gate.partnerHolding || gate.decided;

  bool get visible => _visible;

  int get touchesSent => _touchesSent;

  int get touchesFelt => _touchesFelt;

  bool get canTouch => _stage != SkyTogetherStage.off && _stage != SkyTogetherStage.opening;

  bool touch() {
    if (_disposed || !canTouch) return false;
    final now = link.now();
    final last = _lastTouch;
    if (last != null && now - last >= 0 && now - last < touchGapMs) return false;
    _lastTouch = now;
    unawaited(link.sendTouch());
    _touchesSent++;
    haptic(HapticKind.tap);
    notifyListeners();
    return true;
  }

  void _felt() {
    if (!_visible || _session != null || !link.here) return;
    final now = link.now();
    final last = _lastFelt;
    if (last != null && now - last >= 0 && now - last < feltGapMs) return;
    _lastFelt = now;
    _touchesFelt++;
    haptic(HapticKind.heartbeat);
    notifyListeners();
  }

  void present({required bool visible, required bool night}) {
    if (_disposed) return;
    if (!visible) {
      release();
      _callOff();
    }
    _visible = visible;
    link.setPresence(here: visible || _session != null, night: night);
    _sync();
  }

  void _announceHere() {
    if (_disposed) return;
    link.setPresence(here: _visible || _session != null);
  }

  SkyTogetherStage _stageNow() {
    if (_disposed || _session != null) return SkyTogetherStage.off;
    final phase = gate.phaseAt(link.sharedNow());
    if (phase == SkyGatePhase.opening || phase == SkyGatePhase.open) return SkyTogetherStage.opening;
    if (!_visible || !link.together) return SkyTogetherStage.off;
    return switch (phase) {
      SkyGatePhase.idle => SkyTogetherStage.invite,
      SkyGatePhase.holdingAlone => SkyTogetherStage.alone,
      SkyGatePhase.partnerHolding => SkyTogetherStage.partnerHolding,
      SkyGatePhase.together => SkyTogetherStage.together,
      _ => SkyTogetherStage.opening,
    };
  }

  void _sync() {
    if (_disposed) return;
    final next = _stageNow();
    if (next == _stage) return;
    _stage = next;
    notifyListeners();
  }

  bool press() {
    if (_disposed || gate.holding || gate.decided) return false;
    if (_stage == SkyTogetherStage.off || _stage == SkyTogetherStage.opening) return false;
    final event = link.sendHold(down: true);
    gate.press(event.at);
    _lastTick = event.at;
    haptic(HapticKind.tick);
    _sync();
    return true;
  }

  void release() {
    if (_disposed || !gate.holding) return;
    final event = link.sendHold(down: false);
    gate.release(event.at);
    _sync();
  }

  void toggle() {
    if (gate.holding) {
      release();
    } else {
      press();
    }
  }

  double progress() => gate.progressAt(link.sharedNow());

  void tick() {
    if (_disposed || _session != null) return;
    final now = link.sharedNow();
    final last = _lastTick ?? now;
    _lastTick = now;
    if (!link.linked || !link.partnerHere) _lose(now);
    if (gate.beatsBetween(last, now).isNotEmpty) haptic(HapticKind.heartbeat);
    final due = gate.due(now, leader: link.isLeader);
    if (due != null) {
      final id = _idToOpen();
      gate.commit(id, due.at);
      unawaited(link.sendOpen(id, at: due.at));
    }
    final drawing = gate.drawing;
    if (gate.phaseAt(now) == SkyGatePhase.open && drawing != null) {
      if (now - gate.openAt! > gate.graceMs) {
        _callOff();
        release();
        _sync();
        return;
      }
      _open(drawing);
      return;
    }
    _sync();
  }

  void _lose(int now) {
    final drawing = gate.drawing;
    gate.partnerLost(now);
    if (drawing != null && !gate.decided) unawaited(link.sendClose(drawing));
  }

  void _callOff() {
    final drawing = gate.drawing;
    if (drawing == null) return;
    gate.cancel(drawing);
    unawaited(link.sendClose(drawing));
  }

  String _idToOpen() => _unfinished ?? drawings?.newId() ?? 'sky-${generateUrlSafeNonce(12)}';

  void _open(String id) {
    gate.reset();
    _lastTick = null;
    haptic(HapticKind.celebration);
    final session = SkyPatchSession(
      link: link,
      id: id,
      drawings: drawings,
      keyOf: _keyOf,
      haptic: haptic,
      persistDelay: persistDelay,
      nameEvery: nameEvery,
    );
    _session = session;
    _unfinished = id;
    _sync();
    onOpen?.call(session);
  }

  Future<void> endSession() async {
    final session = _session;
    if (session == null) return;
    _session = null;
    _announceHere();
    _sync();
    try {
      await session.leave();
    } finally {
      session.dispose();
    }
    await refreshUnfinished();
  }

  Future<void> refreshUnfinished() async {
    final service = drawings;
    final key = _keyOf();
    if (service == null || key == null || _disposed) return;
    final record = await service.unfinished(key);
    if (_disposed) return;
    if (_session != null && record == null) return;
    _unfinished = record?.id;
  }

  void _hear(SkyTogetherEvent event) {
    if (_disposed) return;
    final active = _session?.id;
    switch (event) {
      case final SkyHoldEvent hold:
        gate.hear(hold);
        _answer(hold);
      case SkyOpenEvent(:final drawing, :final at):
        if (drawing == active) return;
        if (active != null || !gate.accept(drawing, at, link.sharedNow())) {
          release();
          unawaited(link.sendClose(drawing));
          return;
        }
      case SkyCloseEvent(:final drawing):
        if (drawing == active) return;
        gate.cancel(drawing);
      case SkyTouchEvent():
        _felt();
        return;
      default:
        return;
    }
    tick();
  }

  void _answer(SkyHoldEvent hold) {
    final mine = gate.myPressAt;
    if (_session != null || !hold.down || mine == null || hold.at <= mine) return;
    link.sendHold(down: true, at: mine);
  }

  void _onLink() {
    if (_disposed) return;
    if (!link.linked || !link.partnerHere) _lose(link.sharedNow());
    if (!link.here) _callOff();
    if (!link.together && gate.holding) release();
    _sync();
  }

  @override
  void dispose() {
    if (_disposed) return;
    if (gate.holding) link.sendHold(down: false);
    final session = _session;
    _session = null;
    if (session != null) unawaited(session.leave().whenComplete(session.dispose));
    _disposed = true;
    link.removeListener(_onLink);
    unawaited(_events.cancel());
    unawaited(_watch?.cancel());
    super.dispose();
  }
}
