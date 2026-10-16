import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:our_space_mobile/core/engine/p2p/rtc.dart';

class LocalPeerServer {
  LocalPeerServer._(this._server) {
    _server.listen(_handle);
  }

  static Future<LocalPeerServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return LocalPeerServer._(server);
  }

  final HttpServer _server;
  final Map<String, WebSocket> clients = {};
  final List<Uri> connections = [];
  final List<Map<String, Object?>> relayed = [];
  int heartbeats = 0;

  int get port => _server.port;

  Future<void> _handle(HttpRequest request) async {
    if (request.uri.path != '/peerjs') {
      request.response.statusCode = 404;
      await request.response.close();
      return;
    }
    connections.add(request.uri);
    final id = request.uri.queryParameters['id'] ?? '';
    final socket = await WebSocketTransformer.upgrade(request);
    if (clients.containsKey(id)) {
      socket.add(jsonEncode({
        'type': 'ID-TAKEN',
        'payload': {'msg': 'ID is taken'},
      }));
      await socket.close();
      return;
    }
    clients[id] = socket;
    socket.add(jsonEncode({'type': 'OPEN'}));
    socket.listen(
      (data) {
        final message = (jsonDecode(data as String) as Map).cast<String, Object?>();
        final type = message['type'];
        if (type == 'HEARTBEAT') {
          heartbeats++;
          return;
        }
        final forwarded = {...message, 'src': id};
        relayed.add(forwarded);
        final target = clients[message['dst']];
        if (target != null) {
          target.add(jsonEncode(forwarded));
        } else if (type == 'OFFER') {
          Timer(const Duration(milliseconds: 30), () {
            if (clients[id] == socket) socket.add(jsonEncode({'type': 'EXPIRE', 'src': message['dst'], 'dst': id}));
          });
        }
      },
      onDone: () {
        if (clients[id] == socket) clients.remove(id);
      },
    );
  }

  Future<void> dropAll() async {
    for (final socket in [...clients.values]) {
      await socket.close();
    }
    clients.clear();
  }

  Future<void> close() async {
    await dropAll();
    await _server.close(force: true);
  }
}

class LoopbackChannel implements RtcChannel {
  LoopbackChannel(this.label, {this._state = 'connecting'});

  @override
  final String label;
  String _state;
  LoopbackChannel? partner;
  bool _openFired = false;
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
    if (callback != null && _state == 'open') scheduleMicrotask(_fireOpen);
  }

  void _fireOpen() {
    if (_openFired || _onOpen == null) return;
    _openFired = true;
    _onOpen!();
  }

  void markOpen() {
    _state = 'open';
    _fireOpen();
  }

  @override
  String get readyState => _state;

  @override
  int get bufferedAmount => 0;

  @override
  Future<void> send(Uint8List data) async {
    final target = partner;
    if (target == null || _state != 'open') throw StateError('closed');
    final copy = Uint8List.fromList(data);
    Timer.run(() {
      if (target._state == 'open') target.onBinary?.call(copy);
    });
  }

  void _remoteClosed() {
    if (_state == 'closed') return;
    _state = 'closed';
    onClose?.call();
  }

  @override
  Future<void> close() async {
    if (_state == 'closed') return;
    _state = 'closed';
    final target = partner;
    if (target != null) Timer.run(target._remoteClosed);
  }
}

class LoopbackRtc {
  final Map<String, LoopbackSession> _sessions = {};
  int _next = 0;

  Future<RtcSession> create(Map<String, Object?> configuration) async {
    final session = LoopbackSession(this, 's${_next++}', configuration);
    _sessions[session.name] = session;
    return session;
  }
}

class LoopbackSession implements RtcSession {
  LoopbackSession(this._rtc, this.name, this.configuration);

  final LoopbackRtc _rtc;
  final String name;
  final Map<String, Object?> configuration;
  final List<LoopbackChannel> _channels = [];
  final List<Map<String, Object?>> addedCandidates = [];
  String? _ice;
  bool _closed = false;

  @override
  void Function(Map<String, Object?> candidate)? onIceCandidate;
  @override
  void Function(String state)? onIceConnectionState;
  @override
  void Function(RtcChannel channel)? onDataChannel;

  @override
  String? get iceConnectionState => _ice;

  @override
  String? get signalingState => _closed ? 'closed' : 'stable';

  @override
  Future<RtcChannel> createDataChannel(String label, {required bool ordered}) async {
    final channel = LoopbackChannel(label);
    _channels.add(channel);
    return channel;
  }

  @override
  Future<Map<String, Object?>> createOffer() async => {'type': 'offer', 'sdp': 'loop:$name'};

  @override
  Future<Map<String, Object?>> createAnswer() async => {'type': 'answer', 'sdp': 'loop:$name'};

  @override
  Future<void> setLocalDescription(Map<String, Object?> description) async {
    Timer.run(() => onIceCandidate?.call({'candidate': 'candidate:$name 1 udp 1 127.0.0.1 9 typ host', 'sdpMid': '0', 'sdpMLineIndex': 0}));
  }

  @override
  Future<void> setRemoteDescription(Map<String, Object?> description) async {
    final sdp = description['sdp'] as String;
    final remote = _rtc._sessions[sdp.substring('loop:'.length)];
    if (remote == null) throw StateError('unknown session');
    if (description['type'] != 'answer') return;
    final mine = _channels.single;
    final theirs = LoopbackChannel(mine.label, state: 'open');
    mine.partner = theirs;
    theirs.partner = mine;
    remote._channels.add(theirs);
    Timer.run(() {
      _ice = 'connected';
      remote._ice = 'connected';
      onIceConnectionState?.call('connected');
      remote.onIceConnectionState?.call('connected');
      remote.onDataChannel?.call(theirs);
      mine.markOpen();
    });
  }

  @override
  Future<void> addIceCandidate(Map<String, Object?> candidate) async => addedCandidates.add(candidate);

  @override
  Future<List<Map<String, Object?>>> getStats() async => [
        {'id': 'pair', 'type': 'candidate-pair', 'nominated': true, 'localCandidateId': 'l', 'remoteCandidateId': 'r'},
        {'id': 'l', 'type': 'local-candidate', 'candidateType': 'host'},
        {'id': 'r', 'type': 'remote-candidate', 'candidateType': 'host'},
      ];

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final channel in _channels) {
      await channel.close();
    }
  }
}
