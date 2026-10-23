import 'package:flutter/material.dart';

import '../../../sky/sky.dart';

class PeopleSetupFrame extends StatefulWidget {
  const PeopleSetupFrame({super.key, required this.child, this.visible = true, this.viewKey});

  final Widget? child;
  final bool visible;
  final Object? viewKey;

  @override
  State<PeopleSetupFrame> createState() => _PeopleSetupFrameState();
}

class _PeopleSetupFrameState extends State<PeopleSetupFrame> with SingleTickerProviderStateMixin {
  late final AnimationController _show = AnimationController(
    vsync: this,
    duration: SkyMotion.sheet,
    reverseDuration: SkyMotion.base,
  );
  late final Animation<double> _scrim = CurvedAnimation(parent: _show, curve: Curves.easeOut);
  late final Animation<Offset> _slide = Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(
    CurvedAnimation(
      parent: _show,
      curve: const SkySpringCurve(SkyMotion.sheetSpring, seconds: 0.42),
      reverseCurve: Curves.easeInCubic,
    ),
  );

  bool _motion = true;
  bool _started = false;
  Widget? _last;
  Object? _lastKey;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motion = skyMotionAllowed(context);
    if (_started) return;
    _started = true;
    if (widget.visible) _enter();
  }

  @override
  void didUpdateWidget(PeopleSetupFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible && !oldWidget.visible) {
      _enter();
    } else if (!widget.visible && oldWidget.visible) {
      _leave();
    }
  }

  void _enter() {
    _show.duration = _motion ? SkyMotion.sheet : SkyMotion.fast;
    _show.forward();
  }

  void _leave() {
    if (_motion) {
      _show.reverse();
    } else {
      _show.value = 0;
    }
  }

  @override
  void dispose() {
    _show.dispose();
    super.dispose();
  }

  Widget _content() {
    final view = KeyedSubtree(key: ValueKey<Object?>(_lastKey), child: _last ?? const SizedBox.shrink());
    if (!_motion) return view;
    return AnimatedSize(
      duration: SkyMotion.medium,
      curve: SkyMotion.standard,
      alignment: Alignment.topCenter,
      child: SkySharedAxisSwitcher(child: view),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.visible && widget.child != null) {
      _last = widget.child;
      _lastKey = widget.viewKey;
    }
    final media = MediaQuery.of(context);
    final maxHeight = media.size.height - media.viewPadding.top - SkySpace.lg;
    final sheet = SkyTheme(
      child: Builder(
        builder: (context) {
          final t = context.sky;
          final panel = Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: maxHeight < 0 ? 0 : maxHeight,
                maxWidth: SkySizes.maxContentWidth + 80,
              ),
              child: SkySheet(
                showGrab: false,
                padding: EdgeInsets.zero,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(SkySpace.xl, SkySpace.xs, SkySpace.xl, SkySpace.lg),
                  child: _content(),
                ),
              ),
            ),
          );
          return IgnorePointer(
            ignoring: !widget.visible,
            child: Stack(
              fit: StackFit.expand,
              children: [
                FadeTransition(opacity: _scrim, child: ColoredBox(color: t.scrim)),
                if (_motion)
                  SlideTransition(position: _slide, child: panel)
                else
                  FadeTransition(opacity: _show, child: panel),
              ],
            ),
          );
        },
      ),
    );
    return AnimatedBuilder(
      animation: _show,
      child: sheet,
      builder: (context, child) {
        if (!widget.visible && _show.isDismissed) return const SizedBox.shrink();
        return Positioned.fill(child: child!);
      },
    );
  }
}

class PeopleSheetHeader extends StatelessWidget {
  const PeopleSheetHeader({
    super.key,
    required this.label,
    required this.title,
    this.body,
    this.icon = SkyIcons.heart,
    this.tone = SkyTone.rose,
  });

  final String label;
  final String title;
  final String? body;
  final SkyIcons icon;
  final SkyTone tone;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SkyLabel(label, icon: icon, tone: tone, center: true),
        const SizedBox(height: SkySpace.sm),
        Semantics(
          header: true,
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: SkyType.serif(28, weight: FontWeight.w500, height: 1.15).copyWith(color: t.title),
          ),
        ),
        if (body != null) ...[
          const SizedBox(height: SkySpace.sm),
          Text(
            body!,
            textAlign: TextAlign.center,
            style: SkyType.sans(13.5, height: 1.45).copyWith(color: t.muted),
          ),
        ],
      ],
    );
  }
}

class PeopleSheetItem extends StatelessWidget {
  const PeopleSheetItem({super.key, required this.index, required this.child, this.gap = SkySpace.md});

  final int index;
  final Widget child;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: index == 0 ? 0 : gap),
      child: SkyEntrance(index: index, child: child),
    );
  }
}

List<Widget> peopleSheetItems(List<(String, double, Widget)> entries) {
  return [
    for (var i = 0; i < entries.length; i++)
      PeopleSheetItem(
        key: ValueKey<String>('people-${entries[i].$1}'),
        index: i,
        gap: entries[i].$2,
        child: entries[i].$3,
      ),
  ];
}

class PeopleSetupError extends StatelessWidget {
  const PeopleSetupError(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return SkyNotice(text: text, tone: SkyNoticeTone.error);
  }
}

class PeopleTextLink extends StatelessWidget {
  const PeopleTextLink({
    super.key,
    required this.label,
    required this.onTap,
    this.color,
    this.underline = false,
    this.enabled = true,
    this.size = 12.5,
    this.align = TextAlign.center,
  });

  final String label;
  final VoidCallback onTap;
  final Color? color;
  final bool underline;
  final bool enabled;
  final double size;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final ink = color ?? t.muted;
    return SkyPressable(
      onTap: onTap,
      enabled: enabled,
      haptic: false,
      semanticLabel: label,
      excludeSemantics: true,
      child: AnimatedOpacity(
        opacity: enabled ? 1 : 0.45,
        duration: skyMotionAllowed(context) ? SkyMotion.fast : Duration.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            label,
            textAlign: align,
            style: SkyType.sans(size, weight: FontWeight.w600).copyWith(
              color: ink,
              decoration: underline ? TextDecoration.underline : null,
              decorationColor: ink.withValues(alpha: 0.5),
            ),
          ),
        ),
      ),
    );
  }
}
