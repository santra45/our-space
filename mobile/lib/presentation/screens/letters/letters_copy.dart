import '../../../core/engine.dart';

abstract final class LettersCopy {
  static const String kicker = 'Fallen from the sky';
  static const String title = 'Letters';
  static const String write = 'Write a letter';
  static const String loading = 'Gathering your letters…';

  static const String waiting = 'Waiting';
  static const String opened = 'Opened';
  static const String sent = 'Sent';
  static String segment(String label, int count) => '$label · $count';

  static const String breakSeal = 'Break the seal';
  static const String breaking = 'Breaking the seal…';
  static const String newTonight = 'New tonight';
  static const String newToday = 'New today';
  static const String waitingForYou = 'Waiting for you';
  static const String alsoWaiting = 'Also waiting';
  static const String openedTogether = 'Opened together';
  static const String seeAll = 'See all';
  static String capsuleFrom(String partner) => 'A time capsule from $partner';
  static String capsuleFor(String partner) => 'A time capsule for $partner';
  static const String readyToOpen = 'ready to open';
  static String waitingFor(String partner) => 'waiting for $partner';
  static const String fromYou = 'From you';
  static String from(String who, String when) => 'From $who · $when';

  static const String emptyTitle = 'No letters yet';
  static String emptyMessage(String partner) =>
      'Leave a surprise letter for $partner, or seal one to open on your next anniversary.';
  static const String writeFirst = 'Write the first letter';
  static const String nothingWaitingTitle = 'Nothing waiting right now';
  static const String nothingWaitingMessage = 'When a new letter lands, it will be right here.';
  static const String noneOpenedTitle = 'No opened letters yet';
  static const String noneOpenedMessage = 'Every letter you open stays here, safe and sound.';
  static const String noneSentTitle = 'Nothing sent yet';
  static String noneSentMessage(String partner) => 'Letters you write for $partner will wait here.';

  static String hiddenLetters(int count) =>
      '$count letter${count == 1 ? '' : 's'} could not be opened with your passphrase, so ${count == 1 ? 'it is' : 'they are'} hidden for now.';

  static const String deleteTitle = 'Let this letter go?';
  static String deleteMessage(String partnerPossessive) =>
      'It will be gone from your phone and $partnerPossessive, for good.';
  static const String deleteConfirm = 'Delete it';
  static const String deleteCancel = 'Keep it';
  static const String deleteFailed = 'We could not delete that letter. Please try again.';
  static const String dismiss = 'Dismiss';

  static const String readIt = 'Read it';
  static const String tryToOpen = 'Try to open it';
  static const String deleteLetter = 'Delete this letter';
  static const String moreFor = 'More for this letter';

  static const String letterFrom = 'A letter from';
  static const String you = 'You';
  static const String openWhen = 'Open when';
  static const String writeBack = 'Write back';
  static const String writeAnother = 'Write another';
  static String stillWaitingFor(String partner) => 'Waiting for $partner';
  static const String sendLove = 'Send love';
  static const String back = 'Back';
  static const String more = 'More';
  static const String withLove = '— with all my love';
  static String signature(String name) => '— $name';
  static String keptUntil(String? lockDate) => 'Kept sealed until ${longDate(lockDate)}, just as promised.';

  static const String newLetter = 'A new letter';
  static const String cancel = 'Cancel';
  static const String saved = 'Saved';
  static const String startWithFeeling = 'Start with a feeling';
  static const List<String> prompts = [
    'Open when you miss me',
    "Open when you can't sleep",
    'For our anniversary',
    'Just because',
  ];
  static const String titleLabel = 'Title';
  static const String titleHelper = "Shows while it's sealed";
  static const String titleHint = 'A few words for the envelope';
  static const String bodyHint = 'Write your heart out…';
  static const String bodyLabel = 'Your letter';
  static String forOnly(String partner) => 'For $partner only';
  static const String sealUntil = 'Keep it sealed until';
  static const String sealOff = 'Off, so it can be opened right away';
  static const String pickDay = 'Keep it sealed until';
  static const String sealNote =
      'A sealed letter opens at midnight on the day you choose. We will not open it early, though someone who knows your passphrase could by changing their phone\'s date. It is a promise, not a padlock.';
  static const String seal = 'Seal with wax';
  static const String sealing = 'Sealing…';
  static const String saveFailed = 'We could not seal this letter. Please try again.';
  static String sealedToast(String partner) => 'Sealed with wax. It is waiting for $partner.';

