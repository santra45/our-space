import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/engine.dart';
import '../../../sky/sky.dart';
import '../../../space_scope.dart';
import '../../../widgets/app_haptics.dart';
import 'settings_row.dart';
import 'sheet_parts.dart';

abstract final class GentleCopy {
  static const String title = 'Gentle reminders';
  static const String subtitle = 'Set by this phone for itself. Nothing leaves the phone to make them.';
  static const String allOff = 'All off for now';
  static const String question = "Today's question";
  static const String questionHint = 'If you have not answered by';
  static const String letters = 'A letter opens';
  static const String lettersHint = 'The morning a sealed letter is ready';
  static const String countdown = 'A countdown day';
  static const String countdownHint = 'The morning you have been counting down to';
  static const String together = 'Monthsaries';
  static const String togetherHint = 'Each month on the day it all began';
  static const String memories = 'On this day';
  static const String memoriesHint = 'A polaroid from this day in an earlier year';
  static const String fromYou = 'From you';
  static const String readTitle = 'Ring them when I read a letter';
  static const String readHint = 'Their phone gets a little note the moment you open one of their letters';
  static const String blocked = 'Notifications are off for Our Space on this phone. Tap here to allow them.';
  static const String pickTime = 'Remind me at';
  static const String save = 'Save';
  static const String cancel = 'Cancel';

  static String someOn(int count) => count == 1 ? '1 is on' : '$count are on';

  static String readTitleFor(String partner) {
    final name = partner.trim();
    return name.isEmpty ? readTitle : 'Ring $name when I read a letter';
  }
}

String gentleTime(BuildContext context, int minutes) =>
    MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60));

Future<void> showGentleReminders(BuildContext context) {
  return showSkySheet<void>(context: context, builder: (_) => const GentleRemindersSheet());
}

class GentleRemindersRow extends StatelessWidget {
  const GentleRemindersRow({super.key, required this.reminders});

  final ReminderService reminders;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: reminders,
      builder: (context, _) {
        final on = reminders.enabled.length;
        return SettingsRow(
          icon: SkyIcons.clock,
          tone: SkyTone.lavender,
          title: GentleCopy.title,
          subtitle: on == 0 ? GentleCopy.allOff : GentleCopy.someOn(on),
          onTap: () => unawaited(showGentleReminders(context)),
        );
      },
    );
  }
}

class GentleRemindersSheet extends StatefulWidget {
  const GentleRemindersSheet({super.key});

  static Key toggleKey(ReminderKind kind) => ValueKey<String>('gentle-${kind.name}');
  static const Key timeKey = ValueKey<String>('gentle-time');
  static const Key readKey = ValueKey<String>('gentle-read');
  static const Key blockedKey = ValueKey<String>('gentle-blocked');

  @override
  State<GentleRemindersSheet> createState() => _GentleRemindersSheetState();
}

