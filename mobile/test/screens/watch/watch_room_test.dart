import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/presentation/screens/watch/watch_player.dart';
import 'package:our_space_mobile/presentation/screens/watch/watch_room.dart';

import '../../support/fake_sky_together.dart';
import 'support/fake_watch_player.dart';

const String movie = 'https://example.com/movies/our-film.mp4';
const String other = 'https://example.com/movies/other-film.m3u8';

class Couch {
  Couch({FakeSkyPair? pair, this.makePlayer})
    : pair = pair ?? FakeSkyPair(offsetB: 2500, latency: const Duration(milliseconds: 40)) {
    WatchPlayers.create = () {
      final player = makePlayer?.call() ?? FakeWatchPlayer();
      made.add(player);
      return player;
    };
    a = WatchRoom(link: this.pair.a, tickEvery: null, onWatched: keptA.add);
    b = WatchRoom(link: this.pair.b, tickEvery: null, onWatched: keptB.add);
  }

  final FakeSkyPair pair;
  final FakeWatchPlayer Function()? makePlayer;
  final List<FakeWatchPlayer> made = [];
  final List<WatchedFilm> keptA = [];
  final List<WatchedFilm> keptB = [];
  late final WatchRoom a;
  late final WatchRoom b;

  FakeWatchPlayer get playerA => a.player! as FakeWatchPlayer;

  FakeWatchPlayer get playerB => b.player! as FakeWatchPlayer;

  Future<void> meet() async {
    pair.settle();
    await pumpEventQueue();
    pair.settle();
    await pumpEventQueue();
  }

  Future<void> step([int ms = 100]) async {
    pair.advance(Duration(milliseconds: ms));
    for (final player in made) {
      if (!player.disposed) player.run(ms);
    }
    await pumpEventQueue();
    await a.tick();
    await b.tick();
    await pumpEventQueue();
  }

  Future<void> run(int ms, {int every = 100}) async {
    for (var left = ms; left > 0; left -= every) {
      await step(every);
    }
  }

  Future<void> together() async {
    await meet();
    expect(a.start(movie), isTrue);
    await run(200);
    b.join();
    await run(600);
    expect(a.partnerIn, isTrue);
    expect(b.partnerIn, isTrue);
  }

  Future<void> dispose() async {
    a.dispose();
    b.dispose();
    await pumpEventQueue();
    pair.dispose();
  }
}

