import 'dart:async';
import 'dart:math' as math;

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

enum NoticeTone { warning, error, info, success, indigo, lavender, blush }

@immutable
class NoticePalette {
  const NoticePalette({required this.background, required this.border, required this.text, required this.icon});

  final Color background;
  final Color border;
  final Color text;
  final Color icon;

  static NoticePalette of(NoticeTone tone) {
    switch (tone) {
      case NoticeTone.warning:
        return const NoticePalette(
          background: AppColors.amber50,
          border: AppColors.amber200,
          text: AppColors.amber800,
          icon: AppColors.amber500,
        );
      case NoticeTone.error:
        return const NoticePalette(
          background: AppColors.rose50,
          border: AppColors.rose200,
          text: AppColors.rose700,
          icon: AppColors.rose500,
        );
      case NoticeTone.info:
        return const NoticePalette(
          background: AppColors.slate50,
          border: AppColors.slate200,
          text: AppColors.slate600,
          icon: AppColors.slate400,
        );
      case NoticeTone.success:
        return NoticePalette(
          background: AppColors.emerald50.withValues(alpha: 0.7),
          border: AppColors.emerald100,
          text: AppColors.emerald800,
          icon: AppColors.emerald500,
        );
      case NoticeTone.indigo:
        return NoticePalette(
          background: AppColors.indigo50.withValues(alpha: 0.7),
          border: AppColors.indigo100,
          text: AppColors.indigo800,
          icon: AppColors.indigo500,
        );
      case NoticeTone.lavender:
        return const NoticePalette(
          background: AppColors.lavender50,
          border: AppColors.lavender100,
          text: AppColors.lavender700,
          icon: AppColors.lavender400,
        );
      case NoticeTone.blush:
        return NoticePalette(
          background: AppColors.blush50.withValues(alpha: 0.7),
          border: AppColors.blush100,
          text: AppColors.slate700,
          icon: AppColors.blush500,
        );
    }
  }
}

class OurNotice extends StatelessWidget {
  const OurNotice({
    super.key,
    required this.tone,
    this.message,
    this.child,
    this.title,
    this.icon,
    this.iconColor,
    this.iconSize = 16,
    this.padding = const EdgeInsets.all(12),
    this.radius = AppRadii.x2l,
    this.textStyle,
    this.onDismiss,
    this.centered = false,
    this.borderWidth = 1,
    this.showIcon = true,
  }) : assert(message != null || child != null);

  final NoticeTone tone;
  final String? message;
  final Widget? child;
  final String? title;
  final LucideIconData? icon;
  final Color? iconColor;
  final double iconSize;
  final EdgeInsets padding;
  final double radius;
  final TextStyle? textStyle;
  final VoidCallback? onDismiss;
  final bool centered;
  final double borderWidth;
  final bool showIcon;

