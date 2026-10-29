abstract final class RouletteCopy {
  static const String title = 'Date night';
  static const String anotherIdea = 'Another idea';
  static const String tonight = 'Scratch for tonight';
  static const String weekend = 'Scratch for this weekend';
  static const String hint = 'Rub the gold with your finger';
  static const String revealed = 'Our plan is ready. Enjoy it together';
  static const String dateIdea = 'Our date';
  static const String scratchHere = 'Scratch here';
  static const String scratchLabel = 'Gold to scratch away, hiding our next date idea';
  static const String categories = 'Kinds of date';

  static const String ideasEntry = 'Our date ideas';
  static const String ideasKicker = 'Date night';
  static const String ideasTitle = 'Our date ideas';
  static const String ideasNote = 'Add our own, change any of them, or take out the ones that are not us.';
  static const String addIdea = 'Add a date idea';
  static const String change = 'Change this idea';
  static const String otherKind = 'Other ideas';
  static const String emptyAll = 'No date ideas yet';
  static const String emptyKind = 'No date ideas of this kind yet';
  static const String emptyNote = 'Add one of our own below';
  static const String emptyHint = 'Our ideas are waiting to be written';

  static const String newTitle = 'A new date idea';
  static const String editTitle = 'Change this date idea';
  static const String titleLabel = 'The date';
  static const String titleHint = 'Cook the same dinner on a video call';
  static const String descLabel = 'How it goes';
  static const String descHint = 'Same recipe, same playlist, two kitchens';
  static const String kindLabel = 'What kind of date';
  static const String add = 'Add to our ideas';
  static const String save = 'Save';
  static const String remove = 'Remove this idea';
  static const String confirmRemove = 'Remove this date idea?';
  static const String confirmRemoveNote = 'It will be gone for both of us.';
  static const String confirmRemoveYes = 'Remove';
  static const String keep = 'Keep it';
  static const String saveFailed = 'That idea did not save. Our Space may have locked.';
  static const String removeFailed = 'That idea could not be removed. Our Space may have locked.';

  static String categoryLabel(String id, String label) {
    switch (id) {
      case 'athome':
        return 'At home';
      default:
        return label;
    }
  }

  static String ideasCount(int count) => count == 1 ? '1 idea' : '$count ideas';

  static String ideasEntryLabel(int count) => '$ideasEntry, ${ideasCount(count)}';

  static String hiddenIdeas(int count) =>
      '$count idea${count == 1 ? '' : 's'} could not be opened with your passphrase, so ${count == 1 ? 'it is' : 'they are'} hidden for now.';
}
