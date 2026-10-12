import 'dart:async';
import 'dart:typed_data';

import 'package:our_space_mobile/core/engine/p2p/peer_endpoint.dart';
import 'package:our_space_mobile/core/engine/p2p/peer_framing.dart';

class FakeRoute implements PeerRoute {
  FakeRoute({this.stats = const []});

  List<Map<String, Object?>> stats;
  String? state;
  final List<void Function(String state)> listeners = [];

  @override
  String? get iceConnectionState => state;

  @override
  Future<List<Map<String, Object?>>> getStats() async => stats;

  @override
  void addIceListener(void Function(String state) listener) => listeners.add(listener);

  @override
  void removeIceListener(void Function(String state) listener) => listeners.remove(listener);

  void emit(String value) {
    state = value;
    for (final listener in [...listeners]) {
      if (listeners.contains(listener)) listener(value);
    }
  }
}

class SentFrame {
  SentFrame(this.from, this.bytes);
  final String from;
  final Uint8List bytes;
}

class FakeLink implements PeerLink {
  FakeLink(this.peer, {required this.owner, this.route});

  @override
  final String peer;
  final String owner;
  @override
  PeerRoute? route;

  bool _open = false;
  bool closed = false;
  FakeLink? remote;
  final PeerFraming _framing = PeerFraming();
  final List<Object?> sent = [];
  final List<Uint8List> frames = [];
  List<SentFrame>? transcript;
  bool holdOutgoing = false;
  final List<Uint8List> held = [];

  @override
  void Function()? onOpen;
  @override
  void Function(Object? data)? onData;
  @override
  void Function()? onClose;
  @override
  void Function(Object error)? onError;

  @override
  bool get open => _open;

  void openNow() {
    if (closed) return;
    _open = true;
    onOpen?.call();
  }

  @override
  void send(Object? data) {
    if (!_open) {
      onError?.call(const PeerError('not-open-yet'));
      return;
    }
    sent.add(data);
    for (final frame in _framing.encode(data)) {
      frames.add(frame);
      transcript?.add(SentFrame(owner, frame));
      if (holdOutgoing) {
        held.add(frame);
        continue;
      }
      final target = remote;
      if (target != null) Timer.run(() => target.receiveFrame(frame));
    }
  }

  void releaseHeld() {
    final frames = [...held];
    held.clear();
    final target = remote;
    if (target == null) return;
    for (final frame in frames) {
      Timer.run(() => target.receiveFrame(frame));
    }
  }

  void receiveFrame(Uint8List frame) {
    if (!_open) return;
    final result = _framing.decode(frame);
    switch (result.kind) {
      case PeerFrameKind.message:
        onData?.call(result.data);
      case PeerFrameKind.close:
        close();
      case PeerFrameKind.partial:
        break;
    }
  }

  void receive(Object? data) {
    if (!_open) return;
    onData?.call(data);
  }

  @override
  void close() {
    closed = true;
    if (!_open) return;
    _open = false;
    onClose?.call();
    final target = remote;
    if (target != null) Timer.run(target.close);
  }

  void fail(Object error) => onError?.call(error);
}

class FakeEndpoint implements PeerEndpoint {
  FakeEndpoint(this.requestedId, this.iceServers, this.network);

  final String requestedId;
  final List<Map<String, Object?>> iceServers;
  final FakeNetwork? network;

  String? _id;
  bool _open = false;
  bool _destroyed = false;
  bool _disconnected = false;
  int reconnects = 0;
  final List<FakeLink> dialed = [];

  @override
  void Function(String id)? onOpen;
  @override
  void Function(PeerLink link)? onConnection;
  @override
  void Function(PeerError error)? onError;
  @override
  void Function(String? id)? onDisconnected;
  @override
  void Function()? onClose;

  @override
  String? get id => _id;
  @override
  bool get open => _open;
  @override
  bool get destroyed => _destroyed;
  @override
  bool get disconnected => _disconnected;

  void serverOpen() {
    _id = requestedId;
    _open = true;
    _disconnected = false;
    onOpen?.call(requestedId);
  }

  void serverError(String type, [String message = '']) => onError?.call(PeerError(type, message));

  void drop() {
    _open = false;
    _disconnected = true;
    onDisconnected?.call(_id);
  }

  void incoming(FakeLink link) => onConnection?.call(link);

  @override
  PeerLink? connect(String peerId, {bool reliable = true}) {
    if (_disconnected) {
      onError?.call(const PeerError(PeerError.disconnected));
      return null;
    }
    final link = FakeLink(peerId, owner: requestedId);
    dialed.add(link);
    network?.dial(this, link);
    return link;
  }

  @override
  void reconnect() {
    if (_destroyed) throw StateError('destroyed');
    reconnects++;
    _disconnected = false;
  }

  @override
  void destroy() {
    if (_destroyed) return;
    _destroyed = true;
    _open = false;
    _disconnected = true;
    network?.endpoints.remove(requestedId);
    onClose?.call();
  }
}

class FakeNetwork {
  final Map<String, FakeEndpoint> endpoints = {};
  final List<FakeEndpoint> created = [];
  final List<SentFrame> transcript = [];
  bool autoOpenServer = true;
  bool autoOpenLinks = true;
  bool deliverDials = true;

  PeerEndpoint create(String id, List<Map<String, Object?>> iceServers) {
    final endpoint = FakeEndpoint(id, iceServers, this);
    endpoints[id] = endpoint;
    created.add(endpoint);
    if (autoOpenServer) Timer.run(() => endpoint.destroyed ? null : endpoint.serverOpen());
    return endpoint;
  }

  void dial(FakeEndpoint from, FakeLink outgoing) {
    outgoing.transcript = transcript;
    if (!deliverDials) return;
    final target = endpoints[outgoing.peer];
    if (target == null) return;
    final incoming = FakeLink(from.requestedId, owner: target.requestedId)..transcript = transcript;
    outgoing.remote = incoming;
    incoming.remote = outgoing;
    Timer.run(() {
      if (target.destroyed) return;
      target.incoming(incoming);
      if (autoOpenLinks) {
        Timer.run(() {
          incoming.openNow();
          outgoing.openNow();
        });
      }
    });
  }
}
