import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'plain_record.dart';

const int skyDrawingMaxStars = 30;
const int skyDrawingMaxLines = 40;
const int skyDrawingMaxName = 40;
const int skyDrawingKeptStars = 60;
const int skyDrawingKeptLines = 80;
const int skyDrawingKeptRemoved = 160;
const int skyDrawingMaxGeneration = 1000000;
const int skyDrawingMaxRemoveIds = 8;
const int skyMaxTime = 9007199254740991;
const int skyNightCutoffHour = 5;
const double skyStarSpacing = 0.035;
const double skyPatchEdge = 0.04;

final RegExp skyIdPattern = RegExp(r'^[A-Za-z0-9_-]{1,48}$');
final RegExp skyOwnerPattern = RegExp(r'^[A-Za-z0-9_-]{8,64}$');
final RegExp skyNightPattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');
final RegExp _skyLinePattern = RegExp(r'^[A-Za-z0-9_-]{1,48}~[A-Za-z0-9_-]{1,48}$');
final RegExp _skyControl = RegExp(r'[\u0000-\u001F\u007F]');
final RegExp _skySpaces = RegExp(r'\s+');

int? skyInt(Object? value, {int min = 0, int max = skyMaxTime}) {
  int? out;
  if (value is int) {
    out = value;
  } else if (value is double && value.isFinite && value == value.truncateToDouble() && value.abs() <= skyMaxTime) {
    out = value.toInt();
  }
  if (out == null || out < min || out > max) return null;
  return out;
}

double? skyUnit(Object? value) {
  if (value is! num || !value.isFinite || value < 0 || value > 1) return null;
  return value.toDouble();
}

double skyRound(double value) {
  final clamped = value.isFinite ? value.clamp(0.0, 1.0) : 0.5;
  return (clamped * 10000).round() / 10000;
}

String? skyId(Object? value) => value is String && skyIdPattern.hasMatch(value) ? value : null;

String? skyOwner(Object? value) => value is String && skyOwnerPattern.hasMatch(value) ? value : null;

String skyLineKey(String one, String two) => one.compareTo(two) <= 0 ? '$one~$two' : '$two~$one';

bool isSkyRemovalKey(Object? value) =>
    value is String && (skyIdPattern.hasMatch(value) || _skyLinePattern.hasMatch(value));

bool skyHasLoneSurrogate(String text) {
  for (var i = 0; i < text.length; i++) {
    final unit = text.codeUnitAt(i);
    if (unit < 0xD800 || unit > 0xDFFF) continue;
    if (unit > 0xDBFF || i + 1 >= text.length) return true;
    final next = text.codeUnitAt(i + 1);
    if (next < 0xDC00 || next > 0xDFFF) return true;
    i++;
  }
  return false;
}

String skyWholeText(String text) {
  if (!skyHasLoneSurrogate(text)) return text;
  return String.fromCharCodes(text.runes.where((rune) => rune < 0xD800 || rune > 0xDFFF));
}

String cleanSkyName(String raw) {
  final collapsed = skyWholeText(raw).replaceAll(_skyControl, ' ').replaceAll(_skySpaces, ' ').trim();
  final runes = collapsed.runes.toList(growable: false);
  if (runes.length <= skyDrawingMaxName) return collapsed;
  return String.fromCharCodes(runes.take(skyDrawingMaxName)).trim();
}

String skyNightOf(int ms) {
  final local = DateTime.fromMillisecondsSinceEpoch(ms);
  final day = local.hour < skyNightCutoffHour ? local.subtract(const Duration(hours: skyNightCutoffHour)) : local;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${day.year.toString().padLeft(4, '0')}-${two(day.month)}-${two(day.day)}';
}

int _orderStars(SkyDrawnStar a, SkyDrawnStar b) {
  if (a.at != b.at) return a.at.compareTo(b.at);
  final byId = a.id.compareTo(b.id);
  if (byId != 0) return byId;
  final byOwner = a.by.compareTo(b.by);
  if (byOwner != 0) return byOwner;
  if (a.x != b.x) return a.x.compareTo(b.x);
  if (a.y != b.y) return a.y.compareTo(b.y);
  return a.gen.compareTo(b.gen);
}

