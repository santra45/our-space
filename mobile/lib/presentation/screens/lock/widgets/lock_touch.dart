import 'package:flutter/material.dart';

import '../../../sky/sky.dart';
import 'lock_sky.dart';

class LockTouchButton extends StatefulWidget {
  const LockTouchButton({super.key, required this.label, required this.onTap, this.busy = false, this.busyLabel});

  final String label;
  final VoidCallback? onTap;
  final bool busy;
  final String? busyLabel;

  bool get enabled => onTap != null && !busy;

  @override
  State<LockTouchButton> createState() => _LockTouchButtonState();
}

class _LockTouchButtonState extends State<LockTouchButton> with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(vsync: this, duration: SkyMotion.twinkle);
  bool _motion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final motion = skyMotionAllowed(context);
    if (motion == _motion) return;
    _motion = motion;
    if (motion) {
      _breath.repeat(reverse: true);
    } else {
      _breath
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final shown = widget.busy ? (widget.busyLabel ?? widget.label) : widget.label;
    const ring = LockMetrics.ring;
    const reach = LockMetrics.ringReach;
    final face = t.isNight
        ? const BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              center: Alignment(0, -0.2),
              radius: 0.75,
              colors: [Color(0xFF2A2560), Color(0xFF141238)],
            ),
            boxShadow: [
              BoxShadow(color: Color(0xCCFFD98A), spreadRadius: 1.5),
              BoxShadow(color: Color(0x47FFD98A), blurRadius: 33),
            ],
          )
        : const BoxDecoration(
            shape: BoxShape.circle,
            color: SkyTokens.white,
            boxShadow: [
              BoxShadow(color: Color(0x402B2A6B), spreadRadius: 1.5),
              BoxShadow(color: Color(0x2E2B2A6B), offset: Offset(0, 18), blurRadius: 33),
            ],
          );
    final iconColor = t.isNight ? const Color(0xFFFFD98A) : SkyTokens.indigo;
    final halo = AnimatedBuilder(
      animation: _breath,
      builder: (context, _) {
        final b = Curves.easeInOut.transform(_breath.value);
        return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            _HaloRing(diameter: (ring + reach * 2) * (1 + 0.035 * b), color: t.gold, opacity: 0.10 + 0.05 * b),
            _HaloRing(diameter: (ring + 36) * (1 + 0.02 * b), color: t.gold, opacity: 0.22 + 0.06 * b),
          ],
        );
      },
    );
    const haloBox = ring + reach * 2 + 12;
    final ringFace = SizedBox(
      width: ring,
      height: ring,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: OverflowBox(
              maxWidth: haloBox,
              maxHeight: haloBox,
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: SizedBox(width: haloBox, height: haloBox, child: halo),
                ),
              ),
            ),
          ),
          Container(
            width: ring,
            height: ring,
            decoration: face,
            alignment: Alignment.center,
            child: SkyIcon(SkyIcons.finger, size: 50, color: iconColor),
          ),
          if (widget.busy)
            Positioned.fill(
              child: OverflowBox(
                maxWidth: ring + 10,
                maxHeight: ring + 10,
                child: SizedBox(
                  width: ring + 10,
                  height: ring + 10,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.6,
                    color: t.gold,
                    backgroundColor: const Color(0x00000000),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    return Center(
      child: SkyPressable(
        onTap: widget.enabled ? widget.onTap : null,
        enabled: widget.enabled,
        semanticLabel: shown,
        excludeSemantics: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ringFace,
            const SizedBox(height: 30),
            AnimatedSwitcher(
              duration: skyMotionAllowed(context) ? SkyMotion.fast : Duration.zero,
              child: Text(
                shown,
                key: ValueKey<String>(shown),
                textAlign: TextAlign.center,
                style: SkyType.serif(21, weight: FontWeight.w500, height: 1.2).copyWith(color: t.title),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HaloRing extends StatelessWidget {
  const _HaloRing({required this.diameter, required this.color, required this.opacity});

  final double diameter;
  final Color color;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: opacity.clamp(0.0, 1.0))),
      ),
    );
  }
}
