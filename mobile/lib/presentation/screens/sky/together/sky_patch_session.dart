import 'dart:async';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

import '../../../../core/engine.dart';
import '../../../widgets/app_haptics.dart';

typedef SkyHaptic = void Function(HapticKind kind);

void skyAppHaptic(HapticKind kind) => AppHaptics.handler(kind);

VaultKey? _noKey() => null;

enum SkyPatchStep { drawing, naming, saving, saved }

enum SkyPatchNoticeKind { partnerStartedOver, partnerStar, saved }

@immutable
class SkyPatchNotice {
  const SkyPatchNotice(this.kind, [this.star]);

  final SkyPatchNoticeKind kind;
  final String? star;

  @override
  bool operator ==(Object other) => other is SkyPatchNotice && other.kind == kind && other.star == star;

  @override
  int get hashCode => Object.hash(kind, star);
}

@immutable
class SkyPartnerFinger {
  const SkyPartnerFinger({required this.x, required this.y, required this.down});

  final double x;
  final double y;
  final bool down;

  Offset get unit => Offset(x, y);
}

class SkyFingerNotifier extends ValueNotifier<SkyPartnerFinger?> {
  SkyFingerNotifier() : super(null);

  bool _gone = false;

  @override
  set value(SkyPartnerFinger? next) {
    if (_gone) return;
    super.value = next;
  }

  @override
  void addListener(VoidCallback listener) {
    if (!_gone) super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    if (!_gone) super.removeListener(listener);
  }

  @override
  void dispose() {
    if (_gone) return;
    _gone = true;
    super.dispose();
  }
}

class SkyPatchSession extends ChangeNotifier {
  SkyPatchSession({
    required this.link,
    required this.id,
    this.drawings,
    VaultKey? Function()? keyOf,
    this.haptic = skyAppHaptic,
    int? openedAt,
    this.persistDelay = const Duration(milliseconds: 600),
    this.nameEvery = const Duration(milliseconds: 150),
  }) : _keyOf = keyOf ?? _noKey,
       openedAt = openedAt ?? DateTime.now().millisecondsSinceEpoch {
    _events = link.events.listen(_hear);
    link.addListener(_onLink);
    _watch = drawings?.watch().listen((_) => unawaited(_reload()));
    unawaited(_start());
  }

  final SkyTogetherLink link;
  final String id;
  final SkyDrawingService? drawings;
  final VaultKey? Function() _keyOf;
  final SkyHaptic haptic;
  final int openedAt;
  final Duration persistDelay;
  final Duration nameEvery;

  final StreamController<SkyPatchNotice> _notices = StreamController<SkyPatchNotice>.broadcast();
  final SkyFingerNotifier finger = SkyFingerNotifier();

  late final StreamSubscription<SkyTogetherEvent> _events;
  StreamSubscription<void>? _watch;
  Timer? _persistTimer;
  Timer? _nameTimer;
  Future<void>? _persisting;
  SkyDrawing _drawing = SkyDrawing.empty;
  SkyPatchStep _step = SkyPatchStep.drawing;
  bool _loaded = false;
  bool _hadRecord = false;
  bool _partnerAway = false;
  bool _closed = false;
  bool _disposed = false;
  bool _finishing = false;
  bool _typer = false;
  String _name = '';
  String? _savedName;
  int _nameAt = 0;
  int? _partnerRev;
  int? _lastNameSent;
  bool _namePending = false;

  Stream<SkyPatchNotice> get notices => _notices.stream;

  SkyDrawing get drawing => _drawing;

  SkyPatchStep get step => _step;

  bool get loaded => _loaded;

  bool get partnerAway => _partnerAway;

  bool get closed => _closed;

  bool get typer => _typer;

  String get name => _name;

  String? get savedName => _savedName;

  int get nameChangedAt => _nameAt;

  String? get me => link.owner;

  bool get leader => link.isLeader == true;

  bool get canEdit => !_closed && !_partnerAway && _step == SkyPatchStep.drawing && me != null;

  bool get canFinish => _drawing.visibleStars.length >= 2 && _drawing.visibleLines.isNotEmpty;

  bool get canAgree => _step == SkyPatchStep.naming && !_typer && cleanSkyName(_name).isNotEmpty;

  bool mine(SkyDrawnStar star) => star.by == me;

  Future<void> _start() async {
    await _reload();
    if (_disposed) return;
    _loaded = true;
    if (!_closed) unawaited(link.sendState(id, _drawing));
    notifyListeners();
  }

  Future<void> _reload() async {
    final service = drawings;
    final key = _keyOf();
    if (service == null || key == null || _disposed || (_closed && _loaded)) return;
    final record = await service.find(key, id);
    if (record == null || _disposed) return;
    _hadRecord = true;
    _merge(record.drawing);
  }

  bool _merge(SkyDrawing other) {
    final before = _drawing;
    final merged = before.merge(other);
    if (merged == before) return false;
    _drawing = merged;
    if (merged.gen > before.gen && !before.isBlank) _notice(const SkyPatchNotice(SkyPatchNoticeKind.partnerStartedOver));
    _changed();
    return true;
  }

