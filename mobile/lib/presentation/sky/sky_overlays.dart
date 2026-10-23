import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import 'sky_controls.dart';
import 'sky_icons.dart';
import 'sky_metrics.dart';
import 'sky_motion.dart';
import 'sky_theme.dart';
import 'sky_tokens.dart';
import 'sky_type.dart';

const String _emojiPattern = r'\s*[\p{Extended_Pictographic}\u{1F3FB}-\u{1F3FF}\u{FE0F}\u{200D}\u{20E3}]+\s*';
final RegExp _emojiRun = RegExp(_emojiPattern, unicode: true);
final RegExp _endsWithPunctuation = RegExp(r'[.!?…,:;]$');

String skyCalmText(String text) {
  final parts = [
    for (final part in text.split(_emojiRun))
      if (part.trim().isNotEmpty) part.trim(),
  ];
  if (parts.isEmpty) return '';
  final buffer = StringBuffer(parts.first);
  for (var i = 1; i < parts.length; i++) {
    var next = parts[i];
    if (_endsWithPunctuation.hasMatch(buffer.toString())) {
      buffer.write(' ');
    } else {
      buffer.write('. ');
      next = next[0].toUpperCase() + next.substring(1);
    }
    buffer.write(next);
  }
  return buffer.toString();
}

class SkySheet extends StatelessWidget {
  const SkySheet({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(SkySpace.gutter, 0, SkySpace.gutter, SkySpace.gutter),
    this.showGrab = true,
    this.safeBottom = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool showGrab;
  final bool safeBottom;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: SkyRadii.top(SkyRadii.sheet),
        border: Border(top: BorderSide(color: t.cardBorder)),
        boxShadow: t.sheetShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            if (t.isNight)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 30,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [t.gold.withValues(alpha: 0.1), t.gold.withValues(alpha: 0)],
                      ),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: EdgeInsets.only(bottom: keyboard),
              child: SafeArea(
                top: false,
                bottom: safeBottom,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (showGrab) const SkyGrabHandle() else const SizedBox(height: SkySpace.lg),
                    Flexible(
                      child: Padding(padding: padding, child: child),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SkyGrabHandle extends StatelessWidget {
  const SkyGrabHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: SkySizes.grabWidth,
        height: SkySizes.grabHeight,
        margin: const EdgeInsets.fromLTRB(0, 10, 0, 12),
        decoration: BoxDecoration(
          color: context.sky.muted.withValues(alpha: 0.35),
          borderRadius: SkyRadii.all(SkySizes.grabHeight),
        ),
      ),
    );
  }
}

class SkySheetRoute<T> extends PopupRoute<T> {
  SkySheetRoute({
    required this.builder,
    required this.tokens,
    this.dismissible = true,
    this.enableDrag = true,
    this.chrome = true,
    this.maxHeightFactor = 0.92,
    this.padding = const EdgeInsets.fromLTRB(SkySpace.gutter, 0, SkySpace.gutter, SkySpace.gutter),
    this.label = 'Close',
    super.settings,
  });

  final WidgetBuilder builder;
  final SkyTokens tokens;
  final bool dismissible;
  final bool enableDrag;
  final bool chrome;
  final double maxHeightFactor;
  final EdgeInsetsGeometry padding;
  final String label;

  @override
  Color? get barrierColor => tokens.scrim;

  @override
  bool get barrierDismissible => dismissible;

  @override
  String? get barrierLabel => label;

  @override
  Duration get transitionDuration => SkyMotion.sheet;

  @override
  Duration get reverseTransitionDuration => SkyMotion.base;

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
    final content = Builder(builder: builder);
    final sheet = chrome ? SkySheet(padding: padding, child: content) : content;
    final height = MediaQuery.sizeOf(context).height;
    return SkyTheme(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: height * maxHeightFactor, maxWidth: SkySizes.maxContentWidth + 80),
          child: _SheetDrag(
            enabled: enableDrag && dismissible,
            onDismiss: () => Navigator.of(context).maybePop(),
            child: sheet,
          ),
        ),
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (!skyMotionAllowed(context)) return FadeTransition(opacity: animation, child: child);
    final slide = CurvedAnimation(
      parent: animation,
      curve: const SkySpringCurve(SkyMotion.sheetSpring, seconds: 0.42),
      reverseCurve: Curves.easeInCubic,
    );
    return SlideTransition(
      position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(slide),
      child: child,
    );
  }
}

