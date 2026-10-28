import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/presentation/home_shell.dart';
import 'package:our_space_mobile/presentation/screens/daily/daily_question_card.dart';
import 'package:our_space_mobile/presentation/screens/sky/sky_page.dart';
import 'package:our_space_mobile/presentation/screens/sky/together/sky_patch_page.dart';
import 'package:our_space_mobile/presentation/screens/sky/together/sky_patch_session.dart';
import 'package:our_space_mobile/presentation/screens/sky/together/sky_together_copy.dart';
import 'package:our_space_mobile/presentation/screens/sky/together/sky_together_home.dart';
import 'package:our_space_mobile/presentation/screens/sky/together/sky_together_layer.dart';
import 'package:our_space_mobile/presentation/screens/sky/together/sky_together_scope.dart';
import 'package:our_space_mobile/presentation/sky/sky.dart';
import 'package:our_space_mobile/presentation/widgets/app_haptics.dart';

import '../../../support/fake_sky_together.dart';
import '../../../widgets/harness.dart' show recordHaptics, recordedHaptics, usePhoneSize;
import '../../love/love_harness.dart';

const Duration beat = Duration(milliseconds: 100);

class Phones {
  Phones(this.space, this.pair)
    : b = SkyTogetherHome(link: pair.b, nameEvery: Duration.zero, haptic: _noHaptic) {
    b.onOpen = openedB.add;
  }

  static void _noHaptic(HapticKind kind) {}

  final OurSpace space;
  final FakeSkyPair pair;
  final SkyTogetherHome b;
  final List<SkyPatchSession> openedB = [];

  SkyTogetherHome get a => tester.widget<SkyTogetherLayer>(find.byType(SkyTogetherLayer)).home;

  late WidgetTester tester;

  SkyPatchSession get patchA => tester.widget<SkyPatchPage>(find.byType(SkyPatchPage)).session;

  Future<void> run(Duration total, {Duration step = beat}) async {
    var left = total.inMilliseconds;
    while (left > 0) {
      final ms = left < step.inMilliseconds ? left : step.inMilliseconds;
      pair.advance(Duration(milliseconds: ms));
      b.tick();
      await tester.pump(Duration(milliseconds: ms));
      left -= ms;
    }
  }

  Future<void> meet() async {
    for (var i = 0; i < 4; i++) {
      pair.settle();
      await tester.pump();
    }
    await run(const Duration(milliseconds: 400));
  }

  Future<TestGesture> holdMoon() async {
    final gesture = await tester.startGesture(tester.getCenter(find.byKey(SkyTogetherKeys.target)));
    await tester.pump();
    return gesture;
  }

  Future<SkyPatchSession> openTogether() async {
    final gesture = await holdMoon();
    b.press();
    await run(const Duration(seconds: 11));
    await gesture.up();
    await run(const Duration(milliseconds: 600));
    expect(find.byType(SkyPatchPage), findsOneWidget);
    expect(openedB, isNotEmpty);
    expect(patchA.id, openedB.last.id);
    return openedB.last;
  }

  Rect frame() {
    final box = tester.getRect(find.byKey(SkyTogetherKeys.frame));
    final side = box.width < box.height ? box.width : box.height;
    return Rect.fromCenter(center: box.center, width: side, height: side);
  }

  Offset at(Offset unit) {
    final f = frame();
    return Offset(f.left + unit.dx * f.width, f.top + unit.dy * f.height);
  }

  Future<void> tapSky(Offset unit) async {
    await tester.tapAt(at(unit));
    await run(beat);
  }

  Future<void> dragSky(Offset from, Offset to) async {
    final gesture = await tester.startGesture(at(from));
    await tester.pump(const Duration(milliseconds: 20));
    for (var i = 1; i <= 8; i++) {
      await gesture.moveTo(Offset.lerp(at(from), at(to), i / 8)!);
      await tester.pump(const Duration(milliseconds: 20));
    }
    await gesture.up();
    await run(beat);
  }

