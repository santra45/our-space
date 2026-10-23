import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/presentation/screens/countdown/constellation.dart';
import 'package:our_space_mobile/presentation/screens/letters/widgets/wax_seal.dart';
import 'package:our_space_mobile/presentation/sky/sky.dart';

Widget host(Widget child) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: SkyThemes.legacy(SkyTokens.night),
    home: SkyTheme(child: Material(child: Center(child: child))),
  );
}

void main() {
  testWidgets('the breathing seal repaints on its own layer around a cached seal', (tester) async {
    await tester.pumpWidget(host(const BreathingSeal(child: SizedBox(key: Key('seal'), width: 40, height: 40))));
    await tester.pump(const Duration(milliseconds: 300));
    final boundaries = find.descendant(of: find.byType(BreathingSeal), matching: find.byType(RepaintBoundary));
    expect(boundaries, findsNWidgets(2));
    expect(find.descendant(of: boundaries.last, matching: find.byKey(const Key('seal'))), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("today's breathing dot repaints on its own layer", (tester) async {
    await tester.pumpWidget(host(const StarDot(tone: ConstellationTone.now)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.descendant(of: find.byType(StarDot), matching: find.byType(RepaintBoundary)), findsOneWidget);
    await tester.pumpWidget(host(const StarDot()));
    expect(find.descendant(of: find.byType(StarDot), matching: find.byType(RepaintBoundary)), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
