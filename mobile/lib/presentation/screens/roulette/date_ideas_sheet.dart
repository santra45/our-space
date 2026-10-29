import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/engine.dart';
import '../../sky/sky.dart';
import '../../widgets/app_haptics.dart';
import '../../widgets/confetti_burst.dart';
import '../us/us_keys.dart';
import '../us/widgets/us_sheet_frame.dart';
import 'date_idea_sheet.dart';
import 'roulette_copy.dart';

Future<void> showDateIdeasSheet(BuildContext context, {required DateIdeasRepository ideas, required String category}) {
  return showSkySheet<void>(
    context: context,
    builder: (_) => DateIdeasSheet(ideas: ideas, category: category),
  );
}

class DateIdeasSheet extends StatefulWidget {
  const DateIdeasSheet({super.key, required this.ideas, required this.category});

  final DateIdeasRepository ideas;
  final String category;

  @override
  State<DateIdeasSheet> createState() => _DateIdeasSheetState();
}

class _DateIdeasSheetState extends State<DateIdeasSheet> {
  StreamSubscription<TableSnapshot<DateIdeaRecord>>? _subscription;
  TableSnapshot<DateIdeaRecord>? _snapshot;
  late String _category = widget.category;
  String _error = '';

  DateIdeasRepository get _ideas => widget.ideas;

  @override
  void initState() {
    super.initState();
    _subscription = _ideas.watch().listen(_onSnapshot, onError: (Object error) {});
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _onSnapshot(TableSnapshot<DateIdeaRecord> snapshot) {
    if (mounted) setState(() => _snapshot = snapshot);
  }

  DateIdeaRecord? _find(String id) {
    for (final idea in _snapshot?.items ?? const <DateIdeaRecord>[]) {
      if (idea.id == id) return idea;
    }
    return null;
  }

  Future<SaveOutcome> _add(String title, String desc, String category) async {
    if (title.trim().isEmpty) return SaveOutcome.skipped;
    AppHaptics.tap();
    try {
      await _ideas.add(title: title, desc: desc, category: category);
      if (mounted) {
        setState(() {
          _category = category;
          _error = '';
        });
        AppHaptics.celebration();
        fireHeartConfetti(context);
      }
      return SaveOutcome.saved;
    } catch (_) {
      return SaveOutcome.failed;
    }
  }

  Future<SaveOutcome> _saveEdit(String id, String title, String desc, String category) async {
    final idea = _find(id);
    if (title.trim().isEmpty || idea == null) return SaveOutcome.skipped;
    AppHaptics.tap();
    try {
      await _ideas.edit(idea, title: title, desc: desc, category: category);
      if (mounted) setState(() => _error = '');
      return SaveOutcome.saved;
    } catch (_) {
      return SaveOutcome.failed;
    }
  }

  Future<void> _remove(String id) async {
    AppHaptics.tap();
    try {
      await _ideas.remove(id);
      if (mounted) setState(() => _error = '');
    } catch (_) {
      if (mounted) setState(() => _error = RouletteCopy.removeFailed);
    }
  }

  Future<void> _openAdd() async {
    await showDateIdeaSheet(context, category: _category, onSave: _add);
  }

  Future<void> _openEdit(DateIdeaRecord idea) async {
    final action = await showDateIdeaSheet(
      context,
      idea: idea,
      category: idea.category,
      onSave: (title, desc, category) => _saveEdit(idea.id, title, desc, category),
    );
    if (action == DateIdeaAction.removed && mounted) await _remove(idea.id);
  }

  @override
  Widget build(BuildContext context) {
    final items = _snapshot?.items ?? const <DateIdeaRecord>[];
    final unreadable = _snapshot?.unreadable ?? 0;
    final notice = _error.isNotEmpty ? _error : (unreadable > 0 ? RouletteCopy.hiddenIdeas(unreadable) : null);
    final groups = <(String, List<DateIdeaRecord>)>[
      for (final kind in dateIdeaCategories)
        if (isDateIdeaKind(kind.id))
          (RouletteCopy.categoryLabel(kind.id, kind.label), items.where((idea) => idea.category == kind.id).toList()),
      (RouletteCopy.otherKind, items.where((idea) => !isDateIdeaKind(idea.category)).toList()),
    ].where((group) => group.$2.isNotEmpty).toList();

    return UsSheetFrame(
      kicker: RouletteCopy.ideasKicker,
      title: RouletteCopy.ideasTitle,
      message: RouletteCopy.ideasNote,
      children: [
        if (notice != null)
          Padding(
            padding: const EdgeInsets.only(bottom: SkySpace.md),
            child: SkyEntrance(
              key: ValueKey<String>('idea-notice-$notice'),
              child: SkyNotice(text: notice, tone: _error.isNotEmpty ? SkyNoticeTone.error : SkyNoticeTone.warning),
            ),
          ),
        AddDateIdeaRow(onTap: () => unawaited(_openAdd())),
        for (final (label, ideas) in groups)
          Padding(
            padding: const EdgeInsets.only(top: SkySpace.lg),
            child: DateIdeaGroup(label: label, ideas: ideas, onOpen: (idea) => unawaited(_openEdit(idea))),
          ),
      ],
    );
  }
}

class AddDateIdeaRow extends StatelessWidget {
  const AddDateIdeaRow({super.key = UsKeys.addIdea, required this.onTap});

  static const double size = 26;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    return SkyPressable(
      onTap: onTap,
      pressedScale: 0.98,
      semanticLabel: RouletteCopy.addIdea,
      excludeSemantics: true,
      child: SkyTapTarget(
        child: Row(
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: t.roseSoft,
                border: Border.all(color: t.roseBorder, width: 1.5),
              ),
              alignment: Alignment.center,
              child: SkyIcon(SkyIcons.plus, size: 14, color: t.rose),
            ),
            const SizedBox(width: 12),
            Text(
              RouletteCopy.addIdea,
              style: SkyType.sans(14, weight: FontWeight.w600, height: 1.35).copyWith(color: t.rose),
            ),
          ],
        ),
      ),
    );
  }
}

class DateIdeaGroup extends StatelessWidget {
  const DateIdeaGroup({super.key, required this.label, required this.ideas, required this.onOpen});

  final String label;
  final List<DateIdeaRecord> ideas;
  final ValueChanged<DateIdeaRecord> onOpen;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          header: true,
          child: Text(label.toUpperCase(), style: SkyType.kicker.copyWith(color: t.kicker)),
        ),
        const SizedBox(height: SkySpace.sm),
        SkyCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < ideas.length; i++) ...[
                if (i > 0) const SkyDivider(),
                DateIdeaRow(key: UsKeys.idea(ideas[i].id), idea: ideas[i], onOpen: () => onOpen(ideas[i])),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class DateIdeaRow extends StatelessWidget {
  const DateIdeaRow({super.key, required this.idea, required this.onOpen});

  final DateIdeaRecord idea;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final desc = idea.desc.trim();
    return SkyPressable(
      onTap: onOpen,
      pressedScale: 0.98,
      semanticLabel: '${RouletteCopy.change}, ${idea.title}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    idea.title,
                    style: SkyType.sans(14, weight: FontWeight.w600, height: 1.35).copyWith(color: t.text),
                  ),
                  if (desc.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      desc,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: SkyType.sans(12, height: 1.4).copyWith(color: t.muted),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            SkyIcon(SkyIcons.dots, size: 18, color: t.faint),
          ],
        ),
      ),
    );
  }
}
