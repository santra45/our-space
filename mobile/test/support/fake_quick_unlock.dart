import 'package:flutter/foundation.dart';
import 'package:our_space_mobile/core/engine.dart';

class FakeQuickUnlock implements QuickUnlockPlatform {
  FakeQuickUnlock({this.state = QuickUnlockAvailability.ready});

  QuickUnlockAvailability state;
  String? failNext;
  Uint8List? openAs;
  final List<String> calls = [];

  final Uint8List _pad = Uint8List.fromList(List<int>.generate(64, (i) => (i * 37 + 11) & 0xff));
  Uint8List? _secret;
  Uint8List? _aad;

  bool get holdsKey => _secret != null;

  void _maybeFail() {
    final code = failNext;
    if (code == null) return;
    failNext = null;
    throw QuickUnlockFailure(code);
  }

  Uint8List _xor(List<int> bytes) => Uint8List.fromList([for (var i = 0; i < bytes.length; i++) bytes[i] ^ _pad[i]]);

  @override
  Future<QuickUnlockAvailability> availability() async {
    calls.add('availability');
    return state;
  }

  @override
  Future<SealedSecret> seal(Uint8List secret, Uint8List aad, QuickUnlockPrompt prompt) async {
    calls.add('seal');
    _maybeFail();
    _secret = Uint8List.fromList(secret);
    _aad = Uint8List.fromList(aad);
    return SealedSecret(iv: Uint8List(12), ciphertext: _xor(secret));
  }

  @override
  Future<Uint8List> open(SealedSecret sealed, Uint8List aad, QuickUnlockPrompt prompt) async {
    calls.add('open');
    _maybeFail();
    if (_secret == null || !listEquals(aad, _aad)) throw const QuickUnlockFailure('stale');
    final override = openAs;
    if (override != null) return Uint8List.fromList(override).asUnmodifiableView();
    return _xor(sealed.ciphertext).asUnmodifiableView();
  }

  @override
  Future<void> forget() async {
    calls.add('forget');
    _secret = null;
    _aad = null;
  }
}
