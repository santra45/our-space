import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/presentation/app_shell.dart';
import 'package:our_space_mobile/presentation/screens/bucketlist/bucket_copy.dart';
import 'package:our_space_mobile/presentation/screens/bucketlist/dream_row.dart';
import 'package:our_space_mobile/presentation/screens/bucketlist/layout_glide.dart';
import 'package:our_space_mobile/presentation/screens/countdown/constellation.dart';
import 'package:our_space_mobile/presentation/screens/countdown/milestone_copy.dart';
import 'package:our_space_mobile/presentation/screens/love/love_sheet.dart';
import 'package:our_space_mobile/presentation/screens/roulette/roulette_copy.dart';
import 'package:our_space_mobile/presentation/screens/roulette/scratch_card.dart';
import 'package:our_space_mobile/presentation/screens/us/us_copy.dart';
import 'package:our_space_mobile/presentation/screens/us/us_keys.dart';
import 'package:our_space_mobile/presentation/screens/us/us_page.dart';
import 'package:our_space_mobile/presentation/sky/sky.dart';

import '../../widgets/harness.dart' show usePhoneSize;
import 'us_harness.dart';

const String _emojiPattern = r'[\p{Extended_Pictographic}\u{FE0F}]';
final RegExp _emoji = RegExp(_emojiPattern, unicode: true);
final RegExp _engineWords = RegExp(
  r'\b(sync\w*|devices?|pair\w*|servers?|upload\w*|download\w*|data|peers?|relays?|mailbox\w*|encrypt\w*|keys?)\b',
  caseSensitive: false,
);

List<String> visibleTexts(WidgetTester tester) {
  final texts = <String>[];
  for (final element in find.byWidgetPredicate((widget) => widget is Text || widget is RichText).evaluate()) {
    final widget = element.widget;
    if (widget is Text) {
      final value = widget.data ?? widget.textSpan?.toPlainText();
      if (value != null) texts.add(value);
    } else if (widget is RichText) {
      texts.add(widget.text.toPlainText());
    }
  }
  return texts;
}

void expectWarmCopy(WidgetTester tester) {
  for (final text in visibleTexts(tester)) {
    expect(_emoji.hasMatch(text), isFalse, reason: 'emoji in "$text"');
    expect(_engineWords.hasMatch(text), isFalse, reason: 'engine word in "$text"');
  }
}

double topOf(WidgetTester tester, Finder finder) => tester.getTopLeft(finder).dy;

