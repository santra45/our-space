import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../sky/sky_constellation.dart';
import 'sky_constellation_plan.dart';
import 'sky_constellations.dart';
import 'sky_night_sheet.dart';

abstract final class SkyMapKeys {
  static const Key page = ValueKey<String>('sky-map');
  static const Key empty = ValueKey<String>('sky-map-empty');
  static const Key growing = ValueKey<String>('sky-map-growing');
  static const Key everyDay = ValueKey<String>('sky-map-every-day');
  static const Key finished = ValueKey<String>('sky-map-finished');
  static const Key keepNote = ValueKey<String>('sky-map-keep-note');
  static const Key detail = ValueKey<String>('sky-map-detail');
  static const Key canvas = ValueKey<String>('sky-map-canvas');
  static const Key ghost = ValueKey<String>('sky-map-ghost');
  static const Key starTouch = ValueKey<String>('sky-map-star-touch');
  static const Key status = ValueKey<String>('sky-map-status');
  static const Key myName = ValueKey<String>('sky-map-my-name');
  static const Key partnerName = ValueKey<String>('sky-map-partner-name');
  static const Key fromReveal = ValueKey<String>('sky-map-from-reveal');
  static const Key fromUs = ValueKey<String>('sky-map-from-us');

  static Key constellation(int index) => ValueKey<String>('sky-map-constellation-$index');

  static Key night(int number) => ValueKey<String>('sky-map-night-$number');
}

abstract final class SkyMapCopy {
  static const String title = 'Our sky map';
  static const String action = 'Sky map';
  static const String seeInMap = 'See it in our sky map';
  static const String finished = 'Every finished constellation';
  static const String keepNote = 'Light all 29 stars and it stays here for good';
  static const String everyDayNote = 'Every question and both your answers';
  static const String emptyTitle = 'Our first star is on its way';
  static const String waitingFirst = 'Waiting for its first star';

  static String kicker(int stars) {
    if (stars <= 0) return 'Before the first star';
    return stars == 1 ? 'One star so far' : '$stars stars so far';
  }

  static String emptyMessage({required bool night}) =>
      "Answer ${night ? "tonight's" : "today's"} question together and the first star lights up here.";

  static String nights(int count) => count == 1 ? '1 night' : '$count nights';

  static String stillGrowing(int lit) => 'Still growing · $lit of ${ConstellationChapter.size}';

  static String status(ConstellationChapter chapter) {
    if (chapter.complete) return nights(chapter.lit);
    return chapter.started ? stillGrowing(chapter.lit) : waitingFirst;
  }

  static String card(ConstellationChapter chapter) {
    final range = StarNightCopy.range(chapter);
    return [chapter.label, if (range.isNotEmpty) range, status(chapter)].join(', ');
  }

  static String sky(ConstellationChapter chapter) => '${chapter.label}. ${status(chapter)}.';
}

@immutable
class SkyMapEntries {
  const SkyMapEntries({this.growing, this.finished = const []});

  final ConstellationChapter? growing;
  final List<ConstellationChapter> finished;

  bool get isEmpty => growing == null && finished.isEmpty;
}

abstract final class SkyMapPlan {
  static const double designWidth = 390;
  static const double maxWidth = 520;
  static const double maxScale = 11;
  static const double margin = 28;
  static const double edge = 8;
  static const double ghostDim = 0.16;

  static SkyMapEntries entriesOf(ConstellationSeries series) {
    if (series.stars <= 0) return const SkyMapEntries();
    final current = series.current;
    return SkyMapEntries(
      growing: current.complete ? null : current,
      finished: series.completed.reversed.toList(growable: false),
    );
  }

  static SkyConstellation figure(ConstellationChapter chapter, {required bool litToday}) {
    if (chapter.complete) {
      return SkyConstellation(shape: chapter.shape, gap: null, complete: true, presence: false);
    }
    return SkyConstellationPlan.home(
      stars: chapter.index * ConstellationChapter.size + chapter.lit,
      litToday: litToday && chapter.started,
      presence: false,
    );
  }

  static SkyConstellation waiting() => SkyConstellationPlan.home(stars: 0, litToday: false, presence: false);

  static double scaleOf(double width) => width <= 0 ? 1 : math.min(width, maxWidth) / designWidth;

  static Rect frameFor(Size size, EdgeInsets padding, {double top = 150, double bottom = 130}) {
    final k = scaleOf(size.width);
    final upper = padding.top / k + top;
    final lower = math.max(upper + 160, (size.height - padding.bottom) / k - bottom);
    return Rect.fromLTRB(0, upper, size.width / k, lower);
  }

  static SkyConstellation fit(
    SkyConstellation figure,
    Rect frame, {
    double margin = margin,
    double limit = maxScale,
    bool names = false,
    Size? meSize,
    Size? partnerSize,
  }) {
    final room = frame.deflate(margin);
    SkyConstellation at(double scale) =>
        figure.copyWith(center: room.center - figure.shape.unitBounds.center * scale, scale: scale);
    var fitted = figure.fitted(frame, margin: margin);
    if (fitted.scale > limit) fitted = at(limit);
    if (!names) return fitted;
    SkyConstellation centred(SkyConstellation shown) {
      final group = nameGroup(shown, meSize: meSize, partnerSize: partnerSize);
      return shown.copyWith(center: shown.center + Offset(frame.center.dx - group.center.dx, 0));
    }

    fitted = centred(fitted);
    for (var i = 0; i < 40 && nameSpill(fitted, frame, meSize: meSize, partnerSize: partnerSize) > 0; i++) {
      fitted = centred(at(fitted.scale * 0.96));
    }
    return fitted;
  }

  static Rect nameGroup(SkyConstellation figure, {Size? meSize, Size? partnerSize}) => nameAreas(
    figure,
    meSize: meSize,
    partnerSize: partnerSize,
  ).fold<Rect>(figure.bounds, (group, area) => group.expandToInclude(area));

  static List<Rect> nameAreas(SkyConstellation figure, {Size? meSize, Size? partnerSize}) {
    final shape = figure.shape;
    return [
      shape.meLabel.area(figure.pointAt(figure.me), meSize ?? SkyConstellationPlan.meLabelSize),
      shape.partnerLabel.area(
        figure.pointAt(figure.partner),
        partnerSize ?? SkyConstellationPlan.partnerLabelSize(chip: false),
      ),
    ];
  }

  static double nameSpill(SkyConstellation figure, Rect frame, {Size? meSize, Size? partnerSize}) {
    var spill = 0.0;
    for (final area in nameAreas(figure, meSize: meSize, partnerSize: partnerSize)) {
      spill += math.max(0, frame.left + edge - area.left) + math.max(0, area.right - (frame.right - edge));
    }
    return spill;
  }

  static SkyConstellation? ghostOf(SkyConstellation figure) {
    if (figure.complete && figure.unlit.isEmpty) return null;
    return figure.copyWith(
      complete: true,
      clearGap: true,
      unlit: const <int>{},
      presence: false,
      burst: false,
      dim: ghostDim,
    );
  }
}
