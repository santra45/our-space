import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/presentation/app_shell.dart';
import 'package:our_space_mobile/presentation/home_shell.dart';
import 'package:our_space_mobile/presentation/screens/sky/together/sky_together_scope.dart';
import 'package:our_space_mobile/presentation/screens/watch/watch_copy.dart';
import 'package:our_space_mobile/presentation/screens/watch/watch_page.dart';
import 'package:our_space_mobile/presentation/screens/watch/watch_player.dart';
import 'package:our_space_mobile/presentation/screens/watch/watch_room.dart';
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
    WatchPlayers.create = ExoWatchPlayer.new;
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
      WatchCopy.paste,
      WatchCopy.pasteEmpty,
      WatchCopy.start,
      WatchCopy.play,
      WatchCopy.pause,
      WatchCopy.back,
      WatchCopy.wontPlay,
      WatchCopy.seekLabel,
      WatchCopy.live,
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
    await sofa.run(beat * 3);
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
    await tester.tapAt(const Offset(200, 100));
    await tester.pump();
    expect(find.byKey(WatchKeys.playPause), findsNothing);
    await tester.tapAt(const Offset(200, 100));
    await tester.pump();
    expect(find.byKey(WatchKeys.playPause), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 5));
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
