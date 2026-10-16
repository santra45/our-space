import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../crypto/js_compat.dart';
import 'peer_clock.dart';
import 'peer_endpoint.dart';
import 'peer_framing.dart';
import 'rtc.dart';
import 'signal_socket.dart';

const String peerJsVersion = '1.5.5';
const String peerJsCloudHost = '0.peerjs.com';
const int peerJsCloudPort = 443;
const String peerJsDefaultKey = 'peerjs';
const int peerJsPingIntervalMs = 5000;
const int peerJsMaxBufferedAmount = 8388608;
const String peerJsDataPrefix = 'dc_';

final RegExp peerJsIdPattern = RegExp(r'^[A-Za-z0-9]+(?:[ _-][A-Za-z0-9]+)*$');

final math.Random _tokenRandom = math.Random.secure();

String peerJsRandomToken() {
  const alphabet = '0123456789abcdefghijklmnopqrstuvwxyz';
  final buffer = StringBuffer();
  for (var i = 0; i < 11; i++) {
    buffer.write(alphabet[_tokenRandom.nextInt(alphabet.length)]);
  }
  return buffer.toString();
}

bool peerJsValidateId(String? id) => id == null || id.isEmpty || peerJsIdPattern.hasMatch(id);

class PeerJsOptions {
  PeerJsOptions({
    this.host = peerJsCloudHost,
    this.port = peerJsCloudPort,
    String path = '/',
    this.key = peerJsDefaultKey,
    String? token,
    bool? secure,
    this.pingIntervalMs = peerJsPingIntervalMs,
    this.iceServers = const [],
  })  : path = _normalisePath(path),
        token = token ?? peerJsRandomToken(),
        secure = host == peerJsCloudHost ? true : (secure ?? true);

  final String host;
  final int port;
  final String path;
  final String key;
  final String token;
  final bool secure;
  final int pingIntervalMs;
  final List<Map<String, Object?>> iceServers;

  Map<String, Object?> get rtcConfiguration => {'iceServers': iceServers};

  static String _normalisePath(String path) {
    var out = path;
    if (out.isEmpty) return out;
    if (!out.startsWith('/')) out = '/$out';
    if (!out.endsWith('/')) out = '$out/';
    return out;
  }
}

class PeerJsSocket {
  PeerJsSocket({
    required bool secure,
    required String host,
    required int port,
    required String path,
    required String key,
    required this.connector,
    required this.clock,
    this.pingIntervalMs = peerJsPingIntervalMs,
  }) : baseUrl = '${secure ? 'wss://' : 'ws://'}$host:$port${path}peerjs?key=$key';

  final String baseUrl;
  final SignalSocketConnector connector;
  final PeerClock clock;
  final int pingIntervalMs;

  void Function(Map<String, Object?> message)? onMessage;
  void Function()? onDisconnected;
  void Function(String error)? onError;

  bool _disconnected = true;
  SignalSocket? _socket;
  String? _id;
  List<Map<String, Object?>> _messagesQueue = [];
  Timer? _pingTimer;

  void start(String id, String token) {
    _id = id;
    final wsUrl = '$baseUrl&id=$id&token=$token';
    if (_socket != null || !_disconnected) return;
    final socket = connector(Uri.parse('$wsUrl&version=$peerJsVersion'));
    _socket = socket;
    _disconnected = false;

    socket.onMessage = (data) {
      Object? parsed;
      try {
        parsed = jsonDecode(data);
      } catch (_) {
        return;
      }
      final message = asStringMap(parsed);
      if (message == null) return;
      onMessage?.call(message);
    };

    socket.onClose = () {
      if (_disconnected) return;
      _cleanup();
      _disconnected = true;
      onDisconnected?.call();
    };

    socket.onOpen = () {
      if (_disconnected) return;
      _sendQueuedMessages();
      _scheduleHeartbeat();
    };
  }

  void _scheduleHeartbeat() {
    _pingTimer = clock.after(Duration(milliseconds: pingIntervalMs), _sendHeartbeat);
  }

  void _sendHeartbeat() {
    if (!_wsOpen()) return;
    _socket!.send(jsonEncode({'type': 'HEARTBEAT'}));
    _scheduleHeartbeat();
  }

  bool _wsOpen() => _socket != null && _socket!.isOpen;

  void _sendQueuedMessages() {
    final copied = [..._messagesQueue];
    _messagesQueue = [];
    for (final message in copied) {
      send(message);
    }
  }

