import '../../sky/sky.dart';

abstract final class NoticeCopy {
  static final RegExp technical = RegExp(
    r'\b(sync\w*|devices?|pair\w*|servers?|upload\w*|download\w*|data|peers?|relay\w*|mailbox\w*|encrypt\w*|keys?|cgnat|ice|webrtc|handshake|authentication|vault)\b',
    caseSensitive: false,
  );

  static const String partnerFallback = 'your partner';

  static String fallbackError(String partner) => 'We could not reach ${_who(partner)} just now. Nothing was lost.';

  static const String fallbackNotice = 'Something did not come through just now. Nothing was lost.';

  static const String passphraseMismatch = 'Your passphrases do not match. Check you both typed exactly the same one.';

  static const String noWay =
      'We could not find a way between your two phones from here. Try again on Wi-Fi, or move one phone to a different network.';

  static const String newest = 'One of you needs the newest Our Space. Update it on both phones, then try again.';

  static const String tooLong = 'That took too long, so we stopped. Nothing was lost, try again.';

  static const String outOfSpace =
      'This phone is out of space, so new memories could not be saved. Free some space and try again.';

  static const String connection = 'Trouble with the connection. Check your internet and try again.';

  static const String clockBack = "This phone's date looks like it was changed. We have set things back to the current time.";

  static const String strangerRefused = 'Someone else tried to reach this phone. We said no.';

  static const String strangerLeft = 'Someone else tried to join and did not finish, so we sent them away.';

  static String stoppedAnswering(String partner) =>
      "${_phoneOf(partner)} stopped answering. Nothing was lost, try reaching them again.";

  static String notSure(String partner) => 'We could not make sure it was really ${_who(partner)}, so we stopped. Try again.';

  static String wentWrong(String partner) => 'Something went wrong on the way to ${_who(partner)}. Try again.';

  static String dropped(String partner) => 'The line to ${_who(partner)} dropped. Nothing was lost, try again.';

  static String badCode(String partner) =>
      'That code does not look right. Ask ${_who(partner)} to share their link or code again.';

  static String cannotReach(String partner) =>
      'We could not reach ${_who(partner)}. Check Our Space is open on their phone, then try again.';

  static String newThings(int count, String partner) =>
      '$count new thing${count == 1 ? '' : 's'} from ${_who(partner)}';

  static String sentThings(String count, bool one, String partner) =>
      '$count new thing${one ? '' : 's'} went to ${_who(partner)}';

  static String caughtUp(String partner) => '${_cap(_who(partner))} is all caught up.';

  static String theirSide(String partner) =>
      "Something did not come through on ${_whose(partner)} side. Nothing was lost, try again.";

  static String catchUpFailed(String partner) => 'We could not catch up with ${_who(partner)} just now. Try again in a moment.';

  static String clockAhead(String partner) =>
      "${_phoneOf(partner)} clock looks far ahead of yours, so a few things were held back. Check the date and time on both phones.";

  static String strangersPaused(String partner) =>
      'A few unknown phones are trying to reach this one, so we are not letting new ones in for a minute. ${_cap(_who(partner))} is not affected.';

  static String tooBigToSend(String count, bool one, String partner) =>
      '$count thing${one ? ' was' : 's were'} too big to send to ${_who(partner)}. Add the photo again a bit smaller.';

  static String tooBigThere(String partner) =>
      "A few things on ${_phoneOf(partner, lower: true)} were too big to send, so they were skipped.";

  static String notReached(String count, bool one, String partner) =>
      '$count of your change${one ? '' : 's'} did not reach ${_who(partner)}. Make sure Our Space is up to date on both phones, then open it again.';

  static String unreadable(String count, bool one, String partner) =>
      '$count thing${one ? '' : 's'} from ${_who(partner)} could not be read, so we skipped ${one ? 'it' : 'them'}.';