int _orderLines(SkyDrawnLine a, SkyDrawnLine b) {
  if (a.at != b.at) return a.at.compareTo(b.at);
  final byKey = a.key.compareTo(b.key);
  if (byKey != 0) return byKey;
  final byOwner = a.by.compareTo(b.by);
  if (byOwner != 0) return byOwner;
  return a.gen.compareTo(b.gen);
}

@immutable
class SkyDrawnStar implements Comparable<SkyDrawnStar> {
  const SkyDrawnStar({
    required this.id,
    required this.x,
    required this.y,
    required this.by,
    required this.at,
    required this.gen,
  });

  final String id;
  final double x;
  final double y;
  final String by;
  final int at;
  final int gen;

  Map<String, Object?> toJson() => {'id': id, 'x': x, 'y': y, 'by': by, 'at': at, 'g': gen};

  static SkyDrawnStar? fromJson(Object? raw) {
    if (raw is! Map || raw.length > 8) return null;
    final id = skyId(raw['id']);
    final x = skyUnit(raw['x']);
    final y = skyUnit(raw['y']);
    final by = skyOwner(raw['by']);
    final at = skyInt(raw['at']);
    final gen = skyInt(raw['g'], max: skyDrawingMaxGeneration);
    if (id == null || x == null || y == null || by == null || at == null || gen == null) return null;
    return SkyDrawnStar(id: id, x: x, y: y, by: by, at: at, gen: gen);
  }

  @override
  int compareTo(SkyDrawnStar other) => _orderStars(this, other);

  @override
  bool operator ==(Object other) =>
      other is SkyDrawnStar &&
      other.id == id &&
      other.x == x &&
      other.y == y &&
      other.by == by &&
      other.at == at &&
      other.gen == gen;

  @override
  int get hashCode => Object.hash(id, x, y, by, at, gen);

  @override
  String toString() => 'SkyDrawnStar($id, $x, $y, $by, $at, $gen)';
}

@immutable
class SkyDrawnLine implements Comparable<SkyDrawnLine> {
  const SkyDrawnLine._(this.a, this.b, this.by, this.at, this.gen);

  factory SkyDrawnLine({
    required String from,
    required String to,
    required String by,
    required int at,
    required int gen,
  }) => from.compareTo(to) <= 0 ? SkyDrawnLine._(from, to, by, at, gen) : SkyDrawnLine._(to, from, by, at, gen);

  final String a;
  final String b;
  final String by;
  final int at;
  final int gen;

  String get key => '$a~$b';

  bool touches(String star) => a == star || b == star;

  Map<String, Object?> toJson() => {'a': a, 'b': b, 'by': by, 'at': at, 'g': gen};

  static SkyDrawnLine? fromJson(Object? raw) {
    if (raw is! Map || raw.length > 7) return null;
    final a = skyId(raw['a']);
    final b = skyId(raw['b']);
    final by = skyOwner(raw['by']);
    final at = skyInt(raw['at']);
    final gen = skyInt(raw['g'], max: skyDrawingMaxGeneration);
    if (a == null || b == null || a == b || by == null || at == null || gen == null) return null;
    return SkyDrawnLine(from: a, to: b, by: by, at: at, gen: gen);
  }

  @override
  int compareTo(SkyDrawnLine other) => _orderLines(this, other);

  @override
  bool operator ==(Object other) =>
      other is SkyDrawnLine && other.a == a && other.b == b && other.by == by && other.at == at && other.gen == gen;

  @override
  int get hashCode => Object.hash(a, b, by, at, gen);

  @override
  String toString() => 'SkyDrawnLine($a~$b, $by, $at, $gen)';
}

@immutable
class SkyDrawing {
  SkyDrawing._(this.gen, this.stars, this.lines, this.removed);

