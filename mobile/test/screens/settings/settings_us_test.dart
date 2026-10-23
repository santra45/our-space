import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/main.dart';
import 'package:our_space_mobile/presentation/app_shell.dart';
import 'package:our_space_mobile/presentation/home_shell.dart';
import 'package:our_space_mobile/presentation/screens/settings/settings_dates.dart';
import 'package:our_space_mobile/presentation/screens/settings/settings_page.dart';
import 'package:our_space_mobile/presentation/screens/settings/widgets/names_sheet.dart';
import 'package:our_space_mobile/presentation/screens/sync/add_phone_page.dart';
import 'package:our_space_mobile/presentation/screens/sync/backup_dialogs.dart';
import 'package:our_space_mobile/presentation/screens/sync/together_now.dart';
import 'package:our_space_mobile/presentation/sky/sky.dart';
import 'package:our_space_mobile/presentation/widgets/app_haptics.dart';

import '../../widgets/harness.dart' show recordHaptics, recordedHaptics;
import '../sync/hub_harness.dart';

Finder rowText(Key row, String text) => find.descendant(of: find.byKey(row), matching: find.text(text));

Finder inNames(Finder finder) => find.descendant(of: find.byType(NamesSheet), matching: finder);

Future<OurSpace> coupled(WidgetTester tester) async {
  final space = await openUnlockedSpace(tester);
  await real(
    tester,
    () => space.identity.createCouple(myName: 'Sam', myPronoun: 'she', partnerName: 'Alex', partnerPronoun: 'he'),
  );
  return space;
}

