import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/engine.dart';
import '../../sky/sky.dart';
import '../../widgets/app_haptics.dart';
import 'widgets/people_sheet.dart';
import 'widgets/pronoun_picker.dart';

abstract final class WhoIsWhoCopy {
  static const String title = 'Who is who';
  static const String sheetLabel = 'The two of us';
  static const String sheetBody = 'Your names, and which one of you this phone belongs to.';
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
  static const String tooMany =
      'More than two people are in here, which should not happen. Pick yourself and tell the other phone to do the same.';
  static const String sealed = 'Your names stay sealed like everything else, and only ever appear on your two phones.';

  static const Map<String, String> pronounLabels = {
    'she': 'she / her',
    'he': 'he / him',
    'they': 'they / them',
  };

  static String pronounLabel(String? pronoun) => pronounLabels[pronoun] ?? pronounLabels['they']!;

  static String editLabel(Person person) => 'Edit ${_or(person.name, 'this person')}';

  static String claimTitle(Person partner) => 'Make this phone ${_or(partner.name, 'the other one')}?';

  static String claimBody(Person me) =>
      'Answers already written on this phone stay with ${_or(me.name, 'you')}. If your names just look swapped, use “Swap us back” below instead.';

  static String claimConfirm(Person partner) => 'Yes, I\'m ${_or(partner.name, 'this one')}';

  static String swapBody(Person me, Person partner, String? since) {
    final moved = since == null ? '' : ' Answers written since $since move with them.';
    return '${_or(me.name, 'You')} and ${_or(partner.name, 'your partner')} trade places, along with which phone is whose.$moved Do this on one phone only. The other one follows by itself the next time the two of you catch up.';
  }

  static String _or(String value, String fallback) => value.isEmpty ? fallback : value;
}

String formatSwapMoment(BuildContext context, int ms) {
  final date = DateTime.fromMillisecondsSinceEpoch(ms);
  final localizations = MaterialLocalizations.of(context);
  return '${localizations.formatMediumDate(date)}, ${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(date))}';
}

Future<void> showWhoIsWhoSheet(BuildContext context) {
  return showSkySheet<void>(
    context: context,
    builder: (sheetContext) => const SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          PeopleSheetHeader(
            label: WhoIsWhoCopy.sheetLabel,
            icon: SkyIcons.us,
            tone: SkyTone.rose,
            title: WhoIsWhoCopy.title,
            body: WhoIsWhoCopy.sheetBody,
          ),
          SizedBox(height: SkySpace.lg),
          WhoIsWho(framed: false),
        ],
      ),
    ),
  );
}

class WhoIsWho extends StatefulWidget {
  const WhoIsWho({super.key, this.framed = true});

  final bool framed;

  @override
  State<WhoIsWho> createState() => _WhoIsWhoState();
}

class _WhoIsWhoState extends State<WhoIsWho> {
  final TextEditingController _name = TextEditingController();
  String? _editing;
  String _pronoun = defaultPronoun;
  String? _confirmClaim;
  bool _swapOpen = false;
  String _swapNote = '';
  bool _swapWorked = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _startEdit(Person person) {
    AppHaptics.tap();
    setState(() {
      _editing = person.personId;
      _name.text = person.name;
      _pronoun = pronouns.contains(person.pronoun) ? person.pronoun : defaultPronoun;
    });
  }

  Future<void> _commit(IdentityController identity) async {
    final editing = _editing;
    if (editing == null) return;
    await identity.savePerson(editing, name: _name.text, pronoun: _pronoun);
    if (!mounted) return;
    setState(() => _editing = null);
  }

  Future<void> _claim(IdentityController identity) async {
    final target = _confirmClaim;
    if (target == null) return;
    AppHaptics.tap();
    final ok = await identity.claimPerson(target);
    if (!mounted) return;
    if (ok) setState(() => _confirmClaim = null);
  }

  Future<void> _swap(IdentityController identity) async {
    AppHaptics.tap();
    final ok = await identity.swapUsBack();
    if (!mounted) return;
    if (ok) {
      AppHaptics.celebration();
      setState(() {
        _swapOpen = false;
        _swapWorked = true;
        _swapNote = WhoIsWhoCopy.swapped;
      });
    } else {
      setState(() {
        _swapWorked = false;
        _swapNote = WhoIsWhoCopy.swapFailed;
      });
    }
  }

