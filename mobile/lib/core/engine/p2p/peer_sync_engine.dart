import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;

import '../crypto/aes_gcm.dart';
import '../crypto/base64.dart';
import '../crypto/envelope.dart';
import '../crypto/js_compat.dart';
import '../domain/limits.dart';
import '../identity/device_id.dart';
import '../invite/invite.dart';
import '../storage/local_settings.dart';
import '../storage/merge_rules.dart';
import '../storage/tables.dart';
import '../storage/vault_store.dart' show IncomingRow;
import 'binary_pack.dart';
import 'ice_servers.dart';
import 'peer_clock.dart';
import 'peer_endpoint.dart';
import 'peer_records.dart';
import 'peer_status.dart';

const String peerProtocolId = 'SWEETHEART_V2';
const String legacyPeerProtocolId = 'SWEETHEART_V1';

const int maxCiphertextLength = 30 * 1024 * 1024;

const int authTimeoutMs = 30000;
const int connectOpenTimeoutMs = 15000;
const int unknownConnectOpenTimeoutMs = 8000;
const int unknownAuthTimeoutMs = 12000;
const int strangerEvictAfterMs = 3000;

const int admissionBackoffBaseMs = 2000;
const int admissionBackoffMaxMs = 5 * 60 * 1000;
const int knownPeerFreeAttempts = 3;
const int knownPeerBackoffMaxMs = 15000;
const int admissionEntryTtlMs = 30 * 60 * 1000;
const int admissionMaxTrackedPeers = 128;
const int admissionFloodWindowMs = 60000;
const int admissionFloodMaxUnknown = 6;
const int admissionWarnIntervalMs = 30000;

const int heartbeatIntervalMs = 15000;
const int heartbeatTimeoutMs = 50000;
const int syncSessionTimeoutMs = 120000;

const int maxDecryptFailures = 5;
const int maxPeerRequestsPerSession = 5000;
const int maxConcurrentSessions = 4;
const int maxPeerCoupleNamesLength = 120;

const int routeProbeIntervalMs = 1500;
const int routeProbeMaxAttempts = 12;

const int unavailableIdRetryMs = 1200;
const int offloadCryptoChars = 256 * 1024;
const int signalReconnectMaxMs = 30000;

final RegExp isoDateRegex = RegExp(r'^\d{4}-\d{2}-\d{2}$');

const String iceFailureMessage =
    'Could not open a direct connection to your partner. This app uses no relay server, so a strict mobile network (CGNAT) on either side can block pairing. Try putting both devices on the same Wi-Fi, or switch one device to a different network.';

const String openTimeoutMessage =
    'Could not open a direct connection to your partner. This app uses no relay server, so a strict mobile network (CGNAT) on either side can block pairing. Try the same Wi-Fi network, or a different network on one device.';

const String localPeerIdKey = 'sweetheart_device_peer_id';
const String knownPartnerKey = 'sweetheart_known_partner_peer';

const Set<String> allowedPeerMessageTypes = {
  'CHALLENGE',
  'CHALLENGE_RESPONSE',
  'CHALLENGE_ACK',
  'SYNC_MANIFEST',
  'SYNC_REQUEST_RECORDS',
  'SYNC_RECORDS_BATCH',
  'SYNC_COMPLETE',
  'SYNC_ERROR',
  'LIVE_RECORD_BROADCAST',
  'SYNC_CONFIG',
  'PING',
  'PONG',
};

final Set<String> allowedPeerTables = syncedTables.where((name) => name != vaultMetaTable).toSet();

const List<String> wireFieldsCommon = ['id', 'updatedAt', 'deleted', 'v', 'ciphertext', 'iv'];

const Map<String, List<String>> wireFieldsByTable = {
  memoriesTable: [],
};

Set<String> wireFieldsFor(String table) => {...wireFieldsCommon, ...(wireFieldsByTable[table] ?? const <String>[])};

String unverifiableWarningText(int count) {
  final plural = count == 1 ? '' : 's';
  return '$count change$plural from your partner did not come through. '
      'Make sure Our Space is up to date on both phones, then open it again.';
}

class PeerSyncFailure implements Exception {
  PeerSyncFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class _Session {
  _Session(this.id, this.kind, this.startedAt, {this.phase, this.requested = 0});

  final String id;
  final String kind;
  final int startedAt;
  String? phase;
  final int requested;
  int applied = 0;
  int rejected = 0;
  int unverifiable = 0;
  int expectedSeq = 0;
  Timer? timer;
}

class _Admission {
  _Admission(this.lastSeenAt);
  int attempts = 0;
  int blockedUntil = 0;
  int lastSeenAt;
}

class _Verdict {
  const _Verdict(this.allowed, [this.reason]);
  final bool allowed;
  final String? reason;
}

class _Check {
  const _Check(this.ok, [this.code, this.unverified = false]);
  final bool ok;
  final String? code;
  final bool unverified;
}

class _Staged {
  _Staged(this.staged, this.rejected, this.reasons);
  final List<IncomingRow> staged;
  final int rejected;
  final Map<String, int> reasons;
}

class _Applied {
  const _Applied(this.applied, this.rejected, this.stale, this.unverifiable);
  final int applied;
  final int rejected;
  final int stale;
  final int unverifiable;
}

String _formatCount(num value) => jsNumberToString(value);

bool _isFinite(Object? value) => value is num && value.isFinite;

class PeerSyncEngine {
  PeerSyncEngine({
    required this.records,
    required this.settings,
    required this._endpointFactory,
    this._clock = const SystemPeerClock(),
    this._nonce = generateSecureNonce,
    this._newPeerId = generatePeerId,
    this._iceServers = buildIceServers,
    this._observeRemote,
  }) {
    _knownPartnerId = _storedKnownPartnerId();
  }

  final PeerRecordSource records;
  final LocalSettings settings;
  final PeerEndpointFactory _endpointFactory;
  final PeerClock _clock;
  final String Function(int bytes) _nonce;
  final String Function() _newPeerId;
  final List<Map<String, Object?>> Function() _iceServers;
  final void Function(num stamp)? _observeRemote;

  PeerEndpoint? peer;
  PeerLink? activeConnection;
  String? myPeerId;
  VaultKey? cryptoKey;

  bool isConnected = false;
  bool isAuthorized = false;
  bool isSyncing = false;

  String? pendingChallengeNonce;
  String? dialingPeerId;

  String? _knownPartnerId;
  final Map<String, _Admission> _admission = <String, _Admission>{};
  List<int> _unknownAdmissions = <int>[];
  bool _slotKnown = false;
  int _slotSince = 0;
  bool _slotProgressed = false;
  int _admissionWarnedAt = 0;

  Timer? _authTimeoutTimer;
  Timer? _connectOpenTimer;
  Timer? _heartbeatTimer;
  int lastPongAt = 0;

  String? connectionType;
  Timer? _routeProbeTimer;
  int _routeProbeAttempts = 0;
  void Function(String state)? _iceListener;
  PeerRoute? _icePeerConnection;
  bool _routeFailed = false;

  int decryptFailures = 0;

  final Map<String, _Session> _outSessions = <String, _Session>{};
  final Map<String, _Session> _inSessions = <String, _Session>{};

  bool _clockSkewWarned = false;
  num _observedRemoteMax = 0;

  Future<void> _sendTail = Future<void>.value();
  Future<void> _inboundTail = Future<void>.value();

  bool _hasRetriedUnavailableId = false;
  Completer<String>? _initCompleter;
  Timer? _unavailableRetryTimer;
  Timer? _signalReconnectTimer;
  int _signalDrops = 0;

  final List<void Function(PeerStatus status)> _statusListeners = [];
  final List<void Function(PeerDataUpdate update)> _dataListeners = [];
  final List<void Function(PeerConfigUpdate config)> _configListeners = [];
  final List<void Function(String table, String id)> _localRecordListeners = [];

