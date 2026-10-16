import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../models/vault_config.dart';
import '../crypto/js_compat.dart';
import '../identity/identity_controller.dart';
import '../invite/invite.dart';
import '../storage/tables.dart';
import '../storage/vault_store.dart';
import '../vault/vault_service.dart';
import 'peer_clock.dart';
import 'peer_status.dart';
import 'peer_sync_engine.dart';

const String trustedPartnerKey = 'sweetheart_trusted_partner_id';
const String pairedPartnerKey = 'sweetheart_paired_partner_id';
const String lastConnectedKey = 'sweetheart_last_connected_at';

const int trustedDialDelayMs = 800;
const int resumeCooldownMs = 5000;
const int lastConnectedTickMs = 30000;

const String partnerSyncProblemPrefix = 'Your partner reported a sync problem: ';

class PeerNotice {
  const PeerNotice(this.text, {this.warning = false});

  final String text;
  final bool warning;
}

class PeerSyncHub extends ChangeNotifier {
  PeerSyncHub({
    required this.engine,
    required this.vault,
    required this.identity,
    required this.store,
    this.autoStart = true,
    this._clock = const SystemPeerClock(),
  }) {
    _partnerId = _read(pairedPartnerKey);
    final storedConnected = num.tryParse(_read(lastConnectedKey) ?? '');
    _lastConnectedAt = storedConnected?.toInt();
    engine.addStatusListener(_handleStatus);
    engine.addDataListener(_handleDataUpdated);
    engine.addConfigListener(_handleConfigSynced);
    vault.addListener(_onVault);
    _rowsSub = store.localRows.listen(_onLocalRow);
    _lastKey = vault.key;
    if (_lastKey != null && autoStart) start();
  }

  final PeerSyncEngine engine;
  final VaultService vault;
  final IdentityController identity;
  final VaultStore store;
  final bool autoStart;
  final PeerClock _clock;

  late final StreamSubscription<SealedWrite> _rowsSub;
  final StreamController<PeerNotice> _notices = StreamController<PeerNotice>.broadcast();
  final StreamController<PeerLinkState> _linkStates = StreamController<PeerLinkState>.broadcast();
  final StreamController<PeerStatus> _statuses = StreamController<PeerStatus>.broadcast();

  Object? _lastKey;
  bool _active = false;
  bool _ready = false;
  bool _disposed = false;
  String? _myPeerId;
  String? _partnerId;
  PeerStatus _status = PeerStatus.initial;
  PeerSyncError? _syncError;
  String? _connectionType;
  PendingPeerInvite? _pendingInvite;
  int? _lastConnectedAt;
  String? _pendingConnect;
  Timer? _dialTimer;
  Timer? _connectedTicker;
  int _resumeGuard = 0;
  PeerLinkState _lastLinkState = PeerLinkState.disconnected;
  int _lastSentConfigAt = -1;

  String? get myPeerId => _myPeerId;
  String? get partnerId => _partnerId;
  PeerStatus get status => _status;
  PeerSyncError? get syncError => _syncError;
  String? get connectionType => _connectionType;
  PendingPeerInvite? get pendingInvite => _pendingInvite;
  int? get lastConnectedAt => _lastConnectedAt;
  bool get started => _active;

  PeerLinkState get linkState => engine.linkState;
  bool get isAuthorized => engine.isConnected && engine.isAuthorized;
  bool get isHandshaking => linkState == PeerLinkState.connected;
  bool get isConnecting => linkState == PeerLinkState.connecting;
  bool get isDirectP2P => _connectionType == 'direct';
  bool get isRelayed => _connectionType == 'relayed';
  bool get isRouteUnknown => isAuthorized && _connectionType != 'direct' && _connectionType != 'relayed';

  Stream<PeerNotice> get notices => _notices.stream;
  Stream<PeerLinkState> get linkStates => _linkStates.stream;
  Stream<PeerStatus> get statuses => _statuses.stream;

  String? _read(String key) {
    final value = store.settings.getItem(key);
    if (value == null) return null;
    final trimmed = jsTrim(value);
    return trimmed.isEmpty ? null : trimmed;
  }

  void _write(String key, String value) => unawaited(store.settings.setItem(key, value));

  void _remove(String key) => unawaited(store.settings.removeItem(key));

  @override
  void notifyListeners() {
    if (_disposed) return;
    final state = linkState;
    if (state != _lastLinkState) {
      _lastLinkState = state;
      if (!_linkStates.isClosed) _linkStates.add(state);
    }
    super.notifyListeners();
  }

  void Function(PeerNotice notice)? onNotice;

  void _notice(String text, {bool warning = false}) {
    if (_notices.isClosed || text.isEmpty) return;
    final notice = PeerNotice(text, warning: warning);
    onNotice?.call(notice);
    _notices.add(notice);
  }

  void _onVault() {
    final key = vault.key;
    if (identical(key, _lastKey)) {
      _maybeSendConfig();
      return;
    }
    _lastKey = key;
    if (key == null) {
      stop();
      return;
    }
    if (autoStart) start();
  }

