import 'package:flutter/foundation.dart';

enum PeerRoute { direct, relayed }

@immutable
class PeerLinkError {
  const PeerLinkError({required this.text, this.code = 'error'});

  static const String passphraseMismatch = 'passphrase_mismatch';

  final String text;
  final String code;
}

@immutable
class PeerLinkState {
  const PeerLinkState({
    this.myPeerId,
    this.partnerId,
    this.authorized = false,
    this.handshaking = false,
    this.connecting = false,
    this.syncing = false,
    this.route,
    this.error,
    this.lastConnectedAt,
  });

  static const PeerLinkState offline = PeerLinkState();

  final String? myPeerId;
  final String? partnerId;
  final bool authorized;
  final bool handshaking;
  final bool connecting;
  final bool syncing;
  final PeerRoute? route;
  final PeerLinkError? error;
  final int? lastConnectedAt;
}

abstract class PeerLink extends ChangeNotifier {
  PeerLinkState get state;

  void connect(String partnerPeerId);

  void reconnect();

  void unpair();

  void syncNow();

  void clearError();
}
