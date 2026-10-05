import 'dart:typed_data';

/// In-memory holder for the unlocked master vault key.
///
/// CRITICAL SECURITY INVARIANT:
/// - Never saved to SharedPreferences, disk, SQLite, or logs.
/// - Exists ONLY in volatile memory (RAM) while the session is active.
/// - Cleared immediately when locked.
class VaultKeyHolder {
  VaultKeyHolder._();
  static final VaultKeyHolder instance = VaultKeyHolder._();

  Uint8List? _rawKeyBits;
  String? _salt;
  int? _iterations;
  int _unlockedAt = 0;

  final Set<void Function(bool isUnlocked)> _listeners = {};

  bool get isUnlocked => _rawKeyBits != null;
  Uint8List? get rawKeyBits => _rawKeyBits;
  String? get salt => _salt;
  int? get iterations => _iterations;
  int get unlockedAt => _unlockedAt;

  void addListener(void Function(bool isUnlocked) listener) {
    _listeners.add(listener);
  }

  void removeListener(void Function(bool isUnlocked) listener) {
    _listeners.remove(listener);
  }

  void _notify() {
    final unlocked = isUnlocked;
    for (final listener in List.of(_listeners)) {
      try {
        listener(unlocked);
      } catch (_) {}
    }
  }

  /// Sets the unlocked 256-bit (32 bytes) master key material.
  void setKey(Uint8List keyBits, {String? salt, int? iterations}) {
    if (keyBits.lengthInBytes != 32) {
      throw ArgumentError('Master vault key must be exactly 32 bytes (256 bits).');
    }
    _rawKeyBits = Uint8List.fromList(keyBits);
    _salt = salt;
    _iterations = iterations;
    _unlockedAt = DateTime.now().millisecondsSinceEpoch;
    _notify();
  }

  /// Returns the unlocked key, or throws if locked.
  Uint8List requireKey() {
    final key = _rawKeyBits;
    if (key == null) {
      throw StateError('Vault is locked. Passphrase or biometric required.');
    }
    return key;
  }

  /// Locks the vault and zeros out the key bytes in memory.
  void lock() {
    if (_rawKeyBits != null) {
      _rawKeyBits!.fillRange(0, _rawKeyBits!.length, 0); // Zeroize memory
      _rawKeyBits = null;
    }
    _salt = null;
    _iterations = null;
    _unlockedAt = 0;
    _notify();
  }
}