class _SheetDrag extends StatefulWidget {
  const _SheetDrag({required this.enabled, required this.onDismiss, required this.child});

  final bool enabled;
  final VoidCallback onDismiss;
  final Widget child;

  @override
  State<_SheetDrag> createState() => _SheetDragState();
}

class _SheetDragState extends State<_SheetDrag> with SingleTickerProviderStateMixin {
  late final AnimationController _offset = AnimationController.unbounded(vsync: this);
  bool _leaving = false;

  void _update(DragUpdateDetails details) {
    if (_leaving) return;
    _offset.value = math.max(0, _offset.value + details.delta.dy);
  }

  void _end(DragEndDetails details) {
    if (_leaving) return;
    final height = context.size?.height ?? 400;
    final velocity = details.velocity.pixelsPerSecond.dy;
    if (velocity > 700 || _offset.value > height * 0.3) {
      _leaving = true;
      widget.onDismiss();
      return;
    }
    _offset.animateWith(SpringSimulation(SkyMotion.sheetSpring, _offset.value, 0, velocity));
  }

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return GestureDetector(
      onVerticalDragUpdate: _update,
      onVerticalDragEnd: _end,
      child: AnimatedBuilder(
        animation: _offset,
        builder: (context, child) => Transform.translate(offset: Offset(0, _offset.value), child: child),
        child: widget.child,
      ),
    );
  }
}

Future<T?> showSkySheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isDismissible = true,
  bool enableDrag = true,
  bool useRootNavigator = true,
  bool chrome = true,
  double maxHeightFactor = 0.92,
  EdgeInsetsGeometry padding = const EdgeInsets.fromLTRB(SkySpace.gutter, 0, SkySpace.gutter, SkySpace.gutter),
  RouteSettings? settings,
}) {
  return Navigator.of(context, rootNavigator: useRootNavigator).push<T>(
    SkySheetRoute<T>(
      builder: builder,
      tokens: context.sky,
      dismissible: isDismissible,
      enableDrag: enableDrag,
      chrome: chrome,
      maxHeightFactor: maxHeightFactor,
      padding: padding,
      settings: settings,
    ),
  );
}

class SkyDialog extends StatelessWidget {
  const SkyDialog({
    super.key,
    this.icon,
    this.tone = SkyTone.rose,
    this.title,
    this.message,
    this.child,
    this.actions = const [],
  });

