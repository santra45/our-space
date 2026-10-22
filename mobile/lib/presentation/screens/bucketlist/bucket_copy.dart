import 'package:flutter/foundation.dart';

import '../../sky/sky.dart';

abstract final class BucketCopy {
  static const String title = 'Dreams for us';
  static const String addDream = 'Add a dream';
  static const String progressLabel = 'Dreams come true';
  static const String empty = 'No dreams yet. Add the first one we will chase together.';
  static const String kicker = 'Dreams for us';
  static const String newTitle = 'A new dream';
  static const String editTitle = 'Change this dream';
  static const String textLabel = 'Our dream';
  static const String hint = 'See the northern lights together';
  static const String categoryLabel = 'What kind of dream';
  static const String add = 'Add to our dreams';
  static const String save = 'Save';
  static const String remove = 'Remove this dream';
  static const String confirmRemove = 'Remove this dream from our list?';
  static const String confirmRemoveNote = 'It will be gone for both of us.';
  static const String confirmRemoveYes = 'Remove';
  static const String keep = 'Keep it';
  static const String change = 'Change this dream';
  static const String seedFailed =
      'We could not add the starter dreams on this phone. Anything you add yourselves still saves, and the starters will try again next time you open Us.';
  static const String toggleFailed = 'That change did not save. Our Space may have locked.';
  static const String deleteFailed = 'That dream could not be removed. Our Space may have locked.';
  static const String saveFailed = 'That dream did not save. Our Space may have locked.';
  static const String defaultCategory = 'Romance';

  static String count(int done, int total) => '$done of $total';

  static String countLabel(int done, int total) => '$done of $total dreams come true';

  static String done(String text) => '$text, done';

  static String hiddenItems(int count) =>
      '$count dream${count == 1 ? '' : 's'} could not be opened with your passphrase, so ${count == 1 ? 'it is' : 'they are'} hidden for now.';
}

@immutable
class DreamCategory {
  const DreamCategory(this.value, this.label);

  final String value;
  final String label;
}

const List<DreamCategory> dreamCategories = [
  DreamCategory('Romance', 'Romance'),
  DreamCategory('Travel', 'Travel'),
  DreamCategory('Adventures', 'Adventure'),
  DreamCategory('Silly', 'Silly and fun'),
];

String dreamCategoryLabel(String value) {
  for (final category in dreamCategories) {
    if (category.value == value) return category.label;
  }
  return skyCalmText(value);
}

int progressPercent(int done, int total) => total > 0 ? (done / total * 100).round() : 0;