  static LucideIconData defaultIcon(NoticeTone tone) {
    switch (tone) {
      case NoticeTone.warning:
      case NoticeTone.error:
        return AppIcons.alertTriangle;
      case NoticeTone.info:
        return AppIcons.info;
      case NoticeTone.success:
        return AppIcons.shieldCheck;
      case NoticeTone.indigo:
        return AppIcons.link2;
      case NoticeTone.lavender:
        return AppIcons.lock;
      case NoticeTone.blush:
        return AppIcons.heart;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = NoticePalette.of(tone);
    final style = (textStyle ?? Tw.xs.medium.snug).c(textStyle?.color ?? palette.text);
    final body = DefaultTextStyle.merge(
      style: style,
      textAlign: centered ? TextAlign.center : TextAlign.start,
      child: Column(
        crossAxisAlignment: centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null) Text(title!, style: style.bold),
          if (title != null && (message != null || child != null)) const SizedBox(height: 4),
          if (message != null) Text(message!),
          if (child != null) child!,
        ],
      ),
    );
    return Semantics(
      liveRegion: tone == NoticeTone.error || tone == NoticeTone.warning,
      child: CssBox(
        padding: padding,
        color: palette.background,
        border: Border.all(color: palette.border, width: borderWidth),
        borderRadius: AppRadii.all(radius),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showIcon && !centered) ...[
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: LucideIcon(icon ?? defaultIcon(tone), size: iconSize, color: iconColor ?? palette.icon),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(child: body),
            if (onDismiss != null) ...[
              const SizedBox(width: 8),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  AppHaptics.tick();
                  onDismiss!();
                },
                child: Semantics(
                  button: true,
                  label: 'Dismiss',
                  child: Opacity(
                    opacity: 0.5,
                    child: LucideIcon(AppIcons.x, size: 14, color: style.color),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class OurNoticePill extends StatelessWidget {
  const OurNoticePill({super.key, required this.message, this.bounce = true});

  final String message;
  final bool bounce;

  @override
  Widget build(BuildContext context) {
    final pill = CssBox(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: AppColors.blush500,
      borderRadius: AppRadii.all(AppRadii.full),
      shadows: AppShadows.primaryButton,
      child: Text(message, textAlign: TextAlign.center, style: Tw.xs.semibold.c(AppColors.white)),
    );
    return Semantics(liveRegion: true, child: bounce ? TwBounce(child: pill) : pill);
  }
}

class OurToastController extends ChangeNotifier {
  OurToastController({this.ttl = AppMotion.toast});

  final Duration ttl;
  String? _message;
  Timer? _timer;

  String? get message => _message;

  void show(String message) {
    _timer?.cancel();
    _message = message;
    notifyListeners();
    _timer = Timer(ttl, clear);
  }

  void clear() {
    _timer?.cancel();
    _timer = null;
    if (_message == null) return;
    _message = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

class OurToastScope extends InheritedNotifier<OurToastController> {
  const OurToastScope({super.key, required OurToastController controller, required super.child})
    : super(notifier: controller);

  static OurToastController? maybeOf(BuildContext context) {
    return context.getInheritedWidgetOfExactType<OurToastScope>()?.notifier;
  }
}

abstract final class OurToast {
  static void show(BuildContext context, String message) {
    final scoped = OurToastScope.maybeOf(context);
    if (scoped != null) {
      scoped.show(message);
      return;
    }
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (overlayContext) {
        final top = MediaQuery.viewPaddingOf(overlayContext).top + 12;
        return Positioned(
          top: top,
          left: 16,
          right: 16,
          child: IgnorePointer(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: AppLayout.maxWidthMd),
                child: OurNoticePill(message: message),
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(entry);
    Timer(AppMotion.toast, () {
      if (entry.mounted) entry.remove();
      entry.dispose();
    });
  }
}

class OurEmptyState extends StatelessWidget {
  const OurEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.iconBackground = AppColors.blush100,
    this.iconColor = AppColors.blush400,
  });

  final LucideIconData icon;
  final String title;
  final String message;
  final Widget? action;
  final Color iconBackground;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return CssBox(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 64),
      color: AppColors.white.withValues(alpha: 0.5),
      dashedBorder: const BorderSide(color: AppColors.blush200, width: 2),
      borderRadius: AppRadii.all(AppRadii.x3l),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CssBox(
            width: 64,
            height: 64,
            color: iconBackground,
            borderRadius: AppRadii.all(AppRadii.full),
            child: Center(child: LucideIcon(icon, size: 32, color: iconColor)),
          ),
          const SizedBox(height: 12),
          Text(title, textAlign: TextAlign.center, style: Tw.base.bold.c(AppColors.slate700)),
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppLayout.maxWidthXs),
            child: Text(message, textAlign: TextAlign.center, style: Tw.xs.c(AppColors.slate500)),
          ),
          if (action != null) ...[const SizedBox(height: 20), action!],
        ],
      ),
    );
  }
}

class OurSpinner extends StatelessWidget {
  const OurSpinner({
    super.key,
    this.size = 32,
    this.strokeWidth = 2,
    this.track = AppColors.blush200,
    this.head = AppColors.blush500,
  });

  final double size;
  final double strokeWidth;
  final Color track;
  final Color head;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading',
      child: TwSpin(
        child: CustomPaint(
          size: Size.square(size),
          painter: _BorderSpinnerPainter(track: track, head: head, strokeWidth: strokeWidth),
        ),
      ),
    );
  }
}