  PeerStatus _lastStatus = PeerStatus.initial;

  PeerStatus get lastStatus => _lastStatus;

  num get observedRemoteMax => _observedRemoteMax;

  bool get hasOpenSessions => _outSessions.isNotEmpty || _inSessions.isNotEmpty;

  PeerLinkState get linkState {
    if (isConnected) {
      if (!isAuthorized) return PeerLinkState.connected;
      return isSyncing ? PeerLinkState.syncing : PeerLinkState.authorised;
    }
    if (activeConnection != null || dialingPeerId != null) return PeerLinkState.connecting;
    return PeerLinkState.disconnected;
  }

  void addStatusListener(void Function(PeerStatus status) listener) => _statusListeners.add(listener);
  void removeStatusListener(void Function(PeerStatus status) listener) => _statusListeners.remove(listener);
  void addDataListener(void Function(PeerDataUpdate update) listener) => _dataListeners.add(listener);
  void removeDataListener(void Function(PeerDataUpdate update) listener) => _dataListeners.remove(listener);
  void addConfigListener(void Function(PeerConfigUpdate config) listener) => _configListeners.add(listener);
  void removeConfigListener(void Function(PeerConfigUpdate config) listener) => _configListeners.remove(listener);
  void addLocalRecordListener(void Function(String table, String id) listener) => _localRecordListeners.add(listener);
  void removeLocalRecordListener(void Function(String table, String id) listener) =>
      _localRecordListeners.remove(listener);

  String? _storedKnownPartnerId() {
    final id = settings.getItem(knownPartnerKey);
    if (id != null && peerIdRegex.hasMatch(id)) return id;
    return null;
  }

  String? _storedDevicePeerId() {
    final id = settings.getItem(localPeerIdKey);
    if (id != null && peerIdRegex.hasMatch(id)) return id;
    return null;
  }

  void _setStoredDevicePeerId(String? id) {
    if (id != null && peerIdRegex.hasMatch(id)) unawaited(settings.setItem(localPeerIdKey, id));
  }

  void _setStoredKnownPartnerId(String? id) {
    if (id != null && peerIdRegex.hasMatch(id)) unawaited(settings.setItem(knownPartnerKey, id));
  }

  void _emitStatus(Map<String, Object?> fields) {
    final status = PeerStatus(fields);
    _lastStatus = status;
    for (final listener in [..._statusListeners]) {
      try {
        listener(status);
      } catch (_) {}
    }
  }

  void _emitData(PeerDataUpdate update) {
    for (final listener in [..._dataListeners]) {
      try {
        listener(update);
      } catch (_) {}
    }
  }

  void _emitConfig(PeerConfigUpdate config) {
    for (final listener in [..._configListeners]) {
      try {
        listener(config);
      } catch (_) {}
    }
  }

  String _currentState() {
    if (!isConnected) return 'disconnected';
    if (!isAuthorized) return 'handshaking';
    return isSyncing ? 'syncing' : 'authorized';
  }

  void _emitWarning(String code, String warning, [Map<String, Object?> extra = const {}]) {
    _emitStatus({
      'state': _currentState(),
      'code': code,
      'warning': warning,
      'partnerId': activeConnection?.peer,
      'connectionType': connectionType,
      'isDirect': connectionType == 'direct',
      ...extra,
    });
  }

  void _emitFatal(String code, String error, [String state = 'error']) {
    if (activeConnection != null || isConnected) {
      _closeActiveConnection();
    }
    _emitStatus({'state': state, 'code': code, 'error': error});
  }

  Future<String> init(VaultKey key, [String? customId]) {
    cryptoKey = key;

    final current = peer;
    if (current != null && !current.destroyed && current.open) {
      return Future<String>.value(myPeerId);
    }

    final pending = _initCompleter;
    if (pending != null) return pending.future;

    if (customId != null && customId.isNotEmpty && !peerIdRegex.hasMatch(customId)) {
      return Future<String>.error(PeerSyncFailure('Invalid custom Peer ID format'));
    }

    final iceServers = _iceServers();
    final completer = Completer<String>();
    _initCompleter = completer;

    var peerId = (customId != null && customId.isNotEmpty) ? customId : null;
    peerId ??= _storedDevicePeerId();
    if (peerId == null) {
      peerId = _newPeerId();
      _setStoredDevicePeerId(peerId);
    }
    final chosenId = peerId;

    final PeerEndpoint created;
    try {
      created = _endpointFactory(chosenId, iceServers);
    } catch (_) {
      _initCompleter = null;
      completer.completeError(PeerSyncFailure('Could not start the connection on this phone.'));
      return completer.future;
    }
    peer = created;

    void settle(Future<String> next) {
      next.then((id) {
        if (!completer.isCompleted) completer.complete(id);
      }, onError: (Object error) {
        if (!completer.isCompleted) completer.completeError(error);
      });
    }

    created.onOpen = (id) {
      myPeerId = id;
      _hasRetriedUnavailableId = false;
      _signalDrops = 0;
      _setStoredDevicePeerId(id);
      if (identical(_initCompleter, completer)) _initCompleter = null;
      _emitStatus({'state': 'ready', 'code': 'peer_ready', 'peerId': id});
      if (!completer.isCompleted) completer.complete(id);
    };

    created.onConnection = (conn) {
      if (!identical(peer, created)) {
        try {
          conn.close();
        } catch (_) {}
        return;
      }
      _setupConnection(conn, false);
    };

    created.onError = (err) {
      if (!identical(peer, created)) return;
      if (err.type == PeerError.unavailableId) {
        if (!_hasRetriedUnavailableId) {
          _hasRetriedUnavailableId = true;
          _unavailableRetryTimer?.cancel();
          _unavailableRetryTimer = _clock.after(const Duration(milliseconds: unavailableIdRetryMs), () {
            _unavailableRetryTimer = null;
            if (!identical(peer, created)) return;
            _closeActiveConnection();
            try {
              peer?.destroy();
            } catch (_) {}
            peer = null;
            _initCompleter = null;
            settle(init(key, chosenId));
          });
          return;
        }
        _hasRetriedUnavailableId = false;
        final freshId = _newPeerId();
        _setStoredDevicePeerId(freshId);
        _closeActiveConnection();
        peer = null;
        _initCompleter = null;
        settle(init(key, freshId));
        return;
      }

      var message = 'Could not reach your partner right now.';
      if (err.type == PeerError.peerUnavailable) {
        message = 'Cannot find their phone. Ask them to open Our Space and leave it on screen.';
        _closeActiveConnection();
      } else if (err.type == PeerError.network) {
        message = 'Trouble with the connection. Check your internet and try again.';
      }

      if (isAuthorized && (activeConnection?.open ?? false)) {
        _emitWarning('signalling_${err.type}', message, {'errorType': err.type});
        return;
      }

      if (activeConnection != null || isConnected) _closeActiveConnection();
      _emitStatus({
        'state': 'error',
        'code': err.type.isEmpty ? 'peer_error' : err.type,
        'error': message,
        'errorType': err.type,
      });
    };

    created.onDisconnected = (_) {
      if (!identical(peer, created) || created.destroyed) return;
      _signalDrops++;
      if (_signalDrops <= 1) {
        try {
          created.reconnect();
        } catch (_) {}
        return;
      }
      final delay = math.min(1000 * math.pow(2, _signalDrops - 2).toInt(), signalReconnectMaxMs);
      _signalReconnectTimer?.cancel();
      _signalReconnectTimer = _clock.after(Duration(milliseconds: delay), () {
        _signalReconnectTimer = null;
        if (!identical(peer, created) || created.destroyed || !created.disconnected) return;
        try {
          created.reconnect();
        } catch (_) {}
      });
    };

    return completer.future;
  }