  void _notice(SkyPatchNotice notice) {
    if (!_notices.isClosed) _notices.add(notice);
  }

  void _changed() {
    if (_disposed) return;
    notifyListeners();
    if (leader && !_closed) _schedulePersist();
  }

  SkyDrawnStar? placeStar(double x, double y) {
    final by = me;
    if (!canEdit || by == null) return null;
    final op = _drawing.placeStar(id: 's${generateUrlSafeNonce(9)}', x: x, y: y, by: by, at: link.sharedNow());
    if (op == null) return null;
    _local(op);
    return op.star;
  }

  bool join(String from, String to) {
    final by = me;
    if (!canEdit || by == null) return false;
    final op = _drawing.join(from, to, by: by, at: link.sharedNow());
    if (op == null) return false;
    _local(op);
    return true;
  }

  bool takeAway(String star) {
    final by = me;
    if (!canEdit || by == null) return false;
    final op = _drawing.takeAway(star, by: by);
    if (op == null) return false;
    _local(op);
    return true;
  }

  bool startOver() {
    if (!canEdit || _drawing.isBlank) return false;
    final op = _drawing.startOver();
    if (op == null) return false;
    _local(op);
    return true;
  }

  void _local(SkyDrawingOp op) {
    _drawing = _drawing.apply(op);
    unawaited(link.sendOp(id, op));
    _changed();
  }

  void moveFinger(double x, double y) {
    if (!canEdit) return;
    link.sendCursor(x.clamp(0.0, 1.0), y.clamp(0.0, 1.0));
  }

  void liftFinger() => unawaited(link.hideCursor());

  bool finishDrawing() {
    if (!canEdit || !canFinish) return false;
    _step = SkyPatchStep.naming;
    _typer = true;
    _name = '';
    _nameAt = link.now();
    _lastNameSent = link.now();
    unawaited(link.sendName(id, ''));
    unawaited(link.hideCursor());
    notifyListeners();
    return true;
  }

  void type(String text) {
    if (_step != SkyPatchStep.naming || !_typer || _closed || text == _name) return;
    _name = text;
    _nameAt = link.now();
    _namePending = true;
    notifyListeners();
    _pumpName();
  }

  void _pumpName() {
    if (!_namePending || _nameTimer != null || _disposed) return;
    final last = _lastNameSent;
    final wait = last == null ? 0 : last + nameEvery.inMilliseconds - link.now();
    if (wait > 0) {
      _nameTimer = Timer(Duration(milliseconds: wait), () {
        _nameTimer = null;
        _pumpName();
      });
      return;
    }
    _sendName();
  }

  void _sendName() {
    _nameTimer?.cancel();
    _nameTimer = null;
    if (!_namePending) return;
    _namePending = false;
    _lastNameSent = link.now();
    unawaited(link.sendName(id, _name));
  }

  void changeIt() {
    if (_step != SkyPatchStep.naming || _typer || _closed || _partnerAway) return;
    _typer = true;
    _nameAt = link.now();
    _namePending = true;
    _lastNameSent = null;
    notifyListeners();
    _sendName();
  }

  Future<bool> agree() async {
    if (!canAgree || _closed || _partnerAway) return false;
    final clean = cleanSkyName(_name);
    _savedName = clean;
    unawaited(link.sendAgree(id, clean));
    if (leader) return _finish(clean);
    _step = SkyPatchStep.saving;
    notifyListeners();
    return true;
  }

  void backToDrawing() {
    if (_step != SkyPatchStep.naming || _closed || _partnerAway) return;
    _sendName();
    _step = SkyPatchStep.drawing;
    _typer = false;
    unawaited(link.sendOpen(id, at: link.sharedNow()));
    notifyListeners();
  }

  Future<bool> _finish(String name) async {
    if (_finishing || _step == SkyPatchStep.saved) return false;
    final service = drawings;
    final key = _keyOf();
    if (service == null || key == null) return false;
    _finishing = true;
    _step = SkyPatchStep.saving;
    _persistTimer?.cancel();
    _persistTimer = null;
    notifyListeners();
    try {
      await _persisting;
      final record = await service.finish(key, id: id, drawing: _drawing, name: name);
      _savedName = record.name;
    } catch (_) {
      _finishing = false;
      if (!_disposed && _step == SkyPatchStep.saving) {
        _step = SkyPatchStep.naming;
        notifyListeners();
      }
      return false;
    }
    if (_disposed) return true;
    unawaited(link.sendSaved(id));
    _saved();
    return true;
  }

  void _saved() {
    if (_step == SkyPatchStep.saved || _disposed) return;
    _step = SkyPatchStep.saved;
    _partnerAway = false;
    finger.value = null;
    haptic(HapticKind.celebration);
    _notice(const SkyPatchNotice(SkyPatchNoticeKind.saved));
    notifyListeners();
  }