  final SkyIcons? icon;
  final SkyTone tone;
  final String? title;
  final String? message;
  final Widget? child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    return Material(
      type: MaterialType.transparency,
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: SkyRadii.all(SkyRadii.feature),
          border: Border.all(color: t.cardBorder),
          boxShadow: t.shadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (icon != null) ...[
              Center(
                child: SkyIconTile(icon: icon!, tone: tone, size: 44, iconSize: 22),
              ),
              const SizedBox(height: 14),
            ],
            if (title != null)
              Semantics(
                header: true,
                child: Text(
                  title!,
                  textAlign: TextAlign.center,
                  style: SkyType.serif(22, weight: FontWeight.w500, height: 1.2).copyWith(color: t.text),
                ),
              ),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: SkyType.bodySmall.copyWith(color: t.muted),
              ),
            ],
            if (child != null) ...[const SizedBox(height: 14), child!],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 20),
              Row(
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
                    Expanded(child: actions[i]),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Future<T?> showSkyDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool dismissible = true,
  bool useRootNavigator = true,
}) {
  final tokens = context.sky;
  return showGeneralDialog<T>(
    context: context,
    useRootNavigator: useRootNavigator,
    barrierDismissible: dismissible,
    barrierLabel: 'Close',
    barrierColor: tokens.isNight ? const Color(0x99060516) : const Color(0x4D2B2A6B),
    transitionDuration: SkyMotion.base,
    pageBuilder: (dialogContext, animation, secondary) => SkyTheme(
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Builder(builder: builder),
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (dialogContext, animation, secondary, child) {
      final fade = CurvedAnimation(parent: animation, curve: Curves.easeOut, reverseCurve: Curves.easeIn);
      if (!skyMotionAllowed(dialogContext)) return FadeTransition(opacity: fade, child: child);
      final scale = CurvedAnimation(
        parent: animation,
        curve: const SkySpringCurve(SkyMotion.popSpring, seconds: 0.3),
        reverseCurve: Curves.easeIn,
      );
      return FadeTransition(
        opacity: fade,
        child: ScaleTransition(scale: Tween<double>(begin: 0.94, end: 1).animate(scale), child: child),
      );
    },
  );
}

Future<bool> showSkyConfirm(
  BuildContext context, {
  required String title,
  String? message,
  String confirmLabel = 'Yes',
  String cancelLabel = 'Not now',
  bool destructive = false,
  SkyIcons? icon,
  Widget? child,
}) async {
  final result = await showSkyDialog<bool>(
    context: context,
    dismissible: false,
    builder: (dialogContext) => SkyDialog(
      icon: icon ?? (destructive ? SkyIcons.alert : null),
      tone: destructive ? SkyTone.rose : SkyTone.gold,
      title: title,
      message: message,
      actions: [
        SkyButton(
          label: cancelLabel,
          variant: SkyButtonVariant.ghost,
          onPressed: () => Navigator.of(dialogContext).pop(false),
        ),
        SkyButton(
          label: confirmLabel,
          variant: destructive ? SkyButtonVariant.danger : SkyButtonVariant.primary,
          onPressed: () => Navigator.of(dialogContext).pop(true),
        ),
      ],
      child: child,
    ),
  );
  return result ?? false;
}

class SkyToastPill extends StatelessWidget {
  const SkyToastPill({super.key, required this.message, this.onTap});

  final String message;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: Color.alphaBlend(t.tipBg, t.surface),
        borderRadius: SkyRadii.all(SkyRadii.tile),
        border: Border.all(color: t.tipBorder),
        boxShadow: t.shadow,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SkyIcon(SkyIcons.sparkle, size: 14, color: t.rose),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: SkyType.sans(12.5, weight: FontWeight.w600, height: 1.35).copyWith(color: t.tipText),
            ),
          ),
        ],
      ),
    );
    return Semantics(
      liveRegion: true,
      container: true,
      child: onTap == null ? pill : GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: pill),
    );
  }
}

class SkyToastController extends ChangeNotifier {
  SkyToastController({this.ttl = SkyMotion.toast});

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

class SkyToastScope extends InheritedNotifier<SkyToastController> {
  const SkyToastScope({super.key, required SkyToastController controller, required super.child})
    : super(notifier: controller);

  static SkyToastController? maybeOf(BuildContext context) {
    return context.getInheritedWidgetOfExactType<SkyToastScope>()?.notifier;
  }
}

class SkyToastHost extends StatelessWidget {
  const SkyToastHost({super.key, required this.controller});

  final SkyToastController controller;

  @override
  Widget build(BuildContext context) {
    final motion = skyMotionAllowed(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final message = controller.message;
        final calm = message == null ? '' : skyCalmText(message);
        return AnimatedSwitcher(
          duration: motion ? SkyMotion.medium : Duration.zero,
          reverseDuration: motion ? SkyMotion.quick : Duration.zero,
          switchInCurve: SkyMotion.standard,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(begin: const Offset(0, -0.4), end: Offset.zero).animate(animation),
              child: child,
            ),
          ),
          child: calm.isEmpty
              ? const SizedBox(key: ValueKey<String>('sky-toast-empty'), width: double.infinity)
              : Center(
                  key: ValueKey<String>('sky-toast-$message'),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 448),
                    child: SkyToastPill(message: calm, onTap: controller.clear),
                  ),
                ),
        );
      },
    );
  }
}

abstract final class SkyToast {
  static void show(BuildContext context, String message) {
    final scoped = SkyToastScope.maybeOf(context);
    if (scoped != null) {
      scoped.show(message);
      return;
    }
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    final tokens = context.sky;
    final calm = skyCalmText(message);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (overlayContext) => Positioned(
        top: MediaQuery.viewPaddingOf(overlayContext).top + 12,
        left: 16,
        right: 16,
        child: IgnorePointer(
          child: Theme(
            data: SkyThemes.legacy(tokens),
            child: Center(
              child: SkyEntrance(child: SkyToastPill(message: calm)),
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    Timer(SkyMotion.toast, () {
      if (entry.mounted) entry.remove();
      entry.dispose();
    });
  }
}
