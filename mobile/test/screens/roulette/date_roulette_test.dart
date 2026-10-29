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

  testWidgets('adds our own date idea, changes it and takes it out only after asking', (tester) async {
    calm(tester);
    final space = await usSpace(tester);
    await openDateNight(tester, space);
    await untilFound(tester, find.text(RouletteCopy.ideasCount(10)));
    expect(labelled(RouletteCopy.ideasEntryLabel(10)), findsOneWidget);

    await pressAndSettle(tester, find.byKey(UsKeys.ideasEntry));
    expect(inSheet(find.text(RouletteCopy.ideasTitle)), findsOneWidget);
    await untilFound(tester, inSheet(find.text('Living Room Pillow Fort Movie Night')));
    expect(inSheet(find.text('AT HOME')), findsOneWidget);
    expect(inSheet(find.text('FOODIE')), findsOneWidget);

    await pressAndSettle(tester, find.byKey(UsKeys.addIdea));
    expect(find.text(RouletteCopy.newTitle), findsOneWidget);
    expect(buttonEnabled(tester, UsKeys.ideaSave), isFalse);
    await typeInto(tester, fieldIn(UsKeys.ideaTitle), '  Cook the same dinner on a call  ');
    await typeInto(tester, fieldIn(UsKeys.ideaDesc), 'Same recipe, two kitchens');
    await press(tester, find.widgetWithText(SkyChip, 'Foodie'));
    expect(tester.widget<SkyChip>(find.widgetWithText(SkyChip, 'Foodie')).tone, SkyChipTone.on);
    expect(buttonEnabled(tester, UsKeys.ideaSave), isTrue);

    recordedHaptics.clear();
    await press(tester, find.byKey(UsKeys.ideaSave));
    await untilFound(tester, inSheet(find.text('Cook the same dinner on a call')));
    await settleRoutes(tester);
    expect(find.text(RouletteCopy.newTitle), findsNothing);
    expect(recordedHaptics, contains(HapticKind.celebration));
    final added = (await drive(tester, space.dateIdeas.list)).last;
    expect(added.id, startsWith('date-'));
    expect(added.title, 'Cook the same dinner on a call');
    expect(added.desc, 'Same recipe, two kitchens');
    expect(added.category, 'food');

    await pressAndSettle(tester, find.byKey(UsKeys.idea(added.id)));
    expect(find.text(RouletteCopy.editTitle), findsOneWidget);
    expect(fieldText(tester, UsKeys.ideaTitle), 'Cook the same dinner on a call');
    expect(fieldText(tester, UsKeys.ideaDesc), 'Same recipe, two kitchens');
    await typeInto(tester, fieldIn(UsKeys.ideaTitle), 'Dinner on a call, same playlist');
    await press(tester, find.byKey(UsKeys.ideaSave));
    await untilFound(tester, inSheet(find.text('Dinner on a call, same playlist')));
    await settleRoutes(tester);
    expect(find.text(RouletteCopy.editTitle), findsNothing);

    await pressAndSettle(tester, find.byKey(UsKeys.idea(added.id)));
    await pressAndSettle(tester, find.byKey(UsKeys.ideaRemove));
    expect(find.text(RouletteCopy.confirmRemove), findsOneWidget);
    expect(find.text(RouletteCopy.confirmRemoveNote), findsOneWidget);
    await pressAndSettle(tester, find.text(RouletteCopy.keep));
    expect(find.text(RouletteCopy.editTitle), findsOneWidget);

    await pressAndSettle(tester, find.byKey(UsKeys.ideaRemove));
    await pressAndSettle(tester, find.text(RouletteCopy.confirmRemoveYes));
    await untilGone(tester, find.byKey(UsKeys.idea(added.id)));
    expect(find.text(RouletteCopy.editTitle), findsNothing);
    expect((await drive(tester, space.dateIdeas.list)).map((idea) => idea.id), isNot(contains(added.id)));
    await rest(tester, space);
  });

  testWidgets('a built in idea can be changed and the card shows the new words', (tester) async {
    calm(tester);
    final space = await usSpace(tester);
    await openDateNight(tester, space);
    await pressAndSettle(tester, find.byKey(UsKeys.ideasEntry));
    await untilFound(tester, find.byKey(UsKeys.idea('d1')));
    await pressAndSettle(tester, find.byKey(UsKeys.idea('d1')));
    expect(fieldText(tester, UsKeys.ideaTitle), 'Living Room Pillow Fort Movie Night');
    expect(tester.widget<SkyChip>(find.widgetWithText(SkyChip, 'At home')).tone, SkyChipTone.on);
    await typeInto(tester, fieldIn(UsKeys.ideaTitle), 'Pillow fort on a video call');
    await press(tester, find.byKey(UsKeys.ideaSave));
    await untilFound(tester, inSheet(find.text('Pillow fort on a video call')));
    await settleRoutes(tester);
    await until(tester, () => shownIdea(tester).title == 'Pillow fort on a video call');
    expect(shownIdea(tester).id, 'd1');
    expect((await drive(tester, space.dateIdeas.list)).first.title, 'Pillow fort on a video call');
    await rest(tester, space);
  });

  testWidgets('when the idea on the card is taken out the card moves on to the next one', (tester) async {
    calm(tester);
    final space = await usSpace(tester);
    await openDateNight(tester, space);
    expect(shownIdea(tester).id, 'd1');
    await drive(tester, () => space.dateIdeas.remove('d1'));
    await until(tester, () => shownIdea(tester).id == 'd2');
    expect(scratchCard(tester).revealed, isFalse);
    expect(find.text(RouletteCopy.ideasCount(9)), findsOneWidget);
    await rest(tester, space);
  });

  testWidgets('a kind with no ideas left shows a gentle card instead of the gold', (tester) async {
    calm(tester);
    final space = await usSpace(tester);
    await openDateNight(tester, space);
    await drive(tester, () async {
      for (final id in ['d3', 'd5', 'd9']) {
        await space.dateIdeas.remove(id);
      }
    });
    await untilFound(tester, find.text(RouletteCopy.ideasCount(7)));

    await press(tester, ideaChip('Foodie'));
    await untilFound(tester, find.byKey(UsKeys.ideasEmpty));
    expect(find.byType(ScratchCard), findsNothing);
    expect(find.text(RouletteCopy.emptyKind), findsOneWidget);
    expect(find.text(RouletteCopy.emptyNote), findsOneWidget);
    expect(find.text(RouletteCopy.emptyHint), findsOneWidget);

    await press(tester, find.text(RouletteCopy.anotherIdea));
    expect(find.byKey(UsKeys.ideasEmpty), findsOneWidget);

    await press(tester, ideaChip('Outdoor'));
    expect(find.byType(ScratchCard), findsOneWidget);
    expect(shownIdea(tester).category, 'outdoor');
    await idle(tester);
    await rest(tester, space);
  });

  testWidgets('a card saved on the other phone for our own idea shows once that idea arrives', (tester) async {
    calm(tester);
    final space = await usSpace(tester);
    await openDateNight(tester, space);
    await drive(tester, () => space.roulette.persist(ideaId: 'date-later', category: 'outdoor', revealed: false));
    await idle(tester);
    expect(shownIdea(tester).id, 'd1');

    await drive(
      tester,
      () => space.store.putEncrypted(dateIdeasTable, {
        'id': 'date-later',
        'title': 'Watch the rain together',
        'desc': '',
        'category': 'outdoor',
        'createdAt': 5,
        'updatedAt': space.store.clock.next(),
        'deleted': false,
      }, space.vault.key),
    );
    await untilFound(tester, find.text('Watch the rain together'));
    expect(shownIdea(tester).id, 'date-later');
    expect(chipSelected(tester, 'Outdoor'), isTrue);
    await rest(tester, space);
  });
}
