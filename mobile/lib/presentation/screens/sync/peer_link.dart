import 'package:flutter/foundation.dart';

import '../../../core/engine.dart';

enum PeerRoute { direct, relayed }

@immutable
class PeerLinkError {
  const PeerLinkError({required this.text, this.code = 'error'});

  static const String passphraseMismatch = 'passphrase_mismatch';

  final String text;
  final String code;
}

@immutable
class PeerLinkView {
  const PeerLinkView({
    this.myPeerId,
    this.partnerId,
    this.authorized = false,
    this.handshaking = false,
    this.connecting = false,
    this.syncing = false,
    this.route,
    this.error,
    this.lastConnectedAt,
    this.pendingInvite,
  });

  static const PeerLinkView offline = PeerLinkView();

  final String? myPeerId;
  final String? partnerId;
  final bool authorized;
  final bool handshaking;
  final bool connecting;
  final bool syncing;
  final PeerRoute? route;
  final PeerLinkError? error;
  final int? lastConnectedAt;
  final PendingPeerInvite? pendingInvite;
}

abstract class PeerLink extends ChangeNotifier {
  PeerLinkView get state;

  void connect(String partnerPeerId);

  void reconnect();

  void unpair();

  void syncNow();

  void clearError();

  void confirmInvite() {}

  void declineInvite() {}
}

class HubPeerLink extends PeerLink {
  HubPeerLink(this.hub) {
    hub.addListener(_changed);
  }

  final PeerSyncHub hub;
  bool _disposed = false;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  PeerLinkView get state {
    final error = hub.syncError;
    return PeerLinkView(
      myPeerId: hub.myPeerId,
      partnerId: hub.partnerId,
      authorized: hub.isAuthorized,
      handshaking: hub.isHandshaking,
      connecting: hub.isConnecting,
      syncing: hub.status.state == 'syncing',
      route: hub.isDirectP2P
          ? PeerRoute.direct
          : hub.isRelayed
              ? PeerRoute.relayed
              : null,
      error: error == null ? null : PeerLinkError(text: error.text, code: error.code),
      lastConnectedAt: hub.lastConnectedAt,
      pendingInvite: hub.pendingInvite,
    );
  }

  @override
  void connect(String partnerPeerId) => hub.connectToPartner(partnerPeerId);

  @override
  void reconnect() => hub.reconnectToPartner();

  @override
  void unpair() => hub.unpairPartner();

  @override
  void syncNow() => hub.syncNow().ignore();

  @override
  void clearError() => hub.clearSyncError();

  @override
  void confirmInvite() => hub.confirmPendingInvite();

  @override
  void declineInvite() => hub.declinePendingInvite();

  @override
  void dispose() {
    _disposed = true;
    hub.removeListener(_changed);
    super.dispose();
  }
}
