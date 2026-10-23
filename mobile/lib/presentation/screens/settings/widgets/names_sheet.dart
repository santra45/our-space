import 'package:animations/animations.dart' show SharedAxisTransitionType;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/engine.dart';
import '../../../sky/sky.dart';
import '../../../widgets/app_haptics.dart';
import 'settings_field.dart';
import 'sheet_parts.dart';

abstract final class NamesCopy {
  static const String title = 'Names';
  static const String subtitle = 'Who is who on your two phones';
  static const String thisPhone = 'this phone';
  static const String noNameYet = 'No name yet';
  static const String imThisOne = 'I\'m this one';
  static const String yourName = 'Your name';
  static const String theirName = 'Their name';
  static const String save = 'Save';
  static const String cancel = 'Cancel';
  static const String swappedLink = 'Names or answers look swapped?';
  static const String swapTitle = 'Swap us back?';
  static const String swapAction = 'Swap us back';
  static const String swapped = 'Swapped back. Your answers are where they belong again.';
  static const String swapFailed = 'That did not work, and nothing was changed. Try again in a moment.';
  static const String claimFailed = 'That did not work, and nothing was changed. Try again in a moment.';
  static const String tooMany =
      'More than two people are in here, which should not happen. Pick yourself and ask the other phone to do the same.';
  static const String sealed = 'Your names stay locked inside Our Space, and only ever appear on your two phones.';

  static const Map<String, String> pronounLabels = {'she': 'she / her', 'he': 'he / him', 'they': 'they / them'};

  static String pronounLabel(String? pronoun) => pronounLabels[pronoun] ?? pronounLabels['they']!;

  static String editLabel(Person person) => 'Edit ${_or(person.name, 'this person')}';

  static String claimTitle(Person partner) => 'Make this phone ${_or(partner.name, 'the other one')}?';

  static String claimBody(Person me) =>
      'Answers already written on this phone stay with ${_or(me.name, 'you')}. If your names just look swapped, use “Swap us back” instead.';

  static String claimConfirm(Person partner) => 'Yes, I\'m ${_or(partner.name, 'this one')}';

  static String swapBody(Person me, Person partner, String? since) {
    final moved = since == null ? '' : ' Answers written since $since move with them.';
    return '${_or(me.name, 'You')} and ${_or(partner.name, 'your partner')} trade places, along with which phone is whose.$moved Do this on one phone only. The other one follows by itself the next time you two connect.';
  }

  static String _or(String value, String fallback) => value.isEmpty ? fallback : value;
}

String formatNamesMoment(BuildContext context, int ms) {
  final date = DateTime.fromMillisecondsSinceEpoch(ms);
  final localizations = MaterialLocalizations.of(context);
  return '${localizations.formatMediumDate(date)}, ${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(date))}';
}

Future<void> showNamesSheet(BuildContext context) {
  return showSkySheet<void>(context: context, builder: (_) => const NamesSheet());
}

class NamesSheet extends StatefulWidget {
  const NamesSheet({super.key});

  @override
  State<NamesSheet> createState() => _NamesSheetState();
}

class _NamesSheetState extends State<NamesSheet> {
  final TextEditingController _name = TextEditingController();
  String? _editing;
  String _pronoun = defaultPronoun;
  SettingsNote? _note;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _startEdit(Person person) {
    AppHaptics.tap();
    setState(() {
      _note = null;
      _editing = person.personId;
      _name.text = person.name;
      _pronoun = pronouns.contains(person.pronoun) ? person.pronoun : defaultPronoun;
    });
  }

  void _stopEdit() {
    AppHaptics.tap();
    setState(() => _editing = null);
  }

  Future<void> _commit(IdentityController identity) async {
    final editing = _editing;
    if (editing == null) return;
    await identity.savePerson(editing, name: _name.text, pronoun: _pronoun);
    if (!mounted) return;
    setState(() => _editing = null);
  }

  Future<void> _claim(IdentityController identity, Person me, Person partner) async {
    setState(() => _note = null);
    final yes = await showSkyConfirm(
      context,
      title: NamesCopy.claimTitle(partner),
      message: NamesCopy.claimBody(me),
      confirmLabel: NamesCopy.claimConfirm(partner),
      cancelLabel: NamesCopy.cancel,
      icon: SkyIcons.phone,
    );
    if (!yes || !mounted) return;
    AppHaptics.tap();
    final ok = await identity.claimPerson(partner.personId);
    if (!mounted) return;
    if (!ok) setState(() => _note = const SettingsNote.error(NamesCopy.claimFailed));
  }

  Future<void> _swap(IdentityController identity, Person me, Person partner, int? traded) async {
    setState(() => _note = null);
    final since = traded == null ? null : formatNamesMoment(context, traded);
    final yes = await showSkyConfirm(
      context,
      title: NamesCopy.swapTitle,
      message: NamesCopy.swapBody(me, partner, since),
      confirmLabel: NamesCopy.swapAction,
      cancelLabel: NamesCopy.cancel,
      icon: SkyIcons.us,
    );
    if (!yes || !mounted) return;
    AppHaptics.tap();
    final ok = await identity.swapUsBack();
    if (!mounted) return;
    if (ok) {
      AppHaptics.celebration();
      setState(() => _note = const SettingsNote(NamesCopy.swapped));
    } else {
      setState(() => _note = const SettingsNote.error(NamesCopy.swapFailed));
    }
  }

