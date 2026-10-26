import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/presentation/screens/daily/daily_copy.dart';
import 'package:our_space_mobile/presentation/screens/daily/daily_question_card.dart';
import 'package:our_space_mobile/presentation/screens/daily/daily_question_model.dart';
import 'package:our_space_mobile/presentation/screens/sky/sky_map_detail.dart';
import 'package:our_space_mobile/presentation/screens/sky/sky_map_page.dart';
import 'package:our_space_mobile/presentation/screens/sky/sky_map_plan.dart';
import 'package:our_space_mobile/presentation/screens/sky/sky_night_sheet.dart';
import 'package:our_space_mobile/presentation/space_scope.dart';
import 'package:our_space_mobile/presentation/sky/sky.dart';

import '../../widgets/harness.dart' show recordHaptics;
import '../love/love_harness.dart';

const String _emojiPattern = r'[\p{Extended_Pictographic}\u{FE0F}]';
final RegExp _emoji = RegExp(_emojiPattern, unicode: true);
final RegExp _engineWords = RegExp(
  r'\b(sync\w*|devices?|pair\w*|servers?|upload\w*|download\w*|data|peers?|relays?|mailbox\w*|encrypt\w*|keys?)\b',
  caseSensitive: false,
);

final List<int> heartOrder = ConstellationShape.heart.order;

void expectWarmCopy(WidgetTester tester) {
  for (final element in find.byWidgetPredicate((widget) => widget is Text || widget is RichText).evaluate()) {
    final widget = element.widget;
    final text = widget is Text ? (widget.data ?? widget.textSpan?.toPlainText()) : (widget as RichText).text.toPlainText();
    if (text == null) continue;
    expect(_emoji.hasMatch(text), isFalse, reason: 'emoji in "$text"');
    expect(_engineWords.hasMatch(text), isFalse, reason: 'engine word in "$text"');
  }
}

class MapHost extends StatefulWidget {
  const MapHost({super.key, this.detail});

  final int? detail;

  @override
  State<MapHost> createState() => _MapHostState();
}

class _MapHostState extends State<MapHost> {
  late final DailyQuestionModel model = DailyQuestionModel(context.space);

  @override
  void dispose() {
    model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    model.bindTo(vault: context.watch<VaultService>(), identity: context.watch<IdentityController>());
    final detail = widget.detail;
    if (detail == null) return SkyMapPage(model: model);
    return SkyMapConstellationPage(model: model, index: detail);
  }
}

Widget dayHost({int? detail}) => Theme(data: SkyThemes.legacy(SkyTokens.day), child: MapHost(detail: detail));

SkyScene detailScene(WidgetTester tester) => tester.widget<SkyBackdrop>(find.byKey(SkyMapKeys.canvas)).scene;

Offset starOnScreen(WidgetTester tester, int slot) {
  final canvas = tester.getRect(find.byKey(SkyMapKeys.canvas));
  final scene = detailScene(tester);
  return canvas.topLeft + scene.constellation!.pointAt(slot) * scene.scaleFor(canvas.size);
}

List<SkyConstellation> windowFigures(WidgetTester tester, Finder card) => tester
    .widgetList<CustomPaint>(find.descendant(of: card, matching: find.byType(CustomPaint)))
    .map((paint) => paint.painter)
    .whereType<SkyLivePainter>()
    .map((painter) => painter.scene.constellation!)
    .toList();

SkyConstellation windowFigure(WidgetTester tester, Finder card) =>
    windowFigures(tester, card).where((figure) => figure.dim == 1).single;

SkyConstellation? windowGhost(WidgetTester tester, Finder card) {
  final ghosts = windowFigures(tester, card).where((figure) => figure.dim < 1).toList();
  return ghosts.isEmpty ? null : ghosts.single;
}

