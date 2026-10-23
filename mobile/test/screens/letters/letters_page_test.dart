import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/presentation/screens/letters/letter_read_page.dart';
import 'package:our_space_mobile/presentation/screens/letters/letter_shelf.dart';
import 'package:our_space_mobile/presentation/screens/letters/letter_write_sheet.dart';
import 'package:our_space_mobile/presentation/screens/letters/letters_copy.dart';
import 'package:our_space_mobile/presentation/screens/letters/letters_keys.dart';
import 'package:our_space_mobile/presentation/screens/letters/letters_page.dart';
import 'package:our_space_mobile/presentation/screens/letters/widgets/capsule_card.dart';
import 'package:our_space_mobile/presentation/screens/letters/widgets/letter_row.dart';
import 'package:our_space_mobile/presentation/screens/letters/widgets/letter_segments.dart';
import 'package:our_space_mobile/presentation/screens/letters/widgets/wax_seal.dart';
import 'package:our_space_mobile/presentation/screens/love/love_sheet.dart';
import 'package:our_space_mobile/presentation/sky/sky.dart';
import 'package:our_space_mobile/presentation/space_scope.dart';
import 'package:our_space_mobile/presentation/widgets/app_haptics.dart';

import '../../widgets/harness.dart' show recordHaptics, recordedHaptics, usePhoneSize;
import 'letters_harness.dart';

Finder segment(LetterSegment segment) => find.byKey(LetterSegmentKeys.of(segment));

Finder rowTitled(String title) => find.byWidgetPredicate((widget) => widget is LetterRow && widget.title == title);

String segmentLabel(WidgetTester tester, LetterSegment value) => tester.widget<SkyChip>(segment(value)).label;

bool segmentOn(WidgetTester tester, LetterSegment value) => tester.widget<SkyChip>(segment(value)).tone == SkyChipTone.on;

String fieldText(WidgetTester tester, Finder field) => tester.widget<TextField>(field).controller!.text;

Future<void> openWriter(WidgetTester tester) async {
  await press(tester, find.byKey(LettersKeys.write));
  await settleRoutes(tester);
  expect(find.byType(LetterWriteSheet), findsOneWidget);
}

Future<void> pickToday(WidgetTester tester) async {
  await tester.tap(find.byKey(LettersKeys.sealToggle));
  await settleRoutes(tester);
  await tester.tap(find.text('OK'));
  await settleRoutes(tester);
}