  Future<void> connectToPartner(String? partnerPeerId) async {
    final cleanId = jsTrim(partnerPeerId ?? '');
    if (cleanId.isEmpty || !peerIdRegex.hasMatch(cleanId) || cleanId == myPeerId) {
      throw PeerSyncFailure('Invalid Partner Peer ID format');
    }

    if (isConnected && isAuthorized && activeConnection?.peer == cleanId) return;

    if (peer == null || peer!.destroyed) {
      final key = cryptoKey;
      if (key != null) {
        await init(key);
      } else {
        throw PeerSyncFailure('Peer not initialized');
      }
    }

    final pending = _initCompleter;
    if (!(peer?.open ?? false) && pending != null) {
      await pending.future;
    }

    final ready = peer;
    if (ready == null || ready.destroyed || !ready.open) {
      throw PeerSyncFailure('Peer signaling not ready');
    }

    if (activeConnection != null) _closeActiveConnection();

    dialingPeerId = cleanId;
    _emitStatus({'state': 'connecting', 'code': 'dialing', 'partnerId': cleanId});

    final conn = ready.connect(cleanId, reliable: true);
    _setupConnection(conn, true);
  }

  bool _isKnownPeer(String? peerId) {
    if (peerId == null || peerId.isEmpty) return false;
    return peerId == dialingPeerId || peerId == _knownPartnerId;
  }

  void _pruneAdmission(int now) {
    _admission.removeWhere((_, entry) => now - entry.lastSeenAt > admissionEntryTtlMs);
    while (_admission.length > admissionMaxTrackedPeers) {
      _admission.remove(_admission.keys.first);
    }
    _unknownAdmissions = _unknownAdmissions.where((t) => now - t < admissionFloodWindowMs).toList();
  }

  _Verdict _admitInbound(String peerId, bool isKnown) {
    final now = _clock.now();
    _pruneAdmission(now);

    final entry = _admission[peerId];
    if (entry != null && entry.blockedUntil > now) return const _Verdict(false, 'backoff');

    if (!isKnown && _unknownAdmissions.length >= admissionFloodMaxUnknown) {
      return const _Verdict(false, 'flood');
    }
    return const _Verdict(true);
  }

  void _noteAdmission(String peerId, bool isKnown) {
    final now = _clock.now();
    final entry = _admission[peerId] ?? _Admission(now);
    entry.attempts += 1;
    entry.lastSeenAt = now;

    int backoff;
    if (isKnown) {
      final over = entry.attempts - knownPeerFreeAttempts;
      backoff = over <= 0 ? 0 : math.min(1000 * math.pow(2, over - 1).toInt(), knownPeerBackoffMaxMs);
    } else {
      backoff = math.min(admissionBackoffBaseMs * math.pow(2, entry.attempts - 1).toInt(), admissionBackoffMaxMs);
      _unknownAdmissions.add(now);
    }
    entry.blockedUntil = now + backoff;

    _admission.remove(peerId);
    _admission[peerId] = entry;
  }

  void noteAdmissionSuccess(String? peerId) {
    if (peerId == null || peerId.isEmpty) return;
    _admission.remove(peerId);
    _knownPartnerId = peerId;
    _setStoredKnownPartnerId(peerId);
  }

  void _refuseConnection(PeerLink conn, String warningCode, String warningText) {
    try {
      conn.close();
    } catch (_) {}
    _refuseWarn(warningCode, warningText);
  }

  bool _mayEvictIncumbent(PeerLink conn) {
    if (activeConnection == null || isAuthorized) return false;
    if (_slotKnown) return false;
    if (_isKnownPeer(conn.peer)) return true;
    if (_slotProgressed) return false;
    return _clock.now() - _slotSince >= strangerEvictAfterMs;
  }

  void _setupConnection(PeerLink? conn, bool isInitiator) {
    if (conn == null) return;
    if (identical(activeConnection, conn)) return;

    final isKnown = isInitiator || _isKnownPeer(conn.peer);

    final existing = activeConnection;
    if (existing != null) {
      if (isAuthorized) {
        if (conn.peer != existing.peer) {
          _refuseConnection(conn, 'unknown_peer_rejected', 'Someone else tried to connect. We said no.');
          return;
        }
      } else {
        final expectedPeer = dialingPeerId ?? existing.peer;
        if (conn.peer != expectedPeer) {
          if (!_mayEvictIncumbent(conn)) {
            _refuseConnection(
              conn,
              'unknown_peer_rejected',
              'Someone else tried to connect while you were pairing. We said no.',
            );
            return;
          }
        } else if (myPeerId != null && myPeerId!.compareTo(conn.peer) <= 0) {
          try {
            conn.close();
          } catch (_) {}
          return;
        }
      }
    }

    if (!isInitiator) {
      final verdict = _admitInbound(conn.peer, isKnown);
      if (!verdict.allowed) {
        final flood = verdict.reason == 'flood';
        _refuseConnection(
          conn,
          flood ? 'pairing_flood' : 'peer_rate_limited',
          flood
              ? 'A few unknown phones are trying to connect, so pairing is paused for a minute. This does not affect your partner.'
              : 'A phone is retrying too fast, so we asked it to wait a moment.',
        );
        return;
      }
      _noteAdmission(conn.peer, isKnown);
    }

    _closeActiveConnection();
    if (isInitiator) dialingPeerId = conn.peer;
    activeConnection = conn;
    decryptFailures = 0;
    _routeFailed = false;
    _slotKnown = isKnown;
    _slotSince = _clock.now();
    _slotProgressed = false;

    _startAuthTimeout(conn, isKnown);
    _startConnectOpenTimeout(conn, isKnown);

    Future<void> handleOpen() async {
      if (!identical(activeConnection, conn)) return;
      _clearConnectOpenTimeout();
      isConnected = true;

      _emitStatus({'state': 'handshaking', 'code': 'channel_open', 'partnerId': conn.peer});

      if (isInitiator) {
        try {
          await _sendAuthChallenge();
        } catch (_) {
          _closeActiveConnection();
          _emitFatal('challenge_failed', 'Could not start the connection. Try again.');
        }
      }
    }

    if (conn.open) {
      unawaited(handleOpen());
    } else {
      conn.onOpen = () => unawaited(handleOpen());
    }

    conn.onData = (data) {
      if (!identical(activeConnection, conn)) return;
      _handleMessage(data).catchError((Object err) => _handlePipelineError(err));
    };

    conn.onClose = () {
      if (!identical(activeConnection, conn)) return;
      final routeFailed = _routeFailed;
      _closeActiveConnection();
      if (!routeFailed) {
        _emitStatus({'state': 'disconnected', 'code': 'peer_closed'});
      }
    };

    conn.onError = (_) {
      if (identical(activeConnection, conn)) {
        _closeActiveConnection();
        _emitFatal('data_channel_error', 'The connection dropped.');
      }
    };
  }

  void _handlePipelineError(Object err) {
    if (isStorageFullError(err)) {
      _abortAllSessions('storage_full', silent: true);
      _emitFatal(
        'storage_full',
        'This phone is out of space, so new memories could not be saved. Free some space and try again.',
      );
      return;
    }
    _emitWarning('message_failed', 'Something came through that we could not use, so we skipped it.');
  }

  void _startAuthTimeout(PeerLink conn, [bool isKnown = true]) {
    _clearAuthTimeout();
    final timeout = isKnown ? authTimeoutMs : unknownAuthTimeoutMs;
    final quiet = !isKnown && _knownPartnerId != null;
    _authTimeoutTimer = _clock.after(Duration(milliseconds: timeout), () {
      if (!identical(activeConnection, conn) || isAuthorized) return;
      if (quiet) {
        _closeActiveConnection();
        _refuseWarn('stranger_auth_timeout', 'Someone else tried to pair and did not finish. We disconnected them.');
        return;
      }
      _emitFatal(
        'auth_timeout',
        'Authentication timed out after ${(timeout / 1000).round()} seconds. Your partner never completed the secure handshake.',
        'auth_failed',
      );
    });
  }

