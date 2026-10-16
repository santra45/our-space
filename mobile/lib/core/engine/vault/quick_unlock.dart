import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../crypto/aes_gcm.dart';
import '../crypto/base64.dart';
import '../storage/local_settings.dart';
import 'vault_service.dart';

const String quickUnlockSettingsKey = 'our_space_quick_unlock';

enum QuickUnlockAvailability { ready, noneEnrolled, unsupported }

abstract final class QuickUnlockCopy {
  static const String promptTitle = 'Our Space 💕';
  static const String openSubtitle = 'One touch, and you are back in your memories and notes.';
  static const String setupSubtitle = 'One touch now, so this phone can remember your passphrase.';
  static const String promptCancel = 'Not now';
  static const String needsSetupAgain =
      'Quick unlock needs setting up again on this phone. Use your passphrase just this once.';
  static const String needsSetupForNow =
      'Quick unlock needs setting up again on this phone. Use your passphrase for now.';
  static const String cannot = 'This phone cannot do quick unlock. Your passphrase still works.';
  static const String didNotWork = 'That did not work. Use your passphrase just this once.';
}

class QuickUnlockFailure implements Exception {
  const QuickUnlockFailure(this.code);

  final String code;

  @override
  String toString() => 'QuickUnlockFailure($code)';
}

class SealedSecret {
  const SealedSecret({required this.iv, required this.ciphertext});

  final Uint8List iv;
  final Uint8List ciphertext;
}

class QuickUnlockPrompt {
  const QuickUnlockPrompt({required this.title, this.subtitle, required this.cancel});

  static const QuickUnlockPrompt open = QuickUnlockPrompt(
    title: QuickUnlockCopy.promptTitle,
    subtitle: QuickUnlockCopy.openSubtitle,
    cancel: QuickUnlockCopy.promptCancel,
  );

  static const QuickUnlockPrompt setup = QuickUnlockPrompt(
    title: QuickUnlockCopy.promptTitle,
    subtitle: QuickUnlockCopy.setupSubtitle,
    cancel: QuickUnlockCopy.promptCancel,
  );

  final String title;
  final String? subtitle;
  final String cancel;

  Map<String, Object?> toArguments() => {
        'title': title,
        if (subtitle != null) 'subtitle': subtitle,
        'cancel': cancel,
      };
}

abstract class QuickUnlockPlatform {
  Future<QuickUnlockAvailability> availability();

  Future<SealedSecret> seal(Uint8List secret, Uint8List aad, QuickUnlockPrompt prompt);

  Future<Uint8List> open(SealedSecret sealed, Uint8List aad, QuickUnlockPrompt prompt);

  Future<void> forget();
}

class MethodChannelQuickUnlock implements QuickUnlockPlatform {
  const MethodChannelQuickUnlock([this._channel = const MethodChannel('our_space/quick_unlock')]);

  static const Set<String> _codes = {'cancelled', 'lockout', 'unsupported', 'stale', 'failed'};

  final MethodChannel _channel;

  Future<Object?> _call(String method, [Map<String, Object?>? arguments]) async {
    try {
      return await _channel.invokeMethod<Object?>(method, arguments);
    } on PlatformException catch (e) {
      throw QuickUnlockFailure(_codes.contains(e.code) ? e.code : 'failed');
    } on MissingPluginException {
      throw const QuickUnlockFailure('unsupported');
    } catch (_) {
      throw const QuickUnlockFailure('failed');
    }
  }

  @override
  Future<QuickUnlockAvailability> availability() async {
    try {
      return switch (await _call('availability')) {
        'ready' => QuickUnlockAvailability.ready,
        'none-enrolled' => QuickUnlockAvailability.noneEnrolled,
        _ => QuickUnlockAvailability.unsupported,
      };
    } catch (_) {
      return QuickUnlockAvailability.unsupported;
    }
  }

  @override
  Future<SealedSecret> seal(Uint8List secret, Uint8List aad, QuickUnlockPrompt prompt) async {
    final reply = await _call('seal', {'secret': secret, 'aad': aad, ...prompt.toArguments()});
    if (reply is Map) {
      final iv = reply['iv'];
      final ciphertext = reply['ciphertext'];
      if (iv is Uint8List && ciphertext is Uint8List) return SealedSecret(iv: iv, ciphertext: ciphertext);
    }
    throw const QuickUnlockFailure('failed');
  }

  @override
  Future<Uint8List> open(SealedSecret sealed, Uint8List aad, QuickUnlockPrompt prompt) async {
    final reply = await _call('open', {
      'iv': sealed.iv,
      'ciphertext': sealed.ciphertext,
      'aad': aad,
      ...prompt.toArguments(),
    });
    if (reply is Uint8List) return reply;
    throw const QuickUnlockFailure('failed');
  }

  @override
  Future<void> forget() async {
    try {
      await _call('forget');
    } catch (_) {}
  }
}

class QuickUnlockRecord {
  const QuickUnlockRecord({
    required this.vaultSalt,
    required this.sealed,
    required this.createdAt,
    this.iterations,
  });

  final String vaultSalt;
  final SealedSecret sealed;
  final int createdAt;
  final int? iterations;

  Map<String, Object?> toJson() => {
        'v': 1,
        'vaultSalt': vaultSalt,
        'iv': bufferToBase64(sealed.iv),
        'ciphertext': bufferToBase64(sealed.ciphertext),
        'iterations': iterations,
        'createdAt': createdAt,
      };

