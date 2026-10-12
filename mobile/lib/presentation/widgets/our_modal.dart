import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_metrics.dart';
import '../theme/app_motion.dart';
import '../theme/app_shadows.dart';
import '../theme/app_typography.dart';
import 'app_haptics.dart';
import 'app_icons.dart';
import 'css_box.dart';
import 'lucide_icon.dart';
import 'tw_animations.dart';

enum OurBackdropTone { slate40, black50, black60, black80 }

extension OurBackdropToneStyle on OurBackdropTone {
  Color get color {
    switch (this) {
      case OurBackdropTone.slate40:
        return AppColors.slate900.withValues(alpha: 0.4);
      case OurBackdropTone.black50:
        return AppColors.black.withValues(alpha: 0.5);
      case OurBackdropTone.black60:
        return AppColors.black.withValues(alpha: 0.6);
      case OurBackdropTone.black80:
        return AppColors.black.withValues(alpha: 0.8);
    }
  }

  double get blur => this == OurBackdropTone.black80 ? 12 : 4;
}

enum OurModalEntrance { pop, popSoft, sheet, rise, none }

@immutable
class ModalEntranceFrame {
  const ModalEntranceFrame(this.opacity, this.scale, this.dy);

  final double opacity;
  final double scale;
  final double dy;
}

ModalEntranceFrame entranceFrameAt(OurModalEntrance entrance, double seconds) {
  final fade = AppMotion.framerEase.transform((seconds / 0.3).clamp(0.0, 1.0));
  double scaleFrom(double from) => AppMotion.springValue(AppMotion.framerScaleSpring, from, 1, seconds);
  double slideFrom(double from) => AppMotion.springValue(AppMotion.framerPositionSpring, from, 0, seconds);
  switch (entrance) {
    case OurModalEntrance.pop:
      return ModalEntranceFrame(fade, scaleFrom(0.9), slideFrom(20));
    case OurModalEntrance.popSoft:
      return ModalEntranceFrame(fade, scaleFrom(0.95), 0);
    case OurModalEntrance.sheet:
      return ModalEntranceFrame(fade, 1, slideFrom(40));
    case OurModalEntrance.rise:
      final t = Curves.easeOut.transform((seconds / 0.25).clamp(0.0, 1.0));
      return ModalEntranceFrame(t, 0.98 + 0.02 * t, 24 * (1 - t));
    case OurModalEntrance.none:
      return const ModalEntranceFrame(1, 1, 0);
  }
}