  void _refuseWarn(String code, String text) {
    final now = _clock.now();
    if (now - _admissionWarnedAt < admissionWarnIntervalMs) return;
    _admissionWarnedAt = now;
    _emitWarning(code, text);
  }

  void _clearAuthTimeout() {
    _authTimeoutTimer?.cancel();
    _authTimeoutTimer = null;
  }

  void _startConnectOpenTimeout(PeerLink conn, [bool isKnown = true]) {
    _clearConnectOpenTimeout();
    final timeout = isKnown ? connectOpenTimeoutMs : unknownConnectOpenTimeoutMs;
    final quiet = !isKnown && _knownPartnerId != null;
    _connectOpenTimer = _clock.after(Duration(milliseconds: timeout), () {
      if (!identical(activeConnection, conn) || conn.open) return;
      if (quiet) {
        _closeActiveConnection();
        _refuseWarn('stranger_open_timeout', 'Someone else was holding up pairing, so we disconnected them.');
        return;
      }
      _emitFatal('ice_failed', openTimeoutMessage, 'ice_failed');
    });
  }

  void _clearConnectOpenTimeout() {
    _connectOpenTimer?.cancel();
    _connectOpenTimer = null;
  }

  void _startHeartbeat() {
    _clearHeartbeat();
    lastPongAt = _clock.now();
    _heartbeatTimer = _clock.every(const Duration(milliseconds: heartbeatIntervalMs), () {
      heartbeatTick().catchError((_) {});
    });
  }

  Future<void> heartbeatTick() async {
    if (!isConnected || !isAuthorized || !(activeConnection?.open ?? false) || cryptoKey == null) {
      _clearHeartbeat();
      return;
    }

    if (_clock.now() - lastPongAt > heartbeatTimeoutMs) {
      _closeActiveConnection();
      _emitFatal('peer_unresponsive', 'Lost them - their phone stopped responding. Tap to reconnect.');
      return;
    }

    try {
      await _send({'type': 'PING', 't': _clock.now()});
    } catch (_) {
      _closeActiveConnection();
      _emitStatus({'state': 'disconnected', 'code': 'send_failed'});
    }
  }

  void _clearHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _resetAuthState() {
    _clearAuthTimeout();
    _clearConnectOpenTimeout();
    _clearHeartbeat();
    _clearRouteProbe();
    _abortAllSessions('disconnected', silent: true);
    pendingChallengeNonce = null;
    isAuthorized = false;
    isSyncing = false;
    connectionType = null;
    decryptFailures = 0;
    lastPongAt = 0;
  }

  void _closeActiveConnection() {
    _resetAuthState();
    isConnected = false;
    dialingPeerId = null;
    _slotKnown = false;
    _slotSince = 0;
    _slotProgressed = false;
    final conn = activeConnection;
    if (conn != null) {
      try {
        conn.close();
      } catch (_) {}
      activeConnection = null;
    }
  }

  void closeConnection() {
    _closeActiveConnection();
    _emitStatus({'state': 'disconnected', 'code': 'closed_locally'});
  }

  Future<String?> checkConnectionType() async {
    final conn = activeConnection;
    if (!isConnected || conn == null) return null;

    final pc = conn.route;
    if (pc == null) return 'unknown';

    try {
      final stats = await pc.getStats();
      final byId = <Object?, Map<String, Object?>>{for (final report in stats) report['id']: report};
      var isRelayed = false;
      var hasPair = false;

      for (final report in stats) {
        final bytesSent = report['bytesSent'];
        if (report['type'] == 'candidate-pair' &&
            (report['selected'] == true ||
                report['nominated'] == true ||
                (report['state'] == 'succeeded' && bytesSent is num && bytesSent > 0))) {
          hasPair = true;
          final local = byId[report['localCandidateId']];
          final remote = byId[report['remoteCandidateId']];
          if (local?['candidateType'] == 'relay' || remote?['candidateType'] == 'relay') {
            isRelayed = true;
          }
        }
      }

      if (!hasPair) return 'unknown';
      return isRelayed ? 'relayed' : 'direct';
    } catch (_) {
      return 'unknown';
    }
  }

  void _startRouteProbe() {
    _clearRouteProbe();
    _routeProbeAttempts = 0;

    final pc = activeConnection?.route;
    if (pc != null) {
      void listener(String state) {
        if (state == 'failed') {
          _routeFailed = true;
          _emitFatal('ice_failed', iceFailureMessage, 'ice_failed');
        } else if (state == 'connected' || state == 'completed') {
          unawaited(_probeRoute());
        }
      }

      _iceListener = listener;
      pc.addIceListener(listener);
      _icePeerConnection = pc;
    }

    _routeProbeTimer = _clock.every(const Duration(milliseconds: routeProbeIntervalMs), () {
      unawaited(_probeRoute());
    });

    unawaited(_probeRoute());
  }

  Future<void> _probeRoute() async {
    if (!isConnected || !isAuthorized) {
      _clearRouteProbe();
      return;
    }

    _routeProbeAttempts++;
    final type = await checkConnectionType();
    final settled = type == 'direct' || type == 'relayed';
    final giveUp = _routeProbeAttempts >= routeProbeMaxAttempts;

    if (settled || giveUp) {
      final resolved = settled ? type! : 'unknown';
      if (resolved != connectionType) {
        connectionType = resolved;
        _emitStatus({
          'state': _currentState(),
          'code': 'route_update',
          'partnerId': activeConnection?.peer,
          'connectionType': resolved,
          'isDirect': resolved == 'direct',
        });
      }
      _clearRouteProbe();
    }
  }

  void _clearRouteProbe() {
    _routeProbeTimer?.cancel();
    _routeProbeTimer = null;
    final pc = _icePeerConnection;
    final listener = _iceListener;
    if (pc != null && listener != null) {
      try {
        pc.removeIceListener(listener);
      } catch (_) {}
    }
    _iceListener = null;
    _icePeerConnection = null;
  }

  Future<void> _send(Map<String, Object?> message) {
    final conn = activeConnection;
    if (conn == null || !conn.open) {
      return Future<void>.error(PeerSyncFailure('No open connection to your partner'));
    }
    final key = cryptoKey;
    if (key == null) return Future<void>.error(PeerSyncFailure('Vault is locked'));

    final run = _sendTail.then((_) async {
      final payload = await _seal(message, key);
      if (payload.ciphertext.length > maxCiphertextLength) {
        throw PeerSyncFailure('Message is too large to send');
      }
      conn.send({'protocol': peerProtocolId, 'payload': payload.toJson()});
    });
    _sendTail = run.then((_) {}, onError: (Object _) {});
    return run;
  }

  Future<SealedText> _seal(Map<String, Object?> message, VaultKey key) async {
    final json = jsonStringify(message);
    if (json.length < offloadCryptoChars) return encryptText(json, key);
    return Isolate.run(() => encryptText(json, key));
  }

  Future<Object?> _open(String ciphertext, String iv, VaultKey key) async {
    if (ciphertext.length < offloadCryptoChars) return decryptJson(ciphertext, iv, key);
    return Isolate.run(() => decryptJson(ciphertext, iv, key));
  }

  Future<void> _sendAuthChallenge() async {
    if (activeConnection == null || cryptoKey == null) return;
    final nonce = _nonce(16);
    pendingChallengeNonce = nonce;
    await _send({'type': 'CHALLENGE', 'nonce': nonce});
  }

