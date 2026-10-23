import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/presentation/screens/lock/lock_screen.dart';

final RegExp technical = RegExp(
  r'\b(sync\w*|devices?|pair\w*|servers?|upload\w*|download\w*|data|peers?|relay\w*|mailbox\w*|encrypt\w*|keys?)\b',
  caseSensitive: false,
);
final RegExp emoji = RegExp(r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}]', unicode: true);

List<String> lockStrings() => [
  LockCopy.title,
  LockCopy.tagline,
  LockCopy.kicker(night: true, weekday: 'Friday'),
  LockCopy.kicker(night: false, weekday: 'Friday'),
  LockCopy.footer,
  LockCopy.checking,
  LockCopy.unreadableTitle,
  LockCopy.unreadableBody,
  LockCopy.tryAgain,
  LockCopy.quickButton,
  LockCopy.opening,
  LockCopy.usePassphrase,
  LockCopy.useTouch,
  LockCopy.unlockIntro,
  LockCopy.unlockHint,
  LockCopy.unlockButton,
  LockCopy.unlockTooShort(),
  LockCopy.moreWays,
  LockCopy.moreTitle,
  LockCopy.moreJoin,
  LockCopy.moreJoinHint,
  LockCopy.moreRestore,
  LockCopy.moreRestoreHint,
  LockCopy.moreStartOver,
  LockCopy.moreStartOverHint,
  LockCopy.inviteHere,
  LockCopy.inviteElsewhereLead + LockCopy.inviteElsewhereStrong + LockCopy.inviteElsewhereRest,
  LockCopy.segmentStart,
  LockCopy.segmentJoin,
  LockCopy.setupTitle,
  LockCopy.setupIntro,
  LockCopy.freshTitle,
  LockCopy.freshBody,
  LockCopy.freshAction,
  LockCopy.namesLabel,
  LockCopy.namesHint,
  LockCopy.startLabel,
  LockCopy.sharedPassphraseLabel,
  LockCopy.setupHint,
  LockCopy.setupHelp,
  LockCopy.setupTooShort(),
  LockCopy.createButton,
  LockCopy.replaceButton,
  LockCopy.creating,
  LockCopy.startOverDanger,
  LockCopy.goBack,
  LockCopy.joinTitle,
  LockCopy.joinIntro,
  LockCopy.joinInvited,
  LockCopy.inviteLabel,
  LockCopy.inviteHint,
  LockCopy.inviteHelp,
  LockCopy.inviteSameSpace,
  LockCopy.inviteFound,
  LockCopy.joinHint,
  LockCopy.joinHelp,
  LockCopy.joinButton,
  LockCopy.joining,
  LockCopy.joinDanger,
  LockCopy.pasteInvite,
  LockCopy.restoreTitle,
  LockCopy.restoreIntro,
  LockCopy.chooseFile,
  LockCopy.filePassphraseLabel + LockCopy.filePassphraseEmphasis,
  LockCopy.filePassphraseHint,
  LockCopy.openFile,
  LockCopy.fileOpenedLead + LockCopy.fileOpenedStrong + LockCopy.fileOpenedRest,
  LockCopy.restoreDanger,
  LockCopy.nothingToReplace,
  LockCopy.thenPassphraseLabel + LockCopy.thenPassphraseEmphasis,
  LockCopy.thenPassphraseHint,
  LockCopy.thenPassphraseHelp,
  LockCopy.restoreButton,
  LockCopy.restoring,
  LockCopy.cancel,
  LockCopy.restoreFallback,
  LockCopy.notOurFile,
  LockCopy.couldNotOpenFile,
  LockCopy.missingIdentity,
  LockCopy.fileTooBig(maxBackupFileBytes + 1),
  LockCopy.typeToConfirm(),
  ...LockCopy.restoreErrors.values,
  LockCopy.dangerLabel,
  'Starting.${LockCopy.dangerBodyMiddle}${LockCopy.dangerBodyStrong}${LockCopy.dangerBodyRest}',
  LockCopy.dangerStopLead + LockCopy.dangerStopStrong + LockCopy.dangerStopRest,
  LockCopy.saveFirstTitle,
  LockCopy.saveFirstBody,
  LockCopy.saveFirstHint,
  LockCopy.saveFirstButton,
  LockCopy.saving,
  LockCopy.typeLead + destroyConfirmationPhrase + LockCopy.typeRest,
  LockCopy.incorrectPassphrase,
  LockCopy.joinedUnverified,
  LockCopy.stoppedBeforeJoining,
  LockCopy.couldNotJoin,
  LockCopy.brokenInvite,
  LockCopy.passphraseTooShort(),
  LockDangerGate.savedText(),
];

