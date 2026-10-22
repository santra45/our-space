import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/engine.dart';
import '../../sky/sky.dart';
import '../../widgets/app_haptics.dart';
import '../../widgets/confetti_burst.dart';
import '../love/love_sheet.dart';
import 'letter_options.dart';
import 'letters_copy.dart';
import 'letters_keys.dart';
import 'widgets/ruled_paper.dart';
import 'widgets/wax_seal.dart';

class LetterReadPage extends StatefulWidget {
  const LetterReadPage({
    super.key,
    required this.letter,
    required this.content,
    this.mine = false,
    this.firstOpening = false,
    this.onDelete,
    this.onWriteBack,
  });

  final LetterRecord letter;
  final String content;
  final bool mine;
  final bool firstOpening;
  final Future<bool> Function()? onDelete;
  final VoidCallback? onWriteBack;

  static const Duration celebrateAfter = Duration(milliseconds: 400);

  @override
  State<LetterReadPage> createState() => _LetterReadPageState();
}

class _LetterReadPageState extends State<LetterReadPage> {
  late final int _openedAt = DateTime.now().millisecondsSinceEpoch;
  Timer? _celebrate;

  @override
  void initState() {
    super.initState();
    if (widget.firstOpening) {
      _celebrate = Timer(LetterReadPage.celebrateAfter, () {
        if (!mounted) return;
        AppHaptics.celebration();
        fireHeartConfetti(context);
      });
    }
  }

  @override
  void dispose() {
    _celebrate?.cancel();
    super.dispose();
  }

  Future<void> _delete() async {
    final onDelete = widget.onDelete;
    if (onDelete == null) return;
    final gone = await onDelete();
    if (gone && mounted) Navigator.of(context).pop();
  }

  void _writeBack() => widget.onWriteBack?.call();

  Future<void> _more() async {
    final action = await showLetterOptions(
      context,
      title: widget.letter.title,
      subtitle: LettersCopy.sealedAt(widget.letter.writtenAt),
      primary: LetterOptionsAction.write,
      primaryLabel: widget.mine ? LettersCopy.writeAnother : LettersCopy.writeBack,
      canDelete: widget.onDelete != null,
    );
    if (!mounted || action == null) return;
    switch (action) {
      case LetterOptionsAction.write:
        _writeBack();
      case LetterOptionsAction.delete:
        await _delete();
      case LetterOptionsAction.open:
        break;
    }
  }