  Future<void> _handleMessage(Object? msg) async {
    if (msg is! Map) return;
    final payload = msg['payload'];
    if (payload == null || payload is! Map && payload is! List) return;

    if (msg['protocol'] == legacyPeerProtocolId) {
      _closeActiveConnection();
      _emitFatal('version_mismatch', 'Their Our Space is out of date. Update it on both phones so you can sync.');
      return;
    }
    if (msg['protocol'] != peerProtocolId) return;

    final ciphertext = payload is Map ? payload['ciphertext'] : null;
    final iv = payload is Map ? payload['iv'] : null;
    if (ciphertext is! String || iv is! String) return;
    if (ciphertext.length > maxCiphertextLength) {
      if (isAuthorized) {
        _emitWarning('oversized_message', 'Something was too big to send. We will try it again next time.');
      } else {
        _closeActiveConnection();
        _emitFatal('oversized_message', 'Something went wrong while pairing. Try again.');
      }
      return;
    }

    final key = cryptoKey;
    if (key == null) return;

    final started = Completer<Future<void>>();
    _inboundTail = _inboundTail.then((_) async {
      try {
        Object? decrypted;
        try {
          decrypted = await _open(ciphertext, iv, key);
        } catch (_) {
          _handleDecryptFailure();
          started.complete(Future<void>.value());
          return;
        }
        started.complete(_afterDecrypt(decrypted));
      } catch (error) {
        if (!started.isCompleted) started.complete(Future<void>.error(error));
      }
    });
    await (await started.future);
  }

  Future<void> _afterDecrypt(Object? decrypted) async {
    decryptFailures = 0;
    lastPongAt = _clock.now();
    _slotProgressed = true;

    if (decrypted is! Map || !allowedPeerMessageTypes.contains(decrypted['type'])) return;
    final message = asStringMap(decrypted)!;
    final type = message['type'] as String;

    final isAuthMsg = type == 'CHALLENGE' || type == 'CHALLENGE_RESPONSE' || type == 'CHALLENGE_ACK';
    if (!isAuthorized && !isAuthMsg) return;

    switch (type) {
      case 'CHALLENGE':
        await _onChallenge(message);
      case 'CHALLENGE_RESPONSE':
        await _onChallengeResponse(message);
      case 'CHALLENGE_ACK':
        await _onChallengeAck(message);
      case 'PING':
        try {
          await _send({'type': 'PONG', 't': _clock.now()});
        } catch (_) {}
      case 'PONG':
        break;
      case 'SYNC_CONFIG':
        _onSyncConfig(message['config']);
      case 'SYNC_MANIFEST':
        await _onSyncManifest(message);
      case 'SYNC_REQUEST_RECORDS':
        await _onSyncRequestRecords(message);
      case 'SYNC_RECORDS_BATCH':
        await _onSyncRecordsBatch(message);
      case 'SYNC_COMPLETE':
        _onSyncComplete(message);
      case 'SYNC_ERROR':
        _onSyncError(message);
      case 'LIVE_RECORD_BROADCAST':
        await _applySingleLiveRecord(message['record']);
      default:
        break;
    }
  }

  void _handleDecryptFailure() {
    if (!isAuthorized) {
      _closeActiveConnection();
      _emitFatal(
        'passphrase_mismatch',
        'Your passphrases do not match. Check you both typed exactly the same one.',
        'auth_failed',
      );
      return;
    }

    decryptFailures++;
    if (decryptFailures >= maxDecryptFailures) {
      _closeActiveConnection();
      _emitFatal(
        'corrupt_stream',
        'Too much came through that we could not read, so we closed the connection. Tap to reconnect.',
      );
      return;
    }

    _emitWarning('corrupt_frame', 'Something came through that we could not read, so we skipped it.');
  }

  Future<void> _onChallenge(Map<String, Object?> decrypted) async {
    final nonce = decrypted['nonce'];
    if (nonce is! String || nonce.length < 16) {
      _closeActiveConnection();
      _emitFatal('bad_challenge', 'Something went wrong while pairing. Try again.', 'auth_failed');
      return;
    }

    final counterNonce = _nonce(16);
    pendingChallengeNonce = counterNonce;

    await _send({'type': 'CHALLENGE_RESPONSE', 'echo': nonce, 'counterNonce': counterNonce});
  }

  Future<void> _onChallengeResponse(Map<String, Object?> decrypted) async {
    final echo = decrypted['echo'];
    final counterNonce = decrypted['counterNonce'];
    if (pendingChallengeNonce == null ||
        echo is! String ||
        echo != pendingChallengeNonce ||
        counterNonce is! String ||
        counterNonce.length < 16) {
      _closeActiveConnection();
      _emitFatal('challenge_replay', 'Pairing did not go through. Try again.', 'auth_failed');
      return;
    }

    pendingChallengeNonce = null;

    await _send({'type': 'CHALLENGE_ACK', 'echo': counterNonce});
    await _onAuthorized();
  }

  Future<void> _onChallengeAck(Map<String, Object?> decrypted) async {
    final echo = decrypted['echo'];
    if (pendingChallengeNonce == null || echo is! String || echo != pendingChallengeNonce) {
      _closeActiveConnection();
      _emitFatal('challenge_replay', 'Pairing did not go through. Try again.', 'auth_failed');
      return;
    }

    pendingChallengeNonce = null;
    await _onAuthorized();
  }

  Future<void> _onAuthorized() async {
    _clearAuthTimeout();
    _clearConnectOpenTimeout();
    isAuthorized = true;
    dialingPeerId = null;
    lastPongAt = _clock.now();

    connectionType = 'unknown';
    _startHeartbeat();

    _emitStatus({
      'state': 'authorized',
      'code': 'authorized',
      'partnerId': activeConnection?.peer,
      'connectionType': connectionType,
      'isDirect': false,
    });

    _startRouteProbe();
    await syncNow(wantReciprocal: false);
  }

  Map<String, _Session> _sessionMap(String kind) => kind == 'out' ? _outSessions : _inSessions;

  _Session _openSession(String kind, String sessionId, {String? phase, int requested = 0}) {
    final map = _sessionMap(kind);
    final session = _Session(sessionId, kind, _clock.now(), phase: phase, requested: requested);
    map[sessionId] = session;
    _touchSession(session);

    final wasIdle = !isSyncing;
    isSyncing = true;
    if (wasIdle) {
      _emitStatus({
        'state': 'syncing',
        'code': 'sync_started',
        'partnerId': activeConnection?.peer,
        'connectionType': connectionType,
        'isDirect': connectionType == 'direct',
      });
    }
    return session;
  }

  void _touchSession(_Session session) {
    if (!identical(_sessionMap(session.kind)[session.id], session)) return;
    session.timer?.cancel();
    session.timer = _clock.after(const Duration(milliseconds: syncSessionTimeoutMs), () {
      final map = _sessionMap(session.kind);
      if (!identical(map[session.id], session)) return;
      _closeSession(session.kind, session.id);
      _emitFatal('sync_timeout', 'That took too long, so we stopped. Nothing was lost - try again.');
    });
  }

  _Session? _closeSession(String kind, String sessionId) {
    final map = _sessionMap(kind);
    final session = map[sessionId];
    if (session == null) return null;
    session.timer?.cancel();
    map.remove(sessionId);
    if (_outSessions.isEmpty && _inSessions.isEmpty) {
      isSyncing = false;
    }
    return session;
  }

  void _abortAllSessions(String code, {bool silent = false}) {
    var had = false;
    for (final map in [_outSessions, _inSessions]) {
      for (final session in map.values) {
        session.timer?.cancel();
        had = true;
      }
      map.clear();
    }
    isSyncing = false;
    if (had && !silent) {
      _emitWarning(code, 'That was cancelled.');
    }
  }

