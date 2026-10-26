import 'package:flutter/foundation.dart';

import '../screens/sky/sky_constellations.dart';
import '../sky/sky_constellation.dart';
import '../sky/sky_tokens.dart';

abstract final class SkyWidgetCopy {
  static const String empty = 'Our Space';

  static String stars(int count) => count == 1 ? '1 star' : '$count stars';
}

abstract final class SkyWidgetKeys {
  static const String provider = 'com.ourspace.our_space_mobile.SkyWidgetProvider';
  static const String label = 'sky_widget_label';
  static const String night = 'sky_widget_night';
  static const String sky = 'sky_widget_sky';
  static const String stars = 'sky_widget_stars';

  static const List<String> all = [label, night, sky, stars];
}

@immutable
class SkyWidgetState {
  const SkyWidgetState.empty({this.night = true}) : stars = 0, constellation = null;

  const SkyWidgetState._({required this.stars, required this.night, required this.constellation});

  factory SkyWidgetState.forSeries(ConstellationSeries series, {required bool night}) {
    if (series.stars <= 0) return SkyWidgetState.empty(night: night);
    final chapter = series.current;
    return SkyWidgetState._(
      stars: series.stars,
      night: night,
      constellation: SkyConstellation(
        shape: chapter.shape,
        gap: null,
        complete: chapter.complete,
        presence: false,
        unlit: chapter.unlitSlots,
        gapGuide: false,
      ),
    );
  }

  final int stars;
  final bool night;
  final SkyConstellation? constellation;

  bool get isEmpty => constellation == null;

  SkyMode get mode => night ? SkyMode.night : SkyMode.day;

  String get label => isEmpty ? SkyWidgetCopy.empty : SkyWidgetCopy.stars(stars);

  Map<String, Object> get data => {SkyWidgetKeys.label: label, SkyWidgetKeys.night: night};

  SkyWidgetState inMode({required bool night}) =>
      night == this.night ? this : SkyWidgetState._(stars: stars, night: night, constellation: constellation);

  @override
  bool operator ==(Object other) =>
      other is SkyWidgetState && other.stars == stars && other.night == night && other.constellation == constellation;

  @override
  int get hashCode => Object.hash(stars, night, constellation);

  @override
  String toString() => 'SkyWidgetState($label, ${night ? 'night' : 'day'})';
}
