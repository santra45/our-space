import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../../core/engine.dart';
import '../../space_scope.dart';
import '../../widgets/our_widgets.dart';
import 'live_love_counter.dart';
import 'milestone_copy.dart';

class TogetherCard extends StatefulWidget {
  const TogetherCard({super.key, required this.startDate, required this.duration});

  final String startDate;
  final LoveDuration duration;

  @override
  State<TogetherCard> createState() => _TogetherCardState();
}

class _TogetherCardState extends State<TogetherCard> {
  bool _editing = false;
  late String _newDate = widget.startDate;
  bool _sending = false;
  Timer? _sendingReset;

  @override
  void didUpdateWidget(covariant TogetherCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startDate != widget.startDate && widget.startDate.isNotEmpty) {
      _newDate = widget.startDate;
    }
  }

  @override
  void dispose() {
    _sendingReset?.cancel();
    super.dispose();
  }

  Future<void> _saveStartDate() async {
    final vault = context.read<VaultService>();
    final notices = context.read<AppNotices>();
    final result = await vault.updateSettings(startDate: _newDate);
    final error = result.error;
    if (!result.ok && error != null) notices.showVaultWarning(error);
    if (!mounted) return;
    setState(() => _editing = false);
    AppHaptics.celebration();
  }

  Future<void> _sendBurst() async {
    AppHaptics.celebration();
    fireCelebrationBurst(context);
    if (_sending) return;
    final sync = context.read<SyncService>();
    setState(() => _sending = true);
    try {
      await sync.sendLoveBurst();
    } finally {
      _sendingReset?.cancel();
      _sendingReset = Timer(const Duration(seconds: 1), () {
        if (mounted) setState(() => _sending = false);
      });
    }
  }

  Widget _heading() {
    const heart = LucideIcon(AppIcons.heart, size: 14, color: AppColors.blush500, fill: AppColors.blush400);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        heart,
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            MilestoneCopy.together.toUpperCase(),
            textAlign: TextAlign.center,
            style: Tw.xs.semibold.trackingWidest.c(AppColors.blush500),
          ),
        ),
        const SizedBox(width: 6),
        heart,
      ],
    );
  }

  Widget _days() {
    final daysStyle = Tw.x6l.black.trackingTight.c(AppColors.slate800);
    return DaysPop(
      key: ValueKey<int>(widget.duration.totalDays),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Flexible(child: Text('${widget.duration.totalDays}', style: daysStyle)),
          const SizedBox(width: 8),
          Text(
            MilestoneCopy.days,
            style: Tw.x2l.bold.c(AppColors.blush500).copyWith(letterSpacing: daysStyle.letterSpacing),
          ),
        ],
      ),
    );
  }

  Widget _clock() {
    final duration = widget.duration;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 260),
        child: Row(
          children: [
            Expanded(
              child: TimeCell(
                value: twoDigitCount(duration.hours),
                label: MilestoneCopy.hours,
                valueStyle: Tw.lg.bold.tight.c(AppColors.slate700),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TimeCell(
                value: twoDigitCount(duration.minutes),
                label: MilestoneCopy.minutes,
                valueStyle: Tw.lg.bold.tight.c(AppColors.slate700),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TimeCell(
                value: twoDigitCount(duration.seconds),
                label: MilestoneCopy.seconds,
                valueStyle: Tw.lg.bold.tight.mono.c(AppColors.blush600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _since() {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 24),
      child: Center(
        child: Semantics(
          button: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              AppHaptics.tap();
              setState(() => _editing = true);
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const LucideIcon(AppIcons.calendar, size: 14, color: AppColors.blush400),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    MilestoneCopy.since(formatDatePretty(widget.startDate)),
                    textAlign: TextAlign.center,
                    style: Tw.xs.medium.c(AppColors.slate500),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dateEditor() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppLayout.maxWidthXs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: OurDateField(
                value: parseLocalDate(_newDate),
                onChanged: (date) => setState(() => _newDate = toLocalDateInput(date)),
                style: OurFieldStyle.form.copyWith(
                  border: AppColors.blush300,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                ),
              ),
            ),
            const SizedBox(width: 8),
            BouncyButton(small: true, label: MilestoneCopy.save, onPressed: () => unawaited(_saveStartDate())),
            const SizedBox(width: 8),
            Semantics(
              button: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _editing = false),
                child: Text(MilestoneCopy.cancel, style: Tw.xs.c(AppColors.slate400)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _burst() {
    return CssBox(
      padding: const EdgeInsets.only(top: 16),
      border: Border(top: BorderSide(color: AppColors.blush100.withValues(alpha: 0.7))),
      child: Center(
        child: BouncyButton(
          variant: BouncyVariant.secondary,
          small: true,
          pill: true,
          enabled: !_sending,
          label: _sending ? MilestoneCopy.sendingBurst : MilestoneCopy.sendBurst,
          onPressed: () => unawaited(_sendBurst()),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      clipContent: true,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _heading(),
              const SizedBox(height: 8),
              _days(),
              const SizedBox(height: 12),
              _clock(),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _editing ? _dateEditor() : _since(),
              ),
              const SizedBox(height: 16),
              _burst(),
            ],
          ),
          Positioned(
            top: -60,
            right: -60,
            child: SoftGlow(color: AppColors.blush200.withValues(alpha: 0.4)),
          ),
          Positioned(
            bottom: -60,
            left: -60,
            child: SoftGlow(color: AppColors.lavender200.withValues(alpha: 0.4)),
          ),
        ],
      ),
    );
  }
}

class TimeCell extends StatelessWidget {
  const TimeCell({super.key, required this.value, required this.label, required this.valueStyle});

  static const StrutStyle bodyStrut = StrutStyle(
    fontSize: 16,
    height: 1.5,
    leadingDistribution: TextLeadingDistribution.even,
  );

  final String value;
  final String label;
  final TextStyle valueStyle;

  @override
  Widget build(BuildContext context) {
    return CssBox(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      color: AppColors.white.withValues(alpha: 0.7),
      border: Border.all(color: AppColors.blush100),
      borderRadius: AppRadii.all(AppRadii.x2l),
      shadows: AppShadows.sm,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, textAlign: TextAlign.center, style: valueStyle),
          Text(
            label.toUpperCase(),
            textAlign: TextAlign.center,
            style: Tw.px10.semibold.c(AppColors.slate400),
            strutStyle: bodyStrut,
          ),
        ],
      ),
    );
  }
}

class SoftGlow extends StatelessWidget {
  const SoftGlow({super.key, required this.color, this.size = 144, this.blur = 40});

  final Color color;
  final double size;
  final double blur;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _GlowPainter(color: color, blur: blur)),
      ),
    );
  }
}

