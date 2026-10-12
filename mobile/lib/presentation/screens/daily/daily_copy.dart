import 'dart:ui' as ui;

import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import '../../../core/engine.dart';

abstract final class DailyCopy {
  static const String heading = "Today's question";
  static const String tapToAnswer = 'Tap to answer';
  static const String bothAnswered = 'You both answered. Tap to read 💕';
  static const String placeholder = 'However much or little you want…';
  static const String saving = 'Saving…';
  static const String answer = 'Answer 💕';
  static const String saveFailed = 'That did not save. Try again in a moment.';
  static const String backToArchive = 'Back to the archive';
  static const String you = 'You';
  static const String everything = 'Everything you have both written';
  static const String everyDay = 'Every day so far';
  static const String archiveEmpty = "Nothing here yet. Answer today's and it starts filling itself.";
  static const String fromBackThen = 'A question from back then';
  static const String missedGone = 'You missed this one. The question it was asking is no longer in the app.';
  static const String youPrefix = 'You: ';
  static const String backToToday = 'Back to today';

  static String writeVerb(PronounSet grammar) => grammar.has == 'have' ? 'write' : 'writes';

  static String answered(String partnerPossessive, PronounSet grammar) =>
      'Answered. $partnerPossessive appears the moment ${grammar.subject} ${writeVerb(grammar)} one.';

  static String partnerFirst(String partnerName) => '$partnerName has already answered. Yours unlocks it 💕';

  static String status({
    required bool bothIn,
    required bool answered,
    required bool partnerWaiting,
    required String partnerName,
    required String partnerPossessive,
    required PronounSet partnerGrammar,
  }) {
    if (bothIn) return bothAnswered;
    if (answered) return DailyCopy.answered(partnerPossessive, partnerGrammar);
    if (partnerWaiting) return partnerFirst(partnerName);
    return tapToAnswer;
  }

  static String catchUpHint(String partnerName) =>
      'You did not answer this one at the time. Write it now and what $partnerName wrote that day opens.';

  static String partnerWaitingHint(String partnerName) =>
      '$partnerName has answered already. Write yours and you will both be able to read them.';

  static String notUntilYours(String partnerPossessive) =>
      'You will not see $partnerPossessive until you have written yours.';

  static String nothingYet(String partnerName) =>
      'Nothing from $partnerName yet today. It will appear here on its own.';

  static String missed(String partnerPossessive) =>
      'You missed this one, and something of $partnerPossessive is waiting behind it. Tap to answer it now 💕';

  static String partnerPrefix(String partnerName) => '$partnerName: ';
}

bool _dateSymbolsReady = false;

String deviceDateLocale() {
  final locale = ui.PlatformDispatcher.instance.locale;
  return locale.languageCode == 'en' ? locale.toString() : 'en_US';
}

String prettyDay(String day, {String? locale}) {
  final date = dateFromDayKey(day);
  if (date == null) return day;
  if (!_dateSymbolsReady) {
    initializeDateFormatting();
    _dateSymbolsReady = true;
  }
  try {
    return DateFormat.MMMMd(locale ?? deviceDateLocale()).format(date);
  } catch (_) {
    return DateFormat.MMMMd('en_US').format(date);
  }
}
