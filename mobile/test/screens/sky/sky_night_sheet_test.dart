import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/core/engine/storage/local_settings.dart';
import 'package:our_space_mobile/presentation/screens/daily/daily_copy.dart';
import 'package:our_space_mobile/presentation/screens/sky/sky_constellations.dart';
import 'package:our_space_mobile/presentation/screens/sky/sky_night_sheet.dart';
import 'package:our_space_mobile/presentation/sky/sky.dart';

StarNight nightOf(int number, String day, {DailyQuestion? question, bool answers = true}) => StarNight(
  number: number,
  day: day,
  answers: answers
      ? AnsweredDay(
          day: day,
          question: question,
          mine: DailyAnswerEntry({'text': 'The way you laughed', 'answeredAt': 1}),
          theirs: DailyAnswerEntry({'text': 'Your voice before sleep', 'answeredAt': 2}),
        )
      : null,
);

Widget host(Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: SkyThemes.legacy(SkyTokens.night),
  home: SkyTheme(child: Material(child: child)),
);

void main() {
  group('a night has a warm title', () {
    test('the number of the night and the day it was', () {
      expect(StarNightCopy.title(nightOf(12, '2026-10-06')), 'Night 12 · Tuesday 6 October');
      expect(StarNightCopy.title(nightOf(1, '2026-01-01')), 'Night 1 · Thursday 1 January');
      expect(StarNightCopy.title(nightOf(3, 'someday')), 'Night 3');
      expect(StarNightCopy.constellation(nightOf(12, '2026-10-06')), 'Our first constellation · The Heart');
      expect(StarNightCopy.constellation(nightOf(30, '2026-10-06')), 'Our second constellation · The Moon');
      expect(StarNightCopy.relive, 'Tap a star to relive that night');
    });

    test('the tip to relive a night is remembered once seen', () async {
      final settings = LocalSettings.memory();
      expect(StarNightTip.seen(settings), isFalse);
      await StarNightTip.remember(settings);
      expect(StarNightTip.seen(settings), isTrue);
      expect(settings.getItem(StarNightTip.settingsKey), '1');
    });
  });

  group('the night sheet', () {
    testWidgets('shows that night, its question and both answers', (tester) async {
      final question = allQuestions.first;
      await tester.pumpWidget(
        host(
          StarNightSheet(night: nightOf(12, '2026-10-06', question: question), partnerName: 'alex', myName: 'Sam'),
        ),
      );
      expect(find.text('Night 12 · Tuesday 6 October'.toUpperCase()), findsOneWidget);
      expect(find.text(DailyCopy.quoted(question.text)), findsOneWidget);
      expect(find.text('Our first constellation · The Heart'), findsOneWidget);
      expect(find.text('The way you laughed'), findsOneWidget);
      expect(find.text('Your voice before sleep'), findsOneWidget);
      expect(find.text('You'), findsOneWidget);
      expect(find.text('Alex'), findsOneWidget);
      expect(find.byKey(StarNightKeys.everyDay), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a night whose question left the app still opens', (tester) async {
      await tester.pumpWidget(host(StarNightSheet(night: nightOf(4, '2026-10-06'), partnerName: 'Alex')));
      expect(find.text(DailyCopy.fromBackThen), findsOneWidget);
      await tester.pumpWidget(
        host(StarNightSheet(night: nightOf(4, '2026-10-06', answers: false), partnerName: 'Alex')),
      );
      expect(find.byKey(StarNightKeys.mine), findsNothing);
      expect(find.byKey(StarNightKeys.theirs), findsNothing);
    });

    testWidgets('opens as a sheet, closes, and leads to every day so far', (tester) async {
      final results = <StarNightResult?>[];
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () async =>
                    results.add(await showStarNightSheet(context, night: nightOf(2, '2026-10-06'), partnerName: 'Alex')),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byKey(StarNightKeys.sheet), findsOneWidget);
      await tester.tap(find.byWidgetPredicate((w) => w is SkyIconButton && w.semanticLabel == DailyCopy.close));
      await tester.pumpAndSettle();
      expect(find.byKey(StarNightKeys.sheet), findsNothing);
      expect(results, [null]);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(StarNightKeys.everyDay));
      await tester.pumpAndSettle();
      expect(find.byKey(StarNightKeys.sheet), findsNothing);
      expect(results, [null, StarNightResult.everyDay]);
    });
  });
}
