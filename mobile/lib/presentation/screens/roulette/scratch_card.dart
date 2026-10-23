import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../sky/sky.dart';
import '../../widgets/app_haptics.dart';
import 'roulette_copy.dart';

class ScratchCoverage {
  ScratchCoverage({this.width = canvasWidth, this.height = canvasHeight})
    : sampleCount = ((width * height * 4 - 3) + bytesPerSample - 1) ~/ bytesPerSample {
    _cleared = Uint8List(sampleCount);
  }

  static const int canvasWidth = 340;
  static const int canvasHeight = 255;
  static const double brushRadius = 24;
  static const int bytesPerSample = 64;
  static const int pixelsPerSample = bytesPerSample ~/ 4;
  static const double revealThreshold = 0.4;

  final int width;
  final int height;
  final int sampleCount;
  late final Uint8List _cleared;
  int _clearedCount = 0;

  int get clearedCount => _clearedCount;

  double get fraction => sampleCount == 0 ? 0 : _clearedCount / sampleCount;

  bool get revealed => sampleCount > 0 && fraction > revealThreshold;

  Size get size => Size(width.toDouble(), height.toDouble());

  static ScratchCoverage fitting(Size size) {
    if (size.isEmpty || !size.isFinite) return ScratchCoverage();
    final height = (canvasWidth * size.height / size.width).round().clamp(1, canvasWidth * 4);
    return ScratchCoverage(width: canvasWidth, height: height);
  }

  bool isCleared(int x, int y) {
    final pixel = y * width + x;
    if (pixel % pixelsPerSample != 0) return false;
    final sample = pixel ~/ pixelsPerSample;
    return sample < sampleCount && _cleared[sample] == 1;
  }

  void scratch(double x, double y, {double radius = brushRadius}) {
    final top = math.max(0, (y - radius).floor());
    final bottom = math.min(height - 1, (y + radius).ceil());
    final left = math.max(0, (x - radius).floor());
    final right = math.min(width - 1, (x + radius).ceil());
    if (top > bottom || left > right) return;
    final limit = radius * radius;
    for (var py = top; py <= bottom; py++) {
      final rowStart = py * width;
      final dy = math.max((py - y).abs(), (py + 1 - y).abs());
      final dy2 = dy * dy;
      if (dy2 > limit) continue;
      var px = left + (pixelsPerSample - (rowStart + left) % pixelsPerSample) % pixelsPerSample;
      for (; px <= right; px += pixelsPerSample) {
        final dx = math.max((px - x).abs(), (px + 1 - x).abs());
        if (dx * dx + dy2 > limit) continue;
        final sample = (rowStart + px) ~/ pixelsPerSample;
        if (sample >= sampleCount || _cleared[sample] == 1) continue;
        _cleared[sample] = 1;
        _clearedCount++;
      }
    }
  }
}

abstract final class GoldFoil {
  static const List<Color> colors = [
    Color(0xFFE9C27A),
    Color(0xFFFFF0C8),
    Color(0xFFD9A94F),
    Color(0xFFFFE7A8),
    Color(0xFFC9922F),
    Color(0xFFFFF0C8),
  ];
  static const List<double> stops = [0, 0.22, 0.4, 0.58, 0.78, 1];
  static const Color ink = Color(0xFF6B4A12);
  static const Color dot = Color(0x54FFFFFF);
  static const double dotSpacing = 9;

  static Shader shader(Rect rect) => const LinearGradient(
    begin: Alignment(-1, -0.47),
    end: Alignment(1, 0.47),
    colors: colors,
    stops: stops,
  ).createShader(rect);

  static List<Offset> dots(Size size) {
    return [
      for (var y = dotSpacing / 2; y < size.height; y += dotSpacing)
        for (var x = dotSpacing / 2; x < size.width; x += dotSpacing) Offset(x, y),
    ];
  }
}

class ScratchCoatingPainter extends CustomPainter {
  ScratchCoatingPainter({
    required this.strokes,
    required Listenable repaint,
    this.canvasSize = const Size(340, 255),
    this.shimmer,
  }) : super(repaint: repaint);

  final List<Offset> strokes;
  final Size canvasSize;
  final Animation<double>? shimmer;

