import '../../../models/letter_record.dart';
import '../crypto/base64.dart';
import '../crypto/envelope.dart';
import '../crypto/js_compat.dart';
import '../crypto/time_lock.dart';
import '../domain/date_helpers.dart';
import '../storage/tables.dart';
import '../storage/vault_store.dart';
import 'table_repository.dart';

const int _maxSealUpgradeAttempts = 3;

String? normalizeUnlockDate(Object? value) {
  if (value is! String) return null;
  final trimmed = jsTrim(value);
  if (trimmed.isEmpty) return null;
  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(trimmed)) return trimmed;
  final parsed = DateTime.tryParse(trimmed);
  if (parsed == null) return null;
  return toJsIsoString(parsed.millisecondsSinceEpoch).substring(0, 10);
}

enum LetterNoticeTone { lock, error }

class LetterOpening {
  const LetterOpening._(this.content, this.notice, this.tone);

  const LetterOpening.content(String content) : this._(content, null, null);

  const LetterOpening.notice(String notice, LetterNoticeTone tone) : this._(null, notice, tone);

  final String? content;
  final String? notice;
  final LetterNoticeTone? tone;

  bool get isOpen => content != null;
}

class LettersRepository extends TableRepository<LetterRecord> {
  LettersRepository({required super.store, required super.vault}) : super(table: lettersTable);

  final Map<String, int> _upgradeAttempts = {};
  final Set<String> _sealInFlight = {};

  @override
  LetterRecord? fromPlain(Map<String, Object?> plain, Row row) {
    final fields = stripInternalFields(plain);
    final lockDate = normalizeUnlockDate(fields['unlockDate']);
    return LetterRecord(fields, lockDate: lockDate, lockBoundary: getTimeLockBoundary(lockDate));
  }

  @override
  int compare(LetterRecord a, LetterRecord b) => b.writtenAt - a.writtenAt;

  String newLetterId() => 'let-${store.now().toRadixString(36)}-${generateUrlSafeNonce(6)}';

  Future<Row?> writeLetter({required String title, required String content, String? unlockDate}) async {
    final key = requireKey();
    final trimmedTitle = jsTrim(title);
    final trimmedContent = jsTrim(content);
    if (trimmedTitle.isEmpty || trimmedContent.isEmpty) return null;

    final id = newLetterId();
    final lockDate = normalizeUnlockDate(unlockDate);
    final record = <String, Object?>{
      'id': id,
      'title': trimmedTitle,
      'unlockDate': lockDate,
      'isOpened': false,
      'createdAt': store.now(),
      'updatedAt': stamp(),
      'deleted': false,
    };
    if (lockDate != null) {
      record['sealedContent'] = sealTimeLocked(trimmedContent, lockDate, key, context: id);
    } else {
      record['content'] = trimmedContent;
    }
    return store.putEncrypted(lettersTable, record, key);
  }

  String _until(String lockDate) => '${formatDatePretty(lockDate)} - ${formatTimeRemaining(lockDate, now: store.now())}';

  LetterOpening open(LetterRecord letter) {
    final key = requireKey();
    final now = store.now();
    final lockDate = letter.lockDate;

    if (lockDate != null && letter.isLockedAt(now)) {
      final until = _until(lockDate);
      return LetterOpening.notice(
        letter.isSealed
            ? '"${letter.title}" is sealed until $until 💕 We will not open it early.'
            : '"${letter.title}" stays shut until $until 💕 We are still tucking this one away properly — it will be sealed the next time this screen can.',
        LetterNoticeTone.lock,
      );
    }

    if (!letter.isSealed) {
      return LetterOpening.content(letter.content ?? '');
    }

    try {
      final sealed = letter.sealedContent;
      if (sealed == null) throw RecordError('not a sealed envelope');
      return LetterOpening.content(unsealTimeLocked(sealed, key, context: letter.id, now: now));
    } on TimeLockedError catch (err) {
      return LetterOpening.notice('Still sealed until ${formatDatePretty(err.unlockDate)}.', LetterNoticeTone.lock);
    } catch (_) {
      return const LetterOpening.notice(
        'We could not open this letter. Something about it changed, so it cannot be read any more.',
        LetterNoticeTone.error,
      );
    }
  }

  Future<Row?> markOpened(String id) async {
    final key = requireKey();
    try {
      final stored = await store.getDecrypted(lettersTable, id, key);
      if (stored == null || stored['deleted'] == true || stored['isOpened'] == true) return null;
      return await store.putEncrypted(
        lettersTable,
        {
          ...stripInternalFields(stored),
          'isOpened': true,
          'openedAt': store.now(),
          'updatedAt': stamp(),
        },
        key,
      );
    } catch (_) {
      return null;
    }
  }

  Future<String> _sealOnePendingLock(String id) async {
    final key = requireKey();
    final stored = await store.getDecrypted(lettersTable, id, key);
    if (stored == null) return 'skipped';
    if (stored['deleted'] == true) return 'skipped';
    if (stored['_headerTampered'] == true) return 'skipped';
    final existingSeal = stored['sealedContent'];
    if (existingSeal != null && existingSeal != false && existingSeal != '' && existingSeal != 0) return 'skipped';
    final content = stored['content'];
    if (content is! String || content.isEmpty) return 'skipped';

    final lockDate = normalizeUnlockDate(stored['unlockDate']);
    if (lockDate == null) return 'skipped';
    if (isTimeLockOpen(lockDate, store.now())) return 'skipped';

    final sealedContent = sealTimeLocked(content, lockDate, key, context: id);
    final fields = stripInternalFields(stored)
      ..['unlockDate'] = lockDate
      ..['sealedContent'] = sealedContent
      ..remove('content')
      ..['updatedAt'] = stamp();
    await store.putEncrypted(lettersTable, fields, key);

    final confirmed = await store.getDecrypted(lettersTable, id, key);
    if (confirmed == null || confirmed['sealedContent'] == null) return 'failed';
    return 'sealed';
  }

  Future<int> upgradePendingLocks(Iterable<LetterRecord> records) async {
    var sealed = 0;
    for (final record in records) {
      if (vault.key == null) return sealed;
      if (record.isSealed) continue;
      final content = record.content;
      if (content == null || content.isEmpty) continue;
      final lockDate = record.lockDate;
      if (lockDate == null) continue;
      if (isTimeLockOpen(lockDate, store.now())) continue;

      final id = record.id;
      if (_sealInFlight.contains(id)) continue;
      if ((_upgradeAttempts[id] ?? 0) >= _maxSealUpgradeAttempts) continue;

      _sealInFlight.add(id);
      String outcome;
      try {
        outcome = await _sealOnePendingLock(id);
      } catch (_) {
        outcome = 'failed';
      } finally {
        _sealInFlight.remove(id);
      }
      if (outcome == 'sealed' || outcome == 'failed') {
        _upgradeAttempts[id] = (_upgradeAttempts[id] ?? 0) + 1;
      }
      if (outcome == 'sealed') sealed++;
    }
    return sealed;
  }
}