void main() {
  testWidgets('writes the first letter from the empty sky and keeps it under Sent', (tester) async {
    calm(tester);
    final space = await real(tester, openReadySpace);
    await openLetters(tester, space);
    await untilFound(tester, find.text(LettersCopy.emptyTitle));

    expect(find.widgetWithText(SkyTopBar, LettersCopy.title), findsOneWidget);
    expect(find.text(LettersCopy.kicker.toUpperCase()), findsOneWidget);
    expect(find.text(LettersCopy.emptyMessage('Alex')), findsOneWidget);
    expect(segment(LetterSegment.waiting), findsNothing);

    await press(tester, find.text(LettersCopy.writeFirst));
    await settleRoutes(tester);
    expect(find.text(LettersCopy.newLetter), findsOneWidget);
    expect(find.text(LettersCopy.startWithFeeling.toUpperCase()), findsOneWidget);
    for (final prompt in LettersCopy.prompts) {
      expect(find.text(prompt), findsOneWidget);
    }
    expect(find.text(LettersCopy.titleHelper), findsOneWidget);
    expect(find.text(LettersCopy.forOnly('Alex')), findsOneWidget);
    expect(find.text(LettersCopy.sealOff), findsOneWidget);
    expect(find.text(LettersCopy.sealNote), findsNothing);
    expect(sealEnabled(tester), isFalse);
    expect(tester.widget<AnimatedOpacity>(find.byKey(LettersKeys.saved)).opacity, 0);

    await press(tester, find.text('Open when you miss me'));
    expect(fieldText(tester, textFieldIn(LettersKeys.titleField)), 'Open when you miss me');
    expect(sealEnabled(tester), isFalse);
    expect(tester.widget<AnimatedOpacity>(find.byKey(LettersKeys.saved)).opacity, 1);
    await typeInto(tester, find.byKey(LettersKeys.bodyField), 'You are my favourite hello.');
    expect(sealEnabled(tester), isTrue);

    await press(tester, find.byKey(LettersKeys.sealButton));
    await untilFound(tester, rowTitled('Open when you miss me'));
    await settleRoutes(tester);

    expect(find.byType(LetterWriteSheet), findsNothing);
    expect(segmentOn(tester, LetterSegment.sent), isTrue);
    expect(segmentLabel(tester, LetterSegment.sent), 'Sent · 1');
    expect(segmentLabel(tester, LetterSegment.waiting), 'Waiting · 0');
    expect(find.text('Open when you miss me'), findsOneWidget);
    expect(recordedHaptics, contains(HapticKind.celebration));
    final notices = tester.element(find.byType(LettersPage)).read<AppNotices>();
    expect(notices.toast.message, LettersCopy.sealedToast('Alex'));

    final saved = await drive(tester, space.letters.list);
    expect(saved.single.title, 'Open when you miss me');
    expect(saved.single.content, 'You are my favourite hello.');
    expect(saved.single.isSealed, isFalse);
    expect(LettersWrittenHere.read(space.store.settings), {saved.single.id});

    await press(tester, segment(LetterSegment.waiting));
    await settleRoutes(tester);
    expect(find.text(LettersCopy.nothingWaitingTitle), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));
    expect(notices.toast.message, isNull);
    await openWriter(tester);
    expect(fieldText(tester, textFieldIn(LettersKeys.titleField)), isEmpty);
    expect(sealEnabled(tester), isFalse);
    await drain(tester);
  });

  testWidgets('keeps the draft when the writer is closed and opened again', (tester) async {
    calm(tester);
    final space = await real(tester, openReadySpace);
    await openLetters(tester, space);
    await untilFound(tester, find.text(LettersCopy.emptyTitle));

    await openWriter(tester);
    await typeInto(tester, textFieldIn(LettersKeys.titleField), 'Half written');
    await typeInto(tester, find.byKey(LettersKeys.bodyField), 'Still thinking');
    await press(tester, find.byKey(LettersKeys.cancel));
    await settleRoutes(tester);
    expect(find.byType(LetterWriteSheet), findsNothing);

    await openWriter(tester);
    expect(fieldText(tester, textFieldIn(LettersKeys.titleField)), 'Half written');
    expect(fieldText(tester, find.byKey(LettersKeys.bodyField)), 'Still thinking');
    expect(tester.widget<AnimatedOpacity>(find.byKey(LettersKeys.saved)).opacity, 1);
    expect(sealEnabled(tester), isTrue);
  });

  testWidgets('breaks the seal of the newest letter and remembers it was read', (tester) async {
    calm(tester);
    final space = await real(tester, openReadySpace);
    const body = 'If you are reading this, you miss me. Go to the window. Same moon.';
    await real(tester, () => space.letters.writeLetter(title: 'Open when you miss me', content: body));
    await openLetters(tester, space);
    await untilFound(tester, find.byKey(LettersKeys.feature));

    expect(find.text(LettersCopy.newTonight.toUpperCase()), findsOneWidget);
    expect(find.text('Open when you miss me'), findsOneWidget);
    expect(find.textContaining('From Alex · sealed '), findsOneWidget);
    expect(segmentLabel(tester, LetterSegment.waiting), 'Waiting · 1');
    expect(find.text(body), findsNothing);

    await press(tester, find.text(LettersCopy.breakSeal));
    await settleRoutes(tester);
    expect(find.byType(LetterReadPage), findsOneWidget);
    expect(find.text(LettersCopy.openWhen.toUpperCase()), findsOneWidget);
    expect(find.text('you miss me'), findsOneWidget);
    expect(find.text(body), findsOneWidget);
    expect(find.text(LettersCopy.letterFrom.toUpperCase()), findsOneWidget);
    expect(find.text('Alex'), findsOneWidget);
    expect(find.text(LettersCopy.signature('Alex')), findsOneWidget);
    expect(find.textContaining('Kept sealed until'), findsNothing);
    expect(find.text(LettersCopy.writeBack), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 450));
    expect(recordedHaptics, contains(HapticKind.celebration));

    final stored = await lettersOnceThey(tester, space, (letters) => letters.single.isOpened);
    expect(stored.single.isOpened, isTrue);
    expect(stored.single.openedAt, isNotNull);

    await press(tester, find.byKey(LettersKeys.love));
    await settleRoutes(tester);
    expect(find.text(LoveSheetCopy.title), findsOneWidget);
    await tester.tapAt(const Offset(20, 60));
    await settleRoutes(tester);
    expect(find.text(LoveSheetCopy.title), findsNothing);

    await press(tester, find.byKey(LettersKeys.writeBack));
    await settleRoutes(tester);
    expect(find.byType(LetterWriteSheet), findsOneWidget);
    await press(tester, find.byKey(LettersKeys.cancel));
    await settleRoutes(tester);
    expect(find.byType(LetterReadPage), findsOneWidget);

    await press(tester, find.byType(SkyBackButton));
    await settleRoutes(tester);
    expect(find.byType(LetterReadPage), findsNothing);
    await untilFound(tester, find.text(LettersCopy.openedTogether.toUpperCase()));
    expect(segmentLabel(tester, LetterSegment.opened), 'Opened · 1');
    expect(segmentLabel(tester, LetterSegment.waiting), 'Waiting · 0');
    final written = DateTime.fromMillisecondsSinceEpoch(stored.single.writtenAt);
    expect(find.text(LettersCopy.from('Alex', LettersCopy.shortDate(written, DateTime.now()))), findsOneWidget);

    await press(tester, find.text('Open when you miss me'));
    await settleRoutes(tester);
    expect(find.text(body), findsOneWidget);
    recordedHaptics.clear();
    await tester.pump(const Duration(milliseconds: 450));
    expect(recordedHaptics, isNot(contains(HapticKind.celebration)));
    await drain(tester);
  });

  testWidgets('a time capsule stays shut, counts the nights and says when it opens', (tester) async {
    calm(tester);
    final space = await real(tester, openReadySpace);
    final unlockDate = inDays(40);
    await real(tester, () => space.letters.writeLetter(title: 'Anniversary', content: 'Happy year!', unlockDate: unlockDate));
    await openLetters(tester, space);
    await untilFound(tester, find.byType(CapsuleCard));

    expect(find.text(LettersCopy.capsuleFrom('Alex')), findsOneWidget);
    expect(find.textContaining('Opens ${LettersCopy.longDate(unlockDate)} · 40 nights'), findsOneWidget);
    expect(find.text(LettersCopy.breakSeal), findsNothing);
    expect(segmentLabel(tester, LetterSegment.waiting), 'Waiting · 1');

    await press(tester, find.text('Anniversary'));
    expect(find.byType(LetterReadPage), findsNothing);
    final notice = find.textContaining('"Anniversary" is sealed until ${formatDatePretty(unlockDate)} - ');
    expect(notice, findsOneWidget);
    expect(find.textContaining('We will not open it early.'), findsOneWidget);
    final text = tester.widget<SkyNotice>(find.byKey(LettersKeys.notice)).text;
    expect(skyCalmText(text), text);
    expect(text, isNot(contains('💕')));

    await tester.tap(find.descendant(of: find.byKey(LettersKeys.notice), matching: labelled(LettersCopy.dismiss)));
    await tester.pump();
    expect(notice, findsNothing);

    await press(tester, find.text('Anniversary'));
    expect(notice, findsOneWidget);
    await tester.pump(const Duration(seconds: 8));
    expect(notice, findsNothing);

    await press(tester, labelled(LettersCopy.moreFor));
    await settleRoutes(tester);
    expect(find.text(LettersCopy.tryToOpen), findsOneWidget);
    await press(tester, find.text(LettersCopy.tryToOpen));
    await settleRoutes(tester);
    expect(notice, findsOneWidget);

    await press(tester, labelled(LettersCopy.moreFor));
    await settleRoutes(tester);
    await press(tester, find.text(LettersCopy.deleteLetter));
    await settleRoutes(tester);
    expect(find.text(LettersCopy.deleteMessage("Alex's")), findsOneWidget);
    await press(tester, find.text(LettersCopy.deleteConfirm));
    await settleRoutes(tester);
    await untilFound(tester, find.text(LettersCopy.emptyTitle));
    expect(await drive(tester, space.letters.list), isEmpty);
    await drain(tester);
  });

  testWidgets('tucks away a letter that was saved with a date but not sealed yet', (tester) async {
    calm(tester);
    final space = await real(tester, openReadySpace);
    final id = await seedLetter(tester, space, title: 'From the web', content: 'Wait for it', unlockDate: inDays(10));

    await openLetters(tester, space);
    await untilFound(tester, find.byType(CapsuleCard));

    await lettersOnceThey(tester, space, (letters) => letters.single.isSealed);
    final plain = await drive(tester, () => space.letters.readPlain(id));
    expect(plain!['content'], isNull);
    expect(plain['sealedContent'], isA<Map<String, Object?>>());
    expect(plain['title'], 'From the web');
  });

  testWidgets('a letter sealed for today opens from Sent and remembers its time lock', (tester) async {
    calm(tester);
    final space = await real(tester, openReadySpace);
    await openLetters(tester, space);
    await untilFound(tester, find.text(LettersCopy.emptyTitle));

    await openWriter(tester);
    await typeInto(tester, textFieldIn(LettersKeys.titleField), 'Today');
    await typeInto(tester, find.byKey(LettersKeys.bodyField), 'Sealed and opened the same day.');

    final today = toLocalDateInput(DateTime.now());
    final sealedToday = LettersCopy.sealOn(today, DateTime.now(), night: true);
    await pickToday(tester);
    expect(find.text(sealedToday), findsOneWidget);
    expect(find.text(LettersCopy.sealNote), findsOneWidget);

    await tester.tap(find.byKey(LettersKeys.sealToggle));
    await tester.pump();
    expect(find.text(LettersCopy.sealOff), findsOneWidget);
    expect(find.text(LettersCopy.sealNote), findsNothing);

    await press(tester, find.byKey(LettersKeys.sealRow));
    await settleRoutes(tester);
    await tester.tap(find.text('OK'));
    await settleRoutes(tester);
    expect(find.text(sealedToday), findsOneWidget);

    await press(tester, find.byKey(LettersKeys.sealButton));
    await untilFound(tester, rowTitled('Today'));
    await settleRoutes(tester);
    expect(find.textContaining(LettersCopy.waitingFor('Alex')), findsWidgets);

    final stored = await drive(tester, space.letters.list);
    expect(stored.single.isSealed, isTrue);
    expect(stored.single.content, isNull);
    expect(stored.single.lockDate, today);

    await press(tester, find.text('Today'));
    await settleRoutes(tester);
    await settleRoutes(tester);
    expect(find.byType(LetterReadPage), findsOneWidget);
    expect(find.text('Sealed and opened the same day.'), findsOneWidget);
    expect(find.text(LettersCopy.letterFrom.toUpperCase()), findsOneWidget);
    expect(find.text(LettersCopy.you), findsOneWidget);
    expect(find.text(LettersCopy.signature('Sam')), findsOneWidget);
    expect(find.text(LettersCopy.keptUntil(today)), findsOneWidget);
    expect(find.text(LettersCopy.stillWaitingFor('Alex')), findsOneWidget);
    expect(find.text(LettersCopy.writeAnother), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 450));
    final after = await drive(tester, space.letters.list);
    expect(after.single.isOpened, isFalse);
    await drain(tester);
  });

  testWidgets('a long press on the newest letter gives feedback and offers its options', (tester) async {
    calm(tester);
    final space = await real(tester, openReadySpace);
    await real(tester, () => space.letters.writeLetter(title: 'Newest', content: 'Hello you'));
    await openLetters(tester, space);
    await untilFound(tester, find.byKey(LettersKeys.feature));

    recordedHaptics.clear();
    await tester.longPress(find.text('Newest'));
    await settleRoutes(tester);
    expect(recordedHaptics, contains(HapticKind.tap));
    expect(find.text(LettersCopy.readIt), findsOneWidget);
    await drain(tester);
  });

  testWidgets('deletes letters after asking, from the list and from an open letter', (tester) async {
    calm(tester);
    final space = await real(tester, openReadySpace);
    await real(tester, () => space.letters.writeLetter(title: 'First', content: 'One'));
    await real(tester, () => space.letters.writeLetter(title: 'Second', content: 'Two'));
    await openLetters(tester, space);
    await untilFound(tester, find.text('First'));
    expect(find.text(LettersCopy.alsoWaiting.toUpperCase()), findsOneWidget);
    expect(find.textContaining(LettersCopy.readyToOpen), findsOneWidget);

    await tester.longPress(find.text('First'));
    await settleRoutes(tester);
    expect(find.text(LettersCopy.readIt), findsOneWidget);
    await press(tester, find.text(LettersCopy.deleteLetter));
    await settleRoutes(tester);
    expect(find.text(LettersCopy.deleteTitle), findsOneWidget);
    expect(find.text(LettersCopy.deleteMessage("Alex's")), findsOneWidget);
    await press(tester, find.text(LettersCopy.deleteCancel));
    await settleRoutes(tester);
    expect(find.text('First'), findsOneWidget);

    await tester.longPress(find.text('First'));
    await settleRoutes(tester);
    await press(tester, find.text(LettersCopy.deleteLetter));
    await settleRoutes(tester);
    await press(tester, find.text(LettersCopy.deleteConfirm));
    await settleRoutes(tester);
    await untilGone(tester, find.text('First'));
    expect(find.text('Second'), findsOneWidget);

    await press(tester, find.text(LettersCopy.breakSeal));
    await settleRoutes(tester);
    expect(find.byType(LetterReadPage), findsOneWidget);
    await press(tester, find.byKey(LettersKeys.more));
    await settleRoutes(tester);
    expect(find.text(LettersCopy.writeBack), findsNWidgets(2));
    await press(tester, find.text(LettersCopy.deleteLetter));
    await settleRoutes(tester);
    expect(find.text(LettersCopy.deleteMessage("Alex's")), findsOneWidget);
    await press(tester, find.text(LettersCopy.deleteConfirm));
    await settleRoutes(tester);
    await untilFound(tester, find.text(LettersCopy.emptyTitle));
    await settleRoutes(tester);
    expect(find.byType(LetterReadPage), findsNothing);
    expect(await drive(tester, space.letters.list), isEmpty);
    await drain(tester);
  });

  testWidgets('switches between waiting, opened and sent with their counts', (tester) async {
    calm(tester);
    final space = await real(tester, openReadySpace);
    final now = DateTime.now();
    for (var i = 0; i < 4; i++) {
      await seedLetter(
        tester,
        space,
        title: 'Read $i',
        written: now.subtract(Duration(days: 10 + i)),
        opened: true,
        openedAt: now.subtract(Duration(days: 9 + i)),
      );
    }
    await seedLetter(tester, space, title: 'Mine', written: now.subtract(const Duration(days: 2)), mine: true);
    await seedLetter(tester, space, title: 'Rainy day', written: now.subtract(const Duration(days: 3)));
    await openLetters(tester, space);
    await untilFound(tester, find.byKey(LettersKeys.feature));

    expect(segmentLabel(tester, LetterSegment.waiting), 'Waiting · 1');
    expect(segmentLabel(tester, LetterSegment.opened), 'Opened · 4');
    expect(segmentLabel(tester, LetterSegment.sent), 'Sent · 1');
    expect(segmentOn(tester, LetterSegment.waiting), isTrue);
    expect(find.text(LettersCopy.waitingForYou.toUpperCase()), findsOneWidget);
    expect(find.text('Mine'), findsNothing);
    expect(find.text('Read 0'), findsOneWidget);
    expect(find.text('Read 2'), findsOneWidget);
    expect(find.text('Read 3'), findsNothing);

    await press(tester, find.text(LettersCopy.seeAll));
    await settleRoutes(tester);
    expect(segmentOn(tester, LetterSegment.opened), isTrue);
    for (var i = 0; i < 4; i++) {
      expect(find.text('Read $i'), findsOneWidget);
    }
    expect(find.text('Rainy day'), findsNothing);

    await press(tester, segment(LetterSegment.sent));
    await settleRoutes(tester);
    expect(find.text('Mine'), findsOneWidget);
    expect(find.textContaining(LettersCopy.waitingFor('Alex')), findsOneWidget);
    expect(find.text('Read 0'), findsNothing);

    await press(tester, find.text('Mine'));
    await settleRoutes(tester);
    expect(find.text(LettersCopy.you), findsOneWidget);
    await press(tester, find.byType(SkyBackButton));
    await settleRoutes(tester);
    final mine = (await drive(tester, space.letters.list)).firstWhere((l) => l.title == 'Mine');
    expect(mine.isOpened, isFalse);

    await press(tester, segment(LetterSegment.waiting));
    await settleRoutes(tester);
    expect(find.text('Rainy day'), findsOneWidget);
    await drain(tester);
  });

  testWidgets('shows warm empty shelves for opened and sent letters', (tester) async {
    calm(tester);
    final space = await real(tester, openReadySpace);
    await real(tester, () => space.letters.writeLetter(title: 'Rainy day', content: 'Look up.'));
    await openLetters(tester, space);
    await untilFound(tester, find.byKey(LettersKeys.feature));

    await press(tester, segment(LetterSegment.opened));
    await settleRoutes(tester);
    expect(find.text(LettersCopy.noneOpenedTitle), findsOneWidget);

    await press(tester, segment(LetterSegment.sent));
    await settleRoutes(tester);
    expect(find.text(LettersCopy.noneSentTitle), findsOneWidget);
    expect(find.text(LettersCopy.noneSentMessage('Alex')), findsOneWidget);
    await press(tester, find.text(LettersCopy.write));
    await settleRoutes(tester);
    expect(find.byType(LetterWriteSheet), findsOneWidget);
  });

  testWidgets('a title that is not open when stays whole on the paper', (tester) async {
    calm(tester);
    final space = await real(tester, openReadySpace);
    await real(tester, () => space.letters.writeLetter(title: 'Rainy day', content: 'Look up, I am thinking of you.'));
    await openLetters(tester, space);
    await untilFound(tester, find.byKey(LettersKeys.feature));

    await press(tester, find.text(LettersCopy.breakSeal));
    await settleRoutes(tester);
    expect(find.text('Rainy day'), findsOneWidget);
    expect(find.text(LettersCopy.openWhen.toUpperCase()), findsNothing);
    await drain(tester);
  });

  testWidgets('says so when a letter cannot be opened with this passphrase', (tester) async {
    calm(tester);
    final space = await real(tester, openReadySpace);
    final stranger = await real(tester, openStrangerSpace);
    await real(tester, () async {
      await stranger.letters.writeLetter(title: 'Not ours', content: 'Hidden away');
      final rows = await stranger.store.allRows(lettersTable);
      await space.store.putRow(lettersTable, rows.single);
      await space.letters.writeLetter(title: 'Ours', content: 'Right here');
    });

    await openLetters(tester, space);
    await untilFound(tester, find.text('Ours'));
    expect(find.byKey(LettersKeys.hidden), findsOneWidget);
    expect(find.text(LettersCopy.hiddenLetters(1)), findsOneWidget);
    expect(find.text('Not ours'), findsNothing);
    expect(segmentLabel(tester, LetterSegment.waiting), 'Waiting · 1');
  });

  testWidgets('breaks the seal with motion on and leaves nothing running behind', (tester) async {
    recordHaptics();
    usePhoneSize(tester);
    tester.view.physicalSize = const Size(1290, 2796);
    final space = await real(tester, openReadySpace);
    await real(tester, () => space.letters.writeLetter(title: 'Open when you miss me', content: 'Same moon.'));
    await openLetters(tester, space);
    await untilFound(tester, find.byKey(LettersKeys.feature));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    await tester.tap(find.text(LettersCopy.breakSeal));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(LetterReadPage), findsOneWidget);
    expect(find.text('Same moon.'), findsOneWidget);
    final seal = find.byWidgetPredicate((widget) => widget is WaxSeal && widget.size == 52);
    expect(tester.widget<WaxSeal>(seal).split, closeTo(1, 0.05));
    expect(recordedHaptics, contains(HapticKind.celebration));

    await tester.tap(find.byType(SkyBackButton));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(find.byType(LetterReadPage), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await drain(tester);
  });
}
