import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/engine.dart';
import '../../sky/sky.dart';
import '../../space_scope.dart';
import '../../widgets/app_haptics.dart';
import '../../widgets/confetti_burst.dart';
import '../us/us_keys.dart';
import 'roulette_copy.dart';
import 'scratch_card.dart';

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

  @override
  Widget build(BuildContext context) {
    final night = context.sky.isNight;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SkySectionHeader(title: RouletteCopy.title, action: RouletteCopy.anotherIdea, onAction: () => _pick()),
        const SizedBox(height: 10),
        ScratchPanel(
          key: UsKeys.scratchPanel,
          title: night ? RouletteCopy.tonight : RouletteCopy.weekend,
          subtitle: _revealed ? RouletteCopy.revealed : RouletteCopy.hint,
          foil: ClipRRect(
            borderRadius: SkyRadii.all(SkyRadii.button),
            child: Stack(
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 132),
                  child: DateIdeaReveal(key: ValueKey<String>(_idea.id), idea: _idea),
                ),
                Positioned.fill(
                  child: ScratchCard(key: ValueKey<int>(_cardKey), revealed: _revealed, onRevealed: _onRevealed),
                ),
              ],
            ),
          ),
          categories: DateIdeaChips(selected: _category, onSelect: _selectCategory),
        ),
      ],
    );
  }
}

class ScratchPanel extends StatelessWidget {
  const ScratchPanel({super.key, required this.title, required this.subtitle, required this.foil, this.categories});

  static const List<Color> night = [Color(0xFF2E2870), Color(0xFF1A1650)];
  static const List<Color> day = [SkyTokens.indigo, Color(0xFF4B4AA0)];

  final String title;
  final String subtitle;
  final Widget foil;
  final Widget? categories;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final motion = skyMotionAllowed(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: SkyRadii.all(24),
        border: Border.all(color: t.cardBorder),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: t.isNight ? night : day,
        ),
        boxShadow: t.isDay ? t.softShadow : const [],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: SkyType.serif(20, weight: FontWeight.w500, height: 1.25).copyWith(color: SkyTokens.white),
          ),
          const SizedBox(height: 3),
          AnimatedSwitcher(
            duration: motion ? SkyMotion.base : Duration.zero,
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.topLeft,
              children: [...previous, ?current],
            ),
            child: Text(
              subtitle,
              key: ValueKey<String>(subtitle),
              style: SkyType.sans(12, height: 1.4).copyWith(color: SkyTokens.white.withValues(alpha: 0.7)),
            ),
          ),
          const SizedBox(height: SkySpace.md),
          foil,
          if (categories != null) ...[const SizedBox(height: 6), categories!],
        ],
      ),
    );
  }
}

class DateIdeaChips extends StatelessWidget {
  const DateIdeaChips({super.key = UsKeys.ideaCategories, required this.selected, required this.onSelect});

  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: RouletteCopy.categories,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            for (var i = 0; i < dateIdeaCategories.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              DateIdeaChip(
                label: RouletteCopy.categoryLabel(dateIdeaCategories[i].id, dateIdeaCategories[i].label),
                selected: selected == dateIdeaCategories[i].id,
                onTap: () => onSelect(dateIdeaCategories[i].id),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class DateIdeaChip extends StatelessWidget {
  const DateIdeaChip({super.key, required this.label, required this.selected, required this.onTap});

  static const Color gold = Color(0xFFFFD98A);
  static const Color ink = Color(0xFF1B1838);

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SkyPressable(
      onTap: onTap,
      semanticLabel: label,
      selected: selected,
      excludeSemantics: true,
      child: SkyTapTarget(
        child: AnimatedContainer(
          duration: skyMotionAllowed(context) ? SkyMotion.quick : Duration.zero,
          curve: SkyMotion.standard,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? gold : SkyTokens.white.withValues(alpha: 0.1),
            borderRadius: SkyRadii.all(SkyRadii.pill),
            border: Border.all(color: selected ? gold : SkyTokens.white.withValues(alpha: 0.14)),
          ),
          child: Text(
            label,
            style: SkyType.chip.copyWith(color: selected ? ink : SkyTokens.white.withValues(alpha: 0.86)),
          ),
        ),
      ),
    );
  }
}

class DateIdeaReveal extends StatefulWidget {
  const DateIdeaReveal({super.key, required this.idea});

  static const Color paper = Color(0xFFFFF8EC);
  static const Color goldInk = Color(0xFFB07A1E);

  final DateIdea idea;

  @override
  State<DateIdeaReveal> createState() => _DateIdeaRevealState();
}

class _DateIdeaRevealState extends State<DateIdeaReveal> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: SkyMotion.slow);
  late final Animation<double> _fade = CurvedAnimation(parent: _controller, curve: SkyMotion.gentle);
  late final Animation<double> _scale = Tween<double>(
    begin: 0.96,
    end: 1,
  ).animate(CurvedAnimation(parent: _controller, curve: const SkySpringCurve(SkyMotion.popSpring, seconds: 0.4)));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller.isAnimating || _controller.value > 0) return;
    if (skyMotionAllowed(context)) {
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
    final t = context.sky;
    final idea = widget.idea;
    return DecoratedBox(
      decoration: const BoxDecoration(color: DateIdeaReveal.paper),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: FadeTransition(
          opacity: _fade,
          child: ScaleTransition(
            scale: _scale,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  RouletteCopy.dateIdea.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: SkyType.caps(9.5, weight: FontWeight.w700, tracking: 0.2, color: DateIdeaReveal.goldInk),
                ),
                const SizedBox(height: 6),
                Text(
                  idea.title,
                  textAlign: TextAlign.center,
                  style: SkyType.serif(19, weight: FontWeight.w500, height: 1.25).copyWith(color: t.paperInk),
                ),
                const SizedBox(height: 6),
                Text(
                  idea.desc,
                  textAlign: TextAlign.center,
                  style: SkyType.sans(12.5, height: 1.45).copyWith(color: t.paperMuted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
