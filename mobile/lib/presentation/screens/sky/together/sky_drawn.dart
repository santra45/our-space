import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../../../core/engine.dart';
import '../../../sky/sky_tokens.dart';

enum SkyDrawnStyle {
  night,
  day;

  static SkyDrawnStyle of(SkyTokens tokens) => tokens.isNight ? night : day;
}

enum SkyDrawnFit { drawing, patch }

@immutable
class SkyDrawnSketch {
  SkyDrawnSketch({required List<Offset> points, required List<(int, int)> links})
    : points = List<Offset>.unmodifiable(points),
      links = List<(int, int)>.unmodifiable(links);

  factory SkyDrawnSketch.of(SkyDrawing drawing) {
    final stars = drawing.visibleStars;
    final index = {for (var i = 0; i < stars.length; i++) stars[i].id: i};
    return SkyDrawnSketch(
      points: [for (final s in stars) Offset(s.x * SkyDrawnArt.aspect, s.y)],
      links: [
        for (final l in drawing.visibleLines)
          if (index.containsKey(l.a) && index.containsKey(l.b)) (index[l.a]!, index[l.b]!),
      ],
    );
  }

  static final SkyDrawnSketch empty = SkyDrawnSketch(points: const [], links: const []);

  final List<Offset> points;
  final List<(int, int)> links;

  bool get isEmpty => points.isEmpty;

  Rect get bounds {
    if (points.isEmpty) return const Rect.fromLTWH(0, 0, 1, 1);
    var left = points.first.dx;
    var top = points.first.dy;
    var right = left;
    var bottom = top;
    for (final p in points) {
      left = math.min(left, p.dx);
      top = math.min(top, p.dy);
      right = math.max(right, p.dx);
      bottom = math.max(bottom, p.dy);
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  @override
  bool operator ==(Object other) =>
      other is SkyDrawnSketch && listEquals(other.points, points) && listEquals(other.links, links);

  @override
  int get hashCode => Object.hash(Object.hashAll(points), Object.hashAll(links));
}

@immutable
class SkyDrawnShelf {
  const SkyDrawnShelf._(this.finished, this.unfinished);

  factory SkyDrawnShelf.of(Iterable<SkyDrawingRecord> records) {
    final finished = [for (final r in records) if (r.finished && !r.deleted) r]..sort(newestFirst);
    return SkyDrawnShelf._(
      List<SkyDrawingRecord>.unmodifiable(finished),
      SkyDrawingService.pickUnfinished(records),
    );
  }

  static const SkyDrawnShelf empty = SkyDrawnShelf._([], null);

  final List<SkyDrawingRecord> finished;
  final SkyDrawingRecord? unfinished;

  bool get isEmpty => finished.isEmpty && unfinished == null;

  List<SkyDrawingRecord> recent([int count = 6]) => finished.take(count).toList(growable: false);

  SkyDrawingRecord? byId(String id) {
    for (final r in finished) {
      if (r.id == id) return r;
    }
    return unfinished?.id == id ? unfinished : null;
  }

  static int newestFirst(SkyDrawingRecord a, SkyDrawingRecord b) {
    final at = (b.createdAt ?? b.updatedAt).compareTo(a.createdAt ?? a.updatedAt);
    if (at != 0) return at;
    final updated = b.updatedAt.compareTo(a.updatedAt);
    if (updated != 0) return updated;
    return b.id.compareTo(a.id);
  }
}

abstract final class SkyDrawnArt {
  static const double aspect = 0.7;
  static const double padding = 0.12;
  static const double minSpan = 0.18;

  static const Color _nightStar = Color(0xFFFFD98A);
  static const Color _nightCore = Color(0xFFFFFFFF);
  static const Color _nightLine = Color(0xFFFFD98A);
  static const Color _dayTrail = Color(0xFFFFFFFF);
  static const Color _dayShade = SkyTokens.indigo;

  static Rect frameOf(Rect box, SkyDrawnSketch sketch, {SkyDrawnFit fit = SkyDrawnFit.drawing}) {
    if (fit == SkyDrawnFit.patch) {
      final area = patchIn(box);
      return Rect.fromLTWH(area.left, area.top, area.height, area.height);
    }
    final b = sketch.bounds;
    final span = math.max(math.max(b.width, b.height), minSpan);
    final unit = Rect.fromCenter(center: b.center, width: span, height: span);
    final room = box.deflate(math.min(box.width, box.height) * padding);
    final side = math.max(0.0, math.min(room.width, room.height));
    final frame = Rect.fromCenter(center: room.center, width: side, height: side);
    return Rect.fromLTWH(
      frame.left - (unit.left / span) * side,
      frame.top - (unit.top / span) * side,
      side / span,
      side / span,
    );
  }

  static Offset place(Rect frame, Offset unit) => Offset(frame.left + unit.dx * frame.width, frame.top + unit.dy * frame.height);

  static Rect patchIn(Rect box) {
    final height = math.max(0.0, math.min(box.height, box.width / aspect));
    return Rect.fromCenter(center: box.center, width: height * aspect, height: height);
  }

  static Rect unitFrame(Rect frame) => Rect.fromLTWH(frame.left, frame.top, frame.width * aspect, frame.height);

  static Offset unitOf(Rect frame, Offset local) => Offset(
    frame.width <= 0 ? 0 : (local.dx - frame.left) / frame.width,
    frame.height <= 0 ? 0 : (local.dy - frame.top) / frame.height,
  );

  static double scaleOf(Rect box) => (math.min(box.width, box.height) / 160).clamp(0.35, 2.4);

  static void paint(
    Canvas canvas,
    Rect box,
    SkyDrawnSketch sketch, {
    required SkyDrawnStyle style,
    double opacity = 1,
    SkyDrawnFit fit = SkyDrawnFit.drawing,
    double? scale,
  }) {
    if (sketch.isEmpty || opacity <= 0 || box.isEmpty) return;
    final o = opacity.clamp(0.0, 1.0);
    final k = scale ?? scaleOf(box);
    final frame = frameOf(box, sketch, fit: fit);
    final points = [for (final p in sketch.points) place(frame, p)];
    if (style == SkyDrawnStyle.night) {
      _night(canvas, points, sketch.links, o, k);
    } else {
      _day(canvas, points, sketch.links, o, k);
    }
  }

  static void _night(Canvas canvas, List<Offset> points, List<(int, int)> links, double o, double k) {
    final line = Paint()
      ..color = _nightLine.withValues(alpha: 0.42 * o)
      ..strokeWidth = 0.9 * k
      ..strokeCap = StrokeCap.round;
    for (final (a, b) in links) {
      canvas.drawLine(points[a], points[b], line);
    }
    final halo = Paint()
      ..color = _nightStar.withValues(alpha: 0.22 * o)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2.6 * k);
    final glow = Paint()..color = _nightStar.withValues(alpha: 0.9 * o);
    final core = Paint()..color = _nightCore.withValues(alpha: 0.95 * o);
    for (final p in points) {
      canvas.drawCircle(p, 4.2 * k, halo);
      canvas.drawCircle(p, 1.9 * k, glow);
      canvas.drawCircle(p, 0.9 * k, core);
    }
  }

  static void _day(Canvas canvas, List<Offset> points, List<(int, int)> links, double o, double k) {
    final shade = Paint()
      ..color = _dayShade.withValues(alpha: 0.07 * o)
      ..strokeWidth = 4.4 * k
      ..strokeCap = StrokeCap.round
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 1.8 * k);
    final trail = Paint()
      ..color = _dayTrail.withValues(alpha: 0.5 * o)
      ..strokeWidth = 3.2 * k
      ..strokeCap = StrokeCap.round
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 1.4 * k);
    final thread = Paint()
      ..color = _dayTrail.withValues(alpha: 0.85 * o)
      ..strokeWidth = 0.9 * k
      ..strokeCap = StrokeCap.round;
    for (final (a, b) in links) {
      canvas.drawLine(points[a], points[b], shade);
      canvas.drawLine(points[a], points[b], trail);
      canvas.drawLine(points[a], points[b], thread);
    }
    final puffShade = Paint()
      ..color = _dayShade.withValues(alpha: 0.08 * o)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2.4 * k);
    final puff = Paint()
      ..color = _dayTrail.withValues(alpha: 0.75 * o)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2 * k);
    final core = Paint()..color = _dayTrail.withValues(alpha: 0.98 * o);
    for (final p in points) {
      canvas.drawCircle(p, 5 * k, puffShade);
      canvas.drawCircle(p, 4 * k, puff);
      canvas.drawCircle(p, 1.7 * k, core);
    }
  }
}

