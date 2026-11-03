import 'dart:async';

import 'package:flutter/material.dart';

import '../../sky/sky.dart';
import 'watch_copy.dart';
import 'watch_room.dart';

abstract final class WatchChatKeys {
  static const Key list = ValueKey<String>('watch-chat-list');
  static const Key layer = ValueKey<String>('watch-chat-layer');
  static const Key floating = ValueKey<String>('watch-chat-floating');

  static Key bubble(String id) => ValueKey<String>('watch-chat-$id');
}

class WatchChatList extends StatelessWidget {
  const WatchChatList({super.key = WatchChatKeys.list, required this.lines, required this.partner});

  final List<WatchSaid> lines;
  final String partner;

  @override
  Widget build(BuildContext context) {
    return ListView(
      reverse: true,
      padding: const EdgeInsets.symmetric(vertical: SkySpace.xs),
      children: [
        for (final line in lines.reversed)
          WatchChatBubble(
            key: WatchChatKeys.bubble(line.id),
            text: line.text,
            note: line.missed ? WatchCopy.sayMissed(partner) : WatchCopy.clock(line.posMs),
            noteIsTrouble: line.missed,
            mine: line.mine,
            label: line.mine ? WatchCopy.youSaid(line.text) : WatchCopy.partnerSaid(partner, line.text),
            live: !line.mine,
          ),
      ],
    );
  }
}

class WatchChatBubble extends StatelessWidget {
  const WatchChatBubble({
    super.key,
    required this.text,
    required this.note,
    required this.mine,
    required this.label,
    this.noteIsTrouble = false,
    this.live = false,
  });

  final String text;
  final String note;
  final bool mine;
  final String label;
  final bool noteIsTrouble;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    return Semantics(
      label: label,
      liveRegion: live,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: SkySpace.xs),
        child: FractionallySizedBox(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          widthFactor: 0.8,
          child: Align(
            alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: SkySpace.md, vertical: SkySpace.xs),
              decoration: BoxDecoration(
                color: mine ? t.roseSoft : t.chip,
                borderRadius: SkyRadii.all(SkyRadii.field),
                border: Border.all(color: mine ? t.roseBorder : t.chipBorder),
              ),
              child: Column(
                crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(text, style: context.skyText.body),
                  Text(note, style: context.skyText.bodySmall.copyWith(color: noteIsTrouble ? t.rose : t.faint)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class WatchSayLayer extends StatefulWidget {
  const WatchSayLayer({super.key = WatchChatKeys.layer, required this.room, required this.partner});

  static const int most = 3;

  final WatchRoom room;
  final String partner;

  @override
  State<WatchSayLayer> createState() => _WatchSayLayerState();
}

class _WatchSayLayerState extends State<WatchSayLayer> {
  final List<WatchSaid> _showing = [];
  StreamSubscription<WatchSaid>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = widget.room.heard.listen(_onHeard);
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  void _onHeard(WatchSaid line) {
    if (!mounted) return;
    setState(() {
      if (_showing.length >= WatchSayLayer.most) _showing.removeAt(0);
      _showing.add(line);
    });
  }

  void _done(String id) {
    if (!mounted) return;
    setState(() => _showing.removeWhere((line) => line.id == id));
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, box) => Align(
          alignment: const Alignment(-1, 0.2),
          child: Padding(
            padding: const EdgeInsets.only(left: SkySpace.md),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: box.maxWidth * 0.42),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final line in _showing)
                    _FloatingLine(
                      key: ValueKey<String>(line.id),
                      line: line,
                      partner: widget.partner,
                      onDone: () => _done(line.id),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FloatingLine extends StatefulWidget {
  const _FloatingLine({super.key, required this.line, required this.partner, required this.onDone});

  final WatchSaid line;
  final String partner;
  final VoidCallback onDone;

  @override
  State<_FloatingLine> createState() => _FloatingLineState();
}

class _FloatingLineState extends State<_FloatingLine> with SingleTickerProviderStateMixin {
  static const Duration _showFor = Duration(seconds: 7);

  late final AnimationController _run = AnimationController(
    vsync: this,
    duration: _showFor,
    animationBehavior: AnimationBehavior.preserve,
  );

  @override
  void initState() {
    super.initState();
    _run.forward().whenComplete(() {
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _run.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _run,
      builder: (context, child) {
        final p = _run.value;
        final fade = p < 0.04 ? p / 0.04 : (p > 0.85 ? (1 - p) / 0.15 : 1.0);
        return Opacity(opacity: fade.clamp(0.0, 1.0), child: child);
      },
      child: Semantics(
        liveRegion: true,
        label: WatchCopy.partnerSaid(widget.partner, widget.line.text),
        excludeSemantics: true,
        child: Container(
          key: WatchChatKeys.floating,
          margin: const EdgeInsets.only(bottom: SkySpace.xs),
          padding: const EdgeInsets.symmetric(horizontal: SkySpace.md, vertical: 6),
          decoration: BoxDecoration(color: const Color(0xB3000000), borderRadius: SkyRadii.all(SkyRadii.field)),
          child: Text(
            widget.line.text,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: context.skyText.bodySmall.copyWith(color: SkyTokens.white, decoration: TextDecoration.none),
          ),
        ),
      ),
    );
  }
}
