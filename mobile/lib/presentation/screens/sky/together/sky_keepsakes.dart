import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../../../core/engine.dart';
import '../../../sky/sky.dart';
import 'sky_drawn.dart';
import 'sky_drawn_placement.dart';
import 'sky_drawn_watch.dart';
import 'sky_together_copy.dart';
import 'sky_together_fx.dart';
import 'sky_together_layer.dart';
import 'sky_together_scope.dart';

@immutable
class SkyKeepsakeSpot {
  const SkyKeepsakeSpot({
    required this.record,
    required this.slot,
    required this.rect,
    required this.opacity,
    required this.tilt,
  });

  final SkyDrawingRecord record;
  final int slot;
  final Rect rect;
  final double opacity;
  final double tilt;

  String get id => record.id;

  String get key => '$id@${rect.left.toStringAsFixed(1)},${rect.top.toStringAsFixed(1)}';

  double get strength => (opacity / SkyDrawnPlacement.newestOpacity).clamp(0.0, 1.0);

  @override
  bool operator ==(Object other) =>
      other is SkyKeepsakeSpot &&
      other.id == id &&
      other.record.updatedAt == record.updatedAt &&
      other.slot == slot &&
      other.rect == rect &&
      other.opacity == opacity &&
      other.tilt == tilt;

  @override
  int get hashCode => Object.hash(id, record.updatedAt, slot, rect, opacity, tilt);

  @override
  String toString() => 'SkyKeepsakeSpot($id, slot $slot, $rect, $opacity, $tilt)';
}

abstract final class SkyKeepsakePlan {
  static const int maxShown = 4;
  static const Offset sun = SkyTogetherSpot.sun;
  static const double moonLineGap = 28;
  static const double sunLineGap = 36;
  static const double lineEdge = 18;
  static const double topBarGap = 8;
  static const double streakReach = 14;
  static const double slotGap = 6;
  static const List<double> tilts = [-8, 6, -4, 5];

  static final TextStyle lineStyle = SkyType.serif(15, weight: FontWeight.w500, height: 1.2);

  static List<String> lines(String? partner) => [
    SkyTogetherCopy.hold(true),
    SkyTogetherCopy.hold(false),
    SkyTogetherCopy.bothHolding,
    if (partner != null && partner.trim().isNotEmpty) SkyTogetherCopy.waiting(partner.trim()),
  ];

  static Size measureLine(String? partner, {TextScaler textScaler = TextScaler.noScaling, double scale = 1}) {
    var width = 0.0;
    var height = 0.0;
    final room = (SkyTogetherSpot.lineMax - SkyTogetherSpot.lineMin) * scale;
    for (final text in lines(partner)) {
      final size = SkyTogetherLine.measure(text, lineStyle, textScaler, maxWidth: room);
      width = math.max(width, size.width);
      height = math.max(height, size.height);
    }
    return Size(width, height);
  }

  static Offset bodyOf({required bool night}) => night ? SkyScene.home.moon! : sun;

  static Rect? lineArea(Size line, {required bool night, double width = 390}) {
    if (line.isEmpty) return null;
    final body = bodyOf(night: night);
    final most = math.max(lineEdge, width - lineEdge - line.width);
    final left = (body.dx - line.width / 2).clamp(lineEdge, most);
    return Rect.fromLTWH(left, body.dy + (night ? moonLineGap : sunLineGap), line.width, line.height);
  }

  static Rect streakArea(SkyShootingStar streak) => Rect.fromPoints(streak.from, streak.to).inflate(streakReach);

  static List<Rect> avoid({
    required Size sky,
    required SkyConstellation constellation,
    required double topBarBottom,
    required double sheetTop,
    required bool night,
    List<Rect> extra = const [],
    Size line = Size.zero,
    SkyShootingStar? streak,
  }) => SkyDrawnPlacement.homeAvoid(
    sky: sky,
    constellation: constellation.bounds,
    topBarBottom: topBarBottom + topBarGap,
    sheetTop: sheetTop,
    moon: night ? bodyOf(night: true) : null,
    sun: night ? null : bodyOf(night: false),
    extra: [
      ...extra,
      if (lineArea(line, night: night, width: sky.width) case final area?) area,
      if (streak != null) streakArea(streak),
    ],
  );

  static List<Rect> slots({required Size sky, required List<Rect> avoid}) => [
    for (final spot in SkyDrawnPlacement.place(
      sky: sky,
      avoid: avoid,
      ids: [for (var i = 0; i < maxShown; i++) 'slot-$i'],
      gap: slotGap,
      max: maxShown,
    ))
      spot.rect,
  ];

