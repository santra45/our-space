class PeerError {
  const PeerError(this.type, [this.message = '']);

  static const String unavailableId = 'unavailable-id';
  static const String peerUnavailable = 'peer-unavailable';
  static const String network = 'network';
  static const String serverError = 'server-error';
  static const String socketError = 'socket-error';
  static const String socketClosed = 'socket-closed';
  static const String invalidId = 'invalid-id';
  static const String invalidKey = 'invalid-key';
  static const String disconnected = 'disconnected';
  static const String webrtc = 'webrtc';
  static const String browserIncompatible = 'browser-incompatible';

  final String type;
  final String message;

  @override
  String toString() => 'PeerError($type)';
}

abstract class PeerRoute {
  String? get iceConnectionState;

  Future<List<Map<String, Object?>>> getStats();

  void addIceListener(void Function(String state) listener);

  void removeIceListener(void Function(String state) listener);
}

abstract class PeerLink {
  String get peer;

  bool get open;

  PeerRoute? get route;

  void Function()? onOpen;
  void Function(Object? data)? onData;
  void Function()? onClose;
  void Function(Object error)? onError;

  void send(Object? data);

  void close();
}

abstract class PeerEndpoint {
  String? get id;

  bool get open;

  bool get destroyed;

  bool get disconnected;

  void Function(String id)? onOpen;
  void Function(PeerLink link)? onConnection;
  void Function(PeerError error)? onError;
  void Function(String? id)? onDisconnected;
  void Function()? onClose;

  PeerLink? connect(String peerId, {bool reliable = true});

  void reconnect();

  void destroy();
}

typedef PeerEndpointFactory = PeerEndpoint Function(String id, List<Map<String, Object?>> iceServers);
