import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/engine.dart';
import '../../space_scope.dart';
import '../../widgets/our_widgets.dart';
import 'roulette_copy.dart';
import 'scratch_card.dart';

const Map<String, LucideIconData> dateIdeaCategoryIcons = {
  'all': AppIcons.sparkles,
  'athome': AppIcons.home,
  'outdoor': AppIcons.trees,
  'food': AppIcons.utensils,
  'budget': AppIcons.piggyBank,
};

class DateRoulette extends StatefulWidget {
  const DateRoulette({super.key});

  static math.Random random = math.Random();

  @override
  State<DateRoulette> createState() => _DateRouletteState();
}

class _DateRouletteState extends State<DateRoulette> {
  StreamSubscription<RouletteStateRecord?>? _subscription;
  String _category = 'all';
  DateIdea _idea = defaultDateIdeas.first;
  bool _revealed = false;
  bool _revealedLatch = false;
  int _cardKey = 0;
  int _appliedAt = 0;
  int _persisting = 0;
  bool _hasDeferred = false;
  RouletteStateRecord? _deferred;

  @override
  void initState() {
    super.initState();
    _subscription = context.space.roulette.watch().listen(_onStored);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _onStored(RouletteStateRecord? record) {
    if (!mounted) return;
    if (_persisting > 0) {
      _deferred = record;
      _hasDeferred = true;
      return;
    }
    _adopt(record);
  }

  void _adopt(RouletteStateRecord? record) {
    if (record == null || record.deleted) return;
    if (record.updatedAt <= _appliedAt) return;
    _appliedAt = record.updatedAt;
    final idea = findDateIdea(record.ideaId);
    if (idea == null) return;
    final revealed = record.revealed;
    _revealedLatch = revealed;
    setState(() {
      _idea = idea;
      final category = record.category;
      if (category != null && isDateIdeaCategory(category)) _category = category;
      _revealed = revealed;
      _cardKey++;
    });
  }

  Future<void> _persist({required String ideaId, required String category, required bool revealed}) async {
    _persisting++;
    try {
      final row = await context.space.roulette.persist(ideaId: ideaId, category: category, revealed: revealed);
      final at = readInt(row?['updatedAt']);
      if (at != null && at > _appliedAt) _appliedAt = at;
    } catch (_) {
    } finally {
      _persisting--;
      if (_persisting == 0 && _hasDeferred) {
        final record = _deferred;
        _deferred = null;
        _hasDeferred = false;
        if (mounted) _adopt(record);
      }
    }
  }

  void _pick([String? categoryId]) {
    final category = categoryId ?? _category;
    AppHaptics.tap();
    final pool = dateIdeasIn(category);
    if (pool.isEmpty) return;
    final available = pool.length > 1 ? pool.where((idea) => idea.id != _idea.id).toList() : pool;
    final picked = available.isEmpty ? pool.first : available[DateRoulette.random.nextInt(available.length)];
    _revealedLatch = false;
    setState(() {
      _idea = picked;
      _revealed = false;
      _cardKey++;
    });
    unawaited(_persist(ideaId: picked.id, category: category, revealed: false));
  }

  void _selectCategory(String id) {
    setState(() => _category = id);
    _pick(id);
  }

  void _onRevealed() {
    if (_revealedLatch) return;
    _revealedLatch = true;
    setState(() => _revealed = true);
    AppHaptics.celebration();
    fireHeartConfetti(context);
    unawaited(_persist(ideaId: _idea.id, category: _category, revealed: true));
  }

  Widget _categories() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: math.max(0, constraints.maxWidth - 16)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < dateIdeaCategories.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  OurChip(
                    label: dateIdeaCategories[i].label,
                    icon: dateIdeaCategoryIcons[dateIdeaCategories[i].id],
                    selected: _category == dateIdeaCategories[i].id,
                    onTap: () => _selectCategory(dateIdeaCategories[i].id),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _card() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppLayout.maxWidthSm),
        child: AspectRatio(
          aspectRatio: 4 / 3,
          child: CssBox(
            gradient: AppGradients.scratchCard,
            border: Border.all(color: AppColors.white, width: 4),
            borderRadius: AppRadii.all(AppRadii.x3l),
            shadows: AppShadows.x2l,
            child: ClipRRect(
              borderRadius: AppRadii.all(AppRadii.x3l - 4),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: OverflowBox(
                      minHeight: 0,
                      maxHeight: double.infinity,
                      alignment: Alignment.center,
                      child: DateIdeaReveal(key: ValueKey<String>(_idea.id), idea: _idea),
                    ),
                  ),
                  Positioned.fill(
                    child: ScratchCard(
                      key: ValueKey<int>(_cardKey),
                      revealed: _revealed,
                      onRevealed: _onRevealed,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return OurPage(
      children: [
        const OurSectionHeader(
          title: RouletteCopy.title,
          subtitle: RouletteCopy.subtitle,
          centered: true,
        ),
        _categories(),
        _card(),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Center(
            child: BouncyButton(
              onPressed: () => _pick(),
              icon: AppIcons.refreshCw,
              label: RouletteCopy.rollAnother,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              gap: 8,
            ),
          ),
        ),
      ],
    );
  }
}

class DateIdeaReveal extends StatefulWidget {
  const DateIdeaReveal({super.key, required this.idea});

  final DateIdea idea;

  @override
  State<DateIdeaReveal> createState() => _DateIdeaRevealState();
}

class _DateIdeaRevealState extends State<DateIdeaReveal> with SingleTickerProviderStateMixin {
  static const Duration _length = Duration(milliseconds: 600);

  late final AnimationController _controller = AnimationController(vsync: this, duration: _length);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller.isAnimating || _controller.value > 0) return;
    if (motionAllowed(context)) {
      _controller.forward();
    } else {
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final idea = widget.idea;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: spaced([
        Center(
          child: OurPill(
            label: RouletteCopy.dateIdea.toUpperCase(),
            icon: AppIcons.heart,
            iconSize: 12,
            iconColor: AppColors.slate800,
            iconFill: AppColors.blush600,
            background: AppColors.blush200.withValues(alpha: 0.6),
            foreground: AppColors.slate800,
            textStyle: Tw.px11.bold.trackingWider,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(idea.title, textAlign: TextAlign.center, style: Tw.lg.black.snug.c(AppColors.slate800)),
        ),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppLayout.maxWidthXs),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(idea.desc, textAlign: TextAlign.center, style: Tw.xs.relaxed.c(AppColors.slate600)),
            ),
          ),
        ),
      ], 8),
    );

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final seconds = _controller.value * _length.inMicroseconds / 1e6;
        final opacity = _controller.value >= 1
            ? 1.0
            : AppMotion.framerEase.transform((seconds / 0.3).clamp(0.0, 1.0));
        final scale = _controller.value >= 1
            ? 1.0
            : AppMotion.springValue(AppMotion.framerScaleSpring, 0.96, 1, seconds);
        return Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Transform.scale(scale: scale, child: child),
        );
      },
      child: content,
    );
  }
}
