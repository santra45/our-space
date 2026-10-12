import 'package:flutter/widgets.dart';

abstract final class BucketCopy {
  static const String title = 'Our Bucket List';
  static const String addDream = 'Add Dream';
  static const String conquered = 'Adventures Conquered Together';
  static const String newLabel = 'New Dream or Adventure';
  static const String hint = 'e.g. Visit the Northern Lights...';
  static const String addGoal = 'Add Goal';
  static const String editLabel = 'Edit Dream or Goal';
  static const String cancel = 'Cancel';
  static const String save = 'Save';
  static const String completed = 'COMPLETED';
  static const String deleteQuestion = 'Delete this dream from your bucket list?';
  static const String seedFailed =
      'Could not add the starter bucket list items to this device. Anything you add yourself still saves normally — reopen this screen to try again.';
  static const String toggleFailed = 'Could not save that change. Our Space may have locked.';
  static const String deleteFailed = 'Could not delete that item. Our Space may have locked.';
  static const String saveFailed = 'Could not save that dream. Our Space may have locked.';
  static const String defaultCategory = 'Romance';

  static String progress(int done, int total, int percent) => '$done of $total adventures completed ($percent%)';

  static String hiddenItems(int count) =>
      '$count item${count == 1 ? '' : 's'} could not be opened with your passphrase, so ${count == 1 ? 'it is' : 'they are'} hidden for now.';
}

int progressPercent(int done, int total) => total > 0 ? (done / total * 100).round() : 0;

String breakAnywhere(String text) => text.characters.join('​');
