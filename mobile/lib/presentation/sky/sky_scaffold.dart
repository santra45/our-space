import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'sky_canvas.dart';
import 'sky_controls.dart';
import 'sky_icons.dart';
import 'sky_metrics.dart';
import 'sky_motion.dart';
import 'sky_scene.dart';
import 'sky_theme.dart';
import 'sky_tokens.dart';
import 'sky_type.dart';

class SkyScaffold extends StatelessWidget {
  const SkyScaffold({
    super.key,
    required this.body,
    this.scene = SkyScene.page,
    this.skyHeight = SkySizes.skyHeight,
    this.fadeSky = true,
    this.showSky = true,
    this.anchors = const [],
    this.overlays = const [],
  });

  final Widget body;
  final SkyScene scene;
  final double skyHeight;
  final bool fadeSky;
  final bool showSky;
  final List<SkyAnchor> anchors;
  final List<Widget> overlays;

  @override
  Widget build(BuildContext context) {
    final tokens = context.sky;
    return SkyTheme(
      child: AnnotatedRegion(
        value: tokens.statusBar,
        child: Material(
          color: tokens.page,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (showSky)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: skyHeight.isFinite ? skyHeight : null,
                  bottom: skyHeight.isFinite ? null : 0,
                  child: SkyBackdrop(scene: scene, fade: fadeSky, anchors: anchors),
                ),
              body,
              ...overlays,
            ],
          ),
        ),
      ),
    );
  }
}

class SkyScrollScaffold extends StatelessWidget {
  const SkyScrollScaffold({
    super.key,
    required this.children,
    this.topBar,
    this.scene = SkyScene.page,
    this.skyHeight = SkySizes.skyHeight,
    this.fadeSky = true,
    this.anchors = const [],
    this.padding = const EdgeInsets.fromLTRB(SkySpace.gutter, SkySpace.lg, SkySpace.gutter, 0),
    this.spacing = SkySpace.md,
    this.stagger = true,
    this.controller,
    this.physics,
    this.overlays = const [],
  });

  final List<Widget> children;
  final Widget? topBar;
  final SkyScene scene;
  final double skyHeight;
  final bool fadeSky;
  final List<SkyAnchor> anchors;
  final EdgeInsets padding;
  final double spacing;
  final bool stagger;
  final ScrollController? controller;
  final ScrollPhysics? physics;
  final List<Widget> overlays;

  static double bottomInsetOf(BuildContext context) {
    final media = MediaQuery.of(context);
    if (media.viewInsets.bottom > 0) return SkySpace.lg;
    return math.max(media.padding.bottom + SkySpace.xl, SkySpace.lg);
  }

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0 && spacing > 0) SizedBox(height: spacing),
        stagger ? SkyEntrance(index: i + 1, child: children[i]) : children[i],
      ],
    ];
    return SkyScaffold(
      showSky: false,
      overlays: overlays,
      body: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bottom = bottomInsetOf(context);
            return SingleChildScrollView(
              controller: controller,
              physics: physics,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Stack(
                  children: [
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: skyHeight,
                      child: SkyBackdrop(scene: scene, fade: fadeSky, anchors: anchors),
                    ),
                    Padding(
                      padding: EdgeInsets.only(bottom: bottom),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: SkySizes.maxContentWidth),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (topBar != null) stagger ? SkyEntrance(child: topBar!) : topBar!,
                              Padding(
                                padding: padding,
                                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: items),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class SkyTopBar extends StatelessWidget {
  const SkyTopBar({super.key, required this.title, this.kicker, this.leading, this.trailing, this.compact = false});

  final String title;
  final String? kicker;
  final Widget? leading;
  final Widget? trailing;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final text = context.skyText;
    final top = MediaQuery.viewPaddingOf(context).top + SkySpace.topBarGap;
    final side = compact ? SkySpace.gutter : SkySpace.topBarSide;
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (kicker != null) ...[
          Text(kicker!.toUpperCase(), style: text.kicker, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
        ],
        Semantics(
          header: true,
          child: Text(title, style: compact ? text.title : text.display, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(side, top, side, 0),
      child: Row(
        crossAxisAlignment: compact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: SkySpace.md)],
          Expanded(child: heading),
          if (trailing != null) ...[const SizedBox(width: SkySpace.md), trailing!],
        ],
      ),
    );
  }
}

class SkyBackButton extends StatelessWidget {
  const SkyBackButton({super.key, this.onPressed, this.semanticLabel = 'Back'});

  final VoidCallback? onPressed;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return SkyIconButton(
      icon: SkyIcons.back,
      tone: SkyIconButtonTone.ghost,
      semanticLabel: semanticLabel,
      onPressed: onPressed ?? () => Navigator.of(context).maybePop(),
    );
  }
}
