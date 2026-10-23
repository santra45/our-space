import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/engine.dart';
import '../../sky/sky.dart';
import '../../widgets/app_haptics.dart';
import 'widgets/couple_orbs.dart';
import 'widgets/people_sheet.dart';
import 'widgets/person_choice.dart';
import 'widgets/pronoun_picker.dart';

export 'widgets/people_sheet.dart' show PeopleSetupFrame, PeopleSetupError;
export 'widgets/pronoun_picker.dart' show pronounLabels, pronounLabelFor, PronounPicker, PronounChip;

const Duration namesWait = Duration(seconds: 12);

abstract final class PeopleSetupCopy {
  static const String claimEyebrow = 'Almost there';
  static const String claimTitle = 'Which one of you is this?';
  static const String claimBody = 'Tap your own name. It is only so this phone knows whose answers are whose.';
  static const String claimFallbackName = 'This one';
  static const String claimFooter = 'Picked the wrong one? You can switch any time from Settings.';
  static const String nameEyebrow = 'One small thing';
  static const String nameTitle = 'What should we call you two?';
  static const String nameBody = 'So this place can use your names instead of saying “your partner” forever.';
  static const String nameWarning =
      'Only do this on one phone. If the other phone already has your names, they will arrive here by themselves.';
  static const String youLabel = 'You';
  static const String youHint = 'Your name';
  static const String themLabel = 'Them';
  static const String themHint = 'Their name';
  static const String save = 'That’s us';
  static const String saving = 'Saving…';
  static const String dismiss = 'Already did this on the other phone';
  static const String failed = 'That did not save. Try again in a moment.';

  static String together(String date) => 'Together since $date';
}

const List<String> _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String? togetherSinceLabel(String? startDate, {DateTime? now}) {
  if (startDate == null || startDate.isEmpty) return null;
  final date = parseLocalDate(startDate);
  if (date == null) return null;
  final year = (now ?? DateTime.now()).year;
  final day = '${date.day} ${_monthNames[date.month - 1]}';
  return date.year == year ? day : '$day ${date.year}';
}

enum PeopleSetupView { hidden, claim, name }

bool mailboxIsSettled(SyncService sync) {
  if (!sync.mailboxEnabled) return true;
  final state = sync.status.state;
  return state == MailboxRunState.ok || state == MailboxRunState.failed;
}

const Set<String> stillSyncingPeerStates = {'connecting', 'handshaking', 'authorized', 'syncing'};

bool partnerIsSettling(SyncService sync) => stillSyncingPeerStates.contains(sync.peer?.status.state);

PeopleSetupView peopleSetupView({
  required IdentityStatus status,
  required bool mailboxSettled,
  required bool waitedOut,
  required bool dismissed,
  bool partnerSettling = false,
}) {
  switch (status) {
    case IdentityStatus.loading:
    case IdentityStatus.locked:
    case IdentityStatus.ready:
      return PeopleSetupView.hidden;
    case IdentityStatus.unclaimed:
      return PeopleSetupView.claim;
    case IdentityStatus.empty:
      final stillLooking = !waitedOut && (!mailboxSettled || partnerSettling);
      return dismissed || stillLooking ? PeopleSetupView.hidden : PeopleSetupView.name;
  }
}

class PeopleSetup extends StatefulWidget {
  const PeopleSetup({super.key, this.wait = namesWait});

  final Duration wait;

  @override
  State<PeopleSetup> createState() => _PeopleSetupState();
}

class _PeopleSetupState extends State<PeopleSetup> {
  final TextEditingController _myName = TextEditingController();
  final TextEditingController _theirName = TextEditingController();
  final FocusNode _theirFocus = FocusNode();

  String _myPronoun = defaultPronoun;
  String _theirPronoun = defaultPronoun;
  bool _dismissed = false;
  String? _error;
  String? _claiming;
  bool _waitedOut = false;
  Timer? _wait;

  IdentityStatus? _seenStatus;
  bool? _seenSettled;

  @override
  void dispose() {
    _wait?.cancel();
    _myName.dispose();
    _theirName.dispose();
    _theirFocus.dispose();
    super.dispose();
  }

  bool get _canSave => _myName.text.trim().isNotEmpty && _theirName.text.trim().isNotEmpty;

