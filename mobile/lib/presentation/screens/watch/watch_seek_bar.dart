import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../sky/sky.dart';
import 'watch_copy.dart';

class WatchSeekBar extends StatefulWidget {
  const WatchSeekBar({
    super.key,
    required this.positionMs,
    required this.durationMs,
    required this.bufferedMs,
    required this.full,
    required this.onSeek,
    this.onPreview,
  });

  static const double height = 44;
  static const double side = 12;
  static const int stepMs = 10000;

  final int positionMs;
  final int durationMs;
  final int bufferedMs;
  final bool full;
  final ValueChanged<int> onSeek;
  final ValueChanged<int?>? onPreview;

  @override
  State<WatchSeekBar> createState() => _WatchSeekBarState();
}

class _WatchSeekBarState extends State<WatchSeekBar> {
  int? _dragging;

  int _at(double dx, double width) {
    final room = width - WatchSeekBar.side * 2;
    if (room <= 0) return 0;
    final fraction = ((dx - WatchSeekBar.side) / room).clamp(0.0, 1.0);
    return (fraction * widget.durationMs).round();
  }

  void _preview(int? ms) {
    setState(() => _dragging = ms);
    widget.onPreview?.call(ms);
  }

  void _finish() {
    final ms = _dragging;
    _preview(null);
    if (ms != null) widget.onSeek(ms);
  }

  void _step(int by) => widget.onSeek((widget.positionMs + by).clamp(0, widget.durationMs));

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final full = widget.full;
    final shown = _dragging ?? widget.positionMs.clamp(0, widget.durationMs);
    final motion = skyMotionAllowed(context);
    return Semantics(
      slider: true,
      label: WatchCopy.seekLabel,
      value: WatchCopy.clock(shown),
      increasedValue: WatchCopy.clock((shown + WatchSeekBar.stepMs).clamp(0, widget.durationMs)),
      decreasedValue: WatchCopy.clock((shown - WatchSeekBar.stepMs).clamp(0, widget.durationMs)),
      onIncrease: () => _step(WatchSeekBar.stepMs),
      onDecrease: () => _step(-WatchSeekBar.stepMs),
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, box) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => _preview(_at(details.localPosition.dx, box.maxWidth)),
            onTapUp: (_) => _finish(),
            onTapCancel: () => _preview(null),
            onHorizontalDragStart: (details) => _preview(_at(details.localPosition.dx, box.maxWidth)),
            onHorizontalDragUpdate: (details) => _preview(_at(details.localPosition.dx, box.maxWidth)),
            onHorizontalDragEnd: (_) => _finish(),
            onHorizontalDragCancel: () => _preview(null),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(end: _dragging == null ? 0 : 1),
              duration: motion ? SkyMotion.quick : Duration.zero,
              curve: SkyMotion.standard,
              builder: (context, grow, _) => RepaintBoundary(
                child: CustomPaint(
                  size: Size(box.maxWidth, WatchSeekBar.height),
                  painter: WatchSeekPainter(
                    played: widget.durationMs <= 0 ? 0 : shown / widget.durationMs,
                    buffered: widget.durationMs <= 0 ? 0 : widget.bufferedMs / widget.durationMs,
                    grow: grow,
                    bubble: _dragging == null ? null : WatchCopy.clock(shown),
                    gradient: t.progressGradient,
                    rest: full ? SkyTokens.white.withValues(alpha: 0.22) : t.toggleOff,
                    loaded: full ? SkyTokens.white.withValues(alpha: 0.42) : t.rose.withValues(alpha: 0.24),
                    star: full ? SkyTokens.white : t.rose,
                    halo: t.rose,
                    bubbleFill: full ? SkyTokens.white : t.text,
                    bubbleInk: full ? SkyTokens.indigo : t.surface,
                    bubbleStyle: SkyType.sans(11, weight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class WatchSeekPainter extends CustomPainter {
  const WatchSeekPainter({
    required this.played,
    required this.buffered,
    required this.grow,
    required this.bubble,
    required this.gradient,
    required this.rest,
    required this.loaded,
    required this.star,
    required this.halo,
    required this.bubbleFill,
    required this.bubbleInk,
    required this.bubbleStyle,
  });

  static const double trackY = 28;
  static const double trackHeight = 3;

  final double played;
  final double buffered;
  final double grow;
  final String? bubble;
  final Gradient gradient;
  final Color rest;
  final Color loaded;
  final Color star;
  final Color halo;
  final Color bubbleFill;
  final Color bubbleInk;
  final TextStyle bubbleStyle;

  @override
  void paint(Canvas canvas, Size size) {
    const side = WatchSeekBar.side;
    final width = math.max(0.0, size.width - side * 2);
    final head = side + width * played.clamp(0.0, 1.0);
    final load = side + width * buffered.clamp(0.0, 1.0);
    final thick = trackHeight + grow;
    RRect bar(double from, double to) => RRect.fromRectAndRadius(
      Rect.fromLTRB(from, trackY - thick / 2, to, trackY + thick / 2),
      Radius.circular(thick / 2),
    );

    canvas.drawRRect(bar(side, side + width), Paint()..color = rest);
    if (load > side) canvas.drawRRect(bar(side, load), Paint()..color = loaded);
    if (head > side) {
      canvas.drawRRect(
        bar(side, head),
        Paint()..shader = gradient.createShader(Rect.fromLTRB(side, trackY - thick, side + width, trackY + thick)),
      );
    }

    final center = Offset(head, trackY);
    final reach = 7.5 + 3.5 * grow;
    canvas.drawCircle(center, reach + 7, Paint()..color = halo.withValues(alpha: 0.12 + 0.14 * grow));
    canvas.drawPath(
      _sparkle(center, reach),
      Paint()
        ..color = star
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.solid, 1.2),
    );

    final text = bubble;
    if (text == null) return;
    final painter = TextPainter(
      text: TextSpan(text: text, style: bubbleStyle.copyWith(color: bubbleInk)),
      textDirection: TextDirection.ltr,
    )..layout();
    final pillWidth = painter.width + 12;
    final left = (head - pillWidth / 2).clamp(0.0, math.max(0.0, size.width - pillWidth)).toDouble();
    final top = math.max(0.0, trackY - reach - painter.height - 8);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(left, top, pillWidth, painter.height + 3), const Radius.circular(8)),
      Paint()..color = bubbleFill,
    );
    painter.paint(canvas, Offset(left + 6, top + 1.5));
    painter.dispose();
  }

  Path _sparkle(Offset c, double r) {
    final waist = r * 0.3;
    return Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx + waist * 0.35, c.dy - waist * 0.35, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx + waist * 0.35, c.dy + waist * 0.35, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx - waist * 0.35, c.dy + waist * 0.35, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx - waist * 0.35, c.dy - waist * 0.35, c.dx, c.dy - r)
      ..close();
  }

  @override
  bool shouldRepaint(WatchSeekPainter old) =>
      old.played != played ||
      old.buffered != buffered ||
      old.grow != grow ||
      old.bubble != bubble ||
      old.star != star ||
      old.rest != rest;
}