void main() {
  setUp(recordHaptics);

  group('the sky map', () {
    testWidgets('before the first star it shows where the heart will begin', (tester) async {
      calm(tester);
      final space = await coupleSpace(tester);
      await pumpNight(tester, space, shell: const MapHost());
      await untilFound(tester, find.byKey(SkyMapKeys.empty));

      expect(find.text(SkyMapCopy.title), findsOneWidget);
      expect(find.text('BEFORE THE FIRST STAR'), findsOneWidget);
      expect(find.text(SkyMapCopy.emptyTitle), findsOneWidget);
      expect(find.text(SkyMapCopy.emptyMessage(night: true)), findsOneWidget);
      expect(find.byKey(SkyMapKeys.growing), findsNothing);
      expect(find.byKey(SkyMapKeys.finished), findsNothing);
      expect(find.byKey(SkyMapKeys.everyDay), findsOneWidget);

      final window = find.descendant(of: find.byKey(SkyMapKeys.empty), matching: find.byType(SkyConstellationView));
      expect(tester.element(window.first).sky.isNight, isTrue);
      final figure = windowFigure(tester, find.byKey(SkyMapKeys.empty));
      expect(figure.shape, ConstellationShape.heart);
      expect(figure.gap, ConstellationShape.heart.me);
      expect(figure.litPoints, isEmpty);
      final ghost = windowGhost(tester, find.byKey(SkyMapKeys.empty))!;
      expect(ghost.complete, isTrue);
      expect(ghost.litPoints, hasLength(29));
      expect(ghost.dim, SkyMapPlan.ghostDim);
      expectWarmCopy(tester);

      await press(tester, find.byKey(SkyMapKeys.everyDay));
      await settleRoute(tester);
      await untilFound(tester, find.text('EVERY DAY SO FAR'));
      await press(tester, iconButton(DailyCopy.close));
      await settleRoute(tester);
      expect(find.byKey(DailyKeys.sheet), findsNothing);
      expect(find.byKey(SkyMapKeys.page), findsOneWidget);
      await settle(tester, space);
    });

    testWidgets('a growing heart leads, still growing, with a note on what comes next', (tester) async {
      calm(tester);
      final space = await coupleSpace(tester);
      await bothAnswered(tester, space, 12);
      await pumpNight(tester, space, shell: const MapHost());
      await untilFound(tester, find.byKey(SkyMapKeys.growing));

      expect(find.text('12 STARS SO FAR'), findsOneWidget);
      expect(find.text('Still growing · 12 of 29'), findsOneWidget);
      expect(find.text('The Heart'), findsOneWidget);
      expect(find.text('OUR FIRST CONSTELLATION'), findsOneWidget);
      expect(find.byKey(SkyMapKeys.keepNote), findsOneWidget);
      expect(find.byKey(SkyMapKeys.finished), findsNothing);
      expect(find.byKey(SkyMapKeys.empty), findsNothing);
      expect(tester.widget<SkyProgressBar>(find.byType(SkyProgressBar)).value, closeTo(12 / 29, 1e-9));

      final figure = windowFigure(tester, find.byKey(SkyMapKeys.growing));
      expect(figure.shape, ConstellationShape.heart);
      expect(figure.litPoints.toSet(), heartOrder.take(12).toSet());
      expect(figure.gap, heartOrder[12]);
      expect(figure.presence, isFalse);
      expect(windowGhost(tester, find.byKey(SkyMapKeys.growing))?.shape, ConstellationShape.heart);

      final growing = tester.getRect(find.byKey(SkyMapKeys.growing));
      final everyDay = tester.getRect(find.byKey(SkyMapKeys.everyDay));
      expect(growing.bottom, lessThanOrEqualTo(everyDay.top));
      final label = tester.widget<SkyPressable>(
        find.descendant(of: find.byKey(SkyMapKeys.growing), matching: find.byType(SkyPressable)).first,
      );
      expect(label.semanticLabel, startsWith('Our first constellation · The Heart, '));
      expect(label.semanticLabel, endsWith(', Still growing · 12 of 29'));
      expectWarmCopy(tester);
      await settle(tester, space);
    });

    testWidgets('by day the page wears the day sky while each constellation keeps its night window', (tester) async {
      calm(tester);
      final space = await coupleSpace(tester);
      await bothAnswered(tester, space, 3);
      await pumpLove(tester, space, shell: dayHost());
      await untilFound(tester, find.byKey(SkyMapKeys.growing));

      final page = tester.element(find.byKey(SkyMapKeys.page));
      expect(page.sky.isDay, isTrue);
      final title = tester.widget<Text>(find.text(SkyMapCopy.title));
      expect(title.style?.color, SkyTokens.day.title);
      final window = find.descendant(of: find.byKey(SkyMapKeys.growing), matching: find.byType(SkyConstellationView));
      expect(tester.element(window.first).sky.isNight, isTrue);
      final pill = tester.widget<Text>(find.text('Still growing · 3 of 29'));
      expect(pill.style?.color, SkyTokens.day.goldDeep);
      expectWarmCopy(tester);
      await settle(tester, space);
    });

    testWidgets('by day before the first star it speaks of today', (tester) async {
      calm(tester);
      final space = await coupleSpace(tester);
      await pumpLove(tester, space, shell: dayHost());
      await untilFound(tester, find.byKey(SkyMapKeys.empty));
      expect(find.text(SkyMapCopy.emptyMessage(night: false)), findsOneWidget);
      await settle(tester, space);
    });
  });

  group('one constellation, large on the full sky', () {
    testWidgets('every lit star opens its night, then every day so far', (tester) async {
      calm(tester);
      final space = await coupleSpace(tester);
      await bothAnswered(tester, space, 12);
      await pumpNight(tester, space, shell: const MapHost(detail: 0));
      await untilFound(tester, find.byKey(SkyMapKeys.night(12)));

      expect(find.text('The Heart'), findsOneWidget);
      expect(find.text('OUR FIRST CONSTELLATION'), findsOneWidget);
      expect(find.text('Still growing · 12 of 29'), findsOneWidget);
      expect(find.text(StarNightCopy.relive), findsOneWidget);
      expect(find.byKey(SkyMapKeys.night(1)), findsOneWidget);
      expect(find.byKey(SkyMapKeys.night(13)), findsNothing);
      expect(find.byKey(SkyMapKeys.myName), findsOneWidget);
      expect(find.byKey(SkyMapKeys.partnerName), findsOneWidget);

      final scene = detailScene(tester);
      final figure = scene.constellation!;
      expect(figure.shape, ConstellationShape.heart);
      expect(figure.litPoints, hasLength(12));
      expect(figure.scale, greaterThan(const SkyConstellation().scale));
      final ghost = tester.widget<SkyMapGhost>(find.byKey(SkyMapKeys.ghost)).constellation;
      expect(ghost.center, figure.center);
      expect(ghost.scale, figure.scale);
      expect(ghost.litPoints, hasLength(29));
      final canvas = tester.getRect(find.byKey(SkyMapKeys.canvas));
      final k = scene.scaleFor(canvas.size);
      final title = tester.getRect(find.text('The Heart'));
      final hint = tester.getRect(find.byKey(SkyMapKeys.status));
      for (final slot in figure.litPoints) {
        final at = canvas.topLeft + figure.pointAt(slot) * k;
        expect(at.dy, greaterThan(title.bottom), reason: '$slot');
        expect(at.dy, lessThan(hint.top), reason: '$slot');
        expect(at.dx, inInclusiveRange(canvas.left, canvas.right), reason: '$slot');
      }

      await tester.tapAt(starOnScreen(tester, heartOrder[0]) + const Offset(10, 8));
      await settleRoute(tester);
      expect(find.byKey(StarNightKeys.sheet), findsOneWidget);
      expect(find.text('Mine 12'), findsOneWidget);
      expect(find.text('Theirs 12'), findsOneWidget);

      await tester.tap(find.byKey(StarNightKeys.everyDay));
      await settleRoute(tester);
      await untilFound(tester, find.text('EVERY DAY SO FAR'));
      expect(find.byKey(StarNightKeys.sheet), findsNothing);
      await press(tester, iconButton(DailyCopy.close));
      await settleRoute(tester);

      await tester.tapAt(starOnScreen(tester, heartOrder[20]));
      await settleRoute(tester);
      expect(find.byKey(StarNightKeys.sheet), findsNothing);

      final last = tester.widget<Semantics>(find.byKey(SkyMapKeys.night(12)));
      last.properties.onTap!();
      await settleRoute(tester);
      expect(find.byKey(StarNightKeys.sheet), findsOneWidget);
      expect(find.text('Mine 1'), findsOneWidget);
      await press(tester, iconButton(DailyCopy.close));
      await settleRoute(tester);
      expectWarmCopy(tester);
      await settle(tester, space);
    });

    testWidgets('a finished constellation reads its nights and shines whole', (tester) async {
      calm(tester);
      final space = await coupleSpace(tester);
      await bothAnswered(tester, space, 30);
      await pumpNight(tester, space, shell: const MapHost(detail: 0));
      await untilFound(tester, find.byKey(SkyMapKeys.night(29)));
      expect(find.byKey(SkyMapKeys.night(30)), findsNothing);
      expect(find.text('29 nights'), findsOneWidget);
      final figure = detailScene(tester).constellation!;
      expect(figure.complete, isTrue);
      expect(figure.litPoints, hasLength(29));
      expect(find.byKey(SkyMapKeys.ghost), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Semantics && (widget.properties.label ?? '').startsWith('Our first constellation · The Heart. 29 nights'),
        ),
        findsOneWidget,
      );
      await settle(tester, space);
    });

    testWidgets('every star in each large view is big enough to find by touch with a screen reader', (tester) async {
      calm(tester);
      final handle = tester.ensureSemantics();
      final space = await coupleSpace(tester);
      const size = SkyConstellation.count;
      await bothAnswered(tester, space, ConstellationShape.values.length * size);
      for (var index = 0; index < ConstellationShape.values.length; index++) {
        final shape = ConstellationShape.at(index);
        await pumpNight(tester, space, shell: MapHost(detail: index));
        await untilFound(tester, find.byKey(SkyMapKeys.night((index + 1) * size)));
        expect(detailScene(tester).constellation!.shape, shape);
        for (var star = 0; star < size; star++) {
          final night = find.byKey(SkyMapKeys.night(index * size + star + 1));
          expect(tester.getSemantics(night).rect.size, const Size.square(SkyConstellation.hitRadius * 2));
          expect(tester.getCenter(night), offsetMoreOrLessEquals(starOnScreen(tester, shape.order[star]), epsilon: 0.01));
        }
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      }
      handle.dispose();
      await settle(tester, space);
    });

    testWidgets('a constellation waiting for its first star has nothing to tap yet', (tester) async {
      calm(tester);
      final space = await coupleSpace(tester);
      await pumpNight(tester, space, shell: const MapHost(detail: 0));
      await untilFound(tester, find.byKey(SkyMapKeys.status));
      expect(find.text(SkyMapCopy.waitingFirst), findsOneWidget);
      expect(find.text(StarNightCopy.relive), findsNothing);
      expect(find.byKey(SkyMapKeys.myName), findsNothing);
      expect(tester.widget<GestureDetector>(find.byKey(SkyMapKeys.starTouch)).onTapUp, isNull);
      await settle(tester, space);
    });

    testWidgets('by day the large view wears the day sky', (tester) async {
      calm(tester);
      final space = await coupleSpace(tester);
      await bothAnswered(tester, space, 2);
      await pumpLove(tester, space, shell: dayHost(detail: 0));
      await untilFound(tester, find.byKey(SkyMapKeys.night(2)));
      expect(tester.element(find.byKey(SkyMapKeys.canvas)).sky.isDay, isTrue);
      expect(detailScene(tester).sun, isTrue);
      expect(detailScene(tester).clouds, isNotEmpty);
      await settle(tester, space);
    });
  });
}