  Widget _editor(Person person, bool isMe, IdentityController identity) {
    final t = context.sky;
    final canSave = !identity.busy && _name.text.trim().isNotEmpty;
    return Container(
      key: ValueKey<String>('edit-${person.personId}'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: SkyRadii.all(SkyRadii.tile),
        border: Border.all(color: t.isNight ? t.gold.withValues(alpha: 0.3) : t.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsField(
            controller: _name,
            hint: isMe ? NamesCopy.yourName : NamesCopy.theirName,
            maxLength: maxNameLength,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) {
              if (canSave) _commit(identity);
            },
          ),
          const SizedBox(height: SkySpace.md),
          Row(
            children: [
              for (var i = 0; i < pronouns.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: SkyChip(
                    label: NamesCopy.pronounLabel(pronouns[i]),
                    tone: _pronoun == pronouns[i] ? SkyChipTone.on : SkyChipTone.plain,
                    dense: true,
                    onTap: () => setState(() => _pronoun = pronouns[i]),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: SkySpace.md),
          Row(
            children: [
              Expanded(
                child: SkyButton(
                  label: NamesCopy.cancel,
                  variant: SkyButtonVariant.ghost,
                  height: SkySizes.buttonCompact,
                  onPressed: _stopEdit,
                ),
              ),
              const SizedBox(width: SkySpace.sm),
              Expanded(
                child: SkyButton(
                  label: NamesCopy.save,
                  icon: SkyIcons.check,
                  variant: SkyButtonVariant.gold,
                  height: SkySizes.buttonCompact,
                  onPressed: canSave ? () => _commit(identity) : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(Person person, bool isMe, Person? me, IdentityController identity) {
    final t = context.sky;
    final name = person.name.isEmpty ? NamesCopy.noNameYet : person.name;
    return Padding(
      key: ValueKey<String>('row-${person.personId}'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          SkyAvatar(
            initial: SkyAvatar.initialOf(person.name, fallback: isMe ? 'O' : 'S'),
            style: isMe ? SkyAvatarStyle.me : SkyAvatarStyle.partner,
            size: 36,
            semanticLabel: name,
          ),
          const SizedBox(width: SkySpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SkyType.bodyStrong.copyWith(color: person.name.isEmpty ? t.muted : t.text),
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: SkySpace.sm),
                      const SkyChip(label: NamesCopy.thisPhone, tone: SkyChipTone.rose, dense: true),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(NamesCopy.pronounLabel(person.pronoun), style: SkyType.small.copyWith(color: t.muted)),
              ],
            ),
          ),
          if (!isMe && me != null) ...[
            const SizedBox(width: SkySpace.sm),
            TextAction(
              label: NamesCopy.imThisOne,
              color: t.lavender,
              small: true,
              underline: true,
              enabled: !identity.busy,
              onTap: () => _claim(identity, me, person),
            ),
          ],
          const SizedBox(width: SkySpace.sm),
          SkyIconButton(
            icon: SkyIcons.pen,
            semanticLabel: NamesCopy.editLabel(person),
            tone: SkyIconButtonTone.ghost,
            size: 34,
            iconSize: 15,
            onPressed: () => _startEdit(person),
          ),
        ],
      ),
    );
  }

  Widget _person(Person person, bool isMe, Person? me, IdentityController identity) {
    final editing = _editing == person.personId;
    return SkySharedAxisSwitcher(
      axis: SharedAxisTransitionType.vertical,
      child: editing
          ? Padding(
              key: ValueKey<String>('editor-${person.personId}'),
              padding: const EdgeInsets.all(SkySpace.sm),
              child: _editor(person, isMe, identity),
            )
          : KeyedSubtree(key: ValueKey<String>('view-${person.personId}'), child: _row(person, isMe, me, identity)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final identity = context.watch<IdentityController>();
    final me = identity.me;
    if (identity.status != IdentityStatus.ready || me == null) {
      return const SheetScroll(
        children: [SheetHeader(title: NamesCopy.title, subtitle: NamesCopy.subtitle)],
      );
    }
    final partner = identity.partner;
    final people = identity.everyone;
    final pair = partner != null && people.length == 2;
    final traded = tradedPlacesAt(people);
    final note = _note;

    return SheetScroll(
      children: [
        const SheetHeader(title: NamesCopy.title, subtitle: NamesCopy.subtitle, icon: SkyIcons.pen, tone: SkyTone.rose),
        SkyListGroup(
          children: [_person(me, true, me, identity), if (partner != null) _person(partner, false, me, identity)],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (pair)
              Align(
                alignment: Alignment.centerLeft,
                child: TextAction(
                  label: NamesCopy.swappedLink,
                  icon: SkyIcons.refresh,
                  color: t.muted,
                  small: true,
                  onTap: () => _swap(identity, me, partner, traded),
                ),
              ),
            SettingsNotes(
              notes: [if (note != null) note],
              top: SkySpace.sm,
              onDismiss: (_) => setState(() => _note = null),
            ),
            const SizedBox(height: SkySpace.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: SkyIcon(people.length > 2 ? SkyIcons.alert : SkyIcons.lock, size: 12, color: t.faint),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    people.length > 2 ? NamesCopy.tooMany : NamesCopy.sealed,
                    style: SkyType.caption.copyWith(color: t.faint, height: 1.45),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