  void _finishSession(String kind, String sessionId, String? message, [Map<String, Object?> extra = const {}]) {
    _closeSession(kind, sessionId);
    _emitStatus({
      'state': isSyncing ? 'syncing' : 'synced',
      'code': isSyncing ? 'sync_progress' : 'sync_complete',
      'message': message,
      'partnerId': activeConnection?.peer,
      'connectionType': connectionType,
      'isDirect': connectionType == 'direct',
      ...extra,
    });
  }

  Future<void> _sendSyncError(String sessionId, String code, String message, [Map<String, Object?> extra = const {}]) async {
    try {
      await _send({'type': 'SYNC_ERROR', 'sessionId': sessionId, 'code': code, 'message': message, ...extra});
    } catch (_) {}
  }

  Future<bool> syncNow({bool wantReciprocal = true}) async {
    if (!isConnected || !isAuthorized || !(activeConnection?.open ?? false)) return false;
    if (_outSessions.length >= maxConcurrentSessions) return false;

    final sessionId = _nonce(9);

    _openSession('out', sessionId, phase: 'advertised');

    try {
      final manifest = await records.getManifest();
      await _send({
        'type': 'SYNC_MANIFEST',
        'sessionId': sessionId,
        'manifest': manifest,
        'wantReciprocal': wantReciprocal,
      });
      return true;
    } catch (_) {
      _closeSession('out', sessionId);
      _emitWarning('sync_start_failed', 'Could not start syncing. Try again.');
      return false;
    }
  }

  Future<void> _onSyncManifest(Map<String, Object?> decrypted) async {
    final rawSession = decrypted['sessionId'];
    if (rawSession is! String || rawSession.length < 8 || rawSession.length > 64) {
      await _sendSyncError(rawSession is String ? rawSession : 'unknown', 'bad_session', 'Missing or malformed sessionId');
      return;
    }
    final sessionId = rawSession;
    if (_inSessions.containsKey(sessionId)) {
      await _sendSyncError(sessionId, 'duplicate_session', 'That sync session is already open');
      return;
    }
    if (_inSessions.length >= maxConcurrentSessions) {
      await _sendSyncError(sessionId, 'too_many_sessions', 'Too many sync sessions in flight');
      return;
    }

    final remoteManifest = decrypted['manifest'];
    if (remoteManifest is! Map) {
      await _sendSyncError(sessionId, 'manifest_rejected', 'Manifest was not an object');
      _emitWarning('manifest_rejected', 'Something came through that we could not read. Try again.');
      return;
    }

    List<Map<String, Object?>> requests;
    try {
      requests = await _diffManifest(asStringMap(remoteManifest)!);
    } catch (_) {
      await _sendSyncError(sessionId, 'manifest_rejected', 'Could not read the local manifest');
      _emitWarning('manifest_rejected', 'Could not compare notes with your partner. Try again.');
      return;
    }

    if (requests.isEmpty) {
      await _sendSyncComplete(sessionId, 0, 0);
    } else {
      _openSession('in', sessionId, phase: 'requested', requested: requests.length);
      try {
        await _send({'type': 'SYNC_REQUEST_RECORDS', 'sessionId': sessionId, 'requests': requests});
      } catch (_) {
        _closeSession('in', sessionId);
        _emitWarning('sync_request_failed', 'Could not ask your partner for updates. Try again.');
        return;
      }
    }

    if (decrypted['wantReciprocal'] == true && _outSessions.isEmpty) {
      await syncNow(wantReciprocal: false);
    }
  }

  Future<void> _sendSyncComplete(String sessionId, int applied, int rejected, [int unverifiable = 0]) async {
    try {
      await _send({
        'type': 'SYNC_COMPLETE',
        'sessionId': sessionId,
        'applied': applied,
        'rejected': rejected,
        'unverifiable': unverifiable,
      });
    } catch (_) {}
  }

  Future<List<Map<String, Object?>>> diffAgainstLocal(Object? remoteManifest) async {
    if (remoteManifest is! Map) return const [];
    return _diffManifest(asStringMap(remoteManifest)!);
  }

  Future<List<Map<String, Object?>>> _diffManifest(Map<String, Object?> remoteManifest) async {
    final localManifest = await records.getManifest();
    final requests = <Map<String, Object?>>[];
    final now = _clock.now();
    var sawFutureTimestamp = false;

    for (final entry in remoteManifest.entries) {
      final table = entry.key;
      final remoteItems = entry.value;
      if (!allowedPeerTables.contains(table) || remoteItems is! List) continue;
      if (remoteItems.length > maxRecordsPerTable) continue;

      final localMap = <String, (num, bool)>{};
      for (final item in localManifest[table] ?? const <Map<String, Object?>>[]) {
        final at = item['updatedAt'];
        localMap[item['id'] as String] = (at is num ? at : 0, item['deleted'] == true);
      }

      for (final raw in remoteItems) {
        if (raw is! Map) continue;
        final id = raw['id'];
        if (id is! String || id.length > 128) continue;

        final updatedAt = raw['updatedAt'];
        if (!_isFinite(updatedAt) || (updatedAt as num) < 0) continue;
        if (updatedAt > now + maxClockSkewMs) {
          sawFutureTimestamp = true;
          continue;
        }

        final local = localMap[id];
        final wantsRemote = local == null ||
            updatedAt > local.$1 ||
            (updatedAt == local.$1 && raw['deleted'] == true && !local.$2);

        if (wantsRemote) {
          requests.add({'table': table, 'id': id});
          if (requests.length >= maxPeerRequestsPerSession) break;
        }
      }
      if (requests.length >= maxPeerRequestsPerSession) break;
    }

    if (sawFutureTimestamp) _warnClockSkew();
    return requests;
  }

  void _warnClockSkew() {
    if (_clockSkewWarned) return;
    _clockSkewWarned = true;
    _emitWarning(
      'clock_skew',
      "Your partner's device clock looks far ahead of yours, so some of their items were not accepted. Check the date and time settings on both phones.",
    );
  }

  Future<void> _onSyncRequestRecords(Map<String, Object?> decrypted) async {
    final rawSession = decrypted['sessionId'];
    final session = rawSession is String ? _outSessions[rawSession] : null;
    if (session == null) {
      await _sendSyncError(
        rawSession is String ? rawSession : 'unknown',
        'unknown_session',
        'No such sync session',
        {'fatal': true},
      );
      return;
    }
    final sessionId = session.id;
    if (session.phase != 'advertised') {
      await _sendSyncError(sessionId, 'duplicate_request', 'Records were already sent for that session', {'fatal': true});
      return;
    }
    session.phase = 'sending';
    _touchSession(session);

    final rawRequests = decrypted['requests'];
    final requests = rawRequests is List ? rawRequests : const <Object?>[];
    if (requests.length > maxPeerRequestsPerSession) {
      await _sendSyncError(sessionId, 'too_many_requests', 'Request list exceeded the limit', {'fatal': true});
      _closeSession('out', sessionId);
      _emitWarning('too_many_requests', 'That was more than we can send at once. Try again.');
      return;
    }

    var batch = <Map<String, Object?>>[];
    var batchBytes = 0;
    var seq = 0;
    final oversized = <Map<String, Object?>>[];

    Future<void> flush(bool isFinal) async {
      final out = batch;
      batch = <Map<String, Object?>>[];
      batchBytes = 0;
      await _send({'type': 'SYNC_RECORDS_BATCH', 'sessionId': sessionId, 'seq': seq, 'records': out, 'final': isFinal});
      seq++;
      _touchSession(session);
    }

    try {
      for (final req in requests) {
        if (req is! Map) continue;
        final table = req['table'];
        final id = req['id'];
        if (table is! String || !allowedPeerTables.contains(table) || id is! String || id.length > 128) {
          continue;
        }

        final row = await records.getRow(table, id);
        if (row == null) continue;

        final wire = toWireRecord(table, row);
        final bytes = estimateWireBytes(wire);

        if (bytes > maxSingleRecordBytes) {
          oversized.add({'table': table, 'id': id});
          continue;
        }

        if (batch.isNotEmpty && batchBytes + bytes > maxBatchPayloadBytes) {
          await flush(false);
        }

        batch.add({'table': table, 'data': wire});
        batchBytes += bytes;
      }

      if (oversized.isNotEmpty) {
        await _sendSyncError(
          sessionId,
          'record_too_large',
          '${oversized.length} item(s) are too large to transfer',
          {'items': oversized.take(50).toList()},
        );
        _emitWarning(
          'record_too_large',
          '${oversized.length} item(s) are too large to send to your partner and were skipped. Re-add the photo at a smaller size to sync it.',
        );
      }

      await flush(true);
    } catch (_) {
      _closeSession('out', sessionId);
      await _sendSyncError(sessionId, 'send_failed', 'Could not send records', {'fatal': true});
      _emitWarning('send_failed', 'Could not send your memories right now. We will try again next time.');
    }
  }