  void send(Map<String, Object?> data) {
    if (_disconnected) return;
    if (_id == null) {
      _messagesQueue.add(data);
      return;
    }
    final type = data['type'];
    if (type == null || type == '') {
      onError?.call('Invalid message');
      return;
    }
    if (!_wsOpen()) return;
    _socket!.send(jsonEncode(data));
  }

  void close() {
    if (_disconnected) return;
    _cleanup();
    _disconnected = true;
  }

  void removeAllListeners() {
    onMessage = null;
    onDisconnected = null;
    onError = null;
  }

  void _cleanup() {
    final socket = _socket;
    if (socket != null) {
      socket.onOpen = null;
      socket.onMessage = null;
      socket.onClose = null;
      socket.close();
      _socket = null;
    }
    _pingTimer?.cancel();
    _pingTimer = null;
  }
}

class PeerJsPeer implements PeerEndpoint {
  PeerJsPeer(
    String? id, {
    required PeerJsOptions options,
    required SignalSocketConnector connector,
    required this._rtcFactory,
    PeerClock clock = const SystemPeerClock(),
  })  : _options = options,
        _clock = clock {
    _socket = PeerJsSocket(
      secure: options.secure,
      host: options.host,
      port: options.port,
      path: options.path,
      key: options.key,
      connector: connector,
      clock: clock,
      pingIntervalMs: options.pingIntervalMs,
    );
    _socket.onMessage = _handleMessage;
    _socket.onError = (error) => _abort(PeerError.socketError, error);
    _socket.onDisconnected = () {
      if (disconnected) return;
      _emitError(PeerError.network, 'Lost connection to server.');
      disconnect();
    };

    if (id != null && id.isNotEmpty && !peerJsValidateId(id)) {
      _clock.after(Duration.zero, () => _abort(PeerError.invalidId, 'ID "$id" is invalid'));
      return;
    }
    if (id != null && id.isNotEmpty) _initialize(id);
  }

  static PeerEndpointFactory factory({
    required SignalSocketConnector connector,
    required RtcSessionFactory rtcFactory,
    PeerClock clock = const SystemPeerClock(),
  }) {
    return (id, iceServers) => PeerJsPeer(
          id,
          options: PeerJsOptions(iceServers: iceServers),
          connector: connector,
          rtcFactory: rtcFactory,
          clock: clock,
        );
  }

  final PeerJsOptions _options;
  final RtcSessionFactory _rtcFactory;
  final PeerClock _clock;
  late final PeerJsSocket _socket;

  String? _id;
  String? _lastServerId;
  bool _destroyed = false;
  bool _disconnected = false;
  bool _open = false;
  final Map<String, List<PeerJsDataConnection>> _connections = {};
  final Map<String, List<Map<String, Object?>>> _lostMessages = {};

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

  PeerJsOptions get options => _options;

  PeerJsSocket get socket => _socket;

  RtcSessionFactory get rtcFactory => _rtcFactory;

  PeerClock get clock => _clock;

  @override
  String? get id => _id;

  @override
  bool get open => _open;

  @override
  bool get destroyed => _destroyed;

  @override
  bool get disconnected => _disconnected;

  void _emitError(String type, String message) {
    onError?.call(PeerError(type, message));
  }

  void emitWebRtcError(Object error) => _emitError(PeerError.webrtc, error.toString());

  void _initialize(String id) {
    _id = id;
    _socket.start(id, _options.token);
  }

  void _handleMessage(Map<String, Object?> message) {
    final type = message['type'];
    final payloadValue = message['payload'];
    final payload = payloadValue is Map ? asStringMap(payloadValue) : null;
    final src = message['src'];
    final peerId = src is String ? src : null;

    switch (type) {
      case 'OPEN':
        _lastServerId = id;
        _open = true;
        final current = id;
        if (current != null) onOpen?.call(current);
      case 'ERROR':
        _abort(PeerError.serverError, '${payload?['msg']}');
      case 'ID-TAKEN':
        _abort(PeerError.unavailableId, 'ID "$id" is taken');
      case 'INVALID-KEY':
        _abort(PeerError.invalidKey, 'API KEY "${_options.key}" is invalid');
      case 'LEAVE':
        if (peerId != null) {
          _cleanupPeer(peerId);
          _connections.remove(peerId);
        }
      case 'EXPIRE':
        _emitError(PeerError.peerUnavailable, 'Could not connect to peer $peerId');
      case 'OFFER':
        if (payload == null || peerId == null) return;
        final connectionId = payload['connectionId'];
        final existing = getConnection(peerId, connectionId);
        existing?.close();
        if (payload['type'] != 'data') return;
        final serialization = payload['serialization'];
        final connection = PeerJsDataConnection(
          peerId,
          this,
          connectionId: connectionId is String ? connectionId : null,
          label: payload['label'] is String ? payload['label'] as String : null,
          serialization: serialization is String ? serialization : 'binary',
          reliable: payload['reliable'] == true,
          offer: payload,
        );
        _addConnection(peerId, connection);
        onConnection?.call(connection);
        if (connectionId is String) {
          for (final lost in _getMessages(connectionId)) {
            connection.handleMessage(lost);
          }
        }
      default:
        if (payload == null) return;
        final connectionId = payload['connectionId'];
        final connection = peerId == null ? null : getConnection(peerId, connectionId);
        if (connection != null) {
          connection.handleMessage(message);
        } else if (connectionId is String) {
          _storeMessage(connectionId, message);
        }
    }
  }