  void _follow(IdentityController identity, IdentityStatus status, bool settled) {
    final statusChanged = status != _seenStatus;
    final justSettled = settled && _seenSettled == false;
    _seenStatus = status;
    _seenSettled = settled;

    if (statusChanged) {
      _wait?.cancel();
      _wait = null;
      if (status == IdentityStatus.empty) {
        _wait = Timer(widget.wait, () {
          if (mounted) setState(() => _waitedOut = true);
        });
      } else {
        _waitedOut = false;
      }
    }

    if (justSettled && status == IdentityStatus.empty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(identity.refresh());
      });
    }
  }

  Future<void> _claim(IdentityController identity, String personId) async {
    AppHaptics.tap();
    setState(() {
      _claiming = personId;
      _error = null;
    });
    final ok = await identity.claimPerson(personId);
    if (!mounted) return;
    setState(() => _claiming = null);
    if (ok) {
      AppHaptics.celebration();
      return;
    }
    setState(() => _error = PeopleSetupCopy.failed);
  }

  Future<void> _save(IdentityController identity) async {
    if (!_canSave || identity.busy) return;
    setState(() => _error = null);
    final ok = await identity.createCouple(
      myName: _myName.text,
      myPronoun: _myPronoun,
      partnerName: _theirName.text,
      partnerPronoun: _theirPronoun,
    );
    if (ok) {
      AppHaptics.celebration();
      FocusManager.instance.primaryFocus?.unfocus();
      return;
    }
    if (mounted) setState(() => _error = PeopleSetupCopy.failed);
  }

  void _waveAway() {
    AppHaptics.tap();
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _dismissed = true);
  }

  @override
  Widget build(BuildContext context) {
    final identity = context.watch<IdentityController>();
    final sync = context.watch<SyncService>();
    final vault = context.watch<VaultService?>();
    final settled = mailboxIsSettled(sync);
    final status = identity.status;
    _follow(identity, status, settled);

    final view = peopleSetupView(
      status: status,
      mailboxSettled: settled,
      waitedOut: _waitedOut,
      dismissed: _dismissed,
      partnerSettling: partnerIsSettling(sync),
    );
    final visible = view != PeopleSetupView.hidden;
    return PeopleSetupFrame(
      visible: visible,
      viewKey: view,
      child: switch (view) {
        PeopleSetupView.hidden => null,
        PeopleSetupView.claim => _claimBody(identity),
        PeopleSetupView.name => _nameBody(identity, togetherSinceLabel(vault?.config?.startDate)),
      },
    );
  }

  Widget _claimBody(IdentityController identity) {
    final t = context.sky;
    final people = identity.everyone;
    final busy = identity.busy;
    return Column(
      key: const ValueKey<String>('people-claim'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: peopleSheetItems([
        (
          'claim-header',
          0,
          const PeopleSheetHeader(
            label: PeopleSetupCopy.claimEyebrow,
            icon: SkyIcons.sparkle,
            tone: SkyTone.gold,
            title: PeopleSetupCopy.claimTitle,
            body: PeopleSetupCopy.claimBody,
          ),
        ),
        for (var i = 0; i < people.length; i++)
          (
            'claim-${people[i].personId}',
            i == 0 ? SkySpace.xl : SkySpace.sm + 2,
            PersonChoice(
              key: ValueKey(people[i].personId),
              name: people[i].name.isEmpty ? PeopleSetupCopy.claimFallbackName : people[i].name,
              initial: CoupleOrbs.initialOf(people[i].name),
              detail: pronounLabelFor(people[i].pronoun),
              style: i.isEven ? SkyAvatarStyle.me : SkyAvatarStyle.partner,
              enabled: !busy,
              busy: busy && _claiming == people[i].personId,
              onTap: () => _claim(identity, people[i].personId),
            ),
          ),
        if (_error != null) ('claim-error', SkySpace.md, PeopleSetupError(_error!)),
        (
          'claim-footer',
          SkySpace.lg,
          Text(
            PeopleSetupCopy.claimFooter,
            textAlign: TextAlign.center,
            style: SkyType.caption.copyWith(color: t.faint, height: 1.45),
          ),
        ),
      ]),
    );
  }

  Widget _nameBody(IdentityController identity, String? together) {
    final busy = identity.busy;
    return Column(
      key: const ValueKey<String>('people-name'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: peopleSheetItems([
        (
          'name-orbs',
          0,
          Center(child: CoupleOrbs(myName: _myName.text, partnerName: _theirName.text)),
        ),
        (
          'name-header',
          SkySpace.md,
          const PeopleSheetHeader(
            label: PeopleSetupCopy.nameEyebrow,
            title: PeopleSetupCopy.nameTitle,
            body: PeopleSetupCopy.nameBody,
          ),
        ),
        if (together != null)
          (
            'name-together',
            SkySpace.md,
            Center(child: SkyChip(label: PeopleSetupCopy.together(together), icon: SkyIcons.calendar)),
          ),
        (
          'name-warning',
          SkySpace.lg,
          const SkyNotice(text: PeopleSetupCopy.nameWarning, tone: SkyNoticeTone.warning, icon: SkyIcons.phone),
        ),
        (
          'name-you',
          SkySpace.lg,
          PersonNameFields(
            label: PeopleSetupCopy.youLabel,
            hint: PeopleSetupCopy.youHint,
            controller: _myName,
            pronoun: _myPronoun,
            autofocus: true,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _theirFocus.requestFocus(),
            onPronoun: (value) => setState(() => _myPronoun = value),
          ),
        ),
        (
          'name-them',
          SkySpace.lg,
          PersonNameFields(
            label: PeopleSetupCopy.themLabel,
            hint: PeopleSetupCopy.themHint,
            controller: _theirName,
            focusNode: _theirFocus,
            pronoun: _theirPronoun,
            textInputAction: TextInputAction.go,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _save(identity),
            onPronoun: (value) => setState(() => _theirPronoun = value),
          ),
        ),
        if (_error != null) ('name-error', SkySpace.lg, PeopleSetupError(_error!)),
        (
          'name-save',
          SkySpace.xl,
          SkyButton(
            label: PeopleSetupCopy.save,
            busyLabel: PeopleSetupCopy.saving,
            busy: busy,
            icon: SkyIcons.heart,
            onPressed: _canSave ? () => _save(identity) : null,
          ),
        ),
        (
          'name-dismiss',
          SkySpace.sm,
          PeopleTextLink(label: PeopleSetupCopy.dismiss, onTap: _waveAway),
        ),
      ]),
    );
  }
}

class PersonNameFields extends StatelessWidget {
  const PersonNameFields({
    super.key,
    required this.label,
    required this.hint,
    required this.controller,
    required this.pronoun,
    required this.onPronoun,
    this.focusNode,
    this.autofocus = false,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final String pronoun;
  final ValueChanged<String> onPronoun;
  final FocusNode? focusNode;
  final bool autofocus;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SkyTextField(
          controller: controller,
          focusNode: focusNode,
          label: label,
          hint: hint,
          maxLength: maxNameLength,
          autofocus: autofocus,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: textInputAction,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
        ),
        const SizedBox(height: SkySpace.sm + 2),
        PronounPicker(value: pronoun, onChanged: onPronoun),
      ],
    );
  }
}
