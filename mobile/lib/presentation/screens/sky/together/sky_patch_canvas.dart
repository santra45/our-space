import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';

import '../../../../core/engine.dart';
import '../../../sky/sky.dart';
import '../../../widgets/app_haptics.dart';
import '../sky_sheet_layout.dart';
import 'sky_patch_art.dart';
import 'sky_patch_session.dart';
import 'sky_together_copy.dart';
import 'sky_together_layer.dart';

abstract final class SkyPatchFeel {
  static const double hit = 22;
  static const double snap = 28;
  static const double edge = 24;
  static const double slop = 8;
  static const Duration tap = Duration(milliseconds: 350);
  static const double appear = 0.22;
  static const double rings = 0.8;
  static const double pulse = 0.22;
  static const double grow = 0.18;
  static const double clear = 0.25;
  static const double retract = 0.15;
  static const double tail = 0.28;
  static const int tailPoints = 18;
  static const double smooth = 0.1;
  static const double cometFade = 0.4;
  static const double outside = 0.07;

  static Rect frameOf(Size size) {
    final side = math.min(size.width, size.height);
    return Rect.fromCenter(center: size.center(Offset.zero), width: side, height: side);
  }
}

class SkyPatchCanvas extends StatefulWidget {
  const SkyPatchCanvas({super.key, required this.session, required this.partner});

  final SkyPatchSession session;
  final String partner;

  @override
  State<SkyPatchCanvas> createState() => _SkyPatchCanvasState();
}