  void _hear(SkyTogetherEvent event) {
    if (_disposed || _closed) return;
    switch (event) {
      case SkyOpEvent(:final drawing, :final op) when drawing == id:
        _heardOp(op);
      case SkyStateEvent(:final drawing, :final state) when drawing == id:
        _heardState(state);
      case final SkyCursorEvent cursor:
        _heardCursor(cursor);
      case final SkyNameEvent named when named.drawing == id:
        _heardName(named);
      case SkyAgreeEvent(:final drawing, :final text) when drawing == id:
        _heardAgree(text);
      case SkySavedEvent(:final drawing) when drawing == id:
        _savedName ??= cleanSkyName(_name);
        _saved();
      case SkyCloseEvent(:final drawing) when drawing == id:
        _away();
      case SkyOpenEvent(:final drawing) when drawing == id:
        _heardBack();
      default:
        return;
    }
  }

  void _heardOp(SkyDrawingOp op) {
    final before = _drawing;
    final next = before.apply(op);
    if (next == before) return;
    _drawing = next;
    if (op is SkyStartOver && next.gen > before.gen) {
      _notice(const SkyPatchNotice(SkyPatchNoticeKind.partnerStartedOver));
    } else if (op is SkyAddStar && next.visibleStar(op.star.id) != null) {
      _notice(SkyPatchNotice(SkyPatchNoticeKind.partnerStar, op.star.id));
    }
    _changed();
  }

  void _heardState(SkyDrawing state) {
    _merge(state);
    if (_drawing != state && _loaded) unawaited(link.sendState(id, _drawing));
  }

  void _heardCursor(SkyCursorEvent event) {
    if (event.gone || _step != SkyPatchStep.drawing) {
      finger.value = null;
      return;
    }
    finger.value = SkyPartnerFinger(x: event.x!, y: event.y!, down: event.down);
  }

  void _heardName(SkyNameEvent event) {
    final rev = _partnerRev;
    if (rev != null && event.rev <= rev) return;
    _partnerRev = event.rev;
    if (_step == SkyPatchStep.saving || _step == SkyPatchStep.saved) return;
    final wasTyper = _typer && _step == SkyPatchStep.naming;
    _step = SkyPatchStep.naming;
    finger.value = null;
    if (wasTyper && event.text.trim().isEmpty && _name.trim().isEmpty && leader) {
      _namePending = true;
      _lastNameSent = null;
      _sendName();
      notifyListeners();
      return;
    }
    _typer = false;
    _namePending = false;
    _nameTimer?.cancel();
    _nameTimer = null;
    _name = event.text;
    _nameAt = link.now();
    notifyListeners();
  }

  void _heardAgree(String text) {
    if (_step == SkyPatchStep.saved) return;
    _savedName = text;
    if (leader) {
      unawaited(_finish(text));
      return;
    }
    _step = SkyPatchStep.saving;
    notifyListeners();
  }

  void _heardBack() {
    if (_step != SkyPatchStep.naming) return;
    _step = SkyPatchStep.drawing;
    _typer = false;
    notifyListeners();
  }

  void _away() {
    if (_closed || _partnerAway || _step == SkyPatchStep.saved) return;
    _partnerAway = true;
    finger.value = null;
    notifyListeners();
    if (leader) unawaited(flush());
  }

  void _onLink() {
    if (_disposed) return;
    if (!link.linked || !link.partnerHere) _away();
  }

  bool get _worthKeeping => !_drawing.isBlank || _drawing.gen > 0 || _hadRecord;

  void _schedulePersist() {
    if (_finishing || _step == SkyPatchStep.saved) return;
    _persistTimer?.cancel();
    if (persistDelay == Duration.zero) {
      _persistTimer = null;
      unawaited(_persist());
      return;
    }
    _persistTimer = Timer(persistDelay, () {
      _persistTimer = null;
      unawaited(_persist());
    });
  }

  Future<void> _persist() async {
    final service = drawings;
    final key = _keyOf();
    if (service == null || key == null || !leader || _finishing || _step == SkyPatchStep.saved) return;
    if (!_worthKeeping) return;
    final previous = _persisting;
    final run = () async {
      await previous;
      try {
        await service.saveProgress(key, id: id, drawing: _drawing, startedAt: openedAt);
        _hadRecord = true;
      } catch (_) {}
    }();
    _persisting = run;
    await run;
  }

  Future<void> flush() async {
    _persistTimer?.cancel();
    _persistTimer = null;
    if (leader) await _persist();
    await _persisting;
  }

  Future<void> leave() async {
    if (_closed) return;
    _sendName();
    _closed = true;
    finger.value = null;
    if (_step != SkyPatchStep.saved) unawaited(link.sendClose(id));
    unawaited(link.hideCursor());
    if (!_disposed) notifyListeners();
    await flush();
  }

  bool get disposed => _disposed;

  @override
  void addListener(VoidCallback listener) {
    if (!_disposed) super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    if (!_disposed) super.removeListener(listener);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _closed = true;
    _persistTimer?.cancel();
    _nameTimer?.cancel();
    unawaited(_events.cancel());
    unawaited(_watch?.cancel());
    link.removeListener(_onLink);
    unawaited(_notices.close());
    finger.dispose();
    super.dispose();
  }
}