Future<T?> showOurModal<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  OurBackdropTone backdrop = OurBackdropTone.slate40,
  OurModalEntrance entrance = OurModalEntrance.pop,
  bool barrierDismissible = false,
  Alignment alignment = Alignment.center,
  EdgeInsets screenPadding = const EdgeInsets.all(AppLayout.modalScreenPadding),
  bool useRootNavigator = true,
}) {
  const enter = Duration(milliseconds: 450);
  return showGeneralDialog<T>(
    context: context,
    useRootNavigator: useRootNavigator,
    barrierDismissible: barrierDismissible,
    barrierLabel: barrierDismissible ? MaterialLocalizations.of(context).modalBarrierDismissLabel : null,
    barrierColor: AppColors.transparent,
    transitionDuration: enter,
    pageBuilder: (dialogContext, animation, secondary) => Builder(builder: builder),
    transitionBuilder: (dialogContext, animation, secondary, child) {
      final reversing = animation.status == AnimationStatus.reverse;
      final allowed = motionAllowed(dialogContext);
      final seconds = animation.value * enter.inMicroseconds / 1e6;
      final frame = !allowed
          ? const ModalEntranceFrame(1, 1, 0)
          : reversing
          ? ModalEntranceFrame(animation.value, 1, entrance == OurModalEntrance.sheet ? 40 * (1 - animation.value) : 0)
          : entranceFrameAt(entrance, seconds);
      final backdropT = reversing ? animation.value : (seconds / 0.2).clamp(0.0, 1.0);
      final media = MediaQuery.of(dialogContext);
      return Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: barrierDismissible ? () => Navigator.of(dialogContext).maybePop() : null,
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(
                  sigmaX: backdrop.blur * backdropT,
                  sigmaY: backdrop.blur * backdropT,
                ),
                child: ColoredBox(color: backdrop.color.withValues(alpha: backdrop.color.a * backdropT)),
              ),
            ),
          ),
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.only(
                top: entrance == OurModalEntrance.sheet ? media.viewPadding.top : 0,
                bottom: media.viewInsets.bottom,
              ),
              child: SafeArea(
                top: entrance != OurModalEntrance.sheet,
                bottom: entrance != OurModalEntrance.sheet,
                child: Padding(
                  padding: entrance == OurModalEntrance.sheet ? EdgeInsets.zero : screenPadding,
                  child: Align(
                    alignment: entrance == OurModalEntrance.sheet ? Alignment.bottomCenter : alignment,
                    child: Opacity(
                      opacity: frame.opacity.clamp(0.0, 1.0),
                      child: Transform.translate(
                        offset: Offset(0, frame.dy),
                        child: Transform.scale(scale: frame.scale, child: child),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

Future<T?> showOurSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = false,
}) {
  return showOurModal<T>(
    context: context,
    builder: builder,
    entrance: OurModalEntrance.sheet,
    barrierDismissible: barrierDismissible,
  );
}

class OurCloseButton extends StatelessWidget {
  const OurCloseButton({
    super.key,
    this.onPressed,
    this.size = 32,
    this.background = AppColors.slate100,
    this.foreground = AppColors.slate500,
    this.shadows = const [],
    this.enabled = true,
  });

  final VoidCallback? onPressed;
  final double size;
  final Color background;
  final Color foreground;
  final List<BoxShadow> shadows;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      label: MaterialLocalizations.of(context).closeButtonTooltip,
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? (onPressed ?? () => Navigator.of(context).maybePop()) : null,
          child: CssBox(
            width: size,
            height: size,
            color: background,
            borderRadius: AppRadii.all(AppRadii.full),
            shadows: shadows,
            child: Center(child: LucideIcon(AppIcons.x, size: 16, color: foreground)),
          ),
        ),
      ),
    );
  }
}

class OurModalCard extends StatelessWidget {
  const OurModalCard({
    super.key,
    required this.child,
    this.maxWidth = AppLayout.maxWidthSm,
    this.padding = const EdgeInsets.all(20),
    this.borderColor = AppColors.blush100,
    this.background = AppColors.white,
    this.radius = AppRadii.x3l,
    this.showClose = true,
    this.onClose,
    this.closeEnabled = true,
    this.maxHeightFactor = AppLayout.modalMaxHeightFactor,
    this.sheet = false,
    this.borderWidth = 1,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsets padding;
  final Color borderColor;
  final Color background;
  final double radius;
  final bool showClose;
  final VoidCallback? onClose;
  final bool closeEnabled;
  final double maxHeightFactor;
  final bool sheet;
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final maxHeight = media.size.height * (sheet ? AppLayout.sheetMaxHeightFactor : maxHeightFactor);
    final borderRadius = sheet ? AppRadii.top(radius) : AppRadii.all(radius);
    final bottomInset = sheet ? media.viewPadding.bottom : 0.0;

    Widget content = Stack(
      clipBehavior: Clip.none,
      children: [
        Padding(padding: padding.copyWith(bottom: padding.bottom + bottomInset), child: child),
        if (showClose)
          Positioned(
            top: 16,
            right: 16,
            child: OurCloseButton(onPressed: onClose, enabled: closeEnabled),
          ),
      ],
    );

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: sheet ? double.infinity : maxWidth, maxHeight: maxHeight),
      child: Material(
        type: MaterialType.transparency,
        child: CssBox(
          color: background,
          border: Border.all(color: borderColor, width: borderWidth),
          borderRadius: borderRadius,
          shadows: AppShadows.x2l,
          clipContent: true,
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: SizedBox(width: double.infinity, child: content),
          ),
        ),
      ),
    );
  }
}

