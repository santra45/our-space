import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/engine.dart';
import '../../sky/sky.dart';
import 'watch_copy.dart';
import 'watch_room.dart';

abstract final class WatchReactionKeys {
  static const Key layer = ValueKey<String>('watch-reactions');
  static const Key floater = ValueKey<String>('watch-floater');

  static Key button(SkyReaction reaction) => ValueKey<String>('watch-react-${reaction.name}');
}

String watchReactionEmoji(SkyReaction reaction) => switch (reaction) {
  SkyReaction.heart => '❤️',
  SkyReaction.love => '😍',
  SkyReaction.laugh => '😂',
  SkyReaction.wow => '😮',
  SkyReaction.tear => '😢',
  SkyReaction.fire => '🔥',
};

class WatchReactionButtons extends StatelessWidget {
  const WatchReactionButtons({super.key, required this.room});

  final WatchRoom room;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final reaction in SkyReaction.values)
          SkyPressable(
            key: WatchReactionKeys.button(reaction),
            onTap: () => room.react(reaction),
            pressedScale: 0.8,
            semanticLabel: WatchCopy.reaction(reaction),
            excludeSemantics: true,
            child: SizedBox.square(
              dimension: 46,
              child: Center(
                child: Text(
                  watchReactionEmoji(reaction),
                  style: const TextStyle(fontSize: 26, height: 1.1, decoration: TextDecoration.none),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class WatchReactionLayer extends StatefulWidget {
  const WatchReactionLayer({super.key = WatchReactionKeys.layer, required this.room, this.random});

  static const int most = 20;

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
      _flights.add(_Flight.random(_nextId++, seen, _random));
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
                  _Floater(key: ValueKey<int>(flight.id), flight: flight, onLanded: () => _land(flight.id)),
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
  const _Flight({
    required this.id,
    required this.seen,
    required this.inset,
    required this.size,
    required this.duration,
    required this.sway,
    required this.turns,
    required this.phase,
  });

  factory _Flight.random(int id, WatchReactionSeen seen, math.Random random) => _Flight(
    id: id,
    seen: seen,
    inset: random.nextDouble(),
    size: 28 + random.nextDouble() * 12,
    duration: Duration(milliseconds: 2200 + random.nextInt(1000)),
    sway: 8 + random.nextDouble() * 14,
    turns: 1.2 + random.nextDouble() * 1.3,
    phase: random.nextDouble() * math.pi * 2,
  );

  final int id;
  final WatchReactionSeen seen;
  final double inset;
  final double size;
  final Duration duration;
  final double sway;
  final double turns;
  final double phase;
}

class _Floater extends StatefulWidget {
  const _Floater({super.key, required this.flight, required this.onLanded});

  final _Flight flight;
  final VoidCallback onLanded;

  @override
  State<_Floater> createState() => _FloaterState();
}

class _FloaterState extends State<_Floater> with SingleTickerProviderStateMixin {
  static const double _edge = 12;
  static const double _band = 56;

  late final AnimationController _run = AnimationController(
    vsync: this,
    duration: widget.flight.duration,
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
    final flight = widget.flight;
    final moves = skyMotionAllowed(context);
    final emoji = watchReactionEmoji(flight.seen.reaction);
    return LayoutBuilder(
      builder: (context, box) => AnimatedBuilder(
        animation: _run,
        builder: (context, child) {
          final p = _run.value;
          final fade = p < 0.06 ? p / 0.06 : (p > 0.65 ? (1 - p) / 0.35 : 1.0);
          final fromEdge = _edge + _band * flight.inset;
          final home = flight.seen.mine ? box.maxWidth - fromEdge - flight.size : fromEdge;
          final rise = moves ? Curves.easeOutSine.transform(p) * box.maxHeight * 0.82 : box.maxHeight * 0.3;
          final side = moves ? math.sin(p * flight.turns * math.pi * 2 + flight.phase) * flight.sway * (0.35 + 0.65 * p) : 0.0;
          final pop = moves && p < 0.14 ? 0.4 + 0.6 * Curves.easeOutBack.transform(p / 0.14) : 1.0;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: home + side,
                top: box.maxHeight - flight.size * 1.3 - rise,
                child: Opacity(
                  opacity: fade.clamp(0.0, 1.0),
                  child: Transform.scale(scale: pop, child: child),
                ),
              ),
            ],
          );
        },
        child: Text(
          emoji,
          key: WatchReactionKeys.floater,
          style: TextStyle(fontSize: flight.size, height: 1.2, decoration: TextDecoration.none),
        ),
      ),
    );
  }
}
