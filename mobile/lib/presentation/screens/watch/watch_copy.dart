abstract final class WatchCopy {
  static const String kicker = 'Just the two of us';
  static const String title = 'Watch together';
  static const String entryHint = 'Same video, same second';
  static const String linkLabel = 'A link to a video';
  static const String linkHint = 'https://';
  static const String linkHelp = 'Paste a direct link to the video itself, starting with https://';
  static const String linkInvalid = "That doesn't look like a video link. It needs to start with https://";
  static const String linkBroken = 'Something in that link looks broken. Try copying it again.';
  static const String paste = 'Paste a link';
  static const String pasteEmpty = 'There is no link to paste yet';
  static const String start = 'Start watching';
  static const String play = 'Play';
  static const String pause = 'Pause';
  static const String back = 'Back to us';
  static const String wontPlay = "This link won't play here. Go back and try another one.";
  static const String seekLabel = 'Move to another part of the video';
  static const String live = 'Live';
  static const String audio = 'Audio';
  static const String subtitles = 'Subtitles';
  static const String subtitlesOff = 'Off';
  static const String joinLabel = 'Join';
  static const String notNow = 'Not now';

  static String track(int number) => 'Track $number';

  static String invited(String partner) => '$partner wants to watch something with you';

  static String stillWatching(String partner) => '$partner is still watching';

  static String withPartner(String partner) => 'Watching with $partner';

  static String waitingFor(String partner) => 'Waiting for $partner to join you';

  static String catchingUp(String partner) => "Waiting for $partner's video to catch up";

  static String partnerCantPlay(String partner) => "This link won't play on $partner's phone";

  static const String loading = 'Getting your video ready';

  static const String catchingUpMine = 'Your video is catching up';

  static String clock(int ms) {
    final total = (ms / 1000).floor().clamp(0, 1 << 31);
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    final seconds = (total % 60).toString().padLeft(2, '0');
    if (hours > 0) return '$hours:${minutes.toString().padLeft(2, '0')}:$seconds';
    return '$minutes:$seconds';
  }
}
