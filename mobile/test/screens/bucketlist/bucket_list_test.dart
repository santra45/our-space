import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/presentation/screens/bucketlist/bucket_copy.dart';
import 'package:our_space_mobile/presentation/screens/bucketlist/dream_row.dart';
import 'package:our_space_mobile/presentation/screens/bucketlist/layout_glide.dart';
import 'package:our_space_mobile/presentation/screens/us/us_keys.dart';
import 'package:our_space_mobile/presentation/sky/sky.dart';
import 'package:our_space_mobile/presentation/widgets/app_haptics.dart';

import '../../widgets/harness.dart' show pumpHost;
import '../us/us_harness.dart';

Finder dream(String text) => find.descendant(of: find.byType(DreamRow), matching: find.text(text));

Finder rowOf(String text) => find.ancestor(of: dream(text), matching: find.byType(DreamRow));

Finder inRow(String text, Finder matching) => find.descendant(of: rowOf(text), matching: matching);

Finder chip(String label) => find.widgetWithText(SkyChip, label);

bool chipOn(WidgetTester tester, String label) => tester.widget<SkyChip>(chip(label)).tone == SkyChipTone.on;

Future<void> openDreams(WidgetTester tester, OurSpace space, {int total = 6}) async {
  await pumpUs(tester, space);
  await untilFound(tester, find.text(BucketCopy.count(0, total)));
}