class _SkyPatchCanvasState extends State<SkyPatchCanvas> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  final ValueNotifier<SkyPatchPicture> _picture = ValueNotifier<SkyPatchPicture>(
    const SkyPatchPicture(night: true, stars: [], lines: []),
  );
  final ValueNotifier<SkyPatchLive> _live = ValueNotifier<SkyPatchLive>(SkyPatchLive.none);
  StreamSubscription<SkyPatchNotice>? _notices;
  double _base = 0;
  double _now = 0;
  double _last = 0;
  bool _motion = true;
  bool _night = true;
  double _k = 1;
  Size _size = Size.zero;

  final Map<String, double> _born = {};
  final Map<String, double> _rings = {};
  final Map<String, double> _pulses = {};
  final Map<String, double> _linesBorn = {};
  List<SkyPatchStar> _ghostStars = const [];
  List<SkyPatchLine> _ghostLines = const [];
  double? _ghostAt;
  int? _gen;
  bool _seeded = false;

  int? _pointer;
  Offset? _downAt;
  Duration _downStamp = Duration.zero;
  Offset? _finger;
  bool _dragging = false;
  String? _from;
  String? _snapped;
  Offset? _retractFrom;
  Offset? _retractTo;
  double? _retractAt;

  final List<SkyCometPoint> _tail = [];
  Offset? _head;
  double _comet = 0;

  SkyPatchSession get session => widget.session;

  @override
  void initState() {
    super.initState();
    _attach(widget.session);
  }

  void _attach(SkyPatchSession session) {
    session.addListener(_onSession);
    session.finger.addListener(_onFinger);
    _notices = session.notices.listen(_onNotice);
  }

  void _detach(SkyPatchSession session) {
    session.removeListener(_onSession);
    session.finger.removeListener(_onFinger);
    unawaited(_notices?.cancel());
    _notices = null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motion = skyMotionAllowed(context);
    _night = context.sky.isNight;
    _sync();
  }

  @override
  void didUpdateWidget(covariant SkyPatchCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.session, widget.session)) {
      _detach(oldWidget.session);
      _attach(widget.session);
      _seeded = false;
      _gen = null;
    }
    _sync();
  }

  @override
  void dispose() {
    _detach(widget.session);
    _ticker.dispose();
    _picture.dispose();
    _live.dispose();
    super.dispose();
  }

  void _onSession() {
    if (!mounted) return;
    _sync();
    setState(() {});
  }

  void _onFinger() {
    if (!mounted) return;
    _wake();
    _paintLive();
  }

  void _onNotice(SkyPatchNotice notice) {
    if (!mounted) return;
    if (notice.kind == SkyPatchNoticeKind.partnerStar && notice.star != null && _motion) {
      _rings[notice.star!] = _now;
      _wake();
    }
  }

  void _sync() {
    final drawing = session.drawing;
    if (_gen != null && drawing.gen != _gen && _motion) {
      final previous = _picture.value;
      _ghostStars = [for (final s in previous.stars) if (s.alpha > 0) s];
      _ghostLines = previous.lines;
      _ghostAt = _now;
    }
    _gen = drawing.gen;
    final stamp = _seeded && _motion ? _now : -100.0;
    for (final star in drawing.visibleStars) {
      _born.putIfAbsent(star.id, () => stamp);
    }
    for (final line in drawing.visibleLines) {
      _linesBorn.putIfAbsent(line.key, () => stamp);
    }
    _seeded = true;
    final from = _from;
    if (from != null && drawing.visibleStar(from) == null) {
      _from = null;
      _snapped = null;
    }
    if (!session.canEdit && _pointer != null) _end(lift: false);
    _paintPicture();
    _paintLive();
    _wake();
  }

  Rect get _frame => SkyPatchFeel.frameOf(_size);

  Offset _px(Offset unit) => SkyPatchArt.place(_frame, unit);

  Offset _unit(Offset local) {
    final frame = _frame;
    if (frame.width <= 0) return const Offset(0.5, 0.5);
    return Offset((local.dx - frame.left) / frame.width, (local.dy - frame.top) / frame.height);
  }

  SkyDrawnStar? _starAt(Offset local, double radius, {String? except}) {
    SkyDrawnStar? best;
    var bestDistance = radius;
    for (final star in session.drawing.visibleStars) {
      if (star.id == except) continue;
      final distance = (_px(Offset(star.x, star.y)) - local).distance;
      if (distance <= bestDistance) {
        best = star;
        bestDistance = distance;
      }
    }
    return best;
  }

  bool get _animating {
    bool young(Iterable<double> stamps, double span) => stamps.any((at) => _now - at < span);
    return young(_born.values, SkyPatchFeel.appear) ||
        young(_rings.values, SkyPatchFeel.rings) ||
        young(_pulses.values, SkyPatchFeel.pulse) ||
        young(_linesBorn.values, SkyPatchFeel.grow) ||
        _ghostAt != null ||
        _retractAt != null;
  }

  bool get _wanted => _pointer != null || _animating || session.finger.value != null || _comet > 0;

  void _wake() {
    if (!mounted) return;
    if (_wanted) {
      if (!_ticker.isActive) {
        _last = _now;
        _ticker.start();
      }
    } else if (_ticker.isActive) {
      _ticker.stop();
      _base = _now;
    }
  }

  void _onTick(Duration elapsed) {
    _now = _base + elapsed.inMicroseconds / 1e6;
    final dt = math.max(0.0, _now - _last);
    _last = _now;
    _stepComet(dt);
    if (_ghostAt != null && _now - _ghostAt! >= SkyPatchFeel.clear) {
      _ghostAt = null;
      _ghostStars = const [];
      _ghostLines = const [];
    }
    if (_retractAt != null && _now - _retractAt! >= SkyPatchFeel.retract) {
      _retractAt = null;
      _retractFrom = null;
      _retractTo = null;
    }
    _paintPicture();
    _paintLive();
    if (!_wanted) {
      _ticker.stop();
      _base = _now;
    }
  }

  void _stepComet(double dt) {
    final target = session.finger.value;
    if (target != null && _size != Size.zero) {
      final at = _px(target.unit);
      final head = _head;
      if (head == null || !_motion) {
        _head = at;
      } else {
        final blend = 1 - math.exp(-dt / SkyPatchFeel.smooth);
        _head = Offset.lerp(head, at, blend);
      }
      _comet = 1;
    } else if (_head != null) {
      _comet = _motion ? math.max(0, _comet - dt / SkyPatchFeel.cometFade) : 0;
      if (_comet <= 0) {
        _head = null;
        _tail.clear();
      }
    }
    final head = _head;
    if (head != null && target != null) {
      _tail.add(SkyCometPoint(head, _now));
    }
    _tail.removeWhere((p) => _now - p.seconds > SkyPatchFeel.tail);
    while (_tail.length > SkyPatchFeel.tailPoints) {
      _tail.removeAt(0);
    }
  }

  void _paintPicture() {
    final drawing = session.drawing;
    final me = session.me;
    final stars = drawing.visibleStars;
    final units = {for (final s in stars) s.id: Offset(s.x, s.y)};
    _rings.removeWhere((_, at) => _now - at >= SkyPatchFeel.rings);
    _pulses.removeWhere((_, at) => _now - at >= SkyPatchFeel.pulse);
    final painted = <SkyPatchStar>[
      for (var i = 0; i < stars.length; i++)
        SkyPatchStar(
          id: stars[i].id,
          unit: units[stars[i].id]!,
          index: i,
          mine: stars[i].by == me,
          scale: _appear(_born[stars[i].id]),
          rings: _ringsOf(stars[i].id),
          pulse: _pulseOf(stars[i].id),
        ),
    ];
    final lines = <SkyPatchLine>[
      for (final line in drawing.visibleLines)
        if (units[line.a] != null && units[line.b] != null)
          SkyPatchLine(a: units[line.a]!, b: units[line.b]!, grow: _grow(_linesBorn[line.key])),
    ];
    final fade = _ghostAt == null ? 0.0 : 1 - ((_now - _ghostAt!) / SkyPatchFeel.clear).clamp(0.0, 1.0);
    _picture.value = SkyPatchPicture(
      night: _night,
      stars: [
        if (fade > 0)
          for (final s in _ghostStars)
            SkyPatchStar(id: s.id, unit: s.unit, index: s.index, mine: s.mine, scale: s.scale, alpha: fade),
        ...painted,
      ],
      lines: [
        if (fade > 0)
          for (final l in _ghostLines) SkyPatchLine(a: l.a, b: l.b, alpha: fade),
        ...lines,
      ],
    );
  }

  double _appear(double? born) {
    if (born == null || !_motion) return 1;
    final t = ((_now - born) / SkyPatchFeel.appear).clamp(0.0, 1.0);
    return t >= 1 ? 1 : Curves.easeOutBack.transform(t);
  }

  double _grow(double? born) {
    if (born == null || !_motion) return 1;
    return Curves.easeOutCubic.transform(((_now - born) / SkyPatchFeel.grow).clamp(0.0, 1.0));
  }

  double? _ringsOf(String id) {
    final at = _rings[id];
    if (at == null) return null;
    return ((_now - at) / SkyPatchFeel.rings).clamp(0.0, 1.0);
  }

  double _pulseOf(String id) {
    final at = _pulses[id];
    if (at == null) return 0;
    return ((_now - at) / SkyPatchFeel.pulse).clamp(0.0, 1.0);
  }

  void _paintLive() {
    if (_size == Size.zero) return;
    Offset? lineFrom;
    Offset? lineTo;
    Offset? snapAt;
    final from = _from;
    final finger = _finger;
    if (from != null && _dragging && finger != null) {
      final star = session.drawing.visibleStar(from);
      if (star != null) {
        lineFrom = _px(Offset(star.x, star.y));
        final snapped = _snapped == null ? null : session.drawing.visibleStar(_snapped!);
        snapAt = snapped == null ? null : _px(Offset(snapped.x, snapped.y));
        lineTo = snapAt ?? finger;
      }
    } else if (_retractAt != null && _retractFrom != null && _retractTo != null) {
      final t = Curves.easeIn.transform(((_now - _retractAt!) / SkyPatchFeel.retract).clamp(0.0, 1.0));
      lineFrom = _retractFrom;
      lineTo = Offset.lerp(_retractTo, _retractFrom, t);
    }
    _live.value = SkyPatchLive(
      night: _night,
      k: _k,
      motion: _motion,
      tail: List<SkyCometPoint>.of(_tail),
      head: _head,
      cometAlpha: _comet,
      name: widget.partner,
      finger: _pointer == null ? null : finger,
      lineFrom: lineFrom,
      lineTo: lineTo,
      snapped: snapAt != null,
      snapAt: snapAt,
    );
  }

  void _sendFinger(Offset local) {
    final unit = _unit(local);
    session.moveFinger(unit.dx, unit.dy);
  }

  void _down(PointerDownEvent event) {
    if (_pointer != null || !session.canEdit) return;
    _pointer = event.pointer;
    _downAt = event.localPosition;
    _downStamp = event.timeStamp;
    _finger = event.localPosition;
    _dragging = false;
    _from = _starAt(event.localPosition, SkyPatchFeel.hit * _k)?.id;
    _snapped = null;
    _retractAt = null;
    _sendFinger(event.localPosition);
    _paintLive();
    _wake();
  }

  void _move(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    _finger = event.localPosition;
    if (!_dragging && (event.localPosition - _downAt!).distance > SkyPatchFeel.slop) _dragging = true;
    final from = _from;
    if (_dragging && from != null) {
      final near = _starAt(event.localPosition, SkyPatchFeel.snap * _k, except: from)?.id;
      if (near != _snapped) {
        _snapped = near;
        if (near != null) session.haptic(HapticKind.tick);
      }
    }
    _sendFinger(event.localPosition);
    _paintLive();
  }

  void _up(PointerUpEvent event) {
    if (event.pointer != _pointer) return;
    final quick = event.timeStamp - _downStamp < SkyPatchFeel.tap;
    final from = _from;
    final snapped = _snapped;
    if (!_dragging && quick) {
      _tap(_downAt!);
    } else if (_dragging && from != null) {
      final joined = snapped != null && session.join(from, snapped);
      if (!joined) {
        final star = session.drawing.visibleStar(from);
        if (star != null && _finger != null && _motion) {
          _retractFrom = _px(Offset(star.x, star.y));
          _retractTo = _finger;
          _retractAt = _now;
        }
      }
    }
    _end();
  }

  void _cancel(PointerCancelEvent event) {
    if (event.pointer != _pointer) return;
    _end();
  }

  void _end({bool lift = true}) {
    _pointer = null;
    _finger = null;
    _dragging = false;
    _from = null;
    _snapped = null;
    if (lift) session.liftFinger();
    _paintLive();
    _wake();
  }

  void _tap(Offset local) {
    final hit = _starAt(local, SkyPatchFeel.hit * _k);
    if (hit != null) {
      if (session.mine(hit)) {
        if (session.takeAway(hit.id)) session.haptic(HapticKind.tap);
      } else {
        if (_motion) _pulses[hit.id] = _now;
        session.haptic(HapticKind.tick);
        _paintPicture();
        _wake();
      }
      return;
    }
    final unit = _unit(local);
    const out = SkyPatchFeel.outside;
    if (unit.dx < -out || unit.dx > 1 + out || unit.dy < -out || unit.dy > 1 + out) return;
    _place(unit);
  }

  bool _place(Offset unit) {
    final frame = _frame;
    final edge = frame.width <= 0 ? skyPatchEdge : math.min(0.2, SkyPatchFeel.edge * _k / frame.width);
    final x = unit.dx.clamp(edge, 1 - edge);
    final y = unit.dy.clamp(edge, 1 - edge);
    final placed = session.placeStar(x, y);
    if (placed == null) return false;
    session.haptic(HapticKind.tick);
    return true;
  }

  void _readerAddStar() {
    for (var n = 0; n < 240; n++) {
      final angle = n * 2.399963;
      final r = 0.06 + 0.36 * math.sqrt(n / 240);
      if (_place(Offset(0.5 + r * math.cos(angle), 0.5 + r * math.sin(angle)))) return;
    }
  }

  void _readerJoin() {
    final stars = [...session.drawing.visibleStars]..sort((a, b) => b.at.compareTo(a.at));
    for (var i = 0; i < stars.length; i++) {
      for (var j = i + 1; j < stars.length; j++) {
        if (session.drawing.isLinked(stars[i].id, stars[j].id)) continue;
        if (session.join(stars[i].id, stars[j].id)) {
          session.haptic(HapticKind.tick);
          return;
        }
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final drawing = session.drawing;
    final width = MediaQuery.sizeOf(context).width;
    _k = SkyPageFrame.scaleOf(width);
    final editable = session.canEdit;
    return LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        if (size != _size) {
          _size = size;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _paintLive();
          });
        }
        final frame = SkyPatchFeel.frameOf(size);
        final target = math.max(SkySizes.minTap, SkyPatchFeel.hit * 2 * _k);
        final stars = drawing.visibleStars;
        return Semantics(
          key: SkyTogetherKeys.frame,
          container: true,
          label: SkyTogetherCopy.patchLabel(stars: stars.length, lines: drawing.visibleLines.length),
          customSemanticsActions: editable
              ? {
                  if (!drawing.starsFull) const CustomSemanticsAction(label: SkyTogetherCopy.addStar): _readerAddStar,
                  if (stars.length >= 2 && !drawing.linesFull)
                    const CustomSemanticsAction(label: SkyTogetherCopy.joinNewest): _readerJoin,
                }
              : const {},
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _down,
            onPointerMove: _move,
            onPointerUp: _up,
            onPointerCancel: _cancel,
            child: Stack(
              fit: StackFit.expand,
              children: [
                RepaintBoundary(
                  child: CustomPaint(
                    painter: SkyPatchPainter(
                      picture: _picture,
                      frameOf: SkyPatchFeel.frameOf,
                      k: _k,
                      sigma: t.glowSigma,
                    ),
                  ),
                ),
                RepaintBoundary(
                  child: CustomPaint(painter: SkyPatchLivePainter(live: _live, tokens: t)),
                ),
                for (final star in stars)
                  Positioned(
                    key: SkyTogetherKeys.star(star.id),
                    left: SkyPatchArt.place(frame, Offset(star.x, star.y)).dx - target / 2,
                    top: SkyPatchArt.place(frame, Offset(star.x, star.y)).dy - target / 2,
                    width: target,
                    height: target,
                    child: Semantics(
                      container: true,
                      button: session.mine(star) && editable,
                      label: session.mine(star) ? SkyTogetherCopy.yourStar : SkyTogetherCopy.partnerStar(widget.partner),
                      onTap: session.mine(star) && editable
                          ? () {
                              if (session.takeAway(star.id)) session.haptic(HapticKind.tap);
                            }
                          : null,
                      child: const SizedBox.expand(),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
