import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_gradients.dart';
import '../theme/app_metrics.dart';
import '../theme/app_theme.dart';
import 'ambient_particles.dart';

@immutable
class DocumentScroll {
  const DocumentScroll({required this.pixels, required this.maxScrollExtent});

  final double pixels;
  final double maxScrollExtent;

  static DocumentScroll? fromMetrics(ScrollMetrics metrics) {
    if (metrics.axis != Axis.vertical) return null;
    if (!metrics.hasContentDimensions || !metrics.hasPixels) return null;
    final extent = math.max(0.0, metrics.maxScrollExtent - metrics.minScrollExtent);
    final pixels = (metrics.pixels - metrics.minScrollExtent).clamp(0.0, extent);
    return DocumentScroll(pixels: pixels, maxScrollExtent: extent);
  }

  @override
  bool operator ==(Object other) =>
      other is DocumentScroll && other.pixels == pixels && other.maxScrollExtent == maxScrollExtent;

  @override
  int get hashCode => Object.hash(pixels, maxScrollExtent);
}

class BodyGradientPainter extends CustomPainter {
  BodyGradientPainter(this.scroll) : super(repaint: scroll);

  final ValueListenable<DocumentScroll?> scroll;

  static Rect documentRect(Size viewport, DocumentScroll? scroll) {
    if (scroll == null) return Offset.zero & viewport;
    return Rect.fromLTWH(0, -scroll.pixels, viewport.width, viewport.height + scroll.maxScrollExtent);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = documentRect(size, scroll.value);
    canvas.drawRect(Offset.zero & size, Paint()..shader = AppGradients.body.createShader(rect));
  }

  @override
  bool shouldRepaint(BodyGradientPainter oldDelegate) => oldDelegate.scroll != scroll;
}

class OurBackdrop extends StatefulWidget {
  const OurBackdrop({
    super.key,
    required this.child,
    this.particles = true,
    this.followScroll = true,
    this.scrollToken,
    this.particleSeed,
  });

  final Widget child;
  final bool particles;
  final bool followScroll;
  final Object? scrollToken;
  final int? particleSeed;

  @override
  State<OurBackdrop> createState() => _OurBackdropState();
}

class _OurBackdropState extends State<OurBackdrop> {
  final ValueNotifier<DocumentScroll?> _scroll = ValueNotifier<DocumentScroll?>(null);

  @override
  void didUpdateWidget(covariant OurBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollToken != widget.scrollToken) _scroll.value = null;
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  bool _onMetrics(ScrollMetricsNotification n) {
    if (widget.followScroll && n.depth == 0) _scroll.value = DocumentScroll.fromMetrics(n.metrics);
    return false;
  }

  bool _onScroll(ScrollNotification n) {
    if (widget.followScroll && n.depth == 0) _scroll.value = DocumentScroll.fromMetrics(n.metrics);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(child: CustomPaint(painter: BodyGradientPainter(_scroll))),
        if (widget.particles) Positioned.fill(child: AmbientParticles(seed: widget.particleSeed)),
        NotificationListener<ScrollMetricsNotification>(
          onNotification: _onMetrics,
          child: NotificationListener<ScrollNotification>(onNotification: _onScroll, child: widget.child),
        ),
      ],
    );
  }
}

List<Widget> spaced(List<Widget> children, double spacing) {
  if (spacing <= 0 || children.length < 2) return children;
  return [
    for (var i = 0; i < children.length; i++) ...[
      if (i > 0) SizedBox(height: spacing),
      children[i],
    ],
  ];
}

class OurPage extends StatelessWidget {
  const OurPage({
    super.key,
    required this.children,
    this.spacing = 16,
    this.controller,
    this.physics,
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
    this.maxWidth = AppLayout.maxWidthMd,
    this.horizontalPadding = AppLayout.pagePaddingX,
  });

  final List<Widget> children;
  final double spacing;
  final ScrollController? controller;
  final ScrollPhysics? physics;
  final CrossAxisAlignment crossAxisAlignment;
  final double maxWidth;
  final double horizontalPadding;

  static EdgeInsets paddingOf(BuildContext context, {double horizontal = AppLayout.pagePaddingX}) {
    final media = MediaQuery.of(context);
    final bottom = math.max(media.padding.bottom + AppLayout.pageBottomExtra, media.viewInsets.bottom + AppLayout.pagePaddingTop);
    return EdgeInsets.fromLTRB(horizontal, media.padding.top + AppLayout.pagePaddingTop, horizontal, bottom);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: controller,
      physics: physics,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
      padding: paddingOf(context, horizontal: horizontalPadding),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Column(
            crossAxisAlignment: crossAxisAlignment,
            mainAxisSize: MainAxisSize.min,
            children: spaced(children, spacing),
          ),
        ),
      ),
    );
  }
}

class OurCenteredPage extends StatelessWidget {
  const OurCenteredPage({super.key, required this.child, this.maxWidth = AppLayout.maxWidthMd, this.padding = 16});

  final Widget child;
  final double maxWidth;
  final double padding;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final insets = EdgeInsets.fromLTRB(
      padding + media.padding.left,
      padding + media.padding.top,
      padding + media.padding.right,
      padding + math.max(media.padding.bottom, media.viewInsets.bottom),
    );
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: insets,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: math.max(0, constraints.maxHeight - insets.vertical)),
          child: Center(
            child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
          ),
        ),
      ),
    );
  }
}

class StatusBarTint extends StatelessWidget {
  const StatusBarTint({super.key, this.color = AppTheme.statusBarTint});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.viewPaddingOf(context).top;
    if (top <= 0) return const SizedBox.shrink();
    return Positioned(top: 0, left: 0, right: 0, height: top, child: ColoredBox(color: color));
  }
}

class OurScaffold extends StatelessWidget {
  const OurScaffold({super.key, required this.body, this.particles = true, this.tintStatusBar = true});

  final Widget body;
  final bool particles;
  final bool tintStatusBar;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.systemOverlay,
      child: Scaffold(
        backgroundColor: AppGradients.body.colors.first,
        resizeToAvoidBottomInset: false,
        body: OurBackdrop(
          particles: particles,
          child: Stack(
            fit: StackFit.expand,
            children: [
              body,
              if (tintStatusBar) const StatusBarTint(),
            ],
          ),
        ),
      ),
    );
  }
}
