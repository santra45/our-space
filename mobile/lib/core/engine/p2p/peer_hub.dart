import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../models/vault_config.dart';
import '../crypto/js_compat.dart';
import '../identity/identity_controller.dart';
import '../invite/invite.dart';
import '../storage/tables.dart';
import '../storage/vault_store.dart';
import '../vault/vault_service.dart';
import 'app_update_link.dart';
import 'peer_clock.dart';
import 'peer_status.dart';
import 'peer_sync_engine.dart';
import 'sky_together_link.dart';

const String trustedPartnerKey = 'sweetheart_trusted_partner_id';
const String pairedPartnerKey = 'sweetheart_paired_partner_id';
const String lastConnectedKey = 'sweetheart_last_connected_at';
const String partnerSetAsideKey = 'sweetheart_partner_set_aside';

const int trustedDialDelayMs = 800;
const int resumeCooldownMs = 5000;
const int lastConnectedTickMs = 30000;
const int partnerRetryTickMs = 30000;
const int partnerLookCooldownMs = 15000;

abstract class PartnerCodes {
  Future<bool> leave(String myCode);

  Future<List<String>> find();
}

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
    this.partnerCodes,
    AppUpdatePlatform? updatePlatform,
    this._clock = const SystemPeerClock(),
  }) {
    _partnerId = _read(pairedPartnerKey);
    final storedConnected = num.tryParse(_read(lastConnectedKey) ?? '');
    _lastConnectedAt = storedConnected?.toInt();
    engine.addStatusListener(_handleStatus);
    engine.addDataListener(_handleDataUpdated);
    engine.addConfigListener(_handleConfigSynced);
    vault.addListener(_onVault);
    identity.addListener(_leaveMyCode);
    _rowsSub = store.localRows.listen(_onLocalRow);
    skyTogether = SkyTogetherLink(
      transport: _HubSkyTransport(this),
      owner: () => identity.myOwnerId ?? identity.people.device.deviceId,
      clock: _clock,
    );
    appUpdate = AppUpdateLink(transport: _HubUpdateTransport(this), platform: updatePlatform, clock: _clock);
    _lastKey = vault.key;
    if (_lastKey != null && autoStart) start();
  }

  final PeerSyncEngine engine;
  final VaultService vault;
  final IdentityController identity;
  final VaultStore store;
  final bool autoStart;
  final PartnerCodes? partnerCodes;
  final PeerClock _clock;

  late final StreamSubscription<SealedWrite> _rowsSub;
  late final SkyTogetherLink skyTogether;
  late final AppUpdateLink appUpdate;
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
  bool _syncedOnce = false;
  Timer? _dialTimer;
  Timer? _connectedTicker;
  int _resumeGuard = 0;
  PeerLinkState _lastLinkState = PeerLinkState.disconnected;
  int _lastSentConfigAt = -1;
  Timer? _retryTicker;
  bool _foreground = true;
  String? _leftAs;
  bool _leaving = false;
  bool _looking = false;
  int? _lastLookAt;

  String? get myPeerId => _myPeerId;
  String? get partnerId => _partnerId;

  bool get waitingOnPartnerSync => (_partnerId != null || _pendingConnect != null) && (!_syncedOnce || engine.isSyncing);
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

  void _setAside(bool aside) {
    if ((_read(partnerSetAsideKey) != null) == aside) return;
    if (aside) {
      _write(partnerSetAsideKey, '1');
    } else {
      _remove(partnerSetAsideKey);
    }
  }

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
    if (clean != _myPeerId) _setAside(false);
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
      _leaveMyCode();

      final invited = _pendingConnect;
      _pendingConnect = null;
      final target = invited ?? _read(pairedPartnerKey);
      if (target != null) _offer(target, id, fromLink: invited != null);
      unawaited(lookForPartner());
    }, onError: (Object _) {});

    _retryTicker?.cancel();
    _retryTicker = _clock.every(const Duration(milliseconds: partnerRetryTickMs), _retryTick);

    _maybeResume();
  }

  void _leaveMyCode() {
    final codes = partnerCodes;
    final id = _myPeerId;
    final owner = identity.myOwnerId;
    if (codes == null || _disposed || !_active || !_ready || _leaving || id == null || owner == null) return;
    final mark = '$owner|$id';
    if (mark == _leftAs) return;
    _leaving = true;
    codes.leave(id).then((ok) {
      if (ok) _leftAs = mark;
    }, onError: (Object _) {}).whenComplete(() => _leaving = false);
  }

  Future<bool> lookForPartner() async {
    final codes = partnerCodes;
    if (codes == null || _disposed || !_active || !_ready || _looking) return false;
    if (_pendingInvite != null || isAuthorized || _read(partnerSetAsideKey) != null) return false;
    _looking = true;
    _lastLookAt = _clock.now();
    try {
      final found = await codes.find();
      if (_disposed || !_active || isAuthorized || _pendingInvite != null) return false;
      if (_read(partnerSetAsideKey) != null) return false;
      final mine = _myPeerId;
      for (final code in found) {
        if (code == mine || !peerIdRegex.hasMatch(code)) continue;
        _adoptPartnerCode(code);
        return true;
      }
      return false;
    } catch (_) {
      return false;
    } finally {
      _looking = false;
    }
  }

  void _adoptPartnerCode(String code) {
    if (_read(trustedPartnerKey) != code) _write(trustedPartnerKey, code);
    if (_read(pairedPartnerKey) != code) _write(pairedPartnerKey, code);
    if (engine.knownPartnerId != code) engine.noteAdmissionSuccess(code);
    _partnerId = code;
    notifyListeners();
    _dialQuietly(code);
  }

  void _retryTick() {
    if (_disposed || !_active || !_ready || !_foreground) return;
    _leaveMyCode();
    if (isAuthorized || _pendingInvite != null) return;
    unawaited(lookForPartner().then((adopted) {
      if (adopted || _disposed || !_active || isAuthorized || _pendingInvite != null) return;
      final target = _read(trustedPartnerKey);
      if (target != null && target != _myPeerId) _dialQuietly(target);
    }));
  }

  void _offer(String target, String id, {required bool fromLink}) {
    if (target == id) return;

    _partnerId = target;

    if (target == _read(trustedPartnerKey)) {
      _dialTimer?.cancel();
      _dialTimer = _clock.after(const Duration(milliseconds: trustedDialDelayMs), () {
        _dialTimer = null;
        if (!_active || _read(trustedPartnerKey) != target) return;
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
    _retryTicker?.cancel();
    _retryTicker = null;
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
    if (status.code == 'sync_complete') _syncedOnce = true;
    if (!_statuses.isClosed) _statuses.add(status);

    final peerId = status.peerId;
    if (peerId != null) _myPeerId = peerId;
    if (status.code == 'peer_ready') _leaveMyCode();

    final partner = status.partnerId;
    final authorized = authorizedPeerStates.contains(status.state);
    if (partner != null && authorized) {
      _partnerId = partner;
      _write(pairedPartnerKey, partner);
      if (_read(trustedPartnerKey) != partner) _write(trustedPartnerKey, partner);
      _setAside(false);
      if (engine.knownPartnerId != partner) engine.noteAdmissionSuccess(partner);
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
    if (update.single && appOnlyTables.contains(update.table)) return;
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
    if (appOnlyTables.contains(write.table) && !skyTogether.partnerSpeaksSky) return;
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
    _setAside(false);
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
    _setAside(true);
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
    _setAside(true);
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
    _foreground = true;
    skyTogether.setForeground(true);
    appUpdate.onForeground();
    if (!_active) return;
    engine.onForeground();
    _maybeResume();
  }

  void onBackground() {
    _foreground = false;
    skyTogether.setForeground(false);
  }

  void _maybeResume() {
    if (!_active) return;
    if (_pendingInvite != null) return;
    if (authorizedPeerStates.contains(_status.state) || isAuthorized) return;

    final lastLook = _lastLookAt;
    if (lastLook == null || _clock.now() - lastLook >= partnerLookCooldownMs) unawaited(lookForPartner());

    final target = _read(trustedPartnerKey);
    if (target == null || target == _myPeerId) return;

    final now = _clock.now();
    if (now - _resumeGuard < resumeCooldownMs) return;
    _resumeGuard = now;

    _dialQuietly(target);
  }

  @override
  void dispose() {
    skyTogether.dispose();
    appUpdate.dispose();
    _disposed = true;
    _active = false;
    _ready = false;
    _dialTimer?.cancel();
    _retryTicker?.cancel();
    _retryTicker = null;
    _stopConnectedTicker();
    vault.removeListener(_onVault);
    identity.removeListener(_leaveMyCode);
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

class _HubSkyTransport implements SkyTogetherTransport {
  _HubSkyTransport(this._hub);

  final PeerSyncHub _hub;
  void Function()? _onReadiness;
  void Function(Object? event)? _onEvent;

  @override
  bool get ready => _hub._active && !_hub._disposed && _hub.isAuthorized;

  @override
  void attach({required void Function() onReadiness, required void Function(Object? event) onEvent}) {
    _onReadiness = onReadiness;
    _onEvent = onEvent;
    _hub.addListener(_readiness);
    _hub.engine.addSkyTogetherListener(_event);
  }

  void _readiness() => _onReadiness?.call();

  void _event(Object? event) {
    if (ready) _onEvent?.call(event);
  }

  @override
  void detach() {
    _hub.removeListener(_readiness);
    _hub.engine.removeSkyTogetherListener(_event);
    _onReadiness = null;
    _onEvent = null;
  }

  @override
  Future<bool> send(Map<String, Object?> event) =>
      ready ? _hub.engine.sendSkyTogether(event) : Future<bool>.value(false);
}

class _HubUpdateTransport implements AppUpdateTransport {
  _HubUpdateTransport(this._hub);

  final PeerSyncHub _hub;
  void Function()? _onReadiness;
  void Function(Object? event)? _onEvent;
  void Function(Uint8List piece)? _onPiece;

  @override
  bool get ready => _hub._active && !_hub._disposed && _hub.isAuthorized;

  @override
  void attach({
    required void Function() onReadiness,
    required void Function(Object? event) onEvent,
    required void Function(Uint8List piece) onPiece,
  }) {
    _onReadiness = onReadiness;
    _onEvent = onEvent;
    _onPiece = onPiece;
    _hub.addListener(_readiness);
    _hub.engine.addAppUpdateListener(_event);
    _hub.engine.addAppPieceListener(_piece);
  }

  void _readiness() => _onReadiness?.call();

  void _event(Object? event) {
    if (ready) _onEvent?.call(event);
  }

  void _piece(Uint8List piece) {
    if (ready) _onPiece?.call(piece);
  }

  @override
  void detach() {
    _hub.removeListener(_readiness);
    _hub.engine.removeAppUpdateListener(_event);
    _hub.engine.removeAppPieceListener(_piece);
    _onReadiness = null;
    _onEvent = null;
    _onPiece = null;
  }

  @override
  Future<bool> send(Map<String, Object?> event) =>
      ready ? _hub.engine.sendAppUpdate(event) : Future<bool>.value(false);

  @override
  Future<bool> sendPiece(Uint8List piece) =>
      ready ? _hub.engine.sendAppPiece(piece) : Future<bool>.value(false);
}