  void _storeMessage(String connectionId, Map<String, Object?> message) {
    _lostMessages.putIfAbsent(connectionId, () => []).add(message);
  }

  List<Map<String, Object?>> _getMessages(String connectionId) => _lostMessages.remove(connectionId) ?? const [];

  @override
  PeerLink? connect(String peerId, {bool reliable = true}) {
    if (disconnected) {
      _emitError(PeerError.disconnected, 'Cannot connect to new Peer after disconnecting from server.');
      return null;
    }
    final connection = PeerJsDataConnection(peerId, this, reliable: reliable);
    _addConnection(peerId, connection);
    return connection;
  }

  void _addConnection(String peerId, PeerJsDataConnection connection) {
    _connections.putIfAbsent(peerId, () => []).add(connection);
  }

  void removeConnection(PeerJsDataConnection connection) {
    _connections[connection.peer]?.remove(connection);
    _lostMessages.remove(connection.connectionId);
  }

  PeerJsDataConnection? getConnection(String peerId, Object? connectionId) {
    final connections = _connections[peerId];
    if (connections == null) return null;
    for (final connection in connections) {
      if (connection.connectionId == connectionId) return connection;
    }
    return null;
  }

  void _abort(String type, String message) {
    _emitError(type, message);
    if (_lastServerId == null) {
      destroy();
    } else {
      disconnect();
    }
  }

  @override
  void destroy() {
    if (_destroyed) return;
    _destroyed = true;
    disconnect();
    _cleanup();
    onClose?.call();
  }

  void _cleanup() {
    for (final peerId in [..._connections.keys]) {
      _cleanupPeer(peerId);
      _connections.remove(peerId);
    }
    _socket.removeAllListeners();
  }

  void _cleanupPeer(String peerId) {
    final connections = _connections[peerId];
    if (connections == null) return;
    for (final connection in [...connections]) {
      connection.close();
    }
  }

  void disconnect() {
    if (_disconnected) return;
    final currentId = id;
    _disconnected = true;
    _open = false;
    _socket.close();
    _lastServerId = currentId;
    _id = null;
    onDisconnected?.call(currentId);
  }

  @override
  void reconnect() {
    if (_disconnected && !_destroyed) {
      _disconnected = false;
      final last = _lastServerId;
      if (last != null) _initialize(last);
    } else if (_destroyed) {
      throw StateError('This peer cannot reconnect to the server. It has already been destroyed.');
    } else if (!_disconnected && !_open) {
      return;
    } else {
      throw StateError('Peer $id cannot reconnect because it is not disconnected from the server!');
    }
  }
}

class _PeerJsRoute implements PeerRoute {
  _PeerJsRoute(this._connection);

  final PeerJsDataConnection _connection;
  final List<void Function(String state)> _listeners = [];

  @override
  String? get iceConnectionState => _connection.peerConnection?.iceConnectionState;

  @override
  Future<List<Map<String, Object?>>> getStats() async {
    final pc = _connection.peerConnection;
    if (pc == null) return const [];
    return pc.getStats();
  }

  @override
  void addIceListener(void Function(String state) listener) => _listeners.add(listener);

  @override
  void removeIceListener(void Function(String state) listener) => _listeners.remove(listener);

  void dispatch(String state) {
    for (final listener in [..._listeners]) {
      if (!_listeners.contains(listener)) continue;
      try {
        listener(state);
      } catch (_) {}
    }
  }
}

class PeerJsDataConnection implements PeerLink {
  PeerJsDataConnection(
    this.peer,
    PeerJsPeer provider, {
    String? connectionId,
    String? label,
    this.reliable = false,
    this.serialization = 'binary',
    Map<String, Object?>? offer,
  })  : _provider = provider,
        _signalling = provider,
        connectionId = connectionId ?? '$peerJsDataPrefix${peerJsRandomToken()}' {
    this.label = label ?? this.connectionId;
    _route = _PeerJsRoute(this);
    _negotiatorActive = true;
    _startConnection(offer);
  }

