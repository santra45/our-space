import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/core/engine/p2p/peer_hub.dart' show partnerSyncProblemPrefix;
import 'package:our_space_mobile/core/engine/p2p/peer_sync_engine.dart'
    show iceFailureMessage, openTimeoutMessage, unverifiableWarningText;
import 'package:our_space_mobile/core/engine/storage/sync_clock.dart';
import 'package:our_space_mobile/core/engine/sync/manifest_diff.dart' show clockSkewWarning;
import 'package:our_space_mobile/presentation/screens/sync/notice_copy.dart';
import 'package:our_space_mobile/presentation/screens/sync/peer_link.dart';
import 'package:our_space_mobile/presentation/sky/sky.dart';
import 'package:our_space_mobile/presentation/space_scope.dart';

import 'hub_harness.dart' show openUnlockedSpace;

final RegExp banned = RegExp(
  r'\b(sync\w*|devices?|pair\w*|servers?|upload\w*|download\w*|data|peers?|relay\w*|mailbox\w*|encrypt\w*|keys?)\b',
  caseSensitive: false,
);

const List<String> engineNotices = [
  'Synced 3 new item(s) from Alex 💕',
  'Synced 1 update from your partner!',
  'Synced 4 updates from your partner!',
  'Sent 2 updates to your partner!',
  'Sent 1 update to your partner!',
  'All memories up to date!',
  'Your partner is up to date!',
  'Your partner reported a sync problem.',
  '${partnerSyncProblemPrefix}Could not send records',
  'Could not start a sync right now. Check the connection and try again.',
  'Could not start syncing. Try again.',
  clockSkewWarning,
  SyncClock.rolledBackMessage,
  'Someone else tried to connect. We said no.',
  'Someone else tried to connect while you were pairing. We said no.',
  'A few unknown phones are trying to connect, so pairing is paused for a minute. This does not affect your partner.',
  'A phone is retrying too fast, so we asked it to wait a moment.',
  'Someone else tried to pair and did not finish. We disconnected them.',
  'Something came through that we could not use, so we skipped it.',
  'Something was too big to send. We will try it again next time.',
  'Something came through that we could not read, so we skipped it.',
  'That was cancelled.',
  'Something came through that we could not read. Try again.',
  'Could not compare notes with your partner. Try again.',
  'Could not ask your partner for updates. Try again.',
  'That was more than we can send at once. Try again.',
  '3 item(s) are too large to send to your partner and were skipped. Re-add the photo at a smaller size to sync it.',
  '1 item(s) are too large to send to your partner and were skipped. Re-add the photo at a smaller size to sync it.',
  "Some items on your partner's device are too large to transfer and were skipped.",
  'Could not send your memories right now. We will try again next time.',
  'Things arrived out of order, so we stopped. Try again.',
  '2 item(s) from your partner could not be read and were skipped.',
  "Your partner's phone could not verify 2 of your changes and did not apply them. Make sure both phones are on the same version of Our Space, then unlock this vault again and sync.",
  "Your partner's phone could not verify 1 of your change and did not apply it. Make sure both phones are on the same version of Our Space, then unlock this vault again and sync.",
  'That one is too big to send. Try adding the photo again a bit smaller.',
  'Could not send that just now. It will go through next time you connect.',
  'One update could not be read, so we skipped it.',
  'We could not read their details. Try again.',
  'Nothing to update from their side.',
  'We skipped a settings change from your partner — the date did not look right.',
  'We could not save the settings your partner just sent. Yours are unchanged.',
  'Could not reach your partner right now.',
  'Cannot find their phone. Ask them to open Our Space and leave it on screen.',
  'Trouble with the connection. Check your internet and try again.',
  'Unlock Our Space first 💕',
  'Could not send that just now 💕',
  'Love burst sent to Alex! 💕',
  'Saved 💕 Alex will see it the moment you two connect.',
  '3 new things from Alex 💕',
];

const Map<String, String> engineErrors = {
  'ice_failed': iceFailureMessage,
  'ice_failed ': openTimeoutMessage,
  'version_mismatch': 'Their Our Space is out of date. Update it on both phones so you can sync.',
  'oversized_message': 'Something went wrong while pairing. Try again.',
  'bad_challenge': 'Something went wrong while pairing. Try again.',
  'challenge_replay': 'Pairing did not go through. Try again.',
  'challenge_failed': 'Could not start the connection. Try again.',
  'auth_timeout':
      'Authentication timed out after 20 seconds. Your partner never completed the secure handshake.',
  'passphrase_mismatch': 'Your passphrases do not match. Check you both typed exactly the same one.',
  'corrupt_stream': 'Too much came through that we could not read, so we closed the connection. Tap to reconnect.',
  'data_channel_error': 'The connection dropped.',
  'storage_full': 'This phone is out of space, so new memories could not be saved. Free some space and try again.',
  'peer_unresponsive': 'Lost them - their phone stopped responding. Tap to reconnect.',
  'sync_timeout': 'That took too long, so we stopped. Nothing was lost - try again.',
  'bad_peer_id': '“love-x” is not a usable pairing code. Ask your partner to re-share their code or invite link.',
  'dial_failed': 'We could not reach love-abcdefgh. Check they have Our Space open, then try again.',
  'peer-unavailable': 'Cannot find their phone. Ask them to open Our Space and leave it on screen.',
  'network': 'Trouble with the connection. Check your internet and try again.',
  'peer_error': 'Could not reach your partner right now.',
  'server-error': 'Something odd happened with the relay server.',
  'mystery': '',
};

