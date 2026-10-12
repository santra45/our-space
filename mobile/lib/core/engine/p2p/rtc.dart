import 'dart:typed_data';

abstract class RtcChannel {
  String get label;

  String get readyState;

  int get bufferedAmount;

  void Function()? onOpen;
  void Function()? onClose;
  void Function(Uint8List data)? onBinary;
  void Function(String text)? onText;

  Future<void> send(Uint8List data);

  Future<void> close();
}

abstract class RtcSession {
  void Function(Map<String, Object?> candidate)? onIceCandidate;
  void Function(String state)? onIceConnectionState;
  void Function(RtcChannel channel)? onDataChannel;

  String? get iceConnectionState;

  String? get signalingState;

  Future<RtcChannel> createDataChannel(String label, {required bool ordered});

  Future<Map<String, Object?>> createOffer();

  Future<Map<String, Object?>> createAnswer();

  Future<void> setLocalDescription(Map<String, Object?> description);

  Future<void> setRemoteDescription(Map<String, Object?> description);

  Future<void> addIceCandidate(Map<String, Object?> candidate);

  Future<List<Map<String, Object?>>> getStats();

  Future<void> close();
}

typedef RtcSessionFactory = Future<RtcSession> Function(Map<String, Object?> configuration);
