import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/presentation/screens/daily/daily_copy.dart';
import 'package:our_space_mobile/presentation/screens/daily/daily_question_card.dart';
import 'package:our_space_mobile/presentation/screens/daily/daily_question_model.dart';
import 'package:our_space_mobile/presentation/widgets/our_widgets.dart';

import '../../widgets/harness.dart' show recordHaptics, recordedHaptics;
import 'love_harness.dart';

const String heading = "TODAY'S QUESTION";
const String placeholder = 'However much or little you want…';
const int dayMs = 86400000;

Future<void> openSheet(WidgetTester tester) async {
  await press(tester, find.text(heading));
  await settleRoute(tester);
  expect(find.byType(OurModalCard), findsOneWidget);
}

Future<void> closeSheet(WidgetTester tester) async {
  await press(tester, find.byType(OurCloseButton));
  await settleRoute(tester);
  expect(find.byType(OurModalCard), findsNothing);
}

Finder statusLine(String text) =>
    find.descendant(of: find.byType(DailyQuestionTeaser), matching: find.text(text));

void main() {
  setUp(recordHaptics);

  group('daily question copy', () {
    test('the card line follows who has answered, like the web', () {
      const she = PronounSet(subject: 'she', object: 'her', possessive: 'her', independent: 'hers', has: 'has', isVerb: 'is');
      const they = PronounSet(
        subject: 'they',
        object: 'them',
        possessive: 'their',
        independent: 'theirs',
        has: 'have',
        isVerb: 'are',
      );
      String status({bool bothIn = false, bool answered = false, bool waiting = false, PronounSet grammar = she}) =>
          DailyCopy.status(
            bothIn: bothIn,
            answered: answered,
            partnerWaiting: waiting,
            partnerName: 'Alex',
            partnerPossessive: "Alex's",
            partnerGrammar: grammar,
          );

      expect(status(), 'Tap to answer');
      expect(status(waiting: true), 'Alex has already answered. Yours unlocks it 💕');
      expect(status(answered: true), "Answered. Alex's appears the moment she writes one.");
      expect(status(answered: true, grammar: they), "Answered. Alex's appears the moment they write one.");
      expect(status(answered: true, bothIn: true), 'You both answered. Tap to read 💕');
    });

    test('days read like the browser shows them', () {
      expect(prettyDay('2026-10-12', locale: 'en_US'), 'October 12');
      expect(prettyDay('2026-03-01', locale: 'en_GB'), '1 March');
      expect(prettyDay('2026-03-01', locale: 'en_IN'), '1 March');
      expect(prettyDay('not a day', locale: 'en_US'), 'not a day');
    });
  });

  test('a save the engine refuses shows the gentle web message and keeps the draft', () async {
    final space = await openLoveSpace();
    await space.vault.create(passphrase: passphrase, iterations: fastIterations);
    final model = DailyQuestionModel(space);
    model.bind(key: space.vault.key, ownerId: '', ownerIds: const {});
    await pumpEventQueue();
    await model.refresh();
    expect(model.visible, isTrue);
    expect(model.answered, isFalse);

    model.draft.text = 'This will not stick';
    var celebrated = false;
    await model.save(onSaved: () => celebrated = true);

    expect(model.error, 'That did not save. Try again in a moment.');
    expect(model.saving, isFalse);
    expect(model.draft.text, 'This will not stick');
    expect(celebrated, isFalse);
    model.dispose();
    await space.close();
  });

  testWidgets('answers stay hidden until both have written, then open together', (tester) async {
    calm(tester);
    final space = await coupleSpace(tester);
    final key = space.vault.requireKey();
    final today = space.dailyQuestion.questionForDay(key);

    await pumpLove(tester, space);
    await untilFound(tester, find.text(heading));
    expect(find.text(today.question.text), findsOneWidget);
    expect(statusLine('Tap to answer'), findsOneWidget);

    await partnerAnswers(tester, space, 'Your laugh on the phone last night');
    await untilFound(tester, statusLine('Alex has already answered. Yours unlocks it 💕'));
    expect(find.text('Your laugh on the phone last night'), findsNothing);

    await openSheet(tester);
    expect(recordedHaptics, contains(HapticKind.tap));
    expect(find.text(prettyDay(today.day).toUpperCase()), findsOneWidget);
    expect(find.text(today.question.text), findsNWidgets(2));
    expect(
      find.text('Alex has answered already. Write yours and you will both be able to read them.'),
      findsOneWidget,
    );
    expect(find.text("You will not see Alex's until you have written yours."), findsOneWidget);
    expect(find.text('Your laugh on the phone last night'), findsNothing);
    expect(buttonEnabled(tester, 'Answer 💕'), isFalse);

    await type(tester, fieldWithHint(placeholder), '   ');
    expect(buttonEnabled(tester, 'Answer 💕'), isFalse);
    await type(tester, fieldWithHint(placeholder), 'The way you say goodnight');
    expect(buttonEnabled(tester, 'Answer 💕'), isTrue);

    recordedHaptics.clear();
    await press(tester, find.text('Answer 💕'));
    await untilFound(tester, find.text('YOU'));

    expect(find.text('The way you say goodnight'), findsOneWidget);
    expect(find.text('ALEX'), findsOneWidget);
    expect(find.text('Your laugh on the phone last night'), findsOneWidget);
    expect(fieldWithHint(placeholder), findsNothing);
    expect(recordedHaptics, contains(HapticKind.celebration));
    expect(statusLine('You both answered. Tap to read 💕'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(DailyQuestionTeaser),
        matching: find.byWidgetPredicate((w) => w is LucideIcon && w.icon == AppIcons.check),
      ),
      findsOneWidget,
    );

    final day = await drive(
      tester,
      () => space.dailyQuestion.readDay(
        key,
        ownerId: space.identity.myOwnerId,
        ownerIds: space.identity.myOwnerIds,
      ),
    );
    expect(day.mine?.text, 'The way you say goodnight');
    expect(day.mine?.questionId, today.question.id);
    expect(day.partnerAnswer?.text, 'Your laugh on the phone last night');

    await closeSheet(tester);
    await settle(tester, space);
  });

  testWidgets('answering first waits for the partner and her answer appears on its own', (tester) async {
    calm(tester);
    final space = await coupleSpace(tester);

    await pumpLove(tester, space);
    await untilFound(tester, find.text(heading));
    await openSheet(tester);

    await type(tester, fieldWithHint(placeholder), 'Our first video call');
    await press(tester, find.text('Answer 💕'));
    await untilFound(tester, find.text('Nothing from Alex yet today. It will appear here on its own.'));
    expect(statusLine("Answered. Alex's appears the moment she writes one."), findsOneWidget);

    await partnerAnswers(tester, space, 'When you sent me that song');
    await untilFound(tester, find.text('When you sent me that song'));
    expect(find.text('Nothing from Alex yet today. It will appear here on its own.'), findsNothing);
    expect(statusLine('You both answered. Tap to read 💕'), findsOneWidget);
    await settle(tester, space);
  });

  testWidgets('the archive opens a missed day once she answers it, in that month', (tester) async {
    calm(tester);
    final space = await coupleSpace(tester);
    final key = space.vault.requireKey();
    final now = DateTime.now().millisecondsSinceEpoch;
    final missedWhen = now - 40 * dayMs;
    final missed = space.dailyQuestion.questionForDay(key, missedWhen);
    final olderWhen = now - 45 * dayMs;

    await partnerAnswers(tester, space, 'The rain on our first walk', when: missedWhen);
    await partnerAnswers(tester, space, 'Something long gone', when: olderWhen, questionId: 'retired-question');

    await pumpLove(tester, space);
    await untilFound(tester, find.text(heading));
    await openSheet(tester);

    recordedHaptics.clear();
    await press(tester, find.text('Everything you have both written'));
    await untilFound(tester, find.text('EVERY DAY SO FAR'));
    expect(recordedHaptics, contains(HapticKind.tap));
    expect(find.text(prettyDay(missed.day)), findsOneWidget);
    expect(find.text(missed.question.text), findsOneWidget);
    expect(
      find.text("You missed this one, and something of Alex's is waiting behind it. Tap to answer it now 💕"),
      findsOneWidget,
    );
    expect(find.textContaining('The rain on our first walk'), findsNothing);
    expect(find.text('A question from back then'), findsOneWidget);
    expect(
      find.text('You missed this one. The question it was asking is no longer in the app.'),
      findsOneWidget,
    );

    await press(tester, find.text('You missed this one. The question it was asking is no longer in the app.'));
    expect(find.text('EVERY DAY SO FAR'), findsOneWidget);

    await press(
      tester,
      find.text("You missed this one, and something of Alex's is waiting behind it. Tap to answer it now 💕"),
    );
    expect(find.text(prettyDay(missed.day).toUpperCase()), findsOneWidget);
    expect(find.text(missed.question.text), findsOneWidget);
    expect(
      find.text('You did not answer this one at the time. Write it now and what Alex wrote that day opens.'),
      findsOneWidget,
    );

    await press(tester, find.text('Back to the archive'));
    expect(find.text('EVERY DAY SO FAR'), findsOneWidget);

    await press(
      tester,
      find.text("You missed this one, and something of Alex's is waiting behind it. Tap to answer it now 💕"),
    );
    await type(tester, fieldWithHint(placeholder), 'Holding your hand in the rain');
    await press(tester, find.text('Answer 💕'));
    await untilFound(tester, find.textContaining('The rain on our first walk'));

    expect(find.text('EVERY DAY SO FAR'), findsOneWidget);
    expect(find.text('You: Holding your hand in the rain'), findsOneWidget);
    expect(find.text('Alex: The rain on our first walk'), findsOneWidget);
    expect(recordedHaptics, contains(HapticKind.celebration));

    final rows = await drive(tester, () => space.store.listDecrypted(dailyAnswersTable, key));
    final myId = space.identity.myOwnerId!;
    final mine = rows.where((row) => row['ownerId'] == myId).toList();
    expect(mine, hasLength(1));
    expect(mine.single['month'], monthKey(missed.day));
    expect(mine.single['id'], 'ans-${monthKey(missed.day)}-$myId');
    final answers = mine.single['answers'] as Map;
    expect((answers[missed.day] as Map)['text'], 'Holding your hand in the rain');
    expect((answers[missed.day] as Map)['questionId'], missed.question.id);

    await press(tester, find.text('Back to today'));
    expect(find.text('EVERY DAY SO FAR'), findsNothing);
    expect(find.text('Everything you have both written'), findsOneWidget);
    await settle(tester, space);
  });

  testWidgets('an empty archive says so, and reopening starts back on today', (tester) async {
    calm(tester);
    final space = await coupleSpace(tester);

    await pumpLove(tester, space);
    await untilFound(tester, find.text(heading));
    await openSheet(tester);
    await press(tester, find.text('Everything you have both written'));
    await untilFound(tester, find.text("Nothing here yet. Answer today's and it starts filling itself."));

    await closeSheet(tester);
    await openSheet(tester);
    expect(find.text('EVERY DAY SO FAR'), findsNothing);
    expect(fieldWithHint(placeholder), findsOneWidget);
    await settle(tester, space);
  });

  testWidgets('a draft survives closing the sheet, like the web keeps it', (tester) async {
    calm(tester);
    final space = await coupleSpace(tester);

    await pumpLove(tester, space);
    await untilFound(tester, find.text(heading));
    await openSheet(tester);
    await type(tester, fieldWithHint(placeholder), 'Half a thought');
    await closeSheet(tester);
    await openSheet(tester);

    final field = tester.widget<TextField>(fieldWithHint(placeholder));
    expect(field.controller?.text, 'Half a thought');
    await settle(tester, space);
  });
}
