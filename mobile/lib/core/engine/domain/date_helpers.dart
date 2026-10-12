import '../crypto/js_compat.dart';

const int msPerDay = 1000 * 60 * 60 * 24;

final RegExp _dateOnlyPattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');
final RegExp _utcMidnightPattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})T00:00:00(?:\.0+)?Z$');

const List<String> _shortMonths = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

int _jsYear(int year) => (year >= 0 && year <= 99) ? 1900 + year : year;

DateTime? parseLocalDate(Object? value, {int? now}) {
  if (value == null || value == '') return DateTime.fromMillisecondsSinceEpoch(now ?? systemNow());
  if (value is DateTime) return value;
  if (value is String) {
    final trimmed = jsTrim(value);
    if (_dateOnlyPattern.hasMatch(trimmed)) {
      final parts = trimmed.split('-').map(int.parse).toList();
      return DateTime(_jsYear(parts[0]), parts[1], parts[2]);
    }
    final utcMidnight = _utcMidnightPattern.firstMatch(trimmed);
    if (utcMidnight != null) {
      return DateTime(
        _jsYear(int.parse(utcMidnight.group(1)!)),
        int.parse(utcMidnight.group(2)!),
        int.parse(utcMidnight.group(3)!),
      );
    }
    if (trimmed.contains('T')) {
      final parsed = DateTime.tryParse(trimmed);
      if (parsed != null) return parsed.toLocal();
    }
    final fallback = DateTime.tryParse(value);
    return fallback?.toLocal();
  }
  if (value is num && value.isFinite) {
    return DateTime.fromMillisecondsSinceEpoch(value.floor());
  }
  return null;
}

bool isValidDateInput(Object? value) {
  if (value is! String) return false;
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) return false;
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  return month >= 1 && month <= 12 && day >= 1 && day <= 31;
}

DateTime startOfLocalDay(DateTime date) => DateTime(date.year, date.month, date.day);

String toLocalDateInput([DateTime? date]) {
  final d = date ?? DateTime.now();
  return '${d.year}-${twoDigits(d.month)}-${twoDigits(d.day)}';
}

String localDateString([DateTime? date]) => toLocalDateInput(date);

class LoveDuration {
  const LoveDuration({required this.totalDays, required this.hours, required this.minutes, required this.seconds});

  static const LoveDuration zero = LoveDuration(totalDays: 0, hours: 0, minutes: 0, seconds: 0);

  final int totalDays;
  final int hours;
  final int minutes;
  final int seconds;
}

LoveDuration calculateLoveDuration(String? startDate, {int? now}) {
  if (startDate == null || startDate.isEmpty) return LoveDuration.zero;
  final start = parseLocalDate(startDate);
  if (start == null) return LoveDuration.zero;
  final diffRaw = (now ?? systemNow()) - start.millisecondsSinceEpoch;
  final diff = diffRaw < 0 ? 0 : diffRaw;
  return LoveDuration(
    totalDays: (diff / msPerDay).floor(),
    hours: ((diff / (1000 * 60 * 60)) % 24).floor(),
    minutes: ((diff / (1000 * 60)) % 60).floor(),
    seconds: ((diff / 1000) % 60).floor(),
  );
}

class AnniversaryInfo {
  const AnniversaryInfo({required this.date, required this.daysLeft, required this.year});

  final DateTime date;
  final int daysLeft;
  final int year;
}

class HundredDayInfo {
  const HundredDayInfo({required this.milestone, required this.daysLeft});

  final int milestone;
  final int daysLeft;
}

class NextMilestone {
  const NextMilestone({required this.anniversary, required this.hundredDay});

  final AnniversaryInfo anniversary;
  final HundredDayInfo hundredDay;
}

