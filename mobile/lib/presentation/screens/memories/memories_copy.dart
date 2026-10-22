abstract final class MemoriesCopy {
  static const String title = 'Memories';
  static const String kickerEmpty = 'Kept, just us';
  static const String opening = 'Opening your memories';
  static const String addLabel = 'Add a memory';
  static const String wallError = 'We could not open your memories just now. Please try again.';
  static const String retry = 'Try again';
  static const String lockedTitle = 'Our Space is resting';
  static const String lockedMessage = 'Unlock Our Space to see your memories again.';
  static const String emptyTitle = 'Your first memory';
  static const String createFirst = 'Pin your first memory';
  static const String emptyCaption = 'our first one';
  static const String undated = 'Some day';

  static String kicker(int count) => count <= 0 ? kickerEmpty : '$count kept, just us';

  static String hidden(int count) =>
      '$count ${count == 1 ? 'memory' : 'memories'} could not be opened with your passphrase, so '
      '${count == 1 ? 'it is' : 'they are'} hidden for now.';

  static String emptyMessage(String partnerName) =>
      'Pin a photo of the two of you. It stays right here, just for you and $partnerName.';

  static const String byYou = 'by you';
  static String byPartner(String name) => 'by $name';
  static const String newBadge = 'New';
  static const String developing = 'Developing';
  static const String noImage = 'No photo here';
  static const String photoLocked = 'This photo could not be unlocked.';
  static const String specialMoment = 'A special moment';
  static const String photoAlt = 'A memory';

  static const String removeLabel = 'Remove this memory';
  static const String removeTitle = 'Remove this memory?';
  static const String removeMessage = 'It will be gone for both of you. This cannot be undone.';
  static const String removeConfirm = 'Remove it';
  static const String removeCancel = 'Keep it';
  static const String alreadyRemoved = 'That memory was already removed.';
  static const String removeFailed = 'This memory could not be removed. Please try again.';
  static String removeFailedWith(String message) => 'This memory could not be removed: $message';

  static const String close = 'Close';
  static const String wholePhoto = 'The whole photo';

  static const String sheetKicker = 'Kept just between you two';
  static const String sheetTitle = 'A new memory';
  static const String captureOrChoose = 'Capture or choose a photo together';
  static const String camera = 'Take a photo';
  static const String gallery = 'Choose a photo';
  static const String changePhoto = 'Change photo';
  static const String previewAlt = 'Your chosen photo';
  static const String captionLabel = 'Caption';
  static const String captionHint = 'Write a sweet note or memory...';
  static const String dateLabel = 'Date taken';
  static const String pinIt = 'Pin it to our wall';
  static const String pinning = 'Pinning it up...';
  static const String gettingReady = 'Getting it ready...';
  static const String tuckingAway = 'Tucking it away safely...';
  static const String savingWall = 'Pinning it to your wall...';
  static const String fillCaption = 'Write a little caption first.';
  static const String lockedTryAgain = 'Our Space is locked. Unlock it and try again.';
  static const String saveFailed = 'This memory could not be kept. Please try again.';
  static String saveFailedWith(String message) => 'This memory could not be kept: $message';
  static const String tooLarge = 'This photo is still a little too big, even after making it smaller. Try a smaller one.';
  static const String cameraFailed = 'We could not open your camera just now. Please try again.';
  static const String galleryFailed = 'We could not open your photos just now. Please try again.';

  static const int captionMaxLength = 280;

  static const List<String> _months = [
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

  static const List<String> _shortMonths = [
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

  static String month(DateTime month, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final name = _months[month.month - 1];
    return month.year == today.year ? name : '$name ${month.year}';
  }

  static String day(DateTime date) => '${date.day} ${_shortMonths[date.month - 1]}';

  static String fullDay(DateTime date) => '${date.day} ${_shortMonths[date.month - 1]} ${date.year}';

  static String meta(List<String?> parts) => [
        for (final part in parts)
          if (part != null && part.isNotEmpty) part,
      ].join(' · ');
}