  Widget _editRow(Person person, bool isMe, IdentityController identity) {
    final t = context.sky;
    final canSave = !identity.busy && _name.text.trim().isNotEmpty;
    return Container(
      key: ValueKey('edit-${person.personId}'),
      padding: const EdgeInsets.all(SkySpace.md),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: SkyRadii.all(SkyRadii.tile),
        border: Border.all(color: t.roseBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SkyTextField(
            controller: _name,
            hint: isMe ? WhoIsWhoCopy.yourName : WhoIsWhoCopy.theirName,
            maxLength: maxNameLength,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) {
              if (canSave) _commit(identity);
            },
          ),
          const SizedBox(height: SkySpace.sm + 2),
          PronounPicker(dense: true, value: _pronoun, onChanged: (value) => setState(() => _pronoun = value)),
          const SizedBox(height: SkySpace.md),
          Row(
            children: [
              Expanded(
                child: SkyButton(
                  label: WhoIsWhoCopy.save,
                  icon: SkyIcons.check,
                  variant: SkyButtonVariant.gold,
                  height: 40,
                  onPressed: canSave ? () => _commit(identity) : null,
                ),
              ),
              const SizedBox(width: SkySpace.sm + 2),
              Expanded(
                child: SkyButton(
                  label: WhoIsWhoCopy.cancel,
                  variant: SkyButtonVariant.ghost,
                  height: 40,
                  onPressed: () {
                    AppHaptics.tap();
                    setState(() => _editing = null);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(Person person, bool isMe, IdentityController identity) {
    if (_editing == person.personId) return _editRow(person, isMe, identity);
    final t = context.sky;
    return Container(
      key: ValueKey('row-${person.personId}'),
      padding: const EdgeInsets.fromLTRB(SkySpace.md, 10, 10, 10),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: SkyRadii.all(SkyRadii.tile),
        border: Border.all(color: t.hairline),
      ),
      child: Row(
        children: [
          SkyAvatar(
            initial: SkyAvatar.initialOf(person.name, fallback: ''),
            style: isMe ? SkyAvatarStyle.me : SkyAvatarStyle.partner,
            size: 36,
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
                        person.name.isEmpty ? WhoIsWhoCopy.noNameYet : person.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SkyType.bodyStrong.copyWith(color: person.name.isEmpty ? t.muted : t.text),
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: SkySpace.sm),
                      const SkyChip(label: WhoIsWhoCopy.thisPhone, tone: SkyChipTone.rose, dense: true),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(WhoIsWhoCopy.pronounLabel(person.pronoun), style: SkyType.small.copyWith(color: t.muted)),
              ],
            ),
          ),
          if (!isMe) ...[
            const SizedBox(width: SkySpace.sm),
            PeopleTextLink(
              label: WhoIsWhoCopy.imThisOne,
              color: t.rose,
              size: 12,
              enabled: !identity.busy,
              onTap: () {
                AppHaptics.tap();
                setState(() {
                  _swapOpen = false;
                  _confirmClaim = person.personId;
                });
              },
            ),
          ],
          const SizedBox(width: SkySpace.sm),
          SkyIconButton(
            icon: SkyIcons.pen,
            semanticLabel: WhoIsWhoCopy.editLabel(person),
            tone: SkyIconButtonTone.ghost,
            size: 32,
            iconSize: 15,
            iconColor: t.muted,
            onPressed: () => _startEdit(person),
          ),
        ],
      ),
    );
  }

  Widget _panel({
    required Key key,
    required SkyTone tone,
    required SkyIcons icon,
    required String title,
    required String body,
    required Widget confirm,
    required VoidCallback onCancel,
  }) {
    final t = context.sky;
    final accent = tone.foreground(t);
    return SkyEntrance(
      key: key,
      offset: const Offset(0, 8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Color.alphaBlend(tone.background(t), t.surface),
          borderRadius: SkyRadii.all(SkyRadii.tile),
          border: Border.all(color: accent.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: SkyIcon(icon, size: 17, color: accent),
                ),
                const SizedBox(width: SkySpace.sm + 2),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(title, style: SkyType.bodyStrong.copyWith(color: t.text)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(body, style: SkyType.bodySmall.copyWith(color: t.muted, height: 1.45)),
            const SizedBox(height: SkySpace.md),
            Row(
              children: [
                Expanded(flex: 3, child: confirm),
                const SizedBox(width: SkySpace.sm + 2),
                Expanded(
                  flex: 2,
                  child: SkyButton(
                    label: WhoIsWhoCopy.cancel,
                    variant: SkyButtonVariant.ghost,
                    height: 40,
                    onPressed: onCancel,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final identity = context.watch<IdentityController>();
    final me = identity.me;
    if (identity.status != IdentityStatus.ready || me == null) return const SizedBox.shrink();
    final t = context.sky;
    final partner = identity.partner;
    final people = identity.everyone;
    final pair = partner != null && people.length == 2;
    final traded = tradedPlacesAt(people);

    final children = <Widget>[
      if (widget.framed) ...[
        const SkyLabel(WhoIsWhoCopy.title, icon: SkyIcons.us),
        const SizedBox(height: SkySpace.md),
      ],
      _row(me, true, identity),
      if (partner != null) ...[
        const SizedBox(height: SkySpace.sm),
        _row(partner, false, identity),
      ],
      if (partner != null && _confirmClaim == partner.personId) ...[
        const SizedBox(height: SkySpace.sm + 2),
        _panel(
          key: ValueKey('claim-${partner.personId}'),
          tone: SkyTone.gold,
          icon: SkyIcons.phone,
          title: WhoIsWhoCopy.claimTitle(partner),
          body: WhoIsWhoCopy.claimBody(me),
          confirm: SkyButton(
            label: WhoIsWhoCopy.claimConfirm(partner),
            variant: SkyButtonVariant.gold,
            height: 40,
            onPressed: identity.busy ? null : () => _claim(identity),
          ),
          onCancel: () {
            AppHaptics.tap();
            setState(() => _confirmClaim = null);
          },
        ),
      ],
      if (pair && !_swapOpen) ...[
        const SizedBox(height: SkySpace.xs),
        Align(
          alignment: Alignment.centerLeft,
          child: PeopleTextLink(
            label: WhoIsWhoCopy.swappedLink,
            size: 12,
            underline: true,
            align: TextAlign.start,
            onTap: () {
              AppHaptics.tap();
              setState(() {
                _confirmClaim = null;
                _swapNote = '';
                _swapOpen = true;
              });
            },
          ),
        ),
      ],
      if (pair && _swapOpen) ...[
        const SizedBox(height: SkySpace.sm + 2),
        _panel(
          key: const ValueKey('swap-panel'),
          tone: SkyTone.lavender,
          icon: SkyIcons.refresh,
          title: WhoIsWhoCopy.swapTitle,
          body: WhoIsWhoCopy.swapBody(me, partner, traded == null ? null : formatSwapMoment(context, traded)),
          confirm: SkyButton(
            label: WhoIsWhoCopy.swapAction,
            variant: SkyButtonVariant.gold,
            height: 40,
            onPressed: identity.busy ? null : () => _swap(identity),
          ),
          onCancel: () {
            AppHaptics.tap();
            setState(() => _swapOpen = false);
          },
        ),
      ],
      if (_swapNote.isNotEmpty) ...[
        const SizedBox(height: SkySpace.sm),
        SkyEntrance(
          key: ValueKey('note-$_swapNote'),
          offset: const Offset(0, 8),
          child: SkyNotice(
            text: _swapNote,
            tone: _swapWorked ? SkyNoticeTone.love : SkyNoticeTone.error,
          ),
        ),
      ],
      const SizedBox(height: SkySpace.md),
      if (people.length > 2)
        const SkyNotice(text: WhoIsWhoCopy.tooMany, tone: SkyNoticeTone.warning)
      else
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: SkyIcon(SkyIcons.lock, size: 12, color: t.faint),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(WhoIsWhoCopy.sealed, style: SkyType.caption.copyWith(color: t.faint, height: 1.45)),
            ),
          ],
        ),
    ];

    Widget body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
    if (skyMotionAllowed(context)) {
      body = AnimatedSize(
        duration: SkyMotion.base,
        curve: SkyMotion.standard,
        alignment: Alignment.topCenter,
        child: body,
      );
    }
    if (!widget.framed) return SkyTheme(child: body);
    return SkyTheme(
      child: Padding(
        padding: const EdgeInsets.only(bottom: SkySpace.lg),
        child: SkyCard(padding: const EdgeInsets.all(14), child: body),
      ),
    );
  }
}
