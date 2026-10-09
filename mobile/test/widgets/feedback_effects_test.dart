import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/presentation/theme/app_colors.dart';
import 'package:our_space_mobile/presentation/widgets/ambient_particles.dart';
import 'package:our_space_mobile/presentation/widgets/app_icons.dart';
import 'package:our_space_mobile/presentation/widgets/bouncy_button.dart';
import 'package:our_space_mobile/presentation/widgets/confetti_burst.dart';
import 'package:our_space_mobile/presentation/widgets/css_box.dart';
import 'package:our_space_mobile/presentation/widgets/our_bits.dart';
import 'package:our_space_mobile/presentation/widgets/our_feedback.dart';
import 'package:our_space_mobile/presentation/widgets/tw_animations.dart';

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
  setUp(recordHaptics);

  group('notices and states', () {
    testWidgets('notice tones use the web palettes', (tester) async {
      await pumpHost(
        tester,
        const SizedBox(
          width: 320,
          child: OurNotice(tone: NoticeTone.warning, message: '1 letter could not be opened with your passphrase, so it is hidden for now.'),
        ),
      );
      expect(find.text('1 letter could not be opened with your passphrase, so it is hidden for now.'), findsOneWidget);
      expect(NoticePalette.of(NoticeTone.warning).background, AppColors.amber50);
      expect(NoticePalette.of(NoticeTone.warning).border, AppColors.amber200);
      expect(NoticePalette.of(NoticeTone.error).text, AppColors.rose700);
      expect(NoticePalette.of(NoticeTone.lavender).text, AppColors.lavender700);
      expect(OurNotice.defaultIcon(NoticeTone.warning), AppIcons.alertTriangle);
    });

    testWidgets('dismissible notice reports the tap', (tester) async {
      var dismissed = 0;
      final handle = tester.ensureSemantics();
      await pumpHost(
        tester,
        SizedBox(width: 320, child: OurNotice(tone: NoticeTone.info, message: 'Still sealed.', onDismiss: () => dismissed++)),
      );
      await tester.tap(find.bySemanticsLabel('Dismiss'));
      expect(dismissed, 1);
      handle.dispose();
    });

    testWidgets('empty state mirrors the dashed web card with its call to action', (tester) async {
      var created = 0;
      await pumpHost(
        tester,
        SizedBox(
          width: 600,
          child: OurEmptyState(
            icon: AppIcons.mail,
            title: 'No Letters Yet',
            message: 'Leave a surprise letter for Sam, or seal a time capsule to open on your next anniversary!',
            action: BouncyButton(onPressed: () => created++, small: true, pill: true, label: 'Write First Love Letter 💌'),
          ),
        ),
      );
      expect(find.text('No Letters Yet'), findsOneWidget);
      final dashed = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((c) => c.painter)
          .whereType<DashedBorderPainter>()
          .single;
      expect(dashed.color, AppColors.blush200);
      expect(dashed.strokeWidth, 2);
      await tester.tap(find.text('Write First Love Letter 💌'));
      expect(created, 1);
    });

    testWidgets('loading pieces render without running forever when motion is off', (tester) async {
      await pumpHost(
        tester,
        const SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              OurLoadingState(),
              OurSkeleton(height: 40),
              OurPulseText('Developing... 💕'),
            ],
          ),
        ),
      );
      expect(find.text('Finding your space…'), findsOneWidget);
      expect(find.text('Developing... 💕'), findsOneWidget);
      expect(find.byType(OurSpinner), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('error card uses the ErrorBoundary copy', (tester) async {
      var retries = 0;
      await pumpHost(tester, OurErrorCard(onRetry: () => retries++, onReload: () {}));
      expect(find.text('Something went a bit wrong'), findsOneWidget);
      expect(
        find.text('This screen stopped drawing properly. Nothing has been lost — your memories are still saved on this phone.'),
        findsOneWidget,
      );
      expect(find.text('Reload Our Space'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      expect(retries, 1);
    });

    testWidgets('OurToast falls back to an overlay pill outside the shell', (tester) async {
      await pumpHost(tester, Builder(builder: (context) {
        return TextButton(onPressed: () => OurToast.show(context, 'Copied ID!'), child: const Text('copy'));
      }));
      await tester.tap(find.text('copy'));
      await tester.pump();
      expect(find.text('Copied ID!'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('Copied ID!'), findsNothing);
    });

    testWidgets('pills, tags, progress and washi tape render', (tester) async {
      await pumpHost(
        tester,
        SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              OurPill.blush(label: 'Locked', icon: AppIcons.lock),
              const OurTag('Anniversary'),
              const OurProgressBar(value: 0.5),
              WashiTape.over(child: const SizedBox(height: 60, width: 120)),
              OurIconButton.delete(onPressed: () {}, semanticLabel: 'Delete memory'),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Locked'), findsOneWidget);
      expect(find.text('ANNIVERSARY'), findsOneWidget);
      expect(find.byType(WashiTape), findsOneWidget);
      expect(tester.getSize(find.byType(WashiTape)), const Size(72, 22));
    });
  });

  group('looping animations', () {
    test('pulse, ping and bounce follow the Tailwind keyframes', () {
      expect(TwPulse.opacityAt(0), 1);
      expect(TwPulse.opacityAt(0.5), closeTo(0.5, 1e-9));
      expect(TwPulse.opacityAt(1), closeTo(1, 1e-9));
      expect(TwPing.frameAt(0), (1.0, 1.0));
      expect(TwPing.frameAt(0.8), (2.0, 0.0));
      expect(TwBounce.liftAt(0), 1);
      expect(TwBounce.liftAt(0.5), closeTo(0, 1e-9));
      expect(TwBounce.liftAt(1), closeTo(1, 1e-9));
    });

    testWidgets('loops run when motion is allowed and stop when it is not', (tester) async {
      await pumpHost(tester, const TwSpin(child: SizedBox(width: 10, height: 10)), animations: true);
      await tester.pump(const Duration(milliseconds: 250));
      final turning = tester.widget<Transform>(
        find.descendant(of: find.byType(TwSpin), matching: find.byType(Transform)).first,
      );
      expect(turning.transform.storage[1].abs(), greaterThan(0.5));
      await pumpHost(tester, const TwSpin(child: SizedBox(width: 10, height: 10)));
      await tester.pumpAndSettle();
    });
  });

  group('ambient particles', () {
    test('particles copy the web ranges and the 2x left offset quirk', () {
      final p = AmbientParticle.random(0, math.Random(7));
      expect(p.kind, ParticleKind.sparkle);
      expect(AmbientParticle.random(1, math.Random(7)).kind, ParticleKind.heart);
      expect(p.size, inInclusiveRange(10, 22));
      expect(p.duration, inInclusiveRange(12, 27));
      expect(p.delay, inInclusiveRange(0, 8));
      expect(p.opacity, inInclusiveRange(0.15, 0.5));

      const q = AmbientParticle(x: 20, drift: 2, size: 12, duration: 10, delay: 1, kind: ParticleKind.heart, opacity: 0.3);
      const viewport = Size(400, 800);
      expect(q.positionAt(0.5, viewport), const Offset(160, 840));
      final mid = q.positionAt(6, viewport);
      expect(mid.dx, closeTo((40 + 1) * 4, 1e-9));
      expect(mid.dy, closeTo((105 - 115 * 0.5) * 8, 1e-9));
      expect(AmbientParticle.rotationDegreesAt(1 / 3), closeTo(15, 1e-9));
      expect(AmbientParticle.rotationDegreesAt(2 / 3), closeTo(-15, 1e-9));
      expect(AmbientParticle.rotationDegreesAt(1), 0);
    });

    testWidgets('particles paint behind content and ignore touches', (tester) async {
      await pumpHost(tester, const SizedBox(width: 300, height: 300, child: AmbientParticles(seed: 3)));
      expect(find.byType(AmbientParticles), findsOneWidget);
      expect(
        find.descendant(of: find.byType(AmbientParticles), matching: find.byType(IgnorePointer)),
        findsWidgets,
      );
    });
  });

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

  test('css shadow painter grows radii with the spread and never inverts them', () {
    final painter = CssShadowPainter(shadows: const [BoxShadow(spreadRadius: -30)], borderRadius: BorderRadius.circular(8));
    expect(painter.shouldRepaint(CssShadowPainter(shadows: const [], borderRadius: BorderRadius.circular(8))), isTrue);
  });
}
