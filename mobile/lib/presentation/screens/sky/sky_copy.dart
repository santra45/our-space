import 'sky_days.dart';

abstract final class SkyHomeCopy {
  static const String letterFell = 'A letter fell from the sky';
  static const String answerToLight = 'answer to light it';
  static const String waitingToOpen = 'waiting to open';

  static String kicker({required bool night, int? dayNumber, required String weekday}) {
    final lead = dayNumber == null ? (night ? 'Tonight' : 'Today') : '${night ? 'Night' : 'Day'} $dayNumber';
    return '$lead · $weekday';
  }

  static String title(bool night) => night ? 'Our sky, tonight' : 'Our sky, today';

  static String tonightStar(bool night) => night ? "Tonight's star" : "Today's star";

  static const String almostLit = 'almost lit';

  static String dayOfForever(int dayNumber) => 'Day $dayNumber of forever';

  static String stars(int count) => '$count';

  static String starsLabel(int count) => count == 1 ? 'star joined' : 'stars joined';

  static String milestoneValue(SkyMilestone milestone, {required bool night}) {
    final left = milestone.daysLeft;
    if (left <= 0) return night ? 'Tonight' : 'Today';
    final unit = night ? 'night' : 'day';
    return left == 1 ? '1 $unit' : '$left ${unit}s';
  }

  static String milestoneLabel(SkyMilestone milestone) =>
      milestone.daysLeft <= 0 ? '${milestone.name} together' : 'to ${milestone.name}';

  static String letters(int count) {
    if (count <= 0) return 'No letters';
    return count == 1 ? '1 letter' : '$count letters';
  }

  static String statSemantics(String value, String label) => '$value $label';

  static String skySemantics({
    required int stars,
    required bool night,
    required bool lit,
    required bool waiting,
    required int letters,
  }) {
    final parts = [
      stars == 1 ? 'One star in our sky' : '${stars == 0 ? 'No' : stars} stars in our sky',
      if (lit) '${tonightStar(night)} is lit',
      if (waiting) '${tonightStar(night)} is waiting',
      if (letters > 0) letterFell,
    ];
    return '${parts.join('. ')}.';
  }
}
