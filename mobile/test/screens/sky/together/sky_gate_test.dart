import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/presentation/screens/sky/together/sky_gate.dart';

const int t0 = 1760000000000;

void main() {
  group('the gate', () {
    test('holding alone waits, and never opens however long it lasts', () {
      final gate = SkyGate();
      expect(gate.phaseAt(t0), SkyGatePhase.idle);
      gate.press(t0);
      expect(gate.holding, isTrue);
      expect(gate.phaseAt(t0 + 1), SkyGatePhase.holdingAlone);
      expect(gate.progressAt(t0 + 60000), 0);
      expect(gate.due(t0 + 60000, leader: true), isNull);
      expect(gate.pulsing(t0 + 60000), isFalse);
      expect(gate.beatsBetween(t0, t0 + 60000), isEmpty);
    });

    test('ten seconds of holding together opens both phones at the same moment, decided by the leader', () {
      final leader = SkyGate();
      final follower = SkyGate();
      leader.press(t0 + 1000);
      follower.hear(SkyHoldEvent(down: true, at: t0 + 1000, seq: 1));
      follower.press(t0 + 3000);
      leader.hear(SkyHoldEvent(down: true, at: t0 + 3000, seq: 4));

      for (final gate in [leader, follower]) {
        expect(gate.overlapStart, t0 + 3000);
        expect(gate.phaseAt(t0 + 3000), SkyGatePhase.together);
        expect(gate.progressAt(t0 + 8000), 0.5);
        expect(gate.pulsing(t0 + 8000), isTrue);
      }
      expect(leader.due(t0 + 12599, leader: true), isNull);
      expect(follower.due(t0 + 12600, leader: false), isNull);
      expect(follower.due(t0 + 12600, leader: null), isNull);
      final open = leader.due(t0 + 12600, leader: true)!;
      expect(open.at, t0 + 13000);

      leader.commit('sky-one', open.at);
      expect(follower.accept('sky-one', open.at, t0 + 12700), isTrue);
      for (final gate in [leader, follower]) {
        expect(gate.decided, isTrue);
        expect(gate.drawing, 'sky-one');
        expect(gate.phaseAt(t0 + 12999), SkyGatePhase.opening);
        expect(gate.phaseAt(t0 + 13000), SkyGatePhase.open);
        expect(gate.progressAt(t0 + 12800), 1);
      }
      expect(leader.due(t0 + 13000, leader: true), isNull);

      follower.release(t0 + 12900);
      leader.hear(SkyHoldEvent(down: false, at: t0 + 12900, seq: 4));
      expect(leader.phaseAt(t0 + 13000), SkyGatePhase.open);
      expect(follower.phaseAt(t0 + 13000), SkyGatePhase.open);
      expect(follower.accept('sky-one', open.at, t0 + 13000), isTrue);
    });

    test('a late tick still opens, at once rather than in the past', () {
      final gate = SkyGate()
        ..press(t0)
        ..partnerPress(t0, 1);
      expect(gate.due(t0 + 25000, leader: true)!.at, t0 + 25000);
    });

    test('letting go early fades the thread, and holding again starts from zero', () {
      final gate = SkyGate()
        ..press(t0)
        ..partnerPress(t0 + 500, 1);
      expect(gate.progressAt(t0 + 5500), 0.5);
      gate.release(t0 + 5500);
      expect(gate.phaseAt(t0 + 5600), SkyGatePhase.partnerHolding);
      expect(gate.progressAt(t0 + 5600), 0);
      expect(gate.due(t0 + 30000, leader: true), isNull);

      gate.press(t0 + 7000);
      expect(gate.overlapStart, t0 + 7000);
      expect(gate.progressAt(t0 + 7000), 0);
      expect(gate.due(t0 + 16599, leader: true), isNull);
      expect(gate.due(t0 + 16600, leader: true), isNotNull);

      gate.partnerRelease(t0 + 9000, 1);
      expect(gate.phaseAt(t0 + 9000), SkyGatePhase.holdingAlone);
      expect(gate.progressAt(t0 + 9000), 0);
    });

    test('a release that belongs to an older hold is ignored', () {
      final gate = SkyGate()
        ..press(t0)
        ..partnerPress(t0, 2);
      gate.hear(SkyHoldEvent(down: false, at: t0 + 10, seq: 1));
      expect(gate.partnerHolding, isTrue);
      gate.hear(SkyHoldEvent(down: false, at: t0 + 20, seq: 2));
      expect(gate.partnerHolding, isFalse);
      gate.partnerRelease(t0 + 30, 2);
      expect(gate.phaseAt(t0 + 30), SkyGatePhase.holdingAlone);
    });

    test('a dropped link mid-hold cancels cleanly, even after the door was decided', () {
      final gate = SkyGate()
        ..press(t0)
        ..partnerPress(t0, 1);
      gate.partnerLost(t0 + 4000);
      expect(gate.phaseAt(t0 + 4000), SkyGatePhase.holdingAlone);
      expect(gate.progressAt(t0 + 4000), 0);

      gate.partnerPress(t0 + 5000, 2);
      final open = gate.due(t0 + 14600, leader: true)!;
      gate.commit('sky-one', open.at);
      gate.partnerLost(t0 + 14700);
      expect(gate.decided, isFalse);
      expect(gate.drawing, isNull);
      expect(gate.phaseAt(t0 + 15000), SkyGatePhase.holdingAlone);

      final opened = SkyGate()
        ..press(t0)
        ..partnerPress(t0, 1)
        ..commit('sky-two', t0 + 10000);
      opened.partnerLost(t0 + 10001);
      expect(opened.phaseAt(t0 + 10001), SkyGatePhase.open);
      expect(opened.drawing, 'sky-two');
    });

    test('the follower takes an open that crosses its release, and refuses one long after', () {
      final crossing = SkyGate()
        ..press(t0)
        ..partnerPress(t0, 1)
        ..release(t0 + 9700);
      expect(crossing.accept('sky-one', t0 + 10000, t0 + 9900), isTrue);
      expect(crossing.phaseAt(t0 + 10000), SkyGatePhase.open);

      final stale = SkyGate()
        ..press(t0)
        ..release(t0 + 1000);
      expect(stale.accept('sky-one', t0 + 10000, t0 + 9000), isFalse);
      expect(stale.decided, isFalse);
      expect(SkyGate().accept('sky-one', t0, t0), isFalse);
    });

    test('if both phones ever decide, both settle on the same drawing and its moment', () {
      final a = SkyGate()
        ..press(t0)
        ..partnerPress(t0, 1)
        ..commit('sky-b', t0 + 10000);
      final b = SkyGate()
        ..press(t0)
        ..partnerPress(t0, 1)
        ..commit('sky-a', t0 + 10050);
      expect(a.accept('sky-a', t0 + 10050, t0 + 9700), isTrue);
      expect(b.accept('sky-b', t0 + 10000, t0 + 9700), isTrue);
      expect(a.drawing, 'sky-a');
      expect(b.drawing, 'sky-a');
      expect(a.openAt, t0 + 10050);
      expect(b.openAt, t0 + 10050);
    });

    test('a close for the decided drawing calls it off, and reset forgets everything', () {
      final gate = SkyGate()
        ..press(t0)
        ..partnerPress(t0, 1)
        ..commit('sky-one', t0 + 10000);
      gate.cancel('sky-other');
      expect(gate.decided, isTrue);
      gate.cancel('sky-one');
      expect(gate.decided, isFalse);
      expect(gate.phaseAt(t0 + 10000), SkyGatePhase.together);
      gate.reset();
      expect(gate.phaseAt(t0 + 10000), SkyGatePhase.idle);
      expect(gate.holding || gate.partnerHolding, isFalse);
    });
  });

  group('the heartbeat', () {
    test('beats fall on the shared clock grid, so two phones ticking differently pulse together', () {
      final start = t0 + 123;
      final end = start + 10000;
      final fast = <int>[];
      for (var t = start; t < end; t += 16) {
        fast.addAll(SkyHeartbeat.between(t, t + 16));
      }
      final slow = <int>[];
      for (var t = start; t < end; t += 250) {
        slow.addAll(SkyHeartbeat.between(t, t + 250));
      }
      expect(fast, isNotEmpty);
      expect(fast, slow);
      expect(fast.every((at) => at % SkyHeartbeat.periodMs == 0), isTrue);
      expect(fast.length, inInclusiveRange(7, 8));
      expect(SkyHeartbeat.between(end, end), isEmpty);
      expect(SkyHeartbeat.nextAfter(fast.first), fast.first + SkyHeartbeat.periodMs);
      expect(SkyHeartbeat.nextAfter(fast.first - 1), fast.first);
    });

    test('the glow peaks on the beat, echoes softly, then rests', () {
      final beat = SkyHeartbeat.beatAt(SkyHeartbeat.beatOf(t0) + 1);
      expect(SkyHeartbeat.glow(beat), 1);
      expect(SkyHeartbeat.glow(beat + 90), lessThan(1));
      expect(SkyHeartbeat.glow(beat + SkyHeartbeat.dubMs), greaterThan(SkyHeartbeat.glow(beat + SkyHeartbeat.dubMs - 1)));
      expect(SkyHeartbeat.glow(beat + 1200), lessThan(0.05));
    });

    test('only both holding makes the phones pulse', () {
      final gate = SkyGate()..press(t0);
      expect(gate.beatsBetween(t0, t0 + 5000), isEmpty);
      gate.partnerPress(t0 + 100, 1);
      expect(gate.beatsBetween(t0, t0 + 5000), SkyHeartbeat.between(t0, t0 + 5000));
      gate.release(t0 + 5000);
      expect(gate.beatsBetween(t0 + 5000, t0 + 9000), isEmpty);
    });
  });
}
