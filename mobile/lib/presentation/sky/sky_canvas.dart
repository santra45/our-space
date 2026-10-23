import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'sky_motion.dart';
import 'sky_painter.dart';
import 'sky_scene.dart';
import 'sky_tokens.dart';

enum SkyPointKind { me, partner, gap, heart, moon, design }

@immutable
class SkyPoint {
  const SkyPoint.me() : kind = SkyPointKind.me, index = 0, design = Offset.zero;

  const SkyPoint.partner() : kind = SkyPointKind.partner, index = 0, design = Offset.zero;

  const SkyPoint.gap() : kind = SkyPointKind.gap, index = 0, design = Offset.zero;

  const SkyPoint.heart(this.index) : kind = SkyPointKind.heart, design = Offset.zero;

  const SkyPoint.moon() : kind = SkyPointKind.moon, index = 0, design = Offset.zero;

  const SkyPoint.design(this.design) : kind = SkyPointKind.design, index = 0;

  final SkyPointKind kind;
  final int index;
  final Offset design;

  Offset? resolve(SkyScene scene) {
    final heart = scene.heart;
    switch (kind) {
      case SkyPointKind.me:
        return heart?.pointAt(heart.me);
      case SkyPointKind.partner:
        return heart?.pointAt(heart.partner);
      case SkyPointKind.gap:
        final gap = heart?.gap;
        return gap == null ? null : heart!.pointAt(gap);
      case SkyPointKind.heart:
        return heart?.pointAt(index);
      case SkyPointKind.moon:
        return scene.moon;
      case SkyPointKind.design:
        return design;
    }
  }
}

@immutable
class SkyAnchor {
  const SkyAnchor({
    required this.at,
    required this.child,
    this.offset = Offset.zero,
    this.alignment = Alignment.topCenter,
  });

  final SkyPoint at;
  final Offset offset;
  final Alignment alignment;
  final Widget child;
}

class SkyCanvas extends StatefulWidget {
  const SkyCanvas({super.key, required this.scene, this.anchors = const [], this.animate = true});

  final SkyScene scene;
  final List<SkyAnchor> anchors;
  final bool animate;

  @override
  State<SkyCanvas> createState() => _SkyCanvasState();
}

class _SkyCanvasState extends State<SkyCanvas> with SingleTickerProviderStateMixin {
  static const Duration _rest = Duration(milliseconds: 28);
  static const Duration _queued = Duration(microseconds: -1);

  late final Ticker _ticker = createTicker(_tick);
  final SkyTime _time = SkyTime();
  bool _motion = false;
  Timer? _wake;
  Duration? _origin;
  Duration _now = Duration.zero;
  Duration? _burstFrom;
  Duration? _streakFrom;

  bool get _bursting => widget.scene.heart?.burst == true && widget.scene.heart?.complete == true;

  bool get _playing => _burstFrom != null || _streakFrom != null;

  @override
  void initState() {
    super.initState();
    if (_bursting) _burstFrom = _queued;
    if (widget.scene.shootingStar != null) _streakFrom = _queued;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant SkyCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wasBursting = oldWidget.scene.heart?.burst == true && oldWidget.scene.heart?.complete == true;
    if (_bursting && !wasBursting) _burstFrom = _queued;
    if (widget.scene.shootingStar != null && oldWidget.scene.shootingStar != widget.scene.shootingStar) {
      _streakFrom = _queued;
    }
    _syncMotion();
  }

  bool get _hasLife {
    final scene = widget.scene;
    return scene.twinkle || scene.heart != null || scene.shootingStar != null;
  }

  void _syncMotion() {
    _motion = widget.animate && skyMotionAllowed(context) && _hasLife;
    if (!_motion) {
      _wake?.cancel();
      _wake = null;
      if (_ticker.isActive) _ticker.stop();
      _origin = null;
      _burstFrom = null;
      _streakFrom = null;
      _time.set(seconds: 0, burst: 1, streak: 1);
      return;
    }
    if (_ticker.isActive || (_wake != null && !_playing)) return;
    _wake?.cancel();
    _wake = null;
    _ticker.start();
  }

  void _resume() {
    _wake = null;
    if (!mounted || !_motion || _ticker.isActive) return;
    _ticker.start();
  }

  double _progress(Duration? from, Duration length) {
    if (from == null) return 1;
    final t = (_now - from).inMicroseconds / length.inMicroseconds;
    return t.clamp(0.0, 1.0);
  }

  void _tick(Duration _) {
    final stamp = SchedulerBinding.instance.currentFrameTimeStamp;
    final origin = _origin ??= stamp;
    _now = stamp - origin;
    if (_burstFrom == _queued) _burstFrom = _now;
    if (_streakFrom == _queued) _streakFrom = _now;
    final burst = _progress(_burstFrom, SkyMotion.burst);
    final streak = _progress(_streakFrom, SkyMotion.streak);
    if (burst >= 1) _burstFrom = null;
    if (streak >= 1) _streakFrom = null;
    final seconds = _now.inMicroseconds / 1e6;
    _time.set(seconds: seconds == 0 ? 0.0001 : seconds, burst: burst, streak: streak);
    if (_playing) return;
    _ticker.stop();
    _wake = Timer(_rest, _resume);
  }

  @override
  void dispose() {
    _wake?.cancel();
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.sky;
    final scene = widget.scene;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final k = size.width.isFinite ? scene.scaleFor(size) : 1.0;
        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.hardEdge,
          children: [
            RepaintBoundary(
              child: CustomPaint(
                painter: SkyBackdropPainter(scene: scene, tokens: tokens),
                isComplex: true,
              ),
            ),
            RepaintBoundary(
              child: CustomPaint(
                painter: SkyLivePainter(scene: scene, tokens: tokens, time: _time),
              ),
            ),
            for (final anchor in widget.anchors)
              if (anchor.at.resolve(scene) case final Offset point)
                Positioned(
                  left: (point.dx + anchor.offset.dx) * k,
                  top: (point.dy + anchor.offset.dy) * k,
                  child: FractionalTranslation(
                    translation: Offset(-(anchor.alignment.x + 1) / 2, -(anchor.alignment.y + 1) / 2),
                    child: anchor.child,
                  ),
                ),
          ],
        );
      },
    );
  }
}

class SkyBackdrop extends StatelessWidget {
  const SkyBackdrop({
    super.key,
    this.scene = SkyScene.page,
    this.fade = false,
    this.fadeFraction = 0.55,
    this.anchors = const [],
    this.animate = true,
  });

  final SkyScene scene;
  final bool fade;
  final double fadeFraction;
  final List<SkyAnchor> anchors;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final page = context.sky.page;
    return Stack(
      fit: StackFit.expand,
      children: [
        SkyCanvas(scene: scene, anchors: anchors, animate: animate),
        if (fade)
          IgnorePointer(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                widthFactor: 1,
                heightFactor: fadeFraction,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [page.withValues(alpha: 0), page],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
