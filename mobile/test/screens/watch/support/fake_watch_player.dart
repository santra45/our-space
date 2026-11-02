import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:our_space_mobile/presentation/screens/watch/watch_player.dart';

class FakeWatchPlayer extends ChangeNotifier implements WatchPlayer {
  FakeWatchPlayer({this.durationMs = 3600000, this.loadsAtOnce = true, this.failsToLoad = false});

  @override
  int durationMs;

  final bool loadsAtOnce;
  final bool failsToLoad;
  final Completer<void> _loading = Completer<void>();
  final List<int> seeks = [];
  final List<double> speeds = [];
  final List<String?> pickedSubtitles = [];
  final List<String> pickedAudio = [];

  @override
  List<WatchTrack> audioTracks = const [];

  @override
  List<WatchTrack> subtitleTracks = const [];

  @override
  List<String> cues = const [];

  String? url;
  bool isReady = false;
  bool isBuffering = false;
  bool isFailed = false;
  bool isPlaying = false;
  bool isLive = false;
  bool disposed = false;
  double speed = 1;
  int positionNow = 0;

  @override
  bool get ready => isReady && !isFailed;

  @override
  bool get buffering => isBuffering;

  @override
  bool get failed => isFailed;

  @override
  bool get playing => isPlaying;

  @override
  bool get live => isLive;

  @override
  double get aspect => 16 / 9;

  @override
  Future<void> load(String url) {
    this.url = url;
    if (loadsAtOnce) finishLoading();
    return _loading.future;
  }

  void finishLoading() {
    if (_loading.isCompleted) return;
    if (failsToLoad) {
      isFailed = true;
    } else {
      isReady = true;
    }
    _loading.complete();
    notifyListeners();
  }

  void run(int ms) {
    if (!isPlaying || isBuffering || !ready) return;
    positionNow = (positionNow + ms * speed).round();
    if (!isLive && positionNow >= durationMs) {
      positionNow = durationMs;
      isPlaying = false;
    }
  }

  @override
  Future<int> position() async => positionNow;

  @override
  Future<void> play() async {
    isPlaying = true;
    notifyListeners();
  }

  @override
  Future<void> pause() async {
    isPlaying = false;
    notifyListeners();
  }

  @override
  Future<void> seekTo(int ms) async {
    seeks.add(ms);
    positionNow = ms;
  }

  @override
  Future<void> setSpeed(double value) async {
    speeds.add(value);
    speed = value;
  }

  @override
  Future<void> selectAudio(String id) async {
    pickedAudio.add(id);
    audioTracks = [
      for (final track in audioTracks)
        WatchTrack(id: track.id, label: track.label, detail: track.detail, selected: track.id == id),
    ];
    notifyListeners();
  }

  @override
  Future<void> selectSubtitle(String? id) async {
    pickedSubtitles.add(id);
    subtitleTracks = [
      for (final track in subtitleTracks)
        WatchTrack(id: track.id, label: track.label, detail: track.detail, selected: track.id == id),
    ];
    notifyListeners();
  }

  void show(List<String> lines) {
    cues = lines;
    notifyListeners();
  }

  @override
  Widget view() => const ColoredBox(color: Color(0xFF101010));

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}
