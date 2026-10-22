import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/engine.dart';
import '../../sky/sky.dart';
import '../../widgets/app_haptics.dart';
import '../../widgets/confetti_burst.dart';

abstract final class LoveSheetCopy {
  static const String title = 'Send a little love';
  static const String send = 'Tap to send';
  static const String sending = 'On its way';
  static String forName(String name) => 'For $name';
  static String reaches(String name, PronounSet grammar) =>
      'It reaches $name right away, wherever ${grammar.subject} ${grammar.isVerb}.';
}

Future<void> showLoveSheet(BuildContext context) {
  return showSkySheet<void>(context: context, builder: (_) => const LoveSheet());
}

class LoveSheet extends StatefulWidget {
  const LoveSheet({super.key});

  @override
  State<LoveSheet> createState() => _LoveSheetState();
}

class _LoveSheetState extends State<LoveSheet> {
  bool _sending = false;
  Timer? _reset;

  Future<void> _send() async {
    AppHaptics.celebration();
    fireHeartConfetti(context);
    if (_sending) return;
    final sync = context.read<SyncService>();
    setState(() => _sending = true);
    try {
      await sync.sendLoveBurst();
    } finally {
      _reset?.cancel();
      _reset = Timer(const Duration(seconds: 1), () {
        if (mounted) setState(() => _sending = false);
      });
    }
  }

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final identity = context.watch<IdentityController>();
    final name = identity.partnerName;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SkyLabel(LoveSheetCopy.forName(name), icon: SkyIcons.heart, tone: SkyTone.rose, center: true),
        const SizedBox(height: 6),
        Text(
          LoveSheetCopy.title,
          textAlign: TextAlign.center,
          style: SkyType.serif(30, weight: FontWeight.w500).copyWith(color: t.text),
        ),
        const SizedBox(height: 6),
        Text(
          LoveSheetCopy.reaches(name, identity.partnerGrammar),
          textAlign: TextAlign.center,
          style: SkyType.sans(13).copyWith(color: t.muted),
        ),
        const SizedBox(height: 32),
        SkyLoveButton(size: 128, onTap: _sending ? null : () => unawaited(_send()), semanticLabel: LoveSheetCopy.send),
        const SizedBox(height: 24),
        AnimatedSwitcher(
          duration: skyMotionAllowed(context) ? SkyMotion.quick : Duration.zero,
          child: Text(
            (_sending ? LoveSheetCopy.sending : LoveSheetCopy.send).toUpperCase(),
            key: ValueKey<bool>(_sending),
            style: SkyType.hold.copyWith(color: t.rose),
          ),
        ),
        const SizedBox(height: SkySpace.lg),
      ],
    );
  }
}
