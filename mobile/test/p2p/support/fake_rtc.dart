import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:our_space_mobile/core/engine/p2p/rtc.dart';
import 'package:our_space_mobile/core/engine/p2p/signal_socket.dart';

class FakeSignalSocket implements SignalSocket {
  FakeSignalSocket(this.url);

  final Uri url;
  final List<String> sent = [];
  bool _open = false;
  bool closed = false;

  @override
  void Function()? onOpen;
  @override
  void Function(String data)? onMessage;
  @override
  void Function()? onClose;

  @override
  bool get isOpen => _open && !closed;

  List<Map<String, Object?>> get sentMessages => [for (final s in sent) (jsonDecode(s) as Map).cast<String, Object?>()];

  void serverOpen() {
    _open = true;
    onOpen?.call();
  }

  void serverSend(Map<String, Object?> message) => onMessage?.call(jsonEncode(message));

  void serverClose() {
    _open = false;
    onClose?.call();
  }

  @override
  void send(String data) {
    if (!isOpen) return;
    sent.add(data);
  }

  @override
  void close() {
    closed = true;
    _open = false;
  }
}

class FakeSockets {
  final List<FakeSignalSocket> created = [];

  SignalSocket connect(Uri url) {
    final socket = FakeSignalSocket(url);
    created.add(socket);
    return socket;
  }

  FakeSignalSocket get last => created.last;
}

class FakeRtcChannel implements RtcChannel {
  FakeRtcChannel(this.label, {this.ordered = true, String readyState = 'connecting'}) : _state = readyState;

  @override
  final String label;
  final bool ordered;
  String _state;
  @override
  int bufferedAmount = 0;
  final List<Uint8List> sent = [];
  bool closedLocally = false;

  @override
  void Function()? onOpen;
  @override
  void Function()? onClose;
  @override
  void Function(Uint8List data)? onBinary;
  @override
  void Function(String text)? onText;

  @override
  String get readyState => _state;

  void openNow() {
    _state = 'open';
    onOpen?.call();
  }

  void deliver(Uint8List data) => onBinary?.call(data);

  void closeRemote() {
    _state = 'closed';
    onClose?.call();
  }

  @override
  Future<void> send(Uint8List data) async {
    sent.add(data);
  }

  @override
  Future<void> close() async {
    closedLocally = true;
    _state = 'closed';
  }
}

class FakeRtcSession implements RtcSession {
  FakeRtcSession(this.configuration, {this.holdLocal});

  final Completer<void>? holdLocal;

  final Map<String, Object?> configuration;
  final List<String> calls = [];
  final List<Map<String, Object?>> addedCandidates = [];
  final List<FakeRtcChannel> channels = [];
  Map<String, Object?>? localDescription;
  Map<String, Object?>? remoteDescription;
  String? _ice;
  bool closed = false;
  int _offers = 0;

  @override
  void Function(Map<String, Object?> candidate)? onIceCandidate;
  @override
  void Function(String state)? onIceConnectionState;
  @override
  void Function(RtcChannel channel)? onDataChannel;

  @override
  String? get iceConnectionState => _ice;

  @override
  String? get signalingState => closed ? 'closed' : 'stable';

  void emitCandidate(Map<String, Object?> candidate) => onIceCandidate?.call(candidate);

  void emitIce(String state) {
    _ice = state;
    onIceConnectionState?.call(state);
  }

  void emitDataChannel(FakeRtcChannel channel) {
    channels.add(channel);
    onDataChannel?.call(channel);
  }

  @override
  Future<RtcChannel> createDataChannel(String label, {required bool ordered}) async {
    calls.add('createDataChannel');
    final channel = FakeRtcChannel(label, ordered: ordered);
    channels.add(channel);
    return channel;
  }

  @override
  Future<Map<String, Object?>> createOffer() async {
    calls.add('createOffer');
    _offers++;
    return {'type': 'offer', 'sdp': 'v=0 offer $_offers'};
  }

  @override
  Future<Map<String, Object?>> createAnswer() async {
    calls.add('createAnswer');
    return {'type': 'answer', 'sdp': 'v=0 answer'};
  }

  @override
  Future<void> setLocalDescription(Map<String, Object?> description) async {
    calls.add('setLocalDescription:${description['type']}');
    final hold = holdLocal;
    if (hold != null) await hold.future;
    localDescription = description;
  }

  @override
  Future<void> setRemoteDescription(Map<String, Object?> description) async {
    calls.add('setRemoteDescription:${description['type']}');
    remoteDescription = description;
  }

  @override
  Future<void> addIceCandidate(Map<String, Object?> candidate) async {
    calls.add('addIceCandidate');
    addedCandidates.add(candidate);
  }

  @override
  Future<List<Map<String, Object?>>> getStats() async => const [];

  @override
  Future<void> close() async {
    calls.add('close');
    closed = true;
  }
}

class FakeRtc {
  final List<FakeRtcSession> sessions = [];
  Completer<void>? holdLocal;

  Future<RtcSession> create(Map<String, Object?> configuration) async {
    final session = FakeRtcSession(configuration, holdLocal: holdLocal);
    sessions.add(session);
    return session;
  }

  FakeRtcSession get last => sessions.last;
}

Future<void> drain([int rounds = 20]) async {
  for (var i = 0; i < rounds; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
