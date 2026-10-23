import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/presentation/files/vault_files.dart';
import 'package:our_space_mobile/presentation/screens/settings/settings_page.dart';
import 'package:our_space_mobile/presentation/screens/settings/widgets/settings_field.dart';
import 'package:our_space_mobile/presentation/screens/sync/backup_dialogs.dart';
import 'package:our_space_mobile/presentation/screens/sync/keep_a_copy.dart';
import 'package:our_space_mobile/presentation/sky/sky.dart';
import 'package:our_space_mobile/presentation/widgets/app_haptics.dart';

import '../../widgets/harness.dart' show recordHaptics, recordedHaptics;
import 'hub_harness.dart';

void main() {
  final systemPicker = VaultFiles.picker;
  final systemSaver = VaultFiles.saver;

  setUp(recordHaptics);

  tearDown(() {
    VaultFiles.picker = systemPicker;
    VaultFiles.saver = systemSaver;
  });

  testWidgets('saves a copy only with the passphrase that opens the space', (tester) async {
    calm(tester);
    final space = await openUnlockedSpace(tester);
    await real(tester, () => space.milestones.add(title: 'First date', date: '2021-06-14'));
    final saved = <BackupFile>[];
    var accept = false;
    VaultFiles.saver = (file) async {
      saved.add(file);
      return accept;
    };
    await openSettingsPage(tester, space);
    expect(find.text(BackupCopy.saveHint), findsOneWidget);
    expect(find.text(BackupCopy.bringInHint), findsOneWidget);

    await tapRow(tester, SettingsPage.saveCopyKey);
    expect(find.text(BackupCopy.exportTitle), findsOneWidget);
    expect(find.text(BackupCopy.exportDescription), findsOneWidget);
    final field = fieldWithHint(BackupCopy.passphraseHint);
    final again = fieldWithHint(BackupCopy.confirmHint);

    await type(tester, field, 'short');
    expect(find.text(BackupCopy.tooShort()), findsOneWidget);
    await type(tester, field, 'a different passphrase entirely');
    expect(find.text(BackupCopy.tooShort()), findsNothing);
    await type(tester, again, 'a different passphrase');
    expect(find.text(BackupCopy.mismatch), findsOneWidget);
    await press(tester, find.text(BackupCopy.exportSubmit));
    expect(saved, isEmpty);

    await type(tester, again, 'a different passphrase entirely');
    await press(tester, find.text(BackupCopy.exportSubmit));
    await untilFound(tester, find.text(BackupMessages.wrongPassphrase));
    expect(saved, isEmpty);

    expect(tester.widget<SettingsField>(probe(field)).obscured, isTrue);
    await press(tester, semanticsLabelled(BackupCopy.showPassphrase));
    expect(semanticsLabelled(BackupCopy.hidePassphrase), findsOneWidget);
    expect(tester.widget<SettingsField>(probe(field)).obscured, isFalse);
    expect(tester.widget<SettingsField>(probe(again)).obscured, isFalse);
    await type(tester, field, passphrase);
    await type(tester, again, passphrase);
    await press(tester, find.text(BackupCopy.exportSubmit));
    await until(tester, () => saved.isNotEmpty);
    await tester.pump();
    expect(find.text(BackupCopy.exportTitle), findsOneWidget);
    expect(find.text(BackupMessages.wrongPassphrase), findsNothing);

    accept = true;
    await press(tester, find.text(BackupCopy.exportSubmit));
    await untilFound(tester, find.text(skyCalmText(BackupMessages.saved)));
    await settle(tester);
    expect(find.text(BackupCopy.exportTitle), findsNothing);
    expect(recordedHaptics.last, HapticKind.celebration);
    expect(saved.last.fileName, matches(RegExp(r'^our-space-\d{4}-\d{2}-\d{2}\.vault$')));
    expect(lastCopySavedAt(space), isNotNull);
    expect(find.textContaining('Last saved '), findsOneWidget);
    final opened = await real(
      tester,
      () => space.backup.openContainer(space.backup.parseBackupFile(saved.last.contents), passphrase),
    );
    expect(((opened['tables'] as Map)['milestones'] as List), hasLength(1));

    await tapRow(tester, SettingsPage.saveCopyKey);
    expect(find.text(skyCalmText(BackupMessages.saved)), findsNothing);
    await press(tester, find.text(BackupCopy.cancel));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(BackupCopy.exportTitle), findsNothing);
  });

  testWidgets('brings in a copy after showing exactly what would change', (tester) async {
    calm(tester);
    final source = await openUnlockedSpace(tester);
    final rescue = await real(tester, () => source.backup.exportRescueBackup(passphrase));
    final phone = await real(tester, openHubSpace);
    await real(tester, () async {
      final opened = await phone.backup.openContainer(phone.backup.parseBackupFile(rescue.contents), passphrase);
      final restored = await phone.vault.restoreFromBackup(opened['tables'], passphrase);
      expect(restored.ok, isTrue);
    });
    await real(tester, () => source.milestones.add(title: 'First date', date: '2021-06-14'));
    final withMilestone = await real(tester, () => source.backup.exportBackup(passphrase));

    PickedVaultFile? next;
    VaultFiles.picker = () async => next;
    await openSettingsPage(tester, phone);

    next = PickedVaultFile(name: 'huge.vault', size: maxBackupFileBytes + 1, bytes: Uint8List(0));
    await tapRow(tester, SettingsPage.bringInKey);
    expect(find.text(BackupMessages.tooBig(maxBackupFileBytes + 1)), findsOneWidget);

    next = PickedVaultFile(name: 'notes.txt', size: 5, bytes: Uint8List.fromList(utf8.encode('hello')));
    await tapRow(tester, SettingsPage.bringInKey);
    expect(find.text(BackupMessages.notOurFile), findsOneWidget);
    expect(find.text(BackupMessages.tooBig(maxBackupFileBytes + 1)), findsNothing);

    next = const PickedVaultFile(name: 'lost.vault', size: 10, bytes: null);
    await tapRow(tester, SettingsPage.bringInKey);
    expect(find.text(BackupCopy.couldNotRead), findsOneWidget);

    next = null;
    await tapRow(tester, SettingsPage.bringInKey);
    expect(find.text(BackupCopy.couldNotRead), findsOneWidget);

    VaultFiles.picker = () async => throw StateError('no picker');
    await tapRow(tester, SettingsPage.bringInKey);
    expect(find.text(BackupCopy.couldNotRead), findsOneWidget);
    VaultFiles.picker = () async => next;

    next = pickedFrom(withMilestone);
    await tapRow(tester, SettingsPage.bringInKey);
    expect(find.text(BackupCopy.couldNotRead), findsNothing);
    expect(find.text(BackupCopy.importTitle), findsOneWidget);
    expect(find.text(BackupCopy.importDescription), findsOneWidget);
    expect(fieldWithHint(BackupCopy.confirmHint), findsNothing);
    await type(tester, fieldWithHint(BackupCopy.passphraseHint), 'not the passphrase it was saved with');
    await press(tester, find.text(BackupCopy.importSubmit));
    await untilFound(tester, find.text(BackupMessages.couldNotOpen));

    await type(tester, fieldWithHint(BackupCopy.passphraseHint), passphrase);
    await press(tester, find.text(BackupCopy.importSubmit));
    await untilFound(tester, find.text(BackupCopy.previewTitle));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(BackupCopy.previewIntro), findsOneWidget);
    expect(find.text('ADDED'), findsOneWidget);
    expect(find.text('UPDATED'), findsOneWidget);
    expect(find.text(BackupCopy.nothingRemoved), findsOneWidget);
    expect(find.text(BackupCopy.foreignTitle.toUpperCase()), findsNothing);
    await press(tester, find.text(BackupCopy.add(1)));
    await untilFound(tester, find.text('Added 1 thing.'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(BackupCopy.previewTitle), findsNothing);
    expect(recordedHaptics.last, HapticKind.celebration);
    final milestones = await real(tester, () => phone.milestones.list());
    expect(milestones.map((m) => m.title), ['First date']);

    final added = await real(tester, () => source.milestones.list());
    await real(tester, () => source.milestones.delete(added.single.id));
    final withDelete = await real(tester, () => source.backup.exportBackup(passphrase));
    next = pickedFrom(withDelete);
    await tapRow(tester, SettingsPage.bringInKey);
    expect(find.text('Added 1 thing.'), findsNothing);
    await type(tester, fieldWithHint(BackupCopy.passphraseHint), passphrase);
    await press(tester, find.text(BackupCopy.importSubmit));
    await untilFound(tester, find.text(BackupCopy.previewTitle));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(BackupCopy.willRemove(1)), findsOneWidget);
    expect(find.text(BackupCopy.acknowledge(1)), findsOneWidget);
    await press(tester, find.text(BackupCopy.addRemoving(1)));
    expect(find.text(BackupCopy.previewTitle), findsOneWidget);
    await press(tester, find.text(BackupCopy.acknowledge(1)));
    expect(tester.widget<SkyCheckBox>(find.byType(SkyCheckBox)).checked, isTrue);
    recordedHaptics.clear();
    await press(tester, find.text(BackupCopy.addRemoving(1)));
    await untilFound(
      tester,
      find.text('Added 1 thing. 1 of them removed something you had — those are gone for good.'),
    );
    expect(recordedHaptics, isNot(contains(HapticKind.celebration)));
    expect(await real(tester, () => phone.milestones.list()), isEmpty);

    final stranger = await real(tester, openHubSpace);
    await real(tester, () => stranger.vault.create(passphrase: passphrase, iterations: fastIterations));
    await real(tester, () => stranger.milestones.add(title: 'Not ours', date: '2020-01-01'));
    final foreign = await real(tester, () => stranger.backup.exportBackup(passphrase));
    next = pickedFrom(foreign);
    await tapRow(tester, SettingsPage.bringInKey);
    await type(tester, fieldWithHint(BackupCopy.passphraseHint), passphrase);
    await press(tester, find.text(BackupCopy.importSubmit));
    await untilFound(tester, find.text(BackupCopy.previewTitle));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(BackupCopy.foreignTitle.toUpperCase()), findsOneWidget);
    expect(find.text(BackupCopy.foreignBody), findsOneWidget);
    expect(find.textContaining('left out'), findsOneWidget);
    expect(find.text(BackupCopy.whyBody), findsNothing);
    await press(tester, find.text(BackupCopy.why));
    expect(find.text(BackupCopy.whyBody), findsOneWidget);
    await press(tester, find.text(BackupCopy.nothingToAdd));
    expect(find.text(BackupCopy.previewTitle), findsOneWidget);
    await press(tester, find.text(BackupCopy.cancel));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(BackupCopy.previewTitle), findsNothing);
    expect(find.byType(SettingsPage), findsOneWidget);
  });

  testWidgets('the passphrase sheet cannot be closed while it is working', (tester) async {
    calm(tester);
    final space = await openUnlockedSpace(tester);
    await openSettingsPage(tester, space);
    final gate = Completer<PromptStep<bool>>();
    final result = showPassphrasePrompt<bool>(
      tester.element(find.byType(SettingsPage)),
      title: BackupCopy.exportTitle,
      description: BackupCopy.exportDescription,
      requireConfirm: false,
      submitLabel: BackupCopy.exportSubmit,
      onSubmit: (_) => gate.future,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await type(tester, fieldWithHint(BackupCopy.passphraseHint), passphrase);
    await press(tester, find.text(BackupCopy.exportSubmit));
    expect(find.text(BackupCopy.working), findsOneWidget);
    await tester.state<NavigatorState>(find.byType(Navigator).first).maybePop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(BackupCopy.exportTitle), findsOneWidget);
    gate.complete(const PromptStep<bool>.finish(true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(await result, isTrue);
    expect(find.text(BackupCopy.exportTitle), findsNothing);
  });
}

Finder probe(Finder field) => find.ancestor(of: field, matching: find.byType(SettingsField));
