import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/engine.dart';
import '../../sky/sky.dart';
import 'watch_copy.dart';
import 'watch_room.dart';

abstract final class WatchReactionKeys {
  static const Key layer = ValueKey<String>('watch-reactions');
  static const Key comet = ValueKey<String>('watch-comet');

  static Key button(SkyReaction reaction) => ValueKey<String>('watch-react-${reaction.name}');
}

SkyIcons _iconFor(SkyReaction reaction) => switch (reaction) {
  SkyReaction.heart => SkyIcons.heart,
  SkyReaction.laugh => SkyIcons.laugh,
  SkyReaction.tear => SkyIcons.tear,
  SkyReaction.wow => SkyIcons.sparkle,
};

class WatchReactionButtons extends StatelessWidget {
  const WatchReactionButtons({super.key, required this.room, required this.full});

  final WatchRoom room;
  final bool full;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final reaction in SkyReaction.values)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: full ? 0 : SkySpace.xs),
            child: SkyIconButton(
              key: WatchReactionKeys.button(reaction),
              icon: _iconFor(reaction),
              tone: full ? SkyIconButtonTone.ghost : SkyIconButtonTone.surface,
              iconColor: full ? SkyTokens.white : null,
              semanticLabel: WatchCopy.reaction(reaction),
              onPressed: () => room.react(reaction),
            ),
          ),
      ],
    );
  }
}

class WatchReactionLayer extends StatefulWidget {
  const WatchReactionLayer({super.key = WatchReactionKeys.layer, required this.room, this.random});

  static const int most = 12;

  final WatchRoom room;
  final math.Random? random;

  @override
  State<WatchReactionLayer> createState() => _WatchReactionLayerState();
}

class _WatchReactionLayerState extends State<WatchReactionLayer> {
  late final math.Random _random = widget.random ?? math.Random();
  final List<_Flight> _flights = [];
  StreamSubscription<WatchReactionSeen>? _subscription;
  int _nextId = 0;

  @override
  void initState() {
    super.initState();
    _subscription = widget.room.reactions.listen(_onReaction);
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  void _onReaction(WatchReactionSeen seen) {
    if (!mounted) return;
    setState(() {
      if (_flights.length >= WatchReactionLayer.most) _flights.removeAt(0);
      _flights.add(_Flight(_nextId++, seen, 0.45 + _random.nextDouble() * 0.6));
    });
  }

  void _land(int id) {
    if (!mounted) return;
    setState(() => _flights.removeWhere((flight) => flight.id == id));
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                for (final flight in _flights)
                  _Comet(key: ValueKey<int>(flight.id), flight: flight, onLanded: () => _land(flight.id)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

@immutable
class _Flight {
  const _Flight(this.id, this.seen, this.startX);

  final int id;
  final WatchReactionSeen seen;
  final double startX;
}

class _Comet extends StatefulWidget {
  const _Comet({super.key, required this.flight, required this.onLanded});

  final _Flight flight;
  final VoidCallback onLanded;

  @override
  State<_Comet> createState() => _CometState();
}

class _CometState extends State<_Comet> with SingleTickerProviderStateMixin {
  static const Duration _flying = Duration(milliseconds: 1700);

  late final AnimationController _run = AnimationController(
    vsync: this,
    duration: _flying,
    animationBehavior: AnimationBehavior.preserve,
  );

  @override
  void initState() {
    super.initState();
    _run.forward().whenComplete(() {
      if (mounted) widget.onLanded();
    });
  }

  @override
  void dispose() {
    _run.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final color = widget.flight.seen.mine ? t.gold : t.rose;
    final moves = skyMotionAllowed(context);
    return LayoutBuilder(
      builder: (context, box) => AnimatedBuilder(
        animation: _run,
        builder: (context, _) {
          final p = _run.value;
          final fade = p < 0.08 ? p / 0.08 : (p > 0.72 ? (1 - p) / 0.28 : 1.0);
          final flown = moves ? Curves.easeInSine.transform(p) : 0.45;
          final head = Offset(
            (widget.flight.startX - 0.42 * flown) * box.maxWidth,
            (-0.08 + 1.16 * flown) * box.maxHeight,
          );
          const size = 26.0;
          return Stack(
            key: WatchReactionKeys.comet,
            fit: StackFit.expand,
            children: [
              if (moves)
                CustomPaint(
                  painter: _StreakPainter(
                    head: head,
                    back: Offset(0.42 * box.maxWidth, -1.16 * box.maxHeight),
                    color: color,
                    alpha: fade,
                  ),
                ),
              Positioned(
                left: head.dx - size / 2,
                top: head.dy - size / 2,
                width: size,
                height: size,
                child: Opacity(
                  opacity: fade.clamp(0.0, 1.0),
                  child: SkyIcon(_iconFor(widget.flight.seen.reaction), size: size, color: color),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StreakPainter extends CustomPainter {
  const _StreakPainter({required this.head, required this.back, required this.color, required this.alpha});

  static const double length = 74;

  final Offset head;
  final Offset back;
  final Color color;
  final double alpha;

  @override
  void paint(Canvas canvas, Size size) {
    final distance = back.distance;
    if (distance <= 0 || alpha <= 0) return;
    final tail = head + back / distance * length;
    canvas.drawLine(
      head,
      tail,
      Paint()
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..shader = ui.Gradient.linear(head, tail, [
          color.withValues(alpha: 0.85 * alpha),
          color.withValues(alpha: 0),
        ]),
    );
    canvas.drawCircle(
      head,
      15,
      Paint()
        ..shader = ui.Gradient.radial(head, 15, [
          color.withValues(alpha: 0.4 * alpha),
          color.withValues(alpha: 0),
        ]),
    );
  }

  @override
  bool shouldRepaint(_StreakPainter old) =>
      old.head != head || old.alpha != alpha || old.color != color || old.back != back;
}
