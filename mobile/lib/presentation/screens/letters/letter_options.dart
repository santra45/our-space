import 'package:flutter/material.dart';

import '../../sky/sky.dart';
import 'letters_copy.dart';

enum LetterOptionsAction { open, write, delete }

Future<LetterOptionsAction?> showLetterOptions(
  BuildContext context, {
  required String title,
  required String subtitle,
  required LetterOptionsAction primary,
  required String primaryLabel,
  bool canDelete = true,
}) {
  return showSkySheet<LetterOptionsAction>(
    context: context,
    builder: (sheetContext) => LetterOptionsSheet(
      title: title,
      subtitle: subtitle,
      primary: primary,
      primaryLabel: primaryLabel,
      canDelete: canDelete,
    ),
  );
}

class LetterOptionsSheet extends StatelessWidget {
  const LetterOptionsSheet({
    super.key,
    required this.title,
    required this.subtitle,
    required this.primary,
    required this.primaryLabel,
    this.canDelete = true,
  });

  final String title;
  final String subtitle;
  final LetterOptionsAction primary;
  final String primaryLabel;
  final bool canDelete;

  SkyIcons get _primaryIcon {
    switch (primary) {
      case LetterOptionsAction.open:
        return SkyIcons.letter;
      case LetterOptionsAction.write:
        return SkyIcons.pen;
      case LetterOptionsAction.delete:
        return SkyIcons.trash;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final navigator = Navigator.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: SkyType.headlineSmall.copyWith(color: t.text),
        ),
        const SizedBox(height: SkySpace.xs),
        Text(subtitle, textAlign: TextAlign.center, style: SkyType.small.copyWith(color: t.muted)),
        const SizedBox(height: SkySpace.lg),
        SkyListGroup(
          children: [
            SkyListRow(
              title: primaryLabel,
              icon: _primaryIcon,
              tone: SkyTone.gold,
              onTap: () => navigator.pop(primary),
            ),
            if (canDelete)
              SkyListRow(
                title: LettersCopy.deleteLetter,
                icon: SkyIcons.trash,
                tone: SkyTone.rose,
                onTap: () => navigator.pop(LetterOptionsAction.delete),
              ),
          ],
        ),
        const SizedBox(height: SkySpace.sm),
      ],
    );
  }
}
