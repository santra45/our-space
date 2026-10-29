import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../../../sky/sky.dart';
import 'sky_gate.dart';
import 'sky_together_copy.dart';
import 'sky_together_fx.dart';
import 'sky_together_home.dart';

abstract final class SkyTogetherKeys {
  static const Key layer = ValueKey<String>('sky-together-layer');
  static const Key target = ValueKey<String>('sky-together-target');
  static const Key patch = ValueKey<String>('sky-together-patch');
  static const Key frame = ValueKey<String>('sky-together-frame');
  static const Key help = ValueKey<String>('sky-together-help');
  static const Key startOver = ValueKey<String>('sky-together-start-over');
  static const Key done = ValueKey<String>('sky-together-done');
  static const Key name = ValueKey<String>('sky-together-name');
  static const Key skyName = ValueKey<String>('sky-together-sky-name');
  static const Key agree = ValueKey<String>('sky-together-agree');
  static const Key changeIt = ValueKey<String>('sky-together-change-it');
  static const Key pill = ValueKey<String>('sky-together-pill');

  static Key star(String id) => ValueKey<String>('sky-together-star-$id');
}

abstract final class SkyTogetherLine {
  static String? textFor(SkyTogetherStage stage, {required bool night, required String partner}) => switch (stage) {
    SkyTogetherStage.off => null,
    SkyTogetherStage.invite || SkyTogetherStage.partnerHolding => SkyTogetherCopy.hold(night),
    SkyTogetherStage.alone => SkyTogetherCopy.waiting(partner),
    SkyTogetherStage.together || SkyTogetherStage.opening => SkyTogetherCopy.bothHolding,
  };

  static TextStyle style(SkyTokens t, {double size = 15}) => SkyType.serif(size, weight: FontWeight.w500, height: 1.2)
      .copyWith(
        color: t.label,
        shadows: t.isNight
            ? const [
                Shadow(color: Color(0xD9050418), offset: Offset(0, 1), blurRadius: 8),
                Shadow(color: Color(0x99050418), blurRadius: 2),
              ]
            : const [
                Shadow(color: Color(0xF2FFFFFF), offset: Offset(0, 1), blurRadius: 8),
                Shadow(color: Color(0xE6FFFFFF), blurRadius: 2),
              ],
      );

  static const int maxLines = 2;

  static Size measure(
    String text,
    TextStyle style,
    TextScaler scaler, {
    double maxWidth = double.infinity,
    int lines = maxLines,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      textScaler: scaler,
      maxLines: lines,
      ellipsis: '…',
      textWidthBasis: TextWidthBasis.longestLine,
    )..layout(maxWidth: maxWidth);
    final size = painter.size;
    painter.dispose();
    return size;
  }

  static Rect? rectFor(
    SkyTogetherStage stage, {
    required bool night,
    required String partner,
    required SkyTokens tokens,
    required TextScaler scaler,
    required double scale,
    double start = SkyTogetherSpot.lineMin,
  }) {
    final text = textFor(stage, night: night, partner: partner);
    if (text == null) return null;
    final room = SkyTogetherSpot.lineRoom(start) * scale;
    final lines = SkyTogetherSpot.lineLines(start);
    final size = measure(text, style(tokens), scaler, maxWidth: room, lines: lines) / scale;
    return SkyTogetherSpot.lineRect(size, night: night, start: start);
  }
}

class SkyTogetherLayer extends StatefulWidget {
  const SkyTogetherLayer({
    super.key,
    required this.home,
    required this.constellation,
    required this.partner,
    this.moonPhase,
    this.topBar,
    this.titleEdge,
    this.designWidth = 390,
  });

  final SkyTogetherHome home;
  final SkyConstellation constellation;
  final String partner;
  final MoonPhase? moonPhase;
  final ValueListenable<double?>? topBar;
  final ValueListenable<double?>? titleEdge;
  final double designWidth;

  @override
  State<SkyTogetherLayer> createState() => _SkyTogetherLayerState();
}

