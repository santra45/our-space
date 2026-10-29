import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/engine.dart';
import '../../sky/sky.dart';
import '../../space_scope.dart';
import '../../widgets/app_haptics.dart';
import '../../widgets/confetti_burst.dart';
import '../us/us_keys.dart';
import 'date_ideas_sheet.dart';
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
  StreamSubscription<TableSnapshot<DateIdeaRecord>>? _ideasSubscription;
  List<DateIdea> _ideas = defaultDateIdeas;
  String _category = 'all';
  String? _ideaId = defaultDateIdeas.first.id;
  bool _revealed = false;
  bool _revealedLatch = false;
  int _cardKey = 0;
  int _appliedAt = 0;
  int _persisting = 0;
  bool _hasDeferred = false;
  RouletteStateRecord? _deferred;
  RouletteStateRecord? _pending;

  DateIdea? get _idea => findDateIdea(_ideas, _ideaId);

  @override
  void initState() {
    super.initState();
    _subscription = context.space.roulette.watch().listen(_onStored);
    _ideasSubscription = context.space.dateIdeas.watch().listen(_onIdeas, onError: (Object error) {});
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _ideasSubscription?.cancel();
    super.dispose();
  }

  void _onIdeas(TableSnapshot<DateIdeaRecord> snapshot) {
    if (!mounted || !snapshot.unlocked) return;
    setState(() => _ideas = [for (final record in snapshot.items) record.idea]);
    final pending = _pending;
    if (pending != null && findDateIdea(_ideas, pending.ideaId) != null) {
      _pending = null;
      _show(pending);
    }
    if (_idea == null) _settle();
  }

  void _settle() {
    final pool = dateIdeasIn(_ideas, _category);
    final next = pool.isEmpty ? null : pool.first.id;
    if (next == _ideaId) return;
    _revealedLatch = false;
    setState(() {
      _ideaId = next;
      _revealed = false;
      _cardKey++;
    });
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
    if (findDateIdea(_ideas, record.ideaId) == null) {
      _pending = record;
      return;
    }
    _pending = null;
    _show(record);
  }

  void _show(RouletteStateRecord record) {
    final revealed = record.revealed;
    _revealedLatch = revealed;
    setState(() {
      _ideaId = record.ideaId;
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
    _pending = null;
    final pool = dateIdeasIn(_ideas, category);
    if (pool.isEmpty) {
      _settle();
      return;
    }
    final available = pool.length > 1 ? pool.where((idea) => idea.id != _ideaId).toList() : pool;
    final picked = available.isEmpty ? pool.first : available[DateRoulette.random.nextInt(available.length)];
    _revealedLatch = false;
    setState(() {
      _ideaId = picked.id;
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
    final id = _ideaId;
    if (_revealedLatch || id == null) return;
    _revealedLatch = true;
    setState(() => _revealed = true);
    AppHaptics.celebration();
    fireHeartConfetti(context);
    unawaited(_persist(ideaId: id, category: _category, revealed: true));
  }

  void _openIdeas() {
    AppHaptics.tap();
    unawaited(showDateIdeasSheet(context, ideas: context.space.dateIdeas, category: _category));
  }

  @override
  Widget build(BuildContext context) {
    final night = context.sky.isNight;
    final idea = _idea;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SkySectionHeader(title: RouletteCopy.title, action: RouletteCopy.anotherIdea, onAction: () => _pick()),
        const SizedBox(height: 10),
        ScratchPanel(
          key: UsKeys.scratchPanel,
          title: night ? RouletteCopy.tonight : RouletteCopy.weekend,
          subtitle: idea == null ? RouletteCopy.emptyHint : (_revealed ? RouletteCopy.revealed : RouletteCopy.hint),
          foil: ClipRRect(
            borderRadius: SkyRadii.all(SkyRadii.button),
            child: idea == null
                ? ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 132),
                    child: DateIdeasEmpty(all: _category == 'all' || _ideas.isEmpty),
                  )
                : Stack(
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 132),
                        child: DateIdeaReveal(key: ValueKey<String>(idea.id), idea: idea),
                      ),
                      Positioned.fill(
                        child: ScratchCard(key: ValueKey<int>(_cardKey), revealed: _revealed, onRevealed: _onRevealed),
                      ),
                    ],
                  ),
          ),
          categories: DateIdeaChips(selected: _category, onSelect: _selectCategory),
          footer: DateIdeasEntry(count: _ideas.length, onTap: _openIdeas),
        ),
      ],
    );
  }
}

class ScratchPanel extends StatelessWidget {
  const ScratchPanel({
    super.key,
    required this.title,
    required this.subtitle,
    required this.foil,
    this.categories,
    this.footer,
  });

  static const List<Color> night = [Color(0xFF2E2870), Color(0xFF1A1650)];
  static const List<Color> day = [SkyTokens.indigo, Color(0xFF4B4AA0)];

  final String title;
  final String subtitle;
  final Widget foil;
  final Widget? categories;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final motion = skyMotionAllowed(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: SkyRadii.all(24),
        border: Border.all(color: t.cardBorder),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: t.isNight ? night : day),
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
            layoutBuilder: (current, previous) =>
                Stack(alignment: Alignment.topLeft, children: [...previous, ?current]),
            child: Text(
              subtitle,
              key: ValueKey<String>(subtitle),
              style: SkyType.sans(12, height: 1.4).copyWith(color: SkyTokens.white.withValues(alpha: 0.7)),
            ),
          ),
          const SizedBox(height: SkySpace.md),
          foil,
          if (categories != null) ...[const SizedBox(height: 6), categories!],
          if (footer != null) ...[const SizedBox(height: 4), footer!],
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

class DateIdeasEntry extends StatelessWidget {
  const DateIdeasEntry({super.key = UsKeys.ideasEntry, required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final soft = SkyTokens.white.withValues(alpha: 0.62);
    return SkyPressable(
      onTap: onTap,
      pressedScale: 0.98,
      semanticLabel: RouletteCopy.ideasEntryLabel(count),
      excludeSemantics: true,
      child: SkyTapTarget(
        child: Row(
          children: [
            SkyIcon(SkyIcons.pen, size: 14, color: DateIdeaChip.gold),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                RouletteCopy.ideasEntry,
                style: SkyType.sans(
                  12.5,
                  weight: FontWeight.w600,
                ).copyWith(color: SkyTokens.white.withValues(alpha: 0.9)),
              ),
            ),
            Text(RouletteCopy.ideasCount(count), style: SkyType.sans(12).copyWith(color: soft)),
            const SizedBox(width: 2),
            SkyIcon(SkyIcons.chevron, size: 14, color: soft),
          ],
        ),
      ),
    );
  }
}

class DateIdeasEmpty extends StatelessWidget {
  const DateIdeasEmpty({super.key = UsKeys.ideasEmpty, required this.all});

  final bool all;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    return DecoratedBox(
      decoration: const BoxDecoration(color: DateIdeaReveal.paper),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              all ? RouletteCopy.emptyAll : RouletteCopy.emptyKind,
              textAlign: TextAlign.center,
              style: SkyType.serif(18, weight: FontWeight.w500, height: 1.25).copyWith(color: t.paperInk),
            ),
            const SizedBox(height: 6),
            Text(
              RouletteCopy.emptyNote,
              textAlign: TextAlign.center,
              style: SkyType.sans(12.5, height: 1.45).copyWith(color: t.paperMuted),
            ),
          ],
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