  static final RegExp _receivedItems = RegExp(r'^Synced (\d+) new item\(s\) from ');
  static final RegExp _receivedUpdates = RegExp(r'^Synced (\d+) updates? from your partner');
  static final RegExp _sentUpdates = RegExp(r'^Sent ([\d,]+) update(s?) to your partner');
  static final RegExp _tooBig = RegExp(r'^([\d,]+) item\(s\) are too large to send to your partner');
  static final RegExp _unverified = RegExp(r"^Your partner's phone could not verify ([\d,]+) of your change(s?)\b");
  static final RegExp _rejected = RegExp(r'^([\d,]+) item\(s\) from your partner could not be read');

  static String warm(String text, {String partner = partnerFallback}) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return '';
    final received = _receivedItems.firstMatch(trimmed) ?? _receivedUpdates.firstMatch(trimmed);
    if (received != null) return newThings(int.tryParse(received.group(1)!) ?? 1, partner);
    final sent = _sentUpdates.firstMatch(trimmed);
    if (sent != null) return sentThings(sent.group(1)!, sent.group(2)!.isEmpty, partner);
    if (trimmed.startsWith('Your partner is up to date')) return caughtUp(partner);
    if (trimmed.startsWith('Your partner reported a sync problem')) return theirSide(partner);
    if (trimmed.startsWith('Could not start a sync') || trimmed.startsWith('Could not start syncing')) {
      return catchUpFailed(partner);
    }
    if (trimmed.contains('clock looks far ahead')) return clockAhead(partner);
    if (trimmed.contains('date looks like it was changed')) return clockBack;
    if (trimmed.startsWith('Someone else tried to connect')) return strangerRefused;
    if (trimmed.startsWith('Someone else tried to pair')) return strangerLeft;
    if (trimmed.startsWith('A few unknown phones are trying to connect')) return strangersPaused(partner);
    final tooBig = _tooBig.firstMatch(trimmed);
    if (tooBig != null) return tooBigToSend(tooBig.group(1)!, tooBig.group(1) == '1', partner);
    if (trimmed.startsWith("Some items on your partner's device are too large")) return tooBigThere(partner);
    final unverified = _unverified.firstMatch(trimmed);
    if (unverified != null) return notReached(unverified.group(1)!, unverified.group(2)!.isEmpty, partner);
    final rejected = _rejected.firstMatch(trimmed);
    if (rejected != null) return unreadable(rejected.group(1)!, rejected.group(1) == '1', partner);
    final calm = skyCalmText(trimmed);
    if (calm.isEmpty) return '';
    return technical.hasMatch(calm) ? fallbackNotice : calm;
  }

  static String warmError({required String code, required String text, String partner = partnerFallback}) {
    switch (code) {
      case 'passphrase_mismatch':
        return passphraseMismatch;
      case 'ice_failed':
        return noWay;
      case 'version_mismatch':
        return newest;
      case 'sync_timeout':
        return tooLong;
      case 'storage_full':
        return outOfSpace;
      case 'peer_unresponsive':
        return stoppedAnswering(partner);
      case 'auth_timeout':
      case 'auth_failed':
      case 'bad_challenge':
      case 'challenge_replay':
      case 'challenge_failed':
        return notSure(partner);
      case 'oversized_message':
        return wentWrong(partner);
      case 'data_channel_error':
      case 'corrupt_stream':
        return dropped(partner);
      case 'bad_peer_id':
        return badCode(partner);
      case 'dial_failed':
      case 'peer-unavailable':
        return cannotReach(partner);
      case 'network':
        return connection;
    }
    final calm = skyCalmText(text.trim());
    if (calm.isEmpty || technical.hasMatch(calm)) return fallbackError(partner);
    return calm;
  }

  static String _who(String partner) {
    final name = partner.trim();
    return name.isEmpty ? partnerFallback : name;
  }

  static String _cap(String text) => text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

  static String _whose(String partner) => "${_who(partner)}'s";

  static String _phoneOf(String partner, {bool lower = false}) {
    final whose = "${_whose(partner)} phone";
    return lower ? whose : _cap(whose);
  }
}