  factory SkyDrawing({
    int gen = 0,
    Iterable<SkyDrawnStar> stars = const [],
    Iterable<SkyDrawnLine> lines = const [],
    Iterable<String> removed = const [],
  }) {
    final g = gen.clamp(0, skyDrawingMaxGeneration);
    final keptRemoved = {for (final key in removed) if (isSkyRemovalKey(key)) key}.toList()..sort();
    final gone = keptRemoved.take(skyDrawingKeptRemoved).toSet();
    final starsById = <String, SkyDrawnStar>{};
    for (final star in stars) {
      if (star.gen != g || gone.contains(star.id)) continue;
      final held = starsById[star.id];
      if (held == null || _orderStars(star, held) < 0) starsById[star.id] = star;
    }
    final linesByKey = <String, SkyDrawnLine>{};
    for (final line in lines) {
      if (line.gen != g || gone.contains(line.key) || gone.contains(line.a) || gone.contains(line.b)) continue;
      final held = linesByKey[line.key];
      if (held == null || _orderLines(line, held) < 0) linesByKey[line.key] = line;
    }
    final keptStars = starsById.values.toList()..sort(_orderStars);
    final keptLines = linesByKey.values.toList()..sort(_orderLines);
    return SkyDrawing._(
      g,
      Map<String, SkyDrawnStar>.unmodifiable({for (final s in keptStars.take(skyDrawingKeptStars)) s.id: s}),
      Map<String, SkyDrawnLine>.unmodifiable({for (final l in keptLines.take(skyDrawingKeptLines)) l.key: l}),
      Set<String>.unmodifiable(gone),
    );
  }

  static final SkyDrawing empty = SkyDrawing();

  final int gen;
  final Map<String, SkyDrawnStar> stars;
  final Map<String, SkyDrawnLine> lines;
  final Set<String> removed;

  late final List<SkyDrawnStar> visibleStars = List<SkyDrawnStar>.unmodifiable(
    stars.values.where((s) => !removed.contains(s.id)).take(skyDrawingMaxStars),
  );

  late final Set<String> _visibleIds = {for (final s in visibleStars) s.id};

  late final List<SkyDrawnLine> visibleLines = List<SkyDrawnLine>.unmodifiable(
    lines.values
        .where((l) => !removed.contains(l.key) && _visibleIds.contains(l.a) && _visibleIds.contains(l.b))
        .take(skyDrawingMaxLines),
  );

  bool get isBlank => visibleStars.isEmpty;

  bool get starsFull => visibleStars.length >= skyDrawingMaxStars || stars.length >= skyDrawingKeptStars;

  bool get linesFull => visibleLines.length >= skyDrawingMaxLines || lines.length >= skyDrawingKeptLines;

  bool get removalsFull => removed.length >= skyDrawingKeptRemoved;

  SkyDrawnStar? visibleStar(String id) => _visibleIds.contains(id) ? stars[id] : null;

  bool isLinked(String one, String two) => visibleLines.any((l) => l.key == skyLineKey(one, two));

  SkyDrawing merge(SkyDrawing other) {
    if (identical(this, other)) return this;
    final g = math.max(gen, other.gen);
    final parts = [this, other].where((d) => d.gen == g).toList(growable: false);
    return SkyDrawing(
      gen: g,
      stars: [for (final d in parts) ...d.stars.values],
      lines: [for (final d in parts) ...d.lines.values],
      removed: [for (final d in parts) ...d.removed],
    );
  }

  SkyDrawing apply(SkyDrawingOp op) => merge(op.asDrawing);

  SkyDrawing settled() => SkyDrawing(gen: gen, stars: visibleStars, lines: visibleLines);

  SkyDrawnStar? starNear(double x, double y, {double radius = 0.06}) {
    SkyDrawnStar? best;
    var bestDistance = radius;
    for (final star in visibleStars) {
      final distance = math.sqrt(math.pow(star.x - x, 2) + math.pow(star.y - y, 2));
      if (distance <= bestDistance) {
        best = star;
        bestDistance = distance;
      }
    }
    return best;
  }

  static double snap(double value) => skyRound(value.isFinite ? value.clamp(skyPatchEdge, 1 - skyPatchEdge) : 0.5);

  SkyAddStar? placeStar({
    required String id,
    required double x,
    required double y,
    required String by,
    required int at,
  }) {
    if (skyId(id) == null || skyOwner(by) == null || skyInt(at) == null) return null;
    if (starsFull || stars.containsKey(id) || removed.contains(id)) return null;
    final sx = snap(x);
    final sy = snap(y);
    if (starNear(sx, sy, radius: skyStarSpacing) != null) return null;
    return SkyAddStar(SkyDrawnStar(id: id, x: sx, y: sy, by: by, at: at, gen: gen));
  }

  SkyLink? join(String from, String to, {required String by, required int at}) {
    if (from == to || skyOwner(by) == null || skyInt(at) == null) return null;
    if (visibleStar(from) == null || visibleStar(to) == null) return null;
    if (linesFull || lines.containsKey(skyLineKey(from, to)) || removed.contains(skyLineKey(from, to))) return null;
    return SkyLink(SkyDrawnLine(from: from, to: to, by: by, at: at, gen: gen));
  }

