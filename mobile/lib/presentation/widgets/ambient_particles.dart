import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/app_colors.dart';
import 'tw_animations.dart';

enum ParticleKind { heart, sparkle }

@immutable
class AmbientParticle {
  const AmbientParticle({
    required this.x,
    required this.drift,
    required this.size,
    required this.duration,
    required this.delay,
    required this.kind,
    required this.opacity,
  });

  factory AmbientParticle.random(int index, math.Random random) {
    final x = random.nextDouble() * 100;
    final size = random.nextDouble() * 12 + 10;
    final duration = random.nextDouble() * 15 + 12;
    final delay = random.nextDouble() * 8;
    final opacity = random.nextDouble() * 0.35 + 0.15;
    final drift = random.nextDouble() * 6 - 3;
    return AmbientParticle(
      x: x,
      drift: drift,
      size: size,
      duration: duration,
      delay: delay,
      kind: index % 3 == 0 ? ParticleKind.sparkle : ParticleKind.heart,
      opacity: opacity,
    );
  }

  static const String heartAsset = 'assets/svg/particle-heart.svg';
  static const String sparkleAsset = 'assets/svg/particle-sparkle.svg';

  final double x;
  final double drift;
  final double size;
  final double duration;
  final double delay;
  final ParticleKind kind;
  final double opacity;

  Size get box => Size(size * 0.75, size * 1.5);

  double get shapeSize => kind == ParticleKind.heart ? size * 0.7 : size * 0.75;

  static double rotationDegreesAt(double progress) {
    const frames = [0.0, 15.0, -15.0, 0.0];
    final scaled = progress.clamp(0.0, 1.0) * (frames.length - 1);
    final i = scaled.floor().clamp(0, frames.length - 2);
    final t = scaled - i;
    return frames[i] + (frames[i + 1] - frames[i]) * t;
  }

  double progressAt(double elapsedSeconds) {
    final t = elapsedSeconds - delay;
    if (t <= 0) return 0;
    return (t % duration) / duration;
  }

  Offset positionAt(double elapsedSeconds, Size viewport) {
    final p = progressAt(elapsedSeconds);
    final vw = viewport.width / 100;
    final vh = viewport.height / 100;
    return Offset((x + x + drift * p) * vw, (105 + (-10 - 105) * p) * vh);
  }
}

class AmbientParticles extends StatefulWidget {
  const AmbientParticles({super.key, this.count = 14, this.seed, this.color = AppColors.blush400});

  final int count;
  final int? seed;
  final Color color;

  @override
  State<AmbientParticles> createState() => _AmbientParticlesState();
}

class _AmbientParticlesState extends State<AmbientParticles> with SingleTickerProviderStateMixin {
  late List<AmbientParticle> _particles = _generate();
  late final Ticker _ticker = createTicker(_onTick);
  final ValueNotifier<double> _elapsed = ValueNotifier<double>(0);
  final Map<ParticleKind, PictureInfo> _pictures = {};
  Color? _loadedColor;
  int _loadGeneration = 0;

  List<AmbientParticle> _generate() {
    final random = math.Random(widget.seed);
    return [for (var i = 0; i < widget.count; i++) AmbientParticle.random(i, random)];
  }

  void _onTick(Duration elapsed) {
    _elapsed.value = elapsed.inMicroseconds / 1e6;
  }

  void _releasePictures() {
    for (final info in _pictures.values) {
      info.picture.dispose();
    }
    _pictures.clear();
  }

  Future<void> _loadPictures(Color color) async {
    final generation = ++_loadGeneration;
    final theme = SvgTheme(currentColor: color);
    final bundle = DefaultAssetBundle.of(context);
    final results = <ParticleKind, PictureInfo>{};
    try {
      results[ParticleKind.heart] = await vg.loadPicture(
        SvgAssetLoader(AmbientParticle.heartAsset, assetBundle: bundle, theme: theme),
        null,
      );
      results[ParticleKind.sparkle] = await vg.loadPicture(
        SvgAssetLoader(AmbientParticle.sparkleAsset, assetBundle: bundle, theme: theme),
        null,
      );
    } catch (_) {
      for (final info in results.values) {
        info.picture.dispose();
      }
      return;
    }
    if (!mounted || generation != _loadGeneration) {
      for (final info in results.values) {
        info.picture.dispose();
      }
      return;
    }
    setState(() {
      _releasePictures();
      _pictures.addAll(results);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final allowed = motionAllowed(context);
    if (allowed && !_ticker.isActive) {
      _ticker.start();
    } else if (!allowed && _ticker.isActive) {
      _ticker.stop();
    }
    if (_loadedColor != widget.color) {
      _loadedColor = widget.color;
      _loadPictures(widget.color);
    }
  }

  @override
  void didUpdateWidget(covariant AmbientParticles oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.count != widget.count || oldWidget.seed != widget.seed) {
      _particles = _generate();
    }
    if (_loadedColor != widget.color) {
      _loadedColor = widget.color;
      _loadPictures(widget.color);
    }
  }

  @override
  void dispose() {
    _loadGeneration++;
    _ticker.dispose();
    _elapsed.dispose();
    _releasePictures();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: CustomPaint(
            size: Size.infinite,
            painter: _ParticlePainter(
              particles: _particles,
              pictures: Map.of(_pictures),
              elapsed: _elapsed,
            ),
          ),
        ),
      ),
    );
  }
}

class _ParticlePainter extends CustomPainter {
  _ParticlePainter({required this.particles, required this.pictures, required this.elapsed})
    : super(repaint: elapsed);

  final List<AmbientParticle> particles;
  final Map<ParticleKind, PictureInfo> pictures;
  final ValueNotifier<double> elapsed;

  @override
  void paint(Canvas canvas, Size size) {
    if (pictures.isEmpty) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final seconds = elapsed.value;
    for (final p in particles) {
      final info = pictures[p.kind];
      if (info == null || info.size.isEmpty) continue;
      final origin = p.positionAt(seconds, size);
      final box = p.box;
      final center = origin + Offset(box.width / 2, box.height / 2);
      if (center.dy < -box.height || center.dy > size.height + box.height) continue;
      if (center.dx < -box.width || center.dx > size.width + box.width) continue;
      final shape = p.shapeSize;
      final angle = AmbientParticle.rotationDegreesAt(p.progressAt(seconds)) * math.pi / 180;
      final bounds = Rect.fromCenter(center: center, width: shape * 1.6, height: shape * 1.6);
      canvas.saveLayer(bounds, Paint()..color = ui.Color.fromRGBO(0, 0, 0, p.opacity));
      canvas.translate(center.dx, center.dy);
      canvas.rotate(angle);
      canvas.translate(-shape / 2, -shape / 2);
      canvas.scale(shape / info.size.width, shape / info.size.height);
      canvas.drawPicture(info.picture);
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ParticlePainter oldDelegate) {
    return oldDelegate.particles != particles || !_samePictures(oldDelegate.pictures, pictures);
  }

  static bool _samePictures(Map<ParticleKind, PictureInfo> a, Map<ParticleKind, PictureInfo> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!identical(b[entry.key], entry.value)) return false;
    }
    return true;
  }
}