  void rememberInvitedPartner(String peerId) {
    final clean = jsTrim(peerId);
    if (clean.isEmpty) return;
    _write(pairedPartnerKey, clean);
    final id = _myPeerId;
    if (_active && _ready && id != null) {
      _pendingConnect = null;
      _offer(clean, id, fromLink: true);
      return;
    }
    _pendingConnect = clean;
  }

  void acceptInvite(Invite invite) => rememberInvitedPartner(invite.partnerPeerId);

  void start() {
    final key = vault.key;
    if (key == null || _disposed) return;
    if (_active) return;
    _active = true;
    _lastSentConfigAt = vault.config?.updatedAt ?? -1;

    engine.init(key).then((id) {
      if (!_active || !identical(vault.key, key)) return;
      _ready = true;
      _myPeerId = id;
      notifyListeners();

      final invited = _pendingConnect;
      _pendingConnect = null;
      final target = invited ?? _read(pairedPartnerKey);
      if (target == null) return;
      _offer(target, id, fromLink: invited != null);
    }, onError: (Object _) {});

    _maybeResume();
  }

  void _offer(String target, String id, {required bool fromLink}) {
    if (target == id) return;

    _partnerId = target;

    if (target == _read(trustedPartnerKey)) {
      _dialTimer?.cancel();
      _dialTimer = _clock.after(const Duration(milliseconds: trustedDialDelayMs), () {
        _dialTimer = null;
        if (!_active) return;
        _dialQuietly(target);
      });
      notifyListeners();
      return;
    }

    _pendingInvite = PendingPeerInvite(peerId: target, fromLink: fromLink);
    notifyListeners();
  }

  void stop() {
    _active = false;
    _ready = false;
    _dialTimer?.cancel();
    _dialTimer = null;
    _stopConnectedTicker();
    engine.destroy();
    _myPeerId = null;
    _status = PeerStatus.initial;
    _connectionType = null;
    _pendingInvite = null;
    _syncError = null;
    if (!_disposed) notifyListeners();
  }

  bool _alreadyReaching(String target) =>
      engine.dialingPeerId == target || (engine.activeConnection?.peer == target && engine.linkState != PeerLinkState.disconnected);

  void _dialQuietly(String target) {
    if (_alreadyReaching(target)) return;
    engine.connectToPartner(target).catchError((Object _) {});
  }

  void _handleStatus(PeerStatus status) {
    if (_disposed || !_active) return;
    _status = status;
    if (!_statuses.isClosed) _statuses.add(status);

    final peerId = status.peerId;
    if (peerId != null) _myPeerId = peerId;

    final partner = status.partnerId;
    final authorized = authorizedPeerStates.contains(status.state);
    if (partner != null && authorized) {
      _partnerId = partner;
      _write(pairedPartnerKey, partner);
    }

    if (status.state == 'connecting') _syncError = null;

    if (authorized) {
      final now = _clock.now();
      _lastConnectedAt = now;
      _write(lastConnectedKey, '$now');
      _syncError = null;
      _startConnectedTicker();
      if (status.state == 'authorized') {
        final config = vault.config;
        if (config != null) {
          _lastSentConfigAt = config.updatedAt;
          unawaited(engine.syncVaultConfig(config.toJson()));
        }
      }
    }

    final error = status.error;
    if (error != null) {
      _syncError = PeerSyncError(code: status.code ?? status.state, state: status.state, text: error);
    }

    final warning = status.warning;
    if (warning != null) _notice(_userFacing(warning), warning: true);
    final message = status.message;
    if (message != null) _notice(message);

    if (status.hasConnectionType) _connectionType = status.connectionType;
    if (routeClearingPeerStates.contains(status.state)) _connectionType = null;

    notifyListeners();
  }

  String _userFacing(String warning) {
    if (warning.startsWith(partnerSyncProblemPrefix)) return 'Your partner reported a sync problem.';
    return warning;
  }

  void _handleDataUpdated(PeerDataUpdate update) {
    if (!_active || _disposed) return;
    final count = update.count == 0 ? 1 : update.count;
    _notice('Synced $count new item(s) from ${identity.partnerName} 💕');
  }

  Future<void> _handleConfigSynced(PeerConfigUpdate remote) async {
    if (!_active || _disposed || vault.key == null) return;

    if (!isValidStartDate(remote.startDate)) {
      _notice('We skipped a settings change from your partner — the date did not look right.', warning: true);
      return;
    }

    final remoteUpdatedAt = remote.updatedAt.isFinite ? remote.updatedAt : 0;
    if (remoteUpdatedAt > _clock.now() + maxClockSkewMs) {
      _notice(
        'We skipped a settings change from your partner — their phone’s date is set far in the '
        'future. Fix it on that phone and try again.',
        warning: true,
      );
      return;
    }

    final current = vault.config;
    final localUpdatedAt = current?.updatedAt ?? 0;
    if (remoteUpdatedAt <= localUpdatedAt) return;

    final merged = VaultConfig(
      coupleNames: sanitizeCoupleNames(remote.coupleNames, current?.coupleNames ?? 'Us'),
      startDate: remote.startDate,
      updatedAt: remoteUpdatedAt.floor(),
    );
    try {
      _lastSentConfigAt = merged.updatedAt;
      await vault.adoptPartnerConfig(merged);
    } catch (_) {
      _notice('We could not save the settings your partner just sent. Yours are unchanged.', warning: true);
    }
  }