class OurModalHeader extends StatelessWidget {
  const OurModalHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.iconBackground = AppColors.blush100,
    this.iconColor = AppColors.blush500,
    this.iconFill,
    this.iconSize = 16,
    this.circleSize = 32,
    this.bottomSpacing = 16,
    this.trailingSpace = 40,
  });

  final String title;
  final String? subtitle;
  final LucideIconData? icon;
  final Color iconBackground;
  final Color iconColor;
  final Color? iconFill;
  final double iconSize;
  final double circleSize;
  final double bottomSpacing;
  final double trailingSpace;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottomSpacing, right: trailingSpace),
      child: Row(
        children: [
          if (icon != null) ...[
            CssBox(
              width: circleSize,
              height: circleSize,
              color: iconBackground,
              borderRadius: AppRadii.all(AppRadii.full),
              child: Center(child: LucideIcon(icon!, size: iconSize, color: iconColor, fill: iconFill)),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: Tw.base.bold.c(AppColors.slate800)),
                if (subtitle != null) Text(subtitle!, style: Tw.px11.c(AppColors.slate400)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class OurDialogActions extends StatelessWidget {
  const OurDialogActions({
    super.key,
    required this.confirmLabel,
    required this.onConfirm,
    this.cancelLabel = 'Cancel',
    this.onCancel,
    this.busy = false,
    this.busyLabel = 'Working...',
    this.confirmEnabled = true,
    this.cancelEnabled = true,
    this.confirmColor = AppColors.blush500,
  });

  final String confirmLabel;
  final VoidCallback? onConfirm;
  final String cancelLabel;
  final VoidCallback? onCancel;
  final bool busy;
  final String busyLabel;
  final bool confirmEnabled;
  final bool cancelEnabled;
  final Color confirmColor;

  @override
  Widget build(BuildContext context) {
    final cancelActive = cancelEnabled && !busy;
    final confirmActive = confirmEnabled && !busy && onConfirm != null;
    final radius = AppRadii.all(AppRadii.x2l);
    return Row(
      children: [
        Expanded(
          child: Opacity(
            opacity: cancelActive ? 1 : 0.5,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: cancelActive
                  ? () {
                      AppHaptics.tick();
                      (onCancel ?? () => Navigator.of(context).maybePop())();
                    }
                  : null,
              child: CssBox(
                padding: const EdgeInsets.symmetric(vertical: 10),
                border: Border.all(color: AppColors.slate200),
                borderRadius: radius,
                child: Text(cancelLabel, textAlign: TextAlign.center, style: Tw.xs.bold.c(AppColors.slate600)),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Opacity(
            opacity: confirmActive || busy ? 1 : 0.5,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: confirmActive
                  ? () {
                      AppHaptics.tap();
                      onConfirm!();
                    }
                  : null,
              child: CssBox(
                padding: const EdgeInsets.symmetric(vertical: 10),
                color: confirmColor,
                borderRadius: radius,
                shadows: AppShadows.tinted(AppShadows.sm, AppColors.blush300.withValues(alpha: 0.5)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (busy) ...[
                      const TwSpin(child: LucideIcon(AppIcons.loader2, size: 14, color: AppColors.white)),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        busy ? busyLabel : confirmLabel,
                        textAlign: TextAlign.center,
                        style: Tw.xs.bold.c(AppColors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

Future<bool> showOurConfirm(
  BuildContext context, {
  required String message,
  String? title,
  String confirmLabel = 'OK',
  String cancelLabel = 'Cancel',
  Color confirmColor = AppColors.blush500,
}) async {
  final result = await showOurModal<bool>(
    context: context,
    backdrop: OurBackdropTone.black60,
    entrance: OurModalEntrance.popSoft,
    builder: (dialogContext) => OurModalCard(
      showClose: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Text(title, style: Tw.base.bold.c(AppColors.slate800)),
            const SizedBox(height: 4),
          ],
          Text(
            message,
            style: (title == null ? Tw.sm.medium.c(AppColors.slate700) : Tw.px11.relaxed.c(AppColors.slate500)),
          ),
          const SizedBox(height: 16),
          OurDialogActions(
            confirmLabel: confirmLabel,
            cancelLabel: cancelLabel,
            confirmColor: confirmColor,
            onCancel: () => Navigator.of(dialogContext).pop(false),
            onConfirm: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    ),
  );
  return result ?? false;
}

double modalMaxWidth(BuildContext context, {double maxWidth = AppLayout.maxWidthSm}) {
  final width = MediaQuery.sizeOf(context).width - AppLayout.modalScreenPadding * 2;
  return math.min(width, maxWidth);
}
