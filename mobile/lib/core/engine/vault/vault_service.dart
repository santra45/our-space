import 'package:flutter/foundation.dart';

import '../../../models/vault_config.dart';
import '../crypto/aes_gcm.dart';
import '../crypto/base64.dart';
import '../crypto/canary.dart';
import '../crypto/js_compat.dart';
import '../crypto/kdf.dart';
import '../domain/date_helpers.dart';
import '../identity/device_id.dart';
import '../invite/invite.dart';
import '../storage/vault_store.dart';

const String destroyConfirmationPhrase = 'ERASE OUR MEMORIES';

const int _maxCoupleNamesLength = 120;

enum VaultCheckState { checking, absent, present, unreadable }

class VaultResult {
  const VaultResult._(this.ok, this.error, this.warning, this.code);

  const VaultResult.success({String? warning}) : this._(true, null, warning, null);

  const VaultResult.failure(String error, {String? code}) : this._(false, error, null, code);

  final bool ok;
  final String? error;
  final String? warning;
  final String? code;
}

class RestoreResult {
  const RestoreResult({required this.ok, this.code, this.relation, this.restored = 0, this.invalid = 0, this.undecryptable = 0});

  final bool ok;
  final String? code;
  final String? relation;
  final int restored;
  final int invalid;
  final int undecryptable;
}

class VaultMessages {
  static String passphraseTooShort() => 'Passphrase must be at least $minPassphraseLength characters long.';
  static const String couldNotOpen = 'We could not open your space. Try again in a moment.';
  static const String nothingHereYet = 'There is nothing here yet. Start your space, or join your partner’s.';
  static const String incorrectPassphrase = 'Incorrect passphrase! Please double-check and try again.';
  static const String unreadableNothingChanged = 'We could not read what is on this phone, so nothing was changed.';
  static const String needsConfirmation =
      'There is already a space on this phone. Replacing it would make everything in it impossible to open again, so we need you to confirm.';
  static const String couldNotSetUp = 'We could not set up your space. Please try again.';
  static const String malformedInvite = 'That invite link is malformed. Ask your partner for a fresh one.';
  static const String unreadableStoppedPairing =
      'We could not read what is on this phone, so we stopped instead of pairing.';
  static const String passphraseMismatch =
      'That passphrase does not match your partner’s. Check it together, character for character, and try again.';
  static const String pairedUnverified =
      'Paired! We will know your passphrases match the moment your phones connect — if they do not, we will tell you instead of syncing.';
  static const String couldNotPair = 'We could not pair with your partner. Please try again.';
  static const String lockedSettings = 'Our Space is locked. Unlock it before changing your settings.';
  static const String settingsNotSaved =
      'We could not save your settings. The old ones are still in place, and your partner was not told.';
  static const String pasteInvite =
      'Please paste your partner’s invite link — the one they sent you, or the QR code you scanned.';
  static String typeToConfirm() => 'Type $destroyConfirmationPhrase to confirm you want to erase everything here.';
}

String sanitizeCoupleNames(Object? value, [String fallback = 'Us']) {
  if (value is! String) return fallback;
  final trimmed = jsTrim(jsSlice(value, 0, _maxCoupleNamesLength));
  return trimmed.isEmpty ? fallback : trimmed;
}

bool isValidStartDate(Object? value) => isValidDateInput(value);

class VaultService extends ChangeNotifier {
  VaultService({required this.store, required this.device});

  final VaultStore store;
  final DeviceIdentity device;

  VaultCheckState _state = VaultCheckState.checking;
  VaultKey? _key;
  String? _salt;
  int? _iterations;
  VaultConfig? _config;

  VaultCheckState get state => _state;

  bool? get isInitialized => switch (_state) {
        VaultCheckState.present => true,
        VaultCheckState.absent => false,
        _ => null,
      };

  bool get isUnlocked => _key != null;

  VaultKey? get key => _key;

  String? get salt => _salt;

  int? get kdfIterations => _iterations;

  VaultConfig? get config => _config;

  VaultKey requireKey() {
    final key = _key;
    if (key == null) throw StoreError('Vault is locked. The passphrase must be entered again.');
    return key;
  }

  void _adopt(VaultKey key, String salt, int iterations, VaultConfig config) {
    _key = key;
    _salt = salt;
    _iterations = iterations;
    _config = config;
    _state = VaultCheckState.present;
    notifyListeners();
  }

