import 'dart:async';

import '../crypto/base64.dart';
import '../identity/identity_controller.dart';
import '../storage/local_settings.dart';
import '../vault/vault_service.dart';
import 'mailbox.dart';
import 'sync_service.dart';

const String pushDeviceKey = 'our_space_push_device';
const String pushRegisteredKey = 'our_space_push_registered';
const String pushAskedKey = 'our_space_push_asked';

abstract class PushPlatform {
  Future<bool> isAllowed();

  Future<bool> requestPermission();

  Future<String?> address();

  Stream<String> get addressChanges;

  Stream<void> get rings;
}

class PushService {
  PushService({
    required this.vault,
    required this.identity,
    required this.mailbox,
    required this.settings,
    required this.sync,
    this.platform,
  }) {
    final platform = this.platform;
    if (platform == null) return;
    vault.addListener(_onChange);
    identity.addListener(_onChange);
    _refreshes = platform.addressChanges.listen((address) {
      final registered = settings.getItem(pushRegisteredKey);
      if (registered == null || !registered.endsWith('|$address')) unawaited(check());
    });
    _rings = platform.rings.listen((_) => unawaited(sync.syncNow('push')));
  }

  final VaultService vault;
  final IdentityController identity;
  final Mailbox mailbox;
  final LocalSettings settings;
  final SyncService sync;
  final PushPlatform? platform;

  StreamSubscription<String>? _refreshes;
  StreamSubscription<void>? _rings;
  String? _lastSeen;
  bool _running = false;
  bool _again = false;
  bool _disposed = false;

  bool get available => platform != null && mailbox.isEnabled;

  String get _device {
    final stored = settings.getItem(pushDeviceKey);
    if (stored != null && stored.length >= 8) return stored;
    final fresh = generateUrlSafeNonce(12);
    unawaited(settings.setItem(pushDeviceKey, fresh));
    return fresh;
  }

  void _onChange() {
    final seen = '${vault.salt}|${identity.myOwnerId}|${vault.isUnlocked}';
    if (seen == _lastSeen) return;
    _lastSeen = seen;
    unawaited(check());
  }

  Future<void> check() async {
    if (_disposed || !available) return;
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    try {
      do {
        _again = false;
        await _reconcile();
      } while (_again && !_disposed);
    } catch (_) {
    } finally {
      _running = false;
    }
  }

  Future<void> _reconcile() async {
    final platform = this.platform;
    final key = vault.key;
    final salt = vault.salt;
    final owner = identity.myOwnerId;
    if (platform == null || key == null || salt == null || owner == null || !mailbox.isEnabled) return;

    var allowed = await platform.isAllowed();
    if (!allowed && settings.getItem(pushAskedKey) == null) {
      await settings.setItem(pushAskedKey, '1');
      allowed = await platform.requestPermission();
    }

    final registered = settings.getItem(pushRegisteredKey);
    final previous = registered?.split('|');
    final previousOwner = previous != null && previous.length == 3 && previous[0] == salt ? previous[1] : null;

    if (!allowed) {
      if (registered == null) return;
      if (previousOwner != null) {
        await mailbox.forgetPush(key: key, ownerId: previousOwner, device: _device);
      }
      await settings.removeItem(pushRegisteredKey);
      return;
    }

    final address = await platform.address();
    if (address == null || address.isEmpty) return;
    final fingerprint = '$salt|$owner|$address';
    if (registered == fingerprint) return;

    if (previousOwner != null && previousOwner != owner) {
      await mailbox.forgetPush(key: key, ownerId: previousOwner, device: _device);
    }
    if (await mailbox.registerPush(key: key, ownerId: owner, device: _device, address: address)) {
      await settings.setItem(pushRegisteredKey, fingerprint);
    }
  }

  void dispose() {
    _disposed = true;
    if (platform != null) {
      vault.removeListener(_onChange);
      identity.removeListener(_onChange);
    }
    unawaited(_refreshes?.cancel());
    unawaited(_rings?.cancel());
  }
}
