import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/engine.dart';
import '../../widgets/our_widgets.dart';

const Duration namesWait = Duration(seconds: 12);

const Map<String, String> pronounLabels = {
  'she': 'she / her',
  'he': 'he / him',
  'they': 'they / them',
};

abstract final class PeopleSetupCopy {
  static const String claimEyebrow = 'Almost there';
  static const String claimTitle = 'Which one of you is this?';
  static const String claimBody = 'Tap your own name. It is only so this phone knows whose answers are whose.';
  static const String claimFallbackName = 'This one';
  static const String claimFooter = 'Picked the wrong one? You can switch any time from the Pair & Sync Hub.';
  static const String nameEyebrow = 'One small thing';
  static const String nameTitle = 'What should we call you two?';
  static const String nameBody = 'So this place can use your names instead of saying “your partner” forever.';
  static const String nameWarning =
      'Only do this on one phone. If the other phone already has your names, they will arrive here by themselves.';
  static const String youLabel = 'You';
  static const String youHint = 'Your name';
  static const String themLabel = 'Them';
  static const String themHint = 'Their name';
  static const String save = 'That’s us 💕';
  static const String saving = 'Saving…';
  static const String dismiss = 'Already did this on the other phone';
  static const String failed = 'That did not save. Try again in a moment.';
}

enum PeopleSetupView { hidden, claim, name }

bool mailboxIsSettled(SyncService sync) {
  if (!sync.mailboxEnabled) return true;
  final state = sync.status.state;
  return state == MailboxRunState.ok || state == MailboxRunState.failed;
}

PeopleSetupView peopleSetupView({
  required IdentityStatus status,
  required bool mailboxSettled,
  required bool waitedOut,
  required bool dismissed,
}) {
  switch (status) {
    case IdentityStatus.loading:
    case IdentityStatus.locked:
    case IdentityStatus.ready:
      return PeopleSetupView.hidden;
    case IdentityStatus.unclaimed:
      return PeopleSetupView.claim;
    case IdentityStatus.empty:
      final stillLooking = !waitedOut && !mailboxSettled;
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
    final ok = await identity.claimPerson(personId);
    if (ok) {
      AppHaptics.celebration();
      return;
    }
    if (mounted) setState(() => _error = PeopleSetupCopy.failed);
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
      return;
    }
    if (mounted) setState(() => _error = PeopleSetupCopy.failed);
  }

  @override
  Widget build(BuildContext context) {
    final identity = context.watch<IdentityController>();
    final settled = mailboxIsSettled(context.watch<SyncService>());
    final status = identity.status;
    _follow(identity, status, settled);

    final view = peopleSetupView(
      status: status,
      mailboxSettled: settled,
      waitedOut: _waitedOut,
      dismissed: _dismissed,
    );
    if (view == PeopleSetupView.hidden) return const SizedBox.shrink();
    return PeopleSetupFrame(child: view == PeopleSetupView.claim ? _claimBody(identity) : _nameBody(identity));
  }

  Widget _claimBody(IdentityController identity) {
    final people = identity.everyone;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PeopleSetupEyebrow(PeopleSetupCopy.claimEyebrow),
        const SizedBox(height: 4),
        const PeopleSetupTitle(PeopleSetupCopy.claimTitle),
        const SizedBox(height: 4),
        Text(PeopleSetupCopy.claimBody, style: Tw.xs.relaxed.c(AppColors.slate500)),
        const SizedBox(height: 20),
        ...spaced([
          for (var i = 0; i < people.length; i++)
            BouncyButton(
              key: ValueKey(people[i].personId),
              variant: i == 0 ? BouncyVariant.primary : BouncyVariant.lavender,
              enabled: !identity.busy,
              expand: true,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              label: people[i].name.isEmpty ? PeopleSetupCopy.claimFallbackName : people[i].name,
              onPressed: () => _claim(identity, people[i].personId),
            ),
        ], 8),
        if (_error != null) ...[
          const SizedBox(height: 12),
          PeopleSetupError(_error!, center: true),
        ],
        const SizedBox(height: 16),
        Text(
          PeopleSetupCopy.claimFooter,
          textAlign: TextAlign.center,
          style: Tw.px10.relaxed.c(AppColors.slate400),
        ),
      ],
    );
  }

  Widget _nameBody(IdentityController identity) {
    final busy = identity.busy;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PeopleSetupEyebrow(PeopleSetupCopy.nameEyebrow),
        const SizedBox(height: 4),
        const PeopleSetupTitle(PeopleSetupCopy.nameTitle),
        const SizedBox(height: 4),
        Text(PeopleSetupCopy.nameBody, style: Tw.xs.relaxed.c(AppColors.slate500)),
        const SizedBox(height: 8),
        Text(PeopleSetupCopy.nameWarning, style: Tw.px11.relaxed.c(AppColors.amber700)),
        const SizedBox(height: 20),
        ...spaced([
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
          if (_error != null) PeopleSetupError(_error!),
          BouncyButton(
            enabled: _canSave && !busy,
            expand: true,
            label: busy ? PeopleSetupCopy.saving : PeopleSetupCopy.save,
            onPressed: () => _save(identity),
          ),
          Semantics(
            button: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                AppHaptics.tap();
                setState(() => _dismissed = true);
              },
              child: Text(
                PeopleSetupCopy.dismiss,
                textAlign: TextAlign.center,
                style: Tw.px11.bold.c(AppColors.slate400),
              ),
            ),
          ),
        ], 16),
      ],
    );
  }
}

