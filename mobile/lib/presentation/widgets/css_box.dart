import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

class CssShadowPainter extends CustomPainter {
  const CssShadowPainter({required this.shadows, required this.borderRadius});

  final List<BoxShadow> shadows;
  final BorderRadius borderRadius;

  static RRect _spread(RRect rrect, double spread) {
    Radius grow(Radius r) => Radius.elliptical(math.max(0, r.x + spread), math.max(0, r.y + spread));
    final rect = rrect.outerRect.inflate(spread);
    if (rect.width <= 0 || rect.height <= 0) return RRect.zero;
    return RRect.fromRectAndCorners(
      rect,
      topLeft: grow(rrect.tlRadius),
      topRight: grow(rrect.trRadius),
      bottomLeft: grow(rrect.blRadius),
      bottomRight: grow(rrect.brRadius),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (shadows.isEmpty) return;
    final rect = Offset.zero & size;
    final rrect = borderRadius.toRRect(rect);
    canvas.save();
    canvas.clipPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(rect.inflate(2000))
        ..addRRect(rrect),
    );
    for (final shadow in shadows.reversed) {
      final shape = _spread(rrect.shift(shadow.offset), shadow.spreadRadius);
      if (shape == RRect.zero) continue;
      canvas.drawRRect(shape, shadow.toPaint());
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(CssShadowPainter oldDelegate) {
    return oldDelegate.borderRadius != borderRadius || !_sameShadows(oldDelegate.shadows, shadows);
  }

  static bool _sameShadows(List<BoxShadow> a, List<BoxShadow> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class InsetShadowPainter extends CustomPainter {
  const InsetShadowPainter({required this.borderRadius, required this.color, this.offset = const Offset(0, 2), this.sigma = 2});

  final BorderRadius borderRadius;
  final Color color;
  final Offset offset;
  final double sigma;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = borderRadius.toRRect(Offset.zero & size);
    canvas.save();
    canvas.clipRRect(rrect);
    final ring = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect((Offset.zero & size).inflate(sigma * 6 + offset.distance))
      ..addRRect(rrect.shift(offset));
    canvas.drawPath(
      ring,
      Paint()
        ..color = color
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(InsetShadowPainter oldDelegate) {
    return oldDelegate.borderRadius != borderRadius ||
        oldDelegate.color != color ||
        oldDelegate.offset != offset ||
        oldDelegate.sigma != sigma;
  }
}

class DashedBorderPainter extends CustomPainter {
  const DashedBorderPainter({
    required this.color,
    required this.borderRadius,
    this.strokeWidth = 2,
    this.dash = 6,
    this.gap = 6,
  });

  final Color color;
  final BorderRadius borderRadius;
  final double strokeWidth;
  final double dash;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = strokeWidth / 2;
    final rect = (Offset.zero & size).deflate(inset);
    final rrect = borderRadius.toRRect(rect);
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    for (final metric in path.computeMetrics()) {
      final total = metric.length;
      final count = math.max(1, (total / (dash + gap)).round());
      final period = total / count;
      final on = period * dash / (dash + gap);
      for (var i = 0; i < count; i++) {
        final start = i * period;
        canvas.drawPath(metric.extractPath(start, start + on), paint);
      }
    }
  }

  @override
  bool shouldRepaint(DashedBorderPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.borderRadius != borderRadius ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.dash != dash ||
        oldDelegate.gap != gap;
  }
}

class CssBox extends StatelessWidget {
  const CssBox({
    super.key,
    this.child,
    this.padding = EdgeInsets.zero,
    this.color,
    this.gradient,
    this.border,
    this.dashedBorder,
    this.borderRadius = BorderRadius.zero,
    this.shadows = const [],
    this.backdropBlur = 0,
    this.clipContent = false,
    this.width,
    this.height,
    this.constraints,
    this.opacity = 1,
  });

  final Widget? child;
  final EdgeInsets padding;
  final Color? color;
  final Gradient? gradient;
  final Border? border;
  final BorderSide? dashedBorder;
  final BorderRadius borderRadius;
  final List<BoxShadow> shadows;
  final double backdropBlur;
  final bool clipContent;
  final double? width;
  final double? height;
  final BoxConstraints? constraints;
  final double opacity;

  EdgeInsets get _borderInsets {
    if (dashedBorder != null) return EdgeInsets.all(dashedBorder!.width);
    final b = border;
    if (b == null) return EdgeInsets.zero;
    return EdgeInsets.fromLTRB(
      b.left.style == BorderStyle.none ? 0 : b.left.width,
      b.top.style == BorderStyle.none ? 0 : b.top.width,
      b.right.style == BorderStyle.none ? 0 : b.right.width,
      b.bottom.style == BorderStyle.none ? 0 : b.bottom.width,
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget content = Padding(padding: padding + _borderInsets, child: child);
    if (clipContent) {
      content = ClipRRect(borderRadius: borderRadius, child: content);
    }

    final layers = <Widget>[];
    if (backdropBlur > 0) {
      layers.add(
        Positioned.fill(
          child: ClipRRect(
            borderRadius: borderRadius,
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: backdropBlur, sigmaY: backdropBlur, tileMode: TileMode.clamp),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );
    }
    if (color != null && gradient != null) {
      layers.add(
        Positioned.fill(
          child: DecoratedBox(decoration: BoxDecoration(color: color, borderRadius: borderRadius)),
        ),
      );
    }
    if (color != null || gradient != null || border != null) {
      layers.add(
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: gradient == null ? color : null,
              gradient: gradient,
              border: border,
              borderRadius: border == null || border!.isUniform ? borderRadius : null,
            ),
          ),
        ),
      );
    }
    if (dashedBorder != null) {
      layers.add(
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: DashedBorderPainter(
                color: dashedBorder!.color,
                strokeWidth: dashedBorder!.width,
                borderRadius: borderRadius,
                dash: dashedBorder!.width * 3,
                gap: dashedBorder!.width * 3,
              ),
            ),
          ),
        ),
      );
    }

    Widget result = layers.isEmpty
        ? content
        : Stack(fit: StackFit.passthrough, clipBehavior: Clip.none, children: [...layers, content]);

    if (shadows.isNotEmpty) {
      result = CustomPaint(
        painter: CssShadowPainter(shadows: shadows, borderRadius: borderRadius),
        child: result,
      );
    }

    if (width != null || height != null) {
      result = SizedBox(width: width, height: height, child: result);
    }
    if (constraints != null) {
      result = ConstrainedBox(constraints: constraints!, child: result);
    }
    if (opacity < 1) {
      result = Opacity(opacity: opacity, child: result);
    }
    return result;
  }
}