void main() {
  setUp(recordHaptics);

  test('dates read the way the design writes them', () {
    final now = DateTime(2026, 10, 22);
    expect(settingsLongDate(DateTime(2026, 9, 25), now: now), '25 September');
    expect(settingsLongDate(DateTime(2021, 6, 14), now: now), '14 June 2021');
    expect(settingsShortDate(DateTime(2026, 9, 25)), '25 Sep 2026');
    expect(settingsDayMonth(DateTime(2026, 10, 19), now: now), '19 Oct');
    expect(settingsDayMonth(DateTime(2025, 10, 19), now: now), '19 Oct 2025');
    expect(SettingsCopy.stars(1), '1 star');
    expect(SettingsCopy.stars(28), '28 stars');
    expect(BackupCopy.lastSaved('19 Oct'), 'Last saved 19 Oct');
  });

  testWidgets('the header shows both of them, when it began and the stars they lit', (tester) async {
    calm(tester);
    final space = await coupled(tester);
    await real(tester, () async {
      final key = space.vault.key;
      await space.dailyQuestion.saveAnswer(key, ownerId: space.identity.myOwnerId, questionId: null, text: 'Mine');
      await space.dailyQuestion.saveAnswer(
        key,
        ownerId: space.identity.partner!.personId,
        questionId: null,
        text: 'Theirs',
      );
    });
    await openSettingsPage(tester, space);
    await untilFound(tester, find.text('${SettingsCopy.since('14 June 2021')} · ${SettingsCopy.stars(1)}'));
    expect(find.text('Sam & Alex'), findsNWidgets(2));
    expect(rowText(SettingsPage.namesKey, 'Sam & Alex'), findsOneWidget);
    expect(rowText(SettingsPage.togetherKey, '14 Jun 2021'), findsOneWidget);
    expect(find.text('S'), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
    expect(find.text(SettingsCopy.lockedFooter), findsOneWidget);
  });

  testWidgets('before the two of them are set up the page still opens and hides the names', (tester) async {
    calm(tester);
    final space = await openUnlockedSpace(tester);
    await openSettingsPage(tester, space);
    expect(space.identity.status, IdentityStatus.empty);
    expect(find.byKey(SettingsPage.namesKey), findsNothing);
    expect(find.text('Sam & Alex'), findsOneWidget);
    expect(find.text('S'), findsOneWidget);
    expect(find.text('A'), findsNothing);
    expect(rowText(SettingsPage.togetherKey, '14 Jun 2021'), findsOneWidget);
  });

  testWidgets('together since can be picked again, and backing out keeps it', (tester) async {
    calm(tester);
    final space = await coupled(tester);
    await openSettingsPage(tester, space);

    await tapRow(tester, SettingsPage.togetherKey);
    expect(find.text(SettingsCopy.pickDate), findsOneWidget);
    await tester.tap(find.text(SettingsCopy.cancel));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(SettingsCopy.pickDate), findsNothing);
    expect(space.vault.config!.startDate, '2021-06-14');

    await tapRow(tester, SettingsPage.togetherKey);
    await tester.tap(find.text('20'));
    await tester.pump();
    recordedHaptics.clear();
    await tester.tap(find.text(SettingsCopy.saveDate));
    await tester.pump();
    await until(tester, () => space.vault.config!.startDate == '2021-06-20');
    await settle(tester);
    expect(rowText(SettingsPage.togetherKey, '20 Jun 2021'), findsOneWidget);
    expect(find.text(SettingsCopy.since('20 June 2021')), findsOneWidget);
    expect(recordedHaptics, contains(HapticKind.celebration));
  });

  testWidgets('names open in a sheet where either of them can be renamed', (tester) async {
    calm(tester);
    final space = await coupled(tester);
    await openSettingsPage(tester, space);
    await tapRow(tester, SettingsPage.namesKey);

    expect(inNames(find.text('Sam')), findsOneWidget);
    expect(inNames(find.text('Alex')), findsOneWidget);
    expect(inNames(find.text(NamesCopy.thisPhone)), findsOneWidget);
    expect(inNames(find.text('she / her')), findsOneWidget);
    expect(inNames(find.text('he / him')), findsOneWidget);
    expect(inNames(find.text(NamesCopy.imThisOne)), findsOneWidget);
    expect(inNames(find.text(NamesCopy.swappedLink)), findsOneWidget);
    expect(inNames(find.text(NamesCopy.sealed)), findsOneWidget);

    await press(tester, semanticsLabelled('Edit Alex'));
    final field = fieldWithHint(NamesCopy.theirName);
    expect(field, findsOneWidget);
    expect(tester.widget<TextField>(field).controller!.text, 'Alex');
    await type(tester, field, '   ');
    await press(tester, find.text(NamesCopy.save));
    expect(fieldWithHint(NamesCopy.theirName), findsOneWidget);
    expect(space.identity.partner!.name, 'Alex');

    await type(tester, field, 'Alexa');
    await press(tester, find.text('they / them'));
    await press(tester, find.text(NamesCopy.save));
    await until(tester, () => space.identity.partner?.name == 'Alexa');
    await until(tester, () => !space.identity.busy && fieldWithHint(NamesCopy.theirName).evaluate().isEmpty);
    await settle(tester);
    expect(inNames(find.text('Alexa')), findsOneWidget);
    expect(space.identity.partner!.pronoun, 'they');
    expect(rowText(SettingsPage.namesKey, 'Sam & Alexa'), findsOneWidget);

    await press(tester, semanticsLabelled('Edit Sam'));
    await type(tester, fieldWithHint(NamesCopy.yourName), 'Samantha');
    await press(tester, find.text(NamesCopy.cancel));
    expect(fieldWithHint(NamesCopy.yourName), findsNothing);
    expect(space.identity.me!.name, 'Sam');
  });

  testWidgets('"I\'m this one" asks first, then moves this phone', (tester) async {
    calm(tester);
    final space = await coupled(tester);
    final sam = space.identity.me!.personId;
    final alex = space.identity.partner!.personId;
    await openSettingsPage(tester, space);
    await tapRow(tester, SettingsPage.namesKey);

    await press(tester, find.text(NamesCopy.imThisOne));
    expect(find.text('Make this phone Alex?'), findsOneWidget);
    expect(
      find.text(
        'Answers already written on this phone stay with Sam. If your names just look swapped, use “Swap us back” instead.',
      ),
      findsOneWidget,
    );
    await press(tester, find.text(NamesCopy.cancel));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Make this phone Alex?'), findsNothing);
    expect(space.identity.me!.personId, sam);

    await press(tester, find.text(NamesCopy.imThisOne));
    await press(tester, find.text('Yes, I\'m Alex'));
    await until(tester, () => space.identity.me?.personId == alex);
    await until(tester, () => !space.identity.busy);
    await settle(tester);
    expect(space.identity.partner!.personId, sam);
    final alexRow = find.byKey(ValueKey<String>('row-$alex'));
    expect(find.descendant(of: alexRow, matching: find.text(NamesCopy.thisPhone)), findsOneWidget);
  });

  testWidgets('"Swap us back" asks first, trades the two places and says so', (tester) async {
    calm(tester);
    final space = await coupled(tester);
    final before = space.identity.me!.personId;
    await openSettingsPage(tester, space);
    await tapRow(tester, SettingsPage.namesKey);

    await press(tester, find.text(NamesCopy.swappedLink));
    expect(find.text(NamesCopy.swapTitle), findsOneWidget);
    expect(
      find.textContaining('Sam and Alex trade places, along with which phone is whose. Answers written since '),
      findsOneWidget,
    );
    await press(tester, find.text(NamesCopy.cancel));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(NamesCopy.swapTitle), findsNothing);
    expect(space.identity.me!.personId, before);

    await press(tester, find.text(NamesCopy.swappedLink));
    recordedHaptics.clear();
    await press(tester, find.text(NamesCopy.swapAction));
    await untilFound(tester, find.text(NamesCopy.swapped));
    await until(tester, () => !space.identity.busy);
    await settle(tester);
    expect(recordedHaptics, containsAllInOrder([HapticKind.tap, HapticKind.celebration]));
    expect(space.identity.me!.personId, isNot(before));
    expect(space.identity.me!.name, 'Sam');
    expect(space.identity.partner!.personId, before);
  });

  testWidgets('names copy keeps its fallbacks for missing names', (tester) async {
    const blank = Person(
      personId: 'person-bbbbbbbb',
      name: '',
      pronoun: 'xe',
      deviceIds: [],
      lastActiveAt: null,
      createdAt: 1,
      updatedAt: 3,
    );
    expect(NamesCopy.pronounLabel('xe'), 'they / them');
    expect(NamesCopy.claimTitle(blank), 'Make this phone the other one?');
    expect(NamesCopy.claimConfirm(blank), 'Yes, I\'m this one');
    expect(NamesCopy.editLabel(blank), 'Edit this person');
    expect(
      NamesCopy.swapBody(blank, blank, null),
      'You and your partner trade places, along with which phone is whose. Do this on one phone only. The other one follows by itself the next time you two connect.',
    );
  });

  test('names copy stays warm: no emoji and no technical words', () {
    const me = Person(
      personId: 'person-aaaaaaaa',
      name: 'Sam',
      pronoun: 'she',
      deviceIds: [],
      lastActiveAt: null,
      createdAt: 1,
      updatedAt: 1,
    );
    const blank = Person(
      personId: 'person-bbbbbbbb',
      name: '',
      pronoun: 'they',
      deviceIds: [],
      lastActiveAt: null,
      createdAt: 1,
      updatedAt: 1,
    );
    final copy = <String>[
      NamesCopy.title,
      NamesCopy.subtitle,
      NamesCopy.thisPhone,
      NamesCopy.noNameYet,
      NamesCopy.imThisOne,
      NamesCopy.yourName,
      NamesCopy.theirName,
      NamesCopy.save,
      NamesCopy.cancel,
      NamesCopy.swappedLink,
      NamesCopy.swapTitle,
      NamesCopy.swapAction,
      NamesCopy.swapped,
      NamesCopy.swapFailed,
      NamesCopy.claimFailed,
      NamesCopy.tooMany,
      NamesCopy.sealed,
      ...NamesCopy.pronounLabels.values,
      NamesCopy.editLabel(me),
      NamesCopy.claimTitle(me),
      NamesCopy.claimBody(blank),
      NamesCopy.claimConfirm(me),
      NamesCopy.swapBody(me, blank, 'Sun, Oct 4, 5:10 PM'),
    ];
    final technical = RegExp(
      r'\b(sync\w*|devices?|pair\w*|servers?|upload\w*|download\w*|data|peers?|relay\w*|mailbox\w*|encrypt\w*|keys?)\b',
      caseSensitive: false,
    );
    for (final line in copy) {
      expect(skyCalmText(line), line, reason: line);
      expect(technical.hasMatch(line), isFalse, reason: line);
    }
  });

  testWidgets('add another phone and their phones open from the two of us', (tester) async {
    calm(tester);
    final space = await coupled(tester);
    await openSettingsPage(tester, space);
    expect(rowText(SettingsPage.connectionKey, TogetherNowCopy.notJoined), findsOneWidget);

    await tapRow(tester, SettingsPage.phonesKey);
    expect(find.byType(AddPhonePage), findsOneWidget);
    expect(find.text(AddPhoneCopy.intro), findsOneWidget);
    await tester.tap(semanticsLabelled('Back').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(AddPhonePage), findsNothing);

    await tapRow(tester, SettingsPage.connectionKey);
    expect(find.byType(TogetherNowSheet), findsOneWidget);
    await closeTopModal(tester);
    expect(find.byType(TogetherNowSheet), findsNothing);
  });

  testWidgets('opens from her avatar, and locking closes every sheet and page above the shell', (tester) async {
    calm(tester);
    final space = await coupled(tester);
    await tester.pumpWidget(OurSpaceApp(openSpace: () async => space, shell: const HomeShell(pageBuilder: avatarTab)));
    await tester.pump();
    await untilFound(tester, find.byKey(ShellKeys.avatar));
    await tester.tap(find.byKey(ShellKeys.avatar));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(SettingsPage), findsOneWidget);

    await tapRow(tester, SettingsPage.phonesKey);
    expect(find.byType(AddPhonePage), findsOneWidget);
    await tester.tap(semanticsLabelled('Back').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tapRow(tester, SettingsPage.saveCopyKey);
    expect(find.text(BackupCopy.exportTitle), findsOneWidget);
    space.vault.lock();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(BackupCopy.exportTitle), findsNothing);
    expect(find.byType(SettingsPage), findsNothing);
    expect(find.text('Locked'), findsOneWidget);
  });
}
