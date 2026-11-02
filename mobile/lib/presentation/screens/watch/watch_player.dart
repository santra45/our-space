import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

abstract class WatchPlayer implements Listenable {
  bool get ready;

  bool get buffering;

  bool get failed;

  bool get playing;

  bool get live;

  int get durationMs;

  double get aspect;

  Future<void> load(String url);

  Future<int> position();

  Future<void> play();

  Future<void> pause();

  Future<void> seekTo(int ms);

  Future<void> setSpeed(double speed);

  Widget view();

  void dispose();
}

abstract final class WatchPlayers {
  static WatchPlayer Function() create = ExoWatchPlayer.new;
}

class ExoWatchPlayer extends ChangeNotifier implements WatchPlayer {
  static const int _longestMs = 30 * 24 * 60 * 60 * 1000;

  VideoPlayerController? _controller;
  bool _failed = false;

  VideoPlayerValue get _value => _controller?.value ?? const VideoPlayerValue.uninitialized();

  @override
  bool get ready => _value.isInitialized && !failed;

  @override
  bool get buffering => _value.isBuffering;

  @override
  bool get failed => _failed || _value.hasError;

  @override
  bool get playing => _value.isPlaying;

  @override
  bool get live => durationMs <= 0 || durationMs > _longestMs;

  @override
  int get durationMs => _value.duration.inMilliseconds;

  @override
  double get aspect => _value.isInitialized ? _value.aspectRatio : 16 / 9;

  @override
  Future<void> load(String url) async {
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    _controller = controller;
    controller.addListener(notifyListeners);
    try {
      await controller.initialize();
    } catch (_) {
      _failed = true;
    }
    notifyListeners();
  }

  @override
  Future<int> position() async {
    final controller = _controller;
    if (controller == null) return 0;
    try {
      return (await controller.position)?.inMilliseconds ?? _value.position.inMilliseconds;
    } catch (_) {
      return _value.position.inMilliseconds;
    }
  }

  Future<void> _guard(Future<void> Function(VideoPlayerController controller) task) async {
    final controller = _controller;
    if (controller == null || !ready) return;
    try {
      await task(controller);
    } catch (_) {
      _failed = true;
      notifyListeners();
    }
  }

  @override
  Future<void> play() => _guard((controller) => controller.play());

  @override
  Future<void> pause() => _guard((controller) => controller.pause());

  @override
  Future<void> seekTo(int ms) => _guard((controller) => controller.seekTo(Duration(milliseconds: ms)));

  @override
  Future<void> setSpeed(double speed) => _guard((controller) => controller.setPlaybackSpeed(speed));

  @override
  Widget view() {
    final controller = _controller;
    return controller == null ? const SizedBox.shrink() : VideoPlayer(controller);
  }

  @override
  void dispose() {
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      controller.removeListener(notifyListeners);
      controller.dispose().ignore();
    }
    super.dispose();
  }
}
