import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/engine.dart';
import '../../widgets/our_widgets.dart';
import 'capsule_copy.dart';
import 'spring_entrance.dart';

class LetterEnvelope extends StatefulWidget {
  const LetterEnvelope({
    super.key,
    required this.letter,
    required this.content,
    required this.onClose,
    this.onOpened,
    this.onDelete,
  });

  final LetterRecord letter;
  final String content;
  final VoidCallback onClose;
  final VoidCallback? onOpened;
  final Future<void> Function()? onDelete;

  @override
  State<LetterEnvelope> createState() => _LetterEnvelopeState();
}

class _LetterEnvelopeState extends State<LetterEnvelope> {
  static const double _closeLift = 48;

  bool _isOpen = false;
  bool _reportedOpen = false;
  Timer? _celebrate;

  bool get _wasTimeLocked => widget.letter.lockDate != null;

  String get _writtenOn => prettyTimestamp(widget.letter.writtenAt);

  @override
  void dispose() {
    _celebrate?.cancel();
    super.dispose();
  }

  void _openEnvelope() {
    if (_isOpen) return;
    AppHaptics.tap();
    setState(() => _isOpen = true);
    if (!_reportedOpen) {
      _reportedOpen = true;
      widget.onOpened?.call();
    }
    _celebrate = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      AppHaptics.celebration();
      fireHeartConfetti(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: AppLayout.maxWidthSm),
      child: Material(
        type: MaterialType.transparency,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final room = constraints.maxHeight.isFinite ? constraints.maxHeight - _closeLift * 2 : screenHeight;
            final letterHeight = math.max(120.0, math.min(screenHeight * 0.8, room));
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: _closeLift),
                  child: _isOpen
                      ? SpringEntrance(
                          key: const ValueKey('open'),
                          spec: EntranceSpec.openLetter,
                          child: _openLetter(letterHeight),
                        )
                      : SpringEntrance(
                          key: const ValueKey('sealed'),
                          spec: EntranceSpec.sealedEnvelope,
                          child: PressScale(onTap: _openEnvelope, child: _sealedEnvelope()),
                        ),
                ),
                Positioned(
                  top: 0,
                  right: 0,
                  child: OurCloseButton(
                    onPressed: widget.onClose,
                    background: AppColors.white.withValues(alpha: 0.8),
                    foreground: AppColors.slate600,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _sealedEnvelope() {
    return Semantics(
      button: true,
      child: CssBox(
        padding: const EdgeInsets.all(24),
        gradient: AppGradients.envelope,
        border: Border.all(color: AppColors.blush200, width: 2),
        borderRadius: AppRadii.all(AppRadii.x3l),
        shadows: AppShadows.x2l,
        clipContent: true,
        child: SizedBox(
          width: double.infinity,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CssBox(
                width: 96,
                height: 96,
                color: AppColors.blush200.withValues(alpha: 0.5),
                borderRadius: AppRadii.all(AppRadii.full),
                child: Center(
                  child: OurIconCircle(
                    icon: AppIcons.heart,
                    size: 56,
                    iconSize: 28,
                    background: AppColors.rose500,
                    foreground: AppColors.white,
                    iconFill: AppColors.white,
                    border: Border.all(color: AppColors.white.withValues(alpha: 0.6), width: 2),
                    shadows: AppShadows.tinted(AppShadows.lg, AppColors.rose400.withValues(alpha: 0.4)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                widget.letter.title,
                textAlign: TextAlign.center,
                style: Tw.xl.black.trackingTight.c(AppColors.slate800),
              ),
              const SizedBox(height: 4),
              Text(
                'A private letter written on $_writtenOn',
                textAlign: TextAlign.center,
                style: Tw.xs.c(AppColors.slate500),
              ),
              const SizedBox(height: 20),
              if (_wasTimeLocked) ...[
                OurPill(
                  label: 'Time lock lifted on ${formatDatePretty(widget.letter.lockDate)}',
                  icon: AppIcons.lock,
                  iconSize: 12,
                  gap: 6,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  background: AppColors.white.withValues(alpha: 0.7),
                  foreground: AppColors.slate500,
                  border: AppColors.slate200,
                  textStyle: Tw.px11,
                ),
                const SizedBox(height: 16),
              ],
              TwPulse(
                child: OurPill(
                  label: 'Tap to Break Wax Seal',
                  icon: AppIcons.sparkles,
                  iconSize: 14,
                  gap: 8,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  background: AppColors.blush500,
                  foreground: AppColors.white,
                  textStyle: Tw.xs.bold,
                  shadows: AppShadows.tinted(AppShadows.md, AppColors.blush300),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _openLetter(double maxHeight) {
    return CssBox(
      color: AppColors.letterPaper,
      border: Border.all(color: AppColors.amber100),
      borderRadius: AppRadii.all(AppRadii.x3l),
      shadows: AppShadows.x2l,
      clipContent: true,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.blush200.withValues(alpha: 0.7))),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Secret Love Letter'.toUpperCase(),
                            style: Tw.px10.bold.trackingWidest.c(AppColors.blush500),
                          ),
                          Text(widget.letter.title, style: Tw.xl.bold.c(AppColors.slate800)),
                        ],
                      ),
                    ),
                    const LucideIcon(AppIcons.heart, size: 20, color: AppColors.blush400, fill: AppColors.blush200),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(widget.content, style: Tw.x2l.handwriting.relaxed.c(AppColors.slate800)),
              ),
              if (_wasTimeLocked) ...[
                const SizedBox(height: 20),
                CssBox(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  color: AppColors.slate50,
                  border: Border.all(color: AppColors.slate200),
                  borderRadius: AppRadii.all(AppRadii.x2l),
                  child: Text(
                    'This one was sealed until ${formatDatePretty(widget.letter.lockDate)} 💕 The app would not open it early — though it was always a promise, not a padlock.',
                    style: Tw.px10.relaxed.c(AppColors.slate400),
                  ),
                ),
              ],
              Container(
                margin: const EdgeInsets.only(top: 24),
                padding: const EdgeInsets.only(top: 16),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: AppColors.amber200.withValues(alpha: 0.5))),
                ),
                child: DefaultTextStyle.merge(
                  style: Tw.xs.c(AppColors.slate400),
                  child: Row(
                    children: [
                      const Expanded(child: Text('With all my love forever 💕')),
                      const SizedBox(width: 8),
                      Text(_writtenOn),
                      if (widget.onDelete != null) ...[
                        const SizedBox(width: 12),
                        _deleteButton(),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _deleteButton() {
    return Semantics(
      button: true,
      label: 'Delete letter',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onDelete!(),
        child: CssBox(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          borderRadius: AppRadii.all(AppRadii.lg),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const LucideIcon(AppIcons.trash2, size: 14, color: AppColors.slate400),
              const SizedBox(width: 4),
              Text('Delete', style: Tw.xs.c(AppColors.slate400)),
            ],
          ),
        ),
      ),
    );
  }
}