void main() {
  group('bucket copy', () {
    test('counts dreams come true', () {
      expect(BucketCopy.count(3, 12), '3 of 12');
      expect(BucketCopy.countLabel(3, 12), '3 of 12 dreams come true');
      expect(progressPercent(0, 0), 0);
      expect(progressPercent(1, 6), 17);
      expect(progressPercent(1, 8), 13);
      expect(progressPercent(2, 3), 67);
      expect(progressPercent(5, 5), 100);
    });

    test('counts hidden dreams like before', () {
      expect(BucketCopy.hiddenItems(1), '1 dream could not be opened with your passphrase, so it is hidden for now.');
      expect(
        BucketCopy.hiddenItems(2),
        '2 dreams could not be opened with your passphrase, so they are hidden for now.',
      );
    });

    test('offers the four kinds of dream with plain names', () {
      expect(dreamCategories.map((c) => c.value), bucketCategoryOptions.map((o) => o.value));
      expect(dreamCategories.map((c) => c.label), ['Romance', 'Travel', 'Adventure', 'Silly and fun']);
      expect(dreamCategoryLabel('Adventures'), 'Adventure');
      expect(dreamCategoryLabel('Food \u{1F35D}'), 'Food');
    });
  });

  testWidgets('opens with the six starter dreams', (tester) async {
    calm(tester);
    final space = await usSpace(tester);
    await openDreams(tester, space);

    expect(find.text(BucketCopy.title), findsOneWidget);
    expect(labelled(BucketCopy.countLabel(0, 6)), findsOneWidget);
    expect(tester.widget<SkyProgressBar>(find.byKey(UsKeys.dreamProgress)).value, 0);
    expect(find.text(BucketCopy.newTitle), findsNothing);
    for (final item in defaultBucketItems) {
      expect(dream(item.text), findsOneWidget);
      expect(inRow(item.text, find.text(dreamCategoryLabel(item.category))), findsOneWidget);
    }
    expect(find.byKey(UsKeys.addDream), findsOneWidget);

    final stored = await drive(tester, space.bucketList.list);
    expect(stored.map((item) => item.id), [for (var i = 0; i < 6; i++) defaultBucketItemId(i)]);
    final tops = [for (final item in defaultBucketItems) tester.getTopLeft(dream(item.text)).dy];
    expect(tops, [...tops]..sort());
    await rest(tester, space);
  });

  testWidgets('does not bring the starter dreams back once there are dreams', (tester) async {
    calm(tester);
    final space = await usSpace(tester);
    await real(tester, () => space.bucketList.add(text: 'See the northern lights', category: 'Travel'));
    await openDreams(tester, space, total: 1);

    expect(dream('See the northern lights'), findsOneWidget);
    expect(dream(defaultBucketItems.first.text), findsNothing);
    expect(await drive(tester, space.bucketList.list), hasLength(1));
    await rest(tester, space);
  });

  testWidgets('ticking a dream off celebrates, lights its check and moves it to the end', (tester) async {
    calm(tester);
    final space = await usSpace(tester);
    await openDreams(tester, space);
    final first = defaultBucketItems.first.text;
    final last = defaultBucketItems.last.text;
    expect(tester.getTopLeft(dream(first)).dy, lessThan(tester.getTopLeft(dream(last)).dy));
    expect(inRow(first, find.byType(SkyIcon)), findsOneWidget);

    await press(tester, dream(first));
    await untilFound(tester, find.text(BucketCopy.count(1, 6)));
    expect(tester.widget<SkyProgressBar>(find.byKey(UsKeys.dreamProgress)).value, closeTo(0.17, 1e-9));
    expect(recordedHaptics, containsAllInOrder([HapticKind.tick, HapticKind.tap, HapticKind.celebration]));
    expect(tester.getTopLeft(dream(first)).dy, greaterThan(tester.getTopLeft(dream(last)).dy));
    expect(tester.widget<DreamRow>(rowOf(first)).item.completed, isTrue);
    expect(tester.widget<DreamCheck>(inRow(first, find.byType(DreamCheck))).done, isTrue);
    expect(inRow(first, find.byType(SkyIcon)), findsNWidgets(2));
    expect(labelled(BucketCopy.done(first)), findsOneWidget);
    expect(DefaultTextStyle.of(tester.element(dream(first))).style.decoration, TextDecoration.lineThrough);

    final ticked = (await drive(tester, space.bucketList.list)).last;
    expect(ticked.id, defaultBucketItemId(0));
    expect(ticked.completed, isTrue);
    expect(ticked.completedAt, isNotNull);

    recordedHaptics.clear();
    await press(tester, dream(first));
    await untilFound(tester, find.text(BucketCopy.count(0, 6)));
    expect(recordedHaptics, isNot(contains(HapticKind.celebration)));
    expect(tester.getTopLeft(dream(first)).dy, lessThan(tester.getTopLeft(dream(last)).dy));
    final unticked = (await drive(tester, space.bucketList.list)).first;
    expect(unticked.completed, isFalse);
    expect(unticked.completedAt, isNull);
    await rest(tester, space);
  });

  testWidgets('adds a new dream with the chosen kind', (tester) async {
    calm(tester);
    final space = await usSpace(tester);
    await openDreams(tester, space);

    await pressAndSettle(tester, find.byKey(UsKeys.addDream));
    expect(find.text(BucketCopy.newTitle), findsOneWidget);
    expect(find.text(BucketCopy.categoryLabel), findsOneWidget);
    expect(chipOn(tester, 'Romance'), isTrue);
    expect(buttonEnabled(tester, UsKeys.dreamSave), isFalse);
    await tester.tapAt(const Offset(20, 40));
    await settleRoutes(tester);
    expect(find.text(BucketCopy.newTitle), findsNothing);

    await pressAndSettle(tester, find.byKey(UsKeys.addDream));
    await press(tester, find.byKey(UsKeys.dreamSave));
    expect(find.text(BucketCopy.newTitle), findsOneWidget);
    expect(await drive(tester, space.bucketList.list), hasLength(6));

    await typeInto(tester, fieldIn(UsKeys.dreamText), '  Dance in the rain in Paris  ');
    await press(tester, chip('Travel'));
    expect(chipOn(tester, 'Travel'), isTrue);
    expect(chipOn(tester, 'Romance'), isFalse);

    recordedHaptics.clear();
    await press(tester, find.byKey(UsKeys.dreamSave));
    await untilFound(tester, dream('Dance in the rain in Paris'));
    await settleRoutes(tester);
    expect(find.text(BucketCopy.newTitle), findsNothing);
    expect(find.text(BucketCopy.count(0, 7)), findsOneWidget);
    expect(inRow('Dance in the rain in Paris', find.text('Travel')), findsOneWidget);
    expect(recordedHaptics, contains(HapticKind.celebration));

    final added = (await drive(tester, space.bucketList.list)).last;
    expect(added.text, 'Dance in the rain in Paris');
    expect(added.category, 'Travel');
    expect(added.completed, isFalse);
    expect(added.id, startsWith('bkt-'));

    await pressAndSettle(tester, find.byKey(UsKeys.addDream));
    expect(chipOn(tester, 'Travel'), isTrue);
    expect(fieldText(tester, UsKeys.dreamText), isEmpty);
    await rest(tester, space);
  });

  testWidgets('changes a dream from its row and can back out', (tester) async {
    calm(tester);
    final space = await usSpace(tester);
    await openDreams(tester, space);
    final target = defaultBucketItems[3].text;

    await pressAndSettle(tester, inRow(target, labelled(BucketCopy.change)));
    expect(find.text(BucketCopy.editTitle), findsOneWidget);
    expect(fieldText(tester, UsKeys.dreamText), target);
    expect(chipOn(tester, 'Travel'), isTrue);
    expect(find.byKey(UsKeys.dreamRemove), findsOneWidget);

    await tester.tapAt(const Offset(20, 40));
    await settleRoutes(tester);
    expect(find.text(BucketCopy.editTitle), findsNothing);
    expect(dream(target), findsOneWidget);
    expect(await drive(tester, () async => (await space.bucketList.list()).where((i) => i.completed).length), 0);

    await pressAndSettle(tester, inRow(target, labelled(BucketCopy.change)));
    await typeInto(tester, fieldIn(UsKeys.dreamText), 'Fly to Kyoto for the cherry blossoms');
    await press(tester, chip('Romance'));
    await press(tester, find.byKey(UsKeys.dreamSave));
    await untilFound(tester, dream('Fly to Kyoto for the cherry blossoms'));
    await settleRoutes(tester);
    expect(find.text(BucketCopy.editTitle), findsNothing);
    expect(dream(target), findsNothing);
    expect(inRow('Fly to Kyoto for the cherry blossoms', find.text('Romance')), findsOneWidget);

    final edited = (await drive(tester, space.bucketList.list))[3];
    expect(edited.id, defaultBucketItemId(3));
    expect(edited.text, 'Fly to Kyoto for the cherry blossoms');
    expect(edited.category, 'Romance');
    await rest(tester, space);
  });

  testWidgets('a long press on a dream opens it too', (tester) async {
    calm(tester);
    final space = await usSpace(tester);
    await openDreams(tester, space);
    final target = defaultBucketItems[2].text;
    await reveal(tester, dream(target));
    await tester.longPress(dream(target));
    await settleRoutes(tester);
    expect(find.text(BucketCopy.editTitle), findsOneWidget);
    expect(fieldText(tester, UsKeys.dreamText), target);
    expect(chipOn(tester, 'Silly and fun'), isTrue);
    expect(await drive(tester, () async => (await space.bucketList.list()).where((i) => i.completed).length), 0);
    await rest(tester, space);
  });

  testWidgets('removes a dream only after asking', (tester) async {
    calm(tester);
    final space = await usSpace(tester);
    await openDreams(tester, space);
    final target = defaultBucketItems[1].text;

    await pressAndSettle(tester, inRow(target, labelled(BucketCopy.change)));
    await pressAndSettle(tester, find.byKey(UsKeys.dreamRemove));
    expect(find.text(BucketCopy.confirmRemove), findsOneWidget);
    expect(find.text(BucketCopy.confirmRemoveNote), findsOneWidget);
    await pressAndSettle(tester, find.text(BucketCopy.keep));
    expect(find.text(BucketCopy.editTitle), findsOneWidget);
    expect(dream(target), findsOneWidget);

    recordedHaptics.clear();
    await pressAndSettle(tester, find.byKey(UsKeys.dreamRemove));
    await pressAndSettle(tester, find.text(BucketCopy.confirmRemoveYes));
    await untilGone(tester, dream(target));
    expect(find.text(BucketCopy.editTitle), findsNothing);
    expect(find.text(BucketCopy.count(0, 5)), findsOneWidget);
    expect(recordedHaptics, contains(HapticKind.tap));
    final left = await drive(tester, space.bucketList.list);
    expect(left.map((item) => item.id), isNot(contains(defaultBucketItemId(1))));
    await rest(tester, space);
  });

  testWidgets('a dream of an unknown kind keeps its kind when changed', (tester) async {
    calm(tester);
    final space = await usSpace(tester);
    await real(tester, () => space.bucketList.add(text: 'Cook pasta from scratch', category: 'Food'));
    await openDreams(tester, space, total: 1);
    expect(inRow('Cook pasta from scratch', find.text('Food')), findsOneWidget);

    await pressAndSettle(tester, inRow('Cook pasta from scratch', labelled(BucketCopy.change)));
    expect(chipOn(tester, 'Food'), isTrue);
    await typeInto(tester, fieldIn(UsKeys.dreamText), 'Cook fresh pasta from scratch');
    await press(tester, find.byKey(UsKeys.dreamSave));
    await untilFound(tester, dream('Cook fresh pasta from scratch'));
    expect((await drive(tester, space.bucketList.list)).single.category, 'Food');
    await rest(tester, space);
  });

  testWidgets('says so when a dream cannot be opened with this passphrase', (tester) async {
    calm(tester);
    final space = await usSpace(tester);
    final stranger = await strangerSpace(tester);
    await real(tester, () async {
      await stranger.bucketList.add(text: 'Not ours', category: 'Silly');
      final rows = await stranger.store.allRows(bucketListTable);
      await space.store.putRow(bucketListTable, rows.single);
    });

    await openDreams(tester, space, total: 0);
    expect(find.text(BucketCopy.hiddenItems(1)), findsOneWidget);
    expect(find.text(BucketCopy.empty), findsOneWidget);
    expect(dream(defaultBucketItems.first.text), findsNothing);
    expect(tester.widget<SkyProgressBar>(find.byKey(UsKeys.dreamProgress)).value, 0);
    await rest(tester, space);
  });

  testWidgets('a moved dream glides from where it was', (tester) async {
    const a = ValueKey('a');
    const b = ValueKey('b');
    Widget list(List<Key> order) => GlideScope(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final key in order)
            LayoutGlide(key: key, child: SizedBox(key: ValueKey('box-$key'), width: 100, height: 40)),
        ],
      ),
    );
    Offset topOf(Key key) => tester.getTopLeft(find.byKey(ValueKey('box-$key')));

    await pumpHost(tester, list([a, b]), animations: true);
    final aTop = topOf(a);
    final bTop = topOf(b);
    expect(bTop.dy - aTop.dy, 40);

    await pumpHost(tester, list([b, a]), animations: true);
    expect(topOf(a), aTop);
    expect(topOf(b), bTop);

    await tester.pump(layoutGlideDuration ~/ 2);
    expect(topOf(a).dy, inExclusiveRange(aTop.dy, bTop.dy));
    expect(topOf(b).dy, inExclusiveRange(aTop.dy, bTop.dy));

    await tester.pump(layoutGlideDuration);
    expect(topOf(a), bTop);
    expect(topOf(b), aTop);
  });

  testWidgets('a moved dream jumps straight there when motion is reduced', (tester) async {
    const a = ValueKey('a');
    const b = ValueKey('b');
    Widget list(List<Key> order) => GlideScope(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final key in order)
            LayoutGlide(key: key, child: SizedBox(key: ValueKey('box-$key'), width: 100, height: 40)),
        ],
      ),
    );
    Offset topOf(Key key) => tester.getTopLeft(find.byKey(ValueKey('box-$key')));

    await pumpHost(tester, list([a, b]));
    final aTop = topOf(a);
    final bTop = topOf(b);
    await pumpHost(tester, list([b, a]));
    expect(topOf(a), bTop);
    expect(topOf(b), aTop);
  });
}