  VaultConfig _configFrom(Map<String, Object?>? payload, Map<String, Object?> meta) {
    final payloadStart = payload?['startDate'];
    final payloadUpdated = payload?['updatedAt'];
    final metaUpdated = meta['updatedAt'];
    final updatedAt = numOrZero(payloadUpdated) != 0
        ? numOrZero(payloadUpdated)
        : (numOrZero(metaUpdated) != 0 ? numOrZero(metaUpdated) : 0);
    return VaultConfig(
      coupleNames: sanitizeCoupleNames(payload?['coupleNames']),
      startDate: (payloadStart is String && payloadStart.isNotEmpty) ? payloadStart : '',
      updatedAt: updatedAt.floor(),
    );
  }

  int _nextConfigTimestamp(VaultConfig? current) {
    final base = store.clock.next();
    final localAt = current?.updatedAt ?? 0;
    return base > localAt + 1 ? base : localAt + 1;
  }

  Future<void> check() async {
    _state = VaultCheckState.checking;
    notifyListeners();

    final read = await store.readVaultIdentity();
    if (!read.ok) {
      _state = VaultCheckState.unreadable;
      notifyListeners();
      return;
    }
    final meta = read.meta;
    if (meta == null) {
      _state = VaultCheckState.absent;
      notifyListeners();
      return;
    }
    _salt = meta['salt'] as String;
    _state = VaultCheckState.present;

    final held = _key;
    if (held != null) {
      final payload = readCanary(held, meta);
      if (payload == null) {
        _key = null;
        _config = null;
      } else {
        _config = _configFrom(payload, meta);
      }
    }
    notifyListeners();
  }

  Future<VaultResult> unlock(String passphrase) async {
    if (normalizePassphrase(passphrase).length < minPassphraseLength) {
      return VaultResult.failure(VaultMessages.passphraseTooShort(), code: 'passphrase_too_short');
    }

    Map<String, Object?>? meta;
    try {
      meta = await store.getVaultMeta();
    } catch (_) {
      return const VaultResult.failure(VaultMessages.couldNotOpen, code: 'unreadable');
    }
    final salt = meta?['salt'];
    if (meta == null || salt is! String || salt.isEmpty) {
      return const VaultResult.failure(VaultMessages.nothingHereYet, code: 'no_vault');
    }

    Map<String, Object?>? canaryPayload;
    DerivedKey derived;
    try {
      derived = await deriveKeyWithVerification(
        passphrase,
        salt,
        (candidate) {
          final payload = readCanary(candidate, meta);
          if (payload == null) return false;
          canaryPayload = payload;
          return true;
        },
        iterations: meta['kdfIterations'] as num?,
      );
    } catch (_) {
      return const VaultResult.failure(VaultMessages.incorrectPassphrase, code: 'wrong_passphrase');
    }

    _adopt(derived.key, salt, derived.iterations, _configFrom(canaryPayload, meta));
    return const VaultResult.success();
  }

  Future<(bool, Map<String, Object?>?, VaultResult?)> _guardDestructiveWrite(String? confirmDestroy) async {
    final read = await store.readVaultIdentity();
    if (!read.ok) {
      return (true, null, const VaultResult.failure(VaultMessages.unreadableNothingChanged, code: 'unreadable'));
    }
    if (read.meta == null) return (false, null, null);
    if (confirmDestroy != destroyConfirmationPhrase) {
      return (
        true,
        read.meta,
        const VaultResult.failure(VaultMessages.needsConfirmation, code: 'needs_confirmation'),
      );
    }
    return (false, read.meta, null);
  }

  Future<VaultResult> create({
    required String passphrase,
    String? coupleNames,
    String? startDate,
    String? confirmDestroy,
    int iterations = pbkdf2IterationsCurrent,
  }) async {
    final normalized = normalizePassphrase(passphrase);
    if (normalized.length < minPassphraseLength) {
      return VaultResult.failure(VaultMessages.passphraseTooShort(), code: 'passphrase_too_short');
    }

    final (blocked, existing, failure) = await _guardDestructiveWrite(confirmDestroy);
    if (blocked) return failure!;

    try {
      final salt = generateSalt();
      final key = await deriveKeyFromPassphrase(normalized, salt, iterations: iterations);

      final createdAt = store.now();
      final configAt = _nextConfigTimestamp(null);
      final config = VaultConfig(
        coupleNames: sanitizeCoupleNames(coupleNames),
        startDate: isValidStartDate(startDate) ? startDate! : localDateString(),
        updatedAt: configAt,
      );

      final sealed = createCanary(
        key,
        coupleNames: config.coupleNames,
        startDate: config.startDate,
        createdAt: createdAt,
        updatedAt: config.updatedAt,
        now: store.now,
      );

      await store.putVaultMeta({
        'salt': salt,
        'canary': sealed.canary,
        'canaryIv': sealed.canaryIv,
        'kdfIterations': iterations,
        'updatedAt': configAt,
      });

      if (existing != null) await store.clearSyncedTables();

      _adopt(key, salt, iterations, config);
      return const VaultResult.success();
    } catch (_) {
      return const VaultResult.failure(VaultMessages.couldNotSetUp, code: 'failed');
    }
  }

