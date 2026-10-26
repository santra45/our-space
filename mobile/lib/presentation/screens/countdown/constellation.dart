import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/engine.dart';
import '../../sky/sky.dart';
import '../../space_scope.dart';
import '../../widgets/app_haptics.dart';
import '../../widgets/confetti_burst.dart';
import '../daily/daily_question_model.dart';
import '../sky/sky_map_page.dart';
import '../sky/sky_map_plan.dart';
import '../us/us_copy.dart';
import '../us/us_keys.dart';
import '../us/widgets/us_sheet_frame.dart';
import 'live_love_counter.dart';
import 'milestone_copy.dart';
import 'moment_sheet.dart';

class OurConstellation extends StatefulWidget {
  const OurConstellation({super.key, required this.counter, required this.startDate, required this.onChangeDay});

  final LiveLoveCounter counter;
  final String startDate;
  final VoidCallback onChangeDay;

  @override
  State<OurConstellation> createState() => _OurConstellationState();
}

class _OurConstellationState extends State<OurConstellation> {
  late final Stream<TableSnapshot<MilestoneRecord>> _items;
  late final DailyQuestionModel _daily = DailyQuestionModel(context.space);
  String _error = '';
  bool _writing = false;
  bool _mapOpen = false;

  @override
  void initState() {
    super.initState();
    _items = context.space.milestones.watch();
  }

  @override
  void dispose() {
    _daily.dispose();
    super.dispose();
  }

  bool get _unlocked => context.read<VaultService>().key != null;

  Future<SaveOutcome> _add(String title, String date) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty || !_unlocked || _writing) return SaveOutcome.skipped;
    final space = context.space;
    _writing = true;
    try {
      await space.milestones.add(title: trimmed, date: date);
      if (mounted) {
        setState(() => _error = '');
        AppHaptics.celebration();
        fireHeartConfetti(context);
      }
      return SaveOutcome.saved;
    } catch (_) {
      return SaveOutcome.failed;
    } finally {
      _writing = false;
    }
  }

  Future<SaveOutcome> _update(MilestoneRecord moment, String title, String date) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty || !_unlocked || _writing) return SaveOutcome.skipped;
    AppHaptics.tap();
    final space = context.space;
    _writing = true;
    try {
      await space.milestones.update(moment, title: trimmed, date: date);
      if (mounted) {
        setState(() => _error = '');
        AppHaptics.celebration();
      }
      return SaveOutcome.saved;
    } catch (_) {
      return SaveOutcome.failed;
    } finally {
      _writing = false;
    }
  }

  Future<void> _delete(MilestoneRecord moment) async {
    AppHaptics.tap();
    final space = context.space;
    try {
      await space.milestones.delete(moment.id);
      if (mounted) setState(() => _error = '');
    } catch (_) {
      if (mounted) setState(() => _error = MilestoneCopy.deleteFailed);
    }
  }

  Future<void> _open([MilestoneRecord? moment]) async {
    final action = await showMomentSheet(
      context,
      moment: moment,
      onSave: moment == null ? _add : (title, date) => _update(moment, title, date),
    );
    if (action == MomentAction.removed && moment != null && mounted) await _delete(moment);
  }

  Future<void> _openMap() async {
    if (_mapOpen) return;
    _mapOpen = true;
    await openSkyMap(context, model: _daily);
    _mapOpen = false;
  }

  @override
  Widget build(BuildContext context) {
    _daily.bindTo(vault: context.watch<VaultService>(), identity: context.watch<IdentityController>());
    final night = context.sky.isNight;
    final now = DateTime.fromMillisecondsSinceEpoch(widget.counter.now());
    final start = parseLocalDate(widget.startDate) ?? now;
    return StreamBuilder<TableSnapshot<MilestoneRecord>>(
      stream: _items,
      builder: (context, snapshot) {
        final records = snapshot.data?.items ?? const <MilestoneRecord>[];
        final unreadable = snapshot.data?.unreadable ?? 0;
        final notice = MilestoneCopy.notice(error: _error, unreadable: unreadable);
        final steps = <Widget>[
          ListenableBuilder(
            key: UsKeys.todayStep,
            listenable: Listenable.merge([widget.counter, _daily]),
            builder: (context, _) => ConstellationStep(
              title: MilestoneCopy.today(widget.counter.value.totalDays),
              note: MilestoneCopy.todayStar(
                lit: _daily.visible ? _daily.bothIn : null,
                stars: _daily.stars,
                night: night,
              ),
              tone: ConstellationTone.now,
            ),
          ),
          for (final moment in records) _momentStep(moment, now),
          if (records.isEmpty)
            const ConstellationStep(
              key: UsKeys.emptyStep,
              title: MilestoneCopy.emptyTitle,
              note: MilestoneCopy.emptyNote,
              tone: ConstellationTone.waiting,
            ),
          ConstellationStep(
            key: UsKeys.beganStep,
            title: MilestoneCopy.began,
            note: MilestoneCopy.beganNote(UsDates.short(start, now)),
            onTap: widget.onChangeDay,
            semanticLabel: MilestoneCopy.changeDay,
            trailing: SkyIcon(SkyIcons.pen, size: 15, color: context.sky.faint),
          ),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SkySectionHeader(
              title: MilestoneCopy.constellation,
              action: MilestoneCopy.addMoment,
              onAction: () => unawaited(_open()),
              trailing: SkyMapLink(key: SkyMapKeys.fromUs, compact: true, onTap: () => unawaited(_openMap())),
            ),
            const SizedBox(height: 10),
            if (notice != null)
              Padding(
                padding: const EdgeInsets.only(bottom: SkySpace.md),
                child: SkyEntrance(
                  key: ValueKey<String>('moment-notice-$notice'),
                  child: SkyNotice(
                    text: notice,
                    tone: _error.isNotEmpty ? SkyNoticeTone.error : SkyNoticeTone.warning,
                  ),
                ),
              ),
            ConstellationPath(
              children: [
                for (var i = 0; i < steps.length; i++)
                  SkyEntrance(key: ValueKey<Key?>(steps[i].key), index: i, child: steps[i]),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _momentStep(MilestoneRecord moment, DateTime now) {
    final title = moment.title.isEmpty ? MilestoneCopy.fallbackTitle : moment.title;
    final date = parseLocalDate(moment.date);
    final when = date == null ? '' : UsDates.short(date, now);
    return ConstellationStep(
      key: UsKeys.moment(moment.id),
      title: title,
      note: when,
      onTap: () => unawaited(_open(moment)),
      semanticLabel: MilestoneCopy.openMoment(title, when),
    );
  }
}

class ConstellationPath extends StatelessWidget {
  const ConstellationPath({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    return Stack(
      children: [
        Positioned(
          left: 10,
          top: 10,
          bottom: 16,
          width: 1,
          child: IgnorePointer(
            child: Opacity(
              opacity: 0.6,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [t.gold, t.gold.withValues(alpha: 0)],
                  ),
                ),
              ),
            ),
          ),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: children),
      ],
    );
  }
}

enum ConstellationTone { now, star, waiting }

class ConstellationStep extends StatelessWidget {
  const ConstellationStep({
    super.key,
    required this.title,
    required this.note,
    this.tone = ConstellationTone.star,
    this.onTap,
    this.semanticLabel,
    this.trailing,
  });

  final String title;
  final String note;
  final ConstellationTone tone;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final waiting = tone == ConstellationTone.waiting;
    final body = Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 30,
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 4, top: 2),
                child: StarDot(tone: tone),
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: SkyType.sans(14, weight: FontWeight.w700, height: 1.3).copyWith(
                    color: waiting ? t.muted : t.text,
                  ),
                ),
                if (note.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(note, style: SkyType.sans(12, height: 1.4).copyWith(color: waiting ? t.faint : t.muted)),
                ],
              ],
            ),
          ),
          if (trailing != null) Padding(padding: const EdgeInsets.only(left: 8, top: 2), child: trailing),
        ],
      ),
    );
    final label = semanticLabel ?? (note.isEmpty ? title : '$title, $note');
    if (onTap == null) return Semantics(container: true, label: label, excludeSemantics: true, child: body);
    return SkyPressable(onTap: onTap, pressedScale: 0.98, semanticLabel: label, excludeSemantics: true, child: body);
  }
}

