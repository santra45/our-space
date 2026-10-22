import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/presentation/screens/roulette/date_roulette.dart';
import 'package:our_space_mobile/presentation/screens/roulette/roulette_copy.dart';
import 'package:our_space_mobile/presentation/screens/roulette/scratch_card.dart';
import 'package:our_space_mobile/presentation/screens/us/us_keys.dart';
import 'package:our_space_mobile/presentation/sky/sky.dart';
import 'package:our_space_mobile/presentation/widgets/app_haptics.dart';

import '../us/us_harness.dart';

DateIdea shownIdea(WidgetTester tester) => tester.widget<DateIdeaReveal>(find.byType(DateIdeaReveal)).idea;

ScratchCard scratchCard(WidgetTester tester) => tester.widget<ScratchCard>(find.byType(ScratchCard));

Finder ideaChip(String label) => find.widgetWithText(DateIdeaChip, label);

bool chipSelected(WidgetTester tester, String label) => tester.widget<DateIdeaChip>(ideaChip(label)).selected;

Future<void> openDateNight(WidgetTester tester, OurSpace space, {bool day = false}) async {
  await pumpUs(tester, space, day: day);
  await untilFound(tester, find.byType(ScratchCard));
  await reveal(tester, find.byKey(UsKeys.scratchPanel));
}

Future<void> idle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
}

Future<void> scratchAcross(WidgetTester tester, {double rowStep = 14, double colStep = 12}) async {
  final rect = tester.getRect(find.byType(ScratchCard));
  for (var y = rect.top + 4; y < rect.bottom - 2; y += rowStep) {
    final gesture = await tester.startGesture(Offset(rect.left + 2, y));
    for (var x = rect.left + 2; x < rect.right - 2; x += colStep) {
      await gesture.moveTo(Offset(x, y));
    }
    await gesture.up();
    await tester.pump();
    if (scratchCard(tester).revealed) break;
  }
}

