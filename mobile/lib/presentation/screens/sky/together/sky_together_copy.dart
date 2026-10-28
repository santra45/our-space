abstract final class SkyTogetherCopy {
  static String body(bool night) => night ? 'moon' : 'sun';

  static String hold(bool night) => 'Hold the ${body(night)} together';

  static String waiting(String partner) => 'Waiting for $partner to hold on too';

  static const String bothHolding = "You're both holding on";

  static const String intoPatch = 'Into a patch of sky,\njust for us';

  static String holdLabel(bool night, String partner) => '${hold(night)} with $partner';

  static String holdHint(String partner) => 'Press and hold with $partner';

  static const String holdingOn = 'Holding on';

  static String _lead({required bool night, int? dayNumber}) =>
      dayNumber == null ? (night ? 'Tonight' : 'Today') : '${night ? 'Night' : 'Day'} $dayNumber';

  static String patchKicker({required bool night, int? dayNumber}) =>
      '${_lead(night: night, dayNumber: dayNumber)} · our own patch of sky';

  static String drawingWith(String partner) => '$partner is here, drawing with you';

  static const String drawTitle = 'Draw it together';

  static const String leave = 'Leave for now';

  static const String help = 'Tap for a star · drag from star to star · tap yours to take it away';

  static List<String> get helpParts => help.split(' · ');

  static String starsLeft(int count) => count == 1 ? '1 star left' : '$count stars left';

  static const String fullOfStars = 'This patch is full of stars';

  static const String noRoomForLines = 'No more room for lines';

  static const String startOver = 'Start over';

  static const String done = "We're done";

  static const String startOverTitle = 'Start over?';

  static const String startOverMessage = 'This clears every star you both placed.';

  static const String keepDrawing = 'Keep drawing';

  static String startedOver(String partner) => '$partner started over';

  static String steppedAway(String partner) => '$partner stepped away';

  static String steppedAwayMessage(bool night) =>
      'Your drawing stays just as it is. ${hold(night)} to pick it up again.';

  static const String backToSky = 'Back to our sky';

  static String patchLabel({required int stars, required int lines}) {
    final s = stars == 1 ? 'one star' : '${stars == 0 ? 'no' : stars} stars';
    final l = lines == 1 ? 'one line' : '${lines == 0 ? 'no' : lines} lines';
    return 'Our own patch of sky, with $s and $l';
  }

  static const String addStar = 'Add a star';

  static const String joinNewest = 'Join the newest two stars';

  static const String yourStar = 'Your star, tap to take it away';

  static String partnerStar(String partner) => "$partner's star";

  static String nameKicker({required bool night, int? dayNumber}) =>
      '${_lead(night: night, dayNumber: dayNumber)} · drawn together';

  static const String nameTitle = 'Give it a name';

  static const String backToDrawing = 'Back to drawing';

  static const String nameLabel = 'What shall we call it?';

  static const String nameHint = 'Something only we would call it';

  static String seesIt(String partner) => '$partner sees it as you type';

  static String waitingYes(String partner) => 'Waiting for $partner to say yes';

  static const String isNamingIt = ' is naming it';

  static String naming(String typer) => '$typer$isNamingIt';

  static const String sayYes = 'Say yes and it stays in our sky, for both of us';

  static const String changeIt = 'Change it';

  static const String yes = "Yes, that's it";

  static const String saved = 'Saved in our sky';
}
