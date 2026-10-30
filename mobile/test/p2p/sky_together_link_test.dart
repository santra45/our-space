import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine/p2p/sky_together_link.dart';
import 'package:our_space_mobile/core/engine/p2p/sky_together_wire.dart';
import 'package:our_space_mobile/models/sky_drawing_record.dart';

import '../support/fake_sky_together.dart';

const Duration ms20 = Duration(milliseconds: 20);

Future<void> drain() => Future<void>.delayed(Duration.zero);

List<SkyTogetherEvent> heard(SkyTogetherLink link) {
  final out = <SkyTogetherEvent>[];
  link.events.listen(out.add);
  return out;
}

SkyDrawnStar star(String id, double x, double y, {String by = 'owner-aaaa1111', int at = 1760000000000}) =>
    SkyDrawnStar(id: id, x: x, y: y, by: by, at: at, gen: 0);

void main() {
  test('once the link is up both phones see each other here, and the smaller owner id leads', () {
    final pair = FakeSkyPair();
    pair.settle();

    expect(pair.a.linked && pair.b.linked, isTrue);
    expect(pair.a.partnerHere, isTrue);
    expect(pair.b.partnerHere, isTrue);
    expect(pair.a.together && pair.b.together, isTrue);
    expect(pair.a.partnerSpeaksSky && pair.b.partnerSpeaksSky, isTrue);
    expect(pair.a.partnerOwner, 'owner-bbbb2222');
    expect(pair.b.partnerOwner, 'owner-aaaa1111');
    expect(pair.a.isLeader, isTrue);
    expect(pair.b.isLeader, isFalse);
    pair.dispose();
  });

  test('day or night travels with presence, and a change is announced at once', () {
    final pair = FakeSkyPair();
    pair.settle();
    expect(pair.a.partnerNight, isFalse);

    var notified = 0;
    pair.a.addListener(() => notified++);
    pair.b.setPresence(night: true);
    pair.flush();
    expect(pair.a.partnerNight, isTrue);
    expect(notified, greaterThan(0));
    expect(pair.b.night, isTrue);
    pair.dispose();
  });

  test('presence goes quiet about eight seconds after the last heartbeat, then comes back', () {
    final pair = FakeSkyPair();
    pair.settle();
    pair.transportB.refuse = true;
    final quietFrom = pair.a.lastPresenceAt;

    pair.advance(const Duration(milliseconds: 7000));
    expect(pair.a.partnerHere, isTrue);
    pair.advance(const Duration(milliseconds: 1100));
    expect(pair.clockA.now() - quietFrom, greaterThanOrEqualTo(SkyTogetherLink.staleMs));
    expect(pair.a.partnerHere, isFalse);
    expect(pair.a.together, isFalse);
    expect(pair.a.linked, isTrue);

    pair.transportB.refuse = false;
    pair.advance(const Duration(milliseconds: SkyTogetherLink.beatMs));
    expect(pair.a.partnerHere, isTrue);
    pair.dispose();
  });

  test('a goodbye turns presence off at once, and the background counts as gone', () {
    final pair = FakeSkyPair();
    pair.settle();

    pair.b.setForeground(false);
    pair.flush();
    expect(pair.b.here, isFalse);
    expect(pair.a.partnerHere, isFalse);
    expect(pair.a.linked, isTrue);

    pair.b.setForeground(true);
    pair.flush();
    expect(pair.a.partnerHere, isTrue);

    pair.b.setPresence(here: false);
    pair.flush();
    expect(pair.a.partnerHere, isFalse);
    pair.b.setPresence(here: true);
    pair.flush();
    expect(pair.a.partnerHere, isTrue);
    pair.dispose();
  });

  test('when the link drops presence turns off at once, and nothing waits to be sent later', () async {
    final pair = FakeSkyPair();
    pair.settle();
    final toB = heard(pair.b);

    pair.drop();
    expect(pair.a.linked, isFalse);
    expect(pair.a.partnerHere, isFalse);
    expect(pair.a.partnerSpeaksSky, isFalse);
    expect(pair.b.partnerHere, isFalse);

    final sentBefore = pair.transportA.sent.length;
    expect(await pair.a.sendOpen('sky-one', at: 1), isFalse);
    expect(await pair.a.sendOp('sky-one', SkyStartOver(1)), isFalse);
    expect(await pair.a.sendName('sky-one', 'Our kite'), isFalse);
    pair.a.sendCursor(0.5, 0.5);
    pair.a.sendHold(down: true);
    expect(pair.transportA.sent.length, sentBefore);

    pair.connect();
    pair.settle();
    await drain();
    expect(pair.a.partnerHere && pair.b.partnerHere, isTrue);
    expect(toB.whereType<SkyPresenceEvent>(), isNotEmpty);
    expect(toB.where((e) => e is! SkyPresenceEvent), isEmpty);
    pair.dispose();
  });

  test('a message caught in flight when the link drops is lost, not delivered after it comes back', () async {
    final pair = FakeSkyPair(latency: const Duration(milliseconds: 80));
    pair.settle();
    final toB = heard(pair.b);

    expect(await pair.a.sendSaved('sky-one'), isTrue);
    pair.advance(const Duration(milliseconds: 30));
    pair.drop();
    pair.connect();
    pair.settle();
    await drain();
    expect(toB.whereType<SkySavedEvent>(), isEmpty);
    pair.dispose();
  });

  test('the shared clock agrees on both phones even when their clocks are far apart', () {
    final pair = FakeSkyPair(offsetB: 93457, latency: const Duration(milliseconds: 40));
    expect(pair.a.sharedNow() - pair.b.sharedNow(), -93457);

    pair.settle(rounds: 50);
    expect(pair.a.samples.length, greaterThanOrEqualTo(SkyTogetherLink.wantedSamples));
    expect(pair.b.samples.length, greaterThanOrEqualTo(SkyTogetherLink.wantedSamples));
    expect(pair.a.clockOffset, 93457);
    expect(pair.b.clockOffset, -93457);
    expect(pair.a.roundTrip, 80);
    expect(pair.sharedGap, lessThanOrEqualTo(1));
    expect(pair.a.sharedNow(), pair.timeline.now() + 46728);
    expect(pair.a.toLocal(pair.a.toShared(123456)), 123456);
    expect(pair.b.toShared(pair.clockB.now()), pair.b.sharedNow());
    pair.dispose();
  });

  test('the shared clock holds steady when the link gets slower', () {
    final pair = FakeSkyPair(offsetA: -5000, offsetB: 12000, latency: const Duration(milliseconds: 15));
    pair.settle(rounds: 50);
    expect(pair.sharedGap, lessThanOrEqualTo(1));
    pair.latency = const Duration(milliseconds: 120);
    pair.advance(const Duration(seconds: 30));
    expect(pair.a.roundTrip, 240);
    expect(pair.sharedGap, lessThanOrEqualTo(1));
    pair.dispose();
  });

  test('presence asks for quick echoes until the clock is known, then settles into a slow heartbeat', () {
    final pair = FakeSkyPair(latency: const Duration(milliseconds: 30));
    pair.advance(const Duration(milliseconds: 1500));
    final early = pair.transportA.sentOf('presence').length;
    expect(early, greaterThanOrEqualTo(SkyTogetherLink.wantedSamples));
    expect(early, lessThanOrEqualTo(8));
    expect(pair.transportA.sentOf('presence').last['sync'], isNull);

    pair.advance(const Duration(seconds: 30));
    final later = pair.transportA.sentOf('presence').length - early;
    expect(later, inInclusiveRange(9, 11));
    pair.dispose();
  });

  test('comet positions go out about twenty times a second and the last one always lands', () async {
    final pair = FakeSkyPair();
    pair.settle();
    final toB = heard(pair.b);
    final start = pair.transportA.sentOf('cursor').length;

    for (var i = 0; i <= 100; i++) {
      pair.a.sendCursor(i / 100, 1 - i / 100);
      pair.advance(const Duration(milliseconds: 10));
    }
    pair.advance(const Duration(milliseconds: 200));
    await drain();

    final sent = pair.transportA.sentOf('cursor').length - start;
    expect(sent, inInclusiveRange(18, 22));
    final comets = toB.whereType<SkyCursorEvent>().toList();
    expect(comets.length, sent);
    expect(comets.last.x, 1.0);
    expect(comets.last.y, 0.0);
    expect(comets.last.down, isTrue);
    pair.dispose();
  });

  test('hiding the comet drops a waiting position and says it is gone', () async {
    final pair = FakeSkyPair();
    pair.settle();
    final toB = heard(pair.b);

    pair.a.sendCursor(0.2, 0.2);
    pair.a.sendCursor(0.3, 0.3);
    expect(await pair.a.hideCursor(), isTrue);
    pair.settle();
    await drain();

    final comets = toB.whereType<SkyCursorEvent>().toList();
    expect(comets.first.x, 0.2);
    expect(comets.last.gone, isTrue);
    expect(comets.where((c) => c.x == 0.3), isEmpty);
    pair.dispose();
  });

  test('every kind of event arrives in order and the same as it left', () async {
    final pair = FakeSkyPair();
    pair.settle();
    final toB = heard(pair.b);

    final hold = pair.a.sendHold(down: true);
    expect(hold.seq, 1);
    final release = pair.a.sendHold(down: false);
    expect(release.seq, 1);
    expect(pair.a.sendHold(down: true).seq, 2);
    final drawing = SkyDrawing(stars: [star('s-1', 0.25, 0.5), star('s-2', 0.75, 0.5)]);
    final op = drawing.join('s-1', 's-2', by: 'owner-aaaa1111', at: 1760000000100)!;
    await pair.a.sendOpen('sky-one', at: 1760000010000);
    await pair.a.sendOp('sky-one', op);
    await pair.a.sendState('sky-one', drawing.apply(op));
    await pair.a.sendName('sky-one', 'Our kite ');
    await pair.a.sendName('sky-one', '', take: true);
    await pair.a.sendAgree('sky-one', '  Our   kite ');
    await pair.a.sendSaved('sky-one');
    await pair.a.sendClose('sky-one');
    pair.flush();
    await drain();

    final kinds = [for (final e in toB) if (e is! SkyPresenceEvent) e.kind];
    expect(kinds, ['hold', 'hold', 'hold', 'open', 'op', 'state', 'name', 'name', 'agree', 'saved', 'close']);
    final events = [for (final e in toB) if (e is! SkyPresenceEvent) e];
    expect(events[0], hold);
    expect(events[1], release);
    expect((events[3] as SkyOpenEvent).at, 1760000010000);
    expect((events[4] as SkyOpEvent).op, op);
    expect((events[5] as SkyStateEvent).state, drawing.apply(op));
    expect((events[6] as SkyNameEvent).text, 'Our kite ');
    expect((events[6] as SkyNameEvent).clean, 'Our kite');
    expect((events[6] as SkyNameEvent).rev, 1);
    expect((events[6] as SkyNameEvent).take, isFalse);
    expect(pair.transportA.sentOf('name').first.containsKey('take'), isFalse);
    expect((events[7] as SkyNameEvent).take, isTrue);
    expect((events[7] as SkyNameEvent).rev, 2);
    expect((events[8] as SkyAgreeEvent).text, 'Our kite');
    expect((events[9] as SkySavedEvent).drawing, 'sky-one');
    pair.dispose();
  });

  test('a typed name is never cut through the middle of a character, however many emoji it holds', () async {
    final pair = FakeSkyPair();
    pair.settle();
    final toB = heard(pair.b);
    const family = '\u{1F468}‍\u{1F469}‍\u{1F467}‍\u{1F466}';
    await pair.a.sendName('sky-one', family * 30);
    await pair.a.sendName('sky-one', 'Kite\uD83D');
    pair.flush();
    await drain();
    final names = [for (final e in toB) if (e is SkyNameEvent) e.text];
    expect(names, hasLength(2));
    expect(names.first.length, lessThanOrEqualTo(maxSkyTypedUnits));
    expect(skyHasLoneSurrogate(names.first), isFalse);
    expect(names.first.startsWith(family * 11), isTrue);
    expect(names.last, 'Kite');
    pair.dispose();
  });

  test('drawing events wait until the partner has spoken this language, so the website never gets them', () async {
    final pair = FakeSkyPair(ownerB: null);
    pair.settle();

    expect(pair.b.partnerSpeaksSky, isTrue);
    expect(pair.a.partnerSpeaksSky, isFalse);
    expect(pair.a.partnerHere, isFalse);
    expect(pair.a.isLeader, isNull);
    expect(pair.transportB.sent, isEmpty);

    expect(await pair.a.sendOpen('sky-one', at: 5), isFalse);
    pair.a.sendCursor(0.5, 0.5);
    pair.advance(const Duration(milliseconds: 100));
    expect(pair.transportA.sent.every((e) => e['k'] == 'presence'), isTrue);
    expect(pair.transportA.sent, isNotEmpty);

    pair.ownerB = 'owner-bbbb2222';
    pair.advance(const Duration(milliseconds: SkyTogetherLink.beatMs));
    expect(pair.a.partnerSpeaksSky, isTrue);
    expect(await pair.a.sendOpen('sky-one', at: 5), isTrue);
    pair.dispose();
  });

  test('a touch carries nothing but itself, and a touch with anything more in it is dropped', () async {
    final pair = FakeSkyPair();
    pair.settle();
    final toB = heard(pair.b);
    expect(await pair.a.sendTouch(), isTrue);
    pair.flush();
    pair.inject(pair.b, {'v': 1, 'k': 'touch', 'x': 0.5});
    pair.inject(pair.b, {'v': 1, 'k': 'touch', 'from': 'owner-aaaa1111'});
    pair.inject(pair.b, {'v': 2, 'k': 'touch'});
    await drain();
    expect(pair.transportA.sentOf('touch').single, {'v': 1, 'k': 'touch'});
    expect(toB.whereType<SkyTouchEvent>(), [const SkyTouchEvent()]);
    pair.dispose();
  });

  test('a touch waits until the partner has spoken this language, so the website never gets one', () async {
    final pair = FakeSkyPair(ownerB: null);
    pair.settle();
    expect(pair.a.partnerSpeaksSky, isFalse);
    expect(await pair.a.sendTouch(), isFalse);
    expect(pair.transportA.sentOf('touch'), isEmpty);
    pair.dispose();
  });

  test('the leader falls back to the random tag when both phones carry the same owner', () {
    final pair = FakeSkyPair(ownerA: 'owner-same0000', ownerB: 'owner-same0000');
    pair.settle();
    expect(pair.a.isLeader, isTrue);
    expect(pair.b.isLeader, isFalse);
    pair.dispose();
  });

  test('anything malformed is dropped without a sound, and the good one still passes', () async {
    final pair = FakeSkyPair();
    pair.settle();
    final toB = heard(pair.b);
    final base = {'v': 1, 'k': 'cursor', 'x': 0.5, 'y': 0.5, 'down': true};
    final bad = <Object?>[
      null,
      'cursor',
      42,
      const [1, 2],
      {...base, 'v': 2},
      {...base, 'v': '1'},
      {...base, 'v': 1.0},
      {...base, 'k': 'teleport'},
      {...base, 'x': 1.5},
      {...base, 'y': -0.1},
      {...base, 'x': double.nan},
      {...base, 'x': double.infinity},
      {...base, 'x': '0.5'},
      {...base, 'down': 'yes'},
      {...base, 'gone': true},
      {'v': 1, 'k': 'cursor', 'gone': 'yes'},
      {...base, for (var i = 0; i < 12; i++) 'pad$i': i},
      {'v': 1, 'k': 'hold', 'down': true, 'at': -1, 'seq': 1},
      {'v': 1, 'k': 'hold', 'down': true, 'at': 1.5, 'seq': 1},
      {'v': 1, 'k': 'hold', 'down': true, 'at': 10, 'seq': -3},
      {'v': 1, 'k': 'hold', 'down': 1, 'at': 10, 'seq': 3},
      {'v': 1, 'k': 'open', 'drawing': 'has space', 'at': 10},
      {'v': 1, 'k': 'open', 'drawing': 'x' * 49, 'at': 10},
      {'v': 1, 'k': 'open', 'drawing': '', 'at': 10},
      {'v': 1, 'k': 'open', 'drawing': 'sky-1', 'at': 9007199254740993},
      {'v': 1, 'k': 'saved', 'drawing': 'sky/1'},
      {'v': 1, 'k': 'close'},
      {'v': 1, 'k': 'name', 'drawing': 'sky-1', 'text': 'x' * (maxSkyTypedUnits + 1), 'rev': 1},
      {'v': 1, 'k': 'name', 'drawing': 'sky-1', 'text': 7, 'rev': 1},
      {'v': 1, 'k': 'name', 'drawing': 'sky-1', 'text': 'Kite', 'rev': 1, 'take': 'yes'},
      {'v': 1, 'k': 'name', 'drawing': 'sky-1', 'text': 'Kite\uD83D', 'rev': 1},
      {'v': 1, 'k': 'name', 'drawing': 'sky-1', 'text': '\uDC97Kite', 'rev': 1},
      {'v': 1, 'k': 'agree', 'drawing': 'sky-1', 'text': 'Our kite\uD83D'},
      {'v': 1, 'k': 'agree', 'drawing': 'sky-1', 'text': '   '},
      {'v': 1, 'k': 'op', 'drawing': 'sky-1', 'op': {'o': 'clear', 'g': 0}},
      {'v': 1, 'k': 'op', 'drawing': 'sky-1', 'op': {'o': 'warp', 'g': 1}},
      {'v': 1, 'k': 'op', 'drawing': 'sky-1', 'op': {'o': 'remove', 'ids': [], 'g': 0}},
      {'v': 1, 'k': 'op', 'drawing': 'sky-1', 'op': {'o': 'remove', 'ids': List.filled(9, 's-1'), 'g': 0}},
      {
        'v': 1,
        'k': 'op',
        'drawing': 'sky-1',
        'op': {
          'o': 'star',
          'star': {'id': 's-1', 'x': 0.5, 'y': 0.5, 'by': 'short', 'at': 1, 'g': 0},
        },
      },
      {
        'v': 1,
        'k': 'op',
        'drawing': 'sky-1',
        'op': {
          'o': 'line',
          'line': {'a': 's-1', 'b': 's-1', 'by': 'owner-aaaa1111', 'at': 1, 'g': 0},
        },
      },
      {
        'v': 1,
        'k': 'state',
        'drawing': 'sky-1',
        'state': {
          'g': 0,
          'stars': [
            for (var i = 0; i <= skyDrawingKeptStars; i++)
              {'id': 's-$i', 'x': 0.5, 'y': 0.5, 'by': 'owner-aaaa1111', 'at': i, 'g': 0},
          ],
          'lines': [],
          'removed': [],
        },
      },
      {
        'v': 1,
        'k': 'state',
        'drawing': 'sky-1',
        'state': {
          'g': 1,
          'stars': [
            {'id': 's-1', 'x': 0.5, 'y': 0.5, 'by': 'owner-aaaa1111', 'at': 1, 'g': 0},
          ],
        },
      },
      {'v': 1, 'k': 'presence', 'here': true, 'night': false, 'owner': 'owner-bbbb2222', 'tag': 'tag-x', 't': 5, 'echo': 4},
      {
        'v': 1,
        'k': 'presence',
        'here': true,
        'night': false,
        'owner': 'owner-bbbb2222',
        'tag': 'tag-x',
        't': 5,
        'echo': 4,
        'held': maxSkyHeldMs + 1,
      },
      {'v': 1, 'k': 'presence', 'here': 'yes', 'night': false, 'owner': 'owner-bbbb2222', 'tag': 'tag-x', 't': 5},
      {'v': 1, 'k': 'presence', 'here': true, 'night': false, 'owner': 'owner-bbbb2222', 'tag': 'x', 't': 5},
    ];
    for (final raw in bad) {
      pair.inject(pair.b, raw);
    }
    pair.inject(pair.b, base);
    await drain();

    expect(toB, [const SkyCursorEvent(x: 0.5, y: 0.5)]);
    expect(pair.b.partnerHere, isTrue);
    expect(pair.b.partnerOwner, 'owner-aaaa1111');
    pair.dispose();
  });

  test('a goodbye goes out when the link is put away, and the heartbeat stops', () {
    final pair = FakeSkyPair();
    pair.settle();
    pair.a.dispose();
    expect(pair.transportA.attached, isFalse);
    expect(pair.transportA.sent.last['here'], isFalse);
    final sent = pair.transportA.sent.length;
    pair.flush();
    expect(pair.b.partnerHere, isFalse);

    pair.advance(const Duration(seconds: 10));
    expect(pair.transportA.sent.length, sent);
    pair.b.dispose();
  });

  test('a listener hears each change of who is here', () async {
    final pair = FakeSkyPair(connected: false);
    final changes = <bool>[];
    pair.a.addListener(() => changes.add(pair.a.partnerHere));
    expect(pair.a.linked, isFalse);
    expect(pair.a.partnerHere, isFalse);

    pair.connect();
    pair.settle();
    expect(changes.last, isTrue);
    pair.drop();
    expect(changes.last, isFalse);
    pair.dispose();
  });
}
