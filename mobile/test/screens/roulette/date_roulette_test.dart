import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/presentation/screens/roulette/date_roulette.dart';
import 'package:our_space_mobile/presentation/screens/roulette/scratch_card.dart';
import 'package:our_space_mobile/presentation/widgets/our_widgets.dart';

import '../../widgets/harness.dart' show recordedHaptics;
import '../polaroids/memories_harness.dart';

DateIdea shownIdea(WidgetTester tester) => tester.widget<DateIdeaReveal>(find.byType(DateIdeaReveal)).idea;

ScratchCard scratchCard(WidgetTester tester) => tester.widget<ScratchCard>(find.byType(ScratchCard));

bool chipSelected(WidgetTester tester, String label) =>
    tester.widget<OurChip>(find.widgetWithText(OurChip, label)).selected;

Future<void> scratchAcross(WidgetTester tester, {double rowStep = 22, double colStep = 12}) async {
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

  testWidgets('shows the scratch-off card with the first idea and the categories', (tester) async {
    calm(tester);
    final space = await real(tester, openReadySpace);
    await openTab(tester, space, 'Dates');
    await untilFound(tester, find.text('Date Night Scratch-Off'));

    expect(find.text('Scratch with your finger to reveal what we are doing next!'), findsOneWidget);
    for (final label in ['All', 'At-Home', 'Outdoor', 'Foodie', 'Budget']) {
      expect(find.widgetWithText(OurChip, label), findsOneWidget);
    }
    expect(chipSelected(tester, 'All'), isTrue);
    expect(find.text('DATE IDEA'), findsOneWidget);
    expect(find.text('Living Room Pillow Fort Movie Night'), findsOneWidget);
    expect(
      find.text('Build an epic cozy blanket fort, string fairy lights, pop fresh buttered popcorn, and watch childhood cartoons.'),
      findsOneWidget,
    );
    expect(find.text('Roll Another Date Idea'), findsOneWidget);
    expect(scratchCard(tester).revealed, isFalse);
    expect(await real(tester, () => space.roulette.current()), isNull);
  });

  testWidgets('rolls a new idea, filters by category and saves the card for both of us', (tester) async {
    calm(tester);
    final space = await real(tester, openReadySpace);
    await openTab(tester, space, 'Dates');
    await untilFound(tester, find.text('Date Night Scratch-Off'));

    final firstCard = scratchCard(tester).key;
    await press(tester, find.text('Roll Another Date Idea'));
    final rolled = shownIdea(tester);
    expect(rolled.id, isNot('d1'));
    expect(scratchCard(tester).key, isNot(firstCard));
    expect(recordedHaptics, containsAllInOrder([HapticKind.tick, HapticKind.tap]));
    await idle(tester);
    var stored = await real(tester, () => space.roulette.current());
    expect(stored?.ideaId, rolled.id);
    expect(stored?.category, 'all');
    expect(stored?.revealed, isFalse);

    for (var i = 0; i < 6; i++) {
      final before = shownIdea(tester).id;
      await press(tester, find.text('Foodie'));
      expect(chipSelected(tester, 'Foodie'), isTrue);
      expect(chipSelected(tester, 'All'), isFalse);
      final idea = shownIdea(tester);
      expect(idea.category, 'food');
      expect(idea.id, isNot(before));
    }
    await idle(tester);
    stored = await real(tester, () => space.roulette.current());
    expect(stored?.category, 'food');
    expect(stored?.ideaId, shownIdea(tester).id);

    await press(tester, find.text('Roll Another Date Idea'));
    expect(shownIdea(tester).category, 'food');
    expect(chipSelected(tester, 'Foodie'), isTrue);
    await idle(tester);
  });

  testWidgets('scratching reveals the idea, celebrates and remembers it', (tester) async {
    calm(tester);
    final space = await real(tester, openReadySpace);
    await openTab(tester, space, 'Dates');
    await untilFound(tester, find.text('Date Night Scratch-Off'));
    await reveal(tester, find.byType(ScratchCard));

    recordedHaptics.clear();
    await scratchAcross(tester);
    expect(scratchCard(tester).revealed, isTrue);
    expect(recordedHaptics, contains(HapticKind.tick));
    expect(recordedHaptics.where((kind) => kind == HapticKind.celebration), hasLength(1));
    final ignoring = tester.widget<IgnorePointer>(
      find.descendant(of: find.byType(ScratchCard), matching: find.byType(IgnorePointer)).first,
    );
    expect(ignoring.ignoring, isTrue);

    await idle(tester);
    final stored = await real(tester, () => space.roulette.current());
    expect(stored?.ideaId, 'd1');
    expect(stored?.revealed, isTrue);
    expect(scratchCard(tester).revealed, isTrue);

    await press(tester, find.text('Roll Another Date Idea'));
    expect(scratchCard(tester).revealed, isFalse);
    expect(shownIdea(tester).id, isNot('d1'));
    await idle(tester);
  });

  testWidgets('a quick tap or a short drag does not reveal the card', (tester) async {
    calm(tester);
    final space = await real(tester, openReadySpace);
    await openTab(tester, space, 'Dates');
    await untilFound(tester, find.text('Date Night Scratch-Off'));
    await reveal(tester, find.byType(ScratchCard));
    await tester.tap(find.byType(ScratchCard));
    await tester.pump();
    expect(scratchCard(tester).revealed, isFalse);
    final state = tester.state<ScratchCardState>(find.byType(ScratchCard));
    expect(state.strokeCount, 1);
    expect(state.coverage.clearedCount, greaterThan(0));

    final center = tester.getCenter(find.byType(ScratchCard));
    final gesture = await tester.startGesture(center);
    for (var i = 1; i <= 8; i++) {
      await gesture.moveTo(center - Offset(0, i * 10.0));
    }
    await gesture.up();
    await tester.pump();
    expect(state.strokeCount, 10);
    expect(scratchCard(tester).revealed, isFalse);
    expect(recordedHaptics.where((kind) => kind == HapticKind.tick), isNotEmpty);
    expect(await real(tester, () => space.roulette.current()), isNull);
  });

  testWidgets('picks up the card that was saved, and changes made on the other phone', (tester) async {
    calm(tester);
    final space = await real(tester, openReadySpace);
    await real(tester, () => space.roulette.persist(ideaId: 'd6', category: 'outdoor', revealed: true));

    await openTab(tester, space, 'Dates');
    await untilFound(tester, find.text('Sunrise Breakfast Picnic'));
    expect(chipSelected(tester, 'Outdoor'), isTrue);
    expect(scratchCard(tester).revealed, isTrue);

    await real(tester, () => space.roulette.persist(ideaId: 'd9', category: 'food', revealed: false));
    await untilFound(tester, find.text('Fondue & Storytelling by Candlelight'));
    expect(chipSelected(tester, 'Foodie'), isTrue);
    expect(scratchCard(tester).revealed, isFalse);

    await real(tester, () => space.roulette.persist(ideaId: 'nope', category: 'food', revealed: true));
    await idle(tester);
    expect(shownIdea(tester).id, 'd9');
    expect(scratchCard(tester).revealed, isFalse);
  });

  test('every category has its web icon', () {
    expect(dateIdeaCategoryIcons.keys, dateIdeaCategories.map((category) => category.id));
    expect(dateIdeaCategoryIcons['athome'], AppIcons.home);
    expect(dateIdeaCategoryIcons['budget'], AppIcons.piggyBank);
  });
}
