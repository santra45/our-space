import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/engine.dart';
import '../../widgets/our_widgets.dart';
import 'sync_hub.dart' show HubTextButton;

abstract final class QuickUnlockHubCopy {
  static const String title = 'Open with a touch';
  static const String enrolledBody = 'This phone opens your space with your fingerprint or face.';
  static const String turnOff = 'Turn off';
  static const String setupBody =
      'Type your passphrase once more and this phone will remember it for you. Anyone who can unlock this phone will be able to open your space.';
  static const String passphraseHint = 'Your passphrase';
  static const String notNow = 'Not now';
  static const String setUp = 'Set it up';
  static const String settingUp = 'Setting up…';
  static const String offerBody = 'Skip typing the passphrase on this phone every time.';
  static const String done = 'Done. Next time, just a touch. 💕';
  static const String turnedOff = 'Turned off. Your passphrase still opens everything.';
  static const Map<String, String> problems = {
    'wrong-passphrase': 'That passphrase does not match this space. Have another go.',
    'cancelled': 'That got stopped partway, so nothing changed. Try again when you are ready.',
    'unsupported': 'This phone will not do the fingerprint trick. Your passphrase still works.',
    'no-vault': 'We could not read your space just now. Try again in a moment.',
    'failed': 'That did not finish. Try again in a moment.',
  };
}

class QuickUnlockPanel extends StatefulWidget {
  const QuickUnlockPanel({super.key});

  @override
  State<QuickUnlockPanel> createState() => _QuickUnlockPanelState();
}

class _QuickUnlockPanelState extends State<QuickUnlockPanel> {
  final TextEditingController _passphrase = TextEditingController();
  bool _open = false;
  bool _busy = false;
  String? _note;
  String? _problem;

  @override
  void dispose() {
    _passphrase.dispose();
    super.dispose();
  }

  bool get _canSubmit => !_busy && _passphrase.text.trim().isNotEmpty;

  void _start() {
    AppHaptics.tap();
    setState(() {
      _note = null;
      _problem = null;
      _open = true;
    });
  }

  void _cancel() {
    AppHaptics.tap();
    setState(() {
      _open = false;
      _passphrase.clear();
      _problem = null;
    });
  }

  Future<void> _turnOn() async {
    if (!_canSubmit) return;
    AppHaptics.tap();
    setState(() {
      _note = null;
      _problem = null;
      _busy = true;
    });
    final result = await context.read<QuickUnlockService>().enable(_passphrase.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result.ok) {
        _passphrase.clear();
        _open = false;
        _note = QuickUnlockHubCopy.done;
      } else {
        _problem = QuickUnlockHubCopy.problems[result.code] ?? QuickUnlockHubCopy.problems['failed'];
      }
    });
    if (result.ok) AppHaptics.celebration();
  }

  Future<void> _turnOff() async {
    AppHaptics.tap();
    await context.read<QuickUnlockService>().disable();
    if (!mounted) return;
    setState(() {
      _passphrase.clear();
      _problem = null;
      _open = false;
      _note = QuickUnlockHubCopy.turnedOff;
    });
  }

  Widget _notNowButton() {
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _cancel,
        child: CssBox(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          border: Border.all(color: AppColors.slate200),
          borderRadius: AppRadii.all(AppRadii.xl),
          child: Text(
            QuickUnlockHubCopy.notNow,
            textAlign: TextAlign.center,
            style: Tw.px11.bold.c(AppColors.slate600),
          ),
        ),
      ),
    );
  }

  Widget _body(QuickUnlockService quick) {
    final small = Tw.px10.relaxed.c(AppColors.slate500);
    if (quick.enrolled) {
      return Row(
        children: [
          Expanded(child: Text(QuickUnlockHubCopy.enrolledBody, style: small)),
          const SizedBox(width: 12),
          HubTextButton(
            label: QuickUnlockHubCopy.turnOff,
            color: AppColors.slate500,
            style: Tw.px11.bold,
            underline: true,
            onTap: _turnOff,
          ),
        ],
      );
    }
    if (_open) {
      final field = OurFieldStyle.muted.copyWith(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        textStyle: Tw.xs.c(AppColors.slate800),
        hintStyle: Tw.xs.c(AppColors.placeholder),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(QuickUnlockHubCopy.setupBody, style: small),
          const SizedBox(height: 8),
          OurTextField(
            controller: _passphrase,
            style: field,
            hint: QuickUnlockHubCopy.passphraseHint,
            obscure: true,
            autofocus: true,
            textInputAction: TextInputAction.go,
            autofillHints: const [AutofillHints.password],
            onChanged: (_) => setState(() => _problem = null),
            onSubmitted: (_) => _turnOn(),
            semanticLabel: QuickUnlockHubCopy.passphraseHint,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _notNowButton()),
              const SizedBox(width: 8),
              Expanded(
                child: BouncyButton(
                  onPressed: _turnOn,
                  enabled: _canSubmit,
                  small: true,
                  expand: true,
                  label: _busy ? QuickUnlockHubCopy.settingUp : QuickUnlockHubCopy.setUp,
                ),
              ),
            ],
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: Text(QuickUnlockHubCopy.offerBody, style: small)),
        const SizedBox(width: 12),
        HubTextButton(
          label: QuickUnlockHubCopy.setUp,
          color: AppColors.blush600,
          style: Tw.px11.bold,
          underline: true,
          onTap: _start,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final quick = context.watch<QuickUnlockService>();
    if (!quick.available) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: CssBox(
        padding: const EdgeInsets.only(top: 12),
        border: const Border(top: BorderSide(color: AppColors.slate100)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const LucideIcon(AppIcons.fingerprint, size: 14, color: AppColors.blush500),
                const SizedBox(width: 6),
                Flexible(child: Text(QuickUnlockHubCopy.title, style: Tw.px11.bold.c(AppColors.slate600))),
              ],
            ),
            const SizedBox(height: 8),
            _body(quick),
            if (_note != null) ...[
              const SizedBox(height: 8),
              Text(_note!, style: Tw.px10.semibold.c(AppColors.emerald600)),
            ],
            if (_problem != null) ...[
              const SizedBox(height: 8),
              Text(_problem!, style: Tw.px10.semibold.relaxed.c(AppColors.rose600)),
            ],
          ],
        ),
      ),
    );
  }
}