  static QuickUnlockRecord? parse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    final salt = decoded['vaultSalt'];
    final iv = decoded['iv'];
    final ciphertext = decoded['ciphertext'];
    final iterations = decoded['iterations'];
    final createdAt = decoded['createdAt'];
    if (decoded['v'] != 1 || salt is! String || salt.isEmpty) return null;
    if (!isValidBase64(iv) || !isValidBase64(ciphertext)) return null;
    return QuickUnlockRecord(
      vaultSalt: salt,
      sealed: SealedSecret(iv: base64ToBuffer(iv), ciphertext: base64ToBuffer(ciphertext)),
      createdAt: createdAt is num ? createdAt.floor() : 0,
      iterations: iterations is num ? iterations.floor() : null,
    );
  }
}

class QuickUnlockResult {
  const QuickUnlockResult.ok()
      : ok = true,
        code = null;

  const QuickUnlockResult.failed(String this.code) : ok = false;

  final bool ok;
  final String? code;
}

class QuickUnlockService extends ChangeNotifier {
  QuickUnlockService({
    required this.vault,
    required this.settings,
    QuickUnlockPlatform? platform,
    int Function()? now,
  })  : platform = platform ?? const MethodChannelQuickUnlock(),
        _now = now ?? _systemNow {
    vault.addListener(notifyListeners);
  }

  static int _systemNow() => DateTime.now().millisecondsSinceEpoch;

  final VaultService vault;
  final LocalSettings settings;
  final QuickUnlockPlatform platform;
  final int Function() _now;

  QuickUnlockAvailability _availability = QuickUnlockAvailability.unsupported;
  bool _busy = false;
  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  QuickUnlockAvailability get availability => _availability;

  bool get available => _availability == QuickUnlockAvailability.ready;

  bool get enrolled {
    final record = _record();
    final salt = vault.salt;
    return record != null && salt != null && record.vaultSalt == salt;
  }

  bool get offered => available && enrolled;

  QuickUnlockRecord? _record() => QuickUnlockRecord.parse(settings.getItem(quickUnlockSettingsKey));

  Uint8List _aad(String salt) => Uint8List.fromList(utf8.encode('our-space/quick-unlock/v1:$salt'));

  Future<void> refresh() async {
    final next = await platform.availability();
    if (next == _availability) return;
    _availability = next;
    notifyListeners();
  }

  Future<QuickUnlockResult> enable(String passphrase) async {
    final salt = vault.salt;
    if (salt == null) return const QuickUnlockResult.failed('no-vault');
    if (_busy) return const QuickUnlockResult.failed('failed');
    _busy = true;
    try {
      final derived = await vault.verifyPassphrase(passphrase);
      if (derived == null) return const QuickUnlockResult.failed('wrong-passphrase');
      final bits = derived.key.rawBytes;
      SealedSecret sealed;
      try {
        sealed = await platform.seal(bits, _aad(salt), QuickUnlockPrompt.setup);
      } on QuickUnlockFailure catch (failure) {
        return QuickUnlockResult.failed(failure.code == 'stale' ? 'failed' : failure.code);
      } finally {
        bits.fillRange(0, bits.length, 0);
      }
      final record = QuickUnlockRecord(
        vaultSalt: salt,
        sealed: sealed,
        createdAt: _now(),
        iterations: derived.iterations,
      );
      await settings.setItem(quickUnlockSettingsKey, jsonEncode(record.toJson()));
      notifyListeners();
      return const QuickUnlockResult.ok();
    } catch (_) {
      return const QuickUnlockResult.failed('failed');
    } finally {
      _busy = false;
    }
  }

  Future<VaultResult> unlock() async {
    final salt = vault.salt;
    final record = _record();
    if (salt == null || record == null) {
      return const VaultResult.failure(QuickUnlockCopy.needsSetupAgain, code: 'stale');
    }
    if (record.vaultSalt != salt) {
      await disable();
      return const VaultResult.failure(QuickUnlockCopy.needsSetupAgain, code: 'stale');
    }

    Uint8List bits;
    try {
      bits = await platform.open(record.sealed, _aad(salt), QuickUnlockPrompt.open);
    } on QuickUnlockFailure catch (failure) {
      switch (failure.code) {
        case 'cancelled':
          return const VaultResult.failure('', code: 'cancelled');
        case 'stale':
          await disable();
          return const VaultResult.failure(QuickUnlockCopy.needsSetupAgain, code: 'stale');
        case 'unsupported':
          await refresh();
          return const VaultResult.failure(QuickUnlockCopy.cannot, code: 'unsupported');
        default:
          return VaultResult.failure(QuickUnlockCopy.didNotWork, code: failure.code);
      }
    } catch (_) {
      return const VaultResult.failure(QuickUnlockCopy.didNotWork, code: 'failed');
    }

    try {
      if (bits.length != aesKeyLengthBytes) {
        await disable();
        return const VaultResult.failure(QuickUnlockCopy.needsSetupAgain, code: 'stale');
      }
      final result = await vault.unlockWithKey(VaultKey.fromBits(bits), iterations: record.iterations);
      if (result.code == 'wrong_key') {
        await disable();
        return const VaultResult.failure(QuickUnlockCopy.needsSetupForNow, code: 'stale');
      }
      return result;
    } finally {
      bits.fillRange(0, bits.length, 0);
    }
  }

  Future<void> disable() async {
    await settings.removeItem(quickUnlockSettingsKey);
    await platform.forget();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    vault.removeListener(notifyListeners);
    super.dispose();
  }
}
