abstract final class MilestoneCopy {
  static const String together = 'Together Forever';
  static const String days = 'Days';
  static const String hours = 'Hours';
  static const String minutes = 'Minutes';
  static const String seconds = 'Seconds';
  static const String save = 'Save';
  static const String cancel = 'Cancel';
  static const String sendBurst = 'Send Love Burst 💕';
  static const String sendingBurst = 'Sending Love... 💕';
  static const String anniversary = 'Anniversary';
  static const String today = 'Today! 🎉';
  static const String daysLeft = 'days left';
  static const String nextHundred = 'Next 100-day milestone';
  static const String title = 'Relationship Milestones';
  static const String placeholder = 'e.g. First kiss, moved in together...';
  static const String add = 'Add';
  static const String empty = 'No milestones yet. Tap + to add your first one!';
  static const String editLabel = 'Edit Milestone';
  static const String fallbackTitle = 'A milestone';
  static const String confirmDelete = 'Delete this milestone?';
  static const String editTooltip = 'Edit milestone';
  static const String deleteTooltip = 'Delete milestone';
  static const String saveFailed = 'Could not save that milestone. Our Space may have locked.';
  static const String deleteFailed = 'Could not delete that milestone. Our Space may have locked.';
  static const String updateFailed = 'Could not update that milestone. Our Space may have locked.';

  static String since(String prettyDate) => 'Since $prettyDate (Tap to edit)';

  static String yearCelebration(int year) => 'Year $year Celebration';

  static String dayTag(int milestone) => 'Day $milestone';

  static String hidden(int count) =>
      '$count milestone${count == 1 ? '' : 's'} could not be opened with your passphrase, so '
      '${count == 1 ? 'it is' : 'they are'} hidden for now.';

  static String? notice({required String error, required int unreadable}) {
    if (error.isNotEmpty) return error;
    if (unreadable > 0) return hidden(unreadable);
    return null;
  }
}