  static final Map<Size, List<Offset>> _dotCache = {};

  static final TextPainter _label = TextPainter(
    text: TextSpan(
      text: RouletteCopy.scratchHere.toUpperCase(),
      style: SkyType.caps(11, weight: FontWeight.w700, tracking: 0.22, color: GoldFoil.ink.withValues(alpha: 0.78)),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  static Path _sparkle(Offset center, double r) {
    final k = r * 0.28;
    return Path()
      ..moveTo(center.dx, center.dy - r)
      ..quadraticBezierTo(center.dx + k, center.dy - k, center.dx + r, center.dy)
      ..quadraticBezierTo(center.dx + k, center.dy + k, center.dx, center.dy + r)
      ..quadraticBezierTo(center.dx - k, center.dy + k, center.dx - r, center.dy)
      ..quadraticBezierTo(center.dx - k, center.dy - k, center.dx, center.dy - r)
      ..close();
  }

  List<Offset> _dots() => _dotCache.putIfAbsent(canvasSize, () => GoldFoil.dots(canvasSize));

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || canvasSize.isEmpty) return;
    canvas.save();
    canvas.scale(size.width / canvasSize.width, size.height / canvasSize.height);
    final bounds = Offset.zero & canvasSize;
    canvas.saveLayer(bounds, Paint());
    canvas.drawRect(bounds, Paint()..shader = GoldFoil.shader(bounds));
    canvas.drawPoints(
      ui.PointMode.points,
      _dots(),
      Paint()
        ..color = GoldFoil.dot
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    final sweep = shimmer?.value;
    if (sweep != null) {
      final width = canvasSize.width * 0.45;
      final left = -width + sweep * (canvasSize.width + width * 2);
      final band = Rect.fromLTWH(left, 0, width, canvasSize.height);
      canvas.drawRect(
        bounds,
        Paint()
          ..shader = const LinearGradient(
            colors: [Color(0x00FFFFFF), Color(0x66FFFFFF), Color(0x00FFFFFF)],
            stops: [0, 0.5, 1],
          ).createShader(band),
      );
    }
    final center = bounds.center;
    _label.paint(canvas, center - Offset(_label.width / 2, _label.height / 2));
    final sparkle = Paint()..color = GoldFoil.ink.withValues(alpha: 0.7);
    canvas.drawPath(_sparkle(center - Offset(_label.width / 2 + 12, 0), 5), sparkle);
    canvas.drawPath(_sparkle(center + Offset(_label.width / 2 + 12, 0), 5), sparkle);
    final eraser = Paint()
      ..blendMode = BlendMode.dstOut
      ..isAntiAlias = true;
    for (final point in strokes) {
      canvas.drawCircle(point, ScratchCoverage.brushRadius, eraser);
    }
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(ScratchCoatingPainter oldDelegate) =>
      oldDelegate.strokes != strokes || oldDelegate.canvasSize != canvasSize || oldDelegate.shimmer != shimmer;
}

class ScratchCard extends StatefulWidget {
  const ScratchCard({super.key, required this.revealed, required this.onRevealed});

  static const int strokesPerTick = 4;
  static const int strokesPerProgressCheck = 24;
  static const Duration fade = SkyMotion.slow;
  static const Duration shimmerPeriod = Duration(milliseconds: 2800);
  static const Duration shimmerRest = Duration(milliseconds: 4500);

  final bool revealed;
  final VoidCallback onRevealed;

  @override
  State<ScratchCard> createState() => ScratchCardState();
}

class ScratchCardState extends State<ScratchCard> with TickerProviderStateMixin {
  ScratchCoverage _coverage = ScratchCoverage();
  final List<Offset> _strokes = [];
  final ValueNotifier<int> _repaint = ValueNotifier<int>(0);
  AnimationController? _shimmer;
  Timer? _rest;
  ScrollPosition? _position;
  bool _visible = true;
  int? _pointer;
  int _strokeCount = 0;
  Size _size = Size.zero;

  ScratchCoverage get coverage => _coverage;

  int get strokeCount => _strokeCount;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (!identical(position, _position)) {
      _position?.removeListener(_onScroll);
      _position = position?..addListener(_onScroll);
      WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
    }
    _syncShimmer();
  }

  @override
  void didUpdateWidget(covariant ScratchCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncShimmer();
  }

  bool get _onScreen {
    final box = context.findRenderObject();
    final viewport = Scrollable.maybeOf(context)?.context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return true;
    if (viewport is! RenderBox || !viewport.attached || !viewport.hasSize) return true;
    final top = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
    return top < viewport.size.height && top + box.size.height > 0;
  }

  void _onScroll() {
    if (!mounted) return;
    final visible = _onScreen;
    if (visible == _visible) return;
    _visible = visible;
    _syncShimmer();
  }

  void _syncShimmer() {
    if (widget.revealed || !skyMotionAllowed(context)) {
      _rest?.cancel();
      _rest = null;
      _shimmer?.dispose();
      _shimmer = null;
      return;
    }
    final shimmer = _shimmer ??= AnimationController(vsync: this, duration: ScratchCard.shimmerPeriod)
      ..addStatusListener(_onShimmer);
    if (!_visible) {
      _rest?.cancel();
      _rest = null;
      if (shimmer.isAnimating) shimmer.stop();
      return;
    }
    if (!shimmer.isAnimating && _rest == null) shimmer.forward(from: 0);
  }

  void _onShimmer(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _rest?.cancel();
    _rest = Timer(ScratchCard.shimmerRest, () {
      _rest = null;
      if (mounted) _syncShimmer();
    });
  }

  @override
  void dispose() {
    _rest?.cancel();
    _position?.removeListener(_onScroll);
    _shimmer?.dispose();
    _repaint.dispose();
    super.dispose();
  }

  void _fit(Size size) {
    if (size == _size || size.isEmpty || !size.isFinite) return;
    _size = size;
    final fitted = ScratchCoverage.fitting(size);
    if (fitted.width == _coverage.width && fitted.height == _coverage.height) return;
    _coverage = fitted;
    _strokes.clear();
  }

  void _scratch(Offset local) {
    if (widget.revealed) return;
    if (_size.width == 0 || _size.height == 0) return;
    final x = local.dx * (_coverage.width / _size.width);
    final y = local.dy * (_coverage.height / _size.height);
    _strokes.add(Offset(x, y));
    _coverage.scratch(x, y);
    _repaint.value++;
    _strokeCount++;
    if (_strokeCount % ScratchCard.strokesPerTick == 0) AppHaptics.tick();
    if (_strokeCount % ScratchCard.strokesPerProgressCheck == 0) _check();
  }

  void _check() {
    if (widget.revealed) return;
    if (_coverage.revealed) widget.onRevealed();
  }

  void _down(PointerDownEvent event) {
    if (_pointer != null) return;
    _pointer = event.pointer;
    _scratch(event.localPosition);
  }

  void _move(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    _scratch(event.localPosition);
  }

  void _end(PointerEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    _check();
  }

  @override
  Widget build(BuildContext context) {
    final motion = skyMotionAllowed(context);
    final shimmer = _shimmer;
    return IgnorePointer(
      ignoring: widget.revealed,
      child: AnimatedOpacity(
        opacity: widget.revealed ? 0 : 1,
        duration: motion ? ScratchCard.fade : Duration.zero,
        curve: SkyMotion.standard,
        child: LayoutBuilder(
          builder: (context, constraints) {
            _fit(constraints.biggest);
            return Semantics(
              container: true,
              button: !widget.revealed,
              label: RouletteCopy.scratchLabel,
              onTap: widget.revealed ? null : widget.onRevealed,
              child: RawGestureDetector(
                behavior: HitTestBehavior.opaque,
                gestures: <Type, GestureRecognizerFactory>{
                  EagerGestureRecognizer: GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
                    EagerGestureRecognizer.new,
                    (_) {},
                  ),
                },
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: _down,
                  onPointerMove: _move,
                  onPointerUp: _end,
                  onPointerCancel: _end,
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: ScratchCoatingPainter(
                        strokes: _strokes,
                        canvasSize: _coverage.size,
                        shimmer: shimmer,
                        repaint: shimmer == null ? _repaint : Listenable.merge([_repaint, shimmer]),
                      ),
                      size: Size.infinite,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
