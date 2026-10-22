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

  static String categoryLabel(String id, String label) {
    switch (id) {
      case 'athome':
        return 'At home';
      default:
        return label;
    }
  }
}
