import 'package:flutter/material.dart';

import '../../../sky/sky.dart';

enum SaveOutcome { saved, skipped, failed }

class UsSheetFrame extends StatelessWidget {
  const UsSheetFrame({super.key, this.kicker, required this.title, this.message, required this.children});

  final String? kicker;
  final String title;
  final String? message;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (kicker != null) ...[
            Text(kicker!.toUpperCase(), style: SkyType.kicker.copyWith(color: t.kicker)),
            const SizedBox(height: SkySpace.sm),
          ],
          Semantics(
            header: true,
            child: Text(title, style: SkyType.titleSmall.copyWith(color: t.text)),
          ),
          if (message != null) ...[
            const SizedBox(height: SkySpace.sm),
            Text(message!, style: SkyType.bodySmall.copyWith(color: t.muted)),
          ],
          const SizedBox(height: SkySpace.xl),
          ...children,
        ],
      ),
    );
  }
}

class UsSheetActions extends StatelessWidget {
  const UsSheetActions({super.key, required this.primary, this.secondary});

  final Widget primary;
  final Widget? secondary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: SkySpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          primary,
          if (secondary != null) ...[const SizedBox(height: SkySpace.sm + 2), secondary!],
        ],
      ),
    );
  }
}
