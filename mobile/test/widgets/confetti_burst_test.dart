import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/presentation/theme/app_colors.dart';
import 'package:our_space_mobile/presentation/widgets/confetti_burst.dart';

import 'harness.dart';

class _FixedRandom implements math.Random {
  _FixedRandom(this.value);

  final double value;

  @override
  bool nextBool() => value >= 0.5;

  @override
  double nextDouble() => value;

  @override
  int nextInt(int max) => (value * max).floor().clamp(0, max - 1);
}

void main() {
  group('confetti', () {
    test('presets match fireHeartConfetti and fireCelebrationBurst', () {
      const heart = ConfettiPresets.heart;
      expect(heart.particleCount, 50);
      expect(heart.spread, 70);
      expect(heart.originY, 0.7);
      expect(heart.scalar, 1.2);
      expect(heart.shapes, [ConfettiShape.heart, ConfettiShape.circle]);
      expect(heart.colors.map((c) => c.toARGB32()), [0xFFFF85A3, 0xFFFF5480, 0xFFFFD1DC, 0xFFCDBEFF, 0xFFF9F1DC]);
      final bursts = ConfettiPresets.celebration;
      expect(bursts.map((b) => b.particleCount), [37, 30, 52, 15, 15]);
      expect(bursts.map((b) => b.spread), [26, 60, 100, 120, 120]);
      expect(bursts.map((b) => b.startVelocity), [55, 45, 45, 25, 45]);
      expect(bursts[2].decay, 0.91);
      expect(bursts[3].scalar, 1.2);
    });

    test('one physics step equals canvas-confetti updateFetti', () {
      final rng = _FixedRandom(0.5);
      final p = ConfettiParticle.spawn(ConfettiPresets.heart, const Size(400, 800), AppColors.blush400, ConfettiShape.heart, rng);
      expect(p.x, 200);
      expect(p.y, 560);
      expect(p.velocity, 45 * 0.5 + 0.5 * 45);
      expect(p.angle2D, closeTo(-math.pi / 2, 1e-9));
      expect(p.step(rng), isTrue);
      expect(p.x, closeTo(200 + math.cos(-math.pi / 2) * 45, 1e-9));
      expect(p.y, closeTo(560 + math.sin(-math.pi / 2) * 45 + 3, 1e-9));
      expect(p.velocity, closeTo(45 * 0.9, 1e-9));
      expect(p.progress, 0);
      expect(p.tick, 1);
      for (var i = 1; i < 199; i++) {
        expect(p.step(rng), isTrue);
      }
      expect(p.step(rng), isFalse);
    });

    testWidgets('a burst draws on a root overlay and cleans itself up', (tester) async {
      ConfettiBurst.debugRandom = math.Random(1);
      addTearDown(() => ConfettiBurst.debugRandom = null);
      await pumpHost(
        tester,
        Builder(builder: (context) {
          return TextButton(onPressed: () => fireHeartConfetti(context), child: const Text('love'));
        }),
        animations: true,
      );
      await tester.tap(find.text('love'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(ConfettiCanvas), findsOneWidget);
      expect(ConfettiBurst.activeController!.particles.length, 50);
      for (var i = 0; i < 230; i++) {
        await tester.pump(const Duration(milliseconds: 17));
      }
      expect(find.byType(ConfettiCanvas), findsNothing);
      expect(ConfettiBurst.activeController, isNull);
    });

    testWidgets('confetti is skipped when the system asks for less motion', (tester) async {
      await pumpHost(tester, Builder(builder: (context) {
        return TextButton(onPressed: () => fireCelebrationBurst(context), child: const Text('yay'));
      }));
      await tester.tap(find.text('yay'));
      await tester.pump();
      expect(find.byType(ConfettiCanvas), findsNothing);
    });
  });
}
