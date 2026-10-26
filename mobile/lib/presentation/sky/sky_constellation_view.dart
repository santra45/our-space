import 'package:flutter/widgets.dart';

import 'sky_constellation.dart';
import 'sky_painter.dart';
import 'sky_scene.dart';
import 'sky_tokens.dart';

class SkyConstellationView extends StatefulWidget {
  const SkyConstellationView({
    super.key,
    required this.constellation,
    this.margin = 24,
    this.designWidth = 390,
    this.onStar,
  });

  final SkyConstellation constellation;
  final double margin;
  final double designWidth;
  final ValueChanged<int>? onStar;

  static double scaleFor(Size size, {double designWidth = 390}) =>
      size.width <= 0 ? 1 : size.width / designWidth;

  static SkyConstellation fit(
    SkyConstellation constellation,
    Size size, {
    double margin = 24,
    double designWidth = 390,
  }) {
    final k = scaleFor(size, designWidth: designWidth);
    return constellation.fitted(Rect.fromLTWH(0, 0, designWidth, size.height / k), margin: margin);
  }

  static int? starAt(
    SkyConstellation constellation,
    Size size,
    Offset local, {
    double margin = 24,
    double designWidth = 390,
  }) {
    final k = scaleFor(size, designWidth: designWidth);
    final fitted = fit(constellation, size, margin: margin, designWidth: designWidth);
    return fitted.starAt(local / k, radius: SkyConstellation.hitRadius / k);
  }

  @override
  State<SkyConstellationView> createState() => _SkyConstellationViewState();
}

class _SkyConstellationViewState extends State<SkyConstellationView> {
  final SkyTime _time = SkyTime();

  @override
  void dispose() {
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.sky;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final fitted = SkyConstellationView.fit(
          widget.constellation.copyWith(presence: false, burst: false),
          size,
          margin: widget.margin,
          designWidth: widget.designWidth,
        );
        final scene = SkyScene(
          stars: 0,
          dayStars: 0,
          sun: false,
          clouds: const [],
          haze: false,
          twinkle: false,
          constellation: fitted,
          designWidth: widget.designWidth,
        );
        final paint = RepaintBoundary(
          child: CustomPaint(
            size: size,
            painter: SkyLivePainter(scene: scene, tokens: tokens, time: _time),
          ),
        );
        final onStar = widget.onStar;
        if (onStar == null) return paint;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) {
            final slot = SkyConstellationView.starAt(
              widget.constellation,
              size,
              details.localPosition,
              margin: widget.margin,
              designWidth: widget.designWidth,
            );
            if (slot != null) onStar(slot);
          },
          child: paint,
        );
      },
    );
  }
}
