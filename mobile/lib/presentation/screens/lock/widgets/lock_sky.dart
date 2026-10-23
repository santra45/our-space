import 'dart:math' as math;

import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../sky/sky.dart';
import '../lock_copy.dart';

@immutable
class LockMetrics {
  const LockMetrics({required this.size, this.topInset = 0, this.bottomInset = 0, this.keyboard = 0});

  static const double designWidth = 390;
  static const double designHeight = 844;
  static const double brandBlock = 130;
  static const double ring = 112;
  static const double ringReach = 38;
  static const double touchBlock = ring + 30 + 26 + 14 + 21 + 36 + 14;
  static const double heartLift = 0.28;
  static const double heartScale = 5.2;
  static const double heartDim = 0.6;

  final Size size;
  final double topInset;
  final double bottomInset;
  final double keyboard;

  static const double keyboardHeartGlow = 0.35;

  double get k => size.width <= 0 ? 1 : size.width / designWidth;

  double get designHeightHere => size.height / k;

  double get brandTop => math.max(topInset + 40, 108 * size.height / designHeight);

  double get brandHeight => brandTop + brandBlock;

  double get bodyMinHeight => math.max(0, size.height - keyboard - brandHeight);

  double get footerGap => keyboard > 0 ? SkySpace.lg : math.max(64, bottomInset + 30);

  double get openBlock => touchBlock + footerGap;

  HeartConstellation get heart {
    final top = brandHeight;
    final bottom = size.height - openBlock - ringReach;
    final room = math.max(0.0, bottom - top);
    final scale = ((room - 16) / (29 * k)).clamp(2.6, heartScale);
    final height = 29 * scale * k;
    final heartTop = top + math.max(0.0, room - height) * heartLift;
    final centerY = (heartTop + 12 * scale * k) / k;
    return HeartConstellation(
      center: Offset(designWidth / 2, centerY),
      scale: scale,
      dim: heartDim,
      presence: false,
      gapGuide: false,
    );
  }

  SkyScene get scene => sceneWithHeart(1);

