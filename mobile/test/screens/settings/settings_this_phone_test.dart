import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/presentation/screens/settings/settings_page.dart';
import 'package:our_space_mobile/presentation/screens/settings/widgets/reminders_row.dart';
import 'package:our_space_mobile/presentation/screens/sync/quick_unlock_sheet.dart';
import 'package:our_space_mobile/presentation/sky/sky.dart';
import 'package:our_space_mobile/presentation/widgets/app_haptics.dart';

import '../../support/fake_mailbox_worker.dart';
import '../../support/fake_quick_unlock.dart';
import '../../widgets/harness.dart' show recordHaptics, recordedHaptics;
import '../sync/hub_harness.dart';

Finder rowText(Key row, String text) => find.descendant(of: find.byKey(row), matching: find.text(text));

SkyToggle toggleIn(WidgetTester tester, Key row) =>
    tester.widget<SkyToggle>(find.descendant(of: find.byKey(row), matching: find.byType(SkyToggle)));

Future<OurSpace> remindersSpace(WidgetTester tester, FakePushPlatform push) => openUnlockedSpace(
  tester,
  mailbox: testMailbox,
  client: FakeMailboxWorker(token: 'test-token'),
  push: push,
);

void main() {
  final systemOpen = SystemSettings.openNotifications;

  setUp(recordHaptics);

  tearDown(() => SystemSettings.openNotifications = systemOpen);

  testWidgets('sets open with a touch up with the passphrase and turns it off again', (tester) async {
    calm(tester);
    final fake = FakeQuickUnlock();
    final space = await openUnlockedSpace(tester, quickUnlock: fake);
    await openSettingsPage(tester, space);
    await untilFound(tester, find.byKey(SettingsPage.touchKey));
    expect(rowText(SettingsPage.touchKey, TouchCopy.offBody), findsOneWidget);
    expect(toggleIn(tester, SettingsPage.touchKey).value, isFalse);

    await tapRow(tester, SettingsPage.touchKey);
    expect(find.text(TouchCopy.setupBody), findsOneWidget);
    expect(find.text(TouchCopy.notNow), findsOneWidget);

    final field = fieldWithHint(TouchCopy.passphraseHint);
    await type(tester, field, 'this is not the passphrase at all');
    await press(tester, find.text(TouchCopy.setUp));
    await untilFound(tester, find.text(TouchCopy.problems['wrong-passphrase']!));
    expect(space.quickUnlock.enrolled, isFalse);

    await type(tester, field, passphrase);
    expect(find.text(TouchCopy.problems['wrong-passphrase']!), findsNothing);
    await press(tester, find.text(TouchCopy.setUp));
    await untilFound(tester, find.text(TouchCopy.done));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(TouchCopy.setupBody), findsNothing);
    expect(space.quickUnlock.enrolled, isTrue);
    expect(rowText(SettingsPage.touchKey, TouchCopy.onBody), findsOneWidget);
    expect(toggleIn(tester, SettingsPage.touchKey).value, isTrue);
    expect(recordedHaptics, contains(HapticKind.celebration));

    await press(tester, find.descendant(of: find.byKey(SettingsPage.touchKey), matching: find.byType(SkyToggle)));
    await untilFound(tester, find.text(TouchCopy.turnedOff));
    expect(space.quickUnlock.enrolled, isFalse);
    expect(fake.holdsKey, isFalse);
    expect(find.text(TouchCopy.done), findsNothing);
    expect(rowText(SettingsPage.touchKey, TouchCopy.offBody), findsOneWidget);
  });

  testWidgets('backing out of the fingerprint prompt during setup says nothing changed', (tester) async {
    calm(tester);
    final fake = FakeQuickUnlock();
    final space = await openUnlockedSpace(tester, quickUnlock: fake);
    await openSettingsPage(tester, space);
    await untilFound(tester, find.byKey(SettingsPage.touchKey));

    await tapRow(tester, SettingsPage.touchKey);
    await type(tester, fieldWithHint(TouchCopy.passphraseHint), passphrase);
    fake.failNext = 'cancelled';
    await press(tester, find.text(TouchCopy.setUp));
    await untilFound(tester, find.text(TouchCopy.problems['cancelled']!));
    expect(space.quickUnlock.enrolled, isFalse);

    await press(tester, find.text(TouchCopy.notNow));
    expect(find.text(TouchCopy.setupBody), findsNothing);
    expect(find.text(TouchCopy.done), findsNothing);
    expect(rowText(SettingsPage.touchKey, TouchCopy.offBody), findsOneWidget);
    expect(TouchCopy.problem('something-new'), TouchCopy.problems['failed']);
  });

  testWidgets('a phone that cannot do it never sees the touch row', (tester) async {
    calm(tester);
    final space = await openUnlockedSpace(
      tester,
      quickUnlock: FakeQuickUnlock(state: QuickUnlockAvailability.unsupported),
    );
    await openSettingsPage(tester, space);
    await settle(tester);
    expect(find.byKey(SettingsPage.touchKey), findsNothing);
    expect(find.text(TouchCopy.title), findsNothing);
  });

  testWidgets('little reminders ask first, then say they are on', (tester) async {
    calm(tester);
    final push = FakePushPlatform(grant: true);
    final space = await remindersSpace(tester, push);
    var opened = 0;
    SystemSettings.openNotifications = () async {
      opened++;
      return true;
    };
    await openSettingsPage(tester, space);
    await untilFound(tester, rowText(SettingsPage.remindersKey, RemindersCopy.off));
    expect(toggleIn(tester, SettingsPage.remindersKey).value, isFalse);

    await tapRow(tester, SettingsPage.remindersKey);
    await untilFound(tester, find.text(RemindersCopy.turnedOn));
    expect(push.calls, contains('requestPermission'));
    expect(opened, 0);
    expect(rowText(SettingsPage.remindersKey, RemindersCopy.on), findsOneWidget);
    expect(toggleIn(tester, SettingsPage.remindersKey).value, isTrue);
    expect(recordedHaptics, contains(HapticKind.celebration));

    await tapRow(tester, SettingsPage.remindersKey);
    await until(tester, () => opened == 1);
    expect(find.text(RemindersCopy.turnedOn), findsNothing);
  });

  testWidgets('little reminders lead to the phone settings when they cannot be asked for', (tester) async {
    calm(tester);
    final push = FakePushPlatform();
    final space = await remindersSpace(tester, push);
    var opens = true;
    var opened = 0;
    SystemSettings.openNotifications = () async {
      opened++;
      return opens;
    };
    await openSettingsPage(tester, space);
    await untilFound(tester, rowText(SettingsPage.remindersKey, RemindersCopy.off));

    await tapRow(tester, SettingsPage.remindersKey);
    await until(tester, () => opened == 1);
    expect(find.text(RemindersCopy.openYourself), findsNothing);

    opens = false;
    await tapRow(tester, SettingsPage.remindersKey);
    await untilFound(tester, find.text(RemindersCopy.openYourself));
    expect(opened, 2);

    push.allowed = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await untilFound(tester, rowText(SettingsPage.remindersKey, RemindersCopy.on));
    expect(toggleIn(tester, SettingsPage.remindersKey).value, isTrue);
  });

  testWidgets('reminders stay hidden when this phone cannot get them', (tester) async {
    calm(tester);
    final space = await openUnlockedSpace(tester, push: FakePushPlatform());
    await openSettingsPage(tester, space);
    await settle(tester);
    expect(find.byKey(SettingsPage.remindersKey), findsNothing);
    expect(find.text(RemindersCopy.title), findsNothing);
  });
}
