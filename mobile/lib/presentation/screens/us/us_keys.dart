import 'package:flutter/widgets.dart';

abstract final class UsKeys {
  static const Key hero = ValueKey<String>('us-hero');
  static const Key upcoming = ValueKey<String>('us-upcoming');
  static const Key constellation = ValueKey<String>('us-constellation');
  static const Key dreams = ValueKey<String>('us-dreams');
  static const Key dateNight = ValueKey<String>('us-date-night');

  static const Key todayStep = ValueKey<String>('us-step-today');
  static const Key beganStep = ValueKey<String>('us-step-began');
  static const Key emptyStep = ValueKey<String>('us-step-empty');

  static const Key momentTitle = ValueKey<String>('us-moment-title');
  static const Key momentDate = ValueKey<String>('us-moment-date');
  static const Key momentSave = ValueKey<String>('us-moment-save');
  static const Key momentRemove = ValueKey<String>('us-moment-remove');

  static const Key togetherDate = ValueKey<String>('us-together-date');
  static const Key togetherSave = ValueKey<String>('us-together-save');

  static const Key dreamCount = ValueKey<String>('us-dream-count');
  static const Key dreamProgress = ValueKey<String>('us-dream-progress');
  static const Key addDream = ValueKey<String>('us-add-dream');
  static const Key dreamText = ValueKey<String>('us-dream-text');
  static const Key dreamSave = ValueKey<String>('us-dream-save');
  static const Key dreamRemove = ValueKey<String>('us-dream-remove');

  static const Key scratchPanel = ValueKey<String>('us-scratch-panel');
  static const Key ideaCategories = ValueKey<String>('us-idea-categories');

  static Key moment(String id) => ValueKey<String>('us-moment-$id');

  static Key dream(String id) => ValueKey<String>('us-dream-$id');
}
