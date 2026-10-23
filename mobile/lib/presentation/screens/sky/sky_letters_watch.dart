import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/engine.dart';
import '../../../core/engine/storage/local_settings.dart';
import '../letters/letter_shelf.dart';

typedef SkyNow = int Function();

int _systemNow() => DateTime.now().millisecondsSinceEpoch;

class SkyLettersWatch extends ChangeNotifier {
  SkyLettersWatch(this.letters, {required this.settings, this.tick = const Duration(seconds: 30), SkyNow? now})
    : _now = now ?? _systemNow {
    _subscription = letters.watch().listen(_onSnapshot, onError: (Object error) {});
    _written = LettersWrittenHere.changes(settings)..addListener(_onWritten);
  }

  final LettersRepository letters;
  final LocalSettings settings;
  final Duration tick;
  final SkyNow _now;

  StreamSubscription<TableSnapshot<LetterRecord>>? _subscription;
  late final Listenable _written;
  List<LetterRecord> _items = const [];
  Timer? _timer;
  int _waiting = 0;
  bool _loaded = false;
  bool _disposed = false;

  int get waiting => _waiting;
  bool get loaded => _loaded;

  void _onSnapshot(TableSnapshot<LetterRecord> snapshot) {
    if (_disposed) return;
    _items = snapshot.items;
    final first = !_loaded;
    _loaded = true;
    _recount(force: first);
  }

  void _onWritten() => _recount();

  void _recount({bool force = false}) {
    if (_disposed) return;
    final shelf = LetterShelf.sort(_items, mine: LettersWrittenHere.read(settings), now: _now());
    final next = shelf.waiting.length;
    _syncTimer(shelf.capsules.isNotEmpty);
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
    _written.removeListener(_onWritten);
    _timer?.cancel();
    _timer = null;
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