  SkyRemove? takeAway(String id, {required String by}) {
    final star = visibleStar(id);
    if (star == null || star.by != by || removalsFull) return null;
    return SkyRemove([id], gen: gen);
  }

  SkyStartOver? startOver() {
    if (gen >= skyDrawingMaxGeneration) return null;
    return SkyStartOver(gen + 1);
  }

  Map<String, Object?> toJson() => {
    'g': gen,
    'stars': [for (final s in stars.values) s.toJson()],
    'lines': [for (final l in lines.values) l.toJson()],
    'removed': removed.toList(growable: false),
  };

  static SkyDrawing? fromJson(Object? raw) {
    if (raw is! Map || raw.length > 6) return null;
    return fromParts(gen: raw['g'], stars: raw['stars'], lines: raw['lines'], removed: raw['removed']);
  }

  static SkyDrawing? fromParts({Object? gen, Object? stars, Object? lines, Object? removed}) {
    final g = skyInt(gen ?? 0, max: skyDrawingMaxGeneration);
    final rawStars = stars ?? const <Object?>[];
    final rawLines = lines ?? const <Object?>[];
    final rawRemoved = removed ?? const <Object?>[];
    if (g == null || rawStars is! List || rawLines is! List || rawRemoved is! List) return null;
    if (rawStars.length > skyDrawingKeptStars ||
        rawLines.length > skyDrawingKeptLines ||
        rawRemoved.length > skyDrawingKeptRemoved) {
      return null;
    }
    final parsedStars = <SkyDrawnStar>[];
    for (final item in rawStars) {
      final star = SkyDrawnStar.fromJson(item);
      if (star == null || star.gen != g) return null;
      parsedStars.add(star);
    }
    final parsedLines = <SkyDrawnLine>[];
    for (final item in rawLines) {
      final line = SkyDrawnLine.fromJson(item);
      if (line == null || line.gen != g) return null;
      parsedLines.add(line);
    }
    final parsedRemoved = <String>[];
    for (final item in rawRemoved) {
      if (!isSkyRemovalKey(item)) return null;
      parsedRemoved.add(item as String);
    }
    return SkyDrawing(gen: g, stars: parsedStars, lines: parsedLines, removed: parsedRemoved);
  }

  @override
  bool operator ==(Object other) =>
      other is SkyDrawing &&
      other.gen == gen &&
      mapEquals(other.stars, stars) &&
      mapEquals(other.lines, lines) &&
      setEquals(other.removed, removed);

  @override
  int get hashCode => Object.hash(
    gen,
    Object.hashAllUnordered(stars.values),
    Object.hashAllUnordered(lines.values),
    Object.hashAllUnordered(removed),
  );

  @override
  String toString() => 'SkyDrawing(gen: $gen, stars: ${stars.length}, lines: ${lines.length}, removed: ${removed.length})';
}

sealed class SkyDrawingOp {
  const SkyDrawingOp(this.gen);

  final int gen;

  SkyDrawing get asDrawing;

  Map<String, Object?> toJson();

  static SkyDrawingOp? fromJson(Object? raw) {
    if (raw is! Map || raw.length > 4) return null;
    switch (raw['o']) {
      case 'star':
        final star = SkyDrawnStar.fromJson(raw['star']);
        return star == null ? null : SkyAddStar(star);
      case 'line':
        final line = SkyDrawnLine.fromJson(raw['line']);
        return line == null ? null : SkyLink(line);
      case 'remove':
        final gen = skyInt(raw['g'], max: skyDrawingMaxGeneration);
        final ids = raw['ids'];
        if (gen == null || ids is! List || ids.isEmpty || ids.length > skyDrawingMaxRemoveIds) return null;
        if (!ids.every(isSkyRemovalKey)) return null;
        return SkyRemove([for (final id in ids) id as String], gen: gen);
      case 'clear':
        final gen = skyInt(raw['g'], min: 1, max: skyDrawingMaxGeneration);
        return gen == null ? null : SkyStartOver(gen);
      default:
        return null;
    }
  }
}

final class SkyAddStar extends SkyDrawingOp {
  SkyAddStar(this.star) : super(star.gen);

