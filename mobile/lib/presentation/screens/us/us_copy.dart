import 'package:intl/intl.dart';

abstract final class UsCopy {
  static const String title = 'Us';
  static const String kicker = 'The two of us';
  static const String story = 'Our story';
  static const String dreams = 'Dreams';
  static const String dates = 'Date night';
  static const String dateLabel = 'Date';
  static const String since = 'Since';
}

abstract final class UsDates {
  static final DateFormat _dayMonth = DateFormat('d MMMM');
  static final DateFormat _dayMonthYear = DateFormat('d MMMM y');
  static final DateFormat _shortDayMonth = DateFormat('d MMM');
  static final DateFormat _shortDayMonthYear = DateFormat('d MMM y');

  static String long(DateTime date, [DateTime? now]) =>
      date.year == (now ?? DateTime.now()).year ? _dayMonth.format(date) : _dayMonthYear.format(date);

  static String short(DateTime date, [DateTime? now]) =>
      date.year == (now ?? DateTime.now()).year ? _shortDayMonth.format(date) : _shortDayMonthYear.format(date);

  static String full(DateTime date) => _dayMonthYear.format(date);
}
