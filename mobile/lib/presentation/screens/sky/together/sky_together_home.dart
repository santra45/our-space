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
    _watch = drawings?.watch().listen((_) => unawaited(refreshUnfinished()));
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

  late final StreamSubscription<SkyTogetherEvent> _events;
  StreamSubscription<void>? _watch;
  SkyTogetherStage _stage = SkyTogetherStage.off;
  SkyPatchSession? _session;
  String? _unfinished;
  int? _lastTick;
  bool _visible = true;
  bool _ready = true;
  bool _disposed = false;

  void Function(SkyPatchSession session)? onOpen;

  SkyTogetherStage get stage => _stage;

  SkyPatchSession? get session => _session;

  String? get unfinishedId => _unfinished;

  bool get holding => gate.holding;

  bool get partnerHolding => gate.partnerHolding;

  bool get needsTicks => gate.holding || gate.partnerHolding || gate.decided;

  bool get visible => _visible;

  void present({required bool visible, required bool night}) {
    if (_disposed) return;
    if (!visible) release();
    _visible = visible;
    link.setPresence(here: visible || _session != null, night: night);
    _sync();
  }

  bool get ready => _ready;

  set ready(bool value) {
    if (value == _ready || _disposed) return;
    _ready = value;
    if (!value) release();
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
    if (!_visible || !_ready || !link.together) return SkyTogetherStage.off;
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
    if (_disposed || gate.holding) return false;
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
    if (!link.linked || !link.partnerHere) gate.partnerLost(now);
    if (gate.beatsBetween(last, now).isNotEmpty) haptic(HapticKind.heartbeat);
    final due = gate.due(now, leader: link.isLeader);
    if (due != null) {
      final id = _idToOpen();
      gate.commit(id, due.at);
      unawaited(link.sendOpen(id, at: due.at));
    }
    if (gate.phaseAt(now) == SkyGatePhase.open && gate.drawing != null) {
      _open(gate.drawing!);
      return;
    }
    _sync();
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
        if (active != null) return;
        gate.hear(hold);
      case SkyOpenEvent(:final drawing, :final at):
        if (drawing == active) return;
        if (active != null || !gate.accept(drawing, at, link.sharedNow())) {
          unawaited(link.sendClose(drawing));
          return;
        }
      case SkyCloseEvent(:final drawing):
        if (drawing == active) return;
        gate.cancel(drawing);
      default:
        return;
    }
    tick();
  }

  void _onLink() {
    if (_disposed) return;
    if (!link.linked || !link.partnerHere) gate.partnerLost(link.sharedNow());
    if (!link.together && gate.holding) release();
    _sync();
  }

  @override
  void dispose() {
    if (_disposed) return;
    release();
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