class _GlowPainter extends CustomPainter {
  const _GlowPainter({required this.color, required this.blur});

  final Color color;
  final double blur;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(
      size.center(Offset.zero),
      size.shortestSide / 2,
      Paint()
        ..color = color
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur),
    );
  }

  @override
  bool shouldRepaint(_GlowPainter oldDelegate) => oldDelegate.color != color || oldDelegate.blur != blur;
}

class DaysPop extends StatefulWidget {
  const DaysPop({super.key, required this.child});

  final Widget child;

  @override
  State<DaysPop> createState() => _DaysPopState();
}

class _DaysPopState extends State<DaysPop> with SingleTickerProviderStateMixin {
  static const Duration _length = Duration(milliseconds: 900);

  late final AnimationController _clock = AnimationController(vsync: this, duration: _length);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (motionAllowed(context)) {
      unawaited(_clock.forward());
    } else {
      _clock.value = 1;
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _clock,
      child: widget.child,
      builder: (context, child) {
        if (_clock.isCompleted) return child!;
        final seconds = _clock.value * _length.inMicroseconds / 1e6;
        final opacity = AppMotion.framerEase.transform((seconds / 0.3).clamp(0.0, 1.0));
        final scale = AppMotion.springValue(AppMotion.framerScaleSpring, 0.9, 1, seconds);
        return Opacity(opacity: opacity, child: Transform.scale(scale: scale, child: child));
      },
    );
  }
}
