import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/core/engine/crypto/backup.dart' show createEncryptedBackup;
import 'package:our_space_mobile/core/engine/crypto/js_compat.dart' show jsonStringify;
import 'package:our_space_mobile/presentation/files/vault_files.dart';
import 'package:our_space_mobile/presentation/screens/lock/lock_screen.dart';
import 'package:our_space_mobile/presentation/sky/sky.dart';

import 'lock_harness.dart';

PickedVaultFile pickedText(String name, String text) {
  final bytes = Uint8List.fromList(utf8.encode(text));
  return PickedVaultFile(name: name, size: bytes.length, bytes: bytes);
}

Future<OurSpace> spaceWithMemories(WidgetTester tester, {String passphrase = lockPassphrase}) async {
  final space = await lockReal(tester, openLockSpace);
  await lockReal(tester, () async {
    await space.vault.create(passphrase: passphrase, coupleNames: 'Qalbi & Farhu', iterations: lockIterations);
    await space.milestones.add(title: 'First call', date: '2025-09-25');
  });
  return space;
}

Future<void> chooseFile(WidgetTester tester, PickedVaultFile file) async {
  VaultFiles.picker = () async => file;
  await lockPress(tester, find.byType(LockFileTile));
  await tester.pump();
}

HeartConstellation? skyOfHeart(WidgetTester tester) => tester.widget<SkyCanvas>(find.byType(SkyCanvas)).scene.heart;

String fieldText(WidgetTester tester, String hint) => tester.widget<TextField>(lockField(hint)).controller!.text;

