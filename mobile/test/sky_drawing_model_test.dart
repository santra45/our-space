import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/models/sky_drawing_record.dart';

const String her = 'owner-aaaa1111';
const String him = 'owner-bbbb2222';

SkyDrawnStar star(String id, double x, double y, {String by = her, int at = 100, int gen = 0}) =>
    SkyDrawnStar(id: id, x: x, y: y, by: by, at: at, gen: gen);

SkyDrawnLine line(String a, String b, {String by = her, int at = 200, int gen = 0}) =>
    SkyDrawnLine(from: a, to: b, by: by, at: at, gen: gen);

List<SkyDrawingOp> randomSession(int seed, {int steps = 120}) {
  final rnd = math.Random(seed);
  var mine = SkyDrawing.empty;
  var theirs = SkyDrawing.empty;
  final ops = <SkyDrawingOp>[];
  var clock = 1000;
  for (var i = 0; i < steps; i++) {
    final herTurn = rnd.nextBool();
    final view = herTurn ? mine : theirs;
    final who = herTurn ? her : him;
    clock += rnd.nextInt(40);
    SkyDrawingOp? op;
    final roll = rnd.nextDouble();
    if (roll < 0.5) {
      op = view.placeStar(id: '${herTurn ? 'h' : 'm'}$i', x: rnd.nextDouble(), y: rnd.nextDouble(), by: who, at: clock);
    } else if (roll < 0.8 && view.visibleStars.length >= 2) {
      final a = view.visibleStars[rnd.nextInt(view.visibleStars.length)];
      final b = view.visibleStars[rnd.nextInt(view.visibleStars.length)];
      op = view.join(a.id, b.id, by: who, at: clock);
    } else if (roll < 0.96 && view.visibleStars.isNotEmpty) {
      final pick = view.visibleStars[rnd.nextInt(view.visibleStars.length)];
      op = view.takeAway(pick.id, by: pick.by);
    } else {
      op = view.startOver();
    }
    if (op == null) continue;
    ops.add(op);
    if (herTurn) {
      mine = mine.apply(op);
      if (rnd.nextDouble() < 0.6) theirs = theirs.apply(op);
    } else {
      theirs = theirs.apply(op);
      if (rnd.nextDouble() < 0.6) mine = mine.apply(op);
    }
  }
  return ops;
}

SkyDrawing applyAll(Iterable<SkyDrawingOp> ops) => ops.fold(SkyDrawing.empty, (d, op) => d.apply(op));

