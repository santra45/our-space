import 'dart:ui' as ui;

import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import '../../../core/engine.dart';

String capitalized(String text) {
  if (text.isEmpty) return text;
  return text[0].toUpperCase() + text.substring(1);
}

class DailyStatus {
  const DailyStatus(this.strong, this.rest);

  final String strong;
  final String rest;

  String get sentence => '$strong · $rest';

  @override
  bool operator ==(Object other) => other is DailyStatus && other.strong == strong && other.rest == rest;

  @override
  int get hashCode => Object.hash(strong, rest);

  @override
  String toString() => sentence;
}

abstract final class DailyCopy {
  static const String placeholder = 'However much or little you want…';
  static const String saving = 'Saving…';
  static const String answer = 'Answer';
  static const String saveFailed = 'That did not save. Try again in a moment.';
  static const String loadFailed = 'The question did not open just now. Nothing was lost.';
  static const String tryAgain = 'Try again';
  static const String finding = 'Finding the question…';
  static const String backToArchive = 'Back to the archive';
  static const String you = 'You';
  static const String everyDay = 'Every day so far';
  static const String archiveEmpty = "Nothing here yet. Answer today's and it starts filling itself.";
  static const String fromBackThen = 'A question from back then';
  static const String missedGone = 'You missed this one. The question it was asking is no longer in the app.';
  static const String youPrefix = 'You: ';
  static const String backToToday = 'Back to today';
  static const String close = 'Close';
  static const String justNow = 'just now';
  static const String bothAnswered = 'You both answered';
  static const String sendLoveBack = 'Send love back';
  static const String readBoth = 'Read both answers';
  static const String seeYours = 'See your answer';

  static String when(bool night) => night ? 'Tonight' : 'Today';

  static String questionLabel(bool night) => night ? "Tonight's question" : "Today's question";

  static String lightStar(bool night) => night ? "Light tonight's star" : "Light today's star";

  static String seeStar(bool night) => night ? "See tonight's star" : "See today's star";

  static String starIsLit(bool night) => night ? "Tonight's star is lit" : "Today's star is lit";

  static String starLower(bool night) => night ? "tonight's star" : "today's star";

  static String quoted(String question) => '“$question”';

  static String writeVerb(PronounSet grammar) => grammar.has == 'have' ? 'write' : 'writes';

  static DailyStatus status({
    required bool bothIn,
    required bool answered,
    required bool partnerWaiting,
    required bool night,
    required String partnerName,
    required String partnerPossessive,
    required PronounSet partnerGrammar,
  }) {
    if (bothIn) return DailyStatus(bothAnswered, '${starLower(night)} is lit');
    if (answered) {
      return DailyStatus(
        'You answered',
        '$partnerPossessive appears the moment ${partnerGrammar.subject} ${writeVerb(partnerGrammar)} one',
      );
    }
    if (partnerWaiting) return DailyStatus('${capitalized(partnerName)} answered', 'opens when you do');
    return const DailyStatus('Your turn', 'it opens when you both answer');
  }

  static String catchUpHint(String partnerName) =>
      'You did not answer this one at the time. Write it now and what $partnerName wrote that day opens.';

  static String partnerWaitingHint(String partnerName) =>
      '${capitalized(partnerName)} has answered already. Write yours and you will both be able to read them.';

  static String notUntilYours(String partnerPossessive) =>
      'You will not see $partnerPossessive until you have written yours.';

  static String nothingYet(String partnerName) =>
      'Nothing from $partnerName yet today. It will appear here on its own.';

  static String missed(String partnerPossessive) =>
      'You missed this one, and something of $partnerPossessive is waiting behind it. Tap to answer it now.';

  static String partnerPrefix(String partnerName) => '${capitalized(partnerName)}: ';

  static String revealKicker({required bool night, int? dayNumber, required int stars}) {
    final lead = dayNumber == null ? when(night) : '${night ? 'Night' : 'Day'} $dayNumber';
    return '$lead · Star $stars';
  }

  static String answeredAt(int answeredAt, {int? now, String? locale}) {
    if (answeredAt <= 0) return '';
    final current = now ?? DateTime.now().millisecondsSinceEpoch;
    if ((current - answeredAt).abs() < 60000) return justNow;
    final at = DateTime.fromMillisecondsSinceEpoch(answeredAt);
    final today = DateTime.fromMillisecondsSinceEpoch(current);
    if (at.year == today.year && at.month == today.month && at.day == today.day) {
      _ensureDateSymbols();
      try {
        return DateFormat.jm(locale ?? deviceDateLocale()).format(at);
      } catch (_) {
        return DateFormat.jm('en_US').format(at);
      }
    }
    return prettyDay(dayKeyOf(at), locale: locale);
  }

  static String dayKeyOf(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

bool _dateSymbolsReady = false;

void _ensureDateSymbols() {
  if (_dateSymbolsReady) return;
  initializeDateFormatting();
  _dateSymbolsReady = true;
}

String deviceDateLocale() {
  final locale = ui.PlatformDispatcher.instance.locale;
  return locale.languageCode == 'en' ? locale.toString() : 'en_US';
}

String prettyDay(String day, {String? locale}) {
  final date = dateFromDayKey(day);
  if (date == null) return day;
  _ensureDateSymbols();
  try {
    return DateFormat.MMMMd(locale ?? deviceDateLocale()).format(date);
  } catch (_) {
    return DateFormat.MMMMd('en_US').format(date);
  }
}
