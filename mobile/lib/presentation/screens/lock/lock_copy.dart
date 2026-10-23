import '../../../core/engine.dart';
import '../../sky/sky.dart';

abstract final class LockCopy {
  static const String title = 'Our Space';
  static const String tagline = 'Our little sky.\nOnly the two of you can open it.';
  static String kicker({required bool night, required String weekday}) =>
      night ? 'Tonight · $weekday' : 'Today · $weekday';

  static const String footerLead = 'Locked';
  static const String footerRest = ' with your passphrase';
  static const String footer = '$footerLead$footerRest';

  static const String checking = 'Finding your space…';
  static const String unreadableTitle = 'Something went wrong opening your space';
  static const String unreadableBody = 'Nothing was lost. Give it another try.';
  static const String tryAgain = 'Try again';

  static const String quickButton = 'Open with a touch';
  static const String opening = 'Opening…';
  static const String usePassphrase = 'Use the passphrase instead';
  static const String useTouch = 'Open with a touch instead';

  static const String unlockIntro = 'Type the passphrase you two share to open your memories and notes.';
  static const String unlockHint = 'Your passphrase';
  static const String unlockButton = 'Open Our Space';
  static String unlockTooShort() =>
      'Your passphrase has at least $minPassphraseLength characters. Check it and try again.';

  static const String moreWays = 'More ways in';
  static const String moreTitle = 'How would you like to come in?';
  static const String moreJoin = 'Join your partner’s space';
  static const String moreJoinHint = 'With the invite link they sent you';
  static const String moreRestore = 'Bring back a copy you saved';
  static const String moreRestoreHint = 'Open everything again from a file you kept';
  static const String moreStartOver = 'Start over with a new space';
  static const String moreStartOverHint = 'This erases what is on this phone';

  static const String inviteHere =
      'Your partner’s invite is here. Open Our Space, and we will offer to bring your two phones together.';
  static const String inviteElsewhereLead = 'That invite is for a ';
  static const String inviteElsewhereStrong = 'different space';
  static const String inviteElsewhereRest =
      ', not this one. Opening yours here is safe, the link is simply set aside. Joining it would replace everything on this phone.';

  static const String segmentStart = 'Start a new space';
  static const String segmentJoin = 'Join my partner';

  static const String setupTitle = 'Start your space';
  static const String setupIntro =
      'Choose a passphrase only the two of you know. It is the only thing that opens your space.';
  static const String freshTitle = 'This makes a brand-new, empty space.';
  static const String freshBody =
      'If your partner already started one, please do not make a second. Join theirs with their invite link, '
      'and you will both see the same things.';
  static const String freshAction = 'Join your partner’s space instead';
  static const String namesLabel = 'What should we call you two?';
  static const String namesHint = 'e.g. Qalbi & Farhu';
  static const String startLabel = 'When did your story begin?';
  static const String sharedPassphraseLabel = 'Your shared passphrase';
  static const String setupHint = 'Make up a shared passphrase';
  static const String setupHelp =
      'At least $minPassphraseLength characters. A little sentence only you two would know works best. '
      'It is never saved anywhere, so if you both forget it, everything here is gone.';
  static String setupTooShort() =>
      'Please choose a passphrase of at least $minPassphraseLength characters, something you will both remember.';
  static const String createButton = 'Start our space';
  static const String replaceButton = 'Erase and start fresh';
  static const String creating = 'Setting things up…';
  static const String startOverDanger = 'Starting a new space gives this phone a brand new lock.';
  static const String goBack = 'Never mind, go back';

  static const String joinTitle = 'Join your partner’s space';
  static const String joinIntro = 'Use your partner’s invite link to join their space.';
  static const String joinInvited = 'Your partner invited you!';
  static const String inviteLabel = 'Your partner’s invite link';
  static const String inviteHint = 'Paste the link they sent you';
  static const String inviteHelp =
      'Ask your partner to tap Add another phone in their Settings and send you their link, then paste it here.';
  static const String inviteSameSpace =
      'This invite is for the space you already have here. Joining again is safe, nothing gets erased.';
  static const String inviteFound = 'Found your partner’s invite! Type the passphrase you both chose.';
  static const String joinHint = 'The one you both chose';
  static const String joinHelp = 'It has to match theirs exactly, letter for letter.';
  static const String joinButton = 'Join and open Our Space';
  static const String joining = 'Joining…';
  static const String joinDanger = 'Joining this invite moves this phone over to your partner’s space.';
  static const String pasteInvite =
      'Please paste your partner’s invite link, the one they sent you, or the code you scanned.';

