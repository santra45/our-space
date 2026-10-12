import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'rtc.dart';

Future<RtcSession> createFlutterRtcSession(Map<String, Object?> configuration) async {
  final pc = await createPeerConnection({...configuration, 'sdpSemantics': 'unified-plan'});
  return FlutterRtcSession(pc);
}

String _iceStateName(RTCIceConnectionState state) => switch (state) {
      RTCIceConnectionState.RTCIceConnectionStateNew => 'new',
      RTCIceConnectionState.RTCIceConnectionStateChecking => 'checking',
      RTCIceConnectionState.RTCIceConnectionStateConnected => 'connected',
      RTCIceConnectionState.RTCIceConnectionStateCompleted => 'completed',
      RTCIceConnectionState.RTCIceConnectionStateFailed => 'failed',
      RTCIceConnectionState.RTCIceConnectionStateDisconnected => 'disconnected',
      RTCIceConnectionState.RTCIceConnectionStateClosed => 'closed',
      RTCIceConnectionState.RTCIceConnectionStateCount => 'count',
    };

String _signalingStateName(RTCSignalingState state) => switch (state) {
      RTCSignalingState.RTCSignalingStateStable => 'stable',
      RTCSignalingState.RTCSignalingStateHaveLocalOffer => 'have-local-offer',
      RTCSignalingState.RTCSignalingStateHaveRemoteOffer => 'have-remote-offer',
      RTCSignalingState.RTCSignalingStateHaveLocalPrAnswer => 'have-local-pranswer',
      RTCSignalingState.RTCSignalingStateHaveRemotePrAnswer => 'have-remote-pranswer',
      RTCSignalingState.RTCSignalingStateClosed => 'closed',
    };

class FlutterRtcSession implements RtcSession {
  FlutterRtcSession(this._pc) {
    _pc.onIceCandidate = (candidate) {
      final text = candidate.candidate;
      if (text == null || text.isEmpty) return;
      onIceCandidate?.call({
        'candidate': text,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };
    _pc.onIceConnectionState = (state) => onIceConnectionState?.call(_iceStateName(state));
    _pc.onDataChannel = (channel) {
      final wrapped = FlutterRtcChannel(channel);
      _channels.add(wrapped);
      onDataChannel?.call(wrapped);
    };
  }

  final RTCPeerConnection _pc;
  final List<FlutterRtcChannel> _channels = [];
  bool _closed = false;

  @override
  void Function(Map<String, Object?> candidate)? onIceCandidate;
  @override
  void Function(String state)? onIceConnectionState;
  @override
  void Function(RtcChannel channel)? onDataChannel;

  @override
  String? get iceConnectionState {
    final state = _pc.iceConnectionState;
    return state == null ? null : _iceStateName(state);
  }

  @override
  String? get signalingState {
    if (_closed) return 'closed';
    final state = _pc.signalingState;
    return state == null ? null : _signalingStateName(state);
  }

  @override
  Future<RtcChannel> createDataChannel(String label, {required bool ordered}) async {
    final init = RTCDataChannelInit()..ordered = ordered;
    final channel = FlutterRtcChannel(await _pc.createDataChannel(label, init));
    _channels.add(channel);
    return channel;
  }

  Map<String, Object?> _description(RTCSessionDescription description) => {
        'type': description.type,
        'sdp': description.sdp,
      };

  @override
  Future<Map<String, Object?>> createOffer() async => _description(await _pc.createOffer(<String, dynamic>{}));

  @override
  Future<Map<String, Object?>> createAnswer() async => _description(await _pc.createAnswer(<String, dynamic>{}));

  @override
  Future<void> setLocalDescription(Map<String, Object?> description) =>
      _pc.setLocalDescription(RTCSessionDescription(description['sdp'] as String?, description['type'] as String?));

  @override
  Future<void> setRemoteDescription(Map<String, Object?> description) =>
      _pc.setRemoteDescription(RTCSessionDescription(description['sdp'] as String?, description['type'] as String?));

  @override
  Future<void> addIceCandidate(Map<String, Object?> candidate) {
    final index = candidate['sdpMLineIndex'];
    return _pc.addCandidate(RTCIceCandidate(
      candidate['candidate'] as String?,
      candidate['sdpMid'] as String?,
      index is num ? index.toInt() : null,
    ));
  }

  @override
  Future<List<Map<String, Object?>>> getStats() async {
    final reports = await _pc.getStats();
    return [
      for (final report in reports)
        {
          for (final entry in report.values.entries) entry.key.toString(): entry.value as Object?,
          'id': report.id,
          'type': report.type,
          'timestamp': report.timestamp,
        },
    ];
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    onIceCandidate = null;
    onIceConnectionState = null;
    onDataChannel = null;
    for (final channel in _channels) {
      channel.detach();
    }
    try {
      await _pc.close();
    } catch (_) {}
    try {
      await _pc.dispose();
    } catch (_) {}
  }
}

class FlutterRtcChannel implements RtcChannel {
  FlutterRtcChannel(this._channel) {
    _channel.onDataChannelState = (state) {
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        _fireOpen();
      } else if (state == RTCDataChannelState.RTCDataChannelClosed) {
        if (_closeFired) return;
        _closeFired = true;
        onClose?.call();
      }
    };
    _channel.onMessage = (message) {
      if (message.isBinary) {
        onBinary?.call(message.binary);
      } else {
        onText?.call(message.text);
      }
    };
  }

  final RTCDataChannel _channel;
  bool _openFired = false;
  bool _closeFired = false;
  void Function()? _onOpen;

  @override
  void Function()? onClose;
  @override
  void Function(Uint8List data)? onBinary;
  @override
  void Function(String text)? onText;

  @override
  void Function()? get onOpen => _onOpen;

  @override
  set onOpen(void Function()? callback) {
    _onOpen = callback;
    if (callback != null && readyState == 'open' && !_openFired) {
      scheduleMicrotask(_fireOpen);
    }
  }

  void _fireOpen() {
    if (_openFired) return;
    final callback = _onOpen;
    if (callback == null) return;
    _openFired = true;
    callback();
  }

  void detach() {
    _onOpen = null;
    onClose = null;
    onBinary = null;
    onText = null;
  }

  @override
  String get label => _channel.label ?? '';

  @override
  String get readyState => switch (_channel.state) {
        RTCDataChannelState.RTCDataChannelOpen => 'open',
        RTCDataChannelState.RTCDataChannelClosing => 'closing',
        RTCDataChannelState.RTCDataChannelClosed => 'closed',
        _ => 'connecting',
      };

  @override
  int get bufferedAmount => _channel.bufferedAmount ?? 0;

  @override
  Future<void> send(Uint8List data) => _channel.send(RTCDataChannelMessage.fromBinary(data));

  @override
  Future<void> close() => _channel.close();
}
