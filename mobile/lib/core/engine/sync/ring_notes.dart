import '../storage/local_settings.dart';

const List<String> ringKinds = ['letter', 'opened', 'polaroid', 'answer', 'done', 'dream', 'love'];

const String ringOpenedKey = 'our_space_ring_opened';

class RingNotes {
  RingNotes(this._settings);

  final LocalSettings _settings;
  final Set<String> _pending = {};

  bool get tellsOpened => _settings.getItem(ringOpenedKey) == '1';

  Future<void> setTellsOpened(bool on) =>
      on ? _settings.setItem(ringOpenedKey, '1') : _settings.removeItem(ringOpenedKey);

  void note(String kind) {
    if (!ringKinds.contains(kind)) return;
    if (kind == 'opened' && !tellsOpened) return;
    _pending.add(kind);
  }

  String? get next {
    for (final kind in ringKinds) {
      if (_pending.contains(kind)) return kind;
    }
    return null;
  }

  Set<String> take() {
    final taken = {..._pending};
    _pending.clear();
    return taken;
  }

  void restore(Set<String> kinds) => _pending.addAll(kinds.where(ringKinds.contains));
}