  @override
  final String peer;
  final String connectionId;
  late final String label;
  final bool reliable;
  final String serialization;

  PeerJsPeer? _provider;
  final PeerJsPeer _signalling;
  late final _PeerJsRoute _route;
  bool _negotiatorActive = false;

  RtcSession? peerConnection;
  RtcChannel? dataChannel;
  bool _open = false;
  final PeerFraming _framing = PeerFraming();
  List<Uint8List> _buffer = [];
  bool _buffering = false;
  Future<void> _operations = Future<void>.value();
  bool _remoteDescriptionSet = false;
  final List<Map<String, Object?>> _pendingRemoteCandidates = [];
  bool _localDescriptionSent = false;
  final List<Map<String, Object?>> _pendingLocalCandidates = [];

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

  @override
  PeerRoute? get route => _route;

  int get bufferSize => _buffer.length;

  void _enqueue(Future<void> Function() operation) {
    _operations = _operations.then((_) => operation()).catchError((Object _) {});
  }

  void _emitError(String type, String message) {
    onError?.call(PeerError(type, message));
  }

  void _startConnection(Map<String, Object?>? offer) {
    _enqueue(() async {
      final RtcSession pc;
      try {
        pc = await _signalling.rtcFactory(_signalling.options.rtcConfiguration);
      } catch (error) {
        _signalling.emitWebRtcError(error);
        return;
      }
      if (!_negotiatorActive) {
        unawaited(pc.close().catchError((Object _) {}));
        return;
      }
      peerConnection = pc;
      _setupListeners(pc);
      if (offer == null) {
        try {
          final channel = await pc.createDataChannel(label, ordered: reliable);
          _initializeDataChannel(channel);
        } catch (error) {
          _signalling.emitWebRtcError(error);
          return;
        }
        await _makeOffer();
      } else {
        await _handleSdp('OFFER', offer['sdp']);
      }
    });
  }

  void _setupListeners(RtcSession pc) {
    final provider = _signalling;
    pc.onIceCandidate = (candidate) {
      final text = candidate['candidate'];
      if (text is! String || text.isEmpty) return;
      final message = <String, Object?>{
        'type': 'CANDIDATE',
        'payload': {'candidate': candidate, 'type': 'data', 'connectionId': connectionId},
        'dst': peer,
      };
      if (!_localDescriptionSent) {
        _pendingLocalCandidates.add(message);
        return;
      }
      provider.socket.send(message);
    };
    pc.onIceConnectionState = (state) {
      switch (state) {
        case 'failed':
          _emitError('negotiation-failed', 'Negotiation of connection to $peer failed.');
          close();
        case 'closed':
          _emitError('connection-closed', 'Connection to $peer closed.');
          close();
        case 'completed':
          pc.onIceCandidate = (_) {};
      }
      _route.dispatch(state);
    };
    pc.onDataChannel = (channel) {
      final connection = provider.getConnection(peer, connectionId);
      connection?._initializeDataChannel(channel);
    };
  }

  void _flushLocalCandidates() {
    _localDescriptionSent = true;
    final pending = [..._pendingLocalCandidates];
    _pendingLocalCandidates.clear();
    for (final message in pending) {
      _signalling.socket.send(message);
    }
  }

  Future<void> _makeOffer() async {
    final pc = peerConnection;
    if (pc == null) return;
    try {
      final offer = await pc.createOffer();
      try {
        await pc.setLocalDescription(offer);
        _signalling.socket.send({
          'type': 'OFFER',
          'payload': {
            'sdp': offer,
            'type': 'data',
            'connectionId': connectionId,
            'label': label,
            'reliable': reliable,
            'serialization': serialization,
          },
          'dst': peer,
        });
        _flushLocalCandidates();
      } catch (error) {
        _signalling.emitWebRtcError(error);
      }
    } catch (error) {
      _signalling.emitWebRtcError(error);
    }
  }

  Future<void> _makeAnswer() async {
    final pc = peerConnection;
    if (pc == null) return;
    try {
      final answer = await pc.createAnswer();
      try {
        await pc.setLocalDescription(answer);
        _signalling.socket.send({
          'type': 'ANSWER',
          'payload': {'sdp': answer, 'type': 'data', 'connectionId': connectionId},
          'dst': peer,
        });
        _flushLocalCandidates();
      } catch (error) {
        _signalling.emitWebRtcError(error);
      }
    } catch (error) {
      _signalling.emitWebRtcError(error);
    }
  }

