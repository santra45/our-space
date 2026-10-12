import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/presentation/screens/bucketlist/bucket_copy.dart';
import 'package:our_space_mobile/presentation/screens/bucketlist/bucket_item_card.dart';
import 'package:our_space_mobile/presentation/screens/bucketlist/layout_glide.dart';
import 'package:our_space_mobile/presentation/widgets/our_widgets.dart';

import '../../widgets/harness.dart' show pumpHost, recordedHaptics;
import '../capsule/capsule_harness.dart';

Finder dream(String text) => find.text(breakAnywhere(text));

Finder cardOf(String text) => find.ancestor(of: dream(text), matching: find.byType(BucketItemCard));

Finder inCard(String text, Finder matching) => find.descendant(of: cardOf(text), matching: matching);

Future<void> openBucket(WidgetTester tester, OurSpace space, {int total = 6}) async {
  await openTab(tester, space, 'Bucket');
  await untilFound(tester, find.text(BucketCopy.progress(0, total, 0)));
}

void main() {
  group('bucket copy', () {
    test('counts adventures like the web', () {
      expect(BucketCopy.progress(0, 6, 0), '0 of 6 adventures completed (0%)');
      expect(BucketCopy.progress(1, 6, progressPercent(1, 6)), '1 of 6 adventures completed (17%)');
      expect(progressPercent(0, 0), 0);
      expect(progressPercent(1, 8), 13);
      expect(progressPercent(2, 3), 67);
      expect(progressPercent(5, 5), 100);
    });

    test('counts hidden dreams like the web', () {
      expect(BucketCopy.hiddenItems(1), '1 item could not be opened with your passphrase, so it is hidden for now.');
      expect(BucketCopy.hiddenItems(2), '2 items could not be opened with your passphrase, so they are hidden for now.');
    });

    test('lets a dream break anywhere without splitting emoji', () {
      expect(breakAnywhere('ab'), 'a​b');
      expect(breakAnywhere('a💕b'), 'a​💕​b');
      expect(breakAnywhere(''), '');
    });

    test('offers the four web categories', () {
      expect(bucketOptions.map((o) => o.value), ['Romance', 'Travel', 'Adventures', 'Silly']);
      expect(bucketOptions.map((o) => o.label), ['Romance 💕', 'Travel ✈️', 'Adventures 🌲', 'Silly & Fun 🤪']);
    });

    test('the completed stamp lands tilted and slightly see-through', () {
      final (startScale, startDegrees, startOpacity) = CompletedStampFrames.at(0);
      expect(startScale, 2);
      expect(startDegrees, -20);
      expect(startOpacity, 0);
      final (endScale, endDegrees, endOpacity) = CompletedStampFrames.at(1);
      expect(endScale, closeTo(1, 0.01));
      expect(endDegrees, closeTo(-8, 0.1));
      expect(endOpacity, closeTo(0.85, 1e-9));
    });
  });

  testWidgets('opens with the six starter dreams', (tester) async {
    calm(tester);
    final space = await real(tester, openReadySpace);
    await openBucket(tester, space);

    expect(find.text(BucketCopy.title), findsOneWidget);
    expect(find.text(BucketCopy.conquered), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
    expect(find.text(BucketCopy.newLabel), findsNothing);
    for (final item in defaultBucketItems) {
      expect(dream(item.text), findsOneWidget);
      expect(inCard(item.text, find.text(item.category)), findsOneWidget);
    }
    expect(find.text(BucketCopy.completed), findsNothing);

    final stored = await real(tester, space.bucketList.list);
    expect(stored.map((item) => item.id), [for (var i = 0; i < 6; i++) defaultBucketItemId(i)]);
    final tops = [for (final item in defaultBucketItems) tester.getTopLeft(dream(item.text)).dy];
    expect(tops, [...tops]..sort());
  });

  testWidgets('does not bring the starter dreams back once there are dreams', (tester) async {
    calm(tester);
    final space = await real(tester, openReadySpace);
    await real(tester, () => space.bucketList.add(text: 'See the northern lights', category: 'Travel'));
    await openBucket(tester, space, total: 1);

    expect(dream('See the northern lights'), findsOneWidget);
    expect(dream(defaultBucketItems.first.text), findsNothing);
    expect(await real(tester, space.bucketList.list), hasLength(1));
  });

  testWidgets('ticking a dream off celebrates, stamps it and moves it to the end', (tester) async {
    calm(tester);
    final space = await real(tester, openReadySpace);
    await openBucket(tester, space);
    final first = defaultBucketItems.first.text;
    final last = defaultBucketItems.last.text;
    expect(tester.getTopLeft(dream(first)).dy, lessThan(tester.getTopLeft(dream(last)).dy));

    await press(tester, dream(first));
    await untilFound(tester, find.text(BucketCopy.progress(1, 6, 17)));
    expect(find.text('17%'), findsOneWidget);
    expect(inCard(first, find.text(BucketCopy.completed)), findsOneWidget);
    expect(recordedHaptics, containsAllInOrder([HapticKind.tap, HapticKind.celebration]));
    expect(tester.getTopLeft(dream(first)).dy, greaterThan(tester.getTopLeft(dream(last)).dy));
    final card = tester.widget<BucketItemCard>(cardOf(first));
    expect(card.item.completed, isTrue);

    final ticked = (await real(tester, space.bucketList.list)).last;
    expect(ticked.id, defaultBucketItemId(0));
    expect(ticked.completed, isTrue);
    expect(ticked.completedAt, isNotNull);

    recordedHaptics.clear();
    await press(tester, dream(first));
    await untilFound(tester, find.text(BucketCopy.progress(0, 6, 0)));
    expect(find.text(BucketCopy.completed), findsNothing);
    expect(recordedHaptics, isNot(contains(HapticKind.celebration)));
    expect(tester.getTopLeft(dream(first)).dy, lessThan(tester.getTopLeft(dream(last)).dy));
    final unticked = (await real(tester, space.bucketList.list)).first;
    expect(unticked.completed, isFalse);
    expect(unticked.completedAt, isNull);
  });

  testWidgets('adds a new dream with the chosen category', (tester) async {
    calm(tester);
    final space = await real(tester, openReadySpace);
    await openBucket(tester, space);

    await press(tester, find.text(BucketCopy.addDream));
    expect(find.text(BucketCopy.newLabel), findsOneWidget);
    expect(find.text('Romance 💕'), findsOneWidget);
    await press(tester, find.text(BucketCopy.addDream));
    expect(find.text(BucketCopy.newLabel), findsNothing);

    await press(tester, find.text(BucketCopy.addDream));
    await press(tester, find.text(BucketCopy.addGoal));
    expect(find.text(BucketCopy.newLabel), findsOneWidget);
    expect(await real(tester, space.bucketList.list), hasLength(6));

    await typeInto(tester, fieldWithHint(BucketCopy.hint), '  Dance in the rain in Paris  ');
    await press(tester, find.byType(OurSelectField<String>));
    await settleRoutes(tester);
    await tester.tap(find.text('Travel ✈️'));
    await settleRoutes(tester);
    expect(find.text('Travel ✈️'), findsOneWidget);

    recordedHaptics.clear();
    await press(tester, find.text(BucketCopy.addGoal));
    await untilFound(tester, dream('Dance in the rain in Paris'));
    expect(find.text(BucketCopy.newLabel), findsNothing);
    expect(find.text(BucketCopy.progress(0, 7, 0)), findsOneWidget);
    expect(inCard('Dance in the rain in Paris', find.text('Travel')), findsOneWidget);
    expect(recordedHaptics, contains(HapticKind.celebration));

    final added = (await real(tester, space.bucketList.list)).last;
    expect(added.text, 'Dance in the rain in Paris');
    expect(added.category, 'Travel');
    expect(added.completed, isFalse);
    expect(added.id, startsWith('bkt-'));

    await press(tester, find.text(BucketCopy.addDream));
    expect(find.text('Travel ✈️'), findsOneWidget);
    final field = tester.widget<TextField>(fieldWithHint(BucketCopy.hint));
    expect(field.controller!.text, isEmpty);
  });

  testWidgets('edits a dream in place and can back out', (tester) async {
    calm(tester);
    final space = await real(tester, openReadySpace);
    await openBucket(tester, space);
    final target = defaultBucketItems[3].text;

    await press(tester, inCard(target, iconButton('Edit dream')));
    expect(find.text(BucketCopy.editLabel), findsOneWidget);
    final editing = tester.widget<TextField>(fieldWithHint(BucketCopy.hint));
    expect(editing.controller!.text, target);
    expect(find.text('Travel ✈️'), findsOneWidget);

    await press(tester, find.text(BucketCopy.editLabel));
    expect(find.text(BucketCopy.completed), findsNothing);
    expect(await real(tester, () async => (await space.bucketList.list()).where((i) => i.completed).length), 0);

    await press(tester, find.text(BucketCopy.cancel));
    expect(find.text(BucketCopy.editLabel), findsNothing);
    expect(dream(target), findsOneWidget);

    await press(tester, inCard(target, iconButton('Edit dream')));
    await typeInto(tester, fieldWithHint(BucketCopy.hint), 'Fly to Kyoto for the cherry blossoms');
    await press(tester, find.byType(OurSelectField<String>));
    await settleRoutes(tester);
    await tester.tap(find.text('Romance 💕'));
    await settleRoutes(tester);
    await press(tester, find.text(BucketCopy.save));
    await untilFound(tester, dream('Fly to Kyoto for the cherry blossoms'));
    expect(find.text(BucketCopy.editLabel), findsNothing);
    expect(dream(target), findsNothing);
    expect(inCard('Fly to Kyoto for the cherry blossoms', find.text('Romance')), findsOneWidget);

    final edited = (await real(tester, space.bucketList.list))[3];
    expect(edited.id, defaultBucketItemId(3));
    expect(edited.text, 'Fly to Kyoto for the cherry blossoms');
    expect(edited.category, 'Romance');
  });

  testWidgets('deletes a dream only after asking', (tester) async {
    calm(tester);
    final space = await real(tester, openReadySpace);
    await openBucket(tester, space);
    final target = defaultBucketItems[1].text;

    await press(tester, inCard(target, iconButton('Delete dream')));
    await settleRoutes(tester);
    expect(find.text(BucketCopy.deleteQuestion), findsOneWidget);
    await press(tester, find.text('Cancel'));
    await settleRoutes(tester);
    expect(dream(target), findsOneWidget);
    expect(find.text(BucketCopy.completed), findsNothing);

    await press(tester, inCard(target, iconButton('Delete dream')));
    await settleRoutes(tester);
    await press(tester, find.text('OK'));
    await settleRoutes(tester);
    await untilGone(tester, dream(target));
    expect(find.text(BucketCopy.progress(0, 5, 0)), findsOneWidget);
    expect(find.text(BucketCopy.completed), findsNothing);
    final left = await real(tester, space.bucketList.list);
    expect(left.map((item) => item.id), isNot(contains(defaultBucketItemId(1))));
  });

  testWidgets('says so when a dream cannot be opened with this passphrase', (tester) async {
    calm(tester);
    final space = await real(tester, openReadySpace);
    final stranger = await real(tester, openStrangerSpace);
    await real(tester, () async {
      await stranger.bucketList.add(text: 'Not ours', category: 'Silly');
      final rows = await stranger.store.allRows(bucketListTable);
      await space.store.putRow(bucketListTable, rows.single);
    });

    await openBucket(tester, space, total: 0);
    expect(find.text(BucketCopy.hiddenItems(1)), findsOneWidget);
    expect(dream(defaultBucketItems.first.text), findsNothing);
    expect(find.text('0%'), findsOneWidget);
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