class StarDot extends StatefulWidget {
  const StarDot({super.key, this.tone = ConstellationTone.star});

  static const double size = 12;

  final ConstellationTone tone;

  @override
  State<StarDot> createState() => _StarDotState();
}

class _StarDotState extends State<StarDot> with TickerProviderStateMixin {
  AnimationController? _breath;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant StarDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final breathe = widget.tone == ConstellationTone.now && skyMotionAllowed(context);
    if (breathe && _breath == null) {
      _breath = AnimationController(vsync: this, duration: SkyMotion.presence ~/ 2)..repeat(reverse: true);
    } else if (!breathe && _breath != null) {
      _breath!.dispose();
      _breath = null;
    }
  }

  @override
  void dispose() {
    _breath?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    switch (widget.tone) {
      case ConstellationTone.star:
        return Container(
          width: StarDot.size,
          height: StarDot.size,
          decoration: BoxDecoration(
            color: t.gold,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: t.gold.withValues(alpha: t.isNight ? 0.9 : 0.6), blurRadius: 12)],
          ),
        );
      case ConstellationTone.waiting:
        return Container(
          width: StarDot.size,
          height: StarDot.size,
          decoration: BoxDecoration(
            color: t.page,
            shape: BoxShape.circle,
            border: Border.all(color: t.faint, width: 1.5),
          ),
        );
      case ConstellationTone.now:
        final breath = _breath;
        Widget dot(double v) => Container(
          width: StarDot.size,
          height: StarDot.size,
          decoration: BoxDecoration(
            color: t.rose,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: t.roseSoft, spreadRadius: 4 + 2 * v),
              BoxShadow(color: t.rose.withValues(alpha: 0.55 + 0.45 * v), blurRadius: 14),
            ],
          ),
        );
        if (breath == null) return dot(1);
        return RepaintBoundary(
          child: AnimatedBuilder(
            animation: breath,
            builder: (context, _) => dot(Curves.easeInOut.transform(breath.value)),
          ),
        );
    }
  }
}
