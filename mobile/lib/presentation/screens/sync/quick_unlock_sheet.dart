import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/engine.dart';
import '../../sky/sky.dart';
import '../../widgets/app_haptics.dart';
import '../settings/widgets/settings_field.dart';
import '../settings/widgets/sheet_parts.dart';
import 'backup_dialogs.dart' show SheetButtons;

abstract final class TouchCopy {
  static const String title = 'Open with a touch';
  static const String onBody = 'Your fingerprint opens Our Space';
  static const String offBody = 'Skip typing your passphrase here';
  static const String setupBody =
      'Type your passphrase once more and this phone will remember it for you. Anyone who can unlock this phone will be able to open your space.';
  static const String passphraseHint = 'Your passphrase';
  static const String notNow = 'Not now';
  static const String setUp = 'Set it up';
  static const String settingUp = 'Setting up…';
  static const String done = 'Done. Next time, just a touch.';
  static const String turnedOff = 'Turned off. Your passphrase still opens everything.';
  static const Map<String, String> problems = {
    'wrong-passphrase': 'That passphrase does not match this space. Have another go.',
    'cancelled': 'That got stopped partway, so nothing changed. Try again when you are ready.',
    'unsupported': 'This phone will not do the fingerprint trick. Your passphrase still works.',
    'no-vault': 'We could not read your space just now. Try again in a moment.',
    'failed': 'That did not finish. Try again in a moment.',
  };

  static String problem(String? code) => problems[code] ?? problems['failed']!;
}

Future<bool> showQuickUnlockSetup(BuildContext context) async {
  final result = await showSkySheet<bool>(
    context: context,
    enableDrag: false,
    builder: (_) => const QuickUnlockSetupSheet(),
  );
  return result ?? false;
}

class QuickUnlockSetupSheet extends StatefulWidget {
  const QuickUnlockSetupSheet({super.key});

  @override
  State<QuickUnlockSetupSheet> createState() => _QuickUnlockSetupSheetState();
}

class _QuickUnlockSetupSheetState extends State<QuickUnlockSetupSheet> {
  final TextEditingController _passphrase = TextEditingController();
  bool _reveal = false;
  bool _busy = false;
  String? _problem;

  @override
  void dispose() {
    _passphrase.dispose();
    super.dispose();
  }

  bool get _canSubmit => !_busy && _passphrase.text.trim().isNotEmpty;

  void _cancel() {
    if (_busy) return;
    AppHaptics.tap();
    Navigator.of(context).pop(false);
  }

  Future<void> _turnOn() async {
    if (!_canSubmit) return;
    AppHaptics.tap();
    setState(() {
      _problem = null;
      _busy = true;
    });
    final result = await context.read<QuickUnlockService>().enable(_passphrase.text);
    if (!mounted) return;
    if (result.ok) {
      _passphrase.clear();
      AppHaptics.celebration();
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _problem = TouchCopy.problem(result.code);
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: SheetScroll(
        children: [
          const SheetHeader(
            title: TouchCopy.title,
            subtitle: TouchCopy.setupBody,
            icon: SkyIcons.finger,
            tone: SkyTone.gold,
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              SettingsField(
                controller: _passphrase,
                hint: TouchCopy.passphraseHint,
                obscured: !_reveal,
                onToggleReveal: () => setState(() => _reveal = !_reveal),
                autofocus: true,
                autocorrect: false,
                enableSuggestions: false,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.go,
                onChanged: (_) => setState(() => _problem = null),
                onSubmitted: (_) => _turnOn(),
              ),
              SettingsNotes(notes: [if (_problem != null) SettingsNote.error(_problem!)]),
            ],
          ),
          SheetButtons(
            confirmLabel: TouchCopy.setUp,
            cancelLabel: TouchCopy.notNow,
            busyLabel: TouchCopy.settingUp,
            onConfirm: _turnOn,
            onCancel: _cancel,
            busy: _busy,
            confirmEnabled: _canSubmit,
          ),
        ],
      ),
    );
  }
}
