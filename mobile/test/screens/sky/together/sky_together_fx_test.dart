import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/presentation/screens/sky/together/sky_together_copy.dart';
import 'package:our_space_mobile/presentation/screens/sky/together/sky_together_fx.dart';
import 'package:our_space_mobile/presentation/screens/sky/together/sky_together_home.dart';
import 'package:our_space_mobile/presentation/screens/sky/together/sky_together_layer.dart';
import 'package:our_space_mobile/presentation/sky/sky.dart';

final RegExp technical = RegExp(
  r'\b(sync|device|pair|server|upload|download|data|peer|relay|mailbox|encrypt|key|session|canvas)',
  caseSensitive: false,
);

void main() {
  test('the thread of light arcs above the heart and peaks near the top of its lobes', () {
    const heart = SkyConstellation();
    final me = heart.pointAt(heart.me);
    final partner = heart.pointAt(heart.partner);
    final thread = SkyThread(me, partner, centre: heart.bounds.center);
    expect(thread.at(0), me);
    expect(thread.at(1), partner);
    expect(thread.mid.dy, lessThan(me.dy));
    expect(thread.mid.dy, closeTo(184, 3));
    expect(thread.mid.dx, closeTo((me.dx + partner.dx) / 2, 0.5));

    final below = SkyThread(const Offset(100, 100), const Offset(200, 100), centre: const Offset(150, 60));
    expect(below.mid.dy, greaterThan(100));
    final level = SkyThread(const Offset(100, 100), const Offset(200, 100), centre: const Offset(150, 100));
    expect(level.mid.dy, lessThan(100));
  });

  test('the heartbeat is a lub then a softer dub, and quiet until the next beat', () {
    expect(skyBeatEnvelope(0), 0);
    expect(skyBeatEnvelope(90), closeTo(1, 1e-9));
    expect(skyBeatEnvelope(200), lessThan(1));
    expect(skyBeatEnvelope(260), closeTo(0.55, 0.01));
    expect(skyBeatEnvelope(300), lessThan(0.55));
    expect(skyBeatEnvelope(600), 0);
    expect(skyBeatEnvelope(1100), 0);
    expect(skyBeatEnvelope(-5), 0);
  });

  test('the invitation sits under the moon, kept inside the sky, and under the sun by day', () {
    final night = SkyTogetherSpot.lineRect(const Size(165, 18), night: true);
    expect(night.top, 162);
    expect(night.right, 372);
    final day = SkyTogetherSpot.lineRect(const Size(150, 18), night: false);
    expect(day.top, 148);
    expect(day.center.dx, closeTo(278, 0.01));
    final wide = SkyTogetherSpot.lineRect(const Size(400, 18), night: true);
    expect(wide.left, 18);
  });

  test('when big text brings the title down to the line, the line keeps to the moon side of the title', () {
    expect(SkyTogetherSpot.lineStart(topBarBottom: null, night: true), SkyTogetherSpot.lineMin);
    expect(SkyTogetherSpot.lineStart(topBarBottom: 118, titleEdge: 300, night: true), SkyTogetherSpot.lineMin);
    expect(SkyTogetherSpot.lineStart(topBarBottom: 189, titleEdge: 207, night: true), 207 + SkyTogetherSpot.lineGap);
    expect(SkyTogetherSpot.lineStart(topBarBottom: 189, night: true), SkyTogetherSpot.lineColumn);
    expect(SkyTogetherSpot.lineStart(topBarBottom: 146, titleEdge: 150, night: false), 150 + SkyTogetherSpot.lineGap);
    expect(
      SkyTogetherSpot.lineStart(topBarBottom: 260, titleEdge: 305, night: true),
      SkyTogetherSpot.lineMax - SkyTogetherSpot.lineNarrowest,
    );
    expect(SkyTogetherSpot.lineLines(SkyTogetherSpot.lineMin), 2);
    expect(SkyTogetherSpot.lineLines(219), 3);
    final kept = SkyTogetherSpot.lineRect(const Size(300, 54), night: true, start: 219);
    expect(kept.left, 219);
    expect(SkyTogetherSpot.lineRect(const Size(120, 18), night: true, start: 219).center.dx, closeTo(306, 0.01));
  });

  test('each stage of the gate says the right gentle line', () {
    String? line(SkyTogetherStage stage, {bool night = true}) =>
        SkyTogetherLine.textFor(stage, night: night, partner: 'Alex');
    expect(line(SkyTogetherStage.off), isNull);
    expect(line(SkyTogetherStage.invite), 'Hold the moon together');
    expect(line(SkyTogetherStage.invite, night: false), 'Hold the sun together');
    expect(line(SkyTogetherStage.partnerHolding), 'Hold the moon together');
    expect(line(SkyTogetherStage.alone), 'Waiting for Alex to hold on too');
    expect(line(SkyTogetherStage.together), "You're both holding on");
    expect(line(SkyTogetherStage.opening), "You're both holding on");
  });

  test('every word the two of them read stays warm and plain', () {
    final copy = [
      SkyTogetherCopy.hold(true),
      SkyTogetherCopy.hold(false),
      SkyTogetherCopy.waiting('Alex'),
      SkyTogetherCopy.bothHolding,
      SkyTogetherCopy.intoPatch,
      SkyTogetherCopy.holdLabel(true, 'Alex'),
      SkyTogetherCopy.holdHint('Alex'),
      SkyTogetherCopy.holdingOn,
      SkyTogetherCopy.patchKicker(night: true, dayNumber: 28),
      SkyTogetherCopy.patchKicker(night: false),
      SkyTogetherCopy.drawingWith('Alex'),
      SkyTogetherCopy.drawTitle,
      SkyTogetherCopy.leave,
      SkyTogetherCopy.help,
      SkyTogetherCopy.starsLeft(3),
      SkyTogetherCopy.starsLeft(1),
      SkyTogetherCopy.fullOfStars,
      SkyTogetherCopy.noRoomForLines,
      SkyTogetherCopy.startOver,
      SkyTogetherCopy.done,
      SkyTogetherCopy.startOverTitle,
      SkyTogetherCopy.startOverMessage,
      SkyTogetherCopy.keepDrawing,
      SkyTogetherCopy.startedOver('Alex'),
      SkyTogetherCopy.steppedAway('Alex'),
      SkyTogetherCopy.steppedAwayMessage(true),
      SkyTogetherCopy.steppedAwayMessage(false),
      SkyTogetherCopy.backToSky,
      SkyTogetherCopy.patchLabel(stars: 1, lines: 0),
      SkyTogetherCopy.patchLabel(stars: 3, lines: 2),
      SkyTogetherCopy.addStar,
      SkyTogetherCopy.joinNewest,
      SkyTogetherCopy.yourStar,
      SkyTogetherCopy.partnerStar('Alex'),
      SkyTogetherCopy.nameKicker(night: true, dayNumber: 28),
      SkyTogetherCopy.nameTitle,
      SkyTogetherCopy.backToDrawing,
      SkyTogetherCopy.nameLabel,
      SkyTogetherCopy.nameHint,
      SkyTogetherCopy.seesIt('Alex'),
      SkyTogetherCopy.waitingYes('Alex'),
      SkyTogetherCopy.naming('Alex'),
      SkyTogetherCopy.sayYes,
      SkyTogetherCopy.changeIt,
      SkyTogetherCopy.yes,
      SkyTogetherCopy.saved,
    ];
    final emoji = RegExp(r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]', unicode: true);
    for (final line in copy) {
      expect(technical.hasMatch(line), isFalse, reason: line);
      expect(emoji.hasMatch(line), isFalse, reason: line);
    }
    expect(SkyTogetherCopy.patchKicker(night: true, dayNumber: 28), 'Night 28 · our own patch of sky');
    expect(SkyTogetherCopy.patchKicker(night: false), 'Today · our own patch of sky');
    expect(SkyTogetherCopy.nameKicker(night: false, dayNumber: 3), 'Day 3 · drawn together');
    expect(
      SkyTogetherCopy.steppedAwayMessage(false),
      'Your drawing stays just as it is. Hold the sun together to pick it up again.',
    );
    expect(SkyTogetherCopy.helpParts, hasLength(3));
  });
}