void main() {
  test('every engine notice comes out warm, calm and free of technical words', () {
    final notices = [
      ...engineNotices,
      unverifiableWarningText(1),
      unverifiableWarningText(4),
      describeBursts(1, true, 'Alex'),
      describeBursts(3, false, 'Alex'),
    ];
    for (final partner in ['Alex', '', NoticeCopy.partnerFallback]) {
      for (final text in notices) {
        final warm = NoticeCopy.warm(text, partner: partner);
        expect(warm, isNotEmpty, reason: text);
        expect(banned.hasMatch(warm), isFalse, reason: '$text -> $warm');
        expect(skyCalmText(warm), warm, reason: text);
        expect(warm.contains('(s)'), isFalse, reason: text);
      }
    }
  });

  test('every engine error comes out warm and keeps its meaning', () {
    for (final entry in engineErrors.entries) {
      final warm = NoticeCopy.warmError(code: entry.key.trim(), text: entry.value, partner: 'Alex');
      expect(warm, isNotEmpty, reason: entry.key);
      expect(banned.hasMatch(warm), isFalse, reason: '${entry.key} -> $warm');
      expect(skyCalmText(warm), warm, reason: entry.key);
      expect(warm.contains('love-'), isFalse, reason: entry.key);
    }
    expect(
      NoticeCopy.warmError(code: PeerLinkError.passphraseMismatch, text: '', partner: 'Alex'),
      'Your passphrases do not match. Check you both typed exactly the same one.',
    );
    expect(
      NoticeCopy.warmError(code: 'dial_failed', text: 'We could not reach love-abcdefgh.', partner: 'Alex'),
      'We could not reach Alex. Check Our Space is open on their phone, then try again.',
    );
    expect(
      NoticeCopy.warmError(code: 'mystery', text: 'Something odd with the relay', partner: ''),
      'We could not reach your partner just now. Nothing was lost.',
    );
    expect(
      NoticeCopy.warmError(code: 'peer_error', text: 'Could not reach your partner right now.', partner: 'Alex'),
      'Could not reach your partner right now.',
    );
  });

  test('counts and names read naturally', () {
    expect(NoticeCopy.warm('Synced 3 new item(s) from Alex 💕', partner: 'Alex'), '3 new things from Alex');
    expect(NoticeCopy.warm('Synced 1 update from your partner!', partner: 'Alex'), '1 new thing from Alex');
    expect(NoticeCopy.warm('Sent 1 update to your partner!', partner: 'Alex'), '1 new thing went to Alex');
    expect(NoticeCopy.warm('Your partner is up to date!', partner: 'alex'), 'Alex is all caught up.');
    expect(
      NoticeCopy.warm(clockSkewWarning, partner: 'Alex'),
      "Alex's phone clock looks far ahead of yours, so a few things were held back. Check the date and time on both phones.",
    );
    expect(
      NoticeCopy.warm('1 item(s) are too large to send to your partner and were skipped.', partner: 'Alex'),
      '1 thing was too big to send to Alex. Add the photo again a bit smaller.',
    );
    expect(NoticeCopy.warm('💕'), '');
    expect(NoticeCopy.warm('Love burst sent to Alex! 💕', partner: 'Alex'), 'Love burst sent to Alex!');
    expect(NoticeCopy.warm('Our new widget re-synced the mailbox'), NoticeCopy.fallbackNotice);
  });

  testWidgets('the app notices and the link warm engine words before anything shows them', (tester) async {
    final space = await openUnlockedSpace(tester);
    final notices = AppNotices(vault: space.vault, sync: space.sync);
    addTearDown(notices.dispose);
    final link = HubPeerLink(space.peer);
    addTearDown(link.dispose);
    final partner = space.identity.partnerName;

    space.mailbox.onWarning!('clock_skew', clockSkewWarning);
    await tester.pump();
    expect(notices.syncWarning, NoticeCopy.clockAhead(partner));

    space.store.clock.onWarning!('clock_rolled_back', SyncClock.rolledBackMessage);
    await tester.pump();
    expect(notices.syncWarning, NoticeCopy.clockBack);
    notices.clearSyncWarning();

    space.peer.connectToPartner('not a code!');
    expect(link.state.error?.text, NoticeCopy.badCode(partner));
    expect(link.state.error?.code, 'bad_peer_id');
  });
}