  Future<VaultResult> joinFromInvite({
    required String passphrase,
    required Invite? invite,
    String? confirmDestroy,
  }) async {
    final salt = invite?.salt;
    if (invite == null || salt == null) {
      return const VaultResult.failure(VaultMessages.pasteInvite, code: 'no_invite');
    }
    return joinWithSalt(
      passphrase: passphrase,
      salt: salt,
      startDate: invite.startDate,
      coupleNames: invite.coupleNames,
      canary: invite.canary,
      canaryIv: invite.canaryIv,
      confirmDestroy: confirmDestroy,
    );
  }

  Future<bool> inviteReplacesVault(Invite? invite) async {
    final read = await store.readVaultIdentity();
    final meta = read.meta;
    if (!read.ok || meta == null) return false;
    return invite?.salt != meta['salt'];
  }

  Future<VaultResult> joinWithSalt({
    required String passphrase,
    required String salt,
    String? startDate,
    String? coupleNames,
    String? canary,
    String? canaryIv,
    String? confirmDestroy,
    int iterations = pbkdf2IterationsCurrent,
  }) async {
    final normalized = normalizePassphrase(passphrase);
    if (normalized.length < minPassphraseLength) {
      return VaultResult.failure(VaultMessages.passphraseTooShort(), code: 'passphrase_too_short');
    }
    if (!isValidSalt(salt)) {
      return const VaultResult.failure(VaultMessages.malformedInvite, code: 'bad_salt');
    }

    final read = await store.readVaultIdentity();
    if (!read.ok) {
      return const VaultResult.failure(VaultMessages.unreadableStoppedPairing, code: 'unreadable');
    }
    final existing = read.meta;

    if (existing != null && existing['salt'] == salt) {
      return unlock(passphrase);
    }

    if (existing != null) {
      final (blocked, _, failure) = await _guardDestructiveWrite(confirmDestroy);
      if (blocked) return failure!;
    }

    try {
      final partnerMeta = (canary != null && canaryIv != null) ? {'canary': canary, 'canaryIv': canaryIv} : null;

      VaultKey key;
      String? warning;
      if (partnerMeta != null) {
        try {
          final derived = await deriveKeyWithVerification(
            passphrase,
            salt,
            (candidate) => readCanary(candidate, partnerMeta) != null,
            iterations: iterations,
          );
          key = derived.key;
        } catch (_) {
          return const VaultResult.failure(VaultMessages.passphraseMismatch, code: 'passphrase_mismatch');
        }
      } else {
        key = await deriveKeyFromPassphrase(normalized, salt, iterations: iterations);
        warning = VaultMessages.pairedUnverified;
      }

      final config = VaultConfig(
        coupleNames: sanitizeCoupleNames(coupleNames),
        startDate: isValidStartDate(startDate) ? startDate! : localDateString(),
        updatedAt: 0,
      );

      final sealed = createCanary(
        key,
        coupleNames: config.coupleNames,
        startDate: config.startDate,
        createdAt: store.now(),
        updatedAt: config.updatedAt,
        now: store.now,
      );

      await store.putVaultMeta({
        'salt': salt,
        'canary': sealed.canary,
        'canaryIv': sealed.canaryIv,
        'kdfIterations': iterations,
        'updatedAt': 0,
      });

      if (existing != null) await store.clearSyncedTables();

      _adopt(key, salt, iterations, config);
      return VaultResult.success(warning: warning);
    } catch (_) {
      return const VaultResult.failure(VaultMessages.couldNotPair, code: 'failed');
    }
  }

