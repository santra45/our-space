import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../models/sky_drawing_record.dart';
import '../crypto/base64.dart';
import 'peer_clock.dart';
import 'sky_together_wire.dart';

abstract class SkyTogetherTransport {
  bool get ready;

  void attach({required void Function() onReadiness, required void Function(Object? event) onEvent});

  void detach();

  Future<bool> send(Map<String, Object?> event);
}

@immutable
class SkyClockSample {
  const SkyClockSample({required this.roundTrip, required this.offset});

  final int roundTrip;
  final int offset;
}

class SkyTogetherLink extends ChangeNotifier {
  SkyTogetherLink({
    required this._transport,
    required this._owner,
    this._clock = const SystemPeerClock(),
    String? tag,
  }) : tag = tag ?? 'tag${generateUrlSafeNonce(9)}' {
    _transport.attach(onReadiness: _onReadiness, onEvent: _onRaw);
    _linked = _transport.ready;
    if (_linked) _startBeat();
  }

  static const int beatMs = 3000;
  static const int staleMs = 8000;
  static const int cursorMs = 50;
  static const int quickReplyMs = 100;
  static const int wantedSamples = 4;
  static const int keptSamples = 8;
  static const int maxRoundTripMs = 10000;
  static const int maxOffsetMs = 24 * 60 * 60 * 1000;

  final SkyTogetherTransport _transport;
  final String? Function() _owner;
  final PeerClock _clock;
  final String tag;

  final StreamController<SkyTogetherEvent> _events = StreamController<SkyTogetherEvent>.broadcast();
  final List<int> _sentStamps = [];
  final List<SkyClockSample> _samples = [];

  Timer? _beat;
  Timer? _stale;
  Timer? _cursorTimer;
  Timer? _reply;
  bool _linked = false;
  bool _here = true;
  bool _foreground = true;
  bool _night = false;
  bool _partnerHere = false;
  bool? _partnerNight;
  String? _partnerOwner;
  String? _partnerTag;
  bool _speaks = false;
  int? _partnerStamp;
  int _partnerStampAt = 0;
  int _lastPresenceAt = 0;
  SkyCursorEvent? _pendingCursor;
  int _lastCursorAt = -cursorMs;
  int _holdSeq = 0;
  int _nameRev = 0;
  bool _disposed = false;

  Stream<SkyTogetherEvent> get events => _events.stream;

  bool get linked => _linked;

  bool get here => _here && _foreground;

  bool get night => _night;

  bool get partnerHere => _linked && _partnerHere;

  bool? get partnerNight => _linked ? _partnerNight : null;

  String? get partnerOwner => _partnerOwner;

  bool get partnerSpeaksSky => _linked && _speaks;

  bool get together => here && partnerHere;

  int get lastPresenceAt => _lastPresenceAt;

  String? get owner => skyOwner(_owner());

  bool? get isLeader {
    final mine = owner;
    final theirs = _partnerOwner;
    if (mine == null || theirs == null) return null;
    final byOwner = mine.compareTo(theirs);
    if (byOwner != 0) return byOwner < 0;
    final theirTag = _partnerTag;
    if (theirTag == null || theirTag == tag) return null;
    return tag.compareTo(theirTag) < 0;
  }

  List<SkyClockSample> get samples => List<SkyClockSample>.unmodifiable(_samples);

  SkyClockSample? get _best {
    SkyClockSample? best;
    for (final sample in _samples) {
      if (best == null || sample.roundTrip < best.roundTrip) best = sample;
    }
    return best;
  }

  int get clockOffset => _best?.offset ?? 0;

  int? get roundTrip => _best?.roundTrip;

  int now() => _clock.now();

  int get _shift => (clockOffset / 2).floor();

  int sharedNow() => now() + _shift;

  int toShared(int local) => local + _shift;

  int toLocal(int shared) => shared - _shift;

  void setPresence({bool? here, bool? night}) {
    var changed = false;
    if (here != null && here != _here) {
      _here = here;
      changed = true;
    }
    if (night != null && night != _night) {
      _night = night;
      changed = true;
    }
    if (!changed || _disposed) return;
    _announce();
    notifyListeners();
  }

  void setForeground(bool value) {
    if (value == _foreground || _disposed) return;
    _foreground = value;
    if (!value) _dropCursor();
    _announce();
    notifyListeners();
  }

  Future<bool> send(SkyTogetherEvent event) {
    if (_disposed || !_linked) return Future<bool>.value(false);
    if (event is! SkyPresenceEvent && !_speaks) return Future<bool>.value(false);
    return _transport.send(event.toWire()).then((ok) => ok, onError: (Object _) => false);
  }

  SkyHoldEvent sendHold({required bool down, int? at}) {
    if (down) _holdSeq = _holdSeq >= maxSkyHoldSeq ? 1 : _holdSeq + 1;
    final event = SkyHoldEvent(down: down, at: at ?? sharedNow(), seq: _holdSeq);
    unawaited(send(event));
    return event;
  }

  Future<bool> sendOpen(String drawing, {required int at}) => send(SkyOpenEvent(drawing: drawing, at: at));

  Future<bool> sendOp(String drawing, SkyDrawingOp op) => send(SkyOpEvent(drawing: drawing, op: op));

  Future<bool> sendState(String drawing, SkyDrawing state) => send(SkyStateEvent(drawing: drawing, state: state));

