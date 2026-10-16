import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/presentation/screens/sync/backup_dialogs.dart';
import 'package:our_space_mobile/presentation/screens/sync/quick_unlock_panel.dart';

import '../../support/fake_quick_unlock.dart';
import 'hub_harness.dart';

void main() {
  testWidgets('the hub sets quick unlock up with the passphrase and turns it off again', (tester) async {
    calm(tester);
    final fake = FakeQuickUnlock();
    final space = await openUnlockedSpace(tester, quickUnlock: fake);
    await openHub(tester, space);
    await untilFound(tester, find.text(QuickUnlockHubCopy.title));
    expect(find.text(QuickUnlockHubCopy.offerBody), findsOneWidget);
    expect(find.text(QuickUnlockHubCopy.setupBody), findsNothing);

    await press(tester, find.text(QuickUnlockHubCopy.setUp));
    expect(find.text(QuickUnlockHubCopy.setupBody), findsOneWidget);
    expect(find.text(QuickUnlockHubCopy.notNow), findsOneWidget);

    final field = fieldWithHint(QuickUnlockHubCopy.passphraseHint);
    await type(tester, field, 'this is not the passphrase at all');
    await press(tester, find.text(QuickUnlockHubCopy.setUp));
    await untilFound(tester, find.text(QuickUnlockHubCopy.problems['wrong-passphrase']!));
    expect(space.quickUnlock.enrolled, isFalse);

    await type(tester, field, passphrase);
    await press(tester, find.text(QuickUnlockHubCopy.setUp));
    await untilFound(tester, find.text(QuickUnlockHubCopy.done));
    expect(space.quickUnlock.enrolled, isTrue);
    expect(find.text(QuickUnlockHubCopy.enrolledBody), findsOneWidget);

    await press(tester, find.text(QuickUnlockHubCopy.turnOff));
    await untilFound(tester, find.text(QuickUnlockHubCopy.turnedOff));
    expect(space.quickUnlock.enrolled, isFalse);
    expect(fake.holdsKey, isFalse);
    expect(find.text(QuickUnlockHubCopy.offerBody), findsOneWidget);
  });

  testWidgets('backing out of the fingerprint prompt during setup says nothing changed', (tester) async {
    calm(tester);
    final fake = FakeQuickUnlock();
    final space = await openUnlockedSpace(tester, quickUnlock: fake);
    await openHub(tester, space);
    await untilFound(tester, find.text(QuickUnlockHubCopy.title));

    await press(tester, find.text(QuickUnlockHubCopy.setUp));
    await type(tester, fieldWithHint(QuickUnlockHubCopy.passphraseHint), passphrase);
    fake.failNext = 'cancelled';
    await press(tester, find.text(QuickUnlockHubCopy.setUp));
    await untilFound(tester, find.text(QuickUnlockHubCopy.problems['cancelled']!));
    expect(space.quickUnlock.enrolled, isFalse);

    await press(tester, find.text(QuickUnlockHubCopy.notNow));
    expect(find.text(QuickUnlockHubCopy.setupBody), findsNothing);
    expect(find.text(QuickUnlockHubCopy.offerBody), findsOneWidget);
  });

  testWidgets('a phone that cannot do it never sees the section', (tester) async {
    calm(tester);
    final space = await openUnlockedSpace(
      tester,
      quickUnlock: FakeQuickUnlock(state: QuickUnlockAvailability.unsupported),
    );
    await openHub(tester, space);
    await untilFound(tester, find.text(BackupCopy.sectionTitle));
    expect(find.text(QuickUnlockHubCopy.title), findsNothing);
  });
}
