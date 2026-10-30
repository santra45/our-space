import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/core/engine/crypto/base64.dart' show randomBytes;
import 'package:our_space_mobile/presentation/screens/sky/together/sky_gate.dart';
import 'package:our_space_mobile/presentation/screens/sky/together/sky_patch_session.dart';
import 'package:our_space_mobile/presentation/screens/sky/together/sky_together_home.dart';
import 'package:our_space_mobile/presentation/widgets/app_haptics.dart';

import '../../../support/fake_sky_together.dart';
import '../../../support/harness.dart';
import 'support/together_phones.dart';

void main() {
  group("a touch on the other one's star", () {
    test('reaches the other phone as a heartbeat, and only while both are here', () async {
      final phones = TogetherPhones(pair: FakeSkyPair(connected: false));
      expect(phones.a.canTouch, isFalse);
      expect(phones.a.touch(), isFalse);
      phones.pair.connect();
      await phones.meet();
      expect(phones.a.canTouch, isTrue);
      expect(phones.a.touch(), isTrue);
      await phones.step();
      expect(phones.a.touchesSent, 1);
      expect(phones.b.touchesFelt, 1);
      expect(phones.b.touchesSent, 0);
      expect(phones.kindsA(), [HapticKind.tap]);
      expect(phones.kindsB(), [HapticKind.heartbeat]);
      expect(phones.pair.transportA.sentOf('touch'), hasLength(1));
      phones.dispose();
    });

    test('taps faster than a breath count once, and the next one after goes through', () async {
      final phones = TogetherPhones();
      await phones.meet();
      expect(phones.a.touch(), isTrue);
      expect(phones.a.touch(), isFalse);
      await phones.step();
      expect(phones.a.touch(), isFalse);
      await phones.step(const Duration(milliseconds: 300));
      expect(phones.a.touch(), isTrue);
      await phones.step();
      expect(phones.a.touchesSent, 2);
      expect(phones.b.touchesFelt, 2);
      phones.dispose();
    });

    test('a flood from the other phone buzzes at most every quarter of a second', () async {
      final phones = TogetherPhones();
      await phones.meet();
      for (var i = 0; i < 10; i++) {
        phones.pair.injectEvent(phones.pair.b, const SkyTouchEvent());
      }
      await pumpEventQueue();
      expect(phones.b.touchesFelt, 1);
      await phones.step(const Duration(milliseconds: 300));
      phones.pair.injectEvent(phones.pair.b, const SkyTouchEvent());
      await pumpEventQueue();
      expect(phones.b.touchesFelt, 2);
      expect(phones.kindsB(), [HapticKind.heartbeat, HapticKind.heartbeat]);
      phones.dispose();
    });

    test('nobody can touch a phone that has stepped away, and it feels nothing if one slips through', () async {
      final phones = TogetherPhones();
      await phones.meet();
      phones.b.present(visible: false, night: true);
      await phones.step();
      expect(phones.a.canTouch, isFalse);
      expect(phones.a.touch(), isFalse);
      phones.pair.injectEvent(phones.pair.b, const SkyTouchEvent());
      await pumpEventQueue();
      expect(phones.b.touchesFelt, 0);
      expect(phones.kindsB(), isEmpty);
      phones.dispose();
    });

    test('while the patch is open there is no touching, and none is felt', () async {
      final phones = TogetherPhones();
      await phones.meet();
      await phones.openTogether();
      expect(phones.a.canTouch, isFalse);
      expect(phones.a.touch(), isFalse);
      phones.pair.injectEvent(phones.pair.b, const SkyTouchEvent());
      await pumpEventQueue();
      expect(phones.b.touchesFelt, 0);
      phones.dispose();
    });
  });

  group('the gate between two phones', () {
    test('when both are here each is invited, and nobody is invited alone', () async {
      final phones = TogetherPhones(pair: FakeSkyPair(connected: false));
      expect(phones.a.stage, SkyTogetherStage.off);
      expect(phones.a.press(), isFalse);
      phones.pair.connect();
      await phones.meet();
      expect(phones.a.stage, SkyTogetherStage.invite);
      expect(phones.b.stage, SkyTogetherStage.invite);

      phones.b.present(visible: false, night: true);
      await phones.step();
      expect(phones.b.stage, SkyTogetherStage.off);
      expect(phones.a.stage, SkyTogetherStage.off);
      expect(phones.pair.b.night, isTrue);

      phones.b.present(visible: true, night: true);
      await phones.step();
      expect(phones.a.stage, SkyTogetherStage.invite);
      expect(phones.pair.a.partnerNight, isTrue);
      phones.dispose();
    });

    test('holding alone waits, and never opens however long it lasts', () async {
      final phones = TogetherPhones();
      await phones.meet();
      expect(phones.a.press(), isTrue);
      expect(phones.a.press(), isFalse);
      await phones.run(const Duration(seconds: 25));
      expect(phones.a.stage, SkyTogetherStage.alone);
      expect(phones.b.stage, SkyTogetherStage.partnerHolding);
      expect(phones.a.progress(), 0);
      expect(phones.openedA, isEmpty);
      expect(phones.openedB, isEmpty);
      expect(phones.kindsA(), [HapticKind.tick]);
      expect(phones.kindsB(), isEmpty);
      phones.dispose();
    });

    test('ten seconds of holding together opens both phones at the same moment, on one shared heartbeat', () async {
      final phones = TogetherPhones();
      await phones.meet();
      expect(phones.pair.sharedGap, lessThanOrEqualTo(1));
      phones.a.press();
      await phones.run(const Duration(seconds: 2));
      phones.b.press();
      final pressed = phones.pair.b.sharedNow();
      await phones.step();
      expect(phones.a.stage, SkyTogetherStage.together);
      expect(phones.b.stage, SkyTogetherStage.together);

      int? openA;
      int? openB;
      phones.a.onOpen = (session) {
        openA = phones.pair.a.sharedNow();
        phones.openedA.add(session);
      };
      phones.b.onOpen = (session) {
        openB = phones.pair.b.sharedNow();
        phones.openedB.add(session);
      };
      await phones.run(const Duration(seconds: 9), step: const Duration(milliseconds: 50));
      expect(phones.openedA, isEmpty);
      expect(phones.a.progress(), greaterThan(0.85));
      await phones.run(const Duration(seconds: 2), step: const Duration(milliseconds: 50));
      expect(phones.openedA, hasLength(1));
      expect(phones.openedB, hasLength(1));
      expect(phones.openedA.single.id, phones.openedB.single.id);
      expect((openA! - openB!).abs(), lessThanOrEqualTo(2));
      expect(openA! - pressed, inInclusiveRange(10000, 10200));
      expect(phones.a.stage, SkyTogetherStage.off);
      expect(phones.a.session, same(phones.openedA.single));

      for (final felt in [phones.feltA, phones.feltB]) {
        final beats = [for (final f in felt) if (f.kind == HapticKind.heartbeat) f.shared];
        expect(beats.length, greaterThanOrEqualTo(6));
        expect(felt.last.kind, HapticKind.celebration);
      }
      List<int> grid(List<FeltHaptic> felt) => [
        for (final f in felt)
          if (f.kind == HapticKind.heartbeat) SkyHeartbeat.beatOf(f.shared),
      ];
      expect(grid(phones.feltA), grid(phones.feltB));
      phones.dispose();
    });

    test('letting go early fades it all on both phones and nothing opens', () async {
      final phones = TogetherPhones();
      await phones.meet();
      phones.a.press();
      phones.b.press();
      await phones.run(const Duration(seconds: 5));
      expect(phones.a.progress(), greaterThan(0.4));
      phones.b.release();
      await phones.step();
      expect(phones.a.stage, SkyTogetherStage.alone);
      expect(phones.b.stage, SkyTogetherStage.partnerHolding);
      expect(phones.a.progress(), 0);
      final beats = phones.kindsA().where((k) => k == HapticKind.heartbeat).length;
      await phones.run(const Duration(seconds: 20));
      expect(phones.openedA, isEmpty);
      expect(phones.openedB, isEmpty);
      expect(phones.kindsA().where((k) => k == HapticKind.heartbeat).length, beats);

      phones.a.release();
      await phones.step();
      expect(phones.a.stage, SkyTogetherStage.invite);
      expect(phones.b.stage, SkyTogetherStage.invite);
      phones.dispose();
    });

    test('a hold is let go when the partner leaves, and a screen reader can start and stop it', () async {
      final phones = TogetherPhones();
      await phones.meet();
      phones.a.toggle();
      expect(phones.a.holding, isTrue);
      phones.a.toggle();
      expect(phones.a.holding, isFalse);
      phones.a.toggle();
      phones.b.press();
      await phones.run(const Duration(seconds: 3));
      phones.pair.drop();
      await phones.step();
      expect(phones.a.holding, isFalse);
      expect(phones.a.stage, SkyTogetherStage.off);
      expect(phones.b.stage, SkyTogetherStage.off);
      await phones.run(const Duration(seconds: 15));
      expect(phones.openedA, isEmpty);
      expect(phones.openedB, isEmpty);
      phones.dispose();
    });

    test('a hold made while the other phone is still in the patch still counts when it comes back', () async {
      final phones = TogetherPhones();
      await phones.meet();
      await phones.openTogether();
      expect(phones.pair.a.isLeader, isTrue);

      await phones.b.endSession();
      await phones.step();
      expect(phones.b.stage, SkyTogetherStage.invite);
      expect(phones.b.press(), isTrue);
      await phones.step();
      expect(phones.a.gate.partnerHolding, isTrue);

      await phones.a.endSession();
      await phones.step();
      expect(phones.a.stage, SkyTogetherStage.partnerHolding);
      expect(phones.a.press(), isTrue);
      await phones.run(const Duration(seconds: 12), until: () => phones.openedA.length > 1 && phones.openedB.length > 1);
      expect(phones.openedA, hasLength(2));
      expect(phones.openedB, hasLength(2));
      expect(phones.openedA.last.id, phones.openedB.last.id);
      phones.dispose();
    });

    test('a hold the other phone forgot while it lost sight of us is sent again when it presses', () async {
      final phones = TogetherPhones();
      await phones.meet();
      expect(phones.b.press(), isTrue);
      await phones.step();
      expect(phones.a.stage, SkyTogetherStage.partnerHolding);

      phones.pair.injectEvent(
        phones.pair.a,
        SkyPresenceEvent(here: false, night: false, owner: phones.pair.ownerB!, tag: 'tag-phone-b', t: 1),
      );
      await phones.step();
      expect(phones.a.gate.partnerHolding, isFalse);
      await phones.run(const Duration(seconds: 4), until: () => phones.pair.a.partnerHere);
      expect(phones.a.stage, SkyTogetherStage.invite);
      expect(phones.b.holding, isTrue);

      expect(phones.a.press(), isTrue);
      await phones.step();
      await phones.step();
      expect(phones.a.stage, SkyTogetherStage.together);
      await phones.run(const Duration(seconds: 12), until: () => phones.openedA.isNotEmpty && phones.openedB.isNotEmpty);
      expect(phones.openedA, hasLength(1));
      expect(phones.openedB, hasLength(1));
      phones.dispose();
    });

    test('a door called off on one phone is called off on the other, and nobody opens alone', () async {
      final phones = TogetherPhones();
      await phones.meet();
      phones.a.press();
      phones.b.press();
      await phones.run(const Duration(seconds: 11), until: () => phones.b.gate.decided);
      expect(phones.a.gate.decided, isTrue);
      expect(phones.b.gate.decided, isTrue);
      expect(phones.openedA, isEmpty);

      phones.b.present(visible: false, night: false);
      await phones.step();
      expect(phones.a.gate.decided, isFalse);
      expect(phones.b.gate.decided, isFalse);
      expect(phones.pair.transportB.sentOf('close'), isNotEmpty);
      await phones.run(const Duration(seconds: 2));
      phones.b.present(visible: true, night: false);
      await phones.run(const Duration(seconds: 3));
      expect(phones.openedA, isEmpty);
      expect(phones.openedB, isEmpty);
      expect(phones.a.stage, SkyTogetherStage.invite);
      expect(phones.b.stage, SkyTogetherStage.invite);
      phones.dispose();
    });

    test('the phone that sees the other leave in the last moment tells it, so it does not open alone', () async {
      final phones = TogetherPhones();
      await phones.meet();
      phones.a.press();
      phones.b.press();
      await phones.run(const Duration(seconds: 11), until: () => phones.b.gate.decided);
      phones.pair.injectEvent(
        phones.pair.a,
        SkyPresenceEvent(here: false, night: false, owner: phones.pair.ownerB!, tag: 'tag-phone-b', t: 1),
      );
      await phones.step();
      expect(phones.a.gate.decided, isFalse);
      expect(phones.pair.transportA.sentOf('close').single['drawing'], isNotNull);
      expect(phones.b.gate.decided, isFalse);
      await phones.run(const Duration(seconds: 3));
      expect(phones.openedA, isEmpty);
      expect(phones.openedB, isEmpty);
      phones.dispose();
    });

    test('a phone that wakes long after its moment lets the door go instead of opening alone', () async {
      final phones = TogetherPhones();
      await phones.meet();
      phones.a.press();
      phones.b.press();
      await phones.run(const Duration(seconds: 11), until: () => phones.b.gate.decided);
      for (var i = 0; i < 25; i++) {
        phones.pair.advance(const Duration(milliseconds: 100));
        await pumpEventQueue();
        phones.a.tick();
      }
      expect(phones.openedA, hasLength(1));
      expect(phones.b.gate.phaseAt(phones.pair.b.sharedNow()), SkyGatePhase.open);

      phones.b.tick();
      await phones.step();
      expect(phones.openedB, isEmpty);
      expect(phones.b.gate.decided, isFalse);
      expect(phones.b.holding, isFalse);
      expect(phones.openedA.single.partnerAway, isTrue);
      phones.dispose();
    });

    test('a door set far from now is refused, and the hold lets go so it is not asked again and again', () async {
      final phones = TogetherPhones();
      await phones.meet();
      phones.a.press();
      phones.b.press();
      await phones.step();
      final now = phones.pair.b.sharedNow();
      phones.pair.injectEvent(phones.pair.b, SkyOpenEvent(drawing: 'sky-far', at: now + 3600000));
      await phones.step();
      expect(phones.b.gate.decided, isFalse);
      expect(phones.b.stage, isNot(SkyTogetherStage.opening));
      expect(phones.b.holding, isFalse);
      expect(phones.pair.transportB.sentOf('close').single['drawing'], 'sky-far');
      await phones.run(const Duration(seconds: 12));
      expect(phones.openedA, isEmpty);
      expect(phones.openedB, isEmpty);
      expect(phones.pair.transportA.sentOf('open'), isEmpty);
      phones.dispose();
    });

    test('the follower refuses a door it was never holding for', () async {
      final phones = TogetherPhones();
      await phones.meet();
      phones.pair.injectEvent(phones.pair.b, const SkyOpenEvent(drawing: 'sky-stray', at: 1760000005000));
      await phones.step();
      expect(phones.openedB, isEmpty);
      expect(phones.pair.transportB.sentOf('close').single['drawing'], 'sky-stray');
      phones.dispose();
    });
  });

  group('drawing together', () {
    test('every star, line and removal shows on the other phone, and so does the finger', () async {
      final phones = TogetherPhones();
      await phones.meet();
      final (a, b) = await phones.openTogether();
      expect(a.leader, isTrue);
      expect(b.leader, isFalse);
      final notices = <SkyPatchNotice>[];
      final sub = b.notices.listen(notices.add);

      final one = a.placeStar(0.3, 0.3)!;
      final two = b.placeStar(0.7, 0.6)!;
      await phones.step();
      expect(b.drawing.visibleStars.map((s) => s.id), unorderedEquals([one.id, two.id]));
      expect(a.drawing, b.drawing);
      expect(notices, contains(SkyPatchNotice(SkyPatchNoticeKind.partnerStar, one.id)));
      expect(a.canFinish, isFalse);

      expect(a.join(one.id, two.id), isTrue);
      expect(a.join(two.id, one.id), isFalse);
      await phones.step();
      expect(b.drawing.visibleLines.single.key, skyLineKey(one.id, two.id));
      expect(b.canFinish, isTrue);

      expect(b.takeAway(one.id), isFalse);
      expect(b.takeAway(two.id), isTrue);
      await phones.step();
      expect(a.drawing.visibleStars.single.id, one.id);
      expect(a.drawing.visibleLines, isEmpty);

      a.moveFinger(0.5, 0.25);
      await phones.step();
      expect(b.finger.value!.unit, const Offset(0.5, 0.25));
      a.liftFinger();
      await phones.step();
      expect(b.finger.value, isNull);

      expect(a.startOver(), isTrue);
      await phones.step();
      expect(b.drawing.isBlank, isTrue);
      expect(b.drawing.gen, 1);
      expect(notices.last, const SkyPatchNotice(SkyPatchNoticeKind.partnerStartedOver));
      await sub.cancel();
      phones.dispose();
    });

    test('a phone that missed the start catches up from the other phone', () async {
      final phones = TogetherPhones();
      await phones.meet();
      final (a, b) = await phones.openTogether();
      phones.pair.transportA.refuse = true;
      final lost = a.placeStar(0.2, 0.8)!;
      phones.pair.transportA.refuse = false;
      await phones.step();
      expect(b.drawing.visibleStar(lost.id), isNull);
      b.placeStar(0.8, 0.2);
      await phones.step();
      phones.pair.injectEvent(phones.pair.b, SkyStateEvent(drawing: a.id, state: a.drawing));
      await phones.step();
      await phones.step();
      expect(b.drawing, a.drawing);
      expect(a.drawing.visibleStars, hasLength(2));
      phones.dispose();
    });
  });

  group('naming and keeping it', () {
    late VaultStore store;
    late VaultKey key;
    late SkyDrawingService drawings;

    setUp(() async {
      store = await openTestStore();
      key = VaultKey.fromBits(randomBytes(32));
      drawings = SkyDrawingService(store: store);
    });

    tearDown(() => store.close());

    Future<(SkyPatchSession, SkyPatchSession)> drawKite(TogetherPhones phones) async {
      final (a, b) = await phones.openTogether();
      await phones.real(() => a.loaded && b.loaded);
      final one = a.placeStar(0.3, 0.3)!;
      final two = b.placeStar(0.7, 0.6)!;
      await phones.step();
      a.join(one.id, two.id);
      await phones.step();
      return (a, b);
    }

    test('one says done and types, the other sees it live and says yes, and one drawing is kept', () async {
      final phones = TogetherPhones(drawingsA: drawings, keyA: key);
      await phones.meet();
      final (a, b) = await drawKite(phones);

      expect(b.finishDrawing(), isTrue);
      await phones.step();
      expect(b.step, SkyPatchStep.naming);
      expect(b.typer, isTrue);
      expect(a.step, SkyPatchStep.naming);
      expect(a.typer, isFalse);
      expect(a.canAgree, isFalse);
      expect(await a.agree(), isFalse);

      b.type('Our  kite ');
      await phones.step();
      expect(a.name, 'Our  kite ');
      expect(a.canAgree, isTrue);

      expect(await a.agree(), isTrue);
      await phones.real(() => a.step == SkyPatchStep.saved && b.step == SkyPatchStep.saved);
      expect(a.savedName, 'Our kite');
      expect(b.savedName, 'Our kite');
      expect(phones.kindsA().last, HapticKind.celebration);
      expect(phones.kindsB().last, HapticKind.celebration);

      final kept = await drawings.list(key);
      expect(kept, hasLength(1));
      expect(kept.single.id, a.id);
      expect(kept.single.finished, isTrue);
      expect(kept.single.name, 'Our kite');
      expect(kept.single.night, isNotNull);
      expect(kept.single.drawing.visibleStars, hasLength(2));
      expect(kept.single.drawing.visibleLines, hasLength(1));

      phones.pair.injectEvent(phones.pair.a, SkyAgreeEvent(drawing: a.id, text: 'Something else'));
      await phones.step();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(await drawings.list(key), hasLength(1));
      expect((await drawings.list(key)).single.name, 'Our kite');
      phones.dispose();
    });

    test('change it hands the typing over, and saying done at once leaves the leader typing', () async {
      final phones = TogetherPhones(drawingsA: drawings, keyA: key);
      await phones.meet();
      final (a, b) = await drawKite(phones);

      a.finishDrawing();
      b.finishDrawing();
      await phones.step();
      await phones.step();
      expect(a.typer, isTrue);
      expect(b.typer, isFalse);

      a.type('Kite');
      await phones.step();
      b.changeIt();
      await phones.step();
      expect(b.typer, isTrue);
      expect(a.typer, isFalse);
      expect(b.name, 'Kite');
      b.type('Our kite');
      await phones.step();
      expect(a.name, 'Our kite');

      a.backToDrawing();
      await phones.step();
      expect(a.step, SkyPatchStep.drawing);
      expect(b.step, SkyPatchStep.drawing);
      expect(phones.openedA, hasLength(1));
      expect(phones.a.session, same(a));

      a.finishDrawing();
      await phones.step();
      a.type('The kite');
      await phones.step();
      expect(await b.agree(), isTrue);
      expect(b.step, SkyPatchStep.saving);
      await phones.real(() => b.step == SkyPatchStep.saved);
      expect((await drawings.list(key)).single.name, 'The kite');
      phones.dispose();
    });

    test('the leader only finishes on a yes it can take, and never on a saved it did not send', () async {
      final phones = TogetherPhones(drawingsA: drawings, keyA: key);
      await phones.meet();
      final (a, b) = await drawKite(phones);

      phones.pair.injectEvent(phones.pair.a, SkyAgreeEvent(drawing: a.id, text: 'Kite'));
      await phones.step();
      expect(a.step, SkyPatchStep.drawing);
      phones.pair.injectEvent(phones.pair.a, SkySavedEvent(drawing: a.id));
      await phones.step();
      expect(a.step, SkyPatchStep.drawing);
      a.placeStar(0.5, 0.9);
      await phones.step();
      await a.flush();
      final draft = (await drawings.list(key)).single;
      expect(draft.finished, isFalse);
      expect(draft.drawing.visibleStars, hasLength(3));

      expect(a.finishDrawing(), isTrue);
      await phones.step();
      expect(b.step, SkyPatchStep.naming);
      final theirs = a.drawing.visibleStars.firstWhere((star) => star.by == phones.pair.ownerB);
      phones.pair.injectEvent(phones.pair.a, SkyOpEvent(drawing: a.id, op: SkyRemove([theirs.id], gen: 0)));
      await phones.step();
      expect(a.canFinish, isFalse);
      phones.pair.injectEvent(phones.pair.a, SkyAgreeEvent(drawing: a.id, text: 'Kite'));
      await phones.step();
      await phones.step();
      expect(a.step, SkyPatchStep.drawing);
      expect(b.step, SkyPatchStep.drawing);
      await a.flush();
      expect((await drawings.list(key)).single.finished, isFalse);
      phones.dispose();
    });

    test('a yes that crosses the typer going back to drawing leaves both drawing and nothing finished', () async {
      final phones = TogetherPhones(drawingsA: drawings, keyA: key);
      await phones.meet();
      final (a, b) = await drawKite(phones);
      expect(a.finishDrawing(), isTrue);
      await phones.step();
      a.type('Kite');
      await phones.step();
      expect(b.canAgree, isTrue);

      a.backToDrawing();
      expect(await b.agree(), isTrue);
      expect(b.step, SkyPatchStep.saving);
      await phones.step();
      await phones.step();
      expect(a.step, SkyPatchStep.drawing);
      expect(b.step, SkyPatchStep.drawing);
      expect(b.canEdit, isTrue);
      await a.flush();
      expect((await drawings.list(key)).single.finished, isFalse);
      phones.dispose();
    });

    test('change it hands the typing over even before the leader has typed a letter', () async {
      final phones = TogetherPhones(drawingsA: drawings, keyA: key);
      await phones.meet();
      final (a, b) = await drawKite(phones);
      expect(a.finishDrawing(), isTrue);
      await phones.step();
      expect(a.typer, isTrue);
      expect(b.typer, isFalse);
      expect(a.name, isEmpty);

      b.changeIt();
      for (var i = 0; i < 4; i++) {
        await phones.step();
      }
      expect(b.typer, isTrue);
      expect(a.typer, isFalse);
      b.type('Our kite');
      await phones.step();
      expect(a.name, 'Our kite');
      expect(b.typer, isTrue);
      phones.dispose();
    });

    test('leaving keeps the half-finished drawing, and holding together again opens the same one', () async {
      final phones = TogetherPhones(drawingsA: drawings, keyA: key);
      await phones.meet();
      final (a, b) = await drawKite(phones);
      final id = a.id;

      final leaving = phones.a.endSession();
      await phones.step();
      expect(b.partnerAway, isTrue);
      expect(b.canEdit, isFalse);
      expect(b.placeStar(0.5, 0.5), isNull);
      await leaving;
      await phones.b.endSession();
      await phones.step();

      final draft = await drawings.unfinished(key);
      expect(draft!.id, id);
      expect(draft.drawing.visibleStars, hasLength(2));
      expect(draft.drawing.visibleLines, hasLength(1));
      await phones.real(() => phones.a.unfinishedId == id);
      expect(phones.a.stage, SkyTogetherStage.invite);

      final (again, other) = await phones.openTogether();
      expect(again.id, id);
      expect(other.id, id);
      await phones.real(() => again.loaded && other.drawing.visibleStars.length == 2);
      expect(again.drawing.visibleLines, hasLength(1));
      expect(other.drawing, again.drawing);
      expect(await drawings.list(key), hasLength(1));
      phones.dispose();
    });

    test('home does not read every drawing again while the patch is open, only once it closes', () async {
      final counting = _CountingDrawings(store);
      final phones = TogetherPhones(drawingsA: counting, keyA: key);
      await phones.meet();
      final (a, _) = await drawKite(phones);
      await phones.real(() => a.drawing.visibleLines.isNotEmpty);
      final before = counting.lists;
      for (var i = 0; i < 4; i++) {
        a.placeStar(0.1 + i * 0.2, 0.9);
        await phones.step();
      }
      await a.flush();
      await phones.step();
      expect(counting.lists, before);
      await phones.a.endSession();
      expect(counting.lists, greaterThan(before));
      phones.dispose();
    });

    test('a dropped link pauses the patch on both phones and keeps the drawing', () async {
      final phones = TogetherPhones(drawingsA: drawings, keyA: key);
      await phones.meet();
      final (a, b) = await drawKite(phones);
      phones.pair.drop();
      await phones.step();
      expect(a.partnerAway, isTrue);
      expect(b.partnerAway, isTrue);
      await a.flush();
      expect((await drawings.unfinished(key))!.drawing.visibleStars, hasLength(2));
      phones.dispose();
    });
  });
}

class _CountingDrawings extends SkyDrawingService {
  _CountingDrawings(VaultStore store) : super(store: store);

  int lists = 0;

  @override
  Future<List<SkyDrawingRecord>> list(VaultKey? key) {
    lists++;
    return super.list(key);
  }
}