void main() {
  final systemPicker = VaultFiles.picker;

  tearDown(() => VaultFiles.picker = systemPicker);

  testWidgets('a saved copy is checked step by step before anything changes', (tester) async {
    calmLock(tester);
    const other = 'a different passphrase entirely';
    final source = await spaceWithMemories(tester);
    final file = await lockReal(tester, () => source.backup.exportRescueBackup(lockPassphrase));
    final empty = await lockReal(
      tester,
      () => createEncryptedBackup(
        {
          'version': 2,
          'tables': {'vault_meta': <Object?>[]},
        },
        lockPassphrase,
        iterations: lockIterations,
      ),
    );

    final phone = await lockReal(tester, openLockSpace);
    await pumpLock(tester, phone);
    await lockUntilFound(tester, find.text(LockCopy.setupTitle));
    await lockPress(tester, find.text(LockCopy.moreRestore));
    expect(find.text(LockCopy.restoreTitle), findsOneWidget);
    expect(find.text(LockCopy.restoreIntro), findsOneWidget);
    expect(skyOfHeart(tester), isNull);

    await chooseFile(tester, const PickedVaultFile(name: 'huge.vault', size: maxBackupFileBytes + 1, bytes: null));
    expect(find.text(LockCopy.fileTooBig(maxBackupFileBytes + 1)), findsOneWidget);
    expect(find.text(LockCopy.chooseFile), findsOneWidget);

    await chooseFile(tester, PickedVaultFile(name: 'odd.bin', size: 3, bytes: Uint8List.fromList([0xff, 0xfe, 0xfd])));
    expect(find.text(LockCopy.notOurFile), findsOneWidget);

    await chooseFile(tester, pickedText('notes.txt', 'just a shopping list'));
    expect(find.text(LockCopy.notOurFile), findsOneWidget);
    expect(lockField(LockCopy.filePassphraseHint), findsNothing);

    await chooseFile(tester, pickedText('old.vault', jsonStringify(empty)));
    expect(find.text('old.vault'), findsOneWidget);
    expect(find.text(LockCopy.notOurFile), findsNothing);
    expect(lockButtonEnabled(tester, LockCopy.openFile), isFalse);
    await lockType(tester, lockField(LockCopy.filePassphraseHint), lockPassphrase);
    await lockPress(tester, find.text(LockCopy.openFile));
    await lockUntilFound(tester, find.text(LockCopy.missingIdentity));
    expect(find.text(LockCopy.restoreButton), findsNothing);

    await chooseFile(tester, pickedText(file.fileName, file.contents));
    expect(find.text(file.fileName), findsOneWidget);
    expect(find.text(LockCopy.missingIdentity), findsNothing);
    await lockType(tester, lockField(LockCopy.filePassphraseHint), other);
    await lockPress(tester, find.text(LockCopy.openFile));
    await lockUntilFound(tester, find.text(LockCopy.couldNotOpenFile));

    await lockType(tester, lockField(LockCopy.filePassphraseHint), lockPassphrase);
    expect(find.text(LockCopy.couldNotOpenFile), findsNothing);
    await lockPress(tester, find.text(LockCopy.openFile));
    await lockUntilFound(tester, find.text(LockCopy.restoreButton));
    expect(find.textContaining(LockCopy.fileOpenedLead, findRichText: true), findsOneWidget);
    expect(find.text(LockCopy.nothingToReplace), findsOneWidget);
    expect(find.text(LockCopy.dangerLabel.toUpperCase()), findsNothing);
    expect(fieldText(tester, LockCopy.thenPassphraseHint), lockPassphrase);

    await lockType(tester, lockField(LockCopy.thenPassphraseHint), other);
    await lockPress(tester, find.text(LockCopy.restoreButton));
    await lockUntilFound(tester, find.text(LockCopy.restoreErrors['passphrase_mismatch']!));
    expect(phone.vault.isUnlocked, isFalse);

    await lockType(tester, lockField(LockCopy.thenPassphraseHint), lockPassphrase);
    expect(find.text(LockCopy.restoreErrors['passphrase_mismatch']!), findsNothing);
    await lockPress(tester, find.text(LockCopy.restoreButton));
    await lockUntil(tester, () => phone.vault.isUnlocked);
    expect(phone.vault.salt, source.vault.salt);
    final restored = await lockReal(tester, () => phone.milestones.list());
    expect(restored.map((m) => m.title), ['First call']);
    await closeLock(tester, phone);
    await lockReal(tester, source.close);
  });

  testWidgets('bringing a different space over this one needs the typed words first', (tester) async {
    calmLock(tester);
    final source = await spaceWithMemories(tester);
    final file = await lockReal(tester, () => source.backup.exportRescueBackup(lockPassphrase));
    final phone = await spaceWithMemories(tester, passphrase: 'our own passphrase on this phone');
    phone.vault.lock();
    final oldSalt = phone.vault.salt;

    await pumpLock(tester, phone);
    await lockUntilFound(tester, find.text(LockCopy.unlockIntro));
    await lockPress(tester, find.text(LockCopy.moreWays));
    await lockSettle(tester);
    await lockPress(tester, find.text(LockCopy.moreRestore));
    await lockSettle(tester);

    await chooseFile(tester, pickedText(file.fileName, file.contents));
    await lockType(tester, lockField(LockCopy.filePassphraseHint), lockPassphrase);
    await lockPress(tester, find.text(LockCopy.openFile));
    await lockUntilFound(tester, find.text(LockCopy.restoreButton));
    expect(find.text(LockCopy.dangerLabel.toUpperCase()), findsOneWidget);
    expect(find.text(LockCopy.nothingToReplace), findsNothing);
    expect(lockButtonEnabled(tester, LockCopy.restoreButton), isFalse);
    expect(lockButton(tester, LockCopy.restoreButton).variant, SkyButtonVariant.danger);

    await lockType(tester, lockField(destroyConfirmationPhrase), 'erase our');
    expect(lockButtonEnabled(tester, LockCopy.restoreButton), isFalse);
    await lockType(tester, lockField(destroyConfirmationPhrase), 'erase our memories');
    expect(lockButtonEnabled(tester, LockCopy.restoreButton), isTrue);
    expect(phone.vault.salt, oldSalt);

    await lockPress(tester, find.text(LockCopy.restoreButton));
    await lockUntil(tester, () => phone.vault.isUnlocked);
    expect(phone.vault.salt, source.vault.salt);
    await closeLock(tester, phone);
    await lockReal(tester, source.close);
  });

  testWidgets('a copy from this very phone says there is nothing to swap', (tester) async {
    calmLock(tester);
    final phone = await spaceWithMemories(tester);
    final file = await lockReal(tester, () => phone.backup.exportRescueBackup(lockPassphrase));
    phone.vault.lock();

    await pumpLock(tester, phone);
    await lockUntilFound(tester, find.text(LockCopy.unlockIntro));
    await lockPress(tester, find.text(LockCopy.moreWays));
    await lockSettle(tester);
    await lockPress(tester, find.text(LockCopy.moreRestore));
    await lockSettle(tester);
    await chooseFile(tester, pickedText(file.fileName, file.contents));
    await lockType(tester, lockField(LockCopy.filePassphraseHint), lockPassphrase);
    await lockPress(tester, find.text(LockCopy.openFile));
    await lockUntilFound(tester, find.text(LockCopy.restoreButton));
    expect(find.text(LockCopy.dangerLabel.toUpperCase()), findsNothing);

    await lockPress(tester, find.text(LockCopy.restoreButton));
    await lockUntilFound(tester, find.text(LockCopy.restoreErrors['same_vault']!));
    expect(phone.vault.isUnlocked, isFalse);

    await lockPress(tester, find.text(LockCopy.cancel));
    expect(find.text(LockCopy.unlockIntro), findsOneWidget);
    expect(find.text(LockCopy.restoreErrors['same_vault']!), findsNothing);
    await closeLock(tester, phone);
  });
}