List<String> engineMessages() => [
  VaultMessages.passphraseTooShort(),
  VaultMessages.couldNotOpen,
  VaultMessages.nothingHereYet,
  VaultMessages.incorrectPassphrase,
  VaultMessages.unreadableNothingChanged,
  VaultMessages.needsConfirmation,
  VaultMessages.couldNotSetUp,
  VaultMessages.malformedInvite,
  VaultMessages.unreadableStoppedPairing,
  VaultMessages.passphraseMismatch,
  VaultMessages.pairedUnverified,
  VaultMessages.couldNotPair,
  VaultMessages.pasteInvite,
  VaultMessages.typeToConfirm(),
  QuickUnlockCopy.needsSetupAgain,
  QuickUnlockCopy.needsSetupForNow,
  QuickUnlockCopy.cannot,
  QuickUnlockCopy.didNotWork,
  BackupMessages.rescueSaved,
  BackupMessages.rescueTooShort(),
  BackupMessages.couldNotSave,
  BackupMessages.locked,
];

void main() {
  test('every lock screen line is warm, plain English and free of emoji', () {
    final sampleNames = RegExp(r'(qalbi|farhu)', caseSensitive: false);
    for (final line in lockStrings()) {
      expect(line.trim(), isNotEmpty);
      expect(technical.hasMatch(line), isFalse, reason: line);
      expect(emoji.hasMatch(line), isFalse, reason: line);
      expect(sampleNames.hasMatch(line), isFalse, reason: line);
    }
  });

  test('messages from the engine are retold warmly before she sees them', () {
    expect(LockCopy.warm(VaultMessages.pairedUnverified), LockCopy.joinedUnverified);
    expect(LockCopy.warm(VaultMessages.incorrectPassphrase), LockCopy.incorrectPassphrase);
    expect(LockCopy.warm(VaultMessages.couldNotPair), LockCopy.couldNotJoin);
    expect(LockCopy.warm(VaultMessages.unreadableStoppedPairing), LockCopy.stoppedBeforeJoining);
    expect(LockCopy.warm(VaultMessages.malformedInvite), LockCopy.brokenInvite);
    expect(LockCopy.warm(VaultMessages.pasteInvite), LockCopy.pasteInvite);
    expect(LockCopy.warm(QuickUnlockCopy.didNotWork), QuickUnlockCopy.didNotWork);
    expect(LockCopy.warm('Saved 💕 your copy'), 'Saved. Your copy');
    for (final message in engineMessages()) {
      final told = LockCopy.warm(message);
      expect(told, isNotEmpty);
      expect(technical.hasMatch(told), isFalse, reason: told);
      expect(emoji.hasMatch(told), isFalse, reason: told);
    }
  });

  test('the lock sky keeps the drawing on the design phone', () {
    const metrics = LockMetrics(size: Size(390, 844), topInset: 47, bottomInset: 34);
    final heart = metrics.heart;
    expect(heart.center.dx, 195);
    expect(heart.center.dy, closeTo(322, 12));
    expect(heart.scale, LockMetrics.heartScale);
    expect(heart.dim, LockMetrics.heartDim);
    expect(heart.presence, isFalse);
    expect(heart.gap, isNotNull);
    expect(heart.gapGuide, isFalse);
    final scene = metrics.scene;
    expect(scene.moon, const Offset(312, 92));
    expect(scene.skyline, closeTo(844 - 58, 0.01));
    expect(scene.sunAt!.dy, closeTo(844 - 44, 0.01));
    expect(scene.heart, heart);
  });

  test('the heart always fits between her name and the touch ring', () {
    for (final size in const [Size(390, 844), Size(412, 915), Size(360, 740), Size(375, 667), Size(360, 640)]) {
      final metrics = LockMetrics(size: size, topInset: 24, bottomInset: 16);
      final heart = metrics.heart;
      final top = (heart.center.dy - 12 * heart.scale) * metrics.k;
      final bottom = (heart.center.dy + 17 * heart.scale) * metrics.k;
      expect(top, greaterThanOrEqualTo(metrics.brandHeight - 1), reason: '$size');
      expect(bottom, lessThanOrEqualTo(size.height - metrics.openBlock - LockMetrics.ringReach + 1), reason: '$size');
      expect(metrics.bodyMinHeight + metrics.brandHeight, closeTo(size.height, 0.01));
    }
  });

  test('the heart fades away behind the longer forms', () {
    const metrics = LockMetrics(size: Size(390, 844));
    expect(metrics.sceneWithHeart(0).heart, isNull);
    expect(metrics.sceneWithHeart(0.5).heart!.dim, closeTo(LockMetrics.heartDim / 2, 0.0001));
    expect(metrics.sceneWithHeart(1).heart!.dim, LockMetrics.heartDim);
  });

  test('the lock screen picks the same first mode as before', () {
    expect(defaultLockMode(VaultCheckState.present), LockMode.unlock);
    expect(defaultLockMode(VaultCheckState.checking), isNull);
    expect(defaultLockMode(VaultCheckState.unreadable), isNull);
    expect(defaultLockMode(VaultCheckState.absent), LockMode.setup);
    expect(defaultLockMode(VaultCheckState.absent, inviteHasSalt: true), LockMode.join);
    expect(defaultLockMode(VaultCheckState.absent, installed: true), LockMode.join);
  });
}
