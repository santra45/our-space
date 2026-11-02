import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/presentation/app_shell.dart';
import 'package:our_space_mobile/presentation/home_shell.dart';
import 'package:our_space_mobile/presentation/screens/sky/together/sky_together_scope.dart';
import 'package:our_space_mobile/presentation/screens/watch/films_shelf.dart';
import 'package:our_space_mobile/presentation/screens/watch/watch_copy.dart';
import 'package:our_space_mobile/presentation/screens/watch/watch_page.dart';
import 'package:our_space_mobile/presentation/screens/watch/watch_player.dart';
import 'package:our_space_mobile/presentation/screens/watch/watch_reactions.dart';
import 'package:our_space_mobile/presentation/screens/watch/watch_room.dart';
import 'package:our_space_mobile/presentation/screens/watch/watch_seek_bar.dart';
import 'package:our_space_mobile/presentation/sky/sky.dart';

import '../../support/fake_sky_together.dart';
import '../love/love_harness.dart';
import 'support/fake_watch_player.dart';

const String movie = 'https://example.com/movies/our-film.mp4';
const Duration beat = Duration(milliseconds: 100);

final RegExp technical = RegExp(
  r'\b(sync|device|pair|server|upload|download|data|peer|relay|mailbox|encrypt|key|session|canvas|stream|buffer)',
  caseSensitive: false,
);

class Sofa {
  Sofa(this.tester, this.space, this.pair) : other = WatchRoom(link: pair.b, tickEvery: null);

  final WidgetTester tester;
  final OurSpace space;
  final FakeSkyPair pair;
  final WatchRoom other;
  final List<FakeWatchPlayer> players = [];
  final List<bool> keptOn = [];

  Future<void> run(Duration total) async {
    var left = total.inMilliseconds;
    while (left > 0) {
      pair.advance(beat);
      await other.tick();
      await tester.pump(beat);
      left -= beat.inMilliseconds;
    }
  }

  Future<void> openPage() async {
    final entry = find.byKey(WatchKeys.entry);
    await reveal(tester, entry);
    await tester.tap(entry);
    await settleRoute(tester);
    expect(find.byType(WatchPage), findsOneWidget);
  }

  Future<void> close() async {
    await settle(tester, space);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    other.dispose();
    pair.dispose();
    await tester.pump(const Duration(milliseconds: 50));
    WatchPlayers.create = NativeWatchPlayer.new;
    WatchScreen.keepOn = (_) async {};
  }
}

Future<Sofa> onUs(WidgetTester tester, {FakeWatchPlayer Function()? player}) async {
  calm(tester);
  final space = await coupleSpace(tester);
  final sofa = Sofa(tester, space, FakeSkyPair());
  WatchPlayers.create = () {
    final made = player?.call() ?? FakeWatchPlayer();
    sofa.players.add(made);
    return made;
  };
  WatchScreen.keepOn = (on) async => sofa.keptOn.add(on);
  await pumpNight(
    tester,
    space,
    shell: SkyTogetherScope(link: sofa.pair.a, child: const HomeShell(initialTab: SkyTab.us)),
  );
  await untilFound(tester, find.byKey(WatchKeys.entry));
  for (var i = 0; i < 4; i++) {
    sofa.pair.settle();
    await tester.pump();
  }
  return sofa;
}

