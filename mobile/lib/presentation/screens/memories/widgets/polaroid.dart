import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../sky/sky.dart';
import '../memories_copy.dart';
import '../memory_photos.dart';

abstract final class PolaroidColors {
  static const Color paper = Color(0xFFFFFDF8);
  static const Color ink = Color(0xFF3A3352);
  static const Color faded = Color(0xFFA39BB8);
  static const Color bed = Color(0xFFF2EDE4);
  static const Color bedDeep = Color(0xFFE6DFD3);
  static const Color tape = Color(0xBFFFE8B5);
  static const Color tapeEdge = Color(0x0F000000);
  static const Color pinLight = Color(0xFFFF9AB8);
  static const Color pinDeep = Color(0xFFC42F5E);
}

List<BoxShadow> polaroidShadow(SkyTokens t) => t.isNight
    ? const [
        BoxShadow(color: Color(0x4D000000), offset: Offset(0, 16), blurRadius: 25.1),
        BoxShadow(color: Color(0x26000000), offset: Offset(0, 2), blurRadius: 2.6),
      ]
    : const [
        BoxShadow(color: Color(0x292B2A6B), offset: Offset(0, 14), blurRadius: 23.4),
        BoxShadow(color: Color(0x142B2A6B), offset: Offset(0, 2), blurRadius: 2.6),
      ];

TextStyle polaroidCaptionStyle([double size = 19]) => SkyType.hand(size, color: PolaroidColors.ink);

TextStyle polaroidMetaStyle([double size = 9.5]) =>
    SkyType.sans(size, height: 1.3, letterSpacing: size * 0.04, color: PolaroidColors.faded);

class PolaroidTape extends StatelessWidget {
  const PolaroidTape({super.key, this.width = 58});

  final double width;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -4 * math.pi / 180,
      child: Container(
        width: width,
        height: width * 18 / 58,
        decoration: const BoxDecoration(
          color: PolaroidColors.tape,
          border: Border(
            left: BorderSide(color: PolaroidColors.tapeEdge),
            right: BorderSide(color: PolaroidColors.tapeEdge),
          ),
        ),
      ),
    );
  }
}

class PolaroidPinHead extends StatelessWidget {
  const PolaroidPinHead({super.key, this.size = 14});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: Alignment(-0.3, -0.4),
          radius: 0.96,
          colors: [PolaroidColors.pinLight, PolaroidColors.pinDeep],
          stops: [0, 0.7],
        ),
        boxShadow: [BoxShadow(color: Color(0x59000000), offset: Offset(0, 3), blurRadius: 3.5)],
      ),
    );
  }
}

class PolaroidNewBadge extends StatelessWidget {
  const PolaroidNewBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: context.sky.rose,
        borderRadius: SkyRadii.all(SkyRadii.pill),
        boxShadow: const [BoxShadow(color: Color(0x40E24E79), offset: Offset(0, 3), blurRadius: 6)],
      ),
      child: Text(
        MemoriesCopy.newBadge,
        style: SkyType.sans(9.5, weight: FontWeight.w700, height: 1.25).copyWith(color: SkyTokens.white),
      ),
    );
  }
}

class PolaroidPaper extends StatelessWidget {
  const PolaroidPaper({
    super.key,
    required this.photo,
    this.caption,
    this.captionText,
    this.captionSize = 19,
    this.captionMaxLines = 2,
    this.meta,
    this.pin,
    this.badge,
    this.padding = const EdgeInsets.fromLTRB(9, 9, 9, 0),
    this.radius = 6,
    this.photoRadius = 3,
    this.shadow = true,
  });

  final Widget photo;
  final Widget? caption;
  final String? captionText;
  final double captionSize;
  final int? captionMaxLines;
  final String? meta;
  final PolaroidPin? pin;
  final Widget? badge;
  final EdgeInsets padding;
  final double radius;
  final double photoRadius;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final captionWidget = caption ??
        Text(
          captionText ?? '',
          maxLines: captionMaxLines,
          overflow: captionMaxLines == null ? null : TextOverflow.ellipsis,
          style: polaroidCaptionStyle(captionSize),
        );
    final paper = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: PolaroidColors.paper,
        borderRadius: SkyRadii.all(radius),
        boxShadow: shadow ? polaroidShadow(t) : const [],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(borderRadius: SkyRadii.all(photoRadius), child: photo),
          Padding(padding: const EdgeInsets.fromLTRB(2, 6, 2, 2), child: captionWidget),
          if (meta != null && meta!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
              child: Text(meta!, maxLines: 1, overflow: TextOverflow.ellipsis, style: polaroidMetaStyle()),
            )
          else
            const SizedBox(height: 10),
        ],
      ),
    );
    if (pin == null && badge == null) return paper;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        paper,
        if (pin != null)
          Positioned(
            top: pin == PolaroidPin.tape ? -9 : -7,
            left: 0,
            right: 0,
            child: Center(child: pin == PolaroidPin.tape ? const PolaroidTape() : const PolaroidPinHead()),
          ),
        if (badge != null) Positioned(top: 14, right: 14, child: badge!),
      ],
    );
  }
}

class PolaroidDeveloping extends StatelessWidget {
  const PolaroidDeveloping({super.key, this.label = MemoriesCopy.developing});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [PolaroidColors.bed, PolaroidColors.bedDeep],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SkyPulse(child: SkyIcon(SkyIcons.sparkle, size: 16, color: PolaroidColors.faded)),
              const SizedBox(height: 6),
              Text(label.toUpperCase(), style: SkyType.caps(8.5, tracking: 0.2, color: PolaroidColors.faded)),
            ],
          ),
        ),
      ),
    );
  }
}

class PolaroidNoPhoto extends StatelessWidget {
  const PolaroidNoPhoto({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: PolaroidColors.bed,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SkyIcon(SkyIcons.photo, size: 20, color: PolaroidColors.faded),
              const SizedBox(height: 6),
              Semantics(
                liveRegion: true,
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: SkyType.sans(10.5, weight: FontWeight.w500, height: 1.3).copyWith(color: PolaroidColors.ink),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PolaroidImage extends StatelessWidget {
  const PolaroidImage({
    super.key,
    required this.image,
    this.fit = BoxFit.cover,
    this.semanticLabel,
    this.fallback = MemoriesCopy.noImage,
  });

  final ImageProvider<Object> image;
  final BoxFit fit;
  final String? semanticLabel;
  final String fallback;

  @override
  Widget build(BuildContext context) {
    final duration = skyMotionAllowed(context) ? SkyMotion.slow : SkyMotion.fast;
    return ColoredBox(
      color: PolaroidColors.bed,
      child: Image(
        image: image,
        fit: fit,
        width: fit == BoxFit.cover ? double.infinity : null,
        height: fit == BoxFit.cover ? double.infinity : null,
        gaplessPlayback: true,
        semanticLabel: semanticLabel,
        frameBuilder: (context, child, frame, sync) {
          if (sync) return child;
          return AnimatedOpacity(
            opacity: frame == null ? 0 : 1,
            duration: duration,
            curve: SkyMotion.gentle,
            child: child,
          );
        },
        errorBuilder: (context, error, stack) => PolaroidNoPhoto(text: fallback),
      ),
    );
  }
}

class PolaroidDashedFrame extends CustomPainter {
  const PolaroidDashedFrame({this.color = PolaroidColors.faded});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final rect = (Offset.zero & size).deflate(4);
    final path = Path()..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)));
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = math.min(distance + 6, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + 5;
      }
    }
  }

  @override
  bool shouldRepaint(covariant PolaroidDashedFrame oldDelegate) => oldDelegate.color != color;
}
