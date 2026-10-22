abstract final class MilestoneCopy {
  static const String together = 'Together, and counting';
  static const String days = 'days';
  static const String hours = 'hours';
  static const String minutes = 'min';
  static const String seconds = 'sec';
  static const String changeDay = 'Change the day we began';

  static const String dayKicker = 'Our first day';
  static const String dayTitle = 'When did we begin?';
  static const String dayMessage = 'Pick the day our sky got its very first star.';
  static const String dayField = 'The day it all began';
  static const String saveDay = 'Save our day';
  static const String notNow = 'Not now';

  static const String constellation = 'Our constellation';
  static const String addMoment = 'Add a moment';
  static const String todayNote = 'Another star in our sky';
  static const String began = 'Where it all began';
  static const String emptyTitle = 'Your first moment is waiting';
  static const String emptyNote = 'Add one and it joins our stars';
  static const String fallbackTitle = 'A moment';

  static const String momentKicker = 'Our constellation';
  static const String newTitle = 'A moment to remember';
  static const String editTitle = 'Change this moment';
  static const String whatLabel = 'What happened';
  static const String whatHint = 'The night we talked until sunrise';
  static const String whenLabel = 'When it happened';
  static const String add = 'Add to our sky';
  static const String save = 'Save';
  static const String remove = 'Remove this moment';
  static const String confirmRemove = 'Remove this moment?';
  static const String confirmRemoveNote = 'It will fade from our constellation for both of us.';
  static const String confirmRemoveYes = 'Remove';
  static const String keep = 'Keep it';

  static const String saveFailed = 'That moment did not save. Our Space may have locked.';
  static const String deleteFailed = 'That moment could not be removed. Our Space may have locked.';
  static const String updateFailed = 'That change did not save. Our Space may have locked.';

  static const List<String> _numbers = [
    'Zero',
    'One',
    'Two',
    'Three',
    'Four',
    'Five',
    'Six',
    'Seven',
    'Eight',
    'Nine',
    'Ten',
    'Eleven',
  ];

  static String today(int day) => 'Today · day $day';

  static String beganNote(String date) => '$date · the first star';

  static String openMoment(String title, String date) => '$title, $date. $editTitle';

  static String hidden(int count) =>
      '$count moment${count == 1 ? '' : 's'} could not be opened with your passphrase, so '
      '${count == 1 ? 'it is' : 'they are'} hidden for now.';

  static String? notice({required String error, required int unreadable}) {
    if (error.isNotEmpty) return error;
    if (unreadable > 0) return hidden(unreadable);
    return null;
  }

  static String inDays(int days) {
    if (days <= 0) return 'today';
    if (days == 1) return 'tomorrow';
    return 'in $days days';
  }

  static String months(int count) => count == 1 ? 'One month' : '${_word(count)} months';

  static String years(int count) => count == 1 ? 'First year' : '${_word(count)} years';

  static String hundred(int day) => 'Day $day';

  static String clock(int days, int hours, int minutes) =>
      'Together $days ${days == 1 ? 'day' : 'days'}, $hours ${hours == 1 ? 'hour' : 'hours'} '
      'and $minutes ${minutes == 1 ? 'minute' : 'minutes'}';

  static String _word(int count) => count >= 0 && count < _numbers.length ? _numbers[count] : '$count';
}
