import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/presentation/screens/daily/daily_copy.dart';
import 'package:our_space_mobile/presentation/screens/daily/daily_question_card.dart';
import 'package:our_space_mobile/presentation/screens/daily/daily_question_model.dart';
import 'package:our_space_mobile/presentation/screens/daily/daily_reveal_page.dart';
import 'package:our_space_mobile/presentation/screens/love/love_sheet.dart';
import 'package:our_space_mobile/presentation/screens/sky/sky_days.dart';
import 'package:our_space_mobile/presentation/screens/sky/sky_heart_plan.dart';
import 'package:our_space_mobile/presentation/sky/sky.dart';
import 'package:our_space_mobile/presentation/widgets/our_widgets.dart';

import '../../widgets/harness.dart' show recordHaptics, recordedHaptics;
import 'love_harness.dart';

const String heading = "TONIGHT'S QUESTION";
const String light = "Light tonight's star";
const String placeholder = 'However much or little you want…';
const String missedLine = "You missed this one, and something of Alex's is waiting behind it. Tap to answer it now.";
const int dayMs = 86400000;

const PronounSet she = PronounSet(subject: 'she', object: 'her', possessive: 'her', independent: 'hers', has: 'has', isVerb: 'is');
const PronounSet they = PronounSet(
  subject: 'they',
  object: 'them',
  possessive: 'their',
  independent: 'theirs',
  has: 'have',
  isVerb: 'are',
);

Future<void> openSheet(WidgetTester tester) async {
  await press(tester, find.byKey(DailyKeys.action));
  await settleRoute(tester);
  expect(find.byKey(DailyKeys.sheet), findsOneWidget);
}

Future<void> closeSheet(WidgetTester tester) async {
  await press(tester, iconButton(DailyCopy.close));
  await settleRoute(tester);
  expect(find.byKey(DailyKeys.sheet), findsNothing);
}

DailyStatus statusOf(WidgetTester tester) => tester.widget<DailyStatusRow>(find.byType(DailyStatusRow)).status;

String actionLabel(WidgetTester tester) => tester.widget<SkyButton>(find.byKey(DailyKeys.action)).label;

Future<OurSpace> nightCouple(WidgetTester tester) async {
  return coupleSpace(tester);
}

class _StuckModel extends DailyQuestionModel {
  _StuckModel(super.space);

  int retries = 0;

  @override
  bool get failed => retries == 0;

  @override
  Future<void> retry() async {
    retries++;
    notifyListeners();
  }
}