  static const int titleMaxLength = 120;

  static const List<String> _months = [
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

  static String dayMonth(DateTime date) => '${date.day} ${_months[date.month - 1]}';

  static String dayMonthYear(DateTime date) => '${dayMonth(date)} ${date.year}';

  static String shortDate(DateTime date, DateTime now) => date.year == now.year ? dayMonth(date) : dayMonthYear(date);

  static String longDate(String? date) {
    final parsed = date == null || date.isEmpty ? null : parseLocalDate(date);
    return parsed == null ? '' : dayMonthYear(parsed);
  }

  static String clock(DateTime time) {
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final minutes = time.minute.toString().padLeft(2, '0');
    return '$hour:$minutes ${time.hour < 12 ? 'AM' : 'PM'}';
  }

  static bool isNightHour(DateTime time) => time.hour >= 18 || time.hour < 6;

  static String capitalized(String text) => text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

  static String lowerFirst(String text) => text.isEmpty ? text : text[0].toLowerCase() + text.substring(1);

  static int daysBetween(DateTime from, DateTime to) {
    final a = DateTime.utc(from.year, from.month, from.day);
    final b = DateTime.utc(to.year, to.month, to.day);
    return b.difference(a).inDays;
  }

  static String sealedWhen(int writtenAt, DateTime now) {
    if (writtenAt <= 0) return 'Sealed with love';
    final written = DateTime.fromMillisecondsSinceEpoch(writtenAt);
    final ago = daysBetween(written, now);
    final night = isNightHour(written);
    if (ago <= 0) return night ? 'Sealed tonight' : 'Sealed today';
    if (ago == 1) return night ? 'Sealed last night' : 'Sealed yesterday';
    return 'Sealed ${shortDate(written, now)}';
  }

  static String sealedAt(int writtenAt) {
    if (writtenAt <= 0) return 'Sealed with love';
    final written = DateTime.fromMillisecondsSinceEpoch(writtenAt);
    return 'Sealed ${dayMonth(written)}, ${clock(written)}';
  }

  static String openedWhen(int? openedAt, DateTime now) {
    if (openedAt == null || openedAt <= 0) return 'Opened';
    final opened = DateTime.fromMillisecondsSinceEpoch(openedAt);
    final ago = daysBetween(opened, now);
    if (ago <= 0) return isNightHour(opened) ? 'Opened tonight' : 'Opened today';
    if (ago == 1) return isNightHour(opened) ? 'Opened last night' : 'Opened yesterday';
    return 'Opened ${shortDate(opened, now)}';
  }

  static String newLabel(int writtenAt, DateTime now, {required bool night}) {
    if (writtenAt > 0 && daysBetween(DateTime.fromMillisecondsSinceEpoch(writtenAt), now) <= 1) {
      return night ? newTonight : newToday;
    }
    return waitingForYou;
  }

  static String count(int value, {required bool night}) {
    final unit = night ? 'night' : 'day';
    return '$value $unit${value == 1 ? '' : 's'}';
  }

  static int nightsUntil(int boundary, int now) {
    final left = boundary - now;
    if (left <= 0) return 0;
    return (left / msPerDay).ceil();
  }

  static String opens(String? lockDate, int? boundary, int now, {required bool night}) {
    final when = longDate(lockDate);
    if (boundary == null) return 'Opens $when';
    return 'Opens $when · ${count(nightsUntil(boundary, now), night: night)}';
  }

  static String sealOn(String unlockDate, DateTime now, {required bool night}) {
    final date = parseLocalDate(unlockDate);
    if (date == null) return sealOff;
    final days = daysBetween(now, date);
    final label = shortDate(date, now);
    if (days < 0) return '$label · so it opens right away';
    if (days == 0) return '$label · today, so it opens right away';
    if (days == 1) return '$label · tomorrow';
    return '$label · in ${count(days, night: night)}';
  }

  static ({String? kicker, String headline}) splitTitle(String title) {
    final trimmed = title.trim();
    final match = RegExp(r'^open when\b[\s,:.-]*', caseSensitive: false).firstMatch(trimmed);
    if (match == null) return (kicker: null, headline: trimmed);
    final rest = trimmed.substring(match.end).trim();
    if (rest.isEmpty) return (kicker: null, headline: trimmed);
    return (kicker: openWhen, headline: rest);
  }
}