NextMilestone? calculateNextMilestone(String? startDate, [DateTime? nowDate]) {
  if (startDate == null || startDate.isEmpty) return null;
  final start = parseLocalDate(startDate);
  if (start == null) return null;
  final now = nowDate ?? DateTime.now();
  final today = startOfLocalDay(now);

  var nextAnniversary = DateTime(today.year, start.month, start.day);
  if (nextAnniversary.millisecondsSinceEpoch < today.millisecondsSinceEpoch) {
    nextAnniversary = DateTime(today.year + 1, start.month, start.day);
  }
  if (nextAnniversary.year <= start.year) {
    nextAnniversary = DateTime(start.year + 1, start.month, start.day);
  }

  final daysUntilAnniversary =
      ((nextAnniversary.millisecondsSinceEpoch - today.millisecondsSinceEpoch) / msPerDay).round();
  final yearsTogether = nextAnniversary.year - start.year;

  final totalRaw = ((now.millisecondsSinceEpoch - start.millisecondsSinceEpoch) / msPerDay).floor();
  final totalDays = totalRaw < 0 ? 0 : totalRaw;
  final roundUp = (totalDays / 100).ceil() * 100;
  final nextRoundDay = roundUp < 100 ? 100 : roundUp;

  return NextMilestone(
    anniversary: AnniversaryInfo(date: nextAnniversary, daysLeft: daysUntilAnniversary, year: yearsTogether),
    hundredDay: HundredDayInfo(milestone: nextRoundDay, daysLeft: nextRoundDay - totalDays),
  );
}

bool isDateLocked(String? unlockDate, {int? now}) {
  if (unlockDate == null || unlockDate.isEmpty) return false;
  final target = parseLocalDate(unlockDate);
  if (target == null) return false;
  return (now ?? systemNow()) < target.millisecondsSinceEpoch;
}

String formatTimeRemaining(String? targetDate, {int? now}) {
  if (targetDate == null || targetDate.isEmpty) return '';
  final target = parseLocalDate(targetDate);
  if (target == null) return '';
  final diff = target.millisecondsSinceEpoch - (now ?? systemNow());
  if (diff <= 0) return 'Unlocked';
  final days = (diff / msPerDay).floor();
  final hours = ((diff / (1000 * 60 * 60)) % 24).floor();
  final mins = ((diff / (1000 * 60)) % 60).floor();
  if (days > 0) return '${days}d ${hours}h left';
  if (hours > 0) return '${hours}h ${mins}m left';
  return '${mins}m left';
}

String formatDatePretty(String? date) {
  if (date == null || date.isEmpty) return '';
  final parsed = parseLocalDate(date);
  if (parsed == null) return '';
  return '${_shortMonths[parsed.month - 1]} ${parsed.day}, ${parsed.year}';
}

String formatMonthDay(DateTime date) => '${_shortMonths[date.month - 1]} ${date.day}';

String? formatLastSeen(int? timestamp, {int? now}) {
  if (timestamp == null || timestamp == 0) return null;
  final diffRaw = (now ?? systemNow()) - timestamp;
  final diff = diffRaw < 0 ? 0 : diffRaw;
  final seconds = (diff / 1000).floor();
  final minutes = (seconds / 60).floor();
  final hours = (minutes / 60).floor();
  final days = (hours / 24).floor();
  if (minutes < 1) return 'Just now';
  if (minutes < 60) return '${minutes}m ago';
  if (hours < 24) return '${hours}h ago';
  if (days == 1) return 'Yesterday';
  if (days < 7) return '${days}d ago';
  return formatMonthDay(DateTime.fromMillisecondsSinceEpoch(timestamp));
}

String? formatLastConnected(int? timestamp, {int? now}) {
  if (timestamp == null || timestamp == 0) return null;
  final diffRaw = (now ?? systemNow()) - timestamp;
  final diff = diffRaw < 0 ? 0 : diffRaw;
  final minutes = (diff / 60000).floor();
  final hours = (minutes / 60).floor();
  final days = (hours / 24).floor();
  if (minutes < 1) return 'Just now';
  if (minutes < 60) return '${minutes}m ago';
  if (hours < 24) return '${hours}h ago';
  if (days == 1) return 'Yesterday';
  if (days < 7) return '${days}d ago';
  return formatMonthDay(DateTime.fromMillisecondsSinceEpoch(timestamp));
}
