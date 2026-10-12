import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/engine.dart';
import '../../widgets/our_widgets.dart';

abstract final class WhoIsWhoCopy {
  static const String title = 'Who is who';
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
  static const String swapped = 'Swapped back. Your answers are where they belong again 💕';
  static const String swapFailed = 'That did not work, and nothing was changed. Try again in a moment.';
  static const String tooMany =
      'More than two people are in here, which should not happen. Pick yourself and tell the other phone to do the same.';
  static const String sealed =
      'Names are sealed in your vault like everything else, and only ever appear on your two phones.';

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
    return '${_or(me.name, 'You')} and ${_or(partner.name, 'your partner')} trade places, along with which phone is whose.$moved Do this on one phone only. The other one follows by itself the next time it syncs.';
  }

  static String _or(String value, String fallback) => value.isEmpty ? fallback : value;
}

String formatSwapMoment(BuildContext context, int ms) {
  final date = DateTime.fromMillisecondsSinceEpoch(ms);
  final localizations = MaterialLocalizations.of(context);
  return '${localizations.formatMediumDate(date)}, ${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(date))}';
}

class WhoIsWho extends StatefulWidget {
  const WhoIsWho({super.key});

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
        _swapNote = WhoIsWhoCopy.swapped;
      });
    } else {
      setState(() => _swapNote = WhoIsWhoCopy.swapFailed);
    }
  }

  Widget _editRow(Person person, bool isMe, IdentityController identity) {
    final canSave = !identity.busy && _name.text.trim().isNotEmpty;
    return CssBox(
      key: ValueKey('edit-${person.personId}'),
      padding: const EdgeInsets.all(10),
      color: AppColors.white,
      border: Border.all(color: AppColors.lavender200),
      borderRadius: AppRadii.all(AppRadii.x2l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OurTextField(
            controller: _name,
            style: OurFieldStyle.soft.copyWith(
              radius: AppRadii.xl,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            hint: isMe ? WhoIsWhoCopy.yourName : WhoIsWhoCopy.theirName,
            maxLength: maxNameLength,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) {
              if (canSave) _commit(identity);
            },
            semanticLabel: isMe ? WhoIsWhoCopy.yourName : WhoIsWhoCopy.theirName,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (var i = 0; i < pronouns.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(child: _pronounChip(pronouns[i])),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _Action(
                label: WhoIsWhoCopy.save,
                icon: AppIcons.check,
                color: AppColors.emerald700,
                enabled: canSave,
                onTap: () => _commit(identity),
              ),
              const SizedBox(width: 12),
              _Action(
                label: WhoIsWhoCopy.cancel,
                color: AppColors.slate400,
                onTap: () {
                  AppHaptics.tap();
                  setState(() => _editing = null);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pronounChip(String pronoun) {
    final selected = _pronoun == pronoun;
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _pronoun = pronoun),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: selected ? AppColors.lavender500 : AppColors.lavender50,
            borderRadius: AppRadii.all(AppRadii.lg),
          ),
          child: Text(
            WhoIsWhoCopy.pronounLabel(pronoun),
            textAlign: TextAlign.center,
            style: Tw.px10.bold.c(selected ? AppColors.white : AppColors.lavender600),
          ),
        ),
      ),
    );
  }

  Widget _row(Person person, bool isMe, IdentityController identity) {
    if (_editing == person.personId) return _editRow(person, isMe, identity);
    return CssBox(
      key: ValueKey('row-${person.personId}'),
      padding: const EdgeInsets.all(10),
      color: AppColors.white,
      border: Border.all(color: AppColors.slate200.withValues(alpha: 0.7)),
      borderRadius: AppRadii.all(AppRadii.x2l),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                LucideIcon(AppIcons.userRound, size: 14, color: isMe ? AppColors.blush400 : AppColors.lavender400),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    person.name.isEmpty ? WhoIsWhoCopy.noNameYet : person.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Tw.xs.bold.c(AppColors.slate700),
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 8),
                  CssBox(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    color: AppColors.blush50,
                    border: Border.all(color: AppColors.blush100),
                    borderRadius: AppRadii.all(AppRadii.full),
                    child: Text(WhoIsWhoCopy.thisPhone, style: Tw.px9.bold.c(AppColors.blush600)),
                  ),
                ],
                const SizedBox(width: 8),
                Text(WhoIsWhoCopy.pronounLabel(person.pronoun), style: Tw.px10.c(AppColors.slate400)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (!isMe) ...[
            _Action(
              label: WhoIsWhoCopy.imThisOne,
              color: AppColors.lavender600,
              small: true,
              underline: true,
              enabled: !identity.busy,
              onTap: () {
                AppHaptics.tap();
                setState(() {
                  _swapOpen = false;
                  _confirmClaim = person.personId;
                });
              },
            ),
            const SizedBox(width: 8),
          ],
          Semantics(
            button: true,
            label: WhoIsWhoCopy.editLabel(person),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _startEdit(person),
              child: CssBox(
                width: 24,
                height: 24,
                color: AppColors.slate100,
                borderRadius: AppRadii.all(AppRadii.full),
                child: const Center(child: LucideIcon(AppIcons.pencil, size: 12, color: AppColors.slate500)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final identity = context.watch<IdentityController>();
    final me = identity.me;
    if (identity.status != IdentityStatus.ready || me == null) return const SizedBox.shrink();
    final partner = identity.partner;
    final people = identity.everyone;
    final pair = partner != null && people.length == 2;
    final traded = tradedPlacesAt(people);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: CssBox(
        padding: const EdgeInsets.all(14),
        color: AppColors.slate50,
        border: Border.all(color: AppColors.slate200.withValues(alpha: 0.7)),
        borderRadius: AppRadii.all(AppRadii.x2l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              WhoIsWhoCopy.title.toUpperCase(),
              style: Tw.px11.semibold.trackingWider.c(AppColors.slate500),
            ),
            const SizedBox(height: 8),
            _row(me, true, identity),
            if (partner != null) ...[
              const SizedBox(height: 8),
              _row(partner, false, identity),
            ],
            if (partner != null && _confirmClaim == partner.personId) ...[
              const SizedBox(height: 8),
              CssBox(
                padding: const EdgeInsets.all(12),
                color: AppColors.amber50,
                border: Border.all(color: AppColors.amber200),
                borderRadius: AppRadii.all(AppRadii.x2l),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(WhoIsWhoCopy.claimTitle(partner), style: Tw.px11.bold.relaxed.c(AppColors.amber900)),
                    const SizedBox(height: 4),
                    Text(WhoIsWhoCopy.claimBody(me), style: Tw.px11.relaxed.c(AppColors.amber900)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Flexible(
                          child: _Action(
                            label: WhoIsWhoCopy.claimConfirm(partner),
                            color: AppColors.amber800,
                            underline: true,
                            enabled: !identity.busy,
                            onTap: () => _claim(identity),
                          ),
                        ),
                        const SizedBox(width: 12),
                        _Action(
                          label: WhoIsWhoCopy.cancel,
                          color: AppColors.slate400,
                          onTap: () {
                            AppHaptics.tap();
                            setState(() => _confirmClaim = null);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            if (pair && !_swapOpen) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: _Action(
                  label: WhoIsWhoCopy.swappedLink,
                  color: AppColors.slate400,
                  small: true,
                  underline: true,
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
              const SizedBox(height: 8),
              CssBox(
                padding: const EdgeInsets.all(12),
                color: AppColors.lavender50,
                border: Border.all(color: AppColors.lavender200),
                borderRadius: AppRadii.all(AppRadii.x2l),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(WhoIsWhoCopy.swapTitle, style: Tw.px11.bold.relaxed.c(AppColors.lavender700)),
                    const SizedBox(height: 4),
                    Text(
                      WhoIsWhoCopy.swapBody(me, partner, traded == null ? null : formatSwapMoment(context, traded)),
                      style: Tw.px11.relaxed.c(AppColors.slate700),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _Action(
                          label: WhoIsWhoCopy.swapAction,
                          color: AppColors.lavender700,
                          underline: true,
                          enabled: !identity.busy,
                          onTap: () => _swap(identity),
                        ),
                        const SizedBox(width: 12),
                        _Action(
                          label: WhoIsWhoCopy.cancel,
                          color: AppColors.slate400,
                          onTap: () {
                            AppHaptics.tap();
                            setState(() => _swapOpen = false);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            if (_swapNote.isNotEmpty) ...[
              const SizedBox(height: 8),
              Semantics(
                liveRegion: true,
                child: Text(_swapNote, style: Tw.px11.semibold.c(AppColors.slate600)),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              people.length > 2 ? WhoIsWhoCopy.tooMany : WhoIsWhoCopy.sealed,
              style: Tw.px10.relaxed.c(AppColors.slate400),
            ),
          ],
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.label,
    required this.color,
    required this.onTap,
    this.icon,
    this.small = false,
    this.underline = false,
    this.enabled = true,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;
  final LucideIconData? icon;
  final bool small;
  final bool underline;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    var style = (small ? Tw.px10 : Tw.px11).bold.c(color);
    if (underline) style = style.underline.copyWith(decorationColor: color);
    final text = Text(label, style: style);
    return Semantics(
      button: true,
      enabled: enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: icon == null
              ? text
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LucideIcon(icon!, size: 12, color: color),
                    const SizedBox(width: 4),
                    Flexible(child: text),
                  ],
                ),
        ),
      ),
    );
  }
}
