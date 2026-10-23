const List<String> _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String settingsLongDate(DateTime date, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final month = _months[date.month - 1];
  if (date.year == today.year) return '${date.day} $month';
  return '${date.day} $month ${date.year}';
}

String settingsShortDate(DateTime date) => '${date.day} ${_months[date.month - 1].substring(0, 3)} ${date.year}';

String settingsDayMonth(DateTime date, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final short = '${date.day} ${_months[date.month - 1].substring(0, 3)}';
  return date.year == today.year ? short : '$short ${date.year}';
}