  Future<void> _onSyncRecordsBatch(Map<String, Object?> decrypted) async {
    final rawSession = decrypted['sessionId'];
    final session = rawSession is String ? _inSessions[rawSession] : null;
    if (session == null) {
      await _sendSyncError(
        rawSession is String ? rawSession : 'unknown',
        'unknown_session',
        'No such sync session',
        {'fatal': true},
      );
      return;
    }
    final sessionId = session.id;

    final seq = decrypted['seq'];
    if (!(seq is num && seq == session.expectedSeq)) {
      _closeSession('in', sessionId);
      await _sendSyncError(sessionId, 'out_of_order', 'Batch arrived out of order', {'fatal': true});
      _emitWarning('out_of_order', 'Things arrived out of order, so we stopped. Try again.');
      return;
    }
    session.expectedSeq++;
    _touchSession(session);

    final result = await _applyRemoteRecords(decrypted['records']);
    session.applied += result.applied;
    session.rejected += result.rejected;
    session.unverifiable += result.unverifiable;

    if (decrypted['final'] == true) {
      final applied = session.applied;
      final rejected = session.rejected;
      final unverifiable = session.unverifiable;
      _closeSession('in', sessionId);

      await _sendSyncComplete(sessionId, applied, rejected, unverifiable);

      final String? message = applied > 0
          ? 'Synced $applied update${applied == 1 ? '' : 's'} from your partner!'
          : unverifiable > 0
              ? null
              : 'All memories up to date!';

      _emitStatus({
        'state': isSyncing ? 'syncing' : 'synced',
        'code': isSyncing ? 'sync_progress' : 'sync_complete',
        'message': message,
        'applied': applied,
        'rejected': rejected,
        'unverifiable': unverifiable,
        'partnerId': activeConnection?.peer,
        'connectionType': connectionType,
        'isDirect': connectionType == 'direct',
      });

      if (applied > 0) {
        _emitData(PeerDataUpdate(count: applied));
      }
      if (rejected > 0) {
        _emitWarning('records_rejected', '$rejected item(s) from your partner could not be read and were skipped.');
      }
      if (unverifiable > 0) {
        _emitWarning('records_unverifiable', unverifiableWarningText(unverifiable), {'unverifiable': unverifiable});
      }
    }
  }

  void _onSyncComplete(Map<String, Object?> decrypted) {
    final sessionId = decrypted['sessionId'];
    if (sessionId is! String || !_outSessions.containsKey(sessionId)) return;

    final rawApplied = decrypted['applied'];
    final num applied = _isFinite(rawApplied) ? rawApplied as num : 0;
    final rawUnverifiable = decrypted['unverifiable'];
    final num unverifiable = _isFinite(rawUnverifiable) && (rawUnverifiable as num) > 0
        ? math.min(rawUnverifiable, maxPeerRequestsPerSession)
        : 0;

    final String? message = applied > 0
        ? 'Sent ${_formatCount(applied)} update${applied == 1 ? '' : 's'} to your partner!'
        : unverifiable > 0
            ? null
            : 'Your partner is up to date!';

    _finishSession('out', sessionId, message, {'sent': applied, 'unverifiable': unverifiable});

    if (unverifiable > 0) {
      final count = _formatCount(unverifiable);
      _emitWarning(
        'records_unverifiable_remote',
        "Your partner's phone could not verify $count of your change${unverifiable == 1 ? '' : 's'} and did not apply ${unverifiable == 1 ? 'it' : 'them'}. Make sure both phones are on the same version of Our Space, then unlock this vault again and sync.",
        {'unverifiable': unverifiable},
      );
    }
  }

  void _onSyncError(Map<String, Object?> decrypted) {
    final rawSession = decrypted['sessionId'];
    final sessionId = rawSession is String ? rawSession : null;
    final rawCode = decrypted['code'];
    final code = rawCode is String ? jsSlice(rawCode, 0, 64) : 'sync_error';
    final rawDetail = decrypted['message'];
    final detail = rawDetail is String ? jsSlice(rawDetail, 0, 200) : '';

    if (sessionId != null && decrypted['fatal'] == true) {
      _closeSession('out', sessionId);
      _closeSession('in', sessionId);
    }

    final human = code == 'record_too_large'
        ? "Some items on your partner's device are too large to transfer and were skipped."
        : 'Your partner reported a sync problem${detail.isNotEmpty ? ': $detail' : '.'}';

    _emitWarning(code, human);
  }

  Map<String, Object?> toWireRecord(String table, Map<String, Object?> row) {
    final allowed = wireFieldsFor(table);
    final wire = <String, Object?>{};

    row.forEach((field, value) {
      if (value == null) return;
      if (!allowed.contains(field)) return;
      wire[field] = value;
    });

    wire['id'] = row['id'];
    final updatedAt = row['updatedAt'];
    wire['updatedAt'] = _isFinite(updatedAt) ? updatedAt : 0;
    wire['deleted'] = row['deleted'] == true;

    final blob = row['imageBlob'];
    if (table == memoriesTable && blob != null && isBinaryValue(blob)) {
      wire['imageBlobBase64'] = bufferToBase64(binaryBytes(blob));
    }

    return wire;
  }

  int estimateWireBytes(Map<String, Object?> wire) {
    var bytes = 128;
    wire.forEach((field, value) {
      bytes += field.length + 8;
      if (value is String) {
        bytes += value.length;
      } else {
        bytes += 16;
      }
    });
    return bytes;
  }

  _Check _validateWireRecord(Object? data) {
    if (data is! Map) return const _Check(false, 'shape');
    final id = data['id'];
    if (id is! String || id.isEmpty || id.length > 128) return const _Check(false, 'bad_id');
    final updatedAt = data['updatedAt'];
    if (!_isFinite(updatedAt) || (updatedAt as num) < 0) return const _Check(false, 'bad_timestamp');
    if (updatedAt > _clock.now() + maxClockSkewMs) return const _Check(false, 'future_timestamp');
    if (data['deleted'] is! bool) return const _Check(false, 'bad_tombstone');
    if (data['v'] != recordSchemaVersion) return const _Check(false, 'bad_version');
    return const _Check(true);
  }

  Map<String, Object?>? _sanitizeIncomingRow(String table, Map<Object?, Object?> data) {
    final allowed = wireFieldsFor(table);
    final row = <String, Object?>{};

    data.forEach((field, value) {
      if (field is! String) return;
      if (!allowed.contains(field)) return;
      row[field] = value;
    });

    row['id'] = data['id'];
    row['updatedAt'] = data['updatedAt'];
    row['deleted'] = data['deleted'] == true;
    row['_del'] = row['deleted'] == true ? 1 : 0;

    final blob = data['imageBlobBase64'];
    if (table == memoriesTable && blob is String) {
      try {
        final bytes = base64ToBuffer(blob);
        if (bytes.length > maxImageBlobBytes) return null;
        row['imageBlob'] = bytes;
      } catch (_) {
        return null;
      }
    }

    return row;
  }

