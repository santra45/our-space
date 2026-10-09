import 'dart:async';

import 'package:flutter/foundation.dart';

import '../crypto/derived_ids.dart';
import '../domain/love_bursts.dart';
import '../identity/identity_controller.dart';
import '../storage/tables.dart';
import '../storage/vault_store.dart';
import '../vault/vault_service.dart';
import 'mailbox.dart';

enum MailboxRunState { idle, syncing, ok, failed }

class MailboxStatus {
  const MailboxStatus({
    required this.state,
    required this.at,
    this.applied = 0,
    this.uploaded = 0,
    this.reason,
  });

  static const MailboxStatus idle = MailboxStatus(state: MailboxRunState.idle, at: 0);

  final MailboxRunState state;
  final int at;
  final int applied;
  final int uploaded;
  final String? reason;
}

enum SyncNoticeKind { notice, warning, loveBurst }

class SyncNotice {
  const SyncNotice(this.text, this.kind);

  final String text;
  final SyncNoticeKind kind;
}

class SyncService extends ChangeNotifier {
  SyncService({
    required this.store,
    required this.vault,
    required this.identity,
    required this.mailbox,
    required this.loveBursts,
    this.autoSync = true,
  }) {
    mailbox.onWarning = (code, message) => _notify(SyncNotice(message, SyncNoticeKind.warning));
    store.clock.onWarning = (code, message) => _notify(SyncNotice(message, SyncNoticeKind.warning));
    vault.addListener(_onVault);
    _localSub = store.localWrites.listen((_) {
      if (autoSync) schedule('local-write');
    });
    _burstSub = store.watchTable(loveBurstsTable).listen((_) => unawaited(checkLoveBursts()));
  }

  final VaultStore store;
  final VaultService vault;
  final IdentityController identity;
  final Mailbox mailbox;
  final LoveBurstService loveBursts;
  final bool autoSync;

  late final StreamSubscription<String> _localSub;
  late final StreamSubscription<void> _burstSub;
  final StreamController<SyncNotice> _notices = StreamController<SyncNotice>.broadcast();
  final StreamController<int> _bursts = StreamController<int>.broadcast();

  MailboxStatus _status = MailboxStatus.idle;
  bool _busy = false;
  Timer? _timer;
  Object? _lastKey;
  String? _lastNotice;
  bool _burstCheckRunning = false;

  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  bool get mailboxEnabled => mailbox.isEnabled;
  MailboxStatus get status => _status;
  String? get lastNotice => _lastNotice;
  Stream<SyncNotice> get notices => _notices.stream;
  Stream<int> get loveBurstArrivals => _bursts.stream;

  void _notify(SyncNotice notice) {
    _lastNotice = notice.text;
    if (!_notices.isClosed) _notices.add(notice);
    notifyListeners();
  }

  void clearNotice() {
    _lastNotice = null;
    notifyListeners();
  }

  void _onVault() {
    final key = vault.key;
    if (identical(key, _lastKey)) return;
    _lastKey = key;
    if (key == null) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    if (autoSync) schedule('unlock', const Duration(milliseconds: 1500));
    unawaited(checkLoveBursts());
  }

  void onForeground() {
    identity.appInForeground = true;
    unawaited(identity.touchLastActive());
    if (autoSync) schedule('foreground', const Duration(milliseconds: 500));
  }

  void onBackground() {
    identity.appInForeground = false;
  }

  void schedule(String reason, [Duration delay = const Duration(seconds: 4)]) {
    if (!mailbox.isEnabled) return;
    _timer?.cancel();
    _timer = Timer(delay, () {
      _timer = null;
      unawaited(syncNow(reason));
    });
  }

  Future<MailboxStatus> syncNow([String reason = 'manual']) async {
    final key = vault.key;
    if (key == null || !mailbox.isEnabled) return _status;
    if (_busy) return _status;

    _busy = true;
    _status = MailboxStatus(state: MailboxRunState.syncing, at: _status.at);
    notifyListeners();

    try {
      final slots = derivePersonSlots(key);
      final result = await mailbox.sync(key: key, ownerId: identity.myOwnerId, slots: slots);
      _status = MailboxStatus(
        state: MailboxRunState.ok,
        at: store.now(),
        applied: result.applied,
        uploaded: result.uploaded,
        reason: reason,
      );
      if (result.applied > 0) {
        final plural = result.applied == 1 ? '' : 's';
        _notify(SyncNotice('${result.applied} new thing$plural from ${identity.partnerName} 💕', SyncNoticeKind.notice));
      }
    } catch (_) {
      _status = MailboxStatus(state: MailboxRunState.failed, at: store.now(), reason: reason);
    } finally {
      _busy = false;
      notifyListeners();
    }
    return _status;
  }

  Future<bool> sendLoveBurst() async {
    final key = vault.key;
    if (key == null) {
      _notify(const SyncNotice('Unlock Our Space first 💕', SyncNoticeKind.notice));
      return false;
    }
    try {
      await loveBursts.sendLoveBurst(key);
    } catch (_) {
      _notify(const SyncNotice('Could not send that just now 💕', SyncNoticeKind.notice));
      return false;
    }
    _notify(SyncNotice(
      'Saved 💕 ${identity.partnerName} will see it the moment you two connect.',
      SyncNoticeKind.notice,
    ));
    return true;
  }

  Future<int> checkLoveBursts() async {
    final key = vault.key;
    if (key == null || _burstCheckRunning) return 0;
    _burstCheckRunning = true;
    try {
      final unseen = await loveBursts.collectUnseenBursts(key);
      if (unseen.total <= 0) return 0;
      await loveBursts.markBurstsSeen(unseen.records);
      if (!_bursts.isClosed) _bursts.add(unseen.total);
      _notify(SyncNotice(describeBursts(unseen.total, false, identity.partnerName), SyncNoticeKind.loveBurst));
      return unseen.total;
    } catch (_) {
      return 0;
    } finally {
      _burstCheckRunning = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    vault.removeListener(_onVault);
    unawaited(_localSub.cancel());
    unawaited(_burstSub.cancel());
    unawaited(_notices.close());
    unawaited(_bursts.close());
    super.dispose();
  }
}