  String _openedLabel(String partner) {
    final letter = widget.letter;
    if (widget.mine) {
      if (!letter.isOpened) return LettersCopy.stillWaitingFor(partner);
      return LettersCopy.openedWhen(letter.openedAt, DateTime.now());
    }
    final opened = widget.firstOpening ? _openedAt : (letter.openedAt ?? _openedAt);
    return LettersCopy.openedWhen(opened, DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final identity = context.watch<IdentityController>();
    final media = MediaQuery.of(context);
    final bottom = math.max(media.viewPadding.bottom, SkySpace.lg) + SkySpace.sm;
    return SkyScaffold(
      scene: SkyScene.full,
      skyHeight: double.infinity,
      fadeSky: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(SkySpace.gutter, media.viewPadding.top + 10, SkySpace.gutter, 0),
            child: _topBar(t),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(SkySpace.gutter, 34, SkySpace.gutter, SkySpace.xl),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: SkySizes.maxContentWidth),
                  child: SkyEntrance(
                    offset: const Offset(0, 22),
                    child: Transform.rotate(
                      angle: -0.6 * math.pi / 180,
                      child: _paper(t, identity),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(SkySpace.gutter, SkySpace.sm, SkySpace.gutter, bottom),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: SkySizes.maxContentWidth),
                child: SkyEntrance(
                  index: 2,
                  child: Row(
                    children: [
                      SkyIconButton(
                        key: LettersKeys.love,
                        icon: SkyIcons.heart,
                        square: true,
                        size: SkySizes.button,
                        iconSize: 22,
                        iconColor: t.rose,
                        semanticLabel: LettersCopy.sendLove,
                        onPressed: () => unawaited(showLoveSheet(context)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SkyButton(
                          key: LettersKeys.writeBack,
                          label: widget.mine ? LettersCopy.writeAnother : LettersCopy.writeBack,
                          icon: SkyIcons.pen,
                          onPressed: widget.onWriteBack == null ? null : _writeBack,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _topBar(SkyTokens t) {
    final kicker = widget.mine ? LettersCopy.letterFrom : LettersCopy.letter;
    final name = widget.mine ? LettersCopy.you : LettersCopy.betweenUs;
    return Row(
      children: [
        const SkyBackButton(semanticLabel: LettersCopy.back),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(kicker.toUpperCase(), textAlign: TextAlign.center, style: SkyType.kicker.copyWith(color: t.kicker)),
              const SizedBox(height: SkySpace.xxs),
              Semantics(
                header: true,
                child: Text(
                  name,
                  textAlign: TextAlign.center,
                  style: SkyType.serif(17, weight: FontWeight.w500, height: 1.3).copyWith(color: t.title),
                ),
              ),
            ],
          ),
        ),
        SkyIconButton(
          key: LettersKeys.more,
          icon: SkyIcons.dots,
          tone: SkyIconButtonTone.ghost,
          iconSize: 19,
          semanticLabel: LettersCopy.more,
          onPressed: () => unawaited(_more()),
        ),
      ],
    );
  }

  Widget _paper(SkyTokens t, IdentityController identity) {
    final letter = widget.letter;
    final split = LettersCopy.splitTitle(letter.title);
    final meta = SkyType.caption.copyWith(color: t.paperMuted);
    final signature = widget.mine && identity.me != null ? LettersCopy.signature(identity.myName) : LettersCopy.withLove;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          key: LettersKeys.paper,
          clipBehavior: Clip.antiAlias,
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 18),
          decoration: BoxDecoration(
            color: t.paper,
            borderRadius: SkyRadii.all(SkyRadii.card),
            boxShadow: const [BoxShadow(color: LetterInk.paperShadow, offset: Offset(0, 30), blurRadius: 51)],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (split.kicker != null) ...[
                Text(
                  split.kicker!.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: SkyType.label.copyWith(color: t.roseDeep),
                ),
                const SizedBox(height: 6),
              ],
              Semantics(
                header: true,
                child: Text(
                  split.headline,
                  textAlign: TextAlign.center,
                  style: SkyType.serif(27, weight: FontWeight.w500, height: 1.15).copyWith(color: t.paperInk),
                ),
              ),
              const SizedBox(height: SkySpace.xl),
              CustomPaint(
                painter: const RuledLinesPainter(
                  color: LetterInk.readLine,
                  spacing: 32,
                  offset: 23,
                  bleed: EdgeInsets.fromLTRB(24, 600, 24, 600),
                ),
                child: Text(widget.content, style: SkyType.letter.copyWith(color: t.paperInk)),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: Text(signature, style: SkyType.handSignature.copyWith(color: t.roseDeep)),
              ),
              if (letter.lockDate != null) ...[
                const SizedBox(height: SkySpace.md),
                Row(
                  children: [
                    SkyIcon(SkyIcons.lock, size: 12, color: t.paperMuted),
                    const SizedBox(width: 6),
                    Expanded(child: Text(LettersCopy.keptUntil(letter.lockDate), style: meta)),
                  ],
                ),
              ],
              const SizedBox(height: SkySpace.xl),
              Row(
                children: [
                  Expanded(child: Text(LettersCopy.sealedAt(letter.writtenAt), style: meta)),
                  const SizedBox(width: SkySpace.sm),
                  Text(_openedLabel(identity.partnerName), style: meta),
                ],
              ),
            ],
          ),
        ),
        Positioned(
          top: -22,
          left: 0,
          right: 0,
          child: Center(child: BreakingWaxSeal(size: 52, play: widget.firstOpening)),
        ),
      ],
    );
  }
}
