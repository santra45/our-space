import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/presentation/screens/capsule/capsule_copy.dart';
import 'package:our_space_mobile/presentation/screens/capsule/letter_envelope.dart';
import 'package:our_space_mobile/presentation/screens/capsule/spring_entrance.dart';
import 'package:our_space_mobile/presentation/widgets/our_widgets.dart';

import '../../widgets/harness.dart' show recordedHaptics;
import 'capsule_harness.dart';

bool plainText(WidgetTester tester, Finder text) {
  final style = DefaultTextStyle.of(tester.element(text)).style;
  return style.decorationStyle != TextDecorationStyle.double;
}

void main() {
  group('capsule copy', () {
    test('counts hidden letters like the web', () {
      expect(
        CapsuleCopy.hiddenLetters(1),
        '1 letter could not be opened with your passphrase, so it is hidden for now.',
      );
      expect(
        CapsuleCopy.hiddenLetters(3),
        '3 letters could not be opened with your passphrase, so they are hidden for now.',
      );
    });

    test('names the seal button after the chosen day', () {
      expect(CapsuleCopy.sealButton(saving: false), 'Seal with Wax Stamp 💌');
      expect(CapsuleCopy.sealButton(saving: true), 'Tucking it away…');
      expect(CapsuleCopy.sealButton(saving: false, unlockDate: '2027-02-14'), 'Seal Until Feb 14, 2027 🔒');
      expect(CapsuleCopy.sealButton(saving: true, unlockDate: '2027-02-14'), 'Sealing…');
    });

    test('asks before deleting with the partner name', () {
      expect(
        CapsuleCopy.deleteQuestion("Alex's"),
        "Delete this love letter? It goes from your phone and Alex's, for good.",
      );
      expect(
        CapsuleCopy.emptyMessage('your partner'),
        'Leave a surprise letter for your partner, or seal a time capsule to open on your next anniversary!',
      );
    });

    test('formats the day a letter was written from its timestamp', () {
      expect(prettyTimestamp(0), '');
      expect(prettyTimestamp(DateTime(2026, 10, 9, 23, 59).millisecondsSinceEpoch), 'Oct 9, 2026');
    });

    test('entrance springs settle at rest', () {
      for (final spec in [EntranceSpec.writeModal, EntranceSpec.sealedEnvelope, EntranceSpec.openLetter]) {
        final start = entranceAt(spec, 0);
        expect(start.scale, closeTo(0.9, 1e-9));
        final end = entranceAt(spec, 1.2);
        expect(end.scale, closeTo(1, 0.01));
        expect(end.dy, closeTo(0, 0.2));
        expect(end.opacity, closeTo(1, 0.01));
      }
      expect(entranceAt(EntranceSpec.sealedEnvelope, 0).opacity, 1);
      expect(entranceAt(EntranceSpec.sealedEnvelope, 0).dy, 20);
      expect(entranceAt(EntranceSpec.openLetter, 0).dy, 30);
      expect(entranceAt(EntranceSpec.openLetter, 0).opacity, 0);
    });
  });

  testWidgets('writes the first love letter from the empty capsule', (tester) async {
    calm(tester);
    final space = await real(tester, openReadySpace);
    await openTab(tester, space, 'Letters');
    await untilFound(tester, find.text(CapsuleCopy.emptyTitle));

    expect(find.text(CapsuleCopy.title), findsOneWidget);
    expect(find.text(CapsuleCopy.subtitle), findsOneWidget);
    expect(find.text(CapsuleCopy.emptyMessage('Alex')), findsOneWidget);

    await press(tester, find.text(CapsuleCopy.writeFirst));
    await settleRoutes(tester);
    expect(find.text(CapsuleCopy.modalTitle), findsOneWidget);
    expect(find.text(CapsuleCopy.modalSubtitle), findsOneWidget);
    expect(find.text(CapsuleCopy.promise), findsOneWidget);
    expect(buttonEnabled(tester, 'Seal with Wax Stamp 💌'), isFalse);

    await typeInto(tester, fieldWithHint(CapsuleCopy.titleHint), 'Open when you miss me');
    expect(buttonEnabled(tester, 'Seal with Wax Stamp 💌'), isFalse);
    await typeInto(tester, fieldWithHint(CapsuleCopy.bodyHint), 'You are my favourite hello.');
    expect(buttonEnabled(tester, 'Seal with Wax Stamp 💌'), isTrue);

    await press(tester, find.text('Seal with Wax Stamp 💌'));
    await untilFound(tester, find.text(CapsuleCopy.readLetter));
    await settleRoutes(tester);

    expect(find.text(CapsuleCopy.modalTitle), findsNothing);
    expect(find.text('Open when you miss me'), findsOneWidget);
    expect(find.textContaining('Written on ${prettyTimestamp(DateTime.now().millisecondsSinceEpoch)}'), findsOneWidget);
    expect(recordedHaptics, contains(HapticKind.celebration));

    final saved = await real(tester, space.letters.list);
    expect(saved.single.title, 'Open when you miss me');
    expect(saved.single.content, 'You are my favourite hello.');
    expect(saved.single.isSealed, isFalse);

    await press(tester, find.text(CapsuleCopy.writeLetter));
    await settleRoutes(tester);
    expect(find.text('Open when you miss me'), findsOneWidget);
    expect(buttonEnabled(tester, 'Seal with Wax Stamp 💌'), isFalse);
  });

  testWidgets('keeps the draft when the letter sheet is closed and opened again', (tester) async {
    calm(tester);
    final space = await real(tester, openReadySpace);
    await openTab(tester, space, 'Letters');
    await untilFound(tester, find.text(CapsuleCopy.emptyTitle));

    await press(tester, find.text(CapsuleCopy.writeLetter));
    await settleRoutes(tester);
    await typeInto(tester, fieldWithHint(CapsuleCopy.titleHint), 'Half written');
    await press(tester, find.byType(OurCloseButton));
    await settleRoutes(tester);
    expect(find.text(CapsuleCopy.modalTitle), findsNothing);

    await press(tester, find.text(CapsuleCopy.writeLetter));
    await settleRoutes(tester);
    expect(find.text('Half written'), findsOneWidget);
  });

  testWidgets('opens a letter by breaking the wax seal and remembers it was read', (tester) async {
    calm(tester);
    final space = await real(tester, openReadySpace);
    await real(tester, () => space.letters.writeLetter(title: 'Rainy day', content: 'Look up, I am thinking of you.'));
    await openTab(tester, space, 'Letters');
    await untilFound(tester, find.text('Rainy day'));
    expect(find.text(CapsuleCopy.readLetter), findsOneWidget);

    await press(tester, find.text('Rainy day'));
    await settleRoutes(tester);
    expect(find.byType(LetterEnvelope), findsOneWidget);
    expect(find.text('Tap to Break Wax Seal'), findsOneWidget);
    expect(find.text('A private letter written on ${prettyTimestamp(DateTime.now().millisecondsSinceEpoch)}'),
        findsOneWidget);
    expect(find.textContaining('Time lock lifted'), findsNothing);
    expect(find.text('Look up, I am thinking of you.'), findsNothing);
    expect(plainText(tester, find.text('Tap to Break Wax Seal')), isTrue);

    await press(tester, find.text('Tap to Break Wax Seal'));
    expect(find.text('SECRET LOVE LETTER'), findsOneWidget);
    expect(find.text('Look up, I am thinking of you.'), findsOneWidget);
    expect(find.text('With all my love forever 💕'), findsOneWidget);
    expect(find.textContaining('This one was sealed until'), findsNothing);
    expect(plainText(tester, find.text('Look up, I am thinking of you.')), isTrue);
    expect(recordedHaptics, contains(HapticKind.tap));

    await tester.pump(const Duration(milliseconds: 450));
    expect(recordedHaptics, contains(HapticKind.celebration));

    await untilFound(tester, find.textContaining('· already opened'));
    final stored = await real(tester, space.letters.list);
    expect(stored.single.isOpened, isTrue);
    expect(stored.single.openedAt, isNotNull);

    await press(tester, find.byType(OurCloseButton));
    await settleRoutes(tester);
    expect(find.byType(LetterEnvelope), findsNothing);
    expect(find.text('Rainy day'), findsOneWidget);
  });

  testWidgets('a time-locked letter stays shut and says when it opens', (tester) async {
    calm(tester);
    final space = await real(tester, openReadySpace);
    final unlockDate = inDays(40);
    await real(tester, () => space.letters.writeLetter(title: 'Anniversary', content: 'Happy year!', unlockDate: unlockDate));
    await openTab(tester, space, 'Letters');
    await untilFound(tester, find.text('Anniversary'));

    expect(find.textContaining('· sealed'), findsOneWidget);
    expect(find.text(CapsuleCopy.readLetter), findsNothing);
    expect(find.textContaining('h left'), findsOneWidget);
    final card = tester.widget<GlassCard>(find.ancestor(of: find.text('Anniversary'), matching: find.byType(GlassCard)));
    expect(card.opacity, 0.8);

    await press(tester, find.text('Anniversary'));
    expect(find.byType(LetterEnvelope), findsNothing);
    final notice = find.textContaining('"Anniversary" is sealed until ${formatDatePretty(unlockDate)} - ');
    expect(notice, findsOneWidget);
    expect(find.textContaining('We will not open it early.'), findsOneWidget);

    await tester.tap(find.descendant(of: find.byKey(const ValueKey('capsule-notice')), matching: find.byType(GestureDetector)));
    await tester.pump();
    expect(notice, findsNothing);

    await press(tester, find.text('Anniversary'));
    expect(notice, findsOneWidget);
    await tester.pump(const Duration(seconds: 8));
    expect(notice, findsNothing);
  });

  testWidgets('tucks away a letter that was saved with a date but not sealed yet', (tester) async {
    calm(tester);
    final space = await real(tester, openReadySpace);
    final now = DateTime.now().millisecondsSinceEpoch;
    await real(
      tester,
      () => space.letters.write({
        'id': 'let-pending',
        'title': 'From the web',
        'content': 'Wait for it',
        'unlockDate': inDays(10),
        'isOpened': false,
        'createdAt': now,
        'updatedAt': now,
        'deleted': false,
      }),
    );

    await openTab(tester, space, 'Letters');
    await untilFound(tester, find.textContaining('· sealed'));

    final plain = await real(tester, () => space.letters.readPlain('let-pending'));
    expect(plain!['content'], isNull);
    expect(plain['sealedContent'], isA<Map<String, Object?>>());
    expect(plain['title'], 'From the web');
  });

  testWidgets('a letter sealed for today opens and remembers its time lock', (tester) async {
    calm(tester);
    final space = await real(tester, openReadySpace);
    await openTab(tester, space, 'Letters');
    await untilFound(tester, find.text(CapsuleCopy.emptyTitle));

    await press(tester, find.text(CapsuleCopy.writeLetter));
    await settleRoutes(tester);
    await typeInto(tester, fieldWithHint(CapsuleCopy.titleHint), 'Today');
    await typeInto(tester, fieldWithHint(CapsuleCopy.bodyHint), 'Sealed and opened the same day.');
    expect(
      tester.getSize(find.byType(OurDateField)).width,
      tester.getSize(find.byWidgetPredicate((w) => w is OurTextField && w.hint == CapsuleCopy.titleHint)).width,
    );

    await press(tester, find.text('mm/dd/yyyy'));
    await settleRoutes(tester);
    await tester.tap(find.text('OK'));
    await settleRoutes(tester);
    final today = toLocalDateInput(DateTime.now());
    final sealLabel = CapsuleCopy.sealButton(saving: false, unlockDate: today);
    expect(find.text(sealLabel), findsOneWidget);

    await press(tester, find.bySemanticsLabel('Clear date'));
    expect(find.text('Seal with Wax Stamp 💌'), findsOneWidget);
    expect(find.text('mm/dd/yyyy'), findsOneWidget);

    await press(tester, find.text('mm/dd/yyyy'));
    await settleRoutes(tester);
    await tester.tap(find.text('OK'));
    await settleRoutes(tester);

    await press(tester, find.text(sealLabel));
    await untilFound(tester, find.text(CapsuleCopy.readLetter));
    await settleRoutes(tester);

    final stored = await real(tester, space.letters.list);
    expect(stored.single.isSealed, isTrue);
    expect(stored.single.content, isNull);
    expect(stored.single.lockDate, today);

    await press(tester, find.text('Today'));
    await tester.pump();
    await settleRoutes(tester);
    expect(find.text('Time lock lifted on ${formatDatePretty(today)}'), findsOneWidget);

    await press(tester, find.text('Tap to Break Wax Seal'));
    expect(find.text('Sealed and opened the same day.'), findsOneWidget);
    expect(find.textContaining('This one was sealed until ${formatDatePretty(today)} 💕'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 450));
    await untilFound(tester, find.textContaining('· already opened'));
  });

  testWidgets('deletes letters after asking, from the list and from an open letter', (tester) async {
    calm(tester);
    final space = await real(tester, openReadySpace);
    await real(tester, () => space.letters.writeLetter(title: 'First', content: 'One'));
    await real(tester, () => space.letters.writeLetter(title: 'Second', content: 'Two'));
    await openTab(tester, space, 'Letters');
    await untilFound(tester, find.text('Second'));
    expect(find.byType(GlassCard), findsNWidgets(2));

    final deleteSecond = find.descendant(
      of: find.ancestor(of: find.text('Second'), matching: find.byType(GlassCard)),
      matching: iconButton('Delete love letter'),
    );
    await press(tester, deleteSecond);
    await settleRoutes(tester);
    expect(find.text(CapsuleCopy.deleteQuestion("Alex's")), findsOneWidget);
    await press(tester, find.text('Cancel'));
    await settleRoutes(tester);
    expect(find.byType(GlassCard), findsNWidgets(2));

    await press(tester, deleteSecond);
    await settleRoutes(tester);
    await press(tester, find.text('OK'));
    await settleRoutes(tester);
    await untilGone(tester, find.text('Second'));
    expect(find.text('First'), findsOneWidget);

    await press(tester, find.text('First'));
    await settleRoutes(tester);
    await press(tester, find.text('Tap to Break Wax Seal'));
    await press(tester, find.text('Delete'));
    await settleRoutes(tester);
    expect(find.text(CapsuleCopy.deleteQuestion("Alex's")), findsOneWidget);
    await press(tester, find.text('OK'));
    await settleRoutes(tester);
    await untilFound(tester, find.text(CapsuleCopy.emptyTitle));
    await settleRoutes(tester);
    expect(find.byType(LetterEnvelope), findsNothing);
    expect(await real(tester, space.letters.list), isEmpty);
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

    await openTab(tester, space, 'Letters');
    await untilFound(tester, find.text('Ours'));
    expect(find.text(CapsuleCopy.hiddenLetters(1)), findsOneWidget);
    expect(find.text('Not ours'), findsNothing);
    expect(find.byType(GlassCard), findsOneWidget);
  });
}
