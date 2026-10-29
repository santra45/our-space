import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../models/sky_drawing_record.dart';

const int skyTogetherVersion = 1;
const int maxSkyTypedUnits = skyDrawingMaxName * 4;
const int maxSkyEventKeys = 12;
const int maxSkyHeldMs = 60000;
const int maxSkyHoldSeq = 2147483647;
const int maxSkyNameRev = 2147483647;

bool? _flag(Object? value) => value is bool ? value : null;

String? _tag(Object? value) => value is String && value.length >= 4 ? skyId(value) : null;

@immutable
sealed class SkyTogetherEvent {
  const SkyTogetherEvent();

  String get kind;

  Map<String, Object?> get body;

  Map<String, Object?> toWire() => {'v': skyTogetherVersion, 'k': kind, ...body};

  static SkyTogetherEvent? fromWire(Object? raw) {
    if (raw is! Map || raw.length > maxSkyEventKeys) return null;
    final version = raw['v'];
    if (version is! int || version != skyTogetherVersion) return null;
    try {
      return switch (raw['k']) {
        'presence' => SkyPresenceEvent._read(raw),
        'hold' => SkyHoldEvent._read(raw),
        'open' => SkyOpenEvent._read(raw),
        'op' => SkyOpEvent._read(raw),
        'state' => SkyStateEvent._read(raw),
        'cursor' => SkyCursorEvent._read(raw),
        'name' => SkyNameEvent._read(raw),
        'agree' => SkyAgreeEvent._read(raw),
        'saved' => SkySavedEvent._read(raw),
        'close' => SkyCloseEvent._read(raw),
        _ => null,
      };
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is SkyTogetherEvent && other.runtimeType == runtimeType && jsonEncode(other.toWire()) == jsonEncode(toWire());

  @override
  int get hashCode => jsonEncode(toWire()).hashCode;

  @override
  String toString() => 'SkyTogetherEvent(${jsonEncode(toWire())})';
}

final class SkyPresenceEvent extends SkyTogetherEvent {
  const SkyPresenceEvent({
    required this.here,
    required this.night,
    required this.owner,
    required this.tag,
    required this.t,
    this.echo,
    this.held,
    this.sync = false,
  });

  final bool here;
  final bool night;
  final String owner;
  final String tag;
  final int t;
  final int? echo;
  final int? held;
  final bool sync;

  @override
  String get kind => 'presence';

  @override
  Map<String, Object?> get body => {
    'here': here,
    'night': night,
    'owner': owner,
    'tag': tag,
    't': t,
    if (echo != null && held != null) 'echo': echo,
    if (echo != null && held != null) 'held': held,
    if (sync) 'sync': true,
  };

  static SkyPresenceEvent? _read(Map<Object?, Object?> raw) {
    final here = _flag(raw['here']);
    final night = _flag(raw['night']);
    final owner = skyOwner(raw['owner']);
    final tag = _tag(raw['tag']);
    final t = skyInt(raw['t']);
    final rawEcho = raw['echo'];
    final rawHeld = raw['held'];
    final rawSync = raw['sync'] ?? false;
    if (here == null || night == null || owner == null || tag == null || t == null || rawSync is! bool) return null;
    if ((rawEcho == null) != (rawHeld == null)) return null;
    int? echo;
    int? held;
    if (rawEcho != null) {
      echo = skyInt(rawEcho);
      held = skyInt(rawHeld, max: maxSkyHeldMs);
      if (echo == null || held == null) return null;
    }
    return SkyPresenceEvent(
      here: here,
      night: night,
      owner: owner,
      tag: tag,
      t: t,
      echo: echo,
      held: held,
      sync: rawSync,
    );
  }
}

final class SkyHoldEvent extends SkyTogetherEvent {
  const SkyHoldEvent({required this.down, required this.at, required this.seq});

  final bool down;
  final int at;
  final int seq;

  @override
  String get kind => 'hold';

  @override
  Map<String, Object?> get body => {'down': down, 'at': at, 'seq': seq};

  static SkyHoldEvent? _read(Map<Object?, Object?> raw) {
    final down = _flag(raw['down']);
    final at = skyInt(raw['at']);
    final seq = skyInt(raw['seq'], max: maxSkyHoldSeq);
    if (down == null || at == null || seq == null) return null;
    return SkyHoldEvent(down: down, at: at, seq: seq);
  }
}

final class SkyOpenEvent extends SkyTogetherEvent {
  const SkyOpenEvent({required this.drawing, required this.at});

  final String drawing;
  final int at;

  @override
  String get kind => 'open';

  @override
  Map<String, Object?> get body => {'drawing': drawing, 'at': at};

  static SkyOpenEvent? _read(Map<Object?, Object?> raw) {
    final drawing = skyId(raw['drawing']);
    final at = skyInt(raw['at']);
    if (drawing == null || at == null) return null;
    return SkyOpenEvent(drawing: drawing, at: at);
  }
}

final class SkyOpEvent extends SkyTogetherEvent {
  const SkyOpEvent({required this.drawing, required this.op});

  final String drawing;
  final SkyDrawingOp op;

  @override
  String get kind => 'op';

  @override
  Map<String, Object?> get body => {'drawing': drawing, 'op': op.toJson()};

  static SkyOpEvent? _read(Map<Object?, Object?> raw) {
    final drawing = skyId(raw['drawing']);
    final op = SkyDrawingOp.fromJson(raw['op']);
    if (drawing == null || op == null) return null;
    return SkyOpEvent(drawing: drawing, op: op);
  }
}

final class SkyStateEvent extends SkyTogetherEvent {
  const SkyStateEvent({required this.drawing, required this.state});

  final String drawing;
  final SkyDrawing state;

  @override
  String get kind => 'state';

  @override
  Map<String, Object?> get body => {'drawing': drawing, 'state': state.toJson()};

  static SkyStateEvent? _read(Map<Object?, Object?> raw) {
    final drawing = skyId(raw['drawing']);
    final state = SkyDrawing.fromJson(raw['state']);
    if (drawing == null || state == null) return null;
    return SkyStateEvent(drawing: drawing, state: state);
  }
}

final class SkyCursorEvent extends SkyTogetherEvent {
  const SkyCursorEvent({required double this.x, required double this.y, this.down = true}) : gone = false;

  const SkyCursorEvent.gone() : x = null, y = null, down = false, gone = true;

  final double? x;
  final double? y;
  final bool down;
  final bool gone;

  @override
  String get kind => 'cursor';

  @override
  Map<String, Object?> get body => gone ? {'gone': true} : {'x': x, 'y': y, 'down': down};

  static SkyCursorEvent? _read(Map<Object?, Object?> raw) {
    if (raw['gone'] == true) {
      if (raw.containsKey('x') || raw.containsKey('y')) return null;
      return const SkyCursorEvent.gone();
    }
    if (raw.containsKey('gone') && raw['gone'] != false) return null;
    final x = skyUnit(raw['x']);
    final y = skyUnit(raw['y']);
    final down = _flag(raw['down'] ?? true);
    if (x == null || y == null || down == null) return null;
    return SkyCursorEvent(x: x, y: y, down: down);
  }
}

final class SkyNameEvent extends SkyTogetherEvent {
  const SkyNameEvent({required this.drawing, required this.text, required this.rev, this.take = false});

  final String drawing;
  final String text;
  final int rev;
  final bool take;

  String get clean => cleanSkyName(text);

  @override
  String get kind => 'name';

  @override
  Map<String, Object?> get body => {'drawing': drawing, 'text': text, 'rev': rev, if (take) 'take': true};

  static SkyNameEvent? _read(Map<Object?, Object?> raw) {
    final drawing = skyId(raw['drawing']);
    final text = raw['text'];
    final rev = skyInt(raw['rev'], max: maxSkyNameRev);
    final take = raw['take'] ?? false;
    if (drawing == null || text is! String || text.length > maxSkyTypedUnits || rev == null || take is! bool) {
      return null;
    }
    if (skyHasLoneSurrogate(text)) return null;
    return SkyNameEvent(drawing: drawing, text: text, rev: rev, take: take);
  }
}

final class SkyAgreeEvent extends SkyTogetherEvent {
  const SkyAgreeEvent({required this.drawing, required this.text});

  final String drawing;
  final String text;

  @override
  String get kind => 'agree';

  @override
  Map<String, Object?> get body => {'drawing': drawing, 'text': text};

  static SkyAgreeEvent? _read(Map<Object?, Object?> raw) {
    final drawing = skyId(raw['drawing']);
    final text = raw['text'];
    if (drawing == null || text is! String || text.length > maxSkyTypedUnits || skyHasLoneSurrogate(text)) return null;
    final clean = cleanSkyName(text);
    if (clean.isEmpty) return null;
    return SkyAgreeEvent(drawing: drawing, text: clean);
  }
}

final class SkySavedEvent extends SkyTogetherEvent {
  const SkySavedEvent({required this.drawing});

  final String drawing;

  @override
  String get kind => 'saved';

  @override
  Map<String, Object?> get body => {'drawing': drawing};

  static SkySavedEvent? _read(Map<Object?, Object?> raw) {
    final drawing = skyId(raw['drawing']);
    return drawing == null ? null : SkySavedEvent(drawing: drawing);
  }
}

final class SkyCloseEvent extends SkyTogetherEvent {
  const SkyCloseEvent({required this.drawing});

  final String drawing;

  @override
  String get kind => 'close';

  @override
  Map<String, Object?> get body => {'drawing': drawing};

  static SkyCloseEvent? _read(Map<Object?, Object?> raw) {
    final drawing = skyId(raw['drawing']);
    return drawing == null ? null : SkyCloseEvent(drawing: drawing);
  }
}
