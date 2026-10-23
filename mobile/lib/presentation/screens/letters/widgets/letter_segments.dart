import 'package:flutter/widgets.dart';

import '../../../sky/sky.dart';
import '../letter_shelf.dart';
import '../letters_copy.dart';

abstract final class LetterSegmentKeys {
  static Key of(LetterSegment segment) => ValueKey<String>('letters-segment-${segment.name}');
}

extension LetterSegmentLabel on LetterSegment {
  String get label {
    switch (this) {
      case LetterSegment.waiting:
        return LettersCopy.waiting;
      case LetterSegment.opened:
        return LettersCopy.opened;
      case LetterSegment.sent:
        return LettersCopy.sent;
    }
  }
}

class LetterSegments extends StatelessWidget {
  const LetterSegments({super.key, required this.selected, required this.counts, required this.onSelect});

  final LetterSegment selected;
  final int Function(LetterSegment segment) counts;
  final ValueChanged<LetterSegment> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: SkySpace.sm,
      children: [
        for (final segment in LetterSegment.values)
          SkyChip(
            key: LetterSegmentKeys.of(segment),
            label: LettersCopy.segment(segment.label, counts(segment)),
            tone: segment == selected ? SkyChipTone.on : SkyChipTone.plain,
            onTap: () => onSelect(segment),
          ),
      ],
    );
  }
}
