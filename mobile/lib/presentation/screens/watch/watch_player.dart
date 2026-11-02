import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

@immutable
class WatchTrack {
  const WatchTrack({required this.id, this.label, this.detail, this.selected = false});

  final String id;
  final String? label;
  final String? detail;
  final bool selected;
}

abstract class WatchPlayer implements Listenable {
  bool get ready;

  bool get buffering;

  bool get failed;

  bool get playing;

  bool get live;

  bool get seekable;

  bool get rangeless;

  int get durationMs;

  int get bufferedMs;

  double get aspect;

  List<WatchTrack> get audioTracks;

  List<WatchTrack> get subtitleTracks;

  List<String> get cues;

  Future<void> load(String url);

  Future<int> position();

  Future<void> play();

  Future<void> pause();

  Future<void> seekTo(int ms);

  Future<void> setSpeed(double speed);

  Future<void> selectAudio(String id);

  Future<void> selectSubtitle(String? id);

  Widget view();

  void dispose();
}

abstract final class WatchPlayers {
  static WatchPlayer Function() create = NativeWatchPlayer.new;
}

class NativeWatchPlayer extends ChangeNotifier implements WatchPlayer {
  static const MethodChannel channel = MethodChannel('our_space/watch_player');
  static const int _longestMs = 30 * 24 * 60 * 60 * 1000;
  static final Map<int, NativeWatchPlayer> _players = {};

  static void _listen() {
    channel.setMethodCallHandler((call) async {
      final raw = call.arguments;
      if (raw is! Map) return;
      final id = raw['id'];
      final player = id is int ? _players[id] : null;
      if (player == null) return;
      if (call.method == 'state') player._onState(raw);
      if (call.method == 'cues') player._onCues(raw);
    });
  }

  int? _id;
  int? _textureId;
  bool _ready = false;
  bool _buffering = false;
  bool _failed = false;
  bool _playing = false;
  bool _live = false;
  bool _seekable = false;
  bool _rangeless = false;
  bool _disposed = false;
  int _durationMs = 0;
  int _lastPosition = 0;
  int _buffered = 0;
  double _aspect = 16 / 9;
  List<WatchTrack> _audio = const [];
  List<WatchTrack> _subtitles = const [];
  List<String> _cues = const [];

  @override
  bool get ready => _ready && !_failed;

  @override
  bool get buffering => _buffering;

  @override
  bool get failed => _failed;

  @override
  bool get playing => _playing;

  @override
  bool get live => _live || _durationMs <= 0 || _durationMs > _longestMs;

  @override
  bool get seekable => _seekable;

  @override
  bool get rangeless => _rangeless;

  @override
  int get durationMs => _durationMs;

  @override
  int get bufferedMs => _buffered;

  @override
  double get aspect => _aspect;

  @override
  List<WatchTrack> get audioTracks => _audio;

  @override
  List<WatchTrack> get subtitleTracks => _subtitles;

  @override
  List<String> get cues => _cues;

  static List<WatchTrack> _tracks(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map && item['id'] is String)
          WatchTrack(
            id: item['id'] as String,
            label: item['label'] as String?,
            detail: item['detail'] as String?,
            selected: item['selected'] == true,
          ),
    ];
  }

  void _onState(Map<Object?, Object?> raw) {
    _ready = raw['ready'] == true;
    _buffering = raw['buffering'] == true;
    _playing = raw['playing'] == true;
    _failed = raw['failed'] == true;
    _live = raw['live'] == true;
    _seekable = raw['seekable'] == true;
    _rangeless = raw['rangeless'] == true;
    final duration = raw['durationMs'];
    _durationMs = duration is int ? duration : 0;
    final width = raw['width'];
    final height = raw['height'];
    if (width is num && height is num && width > 0 && height > 0) _aspect = width / height;
    _audio = _tracks(raw['audio']);
    _subtitles = _tracks(raw['subtitles']);
    notifyListeners();
  }

  void _onCues(Map<Object?, Object?> raw) {
    final lines = raw['lines'];
    _cues = lines is List ? [for (final line in lines) if (line is String) line] : const [];
    notifyListeners();
  }

  @override
  Future<void> load(String url) async {
    _listen();
    try {
      final made = await channel.invokeMapMethod<String, Object?>('create', {'url': url});
      final id = made?['id'];
      final texture = made?['textureId'];
      if (id is! int || texture is! int) throw StateError('No player');
      if (_disposed) {
        await channel.invokeMethod<void>('dispose', {'id': id});
        return;
      }
      _id = id;
      _textureId = texture;
      _players[id] = this;
    } catch (_) {
      if (_disposed) return;
      _failed = true;
    }
    notifyListeners();
  }

  Future<void> _call(String method, [Map<String, Object?> extra = const {}]) async {
    final id = _id;
    if (id == null) return;
    try {
      await channel.invokeMethod<void>(method, {'id': id, ...extra});
    } catch (_) {
      if (_disposed) return;
      _failed = true;
      notifyListeners();
    }
  }

  @override
  Future<int> position() async {
    final id = _id;
    if (id == null) return _lastPosition;
    try {
      final now = await channel.invokeMapMethod<String, Object?>('position', {'id': id});
      final position = now?['position'];
      final buffered = now?['buffered'];
      if (position is int) _lastPosition = position;
      if (buffered is int) _buffered = buffered;
    } catch (_) {}
    return _lastPosition;
  }

  @override
  Future<void> play() async {
    _playing = true;
    await _call('play');
  }

  @override
  Future<void> pause() async {
    _playing = false;
    await _call('pause');
  }

  @override
  Future<void> seekTo(int ms) => _call('seek', {'ms': ms});

  @override
  Future<void> setSpeed(double speed) => _call('speed', {'value': speed});

  @override
  Future<void> selectAudio(String id) => _call('audio', {'track': id});

  @override
  Future<void> selectSubtitle(String? id) {
    if (id == null) {
      _cues = const [];
      notifyListeners();
    }
    return _call('subtitle', {'track': id});
  }

  @override
  Widget view() {
    final texture = _textureId;
    return texture == null ? const SizedBox.shrink() : Texture(textureId: texture);
  }

  @override
  void dispose() {
    _disposed = true;
    final id = _id;
    _id = null;
    _textureId = null;
    if (id != null) {
      _players.remove(id);
      channel.invokeMethod<void>('dispose', {'id': id}).catchError((Object _) {});
    }
    super.dispose();
  }
}