  static List<SkyKeepsakeSpot> spots({required List<SkyDrawingRecord> finished, required List<Rect> slots}) {
    if (slots.isEmpty || finished.isEmpty) return const [];
    final shown = math.min(finished.length, slots.length);
    final total = finished.length;
    return [
      for (var rank = 0; rank < shown; rank++)
        if ((total - 1 - rank) % slots.length case final slot)
          SkyKeepsakeSpot(
            record: finished[rank],
            slot: slot,
            rect: slots[slot],
            opacity: SkyDrawnPlacement.opacityFor(rank),
            tilt: tilts[slot % tilts.length],
          ),
    ];
  }
}

abstract final class SkyKeepsakeArt {
  static const Color _gold = Color(0xFFFFD98A);
  static const Color _white = Color(0xFFFFFFFF);
  static const Color _shade = SkyTokens.indigo;
  static const double puffScale = 0.45;
  static const List<(double, double, double)> _puff = [(0, 0, 3.8), (-3, 1, 2.8), (3, 1.3, 2.6), (0.4, -2.7, 2.6)];

  static SkyDrawnSketch tilted(SkyDrawnSketch sketch, double degrees) {
    if (sketch.isEmpty || degrees == 0) return sketch;
    final centre = sketch.bounds.center;
    final turn = degrees * math.pi / 180;
    final c = math.cos(turn);
    final s = math.sin(turn);
    return SkyDrawnSketch(
      points: [
        for (final p in sketch.points)
          centre + Offset((p.dx - centre.dx) * c - (p.dy - centre.dy) * s, (p.dx - centre.dx) * s + (p.dy - centre.dy) * c),
      ],
      links: sketch.links,
    );
  }

  static List<Offset> pointsIn(Rect box, SkyDrawnSketch sketch) {
    final frame = SkyDrawnArt.frameOf(box, sketch);
    return [for (final p in sketch.points) SkyDrawnArt.place(frame, p)];
  }

  static void paint(
    Canvas canvas,
    Rect box,
    SkyDrawnSketch sketch, {
    required SkyDrawnStyle style,
    double opacity = 1,
    double scale = 1,
  }) {
    if (sketch.isEmpty || opacity <= 0 || box.isEmpty) return;
    final o = opacity.clamp(0.0, 1.0);
    final points = pointsIn(box, sketch);
    if (style == SkyDrawnStyle.night) {
      _night(canvas, points, sketch.links, o, scale);
    } else {
      _day(canvas, points, sketch.links, o, scale);
    }
  }

  static void _night(Canvas canvas, List<Offset> points, List<(int, int)> links, double o, double k) {
    final line = Paint()
      ..color = _gold.withValues(alpha: 0.30 * o)
      ..strokeWidth = 0.7 * k
      ..strokeCap = StrokeCap.round;
    for (final (a, b) in links) {
      canvas.drawLine(points[a], points[b], line);
    }
    final halo = Paint()..color = _gold.withValues(alpha: 0.12 * o);
    final gold = Paint()..color = _gold.withValues(alpha: 0.62 * o);
    final white = Paint()..color = _white.withValues(alpha: 0.62 * o);
    for (var i = 0; i < points.length; i++) {
      canvas.drawCircle(points[i], 3 * k, halo);
      canvas.drawCircle(points[i], 1.35 * k, i % 3 == 0 ? white : gold);
    }
  }

  static void _day(Canvas canvas, List<Offset> points, List<(int, int)> links, double o, double k) {
    final soft = MaskFilter.blur(BlurStyle.normal, 1 * k);
    final shade = Paint()
      ..color = _shade.withValues(alpha: 0.035 * o)
      ..strokeWidth = 2.6 * k
      ..strokeCap = StrokeCap.round;
    final trail = Paint()
      ..color = _white.withValues(alpha: 0.30 * o)
      ..strokeWidth = 3 * k
      ..strokeCap = StrokeCap.round
      ..maskFilter = soft;
    final dot = Paint()
      ..color = _white.withValues(alpha: 0.22 * o)
      ..maskFilter = soft;
    final core = Paint()
      ..color = _white.withValues(alpha: 0.55 * o)
      ..strokeWidth = 0.8 * k
      ..strokeCap = StrokeCap.round;
    final drop = Offset(0, 1.2 * k);
    for (final (a, b) in links) {
      final from = points[a];
      final to = points[b];
      canvas.drawLine(from + drop, to + drop, shade);
      canvas.drawLine(from, to, trail);
      final length = (to - from).distance / k;
      const step = 6.0;
      var n = 0;
      for (var s = step / 2; s < length; s += step, n++) {
        canvas.drawCircle(Offset.lerp(from, to, s / length)!, (1.1 + (n % 3) * 0.25) * k, dot);
      }
      canvas.drawLine(from, to, core);
    }
    final under = Paint()..color = _shade.withValues(alpha: 0.04 * o);
    final puff = Paint()
      ..color = _white.withValues(alpha: 0.75 * o)
      ..maskFilter = soft;
    final heart = Paint()..color = _white.withValues(alpha: o);
    final p = puffScale * k;
    for (var i = 0; i < points.length; i++) {
      final at = points[i];
      canvas.drawCircle(at + Offset(0, k), 6.4 * p, under);
      final turn = ((i * 47) % 360) * math.pi / 180;
      final c = math.cos(turn);
      final s = math.sin(turn);
      for (final (x, y, r) in _puff) {
        canvas.drawCircle(at + Offset((x * c - y * s) * p, (x * s + y * c) * p), r * p, puff);
      }
      canvas.drawCircle(at, 2.1 * p, heart);
    }
  }
}

