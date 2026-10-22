import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/core/engine/storage/local_settings.dart';
import 'package:our_space_mobile/presentation/screens/letters/letter_shelf.dart';

const int day = 24 * 60 * 60 * 1000;

LetterRecord letter(
  String id, {
  required int written,
  bool opened = false,
  int? openedAt,
  String? lockDate,
  int? lockBoundary,
}) {
  return LetterRecord(
    {
      'id': id,
      'title': id,
      'createdAt': written,
      'updatedAt': written,
      'isOpened': opened,
      'openedAt': ?openedAt,
    },
    lockDate: lockDate,
    lockBoundary: lockBoundary,
  );
}

void main() {
  final now = DateTime(2026, 10, 22, 21).millisecondsSinceEpoch;

  test('sorts letters into waiting, capsules, opened and sent', () {
    final letters = [
      letter('old-waiting', written: now - 5 * day),
      letter('new-waiting', written: now - 1000),
      letter('far-capsule', written: now - 3 * day, lockDate: '2027-09-25', lockBoundary: now + 300 * day),
      letter('near-capsule', written: now - 2 * day, lockDate: '2026-11-01', lockBoundary: now + 10 * day),
      letter('read-long-ago', written: now - 30 * day, opened: true, openedAt: now - 29 * day),
      letter('read-today', written: now - 20 * day, opened: true, openedAt: now - 1000),
      letter('mine-waiting', written: now - 2000),
      letter('mine-read', written: now - 9 * day, opened: true, openedAt: now - 8 * day),
      letter('mine-capsule', written: now - 4 * day, lockDate: '2026-12-01', lockBoundary: now + 40 * day),
      letter('unlocked-capsule', written: now - 40 * day, lockDate: '2026-10-01', lockBoundary: now - 21 * day),
    ];
    final shelf = LetterShelf.sort(letters, mine: {'mine-waiting', 'mine-read', 'mine-capsule'}, now: now);

    expect(shelf.waiting.map((l) => l.id), ['new-waiting', 'old-waiting', 'unlocked-capsule']);
    expect(shelf.feature?.id, 'new-waiting');
    expect(shelf.capsules.map((l) => l.id), ['near-capsule', 'far-capsule']);
    expect(shelf.opened.map((l) => l.id), ['read-today', 'mine-read', 'read-long-ago']);
    expect(shelf.sent.map((l) => l.id), ['mine-waiting', 'mine-capsule', 'mine-read']);
    expect(shelf.waitingCount, 5);
    expect(shelf.countOf(LetterSegment.waiting), 5);
    expect(shelf.countOf(LetterSegment.opened), 3);
    expect(shelf.countOf(LetterSegment.sent), 3);
  });

  test('an empty shelf has no feature letter', () {
    final shelf = LetterShelf.sort(const [], mine: const {}, now: now);
    expect(shelf.feature, isNull);
    expect(shelf.waitingCount, 0);
  });

  test('remembers the letters written on this phone', () async {
    final settings = LocalSettings.memory();
    expect(LettersWrittenHere.read(settings), isEmpty);
    await LettersWrittenHere.remember(settings, 'let-a');
    final ids = await LettersWrittenHere.remember(settings, 'let-b');
    expect(ids, {'let-a', 'let-b'});
    expect(LettersWrittenHere.read(settings), {'let-a', 'let-b'});
    await LettersWrittenHere.remember(settings, 'let-a');
    expect(LettersWrittenHere.read(settings), hasLength(2));

    final broken = LocalSettings.memory({LettersWrittenHere.settingsKey: 'not json'});
    expect(LettersWrittenHere.read(broken), isEmpty);
    final odd = LocalSettings.memory({LettersWrittenHere.settingsKey: '[1, "", "let-c"]'});
    expect(LettersWrittenHere.read(odd), {'let-c'});
  });

  test('keeps one draft per unlocked space and starts fresh without one', () {
    final key = VaultKey.fromBits(List<int>.filled(32, 7));
    final other = VaultKey.fromBits(List<int>.filled(32, 9));
    final draft = LetterDraft.forKey(key)..title = 'Half written';
    expect(identical(LetterDraft.forKey(key), draft), isTrue);
    expect(LetterDraft.forKey(other).title, isEmpty);
    expect(LetterDraft.forKey(null).isEmpty, isTrue);
    expect(draft.isEmpty, isFalse);
    draft
      ..content = 'Hello'
      ..unlockDate = '2027-02-14'
      ..clear();
    expect(draft.isEmpty, isTrue);
    expect(draft.unlockDate, isNull);
  });
}