void main() {
  setUp(recordHaptics);

  group('daily question copy', () {
    DailyStatus status({
      bool bothIn = false,
      bool answered = false,
      bool waiting = false,
      bool night = true,
      PronounSet grammar = she,
    }) => DailyCopy.status(
      bothIn: bothIn,
      answered: answered,
      partnerWaiting: waiting,
      night: night,
      partnerName: 'Alex',
      partnerPossessive: "Alex's",
      partnerGrammar: grammar,
    );

    test('the card line follows who has answered, without emoji', () {
      expect(status(), const DailyStatus('Your turn', 'it opens when you both answer'));
      expect(status(waiting: true), const DailyStatus('Alex answered', 'opens when you do'));
      expect(status(answered: true).sentence, "You answered · Alex's appears the moment she writes one");
      expect(status(answered: true, grammar: they).rest, "Alex's appears the moment they write one");
      expect(status(answered: true, bothIn: true), const DailyStatus('You both answered', "tonight's star is lit"));
      expect(status(answered: true, bothIn: true, night: false).rest, "today's star is lit");
      expect(
        DailyCopy.status(
          bothIn: false,
          answered: false,
          partnerWaiting: true,
          night: true,
          partnerName: 'your partner',
          partnerPossessive: "your partner's",
          partnerGrammar: they,
        ).strong,
        'Your partner answered',
      );
    });

    test('night and day words, the reveal kicker and no emoji anywhere', () {
      expect(DailyCopy.questionLabel(true), "Tonight's question");
      expect(DailyCopy.questionLabel(false), "Today's question");
      expect(DailyCopy.lightStar(false), "Light today's star");
      expect(DailyCopy.starIsLit(true), "Tonight's star is lit");
      expect(DailyCopy.revealKicker(night: true, dayNumber: 28, stars: 29), 'Night 28 · Star 29');
      expect(DailyCopy.revealKicker(night: false, dayNumber: 28, stars: 29), 'Day 28 · Star 29');
      expect(DailyCopy.revealKicker(night: true, stars: 3), 'Tonight · Star 3');
      expect(DailyCopy.quoted('Why?'), '“Why?”');
      final emoji = RegExp(r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]', unicode: true);
      for (final line in [
        DailyCopy.answer,
        DailyCopy.missed("Alex's"),
        DailyCopy.partnerWaitingHint('Alex'),
        DailyCopy.catchUpHint('Alex'),
        status().sentence,
        status(waiting: true).sentence,
        status(bothIn: true, answered: true).sentence,
      ]) {
        expect(emoji.hasMatch(line), isFalse, reason: line);
      }
    });

    test('days read like the browser shows them', () {
      expect(prettyDay('2026-10-12', locale: 'en_US'), 'October 12');
      expect(prettyDay('2026-03-01', locale: 'en_GB'), '1 March');
      expect(prettyDay('2026-03-01', locale: 'en_IN'), '1 March');
      expect(prettyDay('not a day', locale: 'en_US'), 'not a day');
    });

    test('answer times read as just now, a time today, or the day', () {
      final now = DateTime(2026, 10, 22, 22, 30).millisecondsSinceEpoch;
      expect(DailyCopy.answeredAt(now - 20000, now: now, locale: 'en_US'), 'just now');
      expect(
        DailyCopy.answeredAt(
          DateTime(2026, 10, 22, 22, 14).millisecondsSinceEpoch,
          now: now,
          locale: 'en_US',
        ).replaceAll(' ', ' '),
        '10:14 PM',
      );
      expect(
        DailyCopy.answeredAt(DateTime(2026, 10, 20, 9).millisecondsSinceEpoch, now: now, locale: 'en_US'),
        'October 20',
      );
      expect(DailyCopy.answeredAt(0, now: now), '');
    });
  });

  test('a save the engine refuses shows the gentle message and keeps the draft', () async {
    final space = await openLoveSpace();
    await space.vault.create(passphrase: passphrase, iterations: fastIterations);
    final model = DailyQuestionModel(space);
    model.bind(key: space.vault.key, ownerId: '', ownerIds: const {});
    await pumpEventQueue();
    await model.refresh();
    expect(model.visible, isTrue);
    expect(model.answered, isFalse);
    expect(model.stars, 0);
    expect(model.failed, isFalse);

    model.draft.text = 'This will not stick';
    var celebrated = false;
    final saved = await model.save(onSaved: () => celebrated = true);

    expect(saved, isFalse);
    expect(model.error, 'That did not save. Try again in a moment.');
    expect(model.saving, isFalse);
    expect(model.draft.text, 'This will not stick');
    expect(celebrated, isFalse);
    model.dispose();
    await space.close();
  });

  testWidgets('the model counts the days you both answered as stars', (tester) async {
    calm(tester);
    final space = await coupleSpace(tester);
    final now = DateTime.now().millisecondsSinceEpoch;
    await bothAnswered(tester, space, 3);
    await partnerAnswers(tester, space, 'Only mine that day', when: now - 6 * dayMs);
    await iAnswer(tester, space, 'Only yours that day', when: now - 7 * dayMs);

    final model = DailyQuestionModel(space);
    model.bind(key: space.vault.key, ownerId: space.identity.myOwnerId!, ownerIds: space.identity.myOwnerIds);
    await drive(tester, model.refresh);
    expect(model.stars, 3);
    expect(model.bothIn, isFalse);

    await iAnswer(tester, space, 'Today, me');
    await partnerAnswers(tester, space, 'Today, her');
    await drive(tester, model.refresh);
    expect(model.stars, 4);
    expect(model.bothIn, isTrue);
    model.dispose();
    await drive(tester, space.close);
  });

  testWidgets('a question that does not open says so gently and tries again', (tester) async {
    calm(tester);
    final space = await real(tester, openLoveSpace);
    final model = _StuckModel(space);
    await tester.pumpWidget(
      MaterialApp(
        theme: SkyThemes.legacy(SkyTokens.night),
        home: ChangeNotifierProvider<IdentityController>.value(
          value: space.identity,
          child: Scaffold(
            body: DailyQuestionCard(model: model, onAnswer: () {}, onReveal: () {}),
          ),
        ),
      ),
    );
    expect(find.text(DailyCopy.loadFailed), findsOneWidget);
    await tester.tap(find.text(DailyCopy.tryAgain));
    await tester.pump();
    expect(model.retries, 1);
    expect(find.text(DailyCopy.loadFailed), findsNothing);
    expect(find.byKey(DailyKeys.card), findsNothing);
    await tester.pumpWidget(const SizedBox());
    model.dispose();
    await real(tester, space.close);
  });

  testWidgets('answers stay hidden until both have written, then tonight\'s star lights', (tester) async {
    calm(tester);
    final space = await nightCouple(tester);
    final key = space.vault.requireKey();
    final today = space.dailyQuestion.questionForDay(key);
    final question = DailyCopy.quoted(today.question.text);

    await pumpNight(tester, space);
    await untilFound(tester, find.text(heading));
    expect(find.text(question), findsOneWidget);
    expect(statusOf(tester).strong, 'Your turn');
    expect(actionLabel(tester), light);

    await partnerAnswers(tester, space, 'Your laugh on the phone last night');
    await until(tester, () => statusOf(tester).strong == 'Alex answered');
    expect(statusOf(tester).rest, 'opens when you do');
    expect(find.text('Your laugh on the phone last night'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(DailyStatusRow),
        matching: find.byWidgetPredicate((w) => w is SkyIcon && w.icon == SkyIcons.sealedStar),
      ),
      findsOneWidget,
    );

    recordedHaptics.clear();
    await openSheet(tester);
    expect(recordedHaptics, contains(HapticKind.tick));
    expect(find.text(prettyDay(today.day).toUpperCase()), findsOneWidget);
    expect(find.text(question), findsNWidgets(2));
    expect(
      find.text('Alex has answered already. Write yours and you will both be able to read them.'),
      findsOneWidget,
    );
    expect(find.text("You will not see Alex's until you have written yours."), findsOneWidget);
    expect(find.text('Your laugh on the phone last night'), findsNothing);
    expect(buttonEnabled(tester, DailyCopy.answer), isFalse);

    await type(tester, fieldWithHint(placeholder), '   ');
    expect(buttonEnabled(tester, DailyCopy.answer), isFalse);
    await type(tester, fieldWithHint(placeholder), 'The way you say goodnight');
    expect(buttonEnabled(tester, DailyCopy.answer), isTrue);

    recordedHaptics.clear();
    await press(tester, find.byKey(DailyKeys.submit));
    await untilFound(tester, find.byKey(DailyKeys.reveal));
    await settleRoute(tester);

    expect(find.byKey(DailyKeys.sheet), findsNothing);
    expect(recordedHaptics, contains(HapticKind.celebration));
    expect(find.text("Tonight's star is lit"), findsOneWidget);
    expect(find.text('YOU BOTH ANSWERED'), findsOneWidget);
    expect(find.text('The way you say goodnight'), findsOneWidget);
    expect(find.text('Your laugh on the phone last night'), findsOneWidget);
    expect(find.text('Alex'), findsWidgets);
    expect(find.text('You'), findsOneWidget);
    final dayNumber = SkyDays.dayNumber(SkyDays.startOf(startDate)!, DateTime.now());
    expect(find.text('NIGHT $dayNumber · STAR 1'), findsOneWidget);
    final reveal = tester.widget<SkyBackdrop>(
      find.descendant(of: find.byType(DailyRevealPage), matching: find.byType(SkyBackdrop)),
    );
    expect(reveal.scene.heart?.burst, isTrue);
    expect(reveal.scene.heart?.complete, isTrue);
    expect(reveal.scene.heart?.gap, SkyHeartPlan.order.first);

    final day = await drive(
      tester,
      () => space.dailyQuestion.readDay(key, ownerId: space.identity.myOwnerId, ownerIds: space.identity.myOwnerIds),
    );
    expect(day.mine?.text, 'The way you say goodnight');
    expect(day.mine?.questionId, today.question.id);
    expect(day.partnerAnswer?.text, 'Your laugh on the phone last night');

    await tester.tap(semanticsLabelled('Back'));
    await settleRoute(tester);
    expect(find.byKey(DailyKeys.reveal), findsNothing);
    expect(statusOf(tester), const DailyStatus('You both answered', "tonight's star is lit"));
    expect(actionLabel(tester), DailyCopy.readBoth);
    expect(
      find.descendant(
        of: find.byType(DailyStatusRow),
        matching: find.byWidgetPredicate((w) => w is SkyIcon && w.icon == SkyIcons.check),
      ),
      findsOneWidget,
    );

    await press(tester, find.byKey(DailyKeys.action));
    await settleRoute(tester);
    expect(find.byKey(DailyKeys.reveal), findsOneWidget);
    expect(find.byKey(DailyKeys.sheet), findsNothing);
    await tester.tap(semanticsLabelled('Back'));
    await settleRoute(tester);
    await settle(tester, space);
  });

  testWidgets('answering first waits for the partner, and her answer appears on its own', (tester) async {
    calm(tester);
    final space = await nightCouple(tester);

    await pumpNight(tester, space);
    await untilFound(tester, find.text(heading));
    await openSheet(tester);

    await type(tester, fieldWithHint(placeholder), 'Our first video call');
    recordedHaptics.clear();
    await press(tester, find.byKey(DailyKeys.submit));
    await untilFound(tester, find.text('Nothing from Alex yet today. It will appear here on its own.'));
    expect(recordedHaptics, contains(HapticKind.celebration));
    expect(find.text('Our first video call'), findsOneWidget);
    expect(find.byKey(DailyKeys.reveal), findsNothing);
    expect(statusOf(tester).sentence, "You answered · Alex's appears the moment she writes one");
    expect(find.text(DailyCopy.seeStar(true)), findsNothing);

    await partnerAnswers(tester, space, 'When you sent me that song');
    await untilFound(tester, find.text('When you sent me that song'));
    expect(find.text('Nothing from Alex yet today. It will appear here on its own.'), findsNothing);
    expect(statusOf(tester).strong, 'You both answered');

    await press(tester, find.text(DailyCopy.seeStar(true)));
    await settleRoute(tester);
    expect(find.byKey(DailyKeys.sheet), findsNothing);
    expect(find.byKey(DailyKeys.reveal), findsOneWidget);
    await tester.tap(semanticsLabelled('Back'));
    await settleRoute(tester);
    await settle(tester, space);
  });

  testWidgets('the archive opens a missed day once she answers it, in that month', (tester) async {
    calm(tester);
    final space = await nightCouple(tester);
    final key = space.vault.requireKey();
    final now = DateTime.now().millisecondsSinceEpoch;
    final missedWhen = now - 40 * dayMs;
    final missed = space.dailyQuestion.questionForDay(key, missedWhen);
    final olderWhen = now - 45 * dayMs;

    await partnerAnswers(tester, space, 'The rain on our first walk', when: missedWhen);
    await partnerAnswers(tester, space, 'Something long gone', when: olderWhen, questionId: 'retired-question');

    await pumpNight(tester, space);
    await untilFound(tester, find.text(heading));
    await openSheet(tester);

    recordedHaptics.clear();
    await press(tester, find.text(DailyCopy.everyDay));
    await untilFound(tester, find.text('EVERY DAY SO FAR'));
    expect(recordedHaptics, contains(HapticKind.tick));
    expect(find.text(prettyDay(missed.day)), findsOneWidget);
    expect(find.text(missed.question.text), findsOneWidget);
    expect(find.text(missedLine), findsOneWidget);
    expect(find.textContaining('The rain on our first walk'), findsNothing);
    expect(find.text('A question from back then'), findsOneWidget);
    expect(find.text(DailyCopy.missedGone), findsOneWidget);

    await press(tester, find.text(DailyCopy.missedGone));
    expect(find.text('EVERY DAY SO FAR'), findsOneWidget);

    await press(tester, find.text(missedLine));
    expect(find.text(prettyDay(missed.day).toUpperCase()), findsOneWidget);
    expect(find.text(DailyCopy.quoted(missed.question.text)), findsOneWidget);
    expect(
      find.text('You did not answer this one at the time. Write it now and what Alex wrote that day opens.'),
      findsOneWidget,
    );

    await press(tester, find.text(DailyCopy.backToArchive));
    expect(find.text('EVERY DAY SO FAR'), findsOneWidget);

    await press(tester, find.text(missedLine));
    await type(tester, fieldWithHint(placeholder), 'Holding your hand in the rain');
    recordedHaptics.clear();
    await press(tester, find.byKey(DailyKeys.submit));
    await untilFound(tester, find.textContaining('The rain on our first walk'));

    expect(find.text('EVERY DAY SO FAR'), findsOneWidget);
    expect(find.text('You: Holding your hand in the rain'), findsOneWidget);
    expect(find.text('Alex: The rain on our first walk'), findsOneWidget);
    expect(recordedHaptics, contains(HapticKind.celebration));
    expect(find.byKey(DailyKeys.reveal), findsNothing);

    final rows = await drive(tester, () => space.store.listDecrypted(dailyAnswersTable, key));
    final myId = space.identity.myOwnerId!;
    final mine = rows.where((row) => row['ownerId'] == myId).toList();
    expect(mine, hasLength(1));
    expect(mine.single['month'], monthKey(missed.day));
    expect(mine.single['id'], 'ans-${monthKey(missed.day)}-$myId');
    final answers = mine.single['answers'] as Map;
    expect((answers[missed.day] as Map)['text'], 'Holding your hand in the rain');
    expect((answers[missed.day] as Map)['questionId'], missed.question.id);

    await press(tester, find.text(DailyCopy.backToToday));
    expect(find.text('EVERY DAY SO FAR'), findsNothing);
    expect(find.text(DailyCopy.everyDay), findsOneWidget);
    expect(fieldWithHint(placeholder), findsOneWidget);
    await settle(tester, space);
  });

  testWidgets('an empty archive says so, and reopening starts back on today', (tester) async {
    calm(tester);
    final space = await nightCouple(tester);

    await pumpNight(tester, space);
    await untilFound(tester, find.text(heading));
    await openSheet(tester);
    await press(tester, find.text(DailyCopy.everyDay));
    await untilFound(tester, find.text("Nothing here yet. Answer today's and it starts filling itself."));

    await closeSheet(tester);
    await openSheet(tester);
    expect(find.text('EVERY DAY SO FAR'), findsNothing);
    expect(fieldWithHint(placeholder), findsOneWidget);
    await settle(tester, space);
  });

  testWidgets('a draft survives closing the sheet', (tester) async {
    calm(tester);
    final space = await nightCouple(tester);

    await pumpNight(tester, space);
    await untilFound(tester, find.text(heading));
    await openSheet(tester);
    await type(tester, fieldWithHint(placeholder), 'Half a thought');
    await closeSheet(tester);
    await openSheet(tester);

    final field = tester.widget<TextField>(fieldWithHint(placeholder));
    expect(field.controller?.text, 'Half a thought');
    await settle(tester, space);
  });

  testWidgets('the reveal opens every day so far and sends love back', (tester) async {
    calm(tester);
    final space = await nightCouple(tester);
    await bothAnswered(tester, space, 2);
    await iAnswer(tester, space, 'Your voice at midnight');
    await partnerAnswers(tester, space, 'The song you hummed');

    await pumpNight(tester, space);
    await untilFound(tester, find.text(heading));
    expect(actionLabel(tester), DailyCopy.readBoth);
    await press(tester, find.byKey(DailyKeys.action));
    await settleRoute(tester);
    expect(find.byKey(DailyKeys.reveal), findsOneWidget);
    expect(find.textContaining('· STAR 3'), findsOneWidget);
    final reveal = tester.widget<SkyBackdrop>(
      find.descendant(of: find.byType(DailyRevealPage), matching: find.byType(SkyBackdrop)),
    );
    expect(reveal.scene.heart?.gap, SkyHeartPlan.order[2]);
    expect(reveal.scene.heart?.unlit, hasLength(26));

    await press(tester, find.byKey(DailyKeys.everyDay));
    await settleRoute(tester);
    await untilFound(tester, find.text('EVERY DAY SO FAR'));
    expect(find.text('You: Your voice at midnight'), findsOneWidget);
    expect(find.text('Alex: The song you hummed'), findsOneWidget);
    expect(find.text('You: Mine 1'), findsOneWidget);
    await closeSheet(tester);
    expect(find.byKey(DailyKeys.reveal), findsOneWidget);

    await press(tester, find.byKey(DailyKeys.sendLove));
    await settleRoute(tester);
    expect(find.text(LoveSheetCopy.title), findsOneWidget);
    await tester.tapAt(const Offset(20, 60));
    await settleRoute(tester);
    expect(find.text(LoveSheetCopy.title), findsNothing);
    expect(find.byKey(DailyKeys.reveal), findsOneWidget);

    await tester.tap(semanticsLabelled('Back'));
    await settleRoute(tester);
    expect(find.byKey(DailyKeys.reveal), findsNothing);
    await settle(tester, space);
  });

  testWidgets('locking closes the reveal and the sheet', (tester) async {
    calm(tester);
    final space = await nightCouple(tester);
    await iAnswer(tester, space, 'Before the lock');
    await partnerAnswers(tester, space, 'Also before the lock');

    await pumpNight(tester, space);
    await untilFound(tester, find.text(heading));
    await press(tester, find.byKey(DailyKeys.action));
    await settleRoute(tester);
    await press(tester, find.byKey(DailyKeys.everyDay));
    await settleRoute(tester);
    expect(find.byKey(DailyKeys.sheet), findsOneWidget);

    space.vault.lock();
    await tester.pump();
    await settleRoute(tester);
    await settleRoute(tester);
    expect(find.byKey(DailyKeys.sheet), findsNothing);
    expect(find.byKey(DailyKeys.reveal), findsNothing);
    expect(find.text('Before the lock'), findsNothing);
  });
}
