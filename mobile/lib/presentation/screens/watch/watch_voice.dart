import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../core/engine.dart';
import '../../../core/engine/p2p/flutter_rtc.dart';
import '../../../core/engine/p2p/ice_servers.dart';

abstract class WatchVoice implements Listenable {
  bool get connected;

  bool get failed;

  Future<void> start({
    required bool offering,
    required void Function(String what, String text, {String? mid, int? line}) send,
  });

  Future<void> hear(SkyWatchVoiceEvent signal);

  void dispose();
}

abstract final class WatchVoices {
  static WatchVoice Function() create = NativeWatchVoice.new;
  static Future<bool> Function() askMic = NativeWatchVoice.askMic;
}

class NativeWatchVoice extends ChangeNotifier implements WatchVoice {
  static Future<bool> askMic() async {
    try {
      await prepareFilmFriendlyAudio();
      await Helper.setAndroidAudioConfiguration(filmFriendlyAudio);
      final mic = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': false});
      for (final track in mic.getTracks()) {
        await track.stop();
      }
      await mic.dispose();
      return true;
    } catch (_) {
      return false;
    }
  }

  RTCPeerConnection? _pc;
  MediaStream? _mic;
  Future<void>? _starting;
  void Function(String what, String text, {String? mid, int? line})? _send;
  final List<RTCIceCandidate> _early = [];
  bool _answered = false;
  bool _connected = false;
  bool _failed = false;
  bool _disposed = false;

  @override
  bool get connected => _connected;

  @override
  bool get failed => _failed;

  @override
  Future<void> start({
    required bool offering,
    required void Function(String what, String text, {String? mid, int? line}) send,
  }) {
    _send = send;
    return _starting ??= _open(offering);
  }

  Future<void> _open(bool offering) async {
    try {
      await prepareFilmFriendlyAudio();
      await Helper.setAndroidAudioConfiguration(filmFriendlyAudio);
      final pc = await createPeerConnection({
        'iceServers': [
          for (final url in stunUrls) {'urls': url},
        ],
        'sdpSemantics': 'unified-plan',
      });
      if (_disposed) {
        await pc.close();
        return;
      }
      _pc = pc;
      pc.onIceCandidate = (candidate) {
        final text = candidate.candidate;
        if (text == null || text.isEmpty) return;
        _send?.call('ice', text, mid: candidate.sdpMid, line: candidate.sdpMLineIndex);
      };
      pc.onIceConnectionState = _onIce;
      final mic = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': false});
      if (_disposed) {
        await _closeMic(mic);
        return;
      }
      _mic = mic;
      for (final track in mic.getAudioTracks()) {
        await pc.addTrack(track, mic);
      }
      if (!offering || _disposed) return;
      final offer = await pc.createOffer();
      if (_disposed) return;
      await pc.setLocalDescription(offer);
      final sdp = offer.sdp;
      if (sdp != null) _send?.call('offer', sdp);
    } catch (error) {
      debugPrint('WatchVoice: could not start');
      _fail();
    }
  }

  void _onIce(RTCIceConnectionState state) {
    debugPrint('WatchVoice: $state');
    if (_disposed) return;
    if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
      _fail();
      return;
    }
    final connected =
        state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
        state == RTCIceConnectionState.RTCIceConnectionStateCompleted;
    if (connected == _connected) return;
    _connected = connected;
    notifyListeners();
  }

  void _fail() {
    if (_disposed || _failed) return;
    _failed = true;
    _connected = false;
    notifyListeners();
  }

  @override
  Future<void> hear(SkyWatchVoiceEvent signal) async {
    await _starting;
    final pc = _pc;
    if (pc == null || _disposed) return;
    try {
      switch (signal.what) {
        case skyVoiceOffer:
          await pc.setRemoteDescription(RTCSessionDescription(signal.text, 'offer'));
          await _flushEarly(pc);
          final answer = await pc.createAnswer();
          if (_disposed) return;
          await pc.setLocalDescription(answer);
          final sdp = answer.sdp;
          if (sdp != null) _send?.call('answer', sdp);
        case skyVoiceAnswer:
          await pc.setRemoteDescription(RTCSessionDescription(signal.text, 'answer'));
          await _flushEarly(pc);
        case skyVoiceIce:
          final candidate = RTCIceCandidate(signal.text, signal.mid, signal.line);
          if (_answered) {
            await pc.addCandidate(candidate);
          } else {
            _early.add(candidate);
          }
      }
    } catch (error) {
      debugPrint('WatchVoice: could not use a signal');
      _fail();
    }
  }

  Future<void> _flushEarly(RTCPeerConnection pc) async {
    _answered = true;
    final waiting = List<RTCIceCandidate>.of(_early);
    _early.clear();
    for (final candidate in waiting) {
      await pc.addCandidate(candidate);
    }
  }

  static Future<void> _closeMic(MediaStream mic) async {
    for (final track in mic.getTracks()) {
      await track.stop();
    }
    await mic.dispose();
  }

  Future<void> _close() async {
    await _starting?.catchError((Object _) {});
    final mic = _mic;
    final pc = _pc;
    _mic = null;
    _pc = null;
    try {
      if (mic != null) await _closeMic(mic);
      await pc?.close();
      await pc?.dispose();
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true;
    _send = null;
    unawaited(_close());
    super.dispose();
  }
}