class SkyKeepsakePainter extends CustomPainter {
  const SkyKeepsakePainter({required this.sketch, required this.style, this.opacity = 1, this.scale = 1});

  final SkyDrawnSketch sketch;
  final SkyDrawnStyle style;
  final double opacity;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    SkyKeepsakeArt.paint(canvas, Offset.zero & size, sketch, style: style, opacity: opacity, scale: scale);
  }

  @override
  bool shouldRepaint(SkyKeepsakePainter oldDelegate) =>
      oldDelegate.sketch != sketch ||
      oldDelegate.style != style ||
      oldDelegate.opacity != opacity ||
      oldDelegate.scale != scale;
}

class SkyKeepsakeMark extends StatelessWidget {
  const SkyKeepsakeMark({
    super.key,
    required this.spot,
    required this.sketch,
    required this.style,
    required this.scale,
    required this.target,
    this.duration = Duration.zero,
    this.curve = SkyMotion.gentle,
    this.onGone,
  });

  final SkyKeepsakeSpot spot;
  final SkyDrawnSketch sketch;
  final SkyDrawnStyle style;
  final double scale;
  final double target;
  final Duration duration;
  final Curve curve;
  final VoidCallback? onGone;

  bool get leaving => onGone != null;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: target),
      duration: duration,
      curve: curve,
      onEnd: onGone,
      builder: (context, value, _) => RepaintBoundary(
        child: CustomPaint(
          painter: SkyKeepsakePainter(sketch: sketch, style: style, opacity: value, scale: scale),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class SkyKeepsakes extends StatefulWidget {
  const SkyKeepsakes({
    super.key,
    required this.constellation,
    required this.topBar,
    required this.sky,
    required this.sheetTop,
    this.avoid = const [],
    this.streak,
    this.partner,
    this.shown = true,
    this.records,
  });

  static const Duration arrival = Duration(milliseconds: 600);

  final SkyConstellation constellation;
  final ValueListenable<double?> topBar;
  final Size sky;
  final double sheetTop;
  final List<Rect> avoid;
  final SkyShootingStar? streak;
  final String? partner;
  final bool shown;
  final List<SkyDrawingRecord>? records;

  @override
  State<SkyKeepsakes> createState() => _SkyKeepsakesState();
}

class _SkyKeepsakesState extends State<SkyKeepsakes> {
  SkyDrawnWatch? _watch;
  Set<String>? _first;
  List<SkyKeepsakeSpot> _last = const [];
  final Map<String, SkyKeepsakeSpot> _leaving = {};
  final Map<String, (int, SkyDrawnSketch)> _sketches = {};
  (String?, TextScaler, double, Size)? _line;
  (List<Rect>, Size, List<Rect>)? _slots;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final hidden = !TickerMode.valuesOf(context).enabled;
    _watch?.paused = hidden;
    if (_watch != null || widget.records != null) return;
    VaultService? vault;
    try {
      vault = Provider.of<VaultService>(context, listen: false);
    } on ProviderNotFoundException {
      vault = null;
    }
    if (vault == null) return;
    _watch = SkyDrawnWatch(service: SkyTogetherScope.drawingsOf(context), vault: vault)
      ..addListener(_changed)
      ..paused = hidden;
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _watch
      ?..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  bool get _loaded => widget.records != null || (_watch?.loaded ?? false);

  List<SkyDrawingRecord> get _finished => widget.records ?? _watch?.finished ?? const [];

  SkyDrawnSketch _sketchOf(SkyKeepsakeSpot spot) {
    final cached = _sketches[spot.key];
    if (cached != null && cached.$1 == spot.record.updatedAt) return cached.$2;
    final sketch = SkyKeepsakeArt.tilted(SkyDrawnSketch.of(spot.record.drawing), spot.tilt);
    _sketches[spot.key] = (spot.record.updatedAt, sketch);
    return sketch;
  }

  void _gone(String key) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_leaving.containsKey(key)) return;
      setState(() {
        _leaving.remove(key);
        _sketches.remove(key);
      });
    });
  }

  Size _measured(String? partner, TextScaler scaler, double k) {
    final cached = _line;
    if (cached != null && cached.$1 == partner && cached.$2 == scaler && cached.$3 == k) return cached.$4;
    final size = SkyKeepsakePlan.measureLine(partner, textScaler: scaler, scale: k);
    _line = (partner, scaler, k, size);
    return size;
  }

  List<Rect> _slotsFor(List<Rect> avoid) {
    final cached = _slots;
    if (cached != null && listEquals(cached.$1, avoid) && cached.$2 == widget.sky) return cached.$3;
    final slots = SkyKeepsakePlan.slots(sky: widget.sky, avoid: avoid);
    _slots = (avoid, widget.sky, slots);
    return slots;
  }

  List<SkyKeepsakeSpot> _plan(
    BuildContext context, {
    required double topBarBottom,
    required double k,
    required bool night,
  }) {
    final line = _measured(widget.partner, MediaQuery.textScalerOf(context), k);
    final avoid = SkyKeepsakePlan.avoid(
      sky: widget.sky,
      constellation: widget.constellation,
      topBarBottom: topBarBottom,
      sheetTop: widget.sheetTop,
      night: night,
      extra: widget.avoid,
      line: line / k,
      streak: widget.streak,
    );
    return SkyKeepsakePlan.spots(finished: _finished, slots: _slotsFor(avoid));
  }

  void _track(List<SkyKeepsakeSpot> spots, {required bool motion}) {
    final keys = {for (final s in spots) s.key};
    for (final old in _last) {
      if (motion && !keys.contains(old.key)) _leaving[old.key] = old;
    }
    if (motion) {
      _leaving.removeWhere((key, _) => keys.contains(key));
    } else {
      _leaving.clear();
    }
    _sketches.removeWhere((key, _) => !keys.contains(key) && !_leaving.containsKey(key));
    _last = spots;
    _first ??= keys;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double?>(
      valueListenable: widget.topBar,
      builder: (context, topBar, _) => LayoutBuilder(
        builder: (context, box) {
          final ready = widget.shown && _loaded && topBar != null && box.maxWidth.isFinite && box.maxWidth > 0;
          if (!ready) return const SizedBox.shrink();
          final k = box.maxWidth / widget.sky.width;
          final motion = skyMotionAllowed(context);
          final style = SkyDrawnStyle.of(context.sky);
          final spots = _plan(context, topBarBottom: topBar / k, k: k, night: style == SkyDrawnStyle.night);
          _track(spots, motion: motion);
          final first = _first ?? const <String>{};
          Widget mark(SkyKeepsakeSpot spot, {required bool leaving}) {
            final opening = first.contains(spot.key);
            final r = spot.rect;
            return Positioned(
              key: ValueKey<String>(spot.key),
              left: r.left * k,
              top: r.top * k,
              width: r.width * k,
              height: r.height * k,
              child: SkyKeepsakeMark(
                spot: spot,
                sketch: _sketchOf(spot),
                style: style,
                scale: k,
                target: leaving ? 0 : spot.strength,
                duration: !motion
                    ? Duration.zero
                    : opening
                    ? SkyMotion.slow * 2
                    : SkyKeepsakes.arrival,
                curve: opening ? const Interval(0.5, 1, curve: SkyMotion.gentle) : SkyMotion.gentle,
                onGone: leaving ? () => _gone(spot.key) : null,
              ),
            );
          }

          return IgnorePointer(
            child: ExcludeSemantics(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  for (final spot in _leaving.values) mark(spot, leaving: true),
                  for (final spot in spots) mark(spot, leaving: false),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class SkyHeightProbe extends SingleChildRenderObjectWidget {
  const SkyHeightProbe({super.key, required this.onHeight, super.child});

  final ValueChanged<double> onHeight;

  @override
  RenderSkyHeightProbe createRenderObject(BuildContext context) => RenderSkyHeightProbe(onHeight);

  @override
  void updateRenderObject(BuildContext context, RenderSkyHeightProbe renderObject) {
    renderObject.onHeight = onHeight;
  }
}

class RenderSkyHeightProbe extends RenderProxyBox {
  RenderSkyHeightProbe(this.onHeight);

  ValueChanged<double> onHeight;
  double? _reported;

  @override
  void performLayout() {
    super.performLayout();
    final height = size.height;
    if (height == _reported) return;
    _reported = height;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (attached && _reported == height) onHeight(height);
    });
  }
}
