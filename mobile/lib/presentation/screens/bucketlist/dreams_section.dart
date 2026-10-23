import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/engine.dart';
import '../../sky/sky.dart';
import '../../space_scope.dart';
import '../../widgets/app_haptics.dart';
import '../../widgets/confetti_burst.dart';
import '../us/us_keys.dart';
import '../us/widgets/us_sheet_frame.dart';
import 'bucket_copy.dart';
import 'dream_row.dart';
import 'dream_sheet.dart';
import 'layout_glide.dart';

class DreamsSection extends StatefulWidget {
  const DreamsSection({super.key});

  @override
  State<DreamsSection> createState() => _DreamsSectionState();
}

class _DreamsSectionState extends State<DreamsSection> {
  late final OurSpace _space;
  StreamSubscription<TableSnapshot<BucketListRecord>>? _subscription;
  TableSnapshot<BucketListRecord>? _snapshot;
  String _category = BucketCopy.defaultCategory;
  String _error = '';

  BucketListRepository get _bucket => _space.bucketList;

  @override
  void initState() {
    super.initState();
    _space = context.space;
    _subscription = _bucket.watch().listen(_onSnapshot, onError: (Object error) {});
    if (_space.vault.isUnlocked) unawaited(_seed());
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _onSnapshot(TableSnapshot<BucketListRecord> snapshot) {
    if (mounted) setState(() => _snapshot = snapshot);
  }

  Future<void> _seed() async {
    try {
      await _bucket.seedDefaultsIfEmpty();
    } catch (_) {
      if (mounted) setState(() => _error = BucketCopy.seedFailed);
    }
  }

  BucketListRecord? _find(String id) {
    for (final item in _snapshot?.items ?? const <BucketListRecord>[]) {
      if (item.id == id) return item;
    }
    return null;
  }

  String _categoryOf(BucketListRecord item) {
    final category = item.fields['category'];
    return category is String && category.isNotEmpty ? category : BucketCopy.defaultCategory;
  }

  Future<void> _toggle(BucketListRecord item) async {
    AppHaptics.tap();
    final nowCompleted = !item.completed;
    try {
      await _bucket.toggleComplete(item);
      if (!mounted) return;
      setState(() => _error = '');
      if (nowCompleted) {
        AppHaptics.celebration();
        fireCelebrationBurst(context);
      }
    } catch (_) {
      if (mounted) setState(() => _error = BucketCopy.toggleFailed);
    }
  }

  Future<void> _delete(String id) async {
    AppHaptics.tap();
    try {
      await _bucket.delete(id);
      if (mounted) setState(() => _error = '');
    } catch (_) {
      if (mounted) setState(() => _error = BucketCopy.deleteFailed);
    }
  }

  Future<SaveOutcome> _add(String text, String category) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return SaveOutcome.skipped;
    AppHaptics.tap();
    try {
      await _bucket.add(text: trimmed, category: category);
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

  Future<SaveOutcome> _saveEdit(String id, String text, String category) async {
    final trimmed = text.trim();
    final item = _find(id);
    if (trimmed.isEmpty || item == null) return SaveOutcome.skipped;
    AppHaptics.tap();
    try {
      await _bucket.edit(item, text: trimmed, category: category);
      if (mounted) setState(() => _error = '');
      return SaveOutcome.saved;
    } catch (_) {
      return SaveOutcome.failed;
    }
  }

  Future<void> _openAdd() async {
    await showDreamSheet(context, category: _category, onSave: _add);
  }

  Future<void> _openEdit(BucketListRecord item) async {
    final action = await showDreamSheet(
      context,
      dream: item,
      category: _categoryOf(item),
      onSave: (text, category) => _saveEdit(item.id, text, category),
    );
    if (action == DreamAction.removed && mounted) await _delete(item.id);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final items = _snapshot?.items ?? const <BucketListRecord>[];
    final unreadable = _snapshot?.unreadable ?? 0;
    final done = items.where((item) => item.completed).length;
    final percent = progressPercent(done, items.length);
    final notice = _error.isNotEmpty ? _error : (unreadable > 0 ? BucketCopy.hiddenItems(unreadable) : null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SkySectionHeader(
          title: BucketCopy.title,
          trailing: Semantics(
            label: BucketCopy.countLabel(done, items.length),
            excludeSemantics: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                BucketCopy.count(done, items.length),
                key: UsKeys.dreamCount,
                style: SkyType.sans(12, weight: FontWeight.w600).copyWith(color: t.rose),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (notice != null)
          Padding(
            padding: const EdgeInsets.only(bottom: SkySpace.md),
            child: SkyEntrance(
              key: ValueKey<String>('dream-notice-$notice'),
              child: SkyNotice(
                text: notice,
                tone: _error.isNotEmpty ? SkyNoticeTone.error : SkyNoticeTone.warning,
              ),
            ),
          ),
        SkyCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              SkyProgressBar(key: UsKeys.dreamProgress, value: percent / 100, semanticLabel: BucketCopy.progressLabel),
              const SizedBox(height: 14),
              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: SkySpace.md),
                  child: Text(BucketCopy.empty, style: SkyType.bodySmall.copyWith(color: t.muted)),
                ),
              GlideScope(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < items.length; i++)
                      LayoutGlide(
                        key: ValueKey<String>(items[i].id),
                        child: SkyEntrance(
                          index: i,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: SkySpace.xxs),
                            child: DreamRow(
                              key: UsKeys.dream(items[i].id),
                              item: items[i],
                              onToggle: () => unawaited(_toggle(items[i])),
                              onOpen: () => unawaited(_openEdit(items[i])),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              AddDreamRow(onTap: () => unawaited(_openAdd())),
            ],
          ),
        ),
      ],
    );
  }
}

class AddDreamRow extends StatelessWidget {
  const AddDreamRow({super.key = UsKeys.addDream, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    return SkyPressable(
      onTap: onTap,
      pressedScale: 0.98,
      semanticLabel: BucketCopy.addDream,
      excludeSemantics: true,
      child: Row(
        children: [
          Container(
            width: DreamCheck.size,
            height: DreamCheck.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: t.roseSoft,
              border: Border.all(color: t.roseBorder, width: 1.5),
            ),
            alignment: Alignment.center,
            child: SkyIcon(SkyIcons.plus, size: 14, color: t.rose),
          ),
          const SizedBox(width: 12),
          Text(BucketCopy.addDream, style: SkyType.sans(14, weight: FontWeight.w600, height: 1.35).copyWith(color: t.rose)),
        ],
      ),
    );
  }
}