  Future<VaultResult> updateSettings({String? coupleNames, String? startDate}) async {
    final key = _key;
    if (key == null) {
      return const VaultResult.failure(VaultMessages.lockedSettings, code: 'locked');
    }
    try {
      final meta = await store.getVaultMeta();
      final salt = meta?['salt'];
      if (meta == null || salt is! String || salt.isEmpty) {
        throw StoreError('vaultMeta config row is missing on this device');
      }
      final current = _config;
      final mergedNames = coupleNames ?? current?.coupleNames;
      final mergedStart = startDate ?? current?.startDate;
      final updated = VaultConfig(
        coupleNames: sanitizeCoupleNames(mergedNames),
        startDate: isValidStartDate(mergedStart) ? mergedStart! : '',
        updatedAt: _nextConfigTimestamp(current),
      );
      final sealed = createCanary(
        key,
        coupleNames: updated.coupleNames,
        startDate: updated.startDate,
        updatedAt: updated.updatedAt,
        now: store.now,
      );
      await store.putVaultMeta({
        ...meta,
        'canary': sealed.canary,
        'canaryIv': sealed.canaryIv,
        'updatedAt': updated.updatedAt,
      });
      _config = updated;
      notifyListeners();
      return const VaultResult.success();
    } catch (_) {
      return const VaultResult.failure(VaultMessages.settingsNotSaved, code: 'failed');
    }
  }

  Future<RestoreResult> restoreFromBackup(
    Object? tables,
    String vaultPassphrase, {
    String? confirmDestroy,
  }) async {
    final identity = readBackupVaultIdentity(tables);
    if (identity == null) return const RestoreResult(ok: false, code: 'no_identity');
    final salt = identity['salt'] as String;
    if (!isValidSalt(salt)) return const RestoreResult(ok: false, code: 'bad_salt');
    if (normalizePassphrase(vaultPassphrase).length < minPassphraseLength) {
      return const RestoreResult(ok: false, code: 'passphrase_too_short');
    }

    DerivedKey derived;
    try {
      derived = await deriveKeyWithVerification(
        vaultPassphrase,
        salt,
        (candidate) => readCanary(candidate, identity) != null,
        iterations: identity['kdfIterations'] as num?,
      );
    } catch (_) {
      return const RestoreResult(ok: false, code: 'passphrase_mismatch');
    }

    final read = await store.readVaultIdentity();
    if (!read.ok) return const RestoreResult(ok: false, code: 'unreadable');

    final relation = compareVaultIdentity(identity, read);
    if (relation == 'same') return RestoreResult(ok: false, code: 'same_vault', relation: relation);
    if (relation == 'unknown') return RestoreResult(ok: false, code: 'unreadable', relation: relation);
    if (relation == 'foreign' && confirmDestroy != destroyConfirmationPhrase) {
      return RestoreResult(ok: false, code: 'needs_confirmation', relation: relation);
    }

    try {
      final payload = readCanary(derived.key, identity);
      await store.restoreVaultIdentity({...identity, 'kdfIterations': derived.iterations});
      await store.clearSyncedTables();
      final plan = await store.planBackupMerge(tables, derived.key);
      final applied = await store.applyBackupMerge(plan);
      _adopt(derived.key, salt, derived.iterations, _configFrom(payload, identity));
      return RestoreResult(
        ok: true,
        relation: relation,
        restored: applied.totalWritten,
        invalid: plan.totals.invalid,
        undecryptable: plan.totals.undecryptable,
      );
    } catch (_) {
      return RestoreResult(ok: false, code: 'write_failed', relation: relation);
    }
  }

  String? buildInviteLink({String? baseUrl, bool includeCanary = false, Map<String, Object?>? meta}) {
    final salt = _salt;
    if (salt == null) return null;
    final config = _config;
    return buildInviteUrl(
      device.peerId,
      salt,
      baseUrl: baseUrl,
      startDate: config?.startDate,
      coupleNames: config?.coupleNames,
      canary: includeCanary ? (meta?['canary'] as String?) : null,
      canaryIv: includeCanary ? (meta?['canaryIv'] as String?) : null,
    );
  }

  Future<String?> buildInviteLinkWithProof({String? baseUrl}) async {
    final meta = await store.getVaultMeta();
    return buildInviteLink(baseUrl: baseUrl, includeCanary: true, meta: meta);
  }

  void lock() {
    final wasUnlocked = _key != null;
    _key = null;
    _config = null;
    store.clock.reset();
    if (wasUnlocked) notifyListeners();
  }
}
