import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/engine.dart';
import '../../../core/engine/storage/local_settings.dart';

enum LetterSegment { waiting, opened, sent }

@immutable
class LetterShelf {
  const LetterShelf._({
    required this.waiting,
    required this.capsules,
    required this.opened,
    required this.sent,
  });

  factory LetterShelf.sort(List<LetterRecord> letters, {required Set<String> mine, required int now}) {
    final waiting = <LetterRecord>[];
    final capsules = <LetterRecord>[];
    final opened = <LetterRecord>[];
    final sent = <LetterRecord>[];
    for (final letter in letters) {
      final isMine = mine.contains(letter.id);
      if (isMine) sent.add(letter);
      if (letter.isOpened) {
        opened.add(letter);
      } else if (!isMine) {
        (letter.isLockedAt(now) ? capsules : waiting).add(letter);
      }
    }
    waiting.sort(_newestFirst);
    capsules.sort(_soonestFirst);
    opened.sort(_recentlyOpenedFirst);
    sent.sort(_newestFirst);
    return LetterShelf._(waiting: waiting, capsules: capsules, opened: opened, sent: sent);
  }

  final List<LetterRecord> waiting;
  final List<LetterRecord> capsules;
  final List<LetterRecord> opened;
  final List<LetterRecord> sent;

  LetterRecord? get feature => waiting.isEmpty ? null : waiting.first;

  int get waitingCount => waiting.length + capsules.length;

  int countOf(LetterSegment segment) {
    switch (segment) {
      case LetterSegment.waiting:
        return waitingCount;
      case LetterSegment.opened:
        return opened.length;
      case LetterSegment.sent:
        return sent.length;
    }
  }

  static int _newestFirst(LetterRecord a, LetterRecord b) => b.writtenAt.compareTo(a.writtenAt);

  static int _soonestFirst(LetterRecord a, LetterRecord b) =>
      (a.lockBoundary ?? 0).compareTo(b.lockBoundary ?? 0);

  static int _recentlyOpenedFirst(LetterRecord a, LetterRecord b) =>
      (b.openedAt ?? b.writtenAt).compareTo(a.openedAt ?? a.writtenAt);
}

abstract final class LettersWrittenHere {
  static const String settingsKey = 'lettersWrittenHere';

  static final Expando<ValueNotifier<int>> _changes = Expando<ValueNotifier<int>>('LettersWrittenHere');

  static Listenable changes(LocalSettings settings) => _changes[settings] ??= ValueNotifier<int>(0);

  static Set<String> read(LocalSettings settings) {
    final raw = settings.getItem(settingsKey);
    if (raw == null || raw.isEmpty) return <String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return {for (final id in decoded) if (id is String && id.isNotEmpty) id};
    } catch (_) {}
    return <String>{};
  }

  static Future<Set<String>> remember(LocalSettings settings, String id) async {
    final ids = read(settings)..add(id);
    await settings.setItem(settingsKey, jsonEncode(ids.toList()));
    final changes = _changes[settings];
    if (changes != null) changes.value++;
    return ids;
  }
}

class LetterDraft {
  String title = '';
  String content = '';
  String? unlockDate;

  bool get isEmpty => title.trim().isEmpty && content.trim().isEmpty && unlockDate == null;

  void clear() {
    title = '';
    content = '';
    unlockDate = null;
  }

  static final Expando<LetterDraft> _drafts = Expando<LetterDraft>('LetterDraft');

  static LetterDraft forKey(VaultKey? key) => key == null ? LetterDraft() : (_drafts[key] ??= LetterDraft());
}
