import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../widgets/our_widgets.dart';
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

class ScratchCoatingPainter extends CustomPainter {
  ScratchCoatingPainter({required this.strokes, required Listenable repaint}) : super(repaint: repaint);

  final List<Offset> strokes;

  static const Size canvasSize = Size(340, 255);

  static final TextPainter _headline = TextPainter(
    text: const TextSpan(
      text: RouletteCopy.scratchHere,
      style: TextStyle(color: AppColors.blush500, fontSize: 16, fontWeight: FontWeight.w700),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  static final TextPainter _hint = TextPainter(
    text: const TextSpan(
      text: RouletteCopy.scratchHint,
      style: TextStyle(color: AppColors.slate400, fontSize: 12),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  static void _paintCentered(Canvas canvas, TextPainter text, double centerX, double baseline) {
    final ascent = text.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    text.paint(canvas, Offset(centerX - text.width / 2, baseline - ascent));
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.save();
    canvas.scale(size.width / canvasSize.width, size.height / canvasSize.height);
    final bounds = Offset.zero & canvasSize;
    canvas.saveLayer(bounds, Paint());
    canvas.drawRect(bounds, Paint()..shader = AppGradients.scratchCoatingShader(canvasSize));
    _paintCentered(canvas, _headline, canvasSize.width / 2, canvasSize.height / 2 - 10);
    _paintCentered(canvas, _hint, canvasSize.width / 2, canvasSize.height / 2 + 14);
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
  bool shouldRepaint(ScratchCoatingPainter oldDelegate) => oldDelegate.strokes != strokes;
}

class ScratchCard extends StatefulWidget {
  const ScratchCard({super.key, required this.revealed, required this.onRevealed});

  static const int strokesPerTick = 4;
  static const int strokesPerProgressCheck = 24;
  static const Duration fade = Duration(milliseconds: 500);
  static const Curve fadeCurve = Cubic(0.4, 0, 0.2, 1);

  final bool revealed;
  final VoidCallback onRevealed;

  @override
  State<ScratchCard> createState() => ScratchCardState();
}

class ScratchCardState extends State<ScratchCard> {
  final ScratchCoverage coverage = ScratchCoverage();
  final List<Offset> _strokes = [];
  final ValueNotifier<int> _repaint = ValueNotifier<int>(0);
  int? _pointer;
  int _strokeCount = 0;
  Size _size = Size.zero;

  int get strokeCount => _strokeCount;

  @override
  void dispose() {
    _repaint.dispose();
    super.dispose();
  }

  void _scratch(Offset local) {
    if (widget.revealed) return;
    if (_size.width == 0 || _size.height == 0) return;
    final x = local.dx * (ScratchCoverage.canvasWidth / _size.width);
    final y = local.dy * (ScratchCoverage.canvasHeight / _size.height);
    _strokes.add(Offset(x, y));
    coverage.scratch(x, y);
    _repaint.value++;
    _strokeCount++;
    if (_strokeCount % ScratchCard.strokesPerTick == 0) AppHaptics.tick();
    if (_strokeCount % ScratchCard.strokesPerProgressCheck == 0) _check();
  }

  void _check() {
    if (widget.revealed) return;
    if (coverage.revealed) widget.onRevealed();
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
    return IgnorePointer(
      ignoring: widget.revealed,
      child: AnimatedOpacity(
        opacity: widget.revealed ? 0 : 1,
        duration: ScratchCard.fade,
        curve: ScratchCard.fadeCurve,
        child: LayoutBuilder(
          builder: (context, constraints) {
            _size = constraints.biggest;
            return RawGestureDetector(
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
                child: CustomPaint(
                  painter: ScratchCoatingPainter(strokes: _strokes, repaint: _repaint),
                  size: Size.infinite,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