class SkyDrawnPainter extends CustomPainter {
  const SkyDrawnPainter({
    required this.sketch,
    required this.style,
    this.opacity = 1,
    this.fit = SkyDrawnFit.drawing,
    this.scale,
  });

  final SkyDrawnSketch sketch;
  final SkyDrawnStyle style;
  final double opacity;
  final SkyDrawnFit fit;
  final double? scale;

  @override
  void paint(Canvas canvas, Size size) {
    SkyDrawnArt.paint(canvas, Offset.zero & size, sketch, style: style, opacity: opacity, fit: fit, scale: scale);
  }

  @override
  bool shouldRepaint(SkyDrawnPainter oldDelegate) =>
      oldDelegate.sketch != sketch ||
      oldDelegate.style != style ||
      oldDelegate.opacity != opacity ||
      oldDelegate.fit != fit ||
      oldDelegate.scale != scale;
}

class SkyDrawnView extends StatelessWidget {
  const SkyDrawnView({
    super.key,
    required this.sketch,
    this.style,
    this.opacity = 1,
    this.fit = SkyDrawnFit.drawing,
    this.scale,
    this.semanticLabel,
  });

  final SkyDrawnSketch sketch;
  final SkyDrawnStyle? style;
  final double opacity;
  final SkyDrawnFit fit;
  final double? scale;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final painted = RepaintBoundary(
      child: CustomPaint(
        painter: SkyDrawnPainter(
          sketch: sketch,
          style: style ?? SkyDrawnStyle.of(context.sky),
          opacity: opacity,
          fit: fit,
          scale: scale,
        ),
        child: const SizedBox.expand(),
      ),
    );
    final label = semanticLabel;
    if (label == null) return ExcludeSemantics(child: painted);
    return Semantics(image: true, label: label, child: ExcludeSemantics(child: painted));
  }
}
