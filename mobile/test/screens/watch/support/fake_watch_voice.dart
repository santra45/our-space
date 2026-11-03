import 'package:flutter/foundation.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/presentation/screens/watch/watch_voice.dart';

class FakeWatchVoice extends ChangeNotifier implements WatchVoice {
  bool? offering;
  bool disposed = false;
  final List<SkyWatchVoiceEvent> heard = [];
  void Function(String what, String text, {String? mid, int? line})? _send;
  bool _connected = false;
  bool _failed = false;

  @override
  bool get connected => _connected;

  @override
  bool get failed => _failed;

  @override
  Future<void> start({
    required bool offering,
    required void Function(String what, String text, {String? mid, int? line}) send,
  }) async {
    this.offering = offering;
    _send = send;
    if (offering) send('offer', 'offer-sdp');
  }

  @override
  Future<void> hear(SkyWatchVoiceEvent signal) async {
    heard.add(signal);
    if (signal.what == skyVoiceOffer) _send?.call('answer', 'answer-sdp');
  }

  void sendIce() => _send?.call('ice', 'candidate', mid: '0', line: 0);

  void connect() {
    _connected = true;
    notifyListeners();
  }

  void lose() {
    _connected = false;
    notifyListeners();
  }

  void fail() {
    _failed = true;
    _connected = false;
    notifyListeners();
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}
