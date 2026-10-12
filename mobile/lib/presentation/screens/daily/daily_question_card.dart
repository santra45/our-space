import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../../core/engine.dart';
import '../../space_scope.dart';
import '../../widgets/our_widgets.dart';
import 'daily_copy.dart';
import 'daily_question_model.dart';
import 'daily_question_sheet.dart';

class DailyQuestionCard extends StatefulWidget {
  const DailyQuestionCard({super.key});

  @override
  State<DailyQuestionCard> createState() => _DailyQuestionCardState();
}

class _DailyQuestionCardState extends State<DailyQuestionCard> {
  late final DailyQuestionModel _model = DailyQuestionModel(context.space);
  bool _open = false;

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  void _celebrate() {
    AppHaptics.celebration();
    if (mounted) fireHeartConfetti(context);
  }

  Future<void> _openSheet() async {
    if (_open) return;
    AppHaptics.tap();
    _open = true;
    _model.resetSheet();
    await showOurSheet<void>(
      context: context,
      builder: (_) => DailyQuestionSheet(model: _model, onCelebrate: _celebrate),
    );
    _open = false;
  }

  @override
  Widget build(BuildContext context) {
    final vault = context.watch<VaultService>();
    final identity = context.watch<IdentityController>();
    final personId = identity.myOwnerId;
    _model.bind(
      key: vault.key,
      ownerId: personId == null || personId.isEmpty ? context.space.device.deviceId : personId,
      ownerIds: identity.myOwnerIds,
    );

    return ListenableBuilder(
      listenable: _model,
      builder: (context, _) {
        final today = _model.today;
        if (!_model.visible || today == null) return const SizedBox.shrink();
        return DailyQuestionTeaser(
          question: today.question.text,
          bothIn: _model.bothIn,
          status: DailyCopy.status(
            bothIn: _model.bothIn,
            answered: _model.answered,
            partnerWaiting: _model.partnerWaiting,
            partnerName: identity.partnerName,
            partnerPossessive: identity.partnerPossessive,
            partnerGrammar: identity.partnerGrammar,
          ),
          onTap: _openSheet,
        );
      },
    );
  }
}

class DailyQuestionTeaser extends StatelessWidget {
  const DailyQuestionTeaser({
    super.key,
    required this.question,
    required this.status,
    required this.bothIn,
    required this.onTap,
  });

  final String question;
  final String status;
  final bool bothIn;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      child: CssBox(
        padding: const EdgeInsets.all(16),
        color: AppColors.white.withValues(alpha: 0.8),
        border: Border.all(color: AppColors.lavender200),
        borderRadius: AppRadii.all(AppRadii.x3l),
        shadows: AppShadows.sm,
        backdropBlur: 4,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const LucideIcon(AppIcons.messageCircleHeart, size: 16, color: AppColors.lavender400),
                const SizedBox(width: 8),
                Text(
                  DailyCopy.heading.toUpperCase(),
                  style: Tw.px11.bold.trackingWide.c(AppColors.lavender500),
                ),
                if (bothIn) ...[
                  const Spacer(),
                  const LucideIcon(AppIcons.check, size: 14, color: AppColors.emerald500),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Text(question, style: Tw.xl.handwriting.snug.c(AppColors.slate800)),
            const SizedBox(height: 8),
            Text(status, style: Tw.px11.c(AppColors.slate500)),
          ],
        ),
      ),
    );
  }
}

class PressScale extends StatefulWidget {
  const PressScale({
    super.key,
    required this.child,
    required this.onTap,
    this.pressedScale = 0.98,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;
  final String? semanticLabel;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> with SingleTickerProviderStateMixin {
  late final AnimationController _scale = AnimationController.unbounded(vsync: this, value: 1);

  void _springTo(double target) {
    if (!motionAllowed(context)) {
      _scale.value = 1;
      return;
    }
    _scale.animateWith(SpringSimulation(AppMotion.framerScaleSpring, _scale.value, target, _scale.velocity));
  }

  @override
  void dispose() {
    _scale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _springTo(widget.pressedScale),
        onTapUp: (_) => _springTo(1),
        onTapCancel: () => _springTo(1),
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _scale,
          builder: (context, child) => Transform.scale(scale: _scale.value, child: child),
          child: widget.child,
        ),
      ),
    );
  }
}