  static const String restoreTitle = 'Bring back a saved copy';
  static const String restoreIntro =
      'Rebuilds your space on this phone from a file you saved earlier, so everything inside opens again.';
  static const String chooseFile = 'Choose the file you saved';
  static const String filePassphraseLabel = 'Passphrase that opens this ';
  static const String filePassphraseEmphasis = 'file';
  static const String filePassphraseHint = 'Passphrase for this file';
  static const String openFile = 'Open this file';
  static const String fileOpenedLead = 'File opened! Now the passphrase you used ';
  static const String fileOpenedStrong = 'back then';
  static const String fileOpenedRest = ' will bring everything inside back.';
  static const String restoreDanger = 'Bringing this file back moves this phone over to the space inside it.';
  static const String nothingToReplace =
      'There is nothing here to replace. Anything left over from an older space on this phone is tidied away '
      'first, it cannot be opened any more anyway.';
  static const String thenPassphraseLabel = 'The passphrase you used ';
  static const String thenPassphraseEmphasis = 'back then';
  static const String thenPassphraseHint = 'The passphrase you opened Our Space with back then';
  static const String thenPassphraseHelp =
      'Usually the same as the file passphrase, so we have filled it in. We check it before anything changes, '
      'so a wrong guess costs you nothing.';
  static const String restoreButton = 'Bring everything back';
  static const String restoring = 'Bringing it back…';
  static const String cancel = 'Never mind';
  static const String restoreFallback = 'That did not finish. Please try again.';
  static const String notOurFile = 'That does not look like a file Our Space saved.';
  static const String couldNotOpenFile = 'We could not open that file. Check the passphrase and try again.';
  static const String missingIdentity =
      'That file opened, but it is missing the part we need to rebuild your space here. It was probably saved by '
      'an older version. You can still bring its things in from Settings once you are in.';
  static String fileTooBig(int bytes) =>
      'That file is ${(bytes / (1024 * 1024)).round()}MB, over the ${(maxBackupFileBytes / (1024 * 1024)).round()}MB limit.';
  static String typeToConfirm() => 'Type $destroyConfirmationPhrase to confirm.';

  static const Map<String, String> restoreErrors = {
    'no_identity': 'This file is missing the part we need to rebuild your space here.',
    'bad_salt': 'This file looks damaged, so we left everything as it is.',
    'passphrase_too_short': 'The passphrase needs at least $minPassphraseLength characters.',
    'passphrase_mismatch':
        'That is not the passphrase this file was saved with. Nothing changed. It is the one you '
        'used to open Our Space back when you saved it, not always the same one that opened the file.',
    'unreadable':
        'We could not read what is already on this phone, so we stopped instead of risking it. '
        'Please try again.',
    'same_vault':
        'This file is from this very phone, so there is nothing to swap. Just open Our Space as usual, '
        'then use Bring in a copy in Settings to add its things back.',
    'needs_confirmation': 'Type the words above to replace what is on this phone.',
    'write_failed': 'That stopped partway. Nothing more was changed.',
  };

  static const String dangerLabel = 'This erases everything on this phone';
  static const String dangerBodyMiddle = ' Every photo, letter, milestone and wish saved here ';
  static const String dangerBodyStrong = 'can never be opened again';
  static const String dangerBodyRest =
      ', and all of it is erased from this phone. There is no undo, not by us, not by anyone.';
  static const String dangerStopLead = 'If you have only forgotten the passphrase, ';
  static const String dangerStopStrong = 'please stop here';
  static const String dangerStopRest =
      '. Nothing on this screen can bring it back, and your partner’s phone may still have everything.';
  static const String saveFirstTitle = 'Save a copy first';
  static const String saveFirstBody =
      'This saves everything on this phone into one file. To open it later you will need the passphrase you type '
      'below, at least $minPassphraseLength characters, and the one you open Our Space with today.';
  static const String saveFirstHint = 'A passphrase for this copy';
  static const String saveFirstButton = 'Save a copy';
  static const String saving = 'Saving…';
  static const String typeLead = 'Type ';
  static const String typeRest = ' to continue';

  static const String incorrectPassphrase = 'That passphrase is not quite right. Check it and try again.';
  static const String joinedUnverified =
      'You are in! The moment your phones find each other we will check that your passphrases match, and if they '
      'do not, we will tell you instead of sharing anything.';
  static const String stoppedBeforeJoining =
      'We could not read what is on this phone, so we stopped before joining your partner.';
  static const String couldNotJoin = 'We could not join your partner’s space. Please try again.';
  static const String brokenInvite = 'That invite link looks broken. Ask your partner for a fresh one.';
  static String passphraseTooShort() => 'Your passphrase needs at least $minPassphraseLength characters.';

  static String warm(String message) {
    if (message == VaultMessages.incorrectPassphrase) return incorrectPassphrase;
    if (message == VaultMessages.pairedUnverified) return joinedUnverified;
    if (message == VaultMessages.unreadableStoppedPairing) return stoppedBeforeJoining;
    if (message == VaultMessages.couldNotPair) return couldNotJoin;
    if (message == VaultMessages.malformedInvite) return brokenInvite;
    if (message == VaultMessages.pasteInvite) return pasteInvite;
    if (message == VaultMessages.passphraseTooShort()) return passphraseTooShort();
    return skyCalmText(message);
  }
}