  _Check _verifyRecordIntegrity(Map<String, Object?> row, String table) {
    final key = cryptoKey;
    if (key == null) return const _Check(false, 'locked');
    if (!recordHasAuthenticatedHeader(row)) return const _Check(false, 'unauthenticated');
    try {
      final plain = decryptRecord(row, key, table: table);
      if (plain['_binaryTampered'] == true) return const _Check(false, 'binary_tampered');
      if (plain['_tableTampered'] == true) return const _Check(false, 'table_mismatch');
      if (plain['_headerTampered'] == true) return const _Check(false, 'header_tampered');
      if (plain['_binaryUnverified'] == true || plain['_tableUnverified'] == true) {
        return const _Check(true, null, true);
      }
      return const _Check(true);
    } catch (_) {
      return const _Check(false, 'undecryptable');
    }
  }

  _Staged _stageIncomingRecords(List<Object?> items) {
    final staged = <IncomingRow>[];
    final reasons = <String, int>{};
    var rejected = 0;

    void note(String code) {
      rejected++;
      reasons[code] = (reasons[code] ?? 0) + 1;
    }

    for (final item in items) {
      final table = item is Map ? item['table'] : null;
      if (item is! Map || table is! String || !allowedPeerTables.contains(table)) {
        note('table');
        continue;
      }

      final data = item['data'];
      final check = _validateWireRecord(data);
      if (!check.ok) {
        note(check.code!);
        continue;
      }

      final row = _sanitizeIncomingRow(table, data as Map);
      if (row == null) {
        note('blob_rejected');
        continue;
      }

      final integrity = _verifyRecordIntegrity(row, table);
      if (!integrity.ok) {
        note(integrity.code!);
        continue;
      }

      staged.add(IncomingRow(table, row, unverifiedBinding: integrity.unverified));
    }

    if (reasons.containsKey('future_timestamp')) _warnClockSkew();
    return _Staged(staged, rejected, reasons);
  }

  bool incomingRowWins(Map<String, Object?>? existing, Map<String, Object?> incoming) =>
      incomingWins(existing, incoming);

  String fingerprint(Map<String, Object?> row) => rowFingerprint(row);

  Future<_Applied> _commitStagedRecords(List<IncomingRow> staged) async {
    if (staged.isEmpty) return const _Applied(0, 0, 0, 0);

    final result = await records.commit(staged);

    for (final entry in staged) {
      final at = entry.row['updatedAt'];
      if (at is num && at > _observedRemoteMax) {
        _observedRemoteMax = at;
        _observeRemote?.call(at);
      }
    }

    return _Applied(result.applied, 0, result.stale, result.unverifiable);
  }

  Future<_Applied> _applyRemoteRecords(Object? recordsValue) async {
    if (!isAuthorized || recordsValue is! List) return const _Applied(0, 0, 0, 0);

    final staged = _stageIncomingRecords(recordsValue);
    final committed = await _commitStagedRecords(staged.staged);
    return _Applied(committed.applied, staged.rejected, committed.stale, committed.unverifiable);
  }

  Future<bool> broadcastLiveRecord(String table, Map<String, Object?>? record) async {
    final id = record?['id'];
    if (record == null || id is! String) return false;
    if (!allowedPeerTables.contains(table)) return false;

    for (final listener in [..._localRecordListeners]) {
      try {
        listener(table, id);
      } catch (_) {}
    }

    if (!isConnected || !isAuthorized) return false;

    try {
      final wire = toWireRecord(table, record);
      final bytes = estimateWireBytes(wire);

      if (bytes > maxSingleRecordBytes) {
        _emitWarning('record_too_large', 'That one is too big to send. Try adding the photo again a bit smaller.');
        return false;
      }

      await _send({
        'type': 'LIVE_RECORD_BROADCAST',
        'record': {'table': table, 'data': wire},
      });
      return true;
    } catch (_) {
      _emitWarning('broadcast_failed', 'Could not send that just now. It will go through next time you connect.');
      return false;
    }
  }

  Future<void> _applySingleLiveRecord(Object? record) async {
    if (!isAuthorized || record is! Map) return;

    final staged = _stageIncomingRecords([record]);
    if (staged.staged.isEmpty) {
      if (staged.rejected > 0) {
        final code = staged.reasons.keys.isNotEmpty ? staged.reasons.keys.first : 'record_rejected';
        _emitWarning(code, 'One update could not be read, so we skipped it.');
      }
      return;
    }

    final committed = await _commitStagedRecords(staged.staged);
    if (committed.applied > 0) {
      final table = record['table'];
      _emitData(PeerDataUpdate(count: committed.applied, single: true, table: table is String ? table : null));
    }
    if (committed.unverifiable > 0) {
      _emitWarning(
        'records_unverifiable',
        unverifiableWarningText(committed.unverifiable),
        {'unverifiable': committed.unverifiable},
      );
    }
  }

  Future<bool> syncVaultConfig(Map<String, Object?>? config) async {
    if (!isConnected || !isAuthorized || cryptoKey == null) return false;
    try {
      final rawNames = config?['coupleNames'];
      final names = rawNames is String && rawNames.isNotEmpty ? rawNames : '';
      final rawStart = config?['startDate'];
      final start = rawStart is String ? rawStart : '';
      final rawUpdated = config?['updatedAt'];
      await _send({
        'type': 'SYNC_CONFIG',
        'config': {
          'coupleNames': jsSlice(names, 0, maxPeerCoupleNamesLength),
          'startDate': isoDateRegex.hasMatch(start) ? start : '',
          'updatedAt': _isFinite(rawUpdated) ? rawUpdated : _clock.now(),
        },
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  void _onSyncConfig(Object? config) {
    if (config is! Map) {
      _emitWarning('bad_config', 'We could not read their details. Try again.');
      return;
    }

    final rawNames = config['coupleNames'];
    final coupleNames = rawNames is String ? jsSlice(rawNames, 0, maxPeerCoupleNamesLength) : '';
    final rawStart = config['startDate'];
    final startDate = rawStart is String && isoDateRegex.hasMatch(rawStart) ? rawStart : '';

    num updatedAt = 0;
    final rawUpdated = config['updatedAt'];
    if (_isFinite(rawUpdated) && (rawUpdated as num) >= 0 && rawUpdated <= _clock.now() + maxClockSkewMs) {
      updatedAt = rawUpdated;
    }

    if (coupleNames.isEmpty && startDate.isEmpty) {
      _emitWarning('bad_config', 'Nothing to update from their side.');
      return;
    }

    _emitConfig(PeerConfigUpdate(coupleNames: coupleNames, startDate: startDate, updatedAt: updatedAt));
  }

  void onForeground() {
    final current = peer;
    if (current != null && !current.destroyed && current.disconnected) {
      try {
        current.reconnect();
      } catch (_) {}
    }
    if (isAuthorized) {
      heartbeatTick().catchError((_) {});
    }
  }

  void disconnect() => closeConnection();

  void releaseTransport() {
    _unavailableRetryTimer?.cancel();
    _unavailableRetryTimer = null;
    _signalReconnectTimer?.cancel();
    _signalReconnectTimer = null;
    _signalDrops = 0;
    _closeActiveConnection();
    final current = peer;
    peer = null;
    try {
      current?.destroy();
    } catch (_) {}
    myPeerId = null;
    _initCompleter = null;
  }

  void destroy() {
    releaseTransport();
    cryptoKey = null;
    _observedRemoteMax = 0;
    _clockSkewWarned = false;
    _emitStatus({'state': 'disconnected', 'code': 'destroyed'});
  }
}
