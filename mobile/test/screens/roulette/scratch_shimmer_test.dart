import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/presentation/screens/roulette/scratch_card.dart';
import 'package:our_space_mobile/presentation/sky/sky.dart';

Widget shimmerHost(ScrollController controller) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: SkyThemes.legacy(SkyTokens.night),
    home: SkyTheme(
      child: Material(
        child: SingleChildScrollView(
          controller: controller,
          child: Column(
            children: [
              SizedBox(width: 320, height: 200, child: ScratchCard(revealed: false, onRevealed: () {})),
              const SizedBox(height: 3000),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('the foil shimmers once, rests, shines again and stays still while out of sight', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(shimmerHost(controller));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.hasRunningAnimations, isTrue);

    await tester.pump(ScratchCard.shimmerPeriod);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.hasRunningAnimations, isFalse);

    await tester.pump(ScratchCard.shimmerRest);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.hasRunningAnimations, isTrue);

    controller.jumpTo(1500);
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
    await tester.pump(ScratchCard.shimmerPeriod + ScratchCard.shimmerRest);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.hasRunningAnimations, isFalse);

    controller.jumpTo(0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.hasRunningAnimations, isTrue);

    await tester.pumpWidget(const SizedBox());
  });
}
