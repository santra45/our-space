import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/presentation/screens/watch/watch_player.dart';

const String movie = 'https://example.com/film.mkv';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  Object? Function(MethodCall call) answer = (_) => null;

  setUp(() {
    calls.clear();
    answer = (call) => call.method == 'create' ? {'id': 7, 'textureId': 42} : null;
    messenger.setMockMethodCallHandler(NativeWatchPlayer.channel, (call) async {
      calls.add(call);
      return answer(call);
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(NativeWatchPlayer.channel, null));

  Future<void> tell(String method, Map<String, Object?> body) async {
    await messenger.handlePlatformMessage(
      NativeWatchPlayer.channel.name,
      const StandardMethodCodec().encodeMethodCall(MethodCall(method, body)),
      (_) {},
    );
  }

  Map<String, Object?> state({
    int id = 7,
    bool ready = true,
    bool buffering = false,
    bool playing = false,
    bool failed = false,
    bool live = false,
    bool seekable = true,
    bool rangeless = false,
    int duration = 7200000,
    double width = 1920,
    double height = 800,
    List<Map<String, Object?>> audio = const [],
    List<Map<String, Object?>> subtitles = const [],
  }) => {
    'id': id,
    'ready': ready,
    'buffering': buffering,
    'playing': playing,
    'failed': failed,
    'live': live,
    'seekable': seekable,
    'rangeless': rangeless,
    'durationMs': duration,
    'width': width,
    'height': height,
    'audio': audio,
    'subtitles': subtitles,
  };

  test('loading asks the phone for a player with the link, and nothing is ready until it says so', () async {
    final player = NativeWatchPlayer();
    await player.load(movie);
    expect(calls.single.method, 'create');
    expect(calls.single.arguments, {'url': movie});
    expect(player.ready, isFalse);
    expect(player.failed, isFalse);
    player.dispose();
  });

  test('what the phone reports becomes the state, including tracks, and each change is heard', () async {
    final player = NativeWatchPlayer();
    await player.load(movie);
    var heard = 0;
    player.addListener(() => heard++);
    await tell(
      'state',
      state(
        buffering: true,
        playing: true,
        audio: [
          {'id': '0:0', 'label': 'Hindi', 'detail': '5.1', 'selected': true},
          {'id': '1:0', 'label': null, 'detail': null, 'selected': false},
        ],
        subtitles: [
          {'id': '2:0', 'label': 'English', 'detail': null, 'selected': false},
        ],
      ),
    );
    expect(heard, 1);
    expect(player.ready, isTrue);
    expect(player.buffering, isTrue);
    expect(player.playing, isTrue);
    expect(player.live, isFalse);
    expect(player.durationMs, 7200000);
    expect(player.aspect, closeTo(2.4, 0.001));
    expect(player.audioTracks.first.label, 'Hindi');
    expect(player.audioTracks.first.detail, '5.1');
    expect(player.audioTracks.first.selected, isTrue);
    expect(player.audioTracks.last.label, isNull);
    expect(player.subtitleTracks.single.id, '2:0');

    await tell('cues', {
      'id': 7,
      'lines': ['Hello there', 'you'],
    });
    expect(player.cues, ['Hello there', 'you']);
    await tell('cues', {'id': 7, 'lines': <String>[]});
    expect(player.cues, isEmpty);
    player.dispose();
  });

  test('whether the link can jump comes from the phone', () async {
    final player = NativeWatchPlayer();
    await player.load(movie);
    expect(player.seekable, isFalse);
    await tell('state', state());
    expect(player.seekable, isTrue);
    expect(player.rangeless, isFalse);
    await tell('state', state(seekable: false, rangeless: true));
    expect(player.seekable, isFalse);
    expect(player.rangeless, isTrue);
    player.dispose();
  });

  test('a message for another player is ignored', () async {
    final player = NativeWatchPlayer();
    await player.load(movie);
    await tell('state', state(id: 99));
    expect(player.ready, isFalse);
    player.dispose();
  });

  test('every control goes to the phone with the right player and values', () async {
    final player = NativeWatchPlayer();
    await player.load(movie);
    calls.clear();
    await player.play();
    expect(player.playing, isTrue);
    await player.pause();
    expect(player.playing, isFalse);
    await player.seekTo(1234);
    await player.setSpeed(1.03);
    await player.selectAudio('1:0');
    await player.selectSubtitle('2:0');
    await player.selectSubtitle(null);
    expect([for (final call in calls) '${call.method} ${call.arguments}'], [
      'play {id: 7}',
      'pause {id: 7}',
      'seek {id: 7, ms: 1234}',
      'speed {id: 7, value: 1.03}',
      'audio {id: 7, track: 1:0}',
      'subtitle {id: 7, track: 2:0}',
      'subtitle {id: 7, track: null}',
    ]);
    player.dispose();
  });

  test('position comes from the phone, and the last known one is kept if it cannot answer', () async {
    final player = NativeWatchPlayer();
    await player.load(movie);
    answer = (call) => call.method == 'position' ? {'position': 5000, 'buffered': 42000} : null;
    expect(await player.position(), 5000);
    expect(player.bufferedMs, 42000);
    answer = (_) => throw PlatformException(code: 'gone');
    expect(await player.position(), 5000);
    expect(player.bufferedMs, 42000);
    player.dispose();
  });

  test('turning subtitles off clears the words at once', () async {
    final player = NativeWatchPlayer();
    await player.load(movie);
    await tell('cues', {
      'id': 7,
      'lines': ['Hello'],
    });
    await player.selectSubtitle(null);
    expect(player.cues, isEmpty);
    player.dispose();
  });

  test('a live video and an unknown length both count as live', () async {
    final player = NativeWatchPlayer();
    await player.load(movie);
    await tell('state', state(live: true));
    expect(player.live, isTrue);
    await tell('state', state(duration: -1));
    expect(player.live, isTrue);
    await tell('state', state());
    expect(player.live, isFalse);
    player.dispose();
  });

  test('a playback error or a failed start is reported as failed and not ready', () async {
    final broken = NativeWatchPlayer();
    await broken.load(movie);
    await tell('state', state(failed: true));
    expect(broken.failed, isTrue);
    expect(broken.ready, isFalse);
    broken.dispose();

    answer = (_) => throw PlatformException(code: 'no');
    final refused = NativeWatchPlayer();
    await refused.load(movie);
    expect(refused.failed, isTrue);
    refused.dispose();
  });

  testWidgets('the video is drawn on the texture the phone gave us', (tester) async {
    final player = NativeWatchPlayer();
    expect(player.view(), isA<SizedBox>());
    await tester.runAsync(() => player.load(movie));
    final view = player.view();
    expect(view, isA<Texture>());
    expect((view as Texture).textureId, 42);
    player.dispose();
  });

  test('putting it away releases it on the phone, and later messages do nothing', () async {
    final player = NativeWatchPlayer();
    await player.load(movie);
    calls.clear();
    player.dispose();
    await pumpEventQueue();
    expect(calls.single.method, 'dispose');
    expect(calls.single.arguments, {'id': 7});
    await tell('state', state());
    await player.position();
  });

  test('a player put away while it was still starting is released as soon as it exists', () async {
    final player = NativeWatchPlayer();
    final loading = player.load(movie);
    player.dispose();
    await loading;
    await pumpEventQueue();
    expect(calls.map((call) => call.method), ['create', 'dispose']);
  });
}