class _SkyTogetherLayerState extends State<SkyTogetherLayer> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  final ValueNotifier<SkyTogetherPaint?> _frame = ValueNotifier<SkyTogetherPaint?>(null);
  static const Duration _rest = Duration(milliseconds: 28);

  Duration? _origin;
  Timer? _resting;
  bool _fresh = true;
  double _now = 0;
  double _last = 0;
  bool _motion = true;
  bool _night = true;
  late SkyTogetherStage _stage = widget.home.stage;
  double _presence = 0;
  double? _presenceOnAt;
  double? _presenceOffAt;
  double _presenceFrom = 0;
  double _sun = 0;
  double? _sunOnAt;
  double _hint = 0;
  double _track = 0;
  double _finger = 0;
  double _mine = 0;
  double _theirs = 0;
  double _arc = 0;
  double _thread = 0;
  double? _retractAt;
  double _retractFrom = 0;

  @override
  void initState() {
    super.initState();
    widget.home.addListener(_onHome);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motion = skyMotionAllowed(context);
    _night = context.sky.isNight;
    _compute();
    _wake();
  }

  @override
  void didUpdateWidget(covariant SkyTogetherLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.home, widget.home)) {
      oldWidget.home.removeListener(_onHome);
      widget.home.addListener(_onHome);
      _stage = widget.home.stage;
    }
    _compute();
    _wake();
  }

  void _onHome() {
    if (!mounted) return;
    final next = widget.home.stage;
    if (next != _stage) {
      final wasTogether = _stage == SkyTogetherStage.together;
      if (wasTogether && next != SkyTogetherStage.opening && next != SkyTogetherStage.together) {
        _retractAt = _now;
        _retractFrom = _thread;
      }
      _stage = next;
      setState(() {});
    }
    _compute();
    _wake();
  }

  bool get _settled {
    final stage = _stage;
    final invite = stage != SkyTogetherStage.off;
    final holding = widget.home.holding || stage == SkyTogetherStage.opening;
    bool at(double v, bool on) => on ? v >= 1 : v <= 0;
    final sunDone = _night || (at(_sun, invite) && (_sunOnAt == null || _now - _sunOnAt! >= 0.7));
    final cloudDone = _night || !_motion || (invite ? (_presenceOnAt == null || _now - _presenceOnAt! >= 2.4) : _presenceOffAt == null || _now - _presenceOffAt! >= 1.2);
    return at(_presence, invite) &&
        sunDone &&
        cloudDone &&
        at(_hint, stage == SkyTogetherStage.invite || stage == SkyTogetherStage.partnerHolding) &&
        at(_track, holding) &&
        at(_finger, widget.home.holding) &&
        at(_mine, widget.home.holding) &&
        at(_theirs, widget.home.partnerHolding && stage != SkyTogetherStage.off) &&
        _retractAt == null;
  }

  bool get _wanted => widget.home.needsTicks || (_motion && _stage != SkyTogetherStage.off) || !_settled;

  bool get _ambient => !widget.home.needsTicks && _settled;

  void _wake() {
    if (!mounted) return;
    if (!_wanted) {
      _resting?.cancel();
      _resting = null;
      if (_ticker.isActive) _ticker.stop();
      _fresh = true;
      return;
    }
    if (_resting != null && !_ambient) {
      _resting!.cancel();
      _resting = null;
    }
    if (!_ticker.isActive && _resting == null) _ticker.start();
  }

  void _onTick(Duration _) {
    final stamp = SchedulerBinding.instance.currentFrameTimeStamp;
    final origin = _origin ??= stamp;
    _now = (stamp - origin).inMicroseconds / 1e6;
    if (_fresh) {
      _last = _now;
      _fresh = false;
    }
    widget.home.tick();
    if (!mounted) return;
    _compute();
    if (!_wanted) {
      _ticker.stop();
      _fresh = true;
      return;
    }
    if (_ambient) {
      _ticker.stop();
      _resting = Timer(_rest, () {
        _resting = null;
        _wake();
      });
    }
  }

  static double _toward(double value, double target, double dt, double seconds) {
    if (seconds <= 0) return target;
    final step = dt / seconds;
    if (value < target) return math.min(target, value + step);
    return math.max(target, value - step);
  }

  void _compute() {
    final home = widget.home;
    final stage = _stage;
    final dt = math.max(0.0, _now - _last);
    _last = _now;
    final invite = stage != SkyTogetherStage.off;
    final motion = _motion;
    final night = _night;
    final figure = widget.constellation;
    final me = figure.pointAt(figure.me);
    final partner = figure.pointAt(figure.partner);
    final body = SkyTogetherSpot.body(night);

    if (invite && (_presenceOnAt == null || _presenceOffAt != null)) {
      _presenceOnAt = _now;
      _presenceOffAt = null;
      _sunOnAt = _now;
    } else if (!invite && _presenceOnAt != null && _presenceOffAt == null) {
      _presenceOffAt = _now;
      _presenceFrom = _presence;
    }

    var cloudShift = Offset.zero;
    if (!motion) {
      _presence = _toward(_presence, invite ? 1 : 0, dt, 0.2);
    } else if (night) {
      _presence = _toward(_presence, invite ? 1 : 0, dt, 0.3);
    } else if (invite) {
      final t = _now - (_presenceOnAt ?? _now);
      _presence = (t / 0.6).clamp(0.0, 1.0);
      final start = 420 - (partner.dx + SkyTogetherSpot.cloudRest.dx);
      cloudShift = Offset(start * (1 - Curves.easeOutCubic.transform((t / 2.4).clamp(0.0, 1.0))), 0);
    } else {
      final t = ((_now - (_presenceOffAt ?? _now)) / 1.2).clamp(0.0, 1.0);
      _presence = _presenceFrom * (1 - t);
      cloudShift = Offset(60 * Curves.easeIn.transform(t), 0);
    }

    var sunScale = 1.0;
    if (!night) {
      if (invite && motion) {
        final t = ((_now - (_sunOnAt ?? _now)) / 0.7).clamp(0.0, 1.0);
        _sun = t;
        sunScale = 0.6 + 0.4 * Curves.easeOutBack.transform(t);
      } else {
        _sun = _toward(_sun, invite ? 1 : 0, dt, motion ? 0.3 : 0.15);
      }
    } else {
      _sun = 0;
    }

    final holding = home.holding || stage == SkyTogetherStage.opening;
    final hinting = stage == SkyTogetherStage.invite || stage == SkyTogetherStage.partnerHolding;
    _hint = _toward(_hint, hinting ? 1 : 0, dt, 0.2);
    _track = _toward(_track, holding ? 1 : 0, dt, holding ? 0.15 : 0.3);
    _finger = _toward(_finger, home.holding ? 1 : 0, dt, 0.15);
    _mine = _toward(_mine, home.holding ? 1 : 0, dt, 0.2);
    _theirs = _toward(_theirs, home.partnerHolding && invite ? 1 : 0, dt, 0.2);

    final progress = stage == SkyTogetherStage.opening ? 1.0 : home.progress();
    if (holding) _arc = progress;

    var threadAlpha = 1.0;
    if (stage == SkyTogetherStage.together || stage == SkyTogetherStage.opening) {
      _thread = progress;
      _retractAt = null;
    } else if (_retractAt != null) {
      final t = ((_now - _retractAt!) / 0.45).clamp(0.0, 1.0);
      _thread = _retractFrom * (1 - Curves.easeIn.transform(t));
      threadAlpha = 1 - 0.3 * t;
      if (t >= 1 || !motion) {
        _retractAt = null;
        _thread = 0;
      }
    } else {
      _thread = 0;
    }

    var beat = 0.0;
    int? sinceLub;
    if (stage == SkyTogetherStage.together && motion) {
      final shared = home.link.sharedNow();
      final since = shared - SkyHeartbeat.beatAt(SkyHeartbeat.beatOf(shared));
      beat = skyBeatEnvelope(since);
      sinceLub = since;
    }

    var bodyScale = 1.0;
    if (motion) {
      if (stage == SkyTogetherStage.alone) {
        bodyScale = 1.03 + 0.03 * math.sin(_now * 2 * math.pi / 2.4);
      } else if (stage == SkyTogetherStage.together) {
        bodyScale = 1 + 0.22 * beat;
      }
    }
    if (!night && holding) bodyScale *= 1.08;

    _frame.value = SkyTogetherPaint(
      night: night,
      motion: motion,
      seconds: _now,
      body: body,
      me: me,
      partner: partner,
      thread: SkyThread(me, partner, centre: figure.bounds.center),
      moonPhase: widget.moonPhase,
      presence: _presence,
      cloudShift: cloudShift,
      sun: _sun,
      sunScale: sunScale,
      hint: _hint,
      track: _track,
      arc: _arc,
      hot: night ? _track : 0,
      bodyScale: bodyScale,
      finger: _finger,
      myRing: _mine,
      partnerRing: _theirs,
      threadLevel: _thread,
      threadAlpha: threadAlpha,
      beat: beat,
      sinceLub: sinceLub,
    );
  }

  @override
  void dispose() {
    widget.home.removeListener(_onHome);
    _resting?.cancel();
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topBar = widget.topBar;
    if (topBar == null) return _build(context, null);
    return ValueListenableBuilder<double?>(
      valueListenable: topBar,
      builder: (context, height, _) => _build(context, height),
    );
  }

  Widget _build(BuildContext context, double? topBar) {
    final t = context.sky;
    final stage = _stage;
    final night = t.isNight;
    final motion = skyMotionAllowed(context);
    final body = SkyTogetherSpot.body(night);
    final text = SkyTogetherLine.textFor(stage, night: night, partner: widget.partner);
    return LayoutBuilder(
      builder: (context, box) {
        final k = box.maxWidth.isFinite && box.maxWidth > 0 ? box.maxWidth / widget.designWidth : 1.0;
        final edge = widget.titleEdge?.value;
        final start = SkyTogetherSpot.lineStart(
          topBarBottom: topBar == null ? null : topBar / k,
          titleEdge: edge == null ? null : edge / k,
          night: night,
        );
        final top = SkyTogetherSpot.lineTop(night) * k;
        final line = text == null
            ? const SizedBox.shrink(key: ValueKey<String>('sky-together-no-line'))
            : CustomSingleChildLayout(
                key: ValueKey<String>('sky-together-line-$text'),
                delegate: _LineLayout(
                  centre: body.dx * k,
                  top: top,
                  min: start * k,
                  max: SkyTogetherSpot.lineMax * k,
                ),
                child: Text(
                  text,
                  style: SkyTogetherLine.style(t),
                  maxLines: SkyTogetherSpot.lineLines(start),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  textWidthBasis: TextWidthBasis.longestLine,
                ),
              );
        return Stack(
          key: SkyTogetherKeys.layer,
          fit: StackFit.expand,
          children: [
            IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: SkyTogetherFxPainter(frame: _frame, tokens: t, designWidth: widget.designWidth),
                ),
              ),
            ),
            IgnorePointer(
              child: ExcludeSemantics(
                excluding: text == null,
                child: AnimatedSwitcher(
                  duration: motion ? SkyMotion.quick : Duration.zero,
                  layoutBuilder: (current, previous) =>
                      Stack(fit: StackFit.expand, children: [...previous, ?current]),
                  child: line,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class SkyTogetherTarget extends StatelessWidget {
  const SkyTogetherTarget({super.key, required this.home, required this.partner, this.designWidth = 390});

  final SkyTogetherHome home;
  final String partner;
  final double designWidth;

  @override
  Widget build(BuildContext context) {
    final night = context.sky.isNight;
    return ListenableBuilder(
      listenable: home,
      builder: (context, _) {
        if (home.stage == SkyTogetherStage.off) return const SizedBox.shrink();
        final body = SkyTogetherSpot.body(night);
        return LayoutBuilder(
          builder: (context, box) {
            final k = box.maxWidth.isFinite && box.maxWidth > 0 ? box.maxWidth / designWidth : 1.0;
            final size = SkyTogetherSpot.hit * 2 * k;
            return Stack(
              children: [
                Positioned(
                  left: body.dx * k - size / 2,
                  top: body.dy * k - size / 2,
                  width: size,
                  height: size,
                  child: Semantics(
                    key: SkyTogetherKeys.target,
                    container: true,
                    button: true,
                    label: SkyTogetherCopy.holdLabel(night, partner),
                    hint: SkyTogetherCopy.holdHint(partner),
                    value: home.holding ? SkyTogetherCopy.holdingOn : null,
                    onTap: home.toggle,
                    child: _CircleHit(
                      child: Listener(
                        behavior: HitTestBehavior.opaque,
                        onPointerDown: (_) => home.press(),
                        onPointerUp: (_) => home.release(),
                        onPointerCancel: (_) => home.release(),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _LineLayout extends SingleChildLayoutDelegate {
  const _LineLayout({required this.centre, required this.top, required this.min, required this.max});

  final double centre;
  final double top;
  final double min;
  final double max;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => BoxConstraints(maxWidth: math.max(0, max - min));

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final left = (centre - childSize.width / 2).clamp(min, math.max(min, max - childSize.width)).toDouble();
    return Offset(left, top);
  }

  @override
  bool shouldRelayout(_LineLayout oldDelegate) =>
      oldDelegate.centre != centre || oldDelegate.top != top || oldDelegate.min != min || oldDelegate.max != max;
}

class _CircleHit extends SingleChildRenderObjectWidget {
  const _CircleHit({required Widget super.child});

  @override
  RenderProxyBox createRenderObject(BuildContext context) => _RenderCircleHit();
}

class _RenderCircleHit extends RenderProxyBox {
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final radius = size.shortestSide / 2;
    if ((position - size.center(Offset.zero)).distance > radius) return false;
    return super.hitTest(result, position: position);
  }
}
