import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/engine.dart';
import '../../space_scope.dart';
import '../../widgets/our_widgets.dart';
import 'milestone_copy.dart';

class MilestoneListCard extends StatefulWidget {
  const MilestoneListCard({super.key});

  @override
  State<MilestoneListCard> createState() => _MilestoneListCardState();
}

class _MilestoneListCardState extends State<MilestoneListCard> {
  static final OurFieldStyle _titleStyle = OurFieldStyle.form;
  static final OurFieldStyle _dateStyle = OurFieldStyle.form.copyWith(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
  );
  static final OurFieldStyle _editDateStyle = OurFieldStyle.form.copyWith(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
  );

  late final Stream<TableSnapshot<MilestoneRecord>> _items = context.space.milestones.watch();
  final TextEditingController _title = TextEditingController();
  final TextEditingController _editTitle = TextEditingController();

  bool _adding = false;
  String _date = toLocalDateInput();
  String _error = '';
  String? _editingId;
  String _editDate = toLocalDateInput();
  bool _writing = false;

  @override
  void dispose() {
    _title.dispose();
    _editTitle.dispose();
    super.dispose();
  }

  bool get _unlocked => context.read<VaultService>().key != null;

  Future<void> _add() async {
    final title = _title.text.trim();
    if (title.isEmpty || !_unlocked || _writing) return;
    final space = context.space;
    _writing = true;
    try {
      await space.milestones.add(title: title, date: _date);
      if (!mounted) return;
      _title.clear();
      setState(() {
        _adding = false;
        _error = '';
      });
      AppHaptics.celebration();
      fireHeartConfetti(context);
    } catch (_) {
      if (mounted) setState(() => _error = MilestoneCopy.saveFailed);
    } finally {
      _writing = false;
    }
  }

  Future<void> _delete(MilestoneRecord milestone) async {
    final space = context.space;
    final confirmed = await showOurConfirm(context, message: MilestoneCopy.confirmDelete);
    if (!confirmed || !mounted) return;
    AppHaptics.tap();
    try {
      await space.milestones.delete(milestone.id);
      if (mounted) setState(() => _error = '');
    } catch (_) {
      if (mounted) setState(() => _error = MilestoneCopy.deleteFailed);
    }
  }

  void _startEdit(MilestoneRecord milestone) {
    _editTitle.text = milestone.title;
    setState(() {
      _editingId = milestone.id;
      final date = milestone.date;
      _editDate = date == null || date.isEmpty ? toLocalDateInput() : date;
    });
  }

  void _cancelEdit() {
    AppHaptics.tap();
    _editTitle.clear();
    setState(() => _editingId = null);
  }

  Future<void> _saveEdit(MilestoneRecord milestone) async {
    final title = _editTitle.text.trim();
    if (title.isEmpty || !_unlocked || _writing) return;
    AppHaptics.tap();
    final space = context.space;
    _writing = true;
    try {
      await space.milestones.update(milestone, title: title, date: _editDate);
      if (!mounted) return;
      setState(() {
        _editingId = null;
        _error = '';
      });
      AppHaptics.celebration();
    } catch (_) {
      if (mounted) setState(() => _error = MilestoneCopy.updateFailed);
    } finally {
      _writing = false;
    }
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          const LucideIcon(AppIcons.sparkles, size: 16, color: AppColors.amber500),
          const SizedBox(width: 8),
          Expanded(child: Text(MilestoneCopy.title, style: Tw.sm.bold.c(AppColors.slate800))),
          OurIconButton.add(onPressed: () => setState(() => _adding = !_adding)),
        ],
      ),
    );
  }

  Widget _addForm() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: CssBox(
        padding: const EdgeInsets.all(12),
        color: AppColors.white.withValues(alpha: 0.8),
        border: Border.all(color: AppColors.blush200),
        borderRadius: AppRadii.all(AppRadii.x2l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            OurTextField(
              controller: _title,
              style: _titleStyle,
              hint: MilestoneCopy.placeholder,
              minLines: 2,
              maxLines: 2,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Flexible(
                  child: OurDateField(
                    value: parseLocalDate(_date),
                    onChanged: (date) => setState(() => _date = toLocalDateInput(date)),
                    style: _dateStyle,
                  ),
                ),
                const SizedBox(width: 8),
                BouncyButton(small: true, label: MilestoneCopy.add, onPressed: () => unawaited(_add())),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _editForm(MilestoneRecord milestone) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(MilestoneCopy.editLabel, style: Tw.px11.semibold.c(AppColors.slate600)),
        ),
        OurTextField(
          controller: _editTitle,
          style: _titleStyle,
          hint: MilestoneCopy.placeholder,
          minLines: 2,
          maxLines: 2,
          autofocus: true,
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: OurDateField(
                value: parseLocalDate(_editDate),
                onChanged: (date) => setState(() => _editDate = toLocalDateInput(date)),
                style: _editDateStyle,
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
                    onTap: _cancelEdit,
                    child: CssBox(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      border: Border.all(color: AppColors.slate200),
                      borderRadius: AppRadii.all(AppRadii.xl),
                      child: Text(MilestoneCopy.cancel, style: Tw.xs.medium.c(AppColors.slate500)),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                BouncyButton(
                  small: true,
                  label: MilestoneCopy.save,
                  onPressed: () => unawaited(_saveEdit(milestone)),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _row(MilestoneRecord milestone) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: CssBox(
                    width: 8,
                    height: 8,
                    color: AppColors.blush400,
                    borderRadius: AppRadii.all(AppRadii.full),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    milestone.title.isEmpty ? MilestoneCopy.fallbackTitle : milestone.title,
                    style: Tw.xs.bold.snug.c(AppColors.slate700),
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
              Text(
                formatDatePretty(milestone.date),
                softWrap: false,
                style: Tw.px11.medium.c(AppColors.slate400),
              ),
              const SizedBox(width: 4),
              OurIconButton.edit(
                semanticLabel: MilestoneCopy.editTooltip,
                onPressed: () => _startEdit(milestone),
              ),
              const SizedBox(width: 4),
              OurIconButton(
                icon: AppIcons.trash2,
                haptic: false,
                semanticLabel: MilestoneCopy.deleteTooltip,
                onPressed: () => unawaited(_delete(milestone)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _item(MilestoneRecord milestone) {
    return CssBox(
      key: ValueKey<String>(milestone.id),
      padding: const EdgeInsets.all(12),
      color: AppColors.white.withValues(alpha: 0.6),
      border: Border.all(color: AppColors.blush100),
      borderRadius: AppRadii.all(AppRadii.x2l),
      child: _editingId == milestone.id ? _editForm(milestone) : _row(milestone),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: StreamBuilder<TableSnapshot<MilestoneRecord>>(
        stream: _items,
        builder: (context, snapshot) {
          final records = snapshot.data?.items ?? const <MilestoneRecord>[];
          final notice = MilestoneCopy.notice(error: _error, unreadable: snapshot.data?.unreadable ?? 0);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _header(),
              if (notice != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: OurNotice(tone: NoticeTone.warning, iconColor: AppColors.amber800, message: notice),
                ),
              if (_adding) _addForm(),
              if (records.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    MilestoneCopy.empty,
                    textAlign: TextAlign.center,
                    style: Tw.xs.italic.c(AppColors.slate400),
                  ),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: spaced([for (final milestone in records) _item(milestone)], 8),
                ),
            ],
          );
        },
      ),
    );
  }
}
