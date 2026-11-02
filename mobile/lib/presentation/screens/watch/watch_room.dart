import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../core/engine.dart';
import 'watch_player.dart';

@immutable
class WatchedFilm {
  const WatchedFilm({required this.id, required this.title, required this.togetherMs});

  final String id;
  final String title;
  final int togetherMs;
}

final RegExp _filmExtension = RegExp(r'\.(mkv|mp4|m4v|webm|mov|avi|ts|m3u8|mpd)$', caseSensitive: false);
final RegExp _filmYear = RegExp(r'\b(19|20)\d{2}\b');
final RegExp _filmNoise = RegExp(
  r'\b(480p|720p|1080p|2160p|4k|web-?dl|web-?rip|bluray|blu-ray|brrip|bdrip|hdrip|dvdrip|hdtv|x264|x265|h264|h265|hevc|aac|ddp?5|dual|multi)\b',
  caseSensitive: false,
);
final RegExp _filmHash = RegExp(r'^[0-9a-f-]{8,}$', caseSensitive: false);
const Set<String> _filmPlainNames = {'index', 'master', 'playlist', 'video', 'stream', 'manifest', 'file', 'download'};

String? filmTitleFromLink(String url) {
  final segments = Uri.tryParse(url)?.pathSegments.where((segment) => segment.isNotEmpty).toList() ?? const <String>[];
  if (segments.isEmpty) return null;
  var name = segments.last.replaceFirst(_filmExtension, '').replaceAll(RegExp(r'[._+]'), ' ');
  name = name.replaceAll(RegExp(r'[\[({][^\])}]*[\])}]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (name.isEmpty || _filmHash.hasMatch(name) || !RegExp(r'\p{L}', unicode: true).hasMatch(name)) return null;
  if (_filmPlainNames.contains(name.toLowerCase())) return null;
  final year = _filmYear.firstMatch(name);
  if (year != null && year.start > 0) {
    name = '${name.substring(0, year.start).trim()} (${year.group(0)})';
  } else {
    final noise = _filmNoise.firstMatch(name);
    if (noise != null && noise.start > 0) name = name.substring(0, noise.start).trim();
  }
  return name.runes.length > 80 ? String.fromCharCodes(name.runes.take(80)).trim() : name;
}

class WatchRoom extends ChangeNotifier {
  WatchRoom({required this.link, this.onWatched, this.unnamedFilm = 'A film together', this._tickEvery = const Duration(milliseconds: 200)}) {
    _foreground = link.foreground;
    link.addListener(_onLink);
    _events = link.events.listen(_hear);
  }

  static const int beatMs = 2000;
  static const int goneMs = 7000;
  static const int offerMs = 4000;
  static const int waitAfterMs = 700;
  static const int leadMs = 300;
  static const int seekOverMs = 1500;
  static const int nudgeOverMs = 120;
  static const int settledMs = 40;
  static const int restOverMs = 300;
  static const int endWithinMs = 300;
  static const double nudge = 0.03;
  static const int keepAfterMs = 10 * 60 * 1000;
  static const int longestGapMs = 5000;

  final SkyTogetherLink link;
  final void Function(WatchedFilm film)? onWatched;
  final String unnamedFilm;
  final Duration? _tickEvery;
  final ValueNotifier<int> positionMs = ValueNotifier<int>(0);

  late final StreamSubscription<SkyTogetherEvent> _events;
  Timer? _timer;
  WatchPlayer? _player;
  String? _url;
  String? _loaded;
  String? _declined;
  String? _by;
  String? _film;
  int _togetherMs = 0;
  int? _countedAt;
  bool _kept = false;
  bool _playing = false;
  bool _hold = false;
  int _pos = 0;
  int _at = 0;
  int _seq = 0;
  bool _inRoom = false;
  bool _foreground = true;
  bool _partnerIn = false;
  bool _partnerWait = false;
  bool _partnerFail = false;
  bool _waitingSent = false;
  bool _ticking = false;
  bool _disposed = false;
  int _lastHeardAt = 0;
  int _lastBeatAt = 0;
  int _lastOfferAt = 0;
  int? _bufferingSince;
  double _speed = 1;

  String? get url => _url;

  bool get playing => _playing;

  bool get held => _hold;

  bool get inRoom => _inRoom;

  bool get partnerIn => _partnerIn;

  bool get partnerWaiting => _partnerWait;

  bool get partnerFailed => _partnerFail;

  WatchPlayer? get player => _player;

  bool get offered => _url != null && !_inRoom && _partnerIn;

  bool get invited => offered && _declined != _url;

  bool start(String raw) {
    final clean = skyWatchUrl(raw);
    if (clean == null || _disposed) return false;
    _newFilm('film-${generateUrlSafeNonce(16)}');
    _publish(url: clean, playing: false, hold: false, pos: 0);
    _enter();
    return true;
  }

  void _newFilm(String? id) {
    if (id == _film) return;
    _keep();
    _film = id;
    _togetherMs = 0;
    _countedAt = null;
    _kept = false;
  }

  void _keep() {
    final id = _film;
    final url = _url;
    if (!_kept || id == null || url == null) return;
    onWatched?.call(WatchedFilm(id: id, title: filmTitleFromLink(url) ?? unnamedFilm, togetherMs: _togetherMs));
  }

  void _count(WatchPlayer player) {
    final now = link.now();
    final counting = _partnerIn && _playing && !_hold && player.playing && !player.buffering;
    final last = _countedAt;
    _countedAt = counting ? now : null;
    if (!counting || last == null || now - last > longestGapMs || now < last) return;
    _togetherMs += now - last;
    if (_kept || _togetherMs < keepAfterMs) return;
    _kept = true;
    _keep();
  }

  void join() {
    if (_url == null || _inRoom || _disposed) return;
    _enter();
  }

  void decline() {
    if (_url == null) return;
    _declined = _url;
    notifyListeners();
  }

  void leave() {
    if (!_inRoom || _disposed) return;
    _keep();
    _countedAt = null;
    _inRoom = false;
    _dropPlayer();
    _beat();
    if (_partnerIn) {
      _declined = _url;
    } else {
      _publish(url: null, playing: false, hold: false, pos: 0);
    }
    _waitingSent = false;
    positionMs.value = 0;
    if (_url == null) _stopTimer();
    notifyListeners();
  }

  void togglePlay() {
    if (!_inRoom || _url == null) return;
    if (_playing) {
      _publish(url: _url, playing: false, hold: false, pos: _expected);
    } else {
      final hold = _partnerIn && _partnerWait;
      final player = _player;
      final ended = player != null && player.ready && !player.live && _pos >= player.durationMs - endWithinMs;
      _publish(url: _url, playing: true, hold: hold, pos: ended ? 0 : _pos, at: link.sharedNow() + leadMs);
      if (ended) unawaited(player.seekTo(0));
    }
    unawaited(tick());
  }

  void seek(int ms) {
    if (!_inRoom || _url == null) return;
    final target = math.max(0, ms);
    positionMs.value = target;
    _publish(url: _url, playing: _playing, hold: _hold, pos: target, at: link.sharedNow() + leadMs);
    unawaited(_player?.seekTo(target));
    unawaited(tick());
  }

  int get _expected {
    final moved = _playing && !_hold ? math.max(0, link.sharedNow() - _at) : 0;
    final expected = _pos + moved;
    final player = _player;
    if (player != null && player.ready && !player.live) return math.min(expected, player.durationMs);
    return expected;
  }

  void _publish({required String? url, required bool playing, required bool hold, required int pos, int? at}) {
    _seq = _seq >= maxSkyWatchSeq ? 1 : _seq + 1;
    _by = link.tag;
    _url = url;
    _playing = playing;
    _hold = hold;
    _pos = pos;
    _at = at ?? link.sharedNow();
    _offer();
    notifyListeners();
  }

  void _offer() {
    _lastOfferAt = link.now();
    unawaited(
      link.send(
        SkyWatchEvent(
          url: _url,
          playing: _playing,
          hold: _hold,
          pos: _pos,
          at: _at,
          seq: _seq,
          by: _by ?? link.tag,
          film: _film,
        ),
      ),
    );
  }

  void _beat() {
    _lastBeatAt = link.now();
    unawaited(
      link.send(
        SkyWatchBeatEvent(
          on: _inRoom && _foreground,
          wait: _inRoom && _waitingSent,
          fail: _inRoom && (_player?.failed ?? false),
          seq: _seq,
        ),
      ),
    );
  }

  void _enter() {
    _inRoom = true;
    _declined = null;
    _beat();
    _startTimer();
    final url = _url;
    if (url != null) unawaited(_load(url));
    notifyListeners();
  }

  Future<void> _load(String url) async {
    _dropPlayer();
    _loaded = url;
    _speed = 1;
    final player = WatchPlayers.create();
    _player = player;
    player.addListener(_onPlayer);
    notifyListeners();
    await player.load(url);
    if (_disposed || !identical(player, _player)) return;
    notifyListeners();
    await tick();
  }

  void _dropPlayer() {
    final player = _player;
    _player = null;
    _loaded = null;
    _bufferingSince = null;
    if (player == null) return;
    player.removeListener(_onPlayer);
    player.dispose();
  }

  void _onPlayer() {
    if (!_disposed) notifyListeners();
  }

  void _startTimer() {
    final every = _tickEvery;
    if (every == null || _timer != null) return;
    _timer = Timer.periodic(every, (_) => unawaited(tick()));
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _hear(SkyTogetherEvent event) {
    if (_disposed) return;
    switch (event) {
      case final SkyWatchEvent state:
        _hearState(state);
      case final SkyWatchBeatEvent beat:
        _hearBeat(beat);
      default:
        return;
    }
  }

  void _hearState(SkyWatchEvent state) {
    if (_url == null && !_inRoom) {
      _lastHeardAt = link.now();
      if (state.url == null) return;
    } else if (state.seq < _seq || (state.seq == _seq && state.by.compareTo(_by ?? '') <= 0)) {
      return;
    }
    if (state.url == null && _inRoom) {
      _partnerGone();
      return;
    }
    if (state.url != null) _newFilm(state.film);
    _seq = state.seq;
    _by = state.by;
    _url = state.url;
    _playing = state.playing;
    _hold = state.hold;
    _pos = state.pos;
    _at = state.at;
    _lastHeardAt = link.now();
    _partnerIn = state.url != null;
    if (state.url == null) _clearPartner();
    final url = _url;
    if (_inRoom && url != null && url != _loaded) {
      unawaited(_load(url));
    } else if (_inRoom) {
      unawaited(tick());
    } else if (url != null) {
      _startTimer();
    } else {
      _stopTimer();
    }
    notifyListeners();
  }

  void _hearBeat(SkyWatchBeatEvent beat) {
    _lastHeardAt = link.now();
    _partnerIn = beat.on;
    _partnerWait = beat.on && beat.wait;
    _partnerFail = beat.on && beat.fail;
    if (!beat.on) {
      _partnerGone();
      return;
    }
    if (_inRoom && beat.seq < _seq) _offer();
    if (_inRoom) unawaited(tick());
    notifyListeners();
  }

  void _clearPartner() {
    _partnerIn = false;
    _partnerWait = false;
    _partnerFail = false;
  }

  void _partnerGone() {
    _clearPartner();
    if (!_inRoom) {
      _url = null;
      _declined = null;
      _playing = false;
      _hold = false;
      _stopTimer();
    } else {
      unawaited(tick());
    }
    notifyListeners();
  }

  void _onLink() {
    if (_disposed) return;
    if (!link.linked && (_partnerIn || _partnerWait)) _partnerGone();
    final foreground = link.foreground;
    if (foreground == _foreground) return;
    _foreground = foreground;
    if (!_inRoom) return;
    if (!foreground) unawaited(_player?.pause());
    _beat();
    if (foreground) unawaited(tick());
  }

  bool _waiting(WatchPlayer? player) {
    if (player == null || player.failed || !_foreground) {
      _bufferingSince = null;
      return false;
    }
    if (!player.ready) return true;
    if (!player.buffering) {
      _bufferingSince = null;
      return false;
    }
    final now = link.now();
    final since = _bufferingSince ??= now;
    return now - since >= waitAfterMs;
  }

  Future<void> tick() async {
    if (_disposed || _ticking) return;
    _ticking = true;
    try {
      await _tick();
    } finally {
      _ticking = false;
    }
  }

  Future<void> _tick() async {
    final now = link.now();
    if (_partnerIn && now - _lastHeardAt > goneMs) _partnerGone();
    if (!_inRoom) {
      if (_url == null) _stopTimer();
      return;
    }
    final player = _player;
    final waiting = _waiting(player);
    final changed = waiting != _waitingSent;
    _waitingSent = waiting;
    if (changed || now - _lastBeatAt >= beatMs) _beat();
    if (!_partnerIn && _url != null && now - _lastOfferAt >= offerMs) _offer();
    if (!_foreground) return;
    if (player == null || !player.ready) {
      if (waiting && _playing && !_hold) _holdAt(_expected);
      return;
    }
    final pos = await player.position();
    if (_disposed || !identical(player, _player)) return;
    positionMs.value = pos;
    _settleHold(player, pos, waiting);
    await _steer(player, pos);
    if (!_disposed && identical(player, _player)) _count(player);
  }

  void _holdAt(int pos) => _publish(url: _url, playing: true, hold: true, pos: pos);

  void _settleHold(WatchPlayer player, int pos, bool waiting) {
    if (!_playing) return;
    if (!_hold && waiting) {
      final expected = _expected;
      _holdAt(pos + seekOverMs < expected ? expected : math.min(pos, expected));
      return;
    }
    if (_hold && !waiting && !(_partnerIn && _partnerWait)) {
      _publish(url: _url, playing: true, hold: false, pos: _pos, at: link.sharedNow() + leadMs);
    }
  }

  Future<void> _steer(WatchPlayer player, int pos) async {
    final end = player.durationMs - endWithinMs;
    if (!player.live && _playing && !_hold && pos >= end && _expected >= end) {
      _publish(url: _url, playing: false, hold: false, pos: player.durationMs);
    }
    final shouldPlay = _playing && !_hold && link.sharedNow() >= _at;
    if (!shouldPlay) {
      if (player.playing) await player.pause();
      await _setSpeed(player, 1);
      if (!player.live && !(_playing && !_hold) && (pos - _pos).abs() > restOverMs) await player.seekTo(_pos);
      return;
    }
    if (!player.playing) await player.play();
    if (player.live || player.buffering) return;
    final expected = _expected;
    final diff = pos - expected;
    if (diff.abs() > seekOverMs) {
      await _setSpeed(player, 1);
      await player.seekTo(expected);
    } else if (diff.abs() > nudgeOverMs) {
      await _setSpeed(player, diff > 0 ? 1 - nudge : 1 + nudge);
    } else if (diff.abs() <= settledMs) {
      await _setSpeed(player, 1);
    }
  }

  Future<void> _setSpeed(WatchPlayer player, double speed) async {
    if (speed == _speed) return;
    _speed = speed;
    await player.setSpeed(speed);
  }

  @override
  void dispose() {
    if (_disposed) return;
    if (_inRoom) {
      _keep();
      _inRoom = false;
      _beat();
    }
    _disposed = true;
    _stopTimer();
    _dropPlayer();
    link.removeListener(_onLink);
    unawaited(_events.cancel());
    positionMs.dispose();
    super.dispose();
  }
}
