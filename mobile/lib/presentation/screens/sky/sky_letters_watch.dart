import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/engine.dart';

typedef SkyNow = int Function();

int _systemNow() => DateTime.now().millisecondsSinceEpoch;

class SkyLettersWatch extends ChangeNotifier {
  SkyLettersWatch(this.letters, {this.tick = const Duration(seconds: 30), SkyNow? now}) : _now = now ?? _systemNow {
    _subscription = letters.watch().listen(_onSnapshot, onError: (Object error) {});
  }

  final LettersRepository letters;
  final Duration tick;
  final SkyNow _now;

  StreamSubscription<TableSnapshot<LetterRecord>>? _subscription;
  List<LetterRecord> _items = const [];
  Timer? _timer;
  int _waiting = 0;
  bool _loaded = false;
  bool _disposed = false;

  int get waiting => _waiting;
  bool get loaded => _loaded;

  static bool isWaiting(LetterRecord letter, int now) => !letter.isOpened && !letter.isLockedAt(now);

  void _onSnapshot(TableSnapshot<LetterRecord> snapshot) {
    if (_disposed) return;
    _items = snapshot.items;
    final first = !_loaded;
    _loaded = true;
    _recount(force: first);
  }

  void _recount({bool force = false}) {
    if (_disposed) return;
    final now = _now();
    final next = _items.where((letter) => isWaiting(letter, now)).length;
    final pending = _items.any((letter) => !letter.isOpened && letter.isLockedAt(now));
    _syncTimer(pending);
    if (next == _waiting && !force) return;
    _waiting = next;
    notifyListeners();
  }

  void _syncTimer(bool pending) {
    if (pending && _timer == null) {
      _timer = Timer.periodic(tick, (_) => _recount());
    } else if (!pending && _timer != null) {
      _timer!.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