class PeopleSetupFrame extends StatefulWidget {
  const PeopleSetupFrame({super.key, required this.child});

  final Widget child;

  @override
  State<PeopleSetupFrame> createState() => _PeopleSetupFrameState();
}

class _PeopleSetupFrameState extends State<PeopleSetupFrame> with SingleTickerProviderStateMixin {
  static const Duration _enter = Duration(milliseconds: 250);

  late final AnimationController _entrance = AnimationController(vsync: this, duration: _enter);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (motionAllowed(context)) {
      _entrance.forward();
    } else {
      _entrance.value = 1;
    }
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    const tone = OurBackdropTone.slate40;
    return Positioned.fill(
      child: Stack(
        fit: StackFit.expand,
        children: [
          BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: tone.blur, sigmaY: tone.blur),
            child: ColoredBox(color: tone.color),
          ),
          Padding(
            padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: AnimatedBuilder(
                    animation: _entrance,
                    builder: (context, child) {
                      final seconds = _entrance.value * _enter.inMicroseconds / 1e6;
                      final frame = entranceFrameAt(OurModalEntrance.rise, seconds);
                      return Opacity(
                        opacity: frame.opacity.clamp(0.0, 1.0),
                        child: Transform.translate(
                          offset: Offset(0, frame.dy),
                          child: Transform.scale(scale: frame.scale, child: child),
                        ),
                      );
                    },
                    child: OurModalCard(
                      borderColor: AppColors.lavender100,
                      showClose: false,
                      padding: const EdgeInsets.all(24),
                      child: widget.child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PeopleSetupEyebrow extends StatelessWidget {
  const PeopleSetupEyebrow(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const LucideIcon(AppIcons.heart, size: 16, color: AppColors.blush400, fill: AppColors.blush400),
        const SizedBox(width: 8),
        Flexible(
          child: Text(text.toUpperCase(), style: Tw.px11.bold.trackingWide.c(AppColors.lavender500)),
        ),
      ],
    );
  }
}

class PeopleSetupTitle extends StatelessWidget {
  const PeopleSetupTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: Tw.x2l.handwriting.snug.c(AppColors.slate800));
  }
}

class PeopleSetupError extends StatelessWidget {
  const PeopleSetupError(this.text, {super.key, this.center = false});

  final String text;
  final bool center;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Text(
        text,
        textAlign: center ? TextAlign.center : TextAlign.start,
        style: Tw.px11.semibold.c(AppColors.rose600),
      ),
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

  static final OurFieldStyle fieldStyle = OurFieldStyle.soft.copyWith(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OurFieldLabel(label, caps: true),
        OurTextField(
          controller: controller,
          focusNode: focusNode,
          style: fieldStyle,
          hint: hint,
          maxLength: maxNameLength,
          autofocus: autofocus,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: textInputAction,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          semanticLabel: label,
        ),
        const SizedBox(height: 8),
        PronounPicker(value: pronoun, onChanged: onPronoun),
      ],
    );
  }
}

class PronounPicker extends StatelessWidget {
  const PronounPicker({super.key, required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < pronouns.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: PronounChip(
              label: pronounLabels[pronouns[i]]!,
              selected: value == pronouns[i],
              onTap: () => onChanged(pronouns[i]),
            ),
          ),
        ],
      ],
    );
  }
}

class PronounChip extends StatelessWidget {
  const PronounChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.padding = const EdgeInsets.symmetric(vertical: 6),
    this.radius = AppRadii.xl,
    this.textStyle,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final EdgeInsets padding;
  final double radius;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: CssBox(
          padding: padding,
          color: selected ? AppColors.lavender500 : AppColors.lavender50,
          borderRadius: AppRadii.all(radius),
          child: SizedBox(
            width: double.infinity,
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: (textStyle ?? Tw.px11.bold).c(selected ? AppColors.white : AppColors.lavender600),
            ),
          ),
        ),
      ),
    );
  }
}