  final SkyDrawnStar star;

  @override
  SkyDrawing get asDrawing => SkyDrawing(gen: gen, stars: [star]);

  @override
  Map<String, Object?> toJson() => {'o': 'star', 'star': star.toJson()};

  @override
  bool operator ==(Object other) => other is SkyAddStar && other.star == star;

  @override
  int get hashCode => star.hashCode;
}

final class SkyLink extends SkyDrawingOp {
  SkyLink(this.line) : super(line.gen);

  final SkyDrawnLine line;

  @override
  SkyDrawing get asDrawing => SkyDrawing(gen: gen, lines: [line]);

  @override
  Map<String, Object?> toJson() => {'o': 'line', 'line': line.toJson()};

  @override
  bool operator ==(Object other) => other is SkyLink && other.line == line;

  @override
  int get hashCode => line.hashCode;
}

final class SkyRemove extends SkyDrawingOp {
  SkyRemove(List<String> ids, {required int gen}) : ids = List<String>.unmodifiable(ids), super(gen);

  final List<String> ids;

  @override
  SkyDrawing get asDrawing => SkyDrawing(gen: gen, removed: ids);

  @override
  Map<String, Object?> toJson() => {'o': 'remove', 'ids': ids, 'g': gen};

  @override
  bool operator ==(Object other) => other is SkyRemove && other.gen == gen && listEquals(other.ids, ids);

  @override
  int get hashCode => Object.hash(gen, Object.hashAll(ids));
}

final class SkyStartOver extends SkyDrawingOp {
  const SkyStartOver(super.gen);

  @override
  SkyDrawing get asDrawing => SkyDrawing(gen: gen);

  @override
  Map<String, Object?> toJson() => {'o': 'clear', 'g': gen};

  @override
  bool operator ==(Object other) => other is SkyStartOver && other.gen == gen;

  @override
  int get hashCode => gen.hashCode;
}

class SkyDrawingRecord extends PlainRecord {
  SkyDrawingRecord._(super.fields, this.drawing);

  static SkyDrawingRecord? tryParse(Map<String, Object?> plain) {
    if (skyId(plain['id']) == null || plain['deleted'] == true) return null;
    if (skyInt(plain['updatedAt']) == null) return null;
    final drawing = SkyDrawing.fromParts(
      gen: plain['gen'],
      stars: plain['stars'],
      lines: plain['lines'],
      removed: plain['removed'],
    );
    if (drawing == null) return null;
    final rawName = plain['name'] ?? '';
    final finished = plain['finished'] ?? false;
    final startedAt = skyInt(plain['startedAt']);
    final rawCreated = plain['createdAt'];
    final createdAt = rawCreated == null ? null : skyInt(rawCreated);
    final rawNight = plain['night'];
    if (rawName is! String || rawName.length > skyDrawingMaxName * 4 || finished is! bool || startedAt == null) {
      return null;
    }
    if (rawCreated != null && createdAt == null) return null;
    if (rawNight != null && (rawNight is! String || !skyNightPattern.hasMatch(rawNight))) return null;
    final name = cleanSkyName(rawName);
    if (finished && (name.isEmpty || createdAt == null || rawNight == null || drawing.isBlank)) return null;
    return SkyDrawingRecord._({...plain, 'name': name}, drawing);
  }

  static Map<String, Object?> fieldsFor({
    required String id,
    required SkyDrawing drawing,
    required int startedAt,
    required int updatedAt,
    String name = '',
    bool finished = false,
    int? createdAt,
    String? night,
  }) => {
    'id': id,
    'name': cleanSkyName(name),
    'gen': drawing.gen,
    'stars': [for (final s in drawing.stars.values) s.toJson()],
    'lines': [for (final l in drawing.lines.values) l.toJson()],
    'removed': drawing.removed.toList(growable: false),
    'finished': finished,
    'startedAt': startedAt,
    if (createdAt != null) 'createdAt': createdAt,
    if (night != null) 'night': night,
    'updatedAt': updatedAt,
  };

  final SkyDrawing drawing;

  String get name => readString(fields['name']) ?? '';

  bool get finished => fields['finished'] == true;

  int get startedAt => readInt(fields['startedAt']) ?? 0;

  int? get createdAt => readInt(fields['createdAt']);

  String? get night => readString(fields['night']);
}