class _BorderSpinnerPainter extends CustomPainter {
  const _BorderSpinnerPainter({required this.track, required this.head, required this.strokeWidth});

  final Color track;
  final Color head;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(strokeWidth / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawOval(rect, paint..color = track);
    canvas.drawArc(rect, -3 * math.pi / 4, math.pi / 2, false, paint..color = head);
  }

  @override
  bool shouldRepaint(_BorderSpinnerPainter oldDelegate) {
    return oldDelegate.track != track || oldDelegate.head != head || oldDelegate.strokeWidth != strokeWidth;
  }
}

class OurSkeleton extends StatelessWidget {
  const OurSkeleton({super.key, this.aspectRatio = 3 / 4, this.radius = AppRadii.x2l, this.height});

  final double aspectRatio;
  final double radius;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final box = CssBox(
      color: AppColors.white.withValues(alpha: 0.6),
      border: Border.all(color: AppColors.slate100),
      borderRadius: AppRadii.all(radius),
      child: const SizedBox.expand(),
    );
    return TwPulse(
      child: height != null ? SizedBox(height: height, child: box) : AspectRatio(aspectRatio: aspectRatio, child: box),
    );
  }
}

class OurPulseText extends StatelessWidget {
  const OurPulseText(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return TwPulse(
      child: Text(text, textAlign: TextAlign.center, style: style ?? Tw.xs.medium.c(AppColors.blush400)),
    );
  }
}

class OurLoadingState extends StatelessWidget {
  const OurLoadingState({super.key, this.message = 'Finding your space…', this.child});

  final String message;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const OurSpinner(),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center, style: Tw.xs.medium.c(AppColors.slate500)),
          if (child != null) ...[const SizedBox(height: 12), child!],
        ],
      ),
    );
  }
}

class OurErrorCard extends StatelessWidget {
  const OurErrorCard({super.key, this.onRetry, this.onReload});

  final VoidCallback? onRetry;
  final VoidCallback? onReload;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppLayout.maxWidthSm),
          child: CssBox(
            padding: const EdgeInsets.all(24),
            color: AppColors.white.withValues(alpha: 0.85),
            border: Border.all(color: AppColors.blush100),
            borderRadius: AppRadii.all(AppRadii.x3l),
            shadows: AppShadows.xl,
            backdropBlur: 8,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CssBox(
                  width: 56,
                  height: 56,
                  color: AppColors.amber100,
                  borderRadius: AppRadii.all(AppRadii.full),
                  child: const Center(child: LucideIcon(AppIcons.alertTriangle, size: 28, color: AppColors.amber500)),
                ),
                const SizedBox(height: 16),
                Text(
                  'Something went a bit wrong',
                  textAlign: TextAlign.center,
                  style: Tw.lg.bold.c(AppColors.slate800),
                ),
                const SizedBox(height: 8),
                Text(
                  'This screen stopped drawing properly. Nothing has been lost — your memories are still saved on this phone.',
                  textAlign: TextAlign.center,
                  style: Tw.xs.relaxed.c(AppColors.slate500),
                ),
                const SizedBox(height: 20),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onRetry,
                  child: CssBox(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    color: AppColors.blush400,
                    borderRadius: AppRadii.all(AppRadii.x2l),
                    shadows: AppShadows.primaryButton,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const LucideIcon(AppIcons.rotateCcw, size: 16, color: AppColors.white),
                        const SizedBox(width: 8),
                        Text('Try again', style: Tw.sm.bold.c(AppColors.white)),
                      ],
                    ),
                  ),
                ),
                if (onReload != null) ...[
                  const SizedBox(height: 8),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onReload,
                    child: CssBox(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      border: Border.all(color: AppColors.slate200),
                      borderRadius: AppRadii.all(AppRadii.x2l),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const LucideIcon(AppIcons.refreshCw, size: 14, color: AppColors.slate600),
                          const SizedBox(width: 8),
                          Text('Reload Our Space', style: Tw.xs.semibold.c(AppColors.slate600)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Reloading will ask for your passphrase again, so try the first button first.',
                    textAlign: TextAlign.center,
                    style: Tw.px10.relaxed.c(AppColors.slate400),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
