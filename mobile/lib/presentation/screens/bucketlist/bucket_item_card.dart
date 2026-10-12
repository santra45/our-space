import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/engine.dart';
import '../../widgets/our_widgets.dart';
import 'bucket_copy.dart';

const Duration _cssTransition = Duration(milliseconds: 150);
const Curve _cssEase = Cubic(0.4, 0, 0.2, 1);

final List<OurOption<String>> bucketOptions = [
  for (final option in bucketCategoryOptions) OurOption(option.value, option.label),
];

class BucketItemCard extends StatelessWidget {
  const BucketItemCard({
    super.key,
    required this.item,
    required this.editing,
    required this.editController,
    required this.editCategory,
    required this.onEditCategory,
    required this.onToggle,
    required this.onStartEdit,
    required this.onCancelEdit,
    required this.onSaveEdit,
    required this.onDelete,
  });

  final BucketListRecord item;
  final bool editing;
  final TextEditingController editController;
  final String editCategory;
  final ValueChanged<String> onEditCategory;
  final VoidCallback onToggle;
  final VoidCallback onStartEdit;
  final VoidCallback onCancelEdit;
  final VoidCallback onSaveEdit;
  final VoidCallback onDelete;

  BoxDecoration get _decoration {
    final radius = AppRadii.all(AppRadii.x2l);
    if (editing) {
      return BoxDecoration(
        color: AppColors.white,
        border: Border.all(color: AppColors.blush300),
        borderRadius: radius,
        boxShadow: AppShadows.md,
      );
    }
    if (item.completed) {
      return BoxDecoration(
        color: AppColors.matcha50.withValues(alpha: 0.7),
        border: Border.all(color: AppColors.matcha200.withValues(alpha: 0.8)),
        borderRadius: radius,
      );
    }
    return BoxDecoration(
      color: AppColors.white.withValues(alpha: 0.8),
      border: Border.all(color: AppColors.blush100),
      borderRadius: radius,
    );
  }

  @override
  Widget build(BuildContext context) {
    final card = AnimatedContainer(
      duration: _cssTransition,
      curve: _cssEase,
      padding: const EdgeInsets.all(14),
      decoration: _decoration,
      clipBehavior: Clip.antiAlias,
      child: editing ? _editForm() : _row(context),
    );
    if (editing) return card;
    return Semantics(
      button: true,
      toggled: item.completed,
      child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onToggle, child: card),
    );
  }

  Widget _row(BuildContext context) {
    final ambient = DefaultTextStyle.of(context).style;
    final completed = item.completed;
    final category = item.fields['category'];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(padding: const EdgeInsets.only(top: 2), child: _checkbox(completed)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedDefaultTextStyle(
                        duration: _cssTransition,
                        curve: _cssEase,
                        style: ambient.merge(
                          completed
                              ? Tw.xs.semibold.snug.lineThrough.c(AppColors.slate400)
                              : Tw.xs.semibold.snug.c(AppColors.slate700),
                        ),
                        child: Text(breakAnywhere(item.text), semanticsLabel: item.text),
                      ),
                      const SizedBox(height: 4),
                      if (category is String && category.isNotEmpty)
                        Text(category, style: Tw.px10.medium.c(AppColors.slate400)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (completed) ...[
                const CompletedStamp(),
                const SizedBox(width: 8),
              ],
              OurIconButton(
                icon: AppIcons.pencil,
                haptic: false,
                semanticLabel: 'Edit dream',
                onPressed: onStartEdit,
              ),
              const SizedBox(width: 4),
              OurIconButton(
                icon: AppIcons.trash2,
                haptic: false,
                semanticLabel: 'Delete dream',
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _checkbox(bool completed) {
    return AnimatedContainer(
      duration: _cssTransition,
      curve: _cssEase,
      width: 24,
      height: 24,
      decoration: completed
          ? BoxDecoration(
              color: AppColors.matcha300,
              borderRadius: AppRadii.all(AppRadii.xl),
              boxShadow: AppShadows.sm,
            )
          : BoxDecoration(
              color: AppColors.white,
              border: Border.all(color: AppColors.blush300, width: 2),
              borderRadius: AppRadii.all(AppRadii.xl),
            ),
      child: completed
          ? const Center(
              child: LucideIcon(AppIcons.check, size: 14, strokeWidth: 3, color: AppColors.emerald900),
            )
          : null,
    );
  }

  Widget _editForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(BucketCopy.editLabel, style: Tw.px11.semibold.c(AppColors.slate600)),
        ),
        OurTextField(
          controller: editController,
          hint: BucketCopy.hint,
          minLines: 2,
          maxLines: 2,
          autofocus: true,
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
          semanticLabel: BucketCopy.editLabel,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Flexible(
              child: Align(
                alignment: Alignment.centerLeft,
                child: OurSelectField<String>(
                  value: editCategory,
                  options: bucketOptions,
                  onChanged: onEditCategory,
                  style: OurFieldStyle.form.copyWith(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                  semanticLabel: 'Category',
                ),
              ),
            ),
            const SizedBox(width: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  button: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onCancelEdit,
                    child: CssBox(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      border: Border.all(color: AppColors.slate200),
                      borderRadius: AppRadii.all(AppRadii.xl),
                      child: Text(BucketCopy.cancel, style: Tw.xs.medium.c(AppColors.slate500)),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                BouncyButton(label: BucketCopy.save, small: true, onPressed: onSaveEdit),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

abstract final class CompletedStampFrames {
  static const double restRotation = -8;
  static const double restOpacity = 0.85;
  static const (double, double, double) rest = (1, restRotation, restOpacity);

  static (double scale, double degrees, double opacity) at(double seconds) {
    final scale = AppMotion.springValue(AppMotion.framerScaleSpring, 2, 1, seconds);
    final degrees = AppMotion.springValue(AppMotion.framerPositionSpring, -20, restRotation, seconds);
    final opacity = restOpacity * AppMotion.framerEase.transform((seconds / 0.3).clamp(0.0, 1.0));
    return (scale, degrees, opacity);
  }
}

class CompletedStamp extends StatefulWidget {
  const CompletedStamp({super.key});

  @override
  State<CompletedStamp> createState() => _CompletedStampState();
}

class _CompletedStampState extends State<CompletedStamp> with SingleTickerProviderStateMixin {
  static const Duration _length = Duration(milliseconds: 1000);

  late final AnimationController _clock = AnimationController(vsync: this, duration: _length);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!motionAllowed(context)) {
      _clock.stop();
      _clock.value = 1;
    } else if (_clock.value == 0 && !_clock.isAnimating) {
      _clock.forward();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stamp = IgnorePointer(
      child: CssBox(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        border: Border.all(color: AppColors.emerald600, width: 2),
        borderRadius: AppRadii.all(AppRadii.md),
        child: Text(BucketCopy.completed, style: Tw.px10.black.trackingWider.c(AppColors.emerald700)),
      ),
    );
    return AnimatedBuilder(
      animation: _clock,
      child: stamp,
      builder: (context, child) {
        final (scale, degrees, opacity) = _clock.value >= 1
            ? CompletedStampFrames.rest
            : CompletedStampFrames.at(_clock.value * _length.inMicroseconds / 1e6);
        return Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Transform.rotate(
            angle: degrees * math.pi / 180,
            child: Transform.scale(scale: scale, child: child),
          ),
        );
      },
    );
  }
}