void main() {
  tearDown(() => WatchPlayers.create = NativeWatchPlayer.new);

  group('starting and joining', () {
    test('only a real https link can start, and nothing goes out for a bad one', () async {
      final couch = Couch();
      await couch.meet();
      for (final bad in ['', 'not a link', 'http://example.com/a.mp4', 'file:///a.mp4', 'https://', 'https://a b/c']) {
        expect(couch.a.start(bad), isFalse, reason: bad);
      }
      expect(couch.a.inRoom, isFalse);
      expect(couch.pair.transportA.sentOf('watch'), isEmpty);
      await couch.dispose();
    });

    test('the partner is asked first, and their phone touches the link only after they say yes', () async {
      final couch = Couch();
      await couch.meet();
      expect(couch.a.start('  $movie  '), isTrue);
      expect(couch.a.url, movie);
      expect(couch.playerA.url, movie);
      await couch.run(200);
      expect(couch.b.invited, isTrue);
      expect(couch.b.url, movie);
      expect(couch.b.player, isNull);
      expect(couch.made, hasLength(1));

      couch.b.join();
      await couch.run(300);
      expect(couch.b.invited, isFalse);
      expect(couch.playerB.url, movie);
      expect(couch.a.partnerIn, isTrue);
      await couch.dispose();
    });

    test('not now hides the note, but they can still join from the screen', () async {
      final couch = Couch();
      await couch.meet();
      couch.a.start(movie);
      await couch.run(200);
      couch.b.decline();
      expect(couch.b.invited, isFalse);
      expect(couch.b.offered, isTrue);
      await couch.run(WatchRoom.offerMs + 1000);
      expect(couch.b.invited, isFalse);
      expect(couch.b.offered, isTrue);
      couch.b.join();
      await couch.run(200);
      expect(couch.b.inRoom, isTrue);
      await couch.dispose();
    });

    test('a partner who opens the app later still gets the invitation', () async {
      final couch = Couch(pair: FakeSkyPair(connected: false));
      couch.a.start(movie);
      expect(couch.a.inRoom, isTrue);
      expect(couch.b.invited, isFalse);
      couch.pair.connect();
      await couch.meet();
      await couch.run(WatchRoom.offerMs + 500);
      expect(couch.b.invited, isTrue);
      await couch.dispose();
    });

    test('a phone that restarted with a lower count can still start a room', () async {
      final couch = Couch();
      await couch.meet();
      couch.a.start(movie);
      await couch.run(200);
      couch.a.leave();
      await couch.run(200);
      expect(couch.b.url, isNull);
      final fresh = WatchRoom(link: couch.pair.a, tickEvery: null);
      couch.a.dispose();
      fresh.start(other);
      await couch.run(200);
      expect(couch.b.invited, isTrue);
      expect(couch.b.url, other);
      fresh.dispose();
      couch.b.dispose();
      couch.pair.dispose();
    });

    test('nothing is sent until the other phone speaks this language, so the website never hears it', () async {
      final couch = Couch(pair: FakeSkyPair(ownerB: null));
      await couch.meet();
      expect(couch.pair.a.partnerSpeaksSky, isFalse);
      couch.a.start(movie);
      await couch.run(WatchRoom.offerMs + 1000);
      expect(couch.pair.transportA.sentOf('watch'), isEmpty);
      expect(couch.pair.transportA.sentOf('watchbeat'), isEmpty);
      expect(couch.a.inRoom, isTrue);
      await couch.dispose();
    });
  });

  group('staying in step', () {
    test('play on one phone starts both, and they stay together even with clocks far apart', () async {
      final couch = Couch();
      await couch.together();
      couch.a.togglePlay();
      await couch.run(800);
      expect(couch.playerA.isPlaying, isTrue);
      expect(couch.playerB.isPlaying, isTrue);
      for (var i = 0; i < 20; i++) {
        await couch.run(500);
        expect((couch.playerA.positionNow - couch.playerB.positionNow).abs(), lessThan(WatchRoom.nudgeOverMs + 120));
      }
      expect(couch.playerA.positionNow, greaterThan(9000));
      await couch.dispose();
    });

    test('pause on either phone stops both at the same moment', () async {
      final couch = Couch();
      await couch.together();
      couch.a.togglePlay();
      await couch.run(3000);
      couch.b.togglePlay();
      await couch.run(600);
      expect(couch.a.playing, isFalse);
      expect(couch.playerA.isPlaying, isFalse);
      expect(couch.playerB.isPlaying, isFalse);
      final stopped = couch.playerB.positionNow;
      expect((couch.playerA.positionNow - stopped).abs(), lessThanOrEqualTo(WatchRoom.restOverMs + 100));
      await couch.run(2000);
      expect(couch.playerB.positionNow, stopped);
      await couch.dispose();
    });

    test('a seek on one phone moves the other, playing or paused', () async {
      final couch = Couch();
      await couch.together();
      couch.a.seek(120000);
      await couch.run(600);
      expect(couch.playerA.positionNow, 120000);
      expect(couch.playerB.positionNow, 120000);
      couch.a.togglePlay();
      await couch.run(2000);
      couch.b.seek(600000);
      await couch.run(1200);
      expect((couch.playerA.positionNow - 600000).abs(), lessThan(2000));
      expect((couch.playerA.positionNow - couch.playerB.positionNow).abs(), lessThan(400));
      await couch.dispose();
    });

    test('a small drift is eased back with a tiny change of speed, and then it stops', () async {
      final couch = Couch();
      await couch.together();
      couch.a.togglePlay();
      await couch.run(1500);
      couch.playerB.positionNow += 600;
      await couch.run(300);
      expect(couch.playerB.speed, 1 - WatchRoom.nudge);
      expect(couch.playerB.seeks, isEmpty);
      await couch.run(30000);
      expect(couch.playerB.speed, 1);
      expect((couch.playerA.positionNow - couch.playerB.positionNow).abs(), lessThan(WatchRoom.nudgeOverMs + 120));
      await couch.dispose();
    });

    test('a big gap is closed with a jump', () async {
      final couch = Couch();
      await couch.together();
      couch.a.togglePlay();
      await couch.run(1500);
      couch.playerB.positionNow += 20000;
      await couch.run(300);
      expect(couch.playerB.seeks, isNotEmpty);
      expect((couch.playerA.positionNow - couch.playerB.positionNow).abs(), lessThan(600));
      await couch.dispose();
    });

    test('a short stumble does not stop anyone', () async {
      final couch = Couch();
      await couch.together();
      couch.a.togglePlay();
      await couch.run(1000);
      couch.playerB.isBuffering = true;
      await couch.run(300);
      couch.playerB.isBuffering = false;
      await couch.run(300);
      expect(couch.a.held, isFalse);
      expect(couch.playerA.isPlaying, isTrue);
      await couch.dispose();
    });

    test('a long stall holds both phones, and both go on from the same place when it clears', () async {
      final couch = Couch();
      await couch.together();
      couch.a.togglePlay();
      await couch.run(4000);
      couch.playerB.isBuffering = true;
      await couch.run(WatchRoom.waitAfterMs + 400);
      expect(couch.a.held, isTrue);
      expect(couch.a.partnerWaiting, isTrue);
      expect(couch.playerA.isPlaying, isFalse);
      expect(couch.playerB.isPlaying, isFalse);
      final held = couch.playerB.positionNow;
      await couch.run(5000);
      expect(couch.a.held, isTrue);
      couch.playerB.isBuffering = false;
      await couch.run(900);
      expect(couch.a.held, isFalse);
      expect(couch.b.held, isFalse);
      expect(couch.playerA.isPlaying, isTrue);
      expect(couch.playerB.isPlaying, isTrue);
      expect((couch.playerA.positionNow - couch.playerB.positionNow).abs(), lessThan(400));
      expect((couch.playerB.positionNow - held).abs(), lessThan(1500));
      await couch.dispose();
    });

    test('joining a film already playing waits for the newcomer and never rewinds to the start', () async {
      final couch = Couch(makePlayer: () => FakeWatchPlayer(loadsAtOnce: false));
      await couch.meet();
      couch.a.start(movie);
      couch.playerA.finishLoading();
      await couch.run(200);
      couch.a.togglePlay();
      await couch.run(30000, every: 200);
      final before = couch.playerA.positionNow;
      expect(before, greaterThan(25000));

      couch.b.join();
      await couch.run(500);
      expect(couch.a.held, isTrue);
      expect(couch.playerA.isPlaying, isFalse);
      expect(couch.playerA.positionNow, greaterThan(before - 1000));
      await couch.run(3000);
      couch.playerB.finishLoading();
      await couch.run(1500);
      expect(couch.a.held, isFalse);
      expect(couch.playerB.positionNow, greaterThan(before - 1000));
      expect((couch.playerA.positionNow - couch.playerB.positionNow).abs(), lessThan(400));
      await couch.dispose();
    });

    test('a phone that cannot play the link says so and holds nobody back', () async {
      final made = <FakeWatchPlayer>[];
      final couch = Couch(
        makePlayer: () {
          final player = FakeWatchPlayer(failsToLoad: made.isNotEmpty);
          made.add(player);
          return player;
        },
      );
      await couch.together();
      expect(couch.playerB.failed, isTrue);
      await couch.run(WatchRoom.beatMs + 200);
      expect(couch.a.partnerFailed, isTrue);
      expect(couch.a.partnerWaiting, isFalse);
      couch.a.togglePlay();
      await couch.run(1000);
      expect(couch.a.held, isFalse);
      expect(couch.playerA.isPlaying, isTrue);
      await couch.dispose();
    });

    test('at the end both stop, and play starts over from the top', () async {
      final couch = Couch(makePlayer: () => FakeWatchPlayer(durationMs: 5000));
      await couch.together();
      couch.a.togglePlay();
      await couch.run(6000);
      expect(couch.a.playing, isFalse);
      expect(couch.b.playing, isFalse);
      couch.b.togglePlay();
      await couch.run(1500);
      expect(couch.a.playing, isTrue);
      expect(couch.playerA.positionNow, lessThan(2500));
      expect(couch.playerB.positionNow, lessThan(2500));
      await couch.dispose();
    });

    test('a live video is played and paused together but never jumped or sped up', () async {
      final couch = Couch(makePlayer: () => FakeWatchPlayer()..isLive = true);
      await couch.together();
      couch.a.togglePlay();
      await couch.run(1000);
      couch.playerB.positionNow += 50000;
      await couch.run(2000);
      expect(couch.playerB.isPlaying, isTrue);
      expect(couch.playerB.seeks, isEmpty);
      expect(couch.playerB.speeds, isEmpty);
      await couch.dispose();
    });
  });

  group('saying what the partner did', () {
    test('play, pause, a jump, arriving and leaving are each said once, and a stall says nothing', () async {
      final couch = Couch();
      await couch.meet();
      couch.a.start(movie);
      await couch.run(200);
      expect(couch.a.noticeCount, 0);
      couch.b.join();
      await couch.run(600);
      expect(couch.a.notice, WatchNotice.joined);
      expect(couch.a.noticeCount, 1);
      expect(couch.b.noticeCount, 0);

      couch.b.togglePlay();
      await couch.run(800);
      expect(couch.a.notice, WatchNotice.played);
      expect(couch.a.noticeCount, 2);
      expect(couch.b.noticeCount, 0);

      await couch.run(2000);
      couch.playerB.isBuffering = true;
      await couch.run(WatchRoom.waitAfterMs + 400);
      expect(couch.a.held, isTrue);
      couch.playerB.isBuffering = false;
      await couch.run(1000);
      expect(couch.a.held, isFalse);
      expect(couch.a.noticeCount, 2);

      couch.b.seek(300000);
      await couch.run(1000);
      expect(couch.a.notice, WatchNotice.moved);
      expect(couch.a.noticeCount, 3);

      couch.b.togglePlay();
      await couch.run(500);
      expect(couch.a.notice, WatchNotice.paused);
      expect(couch.a.noticeCount, 4);

      couch.b.leave();
      await couch.run(300);
      expect(couch.a.notice, WatchNotice.left);
      expect(couch.a.noticeCount, 5);
      await couch.dispose();
    });

    test('a film reaching its end is not called a pause', () async {
      final couch = Couch(makePlayer: () => FakeWatchPlayer(durationMs: 5000));
      await couch.together();
      final before = couch.b.noticeCount;
      couch.b.togglePlay();
      await couch.run(7000);
      expect(couch.a.playing, isFalse);
      expect(couch.a.notice, WatchNotice.played);
      expect(couch.b.noticeCount, before);
      await couch.dispose();
    });

    test('a partner going silent is said once', () async {
      final couch = Couch();
      await couch.together();
      final before = couch.a.noticeCount;
      couch.pair.drop();
      await couch.step();
      expect(couch.a.notice, WatchNotice.left);
      expect(couch.a.noticeCount, before + 1);
      await couch.run(WatchRoom.goneMs + 500);
      expect(couch.a.noticeCount, before + 1);
      await couch.dispose();
    });
  });

  group('reactions', () {
    test('it shows on this phone at once and on the other when it arrives, marked whose it is', () async {
      final couch = Couch();
      await couch.together();
      final onA = <WatchReactionSeen>[];
      final onB = <WatchReactionSeen>[];
      couch.a.reactions.listen(onA.add);
      couch.b.reactions.listen(onB.add);
      expect(couch.a.react(SkyReaction.heart), isTrue);
      await pumpEventQueue();
      expect(onA.single.mine, isTrue);
      expect(onA.single.reaction, SkyReaction.heart);
      expect(onB, isEmpty);
      await couch.run(100);
      expect(onB.single.mine, isFalse);
      expect(onB.single.reaction, SkyReaction.heart);
      expect(onA, hasLength(1));
      await couch.dispose();
    });

    test('mashing a button is thinned to a few a second, on the way out and on the way in', () async {
      final couch = Couch();
      await couch.together();
      final onB = <WatchReactionSeen>[];
      couch.b.reactions.listen(onB.add);
      expect(couch.a.react(SkyReaction.laugh), isTrue);
      expect(couch.a.react(SkyReaction.laugh), isFalse);
      await couch.run(100);
      expect(couch.a.react(SkyReaction.laugh), isFalse);
      await couch.run(200);
      expect(couch.a.react(SkyReaction.tear), isTrue);
      await couch.run(100);
      expect(onB.map((seen) => seen.reaction), [SkyReaction.laugh, SkyReaction.tear]);

      onB.clear();
      await couch.run(200);
      for (var i = 0; i < 10; i++) {
        couch.pair.injectEvent(couch.pair.b, const SkyWatchReactEvent(SkyReaction.wow));
      }
      await pumpEventQueue();
      expect(onB, hasLength(1));
      await couch.dispose();
    });

    test('nobody outside the room or away from the app sees or sends one', () async {
      final couch = Couch();
      await couch.meet();
      final onB = <WatchReactionSeen>[];
      couch.b.reactions.listen(onB.add);
      expect(couch.a.react(SkyReaction.heart), isFalse);
      couch.a.start(movie);
      await couch.run(200);
      expect(couch.a.react(SkyReaction.heart), isTrue);
      await couch.run(100);
      expect(onB, isEmpty);
      couch.b.join();
      await couch.run(300);
      couch.pair.b.setForeground(false);
      await couch.run(100);
      couch.pair.injectEvent(couch.pair.b, const SkyWatchReactEvent(SkyReaction.heart));
      await pumpEventQueue();
      expect(onB, isEmpty);
      await couch.dispose();
    });
  });

  group('skipping', () {
    test('it moves both phones and stops at each end of the film', () async {
      final couch = Couch(makePlayer: () => FakeWatchPlayer(durationMs: 60000));
      await couch.together();
      couch.playerA.positionNow = 30000;
      await couch.a.tick();
      couch.a.skip(WatchRoom.skipMs);
      await couch.run(600);
      expect(couch.playerA.positionNow, 40000);
      expect(couch.playerB.positionNow, 40000);
      couch.a.skip(-100000);
      await couch.run(600);
      expect(couch.playerB.positionNow, 0);
      couch.a.skip(100000);
      await couch.run(600);
      expect(couch.playerB.positionNow, 60000);
      await couch.dispose();
    });

    test('a live video cannot be skipped', () async {
      final couch = Couch(makePlayer: () => FakeWatchPlayer()..isLive = true);
      await couch.together();
      couch.a.skip(WatchRoom.skipMs);
      await couch.run(300);
      expect(couch.playerA.seeks, isEmpty);
      await couch.dispose();
    });
  });

  group('keeping the film', () {
    test('ten minutes watched together keeps it on both phones under one id, and leaving records the full time', () async {
      final couch = Couch();
      await couch.together();
      couch.a.togglePlay();
      await couch.run(WatchRoom.keepAfterMs - 60000, every: 1000);
      expect(couch.keptA, isEmpty);
      expect(couch.keptB, isEmpty);
      await couch.run(70000, every: 1000);
      expect(couch.keptA, hasLength(1));
      expect(couch.keptB, hasLength(1));
      expect(couch.keptA.single.id, couch.keptB.single.id);
      expect(couch.keptA.single.title, 'our-film');
      await couch.run(60000, every: 1000);
      expect(couch.keptA, hasLength(1));
      couch.a.leave();
      expect(couch.keptA, hasLength(2));
      expect(couch.keptA.last.id, couch.keptA.first.id);
      expect(couch.keptA.last.togetherMs, greaterThan(couch.keptA.first.togetherMs + 50000));
      await couch.dispose();
    });

    test('watching alone never keeps anything', () async {
      final couch = Couch();
      await couch.meet();
      couch.a.start(movie);
      await couch.run(200);
      couch.a.togglePlay();
      await couch.run(WatchRoom.keepAfterMs + 60000, every: 1000);
      expect(couch.keptA, isEmpty);
      couch.a.leave();
      expect(couch.keptA, isEmpty);
      await couch.dispose();
    });

    test('paused time does not count', () async {
      final couch = Couch();
      await couch.together();
      await couch.run(WatchRoom.keepAfterMs + 60000, every: 1000);
      expect(couch.keptA, isEmpty);
      couch.a.togglePlay();
      await couch.run(5 * 60000, every: 1000);
      couch.a.togglePlay();
      await couch.run(20 * 60000, every: 1000);
      expect(couch.keptA, isEmpty);
      await couch.dispose();
    });

    test('a new link is a new film, and the one before keeps its time', () async {
      final couch = Couch();
      await couch.together();
      couch.a.togglePlay();
      await couch.run(WatchRoom.keepAfterMs + 5000, every: 1000);
      final first = couch.keptA.single;
      couch.a.start(other);
      await couch.run(1000);
      expect(couch.keptA, hasLength(2));
      expect(couch.keptA.last.id, first.id);
      expect(couch.keptB.last.id, first.id);
      couch.a.togglePlay();
      await couch.run(WatchRoom.keepAfterMs + 5000, every: 1000);
      expect(couch.keptA.last.id, isNot(first.id));
      expect(couch.keptA.last.title, 'other-film');
      await couch.dispose();
    });

    test('a good name is pulled from the link, and a meaningless one is left out', () {
      for (final (link, title) in <(String, String?)>[
        ('https://a.dev/8acf85d/Our.Film.2021.1080p.WEB-DL.mkv', 'Our Film (2021)'),
        ('https://a.dev/My%20Film%20%5B1080p%5D.mp4', 'My Film'),
        ('https://a.dev/x/The_Long_Road_720p_x264.mkv?token=abc', 'The Long Road'),
        ('https://a.dev/%E0%A4%AB%E0%A4%BF%E0%A4%B2%E0%A5%8D%E0%A4%AE.mp4', 'फिल्म'),
        ('https://a.dev/2012.mkv', null),
        ('https://a.dev/8acf85d0-11ee-4c55.mkv', null),
        ('https://a.dev/hls/master.m3u8', null),
        ('https://a.dev/', null),
        ('https://a.dev', null),
      ]) {
        expect(filmTitleFromLink(link), title, reason: link);
      }
      expect(filmTitleFromLink('https://a.dev/${'long ' * 40}.mkv')!.runes.length, lessThanOrEqualTo(80));
    });
  });

  group('leaving', () {
    test('the one who stays keeps watching, and the one who left can come back', () async {
      final couch = Couch();
      await couch.together();
      couch.a.togglePlay();
      await couch.run(2000);
      final gone = couch.playerB;
      couch.b.leave();
      expect(gone.disposed, isTrue);
      await couch.run(1000);
      expect(couch.a.partnerIn, isFalse);
      expect(couch.a.url, movie);
      expect(couch.playerA.isPlaying, isTrue);
      expect(couch.b.invited, isFalse);
      await couch.run(WatchRoom.beatMs + 200);
      expect(couch.b.offered, isTrue);

      couch.b.join();
      await couch.run(1500);
      expect(couch.a.partnerIn, isTrue);
      expect((couch.playerA.positionNow - couch.playerB.positionNow).abs(), lessThan(600));
      await couch.dispose();
    });

    test('when the last one leaves the invitation goes away', () async {
      final couch = Couch();
      await couch.meet();
      couch.a.start(movie);
      await couch.run(200);
      expect(couch.b.invited, isTrue);
      couch.a.leave();
      await couch.run(200);
      expect(couch.b.invited, isFalse);
      expect(couch.b.url, isNull);
      await couch.dispose();
    });

    test('a partner who goes silent is let go after a while, and a stall of theirs stops holding us', () async {
      final couch = Couch();
      await couch.together();
      couch.a.togglePlay();
      await couch.run(1000);
      couch.playerB.isBuffering = true;
      await couch.run(WatchRoom.waitAfterMs + 400);
      expect(couch.a.held, isTrue);
      couch.pair.drop();
      await couch.step();
      expect(couch.a.partnerIn, isFalse);
      await couch.run(600);
      expect(couch.a.held, isFalse);
      expect(couch.playerA.isPlaying, isTrue);
      await couch.dispose();
    });

    test('an invitation from a phone that vanished disappears on its own', () async {
      final couch = Couch();
      await couch.meet();
      couch.a.start(movie);
      await couch.run(200);
      expect(couch.b.invited, isTrue);
      couch.a.dispose();
      couch.pair.transportA.refuse = true;
      await couch.run(WatchRoom.goneMs + 500);
      expect(couch.b.invited, isFalse);
      expect(couch.b.url, isNull);
      couch.b.dispose();
      couch.pair.dispose();
    });

    test('going to the background pauses this phone, tells the partner, and catches up on return', () async {
      final couch = Couch();
      await couch.together();
      couch.a.togglePlay();
      await couch.run(2000);
      couch.pair.b.setForeground(false);
      await couch.run(300);
      expect(couch.playerB.isPlaying, isFalse);
      expect(couch.a.partnerIn, isFalse);
      expect(couch.playerA.isPlaying, isTrue);
      await couch.run(5000);
      couch.pair.b.setForeground(true);
      await couch.run(1000);
      expect(couch.a.partnerIn, isTrue);
      expect(couch.playerB.isPlaying, isTrue);
      expect((couch.playerA.positionNow - couch.playerB.positionNow).abs(), lessThan(800));
      await couch.dispose();
    });

    test('a new link from the partner replaces what this phone is playing', () async {
      final couch = Couch();
      await couch.together();
      final first = couch.playerB;
      couch.a.start(other);
      await couch.run(300);
      expect(first.disposed, isTrue);
      expect(couch.playerB.url, other);
      await couch.dispose();
    });
  });
}