void main() {
  group('merging', () {
    for (final seed in [1, 2, 3, 7, 11, 42, 99, 2026]) {
      test('both phones end with the same drawing whatever order the ops arrive in (seed $seed)', () {
        final ops = randomSession(seed);
        expect(ops.length, greaterThan(40));
        final forward = applyAll(ops);
        final backward = applyAll(ops.reversed);
        final shuffled = applyAll(ops.toList()..shuffle(math.Random(seed * 31)));
        final twice = applyAll([...ops, ...ops.reversed]);
        expect(backward, forward);
        expect(shuffled, forward);
        expect(twice, forward);
        expect(backward.visibleStars, forward.visibleStars);
        expect(shuffled.visibleLines, forward.visibleLines);
        expect(jsonEncode(shuffled.toJson()), jsonEncode(forward.toJson()));
      });
    }

    test('merging snapshots is order free, grouping free and safe to repeat', () {
      final ops = randomSession(5, steps: 200);
      final a = applyAll(ops.take(70));
      final b = applyAll(ops.skip(50).take(80));
      final c = applyAll(ops.skip(110));
      expect(a.merge(b), b.merge(a));
      expect(a.merge(b).merge(c), a.merge(b.merge(c)));
      expect(a.merge(a), a);
      expect(a.merge(b).merge(b), a.merge(b));
      expect(a.merge(b).merge(c), applyAll(ops));
      expect(SkyDrawing.empty.merge(a), a);
    });

    test('starting over clears the earlier drawing everywhere, even for a star that arrives late', () {
      final first = SkyDrawing.empty.placeStar(id: 's1', x: 0.3, y: 0.3, by: her, at: 10)!;
      final over = SkyDrawing.empty.apply(first).startOver()!;
      expect(over.gen, 1);
      final late = SkyDrawing.empty.placeStar(id: 's2', x: 0.6, y: 0.6, by: him, at: 11)!;
      final here = SkyDrawing.empty.apply(first).apply(over).apply(late);
      final there = SkyDrawing.empty.apply(late).apply(over).apply(first);
      expect(here, there);
      expect(here.gen, 1);
      expect(here.isBlank, isTrue);
      final both = here.apply(const SkyStartOver(1));
      expect(both, here);
      final fresh = here.placeStar(id: 's3', x: 0.5, y: 0.5, by: him, at: 12)!;
      expect(fresh.gen, 1);
      expect(here.apply(fresh).visibleStars.single.id, 's3');
    });

    test('a star taken away stays away with its lines, even when the removal arrives first', () {
      final base = SkyDrawing(stars: [star('a', 0.2, 0.2), star('b', 0.8, 0.8, by: him)], lines: [line('a', 'b')]);
      final removal = base.takeAway('a', by: her)!;
      final early = SkyDrawing.empty.apply(removal).merge(base);
      final late = base.apply(removal);
      expect(early, late);
      expect(late.visibleStars.map((s) => s.id), ['b']);
      expect(late.visibleLines, isEmpty);
      expect(late.stars.containsKey('a'), isFalse);
      expect(late.lines, isEmpty);
      expect(late.removed, {'a'});
      expect(late.merge(base), late);
    });

    test('the same line drawn by both at once is one line, the earlier one', () {
      final base = SkyDrawing(stars: [star('a', 0.2, 0.2), star('b', 0.8, 0.8, by: him)]);
      final mine = base.join('a', 'b', by: her, at: 300)!;
      final yours = base.join('b', 'a', by: him, at: 250)!;
      final here = base.apply(mine).apply(yours);
      final there = base.apply(yours).apply(mine);
      expect(here, there);
      expect(here.visibleLines.single.by, him);
      expect(here.visibleLines.single.key, 'a~b');
    });
  });

  group('limits', () {
    test('thirty stars and forty lines show, and a race past the limit hides the same extras on both phones', () {
      var drawing = SkyDrawing.empty;
      for (var i = 0; i < skyDrawingMaxStars; i++) {
        drawing = drawing.apply(drawing.placeStar(id: 's$i', x: 0.05 + (i % 6) * 0.15, y: 0.05 + (i ~/ 6) * 0.15, by: her, at: i)!);
      }
      expect(drawing.visibleStars.length, skyDrawingMaxStars);
      expect(drawing.starsFull, isTrue);
      expect(drawing.placeStar(id: 'extra', x: 0.97, y: 0.97, by: her, at: 99), isNull);

      final raceA = SkyAddStar(star('zz-a', 0.5, 0.97, at: 50));
      final raceB = SkyAddStar(star('aa-b', 0.6, 0.97, by: him, at: 40));
      final here = drawing.apply(raceA).apply(raceB);
      final there = drawing.apply(raceB).apply(raceA);
      expect(here, there);
      expect(here.visibleStars.length, skyDrawingMaxStars);
      expect(here.visibleStars.map((s) => s.id), there.visibleStars.map((s) => s.id));
      expect(here.visibleStars.map((s) => s.id), isNot(contains('zz-a')));

      var linked = drawing;
      var count = 0;
      for (var i = 0; i < skyDrawingMaxStars && count < skyDrawingMaxLines + 5; i++) {
        for (var j = i + 1; j < skyDrawingMaxStars && count < skyDrawingMaxLines + 5; j++) {
          final op = linked.join('s$i', 's$j', by: her, at: 1000 + count);
          if (op == null) continue;
          linked = linked.apply(op);
          count++;
        }
      }
      expect(linked.visibleLines.length, skyDrawingMaxLines);
      expect(linked.linesFull, isTrue);
      expect(linked.join('s28', 's29', by: her, at: 5000), isNull);
      final extra = SkyLink(line('s28', 's29', at: 5000));
      expect(linked.apply(extra).visibleLines.length, skyDrawingMaxLines);
    });

    test('kept stars, lines and removals are capped so a drawing stays small', () {
      final many = SkyDrawing(stars: [for (var i = 0; i < 200; i++) star('s$i', 0.5, 0.5, at: i)]);
      expect(many.stars.length, skyDrawingKeptStars);
      expect(many.stars.keys.first, 's0');
      expect(many.starsFull, isTrue);
      final removals = SkyDrawing(removed: [for (var i = 0; i < 400; i++) 'r$i']);
      expect(removals.removed.length, skyDrawingKeptRemoved);
      expect(removals.removalsFull, isTrue);
      final full = SkyDrawing(stars: [star('mine', 0.5, 0.5)], removed: removals.removed);
      expect(full.takeAway('mine', by: her), isNull);
      expect(jsonEncode(many.toJson()).length, lessThan(16 * 1024));
    });
  });

  group('drawing by hand', () {
    test('a dropped star is kept inside the edge, rounded, and refused right on top of another', () {
      final op = SkyDrawing.empty.placeStar(id: 's1', x: -0.2, y: 0.123456789, by: her, at: 5)!;
      expect(op.star.x, skyPatchEdge);
      expect(op.star.y, 0.1235);
      final drawing = SkyDrawing.empty.apply(op);
      expect(drawing.placeStar(id: 's2', x: skyPatchEdge + 0.01, y: 0.13, by: him, at: 6), isNull);
      expect(drawing.placeStar(id: 's2', x: 0.5, y: 0.5, by: him, at: 6), isNotNull);
      expect(drawing.placeStar(id: 's1', x: 0.5, y: 0.5, by: him, at: 6), isNull);
      expect(drawing.placeStar(id: 'bad id', x: 0.5, y: 0.5, by: him, at: 6), isNull);
      expect(drawing.placeStar(id: 's3', x: 0.5, y: 0.5, by: 'tiny', at: 6), isNull);
      expect(drawing.placeStar(id: 's3', x: double.nan, y: 0.5, by: him, at: 6)!.star.x, 0.5);
      expect(drawing.starNear(0.06, 0.15)!.id, 's1');
      expect(drawing.starNear(0.5, 0.5), isNull);
      final gone = drawing.apply(drawing.takeAway('s1', by: her)!);
      expect(gone.placeStar(id: 's1', x: 0.7, y: 0.7, by: her, at: 9), isNull);
    });

    test('only your own star can be taken away', () {
      final drawing = SkyDrawing(stars: [star('a', 0.2, 0.2), star('b', 0.8, 0.8, by: him)]);
      expect(drawing.takeAway('b', by: her), isNull);
      expect(drawing.takeAway('a', by: him), isNull);
      expect(drawing.takeAway('missing', by: her), isNull);
      expect(drawing.takeAway('a', by: her), SkyRemove(['a'], gen: 0));
    });

    test('joining needs two different stars that are both there and not joined yet', () {
      final drawing = SkyDrawing(stars: [star('a', 0.2, 0.2), star('b', 0.8, 0.8, by: him)]);
      expect(drawing.join('a', 'a', by: her, at: 1), isNull);
      expect(drawing.join('a', 'c', by: her, at: 1), isNull);
      final op = drawing.join('b', 'a', by: her, at: 1)!;
      expect(op.line.a, 'a');
      expect(op.line.b, 'b');
      final joined = drawing.apply(op);
      expect(joined.isLinked('b', 'a'), isTrue);
      expect(joined.join('a', 'b', by: him, at: 2), isNull);
    });
  });

  group('wire shapes', () {
    test('ops and drawings travel as plain json and come back the same', () {
      final drawing = applyAll(randomSession(8));
      final back = SkyDrawing.fromJson(jsonDecode(jsonEncode(drawing.toJson())));
      expect(back, drawing);
      for (final op in randomSession(9)) {
        expect(SkyDrawingOp.fromJson(jsonDecode(jsonEncode(op.toJson()))), op);
      }
    });

    test('anything odd in a drawing is refused as a whole', () {
      final good = {
        'g': 0,
        'stars': [star('a', 0.2, 0.2).toJson()],
        'lines': <Object?>[],
        'removed': <Object?>[],
      };
      expect(SkyDrawing.fromJson(good), isNotNull);
      for (final bad in <Object?>[
        null,
        'x',
        {...good, 'g': -1},
        {...good, 'g': 1.5},
        {...good, 'stars': 'many'},
        {
          ...good,
          'stars': [
            {...star('a', 0.2, 0.2).toJson(), 'x': 2},
          ],
        },
        {
          ...good,
          'stars': [
            {...star('a', 0.2, 0.2).toJson(), 'extra': 1, 'more': 2, 'again': 3},
          ],
        },
        {
          ...good,
          'lines': [
            {'a': 'a', 'b': 'b', 'by': her, 'at': 1, 'g': 1},
          ],
        },
        {
          ...good,
          'removed': ['ok', 'not ok'],
        },
        {...good, 'a': 1, 'b': 2, 'c': 3},
      ]) {
        expect(SkyDrawing.fromJson(bad), isNull, reason: '$bad');
      }
    });
  });

  group('names and nights', () {
    test('names are trimmed, squeezed and cut to forty characters', () {
      expect(cleanSkyName('  Our   little\tkite \n'), 'Our little kite');
      expect(cleanSkyName('a' * 60).length, skyDrawingMaxName);
      expect(cleanSkyName('${'b' * 39}  c'), 'b' * 39);
      final hearts = '💗' * 45;
      expect(cleanSkyName(hearts).runes.length, skyDrawingMaxName);
      expect(cleanSkyName('\u0000\u0007'), '');
    });

    test('half of a broken emoji is dropped, so a name always draws', () {
      const lone = '\uD83D';
      expect(skyHasLoneSurrogate('Kite$lone'), isTrue);
      expect(skyHasLoneSurrogate('\uDC97Kite'), isTrue);
      expect(skyHasLoneSurrogate('$lone x'), isTrue);
      expect(skyHasLoneSurrogate('Kite \u{1F497} \u{1F468}‍\u{1F469}‍\u{1F467}'), isFalse);
      expect(skyWholeText('Kite \u{1F497}'), 'Kite \u{1F497}');
      expect(cleanSkyName('Our $lone kite\uDC97'), 'Our kite');
      expect(skyHasLoneSurrogate(cleanSkyName('\u{1F497}' * 45)), isFalse);
    });

    test('before five in the morning still belongs to the night before', () {
      expect(skyNightOf(DateTime(2026, 10, 28, 23, 40).millisecondsSinceEpoch), '2026-10-28');
      expect(skyNightOf(DateTime(2026, 10, 29, 1, 15).millisecondsSinceEpoch), '2026-10-28');
      expect(skyNightOf(DateTime(2026, 10, 29, 4, 59).millisecondsSinceEpoch), '2026-10-28');
      expect(skyNightOf(DateTime(2026, 10, 29, 5).millisecondsSinceEpoch), '2026-10-29');
      expect(skyNightOf(DateTime(2027, 1, 1, 2).millisecondsSinceEpoch), '2026-12-31');
    });
  });

  group('records', () {
    final drawing = SkyDrawing(stars: [star('a', 0.2, 0.2), star('b', 0.8, 0.8, by: him)], lines: [line('a', 'b')]);

    test('an unfinished record reads back with its drawing', () {
      final fields = SkyDrawingRecord.fieldsFor(id: 'sky-1', drawing: drawing, startedAt: 10, updatedAt: 20);
      final record = SkyDrawingRecord.tryParse(jsonDecode(jsonEncode(fields)) as Map<String, Object?>)!;
      expect(record.id, 'sky-1');
      expect(record.finished, isFalse);
      expect(record.name, '');
      expect(record.drawing, drawing);
      expect(record.startedAt, 10);
      expect(record.createdAt, isNull);
      expect(record.night, isNull);
      expect(record.updatedAt, 20);
      expect(fields.containsKey('createdAt'), isFalse);
    });

    test('a finished record needs a name, the moment and the night', () {
      final fields = SkyDrawingRecord.fieldsFor(
        id: 'sky-1',
        drawing: drawing,
        startedAt: 10,
        updatedAt: 30,
        name: '  Our kite ',
        finished: true,
        createdAt: 25,
        night: '2026-10-28',
      );
      final record = SkyDrawingRecord.tryParse(fields)!;
      expect(record.name, 'Our kite');
      expect(record.finished, isTrue);
      expect(record.createdAt, 25);
      expect(record.night, '2026-10-28');
      expect(SkyDrawingRecord.tryParse({...fields, 'name': '  '}), isNull);
      expect(SkyDrawingRecord.tryParse({...fields, 'name': 'Our kite\uD83D'})!.name, 'Our kite');
      expect(SkyDrawingRecord.tryParse({...fields}..remove('createdAt')), isNull);
      expect(SkyDrawingRecord.tryParse({...fields}..remove('night')), isNull);
      expect(SkyDrawingRecord.tryParse({...fields, 'stars': <Object?>[], 'lines': <Object?>[]}), isNull);
    });

    test('a record with anything out of shape is skipped, and a tombstone is not a drawing', () {
      final fields = SkyDrawingRecord.fieldsFor(id: 'sky-1', drawing: drawing, startedAt: 10, updatedAt: 20);
      expect(SkyDrawingRecord.tryParse(fields), isNotNull);
      for (final bad in <Map<String, Object?>>[
        {...fields, 'id': 'bad id'},
        {...fields, 'deleted': true},
        {...fields, 'updatedAt': 'soon'},
        {...fields, 'name': 7},
        {...fields, 'finished': 'no'},
        {...fields, 'startedAt': -5},
        {...fields, 'createdAt': 'then'},
        {...fields, 'night': '28/10/2026'},
        {...fields, 'gen': 3},
        {...fields, 'stars': 'none'},
        {...fields, 'name': 'x' * (skyDrawingMaxName * 4 + 1)},
      ]) {
        expect(SkyDrawingRecord.tryParse(bad), isNull, reason: '$bad');
      }
    });
  });
}
