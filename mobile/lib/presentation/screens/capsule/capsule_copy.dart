import '../../../core/engine.dart';

abstract final class CapsuleCopy {
  static const String title = 'Secret Capsule';
  static const String subtitle = 'Time-locked letters & sweet notes';
  static const String writeLetter = 'Write Letter';
  static const String loading = 'Unsealing your letters...';
  static const String emptyTitle = 'No Letters Yet';
  static const String writeFirst = 'Write First Love Letter 💌';
  static const String readLetter = 'Read Letter 💌';
  static const String unsealing = 'Unsealing...';
  static const String deleteFailed = 'Could not delete that letter. Please try again.';
  static const String saveFailed = 'Could not seal this letter. Please try again.';
  static const String modalTitle = 'Write Love Letter';
  static const String modalSubtitle = 'Only the two of you can read it';
  static const String titleLabel = 'Title / Prompt';
  static const String titleHint = 'e.g. Open when you miss me, or 1st Anniversary';
  static const String titleNote = 'The title still shows while it is sealed — only the letter itself is hidden.';
  static const String bodyLabel = 'Letter Body';
  static const String bodyHint = 'Write your heart out...';
  static const String lockLabel = 'Time-Lock Until (Optional)';
  static const String lockNote =
      'Leave blank to allow opening immediately. A locked letter opens at 00:00 local time on the chosen day.';
  static const String promise =
      'The app will not open a sealed letter early — though anyone who knows your passphrase and changes their phone\'s date could. It is a promise, not a padlock. 💕';
  static const int titleMaxLength = 120;

  static String emptyMessage(String partnerName) =>
      'Leave a surprise letter for $partnerName, or seal a time capsule to open on your next anniversary!';

  static String hiddenLetters(int count) =>
      '$count letter${count == 1 ? '' : 's'} could not be opened with your passphrase, so ${count == 1 ? 'it is' : 'they are'} hidden for now.';

  static String deleteQuestion(String partnerPossessive) =>
      'Delete this love letter? It goes from your phone and $partnerPossessive, for good.';

  static String writtenLine(LetterRecord letter, {required bool isLocked}) {
    final sealed = isLocked && letter.isSealed ? ' · sealed' : '';
    final opened = !isLocked && letter.isOpened ? ' · already opened' : '';
    return 'Written on ${prettyTimestamp(letter.writtenAt)}$sealed$opened';
  }

  static String sealButton({required bool saving, String? unlockDate}) {
    final dated = unlockDate != null && unlockDate.isNotEmpty;
    if (saving) return dated ? 'Sealing…' : 'Tucking it away…';
    return dated ? 'Seal Until ${formatDatePretty(unlockDate)} 🔒' : 'Seal with Wax Stamp 💌';
  }
}

String prettyTimestamp(int milliseconds) {
  if (milliseconds == 0) return '';
  return formatDatePretty(toLocalDateInput(DateTime.fromMillisecondsSinceEpoch(milliseconds)));
}