  Future<bool> sendName(String drawing, String text) {
    _nameRev = _nameRev >= maxSkyNameRev ? 1 : _nameRev + 1;
    final cut = text.length > maxSkyTypedUnits ? text.substring(0, maxSkyTypedUnits) : text;
    return send(SkyNameEvent(drawing: drawing, text: cut, rev: _nameRev));
  }

  Future<bool> sendAgree(String drawing, String text) {
    final clean = cleanSkyName(text);
    if (clean.isEmpty) return Future<bool>.value(false);
    return send(SkyAgreeEvent(drawing: drawing, text: clean));
  }

  Future<bool> sendSaved(String drawing) => send(SkySavedEvent(drawing: drawing));

  Future<bool> sendClose(String drawing) => send(SkyCloseEvent(drawing: drawing));

  void sendCursor(double x, double y, {bool down = true}) {
    if (_disposed || !_linked || !_speaks) return;
    _pendingCursor = SkyCursorEvent(x: skyRound(x), y: skyRound(y), down: down);
    _pumpCursor();
  }

  Future<bool> hideCursor() {
    _dropCursor();
    return send(const SkyCursorEvent.gone());
  }

  void _dropCursor() {
    _pendingCursor = null;
    _cursorTimer?.cancel();
    _cursorTimer = null;
  }

  void _pumpCursor() {
    if (_disposed || _cursorTimer != null || _pendingCursor == null) return;
    final wait = _lastCursorAt + cursorMs - now();
    if (wait > 0) {
      _cursorTimer = _clock.after(Duration(milliseconds: wait), () {
        _cursorTimer = null;
        _pumpCursor();
      });
      return;
    }
    final event = _pendingCursor!;
    _pendingCursor = null;
    _lastCursorAt = now();
    unawaited(send(event));
  }

  void _announce() {
    if (_disposed || !_linked) return;
    final me = owner;
    if (me == null) return;
    final t = now();
    _sentStamps.add(t);
    if (_sentStamps.length > 16) _sentStamps.removeAt(0);
    final echo = _partnerStamp;
    final held = echo == null ? null : t - _partnerStampAt;
    final usable = echo != null && held != null && held >= 0 && held <= maxSkyHeldMs;
    unawaited(send(SkyPresenceEvent(
      here: here,
      night: _night,
      owner: me,
      tag: tag,
      t: t,
      echo: usable ? echo : null,
      held: usable ? held : null,
      sync: _samples.length < wantedSamples,
    )));
  }

  void _onReadiness() {
    if (_disposed) return;
    final ready = _transport.ready;
    if (ready == _linked) return;
    _linked = ready;
    _partnerHere = false;
    _speaks = false;
    _partnerStamp = null;
    _stale?.cancel();
    _stale = null;
    _reply?.cancel();
    _reply = null;
    _dropCursor();
    _beat?.cancel();
    _beat = null;
    if (ready) _startBeat();
    notifyListeners();
  }

  void _startBeat() {
    _beat?.cancel();
    _beat = _clock.every(const Duration(milliseconds: beatMs), _announce);
    _announce();
  }

  void _onRaw(Object? raw) {
    if (_disposed) return;
    if (!_linked) _onReadiness();
    if (!_linked) return;
    final event = SkyTogetherEvent.fromWire(raw);
    if (event == null) return;
    final firstWord = !_speaks;
    _speaks = true;
    if (event is SkyPresenceEvent) {
      _onPresence(event, notify: firstWord);
    } else if (firstWord) {
      notifyListeners();
    }
    if (!_events.isClosed) _events.add(event);
  }

  void _onPresence(SkyPresenceEvent event, {required bool notify}) {
    final at = now();
    var changed = notify;
    final echo = event.echo;
    final held = event.held;
    if (echo != null && held != null && _sentStamps.contains(echo)) {
      final roundTrip = at - echo - held;
      if (roundTrip >= 0 && roundTrip <= maxRoundTripMs) {
        final offset = ((2 * (event.t - at) + roundTrip) / 2).round();
        if (offset.abs() <= maxOffsetMs) {
          final before = clockOffset;
          _samples.add(SkyClockSample(roundTrip: roundTrip, offset: offset));
          if (_samples.length > keptSamples) _samples.removeAt(0);
          if (clockOffset != before) changed = true;
        }
      }
    }
    if (_partnerOwner != event.owner || _partnerTag != event.tag || _partnerNight != event.night) changed = true;
    if (_partnerHere != event.here) changed = true;
    _partnerOwner = event.owner;
    _partnerTag = event.tag;
    _partnerNight = event.night;
    _partnerHere = event.here;
    _partnerStamp = event.t;
    _partnerStampAt = at;
    _lastPresenceAt = at;
    _stale?.cancel();
    _stale = _clock.after(const Duration(milliseconds: staleMs), _goneQuiet);
    if (event.sync && _reply == null) {
      _reply = _clock.after(const Duration(milliseconds: quickReplyMs), () {
        _reply = null;
        _announce();
      });
    }
    if (changed) notifyListeners();
  }

  void _goneQuiet() {
    _stale = null;
    if (_disposed || !_partnerHere) return;
    _partnerHere = false;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    if (_linked && here) {
      _here = false;
      _announce();
    }
    _disposed = true;
    _beat?.cancel();
    _beat = null;
    _stale?.cancel();
    _reply?.cancel();
    _dropCursor();
    _transport.detach();
    unawaited(_events.close());
    super.dispose();
  }
}