class _GentleRemindersSheetState extends State<GentleRemindersSheet> with WidgetsBindingObserver {
  late final ReminderService _reminders = context.read<ReminderService>();
  late final RingNotes _rings = context.space.store.ringNotes;
  late bool _tellsRead = _rings.tellsOpened;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_reminders.refreshAllowed());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_reminders.refreshAllowed());
  }

  Future<void> _toggle(ReminderKind kind) async {
    AppHaptics.tap();
    final on = !_reminders.isOn(kind);
    await _reminders.setOn(kind, on);
    if (on && _reminders.allowed != true) await _reminders.askToNotify();
  }

  Future<void> _pickTime() async {
    final current = _reminders.questionMinutes;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
      helpText: GentleCopy.pickTime,
      confirmText: GentleCopy.save,
      cancelText: GentleCopy.cancel,
      builder: (context, child) => SkyTheme(child: child ?? const SizedBox.shrink()),
    );
    if (picked == null || !mounted) return;
    await _reminders.setQuestionMinutes(picked.hour * 60 + picked.minute);
  }

  Future<void> _toggleRead() async {
    AppHaptics.tap();
    final on = !_tellsRead;
    await _rings.setTellsOpened(on);
    if (mounted) setState(() => _tellsRead = on);
  }

  Widget _row(ReminderKind kind, {required SkyIcons icon, required SkyTone tone, required String title, required String hint}) {
    final on = _reminders.isOn(kind);
    return SettingsRow(
      icon: icon,
      tone: tone,
      title: title,
      subtitle: hint,
      onTap: () => unawaited(_toggle(kind)),
      trailing: SkyToggle(
        key: GentleRemindersSheet.toggleKey(kind),
        value: on,
        semanticLabel: title,
        onChanged: (_) => unawaited(_toggle(kind)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final partner = context.watch<IdentityController>().partnerName;
    return ListenableBuilder(
      listenable: _reminders,
      builder: (context, _) {
        final questionOn = _reminders.isOn(ReminderKind.question);
        final blocked = _reminders.enabled.isNotEmpty && _reminders.allowed == false;
        return SheetScroll(
          children: [
            SheetHeader(
              title: GentleCopy.title,
              subtitle: GentleCopy.subtitle,
              icon: SkyIcons.clock,
              tone: SkyTone.lavender,
              onClose: () => Navigator.of(context).maybePop(),
            ),
            if (blocked)
              SkyPressable(
                key: GentleRemindersSheet.blockedKey,
                onTap: () => unawaited(_reminders.askToNotify()),
                semanticLabel: GentleCopy.blocked,
                child: const SkyNotice(text: GentleCopy.blocked, tone: SkyNoticeTone.warning),
              ),
            SkyListGroup(
              children: [
                SettingsRow(
                  icon: SkyIcons.star,
                  tone: SkyTone.gold,
                  title: GentleCopy.question,
                  subtitle: questionOn
                      ? '${GentleCopy.questionHint} ${gentleTime(context, _reminders.questionMinutes)}'
                      : GentleCopy.questionHint,
                  onTap: () => unawaited(_toggle(ReminderKind.question)),
                  trailing: SkyToggle(
                    key: GentleRemindersSheet.toggleKey(ReminderKind.question),
                    value: questionOn,
                    semanticLabel: GentleCopy.question,
                    onChanged: (_) => unawaited(_toggle(ReminderKind.question)),
                  ),
                ),
                if (questionOn)
                  SettingsRow(
                    key: GentleRemindersSheet.timeKey,
                    icon: SkyIcons.clock,
                    tone: SkyTone.gold,
                    title: GentleCopy.pickTime,
                    value: gentleTime(context, _reminders.questionMinutes),
                    onTap: () => unawaited(_pickTime()),
                  ),
                _row(
                  ReminderKind.letters,
                  icon: SkyIcons.letter,
                  tone: SkyTone.rose,
                  title: GentleCopy.letters,
                  hint: GentleCopy.lettersHint,
                ),
                _row(
                  ReminderKind.countdown,
                  icon: SkyIcons.calendar,
                  tone: SkyTone.gold,
                  title: GentleCopy.countdown,
                  hint: GentleCopy.countdownHint,
                ),
                _row(
                  ReminderKind.together,
                  icon: SkyIcons.heart,
                  tone: SkyTone.rose,
                  title: GentleCopy.together,
                  hint: GentleCopy.togetherHint,
                ),
                _row(
                  ReminderKind.memories,
                  icon: SkyIcons.photo,
                  tone: SkyTone.lavender,
                  title: GentleCopy.memories,
                  hint: GentleCopy.memoriesHint,
                ),
              ],
            ),
            Text(GentleCopy.fromYou, style: SkyType.small.copyWith(color: t.muted)),
            SkyListGroup(
              children: [
                SettingsRow(
                  icon: SkyIcons.eye,
                  tone: SkyTone.rose,
                  title: GentleCopy.readTitleFor(partner),
                  subtitle: GentleCopy.readHint,
                  onTap: () => unawaited(_toggleRead()),
                  trailing: SkyToggle(
                    key: GentleRemindersSheet.readKey,
                    value: _tellsRead,
                    semanticLabel: GentleCopy.readTitle,
                    onChanged: (_) => unawaited(_toggleRead()),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
