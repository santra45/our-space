import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/presentation/screens/letters/letters_copy.dart';
import 'package:our_space_mobile/presentation/sky/sky.dart';

int at(int year, int month, int day, [int hour = 12, int minute = 0]) =>
    DateTime(year, month, day, hour, minute).millisecondsSinceEpoch;

void main() {
  final now = DateTime(2026, 10, 22, 21, 30);

  test('counts hidden letters warmly', () {
    expect(
      LettersCopy.hiddenLetters(1),
      '1 letter could not be opened with your passphrase, so it is hidden for now.',
    );
    expect(
      LettersCopy.hiddenLetters(3),
      '3 letters could not be opened with your passphrase, so they are hidden for now.',
    );
  });

  test('asks before letting a letter go and names whose phone it leaves', () {
    expect(LettersCopy.deleteTitle, 'Let this letter go?');
    expect(LettersCopy.deleteMessage("Alex's"), "It will be gone from your phone and Alex's, for good.");
    expect(
      LettersCopy.emptyMessage('Alex'),
      'Leave a surprise letter for Alex, or seal one to open on your next anniversary.',
    );
    expect(LettersCopy.sealedToast('Alex'), 'Sealed with wax. It is waiting for Alex.');
    expect(LettersCopy.forOnly('Farhu'), 'For Farhu only');
  });

  test('keeps the promise and midnight rule in the seal note', () {
    expect(LettersCopy.sealNote, contains('midnight on the day you choose'));
    expect(LettersCopy.sealNote, contains('We will not open it early'));
    expect(LettersCopy.sealNote, contains('a promise, not a padlock'));
  });

  test('splits open when titles into a kicker and the rest', () {
    final missMe = LettersCopy.splitTitle('Open when you miss me');
    expect(missMe.kicker, 'Open when');
    expect(missMe.headline, 'you miss me');
    final sleep = LettersCopy.splitTitle('  open when, you cannot sleep ');
    expect(sleep.kicker, 'Open when');
    expect(sleep.headline, 'you cannot sleep');
    expect(LettersCopy.splitTitle('Open when').kicker, isNull);
    expect(LettersCopy.splitTitle('Open whenever').kicker, isNull);
    final plain = LettersCopy.splitTitle('Just because');
    expect(plain.kicker, isNull);
    expect(plain.headline, 'Just because');
  });

  test('writes dates and times the way the sky design does', () {
    expect(LettersCopy.dayMonth(DateTime(2026, 10, 12)), '12 Oct');
    expect(LettersCopy.dayMonthYear(DateTime(2027, 9, 25)), '25 Sep 2027');
    expect(LettersCopy.shortDate(DateTime(2026, 9, 25), now), '25 Sep');
    expect(LettersCopy.shortDate(DateTime(2025, 9, 25), now), '25 Sep 2025');
    expect(LettersCopy.longDate('2027-02-14'), '14 Feb 2027');
    expect(LettersCopy.longDate(null), '');
    expect(LettersCopy.clock(DateTime(2026, 10, 21, 23, 40)), '11:40 PM');
    expect(LettersCopy.clock(DateTime(2026, 10, 21, 0, 5)), '12:05 AM');
    expect(LettersCopy.clock(DateTime(2026, 10, 21, 12)), '12:00 PM');
    expect(LettersCopy.sealedAt(at(2026, 10, 21, 23, 40)), 'Sealed 21 Oct, 11:40 PM');
    expect(LettersCopy.sealedAt(0), 'Sealed with love');
  });

  test('says when a letter was sealed in night or day words', () {
    expect(LettersCopy.sealedWhen(at(2026, 10, 22, 20), now), 'Sealed tonight');
    expect(LettersCopy.sealedWhen(at(2026, 10, 22, 9), now), 'Sealed today');
    expect(LettersCopy.sealedWhen(at(2026, 10, 21, 23), now), 'Sealed last night');
    expect(LettersCopy.sealedWhen(at(2026, 10, 21, 10), now), 'Sealed yesterday');
    expect(LettersCopy.sealedWhen(at(2026, 10, 12), now), 'Sealed 12 Oct');
    expect(LettersCopy.sealedWhen(at(2025, 10, 12), now), 'Sealed 12 Oct 2025');
    expect(LettersCopy.sealedWhen(0, now), 'Sealed with love');
  });

  test('says when a letter was opened', () {
    expect(LettersCopy.openedWhen(at(2026, 10, 22, 21), now), 'Opened tonight');
    expect(LettersCopy.openedWhen(at(2026, 10, 22, 11), now), 'Opened today');
    expect(LettersCopy.openedWhen(at(2026, 10, 21, 22), now), 'Opened last night');
    expect(LettersCopy.openedWhen(at(2026, 10, 21, 8), now), 'Opened yesterday');
    expect(LettersCopy.openedWhen(at(2026, 10, 2), now), 'Opened 2 Oct');
    expect(LettersCopy.openedWhen(null, now), 'Opened');
  });

  test('marks a letter sealed today or last night as new tonight or today', () {
    expect(LettersCopy.newLabel(at(2026, 10, 22, 8), now, night: true), 'New tonight');
    expect(LettersCopy.newLabel(at(2026, 10, 22, 8), now, night: false), 'New today');
    expect(LettersCopy.newLabel(at(2026, 10, 21, 23, 40), now, night: true), 'New tonight');
    expect(LettersCopy.newLabel(at(2026, 10, 21, 10), now, night: false), 'New today');
    expect(LettersCopy.newLabel(at(2026, 10, 20), now, night: true), 'Waiting for you');
  });

  test('says who a letter is from like the design', () {
    final sealed = LettersCopy.lowerFirst(LettersCopy.sealedWhen(at(2026, 10, 21, 23), now));
    expect(LettersCopy.from('Farhu', sealed), 'From Farhu · sealed last night');
    expect(LettersCopy.capsuleFrom('Farhu'), 'A time capsule from Farhu');
    expect(LettersCopy.from('Farhu', LettersCopy.shortDate(DateTime(2026, 10, 12), now)), 'From Farhu · 12 Oct');
    expect(LettersCopy.capitalized('your partner'), 'Your partner');
    expect(LettersCopy.signature('Farhu'), '— Farhu');
  });

  test('counts nights at night and days by day', () {
    expect(LettersCopy.count(1, night: true), '1 night');
    expect(LettersCopy.count(338, night: true), '338 nights');
    expect(LettersCopy.count(338, night: false), '338 days');
    final midnight = DateTime(2026, 10, 23).millisecondsSinceEpoch;
    expect(LettersCopy.nightsUntil(midnight, now.millisecondsSinceEpoch), 1);
    expect(LettersCopy.nightsUntil(midnight, midnight + 1), 0);
    final boundary = getTimeLockBoundary('2027-09-25')!;
    final nights = LettersCopy.nightsUntil(boundary, now.millisecondsSinceEpoch);
    expect(nights, 338);
    expect(
      LettersCopy.opens('2027-09-25', boundary, now.millisecondsSinceEpoch, night: true),
      'Opens 25 Sep 2027 · 338 nights',
    );
    expect(
      LettersCopy.opens('2027-09-25', boundary, now.millisecondsSinceEpoch, night: false),
      'Opens 25 Sep 2027 · 338 days',
    );
    expect(LettersCopy.opens('2027-09-25', null, 0, night: true), 'Opens 25 Sep 2027');
  });

  test('describes the chosen seal day', () {
    expect(LettersCopy.sealOn('2026-10-22', now, night: true), '22 Oct · today, so it opens right away');
    expect(LettersCopy.sealOn('2026-10-20', now, night: true), '20 Oct · so it opens right away');
    expect(LettersCopy.sealOn('2026-10-23', now, night: true), '23 Oct · tomorrow');
    expect(LettersCopy.sealOn('2026-11-01', now, night: true), '1 Nov · in 10 nights');
    expect(LettersCopy.sealOn('2026-11-01', now, night: false), '1 Nov · in 10 days');
    expect(LettersCopy.sealOn('2027-01-01', now, night: false), '1 Jan 2027 · in 71 days');
  });

  test('never uses technical words in what she reads', () {
    const banned = ['sync', 'device', 'pair', 'server', 'upload', 'download', 'data', 'peer', 'relay', 'mailbox', 'encrypt', 'key'];
    final copy = [
      LettersCopy.kicker,
      LettersCopy.loading,
      LettersCopy.emptyMessage('Alex'),
      LettersCopy.nothingWaitingMessage,
      LettersCopy.noneOpenedMessage,
      LettersCopy.noneSentMessage('Alex'),
      LettersCopy.hiddenLetters(2),
      LettersCopy.deleteMessage("Alex's"),
      LettersCopy.deleteFailed,
      LettersCopy.sealNote,
      LettersCopy.saveFailed,
      LettersCopy.sealOff,
      LettersCopy.sealedToast('Alex'),
      LettersCopy.keptUntil('2026-10-22'),
      ...LettersCopy.prompts,
    ];
    for (final line in copy) {
      for (final word in banned) {
        expect(RegExp('\\b$word', caseSensitive: false).hasMatch(line), isFalse, reason: '"$line" says $word');
      }
      expect(skyCalmText(line), line, reason: line);
    }
  });
}
