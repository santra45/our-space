import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/presentation/app_shell.dart';
import 'package:our_space_mobile/presentation/screens/love/love_sheet.dart';
import 'package:our_space_mobile/presentation/screens/love/love_week.dart';
import 'package:our_space_mobile/presentation/screens/love/widgets/love_counts.dart';
import 'package:our_space_mobile/presentation/screens/love/widgets/love_heart.dart';
import 'package:our_space_mobile/presentation/sky/sky.dart';
import 'package:our_space_mobile/presentation/widgets/app_haptics.dart';

import '../../widgets/harness.dart' show recordHaptics, recordedHaptics, usePhoneSize;
import 'love_sheet_harness.dart';

const String reaches = 'It reaches Alex right away, wherever she is.';

void main() {
  setUp(recordHaptics);

  testWidgets('the centre heart opens the love sheet for the partner and the scrim closes it', (tester) async {
    calm(tester);
    final space = await coupleSpace(tester);
    await pumpLove(tester, space);
    await openLoveSheet(tester);

    expect(find.text(LoveSheetCopy.title), findsOneWidget);
    expect(find.text('FOR ALEX'), findsOneWidget);
    expect(noteSays(reaches), findsOneWidget);
    expect(find.text('HOLD TO SEND'), findsOneWidget);
    expect(heartFor('Alex'), findsOneWidget);
    await untilFound(tester, labelled('0 sent this week'));
    expect(labelled('0 from Alex'), findsOneWidget);
    expect(find.text('sent this week'), findsOneWidget);
    expect(find.text('from Alex'), findsOneWidget);
    expect(find.text(LoveSheetCopy.waiting('Alex')), findsOneWidget);

    await closeLoveSheet(tester, space);
  });

  testWidgets('a tap on the heart only shows a gentle hint', (tester) async {
    calm(tester);
    final space = await coupleSpace(tester);
    await pumpLove(tester, space);
    await openLoveSheet(tester);
    await untilFound(tester, labelled('0 sent this week'));

    recordedHaptics.clear();
    await tester.tap(heartFor('Alex'));
    await tester.pump();
    expect(noteSays(LoveSheetCopy.hint), findsOneWidget);
    expect(noteSays(reaches), findsNothing);
    expect(find.text('HOLD TO SEND'), findsOneWidget);
    expect(recordedHaptics, [HapticKind.tick]);
    expect(await bursts(tester, space), isEmpty);

    await tester.pump(LoveSheet.noteLife);
    expect(noteSays(LoveSheetCopy.hint), findsNothing);
    expect(noteSays(reaches), findsOneWidget);

    await closeLoveSheet(tester, space);
  });

  testWidgets('holding the heart sends a love burst, celebrates and counts it for the week', (tester) async {
    calm(tester);
    final space = await coupleSpace(tester);
    await pumpLove(tester, space);
    await openLoveSheet(tester);
    await untilFound(tester, labelled('0 sent this week'));

    recordedHaptics.clear();
    final gesture = await tester.startGesture(tester.getCenter(heartFor('Alex')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('KEEP HOLDING'), findsOneWidget);
    await tester.pump(LoveHeart.holdDuration);
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(recordedHaptics, [HapticKind.tick, HapticKind.celebration]);
    expect(noteSays(LoveSheetCopy.hint), findsNothing);

    await untilToast(tester, (message) => message == 'Saved. Alex will see it the moment you two connect.');
    await untilFound(tester, noteSays(LoveSheetCopy.saved('Alex')));
    expect(find.text('SENT WITH LOVE'), findsOneWidget);
    final sent = await bursts(tester, space);
    expect(sent, hasLength(1));
    expect(sent.single['count'], 1);
    await untilFound(tester, labelled('1 sent this week'));
    expect(labelled('0 from Alex'), findsOneWidget);

    await holdHeart(tester, 'Alex');
    expect(find.text('SENT WITH LOVE'), findsOneWidget);
    expect((await bursts(tester, space)).single['count'], 1);

    await tester.pump(LoveSheet.cooldown);
    expect(find.text('HOLD TO SEND'), findsOneWidget);
    await holdHeart(tester, 'Alex');
    await untilFound(tester, find.text('SENT WITH LOVE'));
    await untilFound(tester, labelled('2 sent this week'));
    expect((await bursts(tester, space)).single['count'], 2);

    await tester.pump(LoveSheet.cooldown);
    await closeLoveSheet(tester, space);
  });

  testWidgets('sliding off the heart lets go without sending', (tester) async {
    calm(tester);
    final space = await coupleSpace(tester);
    await pumpLove(tester, space);
    await openLoveSheet(tester);
    await untilFound(tester, labelled('0 sent this week'));

    recordedHaptics.clear();
    final gesture = await tester.startGesture(tester.getCenter(heartFor('Alex')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('KEEP HOLDING'), findsOneWidget);
    await gesture.moveBy(const Offset(60, 0));
    await tester.pump();
    expect(find.text('HOLD TO SEND'), findsOneWidget);
    await tester.pump(LoveHeart.holdDuration);
    await gesture.up();
    await tester.pump();

    expect(recordedHaptics, isNot(contains(HapticKind.celebration)));
    expect(noteSays(LoveSheetCopy.hint), findsNothing);
    expect(await bursts(tester, space), isEmpty);
    expect(find.byType(LoveSheet), findsOneWidget);

    await closeLoveSheet(tester, space);
  });

  testWidgets('love from the partner shows in the count and the latest row as it arrives', (tester) async {
    calm(tester);
    final space = await coupleSpace(tester);
    await pumpLove(tester, space);
    await openLoveSheet(tester);
    await untilFound(tester, labelled('0 from Alex'));

    final now = DateTime.now();
    final at = DateTime(now.year, now.month, now.day, 0, 5).millisecondsSinceEpoch;
    await partnerSendsLove(tester, space, count: 3, at: at);
    await untilFound(tester, labelled('3 from Alex'));
    await untilToast(tester, (message) => message.contains('3 love bursts'));
    expect(labelled('0 sent this week'), findsOneWidget);
    expect(find.text(LoveSheetCopy.waiting('Alex')), findsNothing);
    expect(find.text('Alex sent you love', findRichText: true), findsOneWidget);
    final clock = const DefaultMaterialLocalizations().formatTimeOfDay(
      TimeOfDay.fromDateTime(DateTime.fromMillisecondsSinceEpoch(at)),
    );
    expect(find.text(clock), findsOneWidget);
    expect(labelled(LoveSheetCopy.latest('Alex', clock)), findsOneWidget);
    final row = find.descendant(of: find.byType(LoveNote), matching: find.byType(SkyAvatar));
    expect(row, findsOneWidget);
    expect(tester.widget<SkyAvatar>(row).initial, 'A');
    expect(tester.widget<SkyAvatar>(row).style, SkyAvatarStyle.partner);

    final earlier = DateTime(2026, 6, 14, 12).millisecondsSinceEpoch;
    await partnerSendsLove(tester, space, count: 1204, at: earlier);
    await untilFound(tester, labelled('1,204 from Alex'));
    await untilToast(tester, (message) => message.contains('99+'));
    expect(find.text('Jun 14'), findsOneWidget);
    expect(labelled(LoveSheetCopy.latest('Alex', 'Jun 14')), findsOneWidget);

    await closeLoveSheet(tester, space);
  });

  testWidgets('love sent in an earlier week does not count as this week', (tester) async {
    calm(tester);
    final space = await coupleSpace(tester);
    final longAgo = DateTime.now().subtract(const Duration(days: 30)).millisecondsSinceEpoch;
    await putBurst(tester, space, space.loveBursts.ownBurstRecordId, count: 5, at: longAgo);
    await pumpLove(tester, space);
    await openLoveSheet(tester);
    await untilFound(tester, labelled('0 sent this week'));

    await holdHeart(tester, 'Alex');
    await untilFound(tester, find.text('SENT WITH LOVE'));
    await untilFound(tester, labelled('1 sent this week'));
    expect((await bursts(tester, space)).single['count'], 6);
    final week = LoveWeek.decode(space.store.settings.getItem(LoveWeek.storageKey));
    expect(week?.count, 1);
    expect(week?.start, LoveWeek.startOf(DateTime.now()));

    await tester.pump(LoveSheet.cooldown);
    await closeLoveSheet(tester, space);
    await openLoveSheet(tester);
    await untilFound(tester, labelled('1 sent this week'));
    await closeLoveSheet(tester, space);
  });

  testWidgets('a love burst that does not go through says so and can be tried again', (tester) async {
    calm(tester);
    final space = await coupleSpace(tester);
    await pumpLove(tester, space);
    await untilFound(tester, find.byKey(ShellKeys.dock));

    var attempts = 0;
    final replies = [Completer<bool>(), Completer<bool>()];
    unawaited(
      showSkySheet<void>(
        context: tester.element(find.byKey(ShellKeys.dock)),
        builder: (_) => LoveSheet(send: () => replies[attempts++].future),
      ),
    );
    await settleRoute(tester);
    await untilFound(tester, labelled('0 sent this week'));

    recordedHaptics.clear();
    await holdHeart(tester, 'Alex');
    expect(attempts, 1);
    expect(recordedHaptics, contains(HapticKind.celebration));
    expect(find.text('ON ITS WAY'), findsOneWidget);
    await holdHeart(tester, 'Alex');
    expect(attempts, 1);

    replies[0].complete(false);
    await untilFound(tester, noteSays(LoveSheetCopy.failed));
    expect(find.text('HOLD TO TRY AGAIN'), findsOneWidget);
    expect(find.byWidgetPredicate((widget) => widget is SkyIcon && widget.icon == SkyIcons.alert), findsOneWidget);

    await holdHeart(tester, 'Alex');
    expect(attempts, 2);
    expect(noteSays(LoveSheetCopy.failed), findsNothing);
    replies[1].complete(true);
    await untilFound(tester, noteSays(LoveSheetCopy.saved('Alex')));
    expect(find.text('SENT WITH LOVE'), findsOneWidget);
    expect(await bursts(tester, space), isEmpty);

    await tester.pump(LoveSheet.cooldown);
    await closeLoveSheet(tester, space);
  });

  testWidgets('while Our Space is locked the counts wait and the heart asks to unlock first', (tester) async {
    calm(tester);
    final space = await coupleSpace(tester);
    space.vault.lock();
    await tester.pumpWidget(sheetHost(space));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(labelled('sent this week'), findsOneWidget);
    expect(find.text(LoveCount.pending), findsNWidgets(2));

    recordedHaptics.clear();
    await holdHeart(tester, null);
    expect(recordedHaptics, contains(HapticKind.celebration));
    expect(noteSays(LoveSheetCopy.locked), findsOneWidget);
    expect(find.text('HOLD TO TRY AGAIN'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('the love sheet follows the day sky', (tester) async {
    usePhoneSize(tester);
    final space = await coupleSpace(tester);
    await tester.pumpWidget(sheetHost(space, tokens: SkyTokens.day));
    await tester.pump();
    await untilFound(tester, labelled('0 sent this week'));
    await tester.pump(const Duration(milliseconds: 600));

    final title = tester.widget<Text>(find.text(LoveSheetCopy.title));
    expect(title.style?.color, SkyTokens.day.text);
    final hold = tester.widget<Text>(find.text('HOLD TO SEND'));
    expect(hold.style?.color, SkyTokens.day.rose);
    final painter = tester
        .widget<CustomPaint>(find.descendant(of: find.byType(LoveHeart), matching: find.byType(CustomPaint)))
        .painter! as LoveHeartPainter;
    expect(painter.tokens.isDay, isTrue);
    expect(painter.live, isTrue);

    await holdHeart(tester, 'Alex', extra: const Duration(milliseconds: 300));
    await untilFound(tester, find.text('SENT WITH LOVE'));
    await untilFound(tester, labelled('1 sent this week'));
    await tester.pump(LoveSheet.cooldown);
    expect(find.text('HOLD TO SEND'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await settle(tester, space);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
