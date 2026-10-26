import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../sky/sky_constellation.dart';
import '../sky/sky_painter.dart';
import '../sky/sky_scene.dart';
import '../sky/sky_tokens.dart';
import 'sky_widget_state.dart';

@immutable
class SkyWidgetImages {
  const SkyWidgetImages({required this.sky, this.stars});

  final Uint8List sky;
  final Uint8List? stars;
}

class SkyWidgetArt {
  const SkyWidgetArt({this.side = designSide, this.skyRatio = 2, this.starsRatio = 2.5});

  static const double designSide = 240;
  static const double margin = 28;

  static const SkyScene backdrop = SkyScene(
    seed: 11,
    stars: 44,
    dayStars: 8,
    sunAt: Offset(24, 236),
    clouds: [SkyCloud(196, 36, scale: 0.6, opacity: 0.75), SkyCloud(34, 150, scale: 0.42, opacity: 0.5)],
    horizonGlow: true,
    twinkle: false,
    designWidth: designSide,
  );

  final double side;
  final double skyRatio;
  final double starsRatio;

  int get skyPixels => (side * skyRatio).round();

  int get starsPixels => (side * starsRatio).round();

  static SkyConstellation? figureFor(SkyWidgetState state) =>
      state.constellation?.fitted(const Rect.fromLTWH(0, 0, designSide, designSide), margin: margin);

  static SkyScene starsScene(SkyConstellation figure) => SkyScene(
    stars: 0,
    dayStars: 0,
    sun: false,
    clouds: const [],
    haze: false,
    twinkle: false,
    constellation: figure,
    designWidth: designSide,
  );

  Future<SkyWidgetImages> render(SkyWidgetState state) async {
    final tokens = SkyTokens.of(state.mode);
    final sky = await _png(
      skyRatio,
      (canvas, size) => SkyBackdropPainter(scene: backdrop, tokens: tokens).paint(canvas, size),
    );
    final figure = figureFor(state);
    if (figure == null) return SkyWidgetImages(sky: sky);
    final time = SkyTime();
    try {
      final stars = await _png(
        starsRatio,
        (canvas, size) => SkyLivePainter(scene: starsScene(figure), tokens: tokens, time: time).paint(canvas, size),
      );
      return SkyWidgetImages(sky: sky, stars: stars);
    } finally {
      time.dispose();
    }
  }

  Future<Uint8List> _png(double ratio, void Function(Canvas canvas, Size size) draw) async {
    final pixels = (side * ratio).round();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(ratio);
    draw(canvas, Size.square(side));
    final picture = recorder.endRecording();
    final image = await picture.toImage(pixels, pixels);
    picture.dispose();
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('The sky could not be drawn.');
      return data.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }
}