void main() {
  late math.Random previous;

  setUp(() {
    previous = DateRoulette.random;
    DateRoulette.random = math.Random(42);
  });

  tearDown(() => DateRoulette.random = previous);

  test('the foil keeps the brush round whatever its shape', () {
    final wide = ScratchCoverage.fitting(const Size(318, 159));
    expect(wide.width, 340);
    expect(wide.height, 170);
    final square = ScratchCoverage.fitting(const Size(200, 200));
    expect(square.height, 340);
    final empty = ScratchCoverage.fitting(Size.zero);
    expect(empty.width, ScratchCoverage.canvasWidth);
    expect(empty.height, ScratchCoverage.canvasHeight);
  });

  test('kinds of date read plainly', () {
    expect(RouletteCopy.categoryLabel('athome', 'At-Home'), 'At home');
    expect(RouletteCopy.categoryLabel('food', 'Foodie'), 'Foodie');
  });

  testWidgets('shows the scratch card with the first idea and the kinds of date', (tester) async {
    calm(tester);
    final space = await usSpace(tester);
    await openDateNight(tester, space);

    expect(find.text(RouletteCopy.title), findsOneWidget);
    expect(find.text(RouletteCopy.anotherIdea), findsOneWidget);
    expect(find.text(RouletteCopy.tonight), findsOneWidget);
    expect(find.text(RouletteCopy.hint), findsOneWidget);
    for (final label in ['All', 'At home', 'Outdoor', 'Foodie', 'Budget']) {
      expect(ideaChip(label), findsOneWidget);
    }
    expect(chipSelected(tester, 'All'), isTrue);
    expect(find.text('OUR DATE'), findsOneWidget);
    expect(find.text('Living Room Pillow Fort Movie Night'), findsOneWidget);
    expect(
      find.text(
        'Build an epic cozy blanket fort, string fairy lights, pop fresh buttered popcorn, and watch childhood cartoons.',
      ),
      findsOneWidget,
    );
    expect(scratchCard(tester).revealed, isFalse);
    expect(labelled(RouletteCopy.scratchLabel), findsOneWidget);
    expect(await drive(tester, () => space.roulette.current()), isNull);
    await rest(tester, space);
  });

  testWidgets('rolls another idea, filters by kind and saves the card for both of us', (tester) async {
    calm(tester);
    final space = await usSpace(tester);
    await openDateNight(tester, space);

    final firstCard = scratchCard(tester).key;
    recordedHaptics.clear();
    await press(tester, find.text(RouletteCopy.anotherIdea));
    final rolled = shownIdea(tester);
    expect(rolled.id, isNot('d1'));
    expect(scratchCard(tester).key, isNot(firstCard));
    expect(recordedHaptics, containsAllInOrder([HapticKind.tick, HapticKind.tap]));
    await idle(tester);
    var stored = await drive(tester, () => space.roulette.current());
    expect(stored?.ideaId, rolled.id);
    expect(stored?.category, 'all');
    expect(stored?.revealed, isFalse);

    for (var i = 0; i < 6; i++) {
      final before = shownIdea(tester).id;
      await press(tester, ideaChip('Foodie'));
      expect(chipSelected(tester, 'Foodie'), isTrue);
      expect(chipSelected(tester, 'All'), isFalse);
      final idea = shownIdea(tester);
      expect(idea.category, 'food');
      expect(idea.id, isNot(before));
    }
    await idle(tester);
    stored = await drive(tester, () => space.roulette.current());
    expect(stored?.category, 'food');
    expect(stored?.ideaId, shownIdea(tester).id);

    await press(tester, find.text(RouletteCopy.anotherIdea));
    expect(shownIdea(tester).category, 'food');
    expect(chipSelected(tester, 'Foodie'), isTrue);
    await idle(tester);
    await rest(tester, space);
  });

  testWidgets('scratching reveals the idea, celebrates and remembers it', (tester) async {
    calm(tester);
    final space = await usSpace(tester);
    await openDateNight(tester, space);

    recordedHaptics.clear();
    await scratchAcross(tester);
    expect(scratchCard(tester).revealed, isTrue);
    expect(recordedHaptics, contains(HapticKind.tick));
    expect(recordedHaptics.where((kind) => kind == HapticKind.celebration), hasLength(1));
    final ignoring = tester.widget<IgnorePointer>(
      find.descendant(of: find.byType(ScratchCard), matching: find.byType(IgnorePointer)).first,
    );
    expect(ignoring.ignoring, isTrue);
    expect(find.text(RouletteCopy.revealed), findsOneWidget);
    expect(find.text(RouletteCopy.hint), findsNothing);

    await idle(tester);
    final stored = await drive(tester, () => space.roulette.current());
    expect(stored?.ideaId, 'd1');
    expect(stored?.revealed, isTrue);
    expect(scratchCard(tester).revealed, isTrue);

    await press(tester, find.text(RouletteCopy.anotherIdea));
    expect(scratchCard(tester).revealed, isFalse);
    expect(shownIdea(tester).id, isNot('d1'));
    expect(find.text(RouletteCopy.hint), findsOneWidget);
    await idle(tester);
    await rest(tester, space);
  });

  testWidgets('a quick tap or a short drag does not reveal the card', (tester) async {
    calm(tester);
    final space = await usSpace(tester);
    await openDateNight(tester, space);
    await tester.tap(find.byType(ScratchCard));
    await tester.pump();
    expect(scratchCard(tester).revealed, isFalse);
    final state = tester.state<ScratchCardState>(find.byType(ScratchCard));
    expect(state.strokeCount, 1);
    expect(state.coverage.clearedCount, greaterThan(0));
    final size = tester.getSize(find.byType(ScratchCard));
    expect(state.coverage.width, ScratchCoverage.canvasWidth);
    expect(state.coverage.height, (ScratchCoverage.canvasWidth * size.height / size.width).round());

    final center = tester.getCenter(find.byType(ScratchCard));
    final gesture = await tester.startGesture(center);
    for (var i = 1; i <= 8; i++) {
      await gesture.moveTo(center - Offset(0, i * 6.0));
    }
    await gesture.up();
    await tester.pump();
    expect(state.strokeCount, 10);
    expect(scratchCard(tester).revealed, isFalse);
    expect(recordedHaptics.where((kind) => kind == HapticKind.tick), isNotEmpty);
    expect(await drive(tester, () => space.roulette.current()), isNull);
    await rest(tester, space);
  });

  testWidgets('a screen reader can reveal the card with one tap', (tester) async {
    calm(tester);
    final space = await usSpace(tester);
    await openDateNight(tester, space);
    final semantics = tester.widget<Semantics>(labelled(RouletteCopy.scratchLabel));
    semantics.properties.onTap!();
    await tester.pump();
    expect(scratchCard(tester).revealed, isTrue);
    await idle(tester);
    expect((await drive(tester, () => space.roulette.current()))?.revealed, isTrue);
    await rest(tester, space);
  });

  testWidgets('picks up the card that was saved, and changes made on the other phone', (tester) async {
    calm(tester);
    final space = await usSpace(tester);
    await real(tester, () => space.roulette.persist(ideaId: 'd6', category: 'outdoor', revealed: true));

    await openDateNight(tester, space);
    await untilFound(tester, find.text('Sunrise Breakfast Picnic'));
    expect(chipSelected(tester, 'Outdoor'), isTrue);
    expect(scratchCard(tester).revealed, isTrue);
    expect(find.text(RouletteCopy.revealed), findsOneWidget);

    await drive(tester, () => space.roulette.persist(ideaId: 'd9', category: 'food', revealed: false));
    await untilFound(tester, find.text('Fondue & Storytelling by Candlelight'));
    expect(chipSelected(tester, 'Foodie'), isTrue);
    expect(scratchCard(tester).revealed, isFalse);

    await drive(tester, () => space.roulette.persist(ideaId: 'nope', category: 'food', revealed: true));
    await idle(tester);
    expect(shownIdea(tester).id, 'd9');
    expect(scratchCard(tester).revealed, isFalse);
    await rest(tester, space);
  });

  testWidgets('by day the card asks for this weekend', (tester) async {
    calm(tester);
    final space = await usSpace(tester);
    await openDateNight(tester, space, day: true);
    expect(find.text(RouletteCopy.weekend), findsOneWidget);
    expect(find.text(RouletteCopy.tonight), findsNothing);
    final panel = tester.widget<Container>(
      find.descendant(of: find.byKey(UsKeys.scratchPanel), matching: find.byType(Container)).first,
    );
    final gradient = (panel.decoration! as BoxDecoration).gradient! as LinearGradient;
    expect(gradient.colors, ScratchPanel.day);
    expect(gradient.colors.first, SkyTokens.indigo);
    await rest(tester, space);
  });
}
