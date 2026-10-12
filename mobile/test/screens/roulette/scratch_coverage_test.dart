import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/presentation/screens/roulette/scratch_card.dart';

int bruteForceCleared(List<List<double>> strokes, {int width = 340, int height = 255, double radius = 24}) {
  var cleared = 0;
  for (var i = 3; i < width * height * 4; i += 64) {
    final pixel = (i - 3) ~/ 4;
    final x = pixel % width;
    final y = pixel ~/ width;
    for (final stroke in strokes) {
      final dx = math.max((x - stroke[0]).abs(), (x + 1 - stroke[0]).abs());
      final dy = math.max((y - stroke[1]).abs(), (y + 1 - stroke[1]).abs());
      if (dx * dx + dy * dy <= radius * radius) {
        cleared++;
        break;
      }
    }
  }
  return cleared;
}

void main() {
  test('samples every sixteenth pixel of the 340 by 255 canvas like the web', () {
    final coverage = ScratchCoverage();
    expect(coverage.sampleCount, 5419);
    expect(coverage.clearedCount, 0);
    expect(coverage.revealed, isFalse);
  });

  test('one stroke clears the fully covered sampled pixels', () {
    final coverage = ScratchCoverage()..scratch(170, 127.5);
    expect(coverage.clearedCount, bruteForceCleared([
      [170, 127.5],
    ]));
    expect(coverage.clearedCount, inInclusiveRange(95, 113));
    expect(coverage.isCleared(164, 127), isTrue);
    expect(coverage.isCleared(165, 127), isFalse);
    expect(coverage.isCleared(0, 0), isFalse);
  });

  test('overlapping and edge strokes count each sample once', () {
    final strokes = [
      [0.0, 0.0],
      [3.0, 2.0],
      [339.5, 254.5],
      [100.25, 60.75],
      [110.0, 61.0],
      [-30.0, 300.0],
    ];
    final coverage = ScratchCoverage();
    for (final stroke in strokes) {
      coverage.scratch(stroke[0], stroke[1]);
    }
    expect(coverage.clearedCount, bruteForceCleared(strokes));
  });

  test('reveals only past forty percent', () {
    final coverage = ScratchCoverage();
    final strokes = <List<double>>[];
    for (var y = 0.0; y <= 255 && !coverage.revealed; y += 20) {
      for (var x = 0.0; x <= 340 && !coverage.revealed; x += 10) {
        coverage.scratch(x, y);
        strokes.add([x, y]);
      }
    }
    expect(coverage.revealed, isTrue);
    expect(coverage.fraction, greaterThan(0.4));
    expect(coverage.clearedCount, bruteForceCleared(strokes));

    final last = strokes.removeLast();
    final before = ScratchCoverage();
    for (final stroke in strokes) {
      before.scratch(stroke[0], stroke[1]);
    }
    expect(before.revealed, isFalse);
    before.scratch(last[0], last[1]);
    expect(before.revealed, isTrue);
  });
}
