import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/presentation/screens/love/love_sheet.dart';
import 'package:our_space_mobile/presentation/screens/love/love_tally.dart';

void main() {
  group('LoveTally', () {
    test('splits bursts between this phone, my other phones and the partner', () {
      final tally = LoveTally.fromRows(
        [
          {'id': 'burst-me', 'count': 4, 'lastSentAt': 100},
          {'id': 'burst-my-tablet', 'count': 2, 'lastSentAt': 300},
          {'id': 'burst-alex', 'count': 5, 'lastSentAt': 200},
          {'id': 'burst-alex-laptop', 'count': 1.8, 'lastSentAt': 400},
        ],
        ownRecordId: 'burst-me',
        myOwnerIds: {'person-me', 'my-tablet'},
      );
      expect(tally.sent, 6);
      expect(tally.received, 6);
      expect(tally.lastSentAt, 300);
      expect(tally.lastReceivedAt, 400);
      expect(tally.hasReceived, isTrue);
      expect(tally.mine, {
        'burst-me': (count: 4, at: 100),
        'burst-my-tablet': (count: 2, at: 300),
      });
    });

    test('skips rows that are tampered, deleted, empty or malformed', () {
      final tally = LoveTally.fromRows(
        [
          {'id': 'burst-alex', 'count': 3, 'lastSentAt': 50, '_headerTampered': true},
          {'id': 'burst-alex-2', 'count': 3, 'lastSentAt': 60, '_tableTampered': true},
          {'id': 'burst-alex-3', 'count': 3, 'lastSentAt': 70, 'deleted': true},
          {'id': 'burst-alex-4', 'count': 0, 'lastSentAt': 80},
          {'id': 'burst-alex-5', 'count': -2, 'lastSentAt': 90},
          {'id': 'burst-alex-6', 'count': double.nan},
          {'id': 'burst-alex-7', 'count': '9'},
          {'id': 42, 'count': 9},
          {'count': 9},
          {'id': 'burst-alex-8', 'count': 2, 'lastSentAt': 'yesterday'},
        ],
        ownRecordId: 'burst-me',
      );
      expect(tally.sent, 0);
      expect(tally.received, 2);
      expect(tally.lastReceivedAt, isNull);
      expect(tally.lastSentAt, isNull);
      expect(tally.mine, isEmpty);
    });

    test('an empty table is an empty tally', () {
      expect(LoveTally.fromRows(const [], ownRecordId: 'burst-me'), LoveTally.empty);
      expect(LoveTally.empty.hasReceived, isFalse);
    });

    test('recognises my own records', () {
      expect(LoveTally.isMine('burst-me', ownRecordId: 'burst-me'), isTrue);
      expect(LoveTally.isMine('burst-tab', ownRecordId: 'burst-me', myOwnerIds: {'tab'}), isTrue);
      expect(LoveTally.isMine('burst-alex', ownRecordId: 'burst-me', myOwnerIds: {'tab'}), isFalse);
      expect(LoveTally.isMine('tab', ownRecordId: 'burst-me', myOwnerIds: {'tab'}), isFalse);
    });

    test('counts read with thousands separators', () {
      expect(formatLoveCount(0), '0');
      expect(formatLoveCount(14), '14');
      expect(formatLoveCount(999), '999');
      expect(formatLoveCount(1204), '1,204');
      expect(formatLoveCount(1000000), '1,000,000');
    });
  });

  group('LoveSheetCopy', () {
    const she = PronounSet(
      subject: 'she',
      object: 'her',
      possessive: 'her',
      independent: 'hers',
      has: 'has',
      isVerb: 'is',
    );

    test('uses the partner name and pronoun', () {
      expect(LoveSheetCopy.forName('Alex'), 'For Alex');
      expect(LoveSheetCopy.reaches('Alex', she), 'It reaches Alex right away, wherever she is.');
      expect(LoveSheetCopy.sendTo('Alex'), 'Send love to Alex');
      expect(LoveSheetCopy.fromName('Alex'), 'from Alex');
      expect(LoveSheetCopy.arrived('Alex'), 'Alex has it now.');
      expect(LoveSheetCopy.saved('Alex'), 'Alex will feel it the moment you two connect.');
      expect(LoveSheetCopy.waiting('Alex'), 'When Alex sends love, it lands here.');
      expect(LoveSheetCopy.latest('Alex', '10:42 PM'), 'Alex sent you love, 10:42 PM');
      expect(LoveSheetCopy.latest('Alex', null), 'Alex sent you love');
    });

    test('starts sentences with a capital when the name is a fallback', () {
      expect(LoveSheetCopy.arrived('your partner'), 'Your partner has it now.');
      expect(LoveSheetCopy.saved('your partner'), 'Your partner will feel it the moment you two connect.');
      expect(LoveSheetCopy.latest('your partner', null), 'Your partner sent you love');
      expect(LoveSheetCopy.lead(''), '');
    });

    test('says when love arrived in plain words', () {
      final now = DateTime(2026, 10, 22, 21, 30);
      expect(LoveSheetCopy.when(DateTime(2026, 10, 22, 8, 5), now, '8:05 AM'), '8:05 AM');
      expect(LoveSheetCopy.when(DateTime(2026, 10, 21, 23, 59), now, '11:59 PM'), 'Yesterday');
      expect(LoveSheetCopy.when(DateTime(2026, 6, 14, 12), now, '12:00 PM'), 'Jun 14');
      expect(LoveSheetCopy.when(DateTime(2026, 10, 23, 1), now, '1:00 AM'), '1:00 AM');
    });

    test('never uses emoji or technical words', () {
      final strings = [
        LoveSheetCopy.title,
        LoveSheetCopy.send,
        LoveSheetCopy.holding,
        LoveSheetCopy.sending,
        LoveSheetCopy.sent,
        LoveSheetCopy.retry,
        LoveSheetCopy.hint,
        LoveSheetCopy.failed,
        LoveSheetCopy.locked,
        LoveSheetCopy.sentThisWeek,
        LoveSheetCopy.sentYouLove,
        LoveSheetCopy.yesterday,
        LoveSheetCopy.reaches('Alex', she),
        LoveSheetCopy.arrived('Alex'),
        LoveSheetCopy.saved('Alex'),
        LoveSheetCopy.waiting('Alex'),
      ];
      final banned = RegExp(
        r'\b(sync|device|pair|server|upload|download|data|peer|relay|mailbox|encrypt|key)',
        caseSensitive: false,
      );
      final emoji = RegExp(r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}]', unicode: true);
      for (final s in strings) {
        expect(banned.hasMatch(s), isFalse, reason: s);
        expect(emoji.hasMatch(s), isFalse, reason: s);
      }
    });
  });
}
