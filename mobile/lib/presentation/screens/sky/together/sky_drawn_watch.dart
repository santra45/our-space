import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/engine.dart';
import 'sky_drawn.dart';

class SkyDrawnWatch extends ChangeNotifier {
  SkyDrawnWatch({required this.service, required this.vault}) {
    vault.addListener(_onVault);
    _key = vault.key;
    final service = this.service;
    if (service == null) {
      _loaded = true;
      return;
    }
    _subscription = service.watch().listen((_) => _reload(), onError: (Object _) {});
  }

  final SkyDrawingService? service;
  final VaultService vault;

  StreamSubscription<void>? _subscription;
  VaultKey? _key;
  SkyDrawnShelf _shelf = SkyDrawnShelf.empty;
  bool _loaded = false;
  bool _loading = false;
  bool _again = false;
  bool _paused = false;
  bool _dirty = false;
  bool _disposed = false;

  SkyDrawnShelf get shelf => _shelf;

  List<SkyDrawingRecord> get finished => _shelf.finished;

  bool get loaded => _loaded;

  bool get paused => _paused;

  set paused(bool value) {
    if (value == _paused || _disposed) return;
    _paused = value;
    if (value || !_dirty) return;
    _dirty = false;
    _reload();
  }

  void _onVault() {
    if (_disposed || identical(vault.key, _key)) return;
    _key = vault.key;
    if (_key == null) {
      _apply(SkyDrawnShelf.empty);
      return;
    }
    _reload();
  }

  void _reload() {
    if (_disposed) return;
    if (_paused && _loaded) {
      _dirty = true;
      return;
    }
    if (_loading) {
      _again = true;
      return;
    }
    _loading = true;
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      do {
        _again = false;
        final service = this.service;
        final key = vault.key;
        final records = service == null || key == null ? const <SkyDrawingRecord>[] : await service.list(key);
        if (_disposed) return;
        if (!identical(vault.key, key)) {
          _again = true;
          continue;
        }
        _apply(SkyDrawnShelf.of(records));
      } while (_again && !_disposed);
    } finally {
      _loading = false;
    }
  }

  static String _signature(SkyDrawnShelf shelf) =>
      [for (final r in shelf.finished) '${r.id}:${r.updatedAt}'].join('|');

  void _apply(SkyDrawnShelf next) {
    if (_disposed) return;
    final changed = !_loaded || _signature(next) != _signature(_shelf);
    _shelf = next;
    _loaded = true;
    if (changed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    vault.removeListener(_onVault);
    unawaited(_subscription?.cancel());
    _subscription = null;
    super.dispose();
  }
}