void main() {
  test('every word in the room stays warm and plain', () {
    final copy = [
      WatchCopy.kicker,
      WatchCopy.title,
      WatchCopy.entryHint,
      WatchCopy.linkLabel,
      WatchCopy.linkHelp,
      WatchCopy.linkInvalid,
      WatchCopy.linkBroken,
      WatchCopy.paste,
      WatchCopy.pasteEmpty,
      WatchCopy.start,
      WatchCopy.play,
      WatchCopy.pause,
      WatchCopy.back,
      WatchCopy.wontPlay,
      WatchCopy.seekLabel,
      WatchCopy.live,
      WatchCopy.audio,
      WatchCopy.subtitles,
      WatchCopy.subtitlesOff,
      WatchCopy.track(2),
      WatchCopy.unnamedFilm,
      WatchCopy.filmsTitle,
      WatchCopy.filmEditTitle,
      WatchCopy.filmNameLabel,
      WatchCopy.filmSave,
      WatchCopy.filmSaveFailed,
      WatchCopy.filmRemove,
      WatchCopy.filmRemoveTitle,
      WatchCopy.filmRemoveNote,
      WatchCopy.filmRemoveYes,
      WatchCopy.filmKeep,
      WatchCopy.together(600000),
      for (final reaction in SkyReaction.values) WatchCopy.reaction(reaction),
      WatchCopy.fullscreen,
      WatchCopy.fullscreenExit,
      WatchCopy.leaveTitle,
      WatchCopy.leaveAlone,
      WatchCopy.leaveYes,
      WatchCopy.leaveStay,
      WatchCopy.skipBack,
      WatchCopy.skipAhead,
      WatchCopy.leaveWith('Alex'),
      WatchCopy.paused('Alex'),
      WatchCopy.played('Alex'),
      WatchCopy.moved('Alex'),
      WatchCopy.joined('Alex'),
      WatchCopy.left('Alex'),
      WatchCopy.joinLabel,
      WatchCopy.notNow,
      WatchCopy.loading,
      WatchCopy.catchingUpMine,
      WatchCopy.invited('Alex'),
      WatchCopy.stillWatching('Alex'),
      WatchCopy.withPartner('Alex'),
      WatchCopy.waitingFor('Alex'),
      WatchCopy.catchingUp('Alex'),
      WatchCopy.partnerCantPlay('Alex'),
    ];
    for (final line in copy) {
      expect(technical.hasMatch(line), isFalse, reason: line);
    }
    expect(WatchCopy.clock(0), '0:00');
    expect(WatchCopy.clock(65000), '1:05');
    expect(WatchCopy.clock(3725000), '1:02:05');
    expect(WatchCopy.clock(-5), '0:00');
    expect(WatchCopy.together(600000), '10 min together');
    expect(WatchCopy.together(3600000), '1h together');
    expect(WatchCopy.together(7500000), '2h 5m together');
  });

  testWidgets('the Us tab opens a screen that asks for a link, and a bad one is turned away kindly', (tester) async {
    final sofa = await onUs(tester);
    expect(find.descendant(of: find.byKey(WatchKeys.entry), matching: find.text(WatchCopy.title)), findsOneWidget);
    await sofa.openPage();
    expect(sofa.keptOn, [true]);
    await tester.enterText(find.descendant(of: find.byKey(WatchKeys.linkField), matching: find.byType(EditableText)), 'http://nope');
    await tester.tap(find.byKey(WatchKeys.start));
    await tester.pump();
    expect(find.text(WatchCopy.linkInvalid), findsOneWidget);
    expect(sofa.players, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(SkyBackButton));
    await settleRoute(tester);
    expect(sofa.keptOn, [true, false]);
    await sofa.close();
  });

  testWidgets('a good link starts the video, tells the partner, and going back leaves the room', (tester) async {
    final sofa = await onUs(tester);
    await sofa.openPage();
    await tester.enterText(find.descendant(of: find.byKey(WatchKeys.linkField), matching: find.byType(EditableText)), movie);
    await tester.tap(find.byKey(WatchKeys.start));
    await sofa.run(beat * 4);
    expect(find.byKey(WatchKeys.video), findsOneWidget);
    expect(sofa.players.single.url, movie);
    expect(find.text(WatchCopy.waitingFor('Alex')), findsOneWidget);
    expect(sofa.other.invited, isTrue);

    sofa.other.join();
    await sofa.run(beat * 4);
    expect(find.text(WatchCopy.withPartner('Alex')), findsOneWidget);

    await tester.tap(find.byKey(WatchKeys.playPause));
    await sofa.run(beat * 6);
    expect(sofa.players.first.isPlaying, isTrue);
    expect(sofa.other.playing, isTrue);
    expect(tester.widget<SkyIconButton>(find.byKey(WatchKeys.playPause)).semanticLabel, WatchCopy.pause);

    final mine = sofa.players.first;
    await tester.tap(find.byType(SkyBackButton));
    await settleRoute(tester);
    expect(find.text(WatchCopy.leaveTitle), findsOneWidget);
    expect(find.text(WatchCopy.leaveWith('Alex')), findsOneWidget);
    await tester.tap(find.text(WatchCopy.leaveStay));
    await settleRoute(tester);
    expect(find.byType(WatchPage), findsOneWidget);
    expect(mine.disposed, isFalse);
    await tester.tap(find.byType(SkyBackButton));
    await settleRoute(tester);
    await tester.tap(find.text(WatchCopy.leaveYes));
    await settleRoute(tester);
    await sofa.run(beat * 3);
    expect(find.byType(WatchPage), findsNothing);
    expect(mine.disposed, isTrue);
    expect(sofa.other.partnerIn, isFalse);
    expect(tester.takeException(), isNull);
    await sofa.close();
  });

  testWidgets('the link can be pasted in one tap, and an empty clipboard says so', (tester) async {
    final sofa = await onUs(tester);
    String? clip;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') return clip == null ? null : {'text': clip};
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await sofa.openPage();
    await tester.tap(find.byKey(WatchKeys.paste));
    await tester.pump();
    await tester.pump();
    expect(find.text(WatchCopy.pasteEmpty), findsOneWidget);
    clip = '  $movie ';
    await tester.tap(find.byKey(WatchKeys.paste));
    await tester.pump();
    await tester.pump();
    expect(find.text(movie), findsOneWidget);
    expect(find.text(WatchCopy.pasteEmpty), findsNothing);
    await sofa.close();
  });

  testWidgets('anywhere in the app a note invites you in, and not now puts it away', (tester) async {
    final sofa = await onUs(tester);
    expect(find.byKey(WatchKeys.invite), findsNothing);
    sofa.other.start(movie);
    await sofa.run(beat * 3);
    expect(find.text(WatchCopy.invited('Alex')), findsOneWidget);
    expect(sofa.players, hasLength(1));

    await tester.tap(find.byWidgetPredicate((widget) => widget is SkyPressable && widget.semanticLabel == WatchCopy.notNow));
    await sofa.run(beat);
    expect(find.byKey(WatchKeys.invite), findsNothing);

    await sofa.openPage();
    expect(find.text(WatchCopy.stillWatching('Alex')), findsOneWidget);
    await tester.tap(find.byKey(WatchKeys.join));
    await sofa.run(beat * 3);
    expect(find.byKey(WatchKeys.video), findsOneWidget);
    expect(sofa.players, hasLength(2));
    await sofa.close();
  });

  testWidgets('saying yes on the note goes straight into the room with the partner', (tester) async {
    final sofa = await onUs(tester);
    sofa.other.start(movie);
    await sofa.run(beat * 3);
    await tester.tap(find.text(WatchCopy.joinLabel));
    await settleRoute(tester);
    await sofa.run(beat * 3);
    expect(find.byType(WatchPage), findsOneWidget);
    expect(find.text(WatchCopy.withPartner('Alex')), findsOneWidget);
    expect(find.byKey(WatchKeys.invite), findsNothing);
    await sofa.close();
  });

  testWidgets('a link that will not play says so plainly', (tester) async {
    final sofa = await onUs(tester, player: () => FakeWatchPlayer(failsToLoad: true));
    await sofa.openPage();
    await tester.enterText(find.descendant(of: find.byKey(WatchKeys.linkField), matching: find.byType(EditableText)), movie);
    await tester.tap(find.byKey(WatchKeys.start));
    await sofa.run(beat * 3);
    expect(find.text(WatchCopy.wontPlay), findsOneWidget);
    expect(tester.widget<SkyIconButton>(find.byKey(WatchKeys.playPause)).onPressed, isNull);
    await sofa.close();
  });

  testWidgets('sideways the video fills the screen, a tap shows the controls and a tap hides them', (tester) async {
    final sofa = await onUs(tester);
    await sofa.openPage();
    await tester.enterText(find.descendant(of: find.byKey(WatchKeys.linkField), matching: find.byType(EditableText)), movie);
    await tester.tap(find.byKey(WatchKeys.start));
    await sofa.run(beat * 3);
    tester.view.physicalSize = const Size(2532, 1170);
    addTearDown(tester.view.reset);
    await tester.pump();
    expect(find.byType(SkyTopBar), findsNothing);
    expect(find.byKey(WatchKeys.video), findsOneWidget);
    expect(find.byKey(WatchKeys.playPause), findsOneWidget);
    expect(find.byType(SkyCard), findsNothing);
    await tester.tapAt(const Offset(420, 195));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byKey(WatchKeys.playPause), findsNothing);
    await tester.tapAt(const Offset(420, 195));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byKey(WatchKeys.playPause), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 5));
    await sofa.close();
  });

  Future<Sofa> watching(WidgetTester tester) async {
    final sofa = await onUs(tester);
    await sofa.openPage();
    await tester.enterText(find.descendant(of: find.byKey(WatchKeys.linkField), matching: find.byType(EditableText)), movie);
    await tester.tap(find.byKey(WatchKeys.start));
    await sofa.run(beat * 3);
    return sofa;
  }

  testWidgets('a tap on the seek bar jumps there, and a drag only moves the film when it lets go', (tester) async {
    final sofa = await watching(tester);
    final mine = sofa.players.single;
    await sofa.run(beat * 3);
    final bar = tester.getRect(find.byKey(WatchKeys.seek));
    double xAt(double fraction) => bar.left + WatchSeekBar.side + (bar.width - WatchSeekBar.side * 2) * fraction;

    await tester.tapAt(Offset(xAt(0.5), bar.center.dy));
    await sofa.run(beat);
    expect(mine.seeks.last, closeTo(mine.durationMs / 2, 1000));

    final before = mine.seeks.length;
    final gesture = await tester.startGesture(Offset(xAt(0.5), bar.center.dy));
    await tester.pump(const Duration(milliseconds: 30));
    await gesture.moveTo(Offset(xAt(0.25), bar.center.dy));
    await tester.pump(const Duration(milliseconds: 30));
    await gesture.moveTo(Offset(xAt(0.25) - 1, bar.center.dy));
    await tester.pump(const Duration(milliseconds: 30));
    expect(mine.seeks.length, before);
    final painter = tester.widget<CustomPaint>(
      find.descendant(of: find.byKey(WatchKeys.seek), matching: find.byType(CustomPaint)),
    ).painter! as WatchSeekPainter;
    expect(painter.played, closeTo(0.25, 0.01));
    expect(painter.bubble, isNotNull);
    expect(find.text(WatchCopy.clock((mine.durationMs * painter.played).round())), findsOneWidget);
    await gesture.up();
    await sofa.run(beat);
    expect(mine.seeks.length, before + 1);
    expect(mine.seeks.last, closeTo(mine.durationMs / 4, mine.durationMs * 0.01));
    expect(tester.takeException(), isNull);
    await sofa.close();
  });

  testWidgets('the seek bar shows what has loaded, and a reader can step through the film', (tester) async {
    final sofa = await watching(tester);
    final mine = sofa.players.single..bufferedMs = 900000;
    await sofa.run(beat * 3);
    final seek = tester.widget<WatchSeekBar>(find.byKey(WatchKeys.seek));
    expect(seek.bufferedMs, 900000);
    WatchSeekPainter painter() => tester.widget<CustomPaint>(
      find.descendant(of: find.byKey(WatchKeys.seek), matching: find.byType(CustomPaint)),
    ).painter! as WatchSeekPainter;
    expect(painter().buffered, closeTo(900000 / mine.durationMs, 0.001));
    expect(painter().bubble, isNull);

    final reader = tester.widget<Semantics>(
      find.descendant(of: find.byKey(WatchKeys.seek), matching: find.byWidgetPredicate((w) => w is Semantics && w.properties.slider == true)),
    );
    expect(reader.properties.label, WatchCopy.seekLabel);
    expect(reader.properties.value, '0:00');
    expect(reader.properties.increasedValue, '0:10');
    reader.properties.onIncrease!();
    await sofa.run(beat);
    expect(mine.seeks.last, WatchSeekBar.stepMs);
    await sofa.close();
  });

  testWidgets('what the partner does is said over the video, and fades after a moment', (tester) async {
    final sofa = await watching(tester);
    sofa.other.join();
    await sofa.run(beat * 3);
    expect(find.text(WatchCopy.joined('Alex')), findsOneWidget);
    await sofa.run(const Duration(seconds: 4));
    expect(find.byKey(WatchKeys.pill), findsNothing);

    sofa.other.togglePlay();
    await sofa.run(beat * 6);
    expect(find.text(WatchCopy.played('Alex')), findsOneWidget);
    sofa.other.togglePlay();
    await sofa.run(beat * 3);
    expect(find.text(WatchCopy.paused('Alex')), findsOneWidget);
    sofa.other.seek(300000);
    await sofa.run(beat * 3);
    expect(find.text(WatchCopy.moved('Alex')), findsOneWidget);
    sofa.other.leave();
    await sofa.run(beat * 3);
    expect(find.text(WatchCopy.left('Alex')), findsOneWidget);
    await sofa.run(const Duration(seconds: 4));
    expect(find.byKey(WatchKeys.pill), findsNothing);
    expect(tester.takeException(), isNull);
    await sofa.close();
  });

  testWidgets('when the partner stalls the frozen picture says why and shows it is waiting', (tester) async {
    final sofa = await watching(tester);
    sofa.other.join();
    await sofa.run(beat * 3);
    await sofa.run(const Duration(seconds: 4));
    await tester.tap(find.byKey(WatchKeys.playPause));
    await sofa.run(const Duration(seconds: 1));
    (sofa.other.player! as FakeWatchPlayer).isBuffering = true;
    await sofa.run(const Duration(seconds: 2));
    expect(find.byKey(WatchKeys.waiting), findsOneWidget);
    expect(find.descendant(of: find.byKey(WatchKeys.pill), matching: find.text(WatchCopy.catchingUp('Alex'))), findsOneWidget);
    (sofa.other.player! as FakeWatchPlayer).isBuffering = false;
    await sofa.run(const Duration(seconds: 1));
    expect(find.byKey(WatchKeys.waiting), findsNothing);
    expect(find.byKey(WatchKeys.pill), findsNothing);
    await sofa.close();
  });

  testWidgets('an emoji floats up the film on both sides and fades, and the buttons are there sideways too', (tester) async {
    final sofa = await watching(tester);
    sofa.other.join();
    await sofa.run(beat * 3);
    expect(find.byKey(WatchReactionKeys.floater), findsNothing);
    final heart = tester.widget<SkyPressable>(find.byKey(WatchReactionKeys.button(SkyReaction.heart)));
    expect(heart.semanticLabel, 'Send a heart');

    await reveal(tester, find.byKey(WatchReactionKeys.button(SkyReaction.heart)));
    await tester.tap(find.byKey(WatchReactionKeys.button(SkyReaction.heart)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(WatchReactionKeys.floater), findsOneWidget);
    expect(find.descendant(of: find.byKey(WatchKeys.video), matching: find.text(watchReactionEmoji(SkyReaction.heart))), findsOneWidget);

    await sofa.run(const Duration(milliseconds: 300));
    sofa.pair.injectEvent(sofa.pair.a, const SkyWatchReactEvent(SkyReaction.tear));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(WatchReactionKeys.floater), findsNWidgets(2));
    await tester.pump(const Duration(seconds: 4));
    expect(find.byKey(WatchReactionKeys.floater), findsNothing);

    tester.view.physicalSize = const Size(2532, 1170);
    addTearDown(tester.view.reset);
    await tester.pump();
    expect(find.byKey(WatchReactionKeys.button(SkyReaction.wow)), findsOneWidget);
    await tester.tap(find.byKey(WatchReactionKeys.button(SkyReaction.wow)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(WatchReactionKeys.floater), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 6));
    await sofa.close();
  });

  testWidgets('with motion on, mine rise on the right and theirs on the left, and both climb and fade', (tester) async {
    final sofa = await watching(tester);
    tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
    await tester.pump();
    final video = tester.getRect(find.byKey(WatchKeys.video));
    await reveal(tester, find.byKey(WatchReactionKeys.button(SkyReaction.fire)));
    await tester.tap(find.byKey(WatchReactionKeys.button(SkyReaction.fire)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final mine = find.descendant(of: find.byKey(WatchKeys.video), matching: find.text(watchReactionEmoji(SkyReaction.fire)));
    final early = tester.getCenter(mine);
    expect(early.dx, greaterThan(video.center.dx));
    await tester.pump(const Duration(milliseconds: 900));
    final later = tester.getCenter(mine);
    expect(later.dy, lessThan(early.dy - 20));

    sofa.pair.advance(const Duration(milliseconds: 200));
    sofa.pair.injectEvent(sofa.pair.a, const SkyWatchReactEvent(SkyReaction.love));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final theirs = find.descendant(of: find.byKey(WatchKeys.video), matching: find.text(watchReactionEmoji(SkyReaction.love)));
    expect(tester.getCenter(theirs).dx, lessThan(video.center.dx));
    await tester.pump(const Duration(seconds: 4));
    expect(find.byKey(WatchReactionKeys.floater), findsNothing);
    expect(tester.takeException(), isNull);
    await sofa.close();
  });

  testWidgets('a burst keeps only the newest ones in the air', (tester) async {
    final sofa = await watching(tester);
    for (var i = 0; i < WatchReactionLayer.most + 5; i++) {
      sofa.pair.advance(const Duration(milliseconds: 120));
      sofa.pair.injectEvent(sofa.pair.a, const SkyWatchReactEvent(SkyReaction.laugh));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(WatchReactionKeys.floater), findsNWidgets(WatchReactionLayer.most));
    await tester.pump(const Duration(seconds: 4));
    expect(find.byKey(WatchReactionKeys.floater), findsNothing);
    await sofa.close();
  });

  testWidgets('a double tap skips ten seconds on the side it lands on, and never before the start', (tester) async {
    final sofa = await watching(tester);
    final mine = sofa.players.single;
    final video = tester.getRect(find.byKey(WatchKeys.video));
    Future<void> doubleTap(Offset at) async {
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 60));
    }

    await doubleTap(video.centerRight - const Offset(30, 0));
    expect(mine.seeks.last, WatchRoom.skipMs);
    expect(find.descendant(of: find.byKey(WatchKeys.skip), matching: find.text(WatchCopy.skipAhead)), findsOneWidget);
    await sofa.run(const Duration(seconds: 1));
    expect(find.byKey(WatchKeys.skip), findsNothing);

    mine.positionNow = 4000;
    await sofa.run(beat * 3);
    await doubleTap(video.centerLeft + const Offset(30, 0));
    expect(mine.seeks.last, 0);
    expect(find.descendant(of: find.byKey(WatchKeys.skip), matching: find.text(WatchCopy.skipBack)), findsOneWidget);
    await sofa.run(const Duration(seconds: 1));
    await sofa.close();
  });

  testWidgets('the full screen button turns the screen, and back leaves full screen before it asks about leaving', (tester) async {
    final turns = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemChrome.setPreferredOrientations') turns.add(call.arguments);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final sofa = await watching(tester);
    turns.clear();
    await tester.tap(find.byKey(WatchKeys.fullscreen));
    await tester.pump();
    expect(turns.single, ['DeviceOrientation.landscapeLeft', 'DeviceOrientation.landscapeRight']);

    tester.view.physicalSize = const Size(2532, 1170);
    addTearDown(tester.view.reset);
    await tester.pump();
    turns.clear();
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(turns.single, ['DeviceOrientation.portraitUp']);
    expect(find.text(WatchCopy.leaveTitle), findsNothing);
    expect(find.byType(WatchPage), findsOneWidget);

    tester.view.physicalSize = const Size(1170, 2532);
    await tester.pump();
    await tester.binding.handlePopRoute();
    await settleRoute(tester);
    expect(find.text(WatchCopy.leaveTitle), findsOneWidget);
    await tester.tap(find.text(WatchCopy.leaveStay));
    await settleRoute(tester);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 5));
    await sofa.close();
  });

  testWidgets('each phone picks its own audio and subtitles, and the other phone is not touched', (tester) async {
    final sofa = await onUs(
      tester,
      player: () => FakeWatchPlayer()
        ..audioTracks = const [
          WatchTrack(id: '0:0', label: 'Hindi', detail: '5.1', selected: true),
          WatchTrack(id: '1:0', label: 'English'),
          WatchTrack(id: '2:0'),
        ]
        ..subtitleTracks = const [WatchTrack(id: '3:0', label: 'English')],
    );
    await sofa.openPage();
    await tester.enterText(find.descendant(of: find.byKey(WatchKeys.linkField), matching: find.byType(EditableText)), movie);
    await tester.tap(find.byKey(WatchKeys.start));
    await sofa.run(beat * 3);
    final mine = sofa.players.single;
    final told = sofa.pair.transportA.sentOf('watch').length;

    await tester.tap(find.byKey(WatchKeys.audio));
    await settleRoute(tester);
    expect(find.text('Hindi'), findsOneWidget);
    expect(find.text('5.1'), findsOneWidget);
    expect(find.text(WatchCopy.track(3)), findsOneWidget);
    await tester.tap(find.byKey(WatchKeys.track('1:0')));
    await settleRoute(tester);
    expect(mine.pickedAudio, ['1:0']);

    await tester.tap(find.byKey(WatchKeys.subtitles));
    await settleRoute(tester);
    await tester.tap(find.byKey(WatchKeys.track('3:0')));
    await settleRoute(tester);
    expect(mine.pickedSubtitles, ['3:0']);

    mine.show(['Hello there', 'my love']);
    await tester.pump();
    expect(find.text('Hello there\nmy love'), findsOneWidget);
    mine.show(const []);
    await tester.pump();
    expect(find.byKey(WatchKeys.cues), findsNothing);

    await tester.tap(find.byKey(WatchKeys.subtitles));
    await settleRoute(tester);
    await tester.tap(find.byKey(WatchKeys.subtitlesOff));
    await settleRoute(tester);
    expect(mine.pickedSubtitles, ['3:0', null]);

    expect(sofa.pair.transportA.sentOf('watch').length, told);
    expect(tester.takeException(), isNull);
    await sofa.close();
  });

  testWidgets('with one audio track and no subtitles there is nothing extra to press', (tester) async {
    final sofa = await onUs(
      tester,
      player: () => FakeWatchPlayer()..audioTracks = const [WatchTrack(id: '0:0', label: 'Hindi', selected: true)],
    );
    await sofa.openPage();
    await tester.enterText(find.descendant(of: find.byKey(WatchKeys.linkField), matching: find.byType(EditableText)), movie);
    await tester.tap(find.byKey(WatchKeys.start));
    await sofa.run(beat * 3);
    expect(find.byKey(WatchKeys.playPause), findsOneWidget);
    expect(find.byKey(WatchKeys.audio), findsNothing);
    expect(find.byKey(WatchKeys.subtitles), findsNothing);
    await sofa.close();
  });

  testWidgets('films we watched sit on the Us tab, and can be renamed or taken off for both of us', (tester) async {
    final sofa = await onUs(tester);
    expect(find.text(WatchCopy.filmsTitle), findsNothing);
    final room = WatchScope.maybeOf(tester.element(find.byKey(WatchKeys.entry)))!;
    room.onWatched!(const WatchedFilm(id: 'film-one', title: 'Our First Film (2020)', togetherMs: 7500000));
    await settle(tester, sofa.space);
    await untilFound(tester, find.text(WatchCopy.filmsTitle));
    expect(find.text('Our First Film (2020)'), findsOneWidget);
    expect(find.textContaining('2h 5m together'), findsOneWidget);

    final ticket = find.byKey(FilmKeys.film('film-one'));
    await reveal(tester, ticket);
    await tester.tap(ticket);
    await settleRoute(tester);
    await tester.enterText(find.descendant(of: find.byKey(FilmKeys.title), matching: find.byType(EditableText)), 'The one with the rain');
    await tester.pump();
    await tester.tap(find.byKey(FilmKeys.save));
    await settle(tester, sofa.space);
    await untilFound(tester, find.text('The one with the rain'));
    await settleRoute(tester);
    expect((await drive(tester, sofa.space.films.load)).items.single.title, 'The one with the rain');

    await reveal(tester, ticket);
    await tester.tap(ticket);
    await settleRoute(tester);
    await reveal(tester, find.byKey(FilmKeys.remove));
    await tester.tap(find.byKey(FilmKeys.remove));
    await settleRoute(tester);
    expect(find.text(WatchCopy.filmRemoveNote), findsOneWidget);
    await tester.tap(find.text(WatchCopy.filmRemoveYes));
    await settleRoute(tester);
    await settle(tester, sofa.space);
    await untilGone(tester, ticket);
    expect((await drive(tester, sofa.space.films.load)).items, isEmpty);
    expect(tester.takeException(), isNull);
    await sofa.close();
  });

  testWidgets('locking closes the room like every other screen', (tester) async {
    final sofa = await onUs(tester);
    await sofa.openPage();
    await tester.enterText(find.descendant(of: find.byKey(WatchKeys.linkField), matching: find.byType(EditableText)), movie);
    await tester.tap(find.byKey(WatchKeys.start));
    await sofa.run(beat * 3);
    final mine = sofa.players.single;
    await drive(tester, () async => sofa.space.vault.lock());
    await settleRoute(tester);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(WatchPage), findsNothing);
    expect(mine.disposed, isTrue);
    expect(sofa.keptOn.last, isFalse);
    await sofa.close();
  });
}