void main() {
  test('the sections keep their names', () {
    expect(UsSection.values.map((section) => section.label), ['Our story', 'Dreams', 'Date night']);
    expect(const UsPage().initialSection, UsSection.story);
  });

  testWidgets('Us shows the counter, next milestones, constellation, dreams and date night in order', (tester) async {
    calm(tester);
    final space = await usSpace(tester);
    await pumpUs(tester, space);
    await untilFound(tester, find.text(BucketCopy.count(0, 6)));

    expect(find.byType(ShellAvatar), findsOneWidget);
    expect(find.text('SINCE 14 JUNE 2021'), findsOneWidget);
    final order = [
      find.byKey(UsKeys.hero),
      find.byKey(UsKeys.upcoming),
      find.text(MilestoneCopy.constellation),
      find.text(BucketCopy.title),
      find.text(RouletteCopy.title),
    ];
    final tops = [for (final finder in order) topOf(tester, finder)];
    expect(tops, [...tops]..sort());
    expect(find.byType(SkyCanvas), findsWidgets);
    expect(tester.widget<SkyBackdrop>(find.byType(SkyBackdrop).first).scene, UsPage.scene);
    await rest(tester, space);
  });

  testWidgets('opening at dreams or date night brings that part into view', (tester) async {
    calm(tester);
    final space = await usSpace(tester);
    await pumpUs(tester, space, section: UsSection.dreams);
    await untilFound(tester, find.text(BucketCopy.count(0, 6)));
    await tester.pump();
    await tester.pump();
    final dreamsTop = topOf(tester, find.text(BucketCopy.title));
    expect(dreamsTop, inInclusiveRange(0, 120));
    await rest(tester, space);

    final again = await usSpace(tester);
    await pumpUs(tester, again, section: UsSection.dates);
    await untilFound(tester, find.text(BucketCopy.count(0, 6)));
    await tester.pump();
    await tester.pump();
    final height = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final panel = tester.getRect(find.byKey(UsKeys.scratchPanel));
    expect(panel.top, lessThan(height));
    expect(topOf(tester, find.text(RouletteCopy.title)), lessThan(height / 2));
    await rest(tester, again);
  });

  testWidgets('a hand on the page stops it from jumping to a section', (tester) async {
    calm(tester);
    final space = await usSpace(tester);
    await pumpUs(tester, space, section: UsSection.dates);
    await untilFound(tester, find.text(BucketCopy.count(0, 6)));
    await tester.pump();
    ScrollPosition page() => tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    expect(page().pixels, greaterThan(200));

    await tester.dragFrom(const Offset(200, 150), const Offset(0, 160));
    await tester.pump();
    final scrolled = page().pixels;
    await drive(tester, () => space.milestones.add(title: 'Our first call', date: '2021-06-15'));
    await untilFound(tester, find.text('Our first call'));
    await tester.pump();
    await tester.pump();
    expect(page().pixels, scrolled);
    await rest(tester, space);
  });

  testWidgets('no engine words and no emoji reach the screen, sheets included', (tester) async {
    calm(tester);
    final space = await usSpace(tester);
    await real(tester, () => space.milestones.add(title: 'First date', date: '2021-06-14'));
    await pumpUs(tester, space);
    await untilFound(tester, find.text(BucketCopy.count(0, 6)));
    await untilFound(tester, find.text('First date'));
    expectWarmCopy(tester);

    await pressAndSettle(tester, find.byKey(UsKeys.hero));
    expectWarmCopy(tester);
    await pressAndSettle(tester, find.text(MilestoneCopy.notNow));

    await pressAndSettle(tester, find.text('First date'));
    expectWarmCopy(tester);
    await pressAndSettle(tester, find.byKey(UsKeys.momentRemove));
    expectWarmCopy(tester);
    await pressAndSettle(tester, find.text(MilestoneCopy.keep));
    await tester.tapAt(const Offset(20, 40));
    await settleRoutes(tester);

    await pressAndSettle(tester, find.byKey(UsKeys.addDream));
    expectWarmCopy(tester);
    await tester.tapAt(const Offset(20, 40));
    await settleRoutes(tester);
    await rest(tester, space);
  });

  testWidgets('the heart in the dock still sends love from Us', (tester) async {
    calm(tester);
    final space = await usSpace(tester);
    await pumpUs(tester, space);
    await tester.tap(find.descendant(of: find.byKey(ShellKeys.dock), matching: labelled(ShellCopy.sendLove)));
    await settleRoutes(tester);
    expect(find.byType(LoveSheet), findsOneWidget);
    await tester.tapAt(const Offset(20, 40));
    await settleRoutes(tester);
    expect(find.byType(LoveSheet), findsNothing);
    await rest(tester, space);
  });

  testWidgets('with motion on, the clock ticks, the check pops, sheets spring and the gold scratches away', (
    tester,
  ) async {
    usePhoneSize(tester);
    recordedHaptics.clear();
    var now = DateTime(2025, 10, 23, 14, 32, 9).millisecondsSinceEpoch;
    final space = await usSpace(tester, startDate: '2025-09-25');
    await pumpUs(tester, space, clock: () => now);
    await untilFound(tester, find.text(BucketCopy.count(0, 6)));
    expect(find.text('28'), findsOneWidget);
    expect(find.text('One month'), findsOneWidget);
    expect(find.byType(StarDot), findsWidgets);

    for (var i = 0; i < 3; i++) {
      now += 1000;
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.text('12'), findsOneWidget);
    expect(find.text('09'), findsNothing);

    now = DateTime(2025, 10, 23, 23, 59, 59).millisecondsSinceEpoch;
    await tester.pump(const Duration(seconds: 1));
    now += 1000;
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('29'), findsOneWidget);
    await tester.pump(SkyMotion.slow);

    final first = find.descendant(of: find.byType(DreamRow), matching: find.text(defaultBucketItems.first.text));
    await press(tester, first);
    await untilFound(tester, find.text(BucketCopy.count(1, 6)));
    await tester.pump(SkyMotion.slow);
    await tester.pump(layoutGlideDuration);

    await press(tester, find.byKey(UsKeys.addDream));
    await tester.pump(SkyMotion.sheet);
    await tester.pump(SkyMotion.sheet);
    expect(find.text(BucketCopy.newTitle), findsOneWidget);
    await tester.tapAt(const Offset(20, 40));
    await tester.pump(SkyMotion.sheet);
    await tester.pump(SkyMotion.sheet);
    expect(find.text(BucketCopy.newTitle), findsNothing);

    await reveal(tester, find.byKey(UsKeys.scratchPanel));
    await tester.pump(SkyMotion.slow);
    final rect = tester.getRect(find.byType(ScratchCard));
    for (var y = rect.top + 4; y < rect.bottom - 2; y += 14) {
      final gesture = await tester.startGesture(Offset(rect.left + 2, y));
      for (var x = rect.left + 2; x < rect.right - 2; x += 12) {
        await gesture.moveTo(Offset(x, y));
      }
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 16));
      if (tester.widget<ScratchCard>(find.byType(ScratchCard)).revealed) break;
    }
    expect(tester.widget<ScratchCard>(find.byType(ScratchCard)).revealed, isTrue);
    await tester.pump(ScratchCard.fade);
    await tester.pump(SkyMotion.celebration);
    expect(find.text(RouletteCopy.revealed), findsOneWidget);
    await rest(tester, space);
  });

  testWidgets('by day the page wears the day sky', (tester) async {
    calm(tester);
    final space = await usSpace(tester);
    await pumpUs(tester, space, day: true);
    await untilFound(tester, find.text(BucketCopy.count(0, 6)));
    expect(tester.element(find.byKey(UsKeys.hero)).sky.isDay, isTrue);
    final title = tester.widget<Text>(find.text(UsCopy.title).first);
    expect(title.style?.color, SkyTokens.day.title);
    expect(find.text(RouletteCopy.weekend), findsOneWidget);
    expectWarmCopy(tester);
    await rest(tester, space);
  });
}
