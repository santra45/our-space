import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../sky/sky.dart';
import '../lock_copy.dart';

class LockLink extends StatelessWidget {
  const LockLink({super.key, required this.label, required this.onTap, this.icon, this.tone, this.small = false});

  final String label;
  final VoidCallback? onTap;
  final SkyIcons? icon;
  final SkyTone? tone;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final color = tone?.foreground(t) ?? t.muted;
    final style = SkyType.sans(small ? 12 : 13, weight: FontWeight.w600, height: 1.35).copyWith(color: color);
    return Center(
      child: SkyPressable(
        onTap: onTap,
        enabled: onTap != null,
        semanticLabel: label,
        excludeSemantics: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          child: Container(
            padding: const EdgeInsets.only(bottom: 2),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: t.hairline)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[SkyIcon(icon!, size: 14, color: color), const SizedBox(width: 6)],
                Flexible(
                  child: Text(label, textAlign: TextAlign.center, style: style),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class LockInlineError extends StatelessWidget {
  const LockInlineError(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: SkyIcon(SkyIcons.alert, size: 15, color: t.rose),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                text,
                textAlign: TextAlign.center,
                textWidthBasis: TextWidthBasis.longestLine,
                style: SkyType.sans(12.5, weight: FontWeight.w600, height: 1.4).copyWith(color: t.rose),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LockSegment<T> {
  const LockSegment({required this.value, required this.label, required this.icon});

  final T value;
  final String label;
  final SkyIcons icon;
}

class LockSegmented<T> extends StatelessWidget {
  const LockSegmented({super.key, required this.segments, required this.selected, required this.onChanged});

  final List<LockSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final index = math.max(0, segments.indexWhere((s) => s.value == selected));
    final motion = skyMotionAllowed(context);
    final x = segments.length < 2 ? 0.0 : -1 + 2 * index / (segments.length - 1);
    return Container(
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: t.isNight ? const Color(0xD9110F33) : SkyTokens.white,
        borderRadius: SkyRadii.all(SkyRadii.pill),
        border: Border.all(color: t.chipBorder),
        boxShadow: t.isDay ? t.softShadow : const [],
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: motion ? SkyMotion.slow : Duration.zero,
            curve: const SkySpringCurve(SkyMotion.popSpring, seconds: 0.5),
            alignment: Alignment(x, 0),
            child: FractionallySizedBox(
              widthFactor: 1 / segments.length,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: t.activeBg,
                  borderRadius: SkyRadii.all(SkyRadii.pill),
                  boxShadow: [BoxShadow(color: t.activeGlow, blurRadius: 14)],
                ),
              ),
            ),
          ),
          Row(
            children: [
              for (final segment in segments)
                Expanded(
                  child: SkyPressable(
                    onTap: segment.value == selected ? null : () => onChanged(segment.value),
                    selected: segment.value == selected,
                    semanticLabel: segment.label,
                    excludeSemantics: true,
                    child: Center(
                      child: _SegmentLabel(segment: segment, active: segment.value == selected),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SegmentLabel<T> extends StatelessWidget {
  const _SegmentLabel({required this.segment, required this.active});

  final LockSegment<T> segment;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final color = active ? t.activeFg : t.muted;
    return AnimatedDefaultTextStyle(
      duration: skyMotionAllowed(context) ? SkyMotion.fast : Duration.zero,
      style: SkyType.sans(12.5, weight: active ? FontWeight.w700 : FontWeight.w600, height: 1.2).copyWith(color: color),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SkyIcon(segment.icon, size: 15, color: color),
          const SizedBox(width: 6),
          Flexible(child: Text(segment.label, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

class LockPanel extends StatelessWidget {
  const LockPanel({super.key, required this.child, this.padding = const EdgeInsets.fromLTRB(18, 22, 18, 18)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: t.isNight
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [t.cardTop.withValues(alpha: 0.94), t.cardBottom.withValues(alpha: 0.96)],
              )
            : t.cardGradient,
        borderRadius: SkyRadii.all(SkyRadii.feature),
        border: Border.all(color: t.cardBorder),
        boxShadow: t.isDay ? t.shadow : t.softShadow,
      ),
      child: child,
    );
  }
}

class LockPanelHeader extends StatelessWidget {
  const LockPanelHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.intro,
    this.tone = SkyTone.gold,
  });

  final SkyIcons icon;
  final String title;
  final String intro;
  final SkyTone tone;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    return Column(
      children: [
        SkyIconTile(icon: icon, tone: tone, size: 46, iconSize: 22),
        const SizedBox(height: 12),
        Semantics(
          header: true,
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: SkyType.headline.copyWith(color: t.text),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          intro,
          textAlign: TextAlign.center,
          style: SkyType.bodySmall.copyWith(color: t.muted),
        ),
      ],
    );
  }
}

enum LockNoteTone { info, safe, love, warning, error }

class LockNote extends StatelessWidget {
  const LockNote({
    super.key,
    this.text,
    this.spans,
    this.title,
    this.tone = LockNoteTone.info,
    this.icon,
    this.actionLabel,
    this.onAction,
  }) : assert(text != null || spans != null);

  final String? text;
  final List<InlineSpan>? spans;
  final String? title;
  final LockNoteTone tone;
  final SkyIcons? icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    late final Color accent;
    late final Color bg;
    late final Color border;
    late final SkyIcons glyph;
    switch (tone) {
      case LockNoteTone.info:
        accent = t.lavender;
        bg = t.isNight ? const Color(0xD9110F33) : t.surface;
        border = t.chipBorder;
        glyph = SkyIcons.info;
      case LockNoteTone.safe:
        accent = t.gold;
        bg = t.isNight ? const Color(0xD9110F33) : t.surface;
        border = t.gold.withValues(alpha: 0.35);
        glyph = SkyIcons.check;
      case LockNoteTone.love:
        accent = t.rose;
        bg = t.isNight
            ? Color.alphaBlend(t.roseSoft, const Color(0xE6110F33))
            : Color.alphaBlend(t.roseSoft, t.surface);
        border = t.roseBorder;
        glyph = SkyIcons.heart;
      case LockNoteTone.warning:
        accent = t.gold;
        bg = t.isNight
            ? Color.alphaBlend(t.goldSoft, const Color(0xE6110F33))
            : Color.alphaBlend(t.goldSoft, t.surface);
        border = t.gold.withValues(alpha: 0.4);
        glyph = SkyIcons.alert;
      case LockNoteTone.error:
        accent = t.rose;
        bg = t.isNight
            ? Color.alphaBlend(t.roseSoft, const Color(0xE6110F33))
            : Color.alphaBlend(t.roseSoft, t.surface);
        border = t.roseBorder;
        glyph = SkyIcons.alert;
    }
    final body = SkyType.bodySmall.copyWith(color: t.text);
    return Semantics(
      liveRegion: tone == LockNoteTone.error,
      container: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: SkyRadii.all(SkyRadii.tile),
          border: Border.all(color: border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: SkyIcon(icon ?? glyph, size: 17, color: accent),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (title != null) ...[
                    Text(title!, style: SkyType.bodyStrong.copyWith(color: t.text, fontSize: 13)),
                    const SizedBox(height: 3),
                  ],
                  if (spans != null) Text.rich(TextSpan(children: spans), style: body) else Text(text!, style: body),
                  if (actionLabel != null) ...[
                    const SizedBox(height: 8),
                    SkyPressable(
                      onTap: onAction,
                      semanticLabel: actionLabel,
                      excludeSemantics: true,
                      child: Text(
                        actionLabel!,
                        style: SkyType.sans(12.5, weight: FontWeight.w700).copyWith(color: t.rose),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const TextStyle lockStrong = TextStyle(fontWeight: FontWeight.w700);

class LockFileTile extends StatelessWidget {
  const LockFileTile({super.key, required this.label, required this.onTap, this.chosen = false});

  final String label;
  final VoidCallback? onTap;
  final bool chosen;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final color = chosen ? t.text : t.muted;
    return SkyPressable(
      onTap: onTap,
      enabled: onTap != null,
      pressedScale: 0.98,
      semanticLabel: label,
      excludeSemantics: true,
      child: CustomPaint(
        painter: _DashedRRectPainter(color: chosen ? t.gold.withValues(alpha: 0.7) : t.muted.withValues(alpha: 0.45)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SkyIcon(chosen ? SkyIcons.check : SkyIcons.upload, size: 18, color: chosen ? t.gold : t.muted),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SkyType.sans(13.5, weight: FontWeight.w600).copyWith(color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  _DashedRRectPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius((Offset.zero & size).deflate(0.75), const Radius.circular(SkyRadii.tile));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, math.min(d + 6, metric.length)), paint);
        d += 11;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRectPainter oldDelegate) => oldDelegate.color != color;
}

enum LockWay { join, restore, startOver }

class LockMoreSheet extends StatelessWidget {
  const LockMoreSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    void choose(LockWay way) => Navigator.of(context).pop(way);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
          child: Text(LockCopy.moreTitle, style: SkyType.headlineSmall.copyWith(color: t.text)),
        ),
        SkyListGroup(
          children: [
            SkyListRow(
              title: LockCopy.moreJoin,
              subtitle: LockCopy.moreJoinHint,
              icon: SkyIcons.us,
              tone: SkyTone.lavender,
              onTap: () => choose(LockWay.join),
            ),
            SkyListRow(
              title: LockCopy.moreRestore,
              subtitle: LockCopy.moreRestoreHint,
              icon: SkyIcons.box,
              tone: SkyTone.gold,
              onTap: () => choose(LockWay.restore),
            ),
            SkyListRow(
              title: LockCopy.moreStartOver,
              subtitle: LockCopy.moreStartOverHint,
              icon: SkyIcons.refresh,
              tone: SkyTone.rose,
              onTap: () => choose(LockWay.startOver),
            ),
          ],
        ),
      ],
    );
  }
}