  void _maybeSendConfig() {
    if (!_active) return;
    final config = vault.config;
    if (config == null || config.updatedAt == _lastSentConfigAt) return;
    _lastSentConfigAt = config.updatedAt;
    if (isAuthorized) unawaited(engine.syncVaultConfig(config.toJson()));
  }

  void _onLocalRow(SealedWrite write) {
    if (!_active || _disposed) return;
    if (!syncedTables.contains(write.table)) return;
    unawaited(engine.broadcastLiveRecord(write.table, write.row));
  }

  void _startConnectedTicker() {
    if (_connectedTicker != null) return;
    _connectedTicker = _clock.every(const Duration(milliseconds: lastConnectedTickMs), () {
      if (!isAuthorized) {
        _stopConnectedTicker();
        return;
      }
      final now = _clock.now();
      _lastConnectedAt = now;
      _write(lastConnectedKey, '$now');
      notifyListeners();
    });
  }

  void _stopConnectedTicker() {
    _connectedTicker?.cancel();
    _connectedTicker = null;
  }

  void connectToPartner(String id) => _trustAndConnect(id);

  void _trustAndConnect(String id) {
    final clean = jsTrim(id);
    if (clean.isEmpty) return;
    if (!peerIdRegex.hasMatch(clean) || clean == _myPeerId) {
      _syncError = PeerSyncError(
        code: 'bad_peer_id',
        state: 'error',
        text: '“$clean” is not a usable pairing code. Ask your partner to re-share their code or invite link.',
      );
      notifyListeners();
      return;
    }
    _write(trustedPartnerKey, clean);
    _write(pairedPartnerKey, clean);
    _partnerId = clean;
    _syncError = null;
    notifyListeners();
    engine.connectToPartner(clean).catchError((Object _) {
      _syncError = PeerSyncError(
        code: 'dial_failed',
        state: 'error',
        text: 'We could not reach $clean. Check they have Our Space open, then try again.',
      );
      notifyListeners();
    });
  }

  void confirmPendingInvite() {
    final pending = _pendingInvite;
    if (pending == null) return;
    _pendingInvite = null;
    _trustAndConnect(pending.peerId);
  }

  void declinePendingInvite() {
    final declined = _pendingInvite?.peerId;
    _pendingInvite = null;
    if (declined == null) {
      notifyListeners();
      return;
    }
    if (_read(pairedPartnerKey) == declined) _remove(pairedPartnerKey);
    if (_read(trustedPartnerKey) == declined) _remove(trustedPartnerKey);
    if (_partnerId == declined) _partnerId = null;
    notifyListeners();
  }

  void reconnectToPartner() {
    final target = _read(trustedPartnerKey) ?? _partnerId ?? _read(pairedPartnerKey);
    if (target == null || target == _myPeerId) return;
    _trustAndConnect(target);
  }

  void unpairPartner() {
    _remove(pairedPartnerKey);
    _remove(trustedPartnerKey);
    _pendingConnect = null;
    _partnerId = null;
    _pendingInvite = null;
    _syncError = null;
    _connectionType = null;
    notifyListeners();
    engine.disconnect();
  }

  Future<bool> syncNow() async {
    final started = await engine.syncNow();
    if (!started) {
      _notice('Could not start a sync right now. Check the connection and try again.', warning: true);
    }
    return started;
  }

  void disconnect() => engine.disconnect();

  void clearSyncError() {
    _syncError = null;
    notifyListeners();
  }

  void onForeground() {
    if (!_active) return;
    engine.onForeground();
    _maybeResume();
  }

  void onBackground() {}

  void _maybeResume() {
    if (!_active) return;
    if (_pendingInvite != null) return;
    if (authorizedPeerStates.contains(_status.state) || isAuthorized) return;

    final target = _read(trustedPartnerKey);
    if (target == null || target == _myPeerId) return;

    final now = _clock.now();
    if (now - _resumeGuard < resumeCooldownMs) return;
    _resumeGuard = now;

    _dialQuietly(target);
  }

  @override
  void dispose() {
    _disposed = true;
    _active = false;
    _ready = false;
    _dialTimer?.cancel();
    _stopConnectedTicker();
    vault.removeListener(_onVault);
    engine.removeStatusListener(_handleStatus);
    engine.removeDataListener(_handleDataUpdated);
    engine.removeConfigListener(_handleConfigSynced);
    unawaited(_rowsSub.cancel());
    engine.destroy();
    unawaited(_notices.close());
    unawaited(_linkStates.close());
    unawaited(_statuses.close());
    super.dispose();
  }
}