  Future<void> close() async {
    if (find.byType(SkyPatchPage).evaluate().isNotEmpty) await drive(tester, patchA.leave);
    await settle(tester, space);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    b.dispose();
    pair.dispose();
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<Phones> meetOnHome(WidgetTester tester, {bool day = false, bool motion = false, FakeSkyPair? pair}) async {
  if (motion) {
    usePhoneSize(tester);
  } else {
    calm(tester);
  }
  final space = await coupleSpace(tester);
  final phones = Phones(space, pair ?? FakeSkyPair())..tester = tester;
  final scoped = SkyTogetherScope(link: phones.pair.a, child: const HomeShell());
  if (day) {
    await pumpLove(tester, space, shell: Theme(data: SkyThemes.legacy(SkyTokens.day), child: scoped));
    await untilFound(tester, find.byType(HomeShell));
    await tester.pump(SkyMotion.dayNight + const Duration(milliseconds: 100));
  } else {
    await pumpNight(tester, space, shell: scoped);
  }
  await untilFound(tester, find.byKey(DailyKeys.card));
  await phones.meet();
  return phones;
}

Finder semanticsTarget() => find.byKey(SkyTogetherKeys.target);

void main() {
  setUp(recordHaptics);

  testWidgets('when both are here the moon invites them, and holding alone only waits', (tester) async {
    final phones = await meetOnHome(tester);
    expect(find.text(SkyTogetherCopy.hold(true)), findsOneWidget);
    final target = tester.widget<Semantics>(semanticsTarget());
    expect(target.properties.label, 'Hold the moon together with Alex');
    expect(target.properties.hint, 'Press and hold with Alex');
    expect(phones.pair.a.night, isTrue);
    expect(phones.pair.b.partnerNight, isTrue);

    final gesture = await phones.holdMoon();
    expect(phones.a.holding, isTrue);
    expect(recordedHaptics, [HapticKind.tick]);
    await phones.run(const Duration(seconds: 2));
    expect(find.text(SkyTogetherCopy.waiting('Alex')), findsOneWidget);
    expect(phones.b.stage, SkyTogetherStage.partnerHolding);
    await phones.run(const Duration(seconds: 14));
    expect(find.byType(SkyPatchPage), findsNothing);
    expect(recordedHaptics, [HapticKind.tick]);
    expect(phones.openedB, isEmpty);

    await gesture.up();
    await phones.run(beat);
    expect(phones.a.holding, isFalse);
    expect(find.text(SkyTogetherCopy.hold(true)), findsOneWidget);

    phones.pair.b.setForeground(false);
    await phones.run(beat * 3);
    expect(find.text(SkyTogetherCopy.hold(true)), findsNothing);
    expect(semanticsTarget(), findsNothing);
    expect(tester.takeException(), isNull);
    await phones.close();
  });

  testWidgets('a waiting letter steps aside for the invitation and comes back after', (tester) async {
    calm(tester);
    final space = await coupleSpace(tester);
    await drive(tester, () => space.letters.writeLetter(title: 'Open when you miss me', content: 'I miss you too'));
    final phones = Phones(space, FakeSkyPair(connected: false))..tester = tester;
    await pumpNight(tester, space, shell: SkyTogetherScope(link: phones.pair.a, child: const HomeShell()));
    await untilFound(tester, find.byKey(SkyPageKeys.letterTip));
    double tipOpacity() => tester
        .widget<AnimatedOpacity>(find.ancestor(of: find.byKey(SkyPageKeys.letterTip), matching: find.byType(AnimatedOpacity)))
        .opacity;
    expect(tipOpacity(), 1);
    phones.pair.connect();
    await phones.meet();
    expect(find.text(SkyTogetherCopy.hold(true)), findsOneWidget);
    expect(tipOpacity(), 0);
    phones.pair.drop();
    await phones.run(beat * 2);
    expect(find.text(SkyTogetherCopy.hold(true)), findsNothing);
    expect(tipOpacity(), 1);
    await phones.close();
  });

  testWidgets('ten seconds of holding together opens the patch on both phones, and letting go early does not', (
    tester,
  ) async {
    final phones = await meetOnHome(tester);
    final gesture = await phones.holdMoon();
    phones.b.press();
    await phones.run(const Duration(seconds: 4));
    expect(find.text(SkyTogetherCopy.bothHolding), findsOneWidget);
    expect(recordedHaptics.where((k) => k == HapticKind.heartbeat).length, greaterThanOrEqualTo(2));

    phones.b.release();
    await phones.run(const Duration(seconds: 1));
    expect(find.text(SkyTogetherCopy.waiting('Alex')), findsOneWidget);
    await phones.run(const Duration(seconds: 12));
    expect(find.byType(SkyPatchPage), findsNothing);
    expect(phones.openedB, isEmpty);
    expect(recordedHaptics, isNot(contains(HapticKind.celebration)));

    phones.b.press();
    await phones.run(const Duration(seconds: 9));
    expect(find.byType(SkyPatchPage), findsNothing);
    await phones.run(const Duration(seconds: 2));
    expect(phones.openedB, hasLength(1));
    await gesture.up();
    await phones.run(const Duration(milliseconds: 600));
    expect(find.byType(SkyPatchPage), findsOneWidget);
    expect(phones.patchA.id, phones.openedB.single.id);
    expect(recordedHaptics.last, HapticKind.celebration);
    expect(find.text(SkyTogetherCopy.drawTitle), findsOneWidget);
    expect(find.text(SkyTogetherCopy.drawingWith('Alex')), findsOneWidget);
    expect(find.descendant(of: find.byKey(SkyTogetherKeys.help), matching: find.textContaining('Tap for a star')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await phones.close();
  });

  testWidgets('a screen reader can start and stop the hold without pressing', (tester) async {
    final phones = await meetOnHome(tester);
    tester.widget<Semantics>(semanticsTarget()).properties.onTap!();
    await phones.run(beat);
    expect(phones.a.holding, isTrue);
    expect(tester.widget<Semantics>(semanticsTarget()).properties.value, SkyTogetherCopy.holdingOn);
    phones.b.press();
    await phones.run(const Duration(seconds: 11));
    expect(find.byType(SkyPatchPage), findsOneWidget);
    await phones.close();
  });

  testWidgets('every star and line drawn on one phone appears on the other, and the agreed name keeps one drawing', (
    tester,
  ) async {
    final phones = await meetOnHome(tester);
    final other = await phones.openTogether();
    final mine = phones.patchA;
    await until(tester, () => mine.loaded);

    await phones.tapSky(const Offset(0.3, 0.3));
    expect(mine.drawing.visibleStars, hasLength(1));
    await phones.run(beat);
    expect(other.drawing.visibleStars.single.id, mine.drawing.visibleStars.single.id);
    expect(recordedHaptics.last, HapticKind.tick);

    final theirs = other.placeStar(0.7, 0.6)!;
    await phones.run(beat * 2);
    expect(mine.drawing.visibleStar(theirs.id), isNotNull);
    expect(find.bySemanticsLabel(SkyTogetherCopy.partnerStar('Alex')), findsOneWidget);
    expect(find.bySemanticsLabel(SkyTogetherCopy.yourStar), findsOneWidget);
    expect(tester.widget<SkyButton>(find.byKey(SkyTogetherKeys.done)).enabled, isFalse);

    other.moveFinger(0.5, 0.5);
    await phones.run(beat);
    expect(mine.finger.value, isNotNull);
    other.liftFinger();
    await phones.run(beat);
    expect(mine.finger.value, isNull);

    await phones.dragSky(const Offset(0.3, 0.3), const Offset(0.69, 0.59));
    expect(mine.drawing.visibleLines, hasLength(1));
    await phones.run(beat);
    expect(other.drawing.visibleLines, hasLength(1));
    expect(tester.widget<SkyButton>(find.byKey(SkyTogetherKeys.done)).enabled, isTrue);

    await tester.tap(find.byKey(SkyTogetherKeys.done));
    await phones.run(beat * 3);
    expect(find.text(SkyTogetherCopy.nameTitle), findsOneWidget);
    expect(find.text(SkyTogetherCopy.seesIt('Alex')), findsOneWidget);
    expect(other.step, SkyPatchStep.naming);
    expect(other.typer, isFalse);

    await tester.enterText(find.descendant(of: find.byKey(SkyTogetherKeys.name), matching: find.byType(TextField)), 'Our kite');
    await phones.run(const Duration(milliseconds: 300));
    expect(other.name, 'Our kite');
    expect(find.descendant(of: find.byKey(SkyTogetherKeys.skyName), matching: find.text('Our kite')), findsOneWidget);
    await phones.run(const Duration(milliseconds: 1400));
    expect(find.text(SkyTogetherCopy.waitingYes('Alex')), findsOneWidget);

    expect(await other.agree(), isTrue);
    await phones.run(beat);
    await until(tester, () {
      phones.pair.advance(const Duration(milliseconds: 20));
      return mine.step == SkyPatchStep.saved && other.step == SkyPatchStep.saved;
    });
    await tester.pump();
    expect(find.text(SkyTogetherCopy.saved), findsOneWidget);
    expect(recordedHaptics.last, HapticKind.celebration);

    final key = phones.space.vault.requireKey();
    final kept = await drive(tester, () => phones.space.skyDrawings.list(key));
    expect(kept, hasLength(1));
    expect(kept.single.finished, isTrue);
    expect(kept.single.name, 'Our kite');
    expect(kept.single.drawing.visibleStars, hasLength(2));
    expect(kept.single.drawing.visibleLines, hasLength(1));

    await phones.run(const Duration(milliseconds: 1700));
    await phones.run(const Duration(milliseconds: 400));
    expect(find.byType(SkyPatchPage), findsNothing);
    expect(find.byKey(DailyKeys.card), findsOneWidget);
    expect(tester.takeException(), isNull);
    await phones.close();
  });

  testWidgets('the partner can name it while this phone says yes', (tester) async {
    final phones = await meetOnHome(tester);
    final other = await phones.openTogether();
    final mine = phones.patchA;
    await until(tester, () => mine.loaded);
    final one = other.placeStar(0.2, 0.2)!;
    final two = other.placeStar(0.8, 0.8)!;
    other.join(one.id, two.id);
    await phones.run(beat * 2);
    expect(other.finishDrawing(), isTrue);
    await phones.run(beat * 2);
    other.type('Long way');
    await phones.run(beat * 2);
    expect(find.text('Long way'), findsWidgets);
    expect(find.text(SkyTogetherCopy.naming('Alex')), findsOneWidget);
    expect(find.text(SkyTogetherCopy.sayYes), findsOneWidget);

    await tester.tap(find.byKey(SkyTogetherKeys.agree));
    await phones.run(beat);
    await until(tester, () {
      phones.pair.advance(const Duration(milliseconds: 20));
      return mine.step == SkyPatchStep.saved && other.step == SkyPatchStep.saved;
    });
    final kept = await drive(tester, () => phones.space.skyDrawings.list(phones.space.vault.requireKey()));
    expect(kept.single.name, 'Long way');
    await phones.close();
  });

  testWidgets('leaving keeps the drawing, and holding together again opens the very same one', (tester) async {
    final phones = await meetOnHome(tester);
    final other = await phones.openTogether();
    final mine = phones.patchA;
    final id = mine.id;
    await until(tester, () => mine.loaded);
    await phones.tapSky(const Offset(0.25, 0.4));
    other.placeStar(0.75, 0.4);
    await phones.run(beat * 2);
    expect(mine.drawing.visibleStars, hasLength(2));

    await tester.tap(find.bySemanticsLabel(SkyTogetherCopy.leave));
    await phones.run(const Duration(milliseconds: 400));
    expect(find.byType(SkyPatchPage), findsNothing);
    expect(other.partnerAway, isTrue);
    await phones.b.endSession();

    final key = phones.space.vault.requireKey();
    await until(tester, () => phones.a.unfinishedId == id);
    final draft = await drive(tester, () => phones.space.skyDrawings.unfinished(key));
    expect(draft!.id, id);
    expect(draft.drawing.visibleStars, hasLength(2));
    await phones.run(beat * 3);
    expect(find.text(SkyTogetherCopy.hold(true)), findsOneWidget);

    final again = await phones.openTogether();
    expect(again.id, id);
    await until(tester, () {
      phones.pair.advance(const Duration(milliseconds: 20));
      return phones.patchA.drawing.visibleStars.length == 2 && again.drawing.visibleStars.length == 2;
    });
    expect(await drive(tester, () => phones.space.skyDrawings.list(key)), hasLength(1));
    await phones.close();
  });

  testWidgets('when the partner steps away a gentle note leads back to the sky', (tester) async {
    final phones = await meetOnHome(tester);
    await phones.openTogether();
    await phones.b.endSession();
    await phones.run(beat * 3);
    expect(find.text(SkyTogetherCopy.steppedAway('Alex')), findsOneWidget);
    expect(find.text(SkyTogetherCopy.steppedAwayMessage(true)), findsOneWidget);
    await tester.tap(find.text(SkyTogetherCopy.backToSky));
    await phones.run(const Duration(milliseconds: 600));
    expect(find.byType(SkyPatchPage), findsNothing);
    expect(find.byKey(DailyKeys.card), findsOneWidget);
    await phones.close();
  });

  testWidgets('start over asks first, clears both phones and tells the partner', (tester) async {
    final phones = await meetOnHome(tester);
    final other = await phones.openTogether();
    final mine = phones.patchA;
    await until(tester, () => mine.loaded);
    await phones.tapSky(const Offset(0.4, 0.4));
    await phones.run(beat);
    await tester.tap(find.byKey(SkyTogetherKeys.startOver));
    await phones.run(beat * 3);
    expect(find.text(SkyTogetherCopy.startOverMessage), findsOneWidget);
    await tester.tap(find.text(SkyTogetherCopy.keepDrawing));
    await phones.run(beat * 3);
    expect(mine.drawing.visibleStars, hasLength(1));

    await tester.tap(find.byKey(SkyTogetherKeys.startOver));
    await phones.run(beat * 3);
    await tester.tap(find.widgetWithText(SkyButton, SkyTogetherCopy.startOver));
    await phones.run(beat * 3);
    expect(mine.drawing.isBlank, isTrue);
    expect(other.drawing.isBlank, isTrue);
    expect(recordedHaptics.last, HapticKind.tap);

    other.placeStar(0.5, 0.5);
    await phones.run(beat);
    expect(other.startOver(), isTrue);
    await phones.run(beat * 2);
    expect(find.text(SkyTogetherCopy.startedOver('Alex')), findsOneWidget);
    await phones.run(const Duration(seconds: 5));
    await phones.close();
  });

  testWidgets('a full patch says so softly instead of the help', (tester) async {
    final phones = await meetOnHome(tester);
    final other = await phones.openTogether();
    for (var i = 0; i < 26; i++) {
      other.placeStar(0.1 + (i % 6) * 0.15, 0.1 + (i ~/ 6) * 0.15);
    }
    await phones.run(beat * 2);
    expect(find.text(SkyTogetherCopy.starsLeft(4)), findsOneWidget);
    for (var i = 0; i < 4; i++) {
      other.placeStar(0.18 + i * 0.15, 0.92);
    }
    await phones.run(beat * 2);
    expect(phones.patchA.drawing.visibleStars, hasLength(30));
    expect(find.text(SkyTogetherCopy.fullOfStars), findsOneWidget);
    final before = phones.patchA.drawing;
    await phones.tapSky(const Offset(0.5, 0.97));
    expect(phones.patchA.drawing, before);
    await phones.close();
  });

  testWidgets('by day the sun is held, and the patch draws soft contrails', (tester) async {
    final phones = await meetOnHome(tester, day: true);
    expect(find.text(SkyTogetherCopy.hold(false)), findsOneWidget);
    expect(tester.widget<Semantics>(semanticsTarget()).properties.label, 'Hold the sun together with Alex');
    final other = await phones.openTogether();
    other.placeStar(0.3, 0.3);
    await phones.run(beat);
    expect(find.text(SkyTogetherCopy.drawTitle), findsOneWidget);
    expect(tester.takeException(), isNull);
    await phones.close();
  });

  testWidgets('with motion on, the twinkle, the beat, the pan and the comet play without errors', (tester) async {
    final phones = await meetOnHome(tester, motion: true);
    final gesture = await phones.holdMoon();
    phones.b.press();
    await phones.run(const Duration(seconds: 11), step: const Duration(milliseconds: 50));
    await gesture.up();
    for (var i = 0; i < 40; i++) {
      phones.pair.advance(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(SkyPatchPage), findsOneWidget);
    final other = phones.openedB.single;
    other.moveFinger(0.4, 0.4);
    await phones.run(const Duration(milliseconds: 200), step: const Duration(milliseconds: 16));
    other.moveFinger(0.6, 0.5);
    await phones.run(const Duration(milliseconds: 200), step: const Duration(milliseconds: 16));
    other.liftFinger();
    await phones.tapSky(const Offset(0.3, 0.6));
    other.placeStar(0.6, 0.3);
    await phones.run(const Duration(seconds: 1), step: const Duration(milliseconds: 16));
    await tester.tap(find.bySemanticsLabel(SkyTogetherCopy.leave));
    for (var i = 0; i < 30; i++) {
      phones.pair.advance(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(SkyPatchPage), findsNothing);
    expect(tester.takeException(), isNull);
    await phones.close();
  });

  testWidgets('a reader can add a star and join the newest two from the patch actions', (tester) async {
    final phones = await meetOnHome(tester);
    final other = await phones.openTogether();
    final handle = tester.ensureSemantics();
    final frame = tester.getSemantics(find.byKey(SkyTogetherKeys.frame));
    final add = frame.getSemanticsData().customSemanticsActionIds!.map(CustomSemanticsAction.getAction).toList();
    expect(add.map((a) => a!.label), contains(SkyTogetherCopy.addStar));
    void perform(String label) {
      final id = frame
          .getSemanticsData()
          .customSemanticsActionIds!
          .firstWhere((id) => CustomSemanticsAction.getAction(id)!.label == label);
      frame.owner!.performAction(frame.id, SemanticsAction.customAction, id);
    }

    perform(SkyTogetherCopy.addStar);
    await phones.run(beat);
    perform(SkyTogetherCopy.addStar);
    await phones.run(beat);
    expect(phones.patchA.drawing.visibleStars, hasLength(2));
    final refreshed = tester.getSemantics(find.byKey(SkyTogetherKeys.frame));
    final join = refreshed
        .getSemanticsData()
        .customSemanticsActionIds!
        .firstWhere((id) => CustomSemanticsAction.getAction(id)!.label == SkyTogetherCopy.joinNewest);
    refreshed.owner!.performAction(refreshed.id, SemanticsAction.customAction, join);
    await phones.run(beat * 2);
    expect(other.drawing.visibleLines, hasLength(1));
    handle.dispose();
    await phones.close();
  });
}