  SkyScene sceneWithHeart(double glow) {
    final h = designHeightHere;
    final shown = glow.clamp(0.0, 1.0);
    return SkyScene(
      moon: const Offset(312, 92),
      sunAt: Offset(60, h - 44),
      skyline: h - 58,
      clouds: const [
        SkyCloud(320, 120, scale: 1, opacity: 0.8),
        SkyCloud(70, 260, scale: 0.75, opacity: 0.55),
        SkyCloud(340, 470, scale: 0.6, opacity: 0.45),
      ],
      heart: shown <= 0.01 ? null : heart.copyWith(dim: heartDim * shown),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LockMetrics &&
      other.size == size &&
      other.topInset == topInset &&
      other.bottomInset == bottomInset &&
      other.keyboard == keyboard;

  @override
  int get hashCode => Object.hash(size, topInset, bottomInset, keyboard);
}

typedef LockViewBuilder = Widget Function(BuildContext context, LockMetrics metrics);

class LockSkyFrame extends StatefulWidget {
  const LockSkyFrame({
    super.key,
    required this.viewKey,
    required this.builder,
    this.reverse = false,
    this.header,
    this.headerExtent = 0,
    this.heartVisible = true,
  });

  final Object viewKey;
  final LockViewBuilder builder;
  final bool reverse;
  final Widget? header;
  final double headerExtent;
  final bool heartVisible;

  static const Duration entranceMemory = Duration(milliseconds: 1200);

  @override
  State<LockSkyFrame> createState() => _LockSkyFrameState();
}

class _LockSkyFrameState extends State<LockSkyFrame> {
  static DateTime? _lastSeen;

  late final bool _enter;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final last = _lastSeen;
    _enter = last == null || now.difference(last) > LockSkyFrame.entranceMemory;
    _lastSeen = now;
  }

  @override
  void dispose() {
    _lastSeen = DateTime.now();
    super.dispose();
  }

  Widget _maybeEnter(Widget child, int index) => _enter ? SkyEntrance(index: index, child: child) : child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final padding = MediaQuery.viewPaddingOf(context);
        final keyboard = MediaQuery.viewInsetsOf(context).bottom;
        final metrics = LockMetrics(size: constraints.biggest, topInset: padding.top, bottomInset: padding.bottom);
        final layout = LockMetrics(
          size: constraints.biggest,
          topInset: padding.top,
          bottomInset: padding.bottom,
          keyboard: keyboard,
        );
        final tokens = context.sky;
        final motion = skyMotionAllowed(context);
        final scroll = SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: SkySizes.maxContentWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: metrics.brandHeight,
                    child: _maybeEnter(LockBrand(top: metrics.brandTop), 0),
                  ),
                  if (widget.header != null)
                    SizedBox(
                      height: widget.headerExtent,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(SkySpace.gutter, 0, SkySpace.gutter, SkySpace.lg),
                        child: SkyEntrance(index: 1, child: widget.header!),
                      ),
                    ),
                  _maybeEnter(
                    SkySharedAxisSwitcher(
                      axis: SharedAxisTransitionType.horizontal,
                      reverse: widget.reverse,
                      child: KeyedSubtree(
                        key: ValueKey<Object>(widget.viewKey),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: math.max(0.0, layout.bodyMinHeight - widget.headerExtent),
                          ),
                          child: widget.builder(context, layout),
                        ),
                      ),
                    ),
                    2,
                  ),
                ],
              ),
            ),
          ),
        );
        final body = Padding(
          padding: EdgeInsets.only(bottom: keyboard),
          child: scroll,
        );
        return SkyTheme(
          child: AnnotatedRegion(
            value: tokens.statusBar,
            child: Material(
              color: tokens.page,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(
                    child: TweenAnimationBuilder<double>(
                      tween: Tween<double>(
                        end: widget.heartVisible ? (keyboard > 0 ? LockMetrics.keyboardHeartGlow : 1) : 0,
                      ),
                      duration: motion ? SkyMotion.slow : Duration.zero,
                      curve: SkyMotion.standard,
                      builder: (context, glow, _) => SkyBackdrop(scene: metrics.sceneWithHeart(glow)),
                    ),
                  ),
                  body,
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class LockBrand extends StatelessWidget {
  const LockBrand({super.key, required this.top, this.now});

  final double top;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final text = context.skyText;
    final weekday = DateFormat('EEEE').format(now ?? DateTime.now());
    return Padding(
      padding: EdgeInsets.only(top: top, left: SkySpace.gutter, right: SkySpace.gutter),
      child: Align(
        alignment: Alignment.topCenter,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.topCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                LockCopy.kicker(night: t.isNight, weekday: weekday).toUpperCase(),
                style: text.kicker,
              ),
              const SizedBox(height: 6),
              Semantics(
                header: true,
                child: Text(LockCopy.title, textAlign: TextAlign.center, style: text.displayLarge),
              ),
              const SizedBox(height: 10),
              Text(
                LockCopy.tagline,
                textAlign: TextAlign.center,
                style: SkyType.sans(13.5, height: 1.5).copyWith(color: t.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LockFooter extends StatelessWidget {
  const LockFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final style = SkyType.sans(11, height: 1.3).copyWith(color: t.faint);
    return Semantics(
      label: LockCopy.footer,
      excludeSemantics: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SkyIcon(SkyIcons.lock, size: 12, color: t.faint),
          const SizedBox(width: 6),
          Text(LockCopy.footerLead, style: style),
          Flexible(
            child: Text(LockCopy.footerRest, style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

class LockOpenView extends StatelessWidget {
  const LockOpenView({super.key, required this.metrics, required this.children, this.footerSpace = 36});

  final LockMetrics metrics;
  final List<Widget> children;
  final double footerSpace;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: SkySpace.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: SkySpace.lg),
          ...children,
          SizedBox(height: footerSpace),
          const LockFooter(),
          SizedBox(height: metrics.footerGap),
        ],
      ),
    );
  }
}

class LockFormView extends StatelessWidget {
  const LockFormView({super.key, required this.metrics, required this.children});

  final LockMetrics metrics;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: SkySpace.gutter),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 28),
              const LockFooter(),
              SizedBox(height: metrics.footerGap),
            ],
          ),
        ],
      ),
    );
  }
}
