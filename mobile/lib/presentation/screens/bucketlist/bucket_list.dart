import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/engine.dart';
import '../../space_scope.dart';
import '../../widgets/our_widgets.dart';
import 'bucket_copy.dart';
import 'bucket_item_card.dart';
import 'layout_glide.dart';

class BucketList extends StatefulWidget {
  const BucketList({super.key});

  @override
  State<BucketList> createState() => _BucketListState();
}

class _BucketListState extends State<BucketList> {
  late final OurSpace _space = context.space;
  StreamSubscription<TableSnapshot<BucketListRecord>>? _subscription;
  TableSnapshot<BucketListRecord>? _snapshot;
  final TextEditingController _newText = TextEditingController();
  final TextEditingController _editText = TextEditingController();
  String _category = BucketCopy.defaultCategory;
  String _editCategory = BucketCopy.defaultCategory;
  bool _isAdding = false;
  String _error = '';
  String? _editingId;

  BucketListRepository get _bucket => _space.bucketList;

  @override
  void initState() {
    super.initState();
    _subscription = _bucket.watch().listen(_onSnapshot, onError: (Object error) {});
    if (_space.vault.isUnlocked) unawaited(_seed());
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _newText.dispose();
    _editText.dispose();
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
    final confirmed = await showOurConfirm(context, message: BucketCopy.deleteQuestion);
    if (!confirmed || !mounted) return;
    AppHaptics.tap();
    try {
      await _bucket.delete(id);
      if (mounted) setState(() => _error = '');
    } catch (_) {
      if (mounted) setState(() => _error = BucketCopy.deleteFailed);
    }
  }

  void _startEdit(BucketListRecord item) {
    AppHaptics.tap();
    final category = item.fields['category'];
    setState(() {
      _editingId = item.id;
      _editText.text = item.text;
      _editCategory = category is String && category.isNotEmpty ? category : BucketCopy.defaultCategory;
    });
  }

  void _cancelEdit() {
    AppHaptics.tap();
    setState(() {
      _editingId = null;
      _editText.clear();
    });
  }

  Future<void> _saveEdit(String id) async {
    final text = _editText.text.trim();
    final item = _find(id);
    if (text.isEmpty || item == null) return;
    AppHaptics.tap();
    try {
      await _bucket.edit(item, text: text, category: _editCategory);
      if (!mounted) return;
      setState(() {
        _editingId = null;
        _error = '';
      });
    } catch (_) {
      if (mounted) setState(() => _error = BucketCopy.saveFailed);
    }
  }

  Future<void> _add() async {
    final text = _newText.text.trim();
    if (text.isEmpty) return;
    AppHaptics.tap();
    try {
      await _bucket.add(text: text, category: _category);
      if (!mounted) return;
      _newText.clear();
      setState(() {
        _isAdding = false;
        _error = '';
      });
      AppHaptics.celebration();
      fireHeartConfetti(context);
    } catch (_) {
      if (mounted) setState(() => _error = BucketCopy.saveFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _snapshot?.items ?? const <BucketListRecord>[];
    final unreadable = _snapshot?.unreadable ?? 0;
    final done = items.where((item) => item.completed).length;
    final percent = progressPercent(done, items.length);

    return OurPage(
      children: [
        GlideScope(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: spaced([
              OurSectionHeader(
                title: BucketCopy.title,
                subtitle: BucketCopy.progress(done, items.length, percent),
                icon: AppIcons.trophy,
                trailing: BouncyButton(
                  label: BucketCopy.addDream,
                  icon: AppIcons.plus,
                  small: true,
                  pill: true,
                  onPressed: () {
                    AppHaptics.tap();
                    setState(() => _isAdding = !_isAdding);
                  },
                ),
              ),
              if (_error.isNotEmpty || unreadable > 0)
                OurNotice(
                  tone: NoticeTone.warning,
                  iconColor: AppColors.amber800,
                  message: _error.isNotEmpty ? _error : BucketCopy.hiddenItems(unreadable),
                ),
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(BucketCopy.conquered, style: Tw.xs.bold.c(AppColors.slate700))),
                        Text('$percent%', style: Tw.xs.extrabold.c(AppColors.blush600)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    OurProgressBar(value: percent / 100),
                  ],
                ),
              ),
              if (_isAdding) _addForm(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: spaced([
                  for (final item in items)
                    LayoutGlide(
                      key: ValueKey(item.id),
                      child: BucketItemCard(
                        item: item,
                        editing: _editingId == item.id,
                        editController: _editText,
                        editCategory: _editCategory,
                        onEditCategory: (value) => setState(() => _editCategory = value),
                        onToggle: () => _toggle(item),
                        onStartEdit: () => _startEdit(item),
                        onCancelEdit: _cancelEdit,
                        onSaveEdit: () => _saveEdit(item.id),
                        onDelete: () => _delete(item.id),
                      ),
                    ),
                ], 10),
              ),
            ], 16),
          ),
        ),
      ],
    );
  }

  Widget _addForm() {
    return CssBox(
      padding: const EdgeInsets.all(16),
      color: AppColors.white,
      border: Border.all(color: AppColors.blush200),
      borderRadius: AppRadii.all(AppRadii.x3l),
      shadows: AppShadows.lg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const OurFieldLabel(BucketCopy.newLabel),
          OurTextField(
            controller: _newText,
            hint: BucketCopy.hint,
            minLines: 2,
            maxLines: 2,
            autofocus: true,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            semanticLabel: BucketCopy.newLabel,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Flexible(
                child: OurSelectField<String>(
                  value: _category,
                  options: bucketOptions,
                  onChanged: (value) => setState(() => _category = value),
                  style: OurFieldStyle.form.copyWith(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
                  semanticLabel: 'Category',
                ),
              ),
              const SizedBox(width: 8),
              BouncyButton(label: BucketCopy.addGoal, small: true, onPressed: _add),
            ],
          ),
        ],
      ),
    );
  }
}