  Future<void> _handleSdp(String type, Object? sdp) async {
    final pc = peerConnection;
    if (pc == null) return;
    final description = sdp is Map ? asStringMap(sdp)! : <String, Object?>{};
    try {
      await pc.setRemoteDescription({'type': description['type'], 'sdp': description['sdp']});
      _remoteDescriptionSet = true;
      final pending = [..._pendingRemoteCandidates];
      _pendingRemoteCandidates.clear();
      for (final candidate in pending) {
        await _handleCandidate(candidate);
      }
      if (type == 'OFFER') await _makeAnswer();
    } catch (error) {
      _signalling.emitWebRtcError(error);
    }
  }

  Future<void> _handleCandidate(Map<String, Object?> candidate) async {
    final pc = peerConnection;
    if (pc == null) return;
    if (!_remoteDescriptionSet) {
      _pendingRemoteCandidates.add(candidate);
      return;
    }
    try {
      await pc.addIceCandidate(candidate);
    } catch (error) {
      _signalling.emitWebRtcError(error);
    }
  }

  void handleMessage(Map<String, Object?> message) {
    final payloadValue = message['payload'];
    final payload = payloadValue is Map ? asStringMap(payloadValue)! : <String, Object?>{};
    switch (message['type']) {
      case 'ANSWER':
        _enqueue(() => _handleSdp('ANSWER', payload['sdp']));
      case 'CANDIDATE':
        final candidate = payload['candidate'];
        if (candidate is Map) _enqueue(() => _handleCandidate(asStringMap(candidate)!));
    }
  }

  void _initializeDataChannel(RtcChannel channel) {
    dataChannel = channel;
    channel.onOpen = () {
      if (!identical(dataChannel, channel)) return;
      _open = true;
      onOpen?.call();
    };
    channel.onBinary = (data) {
      if (!identical(dataChannel, channel)) return;
      _handleDataMessage(data);
    };
    channel.onText = (_) {};
    channel.onClose = () {
      if (!identical(dataChannel, channel)) return;
      close();
    };
  }

  void _handleDataMessage(Uint8List data) {
    PeerFrameResult result;
    try {
      result = _framing.decode(data);
    } catch (_) {
      return;
    }
    switch (result.kind) {
      case PeerFrameKind.close:
        close();
      case PeerFrameKind.partial:
        break;
      case PeerFrameKind.message:
        onData?.call(result.data);
    }
  }

  @override
  void send(Object? data) {
    if (!open) {
      _emitError('not-open-yet', 'Connection is not open. You should listen for the `open` event before sending messages.');
      return;
    }
    for (final frame in _framing.encode(data)) {
      _bufferedSend(frame);
    }
  }

  void _bufferedSend(Uint8List message) {
    if (_buffering || !_trySend(message)) {
      _buffer.add(message);
    }
  }

  bool _trySend(Uint8List message) {
    if (!open) return false;
    final channel = dataChannel;
    if (channel == null) return false;
    if (channel.bufferedAmount > peerJsMaxBufferedAmount) {
      _buffering = true;
      _signalling.clock.after(const Duration(milliseconds: 50), () {
        _buffering = false;
        _tryBuffer();
      });
      return false;
    }
    try {
      channel.send(message).catchError((Object _) {
        _buffering = true;
        close();
      });
    } catch (_) {
      _buffering = true;
      close();
      return false;
    }
    return true;
  }

  void _tryBuffer() {
    if (!open) return;
    while (_buffer.isNotEmpty) {
      if (!_trySend(_buffer.first)) return;
      _buffer.removeAt(0);
    }
  }

  @override
  void close() {
    _buffer = [];
    if (_negotiatorActive) {
      _negotiatorActive = false;
      final pc = peerConnection;
      peerConnection = null;
      if (pc != null) {
        pc.onIceCandidate = (_) {};
        pc.onIceConnectionState = (_) {};
        pc.onDataChannel = (_) {};
        unawaited(pc.close().catchError((Object _) {}));
      }
    }
    final provider = _provider;
    if (provider != null) {
      provider.removeConnection(this);
      _provider = null;
    }
    final channel = dataChannel;
    if (channel != null) {
      channel.onOpen = null;
      channel.onBinary = null;
      channel.onText = null;
      channel.onClose = null;
      dataChannel = null;
    }
    _framing.reset();
    if (!open) return;
    _open = false;
    onClose?.call();
  }
}
