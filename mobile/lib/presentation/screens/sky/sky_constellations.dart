import 'package:flutter/foundation.dart';

import '../../../core/engine/domain/daily_question.dart' show dateFromDayKey;
import '../../../models/daily_answers_record.dart';
import '../../sky/sky_constellation.dart';

@immutable
class StarNight {
  const StarNight({required this.number, required this.day, this.answers});

  final int number;
  final String day;
  final AnsweredDay? answers;

  int get star => number - 1;

  int get constellation => star ~/ ConstellationShape.count;

  int get position => star % ConstellationShape.count;

  ConstellationShape get shape => ConstellationShape.at(constellation);

  int get slot => shape.order[position];

  DateTime? get date => dateFromDayKey(day);

  DailyQuestion? get question => answers?.question;

  DailyAnswerEntry? get mine => answers?.mine;

  DailyAnswerEntry? get theirs => answers?.theirs;

  @override
  bool operator ==(Object other) =>
      other is StarNight && other.number == number && other.day == day && identical(other.answers, answers);

  @override
  int get hashCode => Object.hash(number, day, answers);

  @override
  String toString() => 'Night $number ($day)';
}

@immutable
class ConstellationChapter {
  ConstellationChapter({required this.index, required List<StarNight> nights})
    : nights = List<StarNight>.unmodifiable(nights);

  static const int size = ConstellationShape.count;

  static const List<String> _ordinals = [
    'first',
    'second',
    'third',
    'fourth',
    'fifth',
    'sixth',
    'seventh',
    'eighth',
    'ninth',
    'tenth',
    'eleventh',
    'twelfth',
    'thirteenth',
    'fourteenth',
    'fifteenth',
    'sixteenth',
    'seventeenth',
    'eighteenth',
    'nineteenth',
    'twentieth',
  ];

  final int index;
  final List<StarNight> nights;

  int get number => index + 1;

  ConstellationShape get shape => ConstellationShape.at(index);

  int get lit => nights.length;

  bool get started => nights.isNotEmpty;

  bool get complete => lit >= size;

  int? get nextSlot => complete ? null : shape.order[lit];

  Set<int> get litSlots => {for (final night in nights) night.slot};

  Set<int> get unlitSlots => {for (var i = lit; i < size; i++) shape.order[i]};

  StarNight? get latest => nights.isEmpty ? null : nights.last;

  StarNight? nightAt(int slot) {
    for (final night in nights) {
      if (night.slot == slot) return night;
    }
    return null;
  }

  String? get firstDay => nights.isEmpty ? null : nights.first.day;

  String? get lastDay => nights.isEmpty ? null : nights.last.day;

  DateTime? get from => nights.isEmpty ? null : nights.first.date;

  DateTime? get to => nights.isEmpty ? null : nights.last.date;

  static String ordinalOf(int number) {
    if (number >= 1 && number <= _ordinals.length) return _ordinals[number - 1];
    final teen = number % 100 >= 11 && number % 100 <= 13;
    final suffix = teen ? 'th' : switch (number % 10) { 1 => 'st', 2 => 'nd', 3 => 'rd', _ => 'th' };
    return '$number$suffix';
  }

  static String titleOf(int index) => 'Our ${ordinalOf(index + 1)} constellation';

  static String completeLineOf(int index) => '${titleOf(index)} is complete';

  String get ordinal => ordinalOf(number);

  String get title => titleOf(index);

  String get name => shape.title;

  String get label => '$title · $name';

  String get completeLine => completeLineOf(index);

  @override
  bool operator ==(Object other) =>
      other is ConstellationChapter && other.index == index && listEquals(other.nights, nights);

  @override
  int get hashCode => Object.hash(index, Object.hashAll(nights));

  @override
  String toString() => '$label ($lit of $size)';
}

@immutable
class ConstellationSeries {
  ConstellationSeries({required List<StarNight> nights, required this.today})
    : nights = List<StarNight>.unmodifiable(nights);

  factory ConstellationSeries.fromAnswered(Iterable<AnsweredDay> answered, {required String today}) {
    final both = answered.where((day) => day.theirs != null).toList()..sort((a, b) => a.day.compareTo(b.day));
    return ConstellationSeries(
      nights: [for (var i = 0; i < both.length; i++) StarNight(number: i + 1, day: both[i].day, answers: both[i])],
      today: today,
    );
  }

  factory ConstellationSeries.fromDays(Iterable<String> days, {required String today}) {
    final sorted = days.toSet().toList()..sort();
    return ConstellationSeries(
      nights: [for (var i = 0; i < sorted.length; i++) StarNight(number: i + 1, day: sorted[i])],
      today: today,
    );
  }

  static const int size = ConstellationShape.count;

  final List<StarNight> nights;
  final String today;

  int get stars => nights.length;

  bool get litToday => nights.any((night) => night.day == today);

  int get currentIndex => litToday ? (stars - 1) ~/ size : stars ~/ size;

  ConstellationChapter chapter(int index) => ConstellationChapter(
    index: index,
    nights: [for (final night in nights) if (night.constellation == index) night],
  );

  ConstellationChapter get current => chapter(currentIndex);

  List<ConstellationChapter> get constellations => [for (var i = 0; i <= currentIndex; i++) chapter(i)];

  List<ConstellationChapter> get completed => [
    for (final chapter in constellations)
      if (chapter.complete) chapter,
  ];

  bool get completedTonight => litToday && stars > 0 && stars % size == 0;

  int? get tonightSlot => litToday ? null : current.nextSlot;

  StarNight? get latest => nights.isEmpty ? null : nights.last;

  StarNight? nightAt(int slot) => current.nightAt(slot);

  StarNight? nightOn(String day) {
    for (final night in nights) {
      if (night.day == day) return night;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is ConstellationSeries && other.today == today && listEquals(other.nights, nights);

  @override
  int get hashCode => Object.hash(today, Object.hashAll(nights));
}
