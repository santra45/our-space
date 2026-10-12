import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/presentation/home_shell.dart';
import 'package:our_space_mobile/presentation/screens/people/people_setup.dart';
import 'package:our_space_mobile/presentation/widgets/our_widgets.dart';

import '../../support/fake_mailbox_worker.dart';
import '../../widgets/harness.dart' show recordHaptics, recordedHaptics;
import 'people_harness.dart';

class ScriptedIdentity extends IdentityController {
  ScriptedIdentity(OurSpace space, {required this.scripted, this.cast = const []})
      : super(store: space.store, vault: space.vault, people: space.peopleService, repair: space.repair);

  IdentityStatus scripted;

  void become(IdentityStatus next) {
    scripted = next;
    notifyListeners();
  }
  final List<Person> cast;
  final List<String> calls = [];

  @override
  IdentityStatus get status => scripted;

  @override
  List<Person> get everyone => cast;

  @override
  Future<bool> createCouple({
    required String myName,
    String? myPronoun,
    required String partnerName,
    String? partnerPronoun,
  }) async {
    calls.add('create $myName/$myPronoun $partnerName/$partnerPronoun');
    return false;
  }

  @override
  Future<bool> claimPerson(String personId) async {
    calls.add('claim $personId');
    return false;
  }
}

Person person(String id, String name) => Person(
      personId: id,
      name: name,
      pronoun: 'they',
      deviceIds: const [],
      lastActiveAt: null,
      createdAt: 1,
      updatedAt: 1,
    );

Future<void> pumpAlone(WidgetTester tester, OurSpace space, IdentityController identity) async {
  await tester.pumpWidget(MaterialApp(
    home: MultiProvider(
      providers: [
        ChangeNotifierProvider<IdentityController>.value(value: identity),
        ChangeNotifierProvider<SyncService>.value(value: space.sync),
      ],
      child: const Scaffold(body: Stack(fit: StackFit.expand, children: [PeopleSetup()])),
    ),
  ));
  await tester.pump();
}

void main() {
  setUp(recordHaptics);

  group('when to ask', () {
    test('only an empty or unclaimed space ever sees the prompt', () {
      for (final status in [IdentityStatus.loading, IdentityStatus.locked, IdentityStatus.ready]) {
        expect(
          peopleSetupView(status: status, mailboxSettled: true, waitedOut: true, dismissed: false),
          PeopleSetupView.hidden,
        );
      }
      expect(
        peopleSetupView(status: IdentityStatus.unclaimed, mailboxSettled: false, waitedOut: false, dismissed: true),
        PeopleSetupView.claim,
      );
    });

    test('an empty space waits for the mailbox or 12 seconds, and can be waved away', () {
      expect(namesWait, const Duration(seconds: 12));
      PeopleSetupView view({required bool settled, required bool waited, bool dismissed = false}) => peopleSetupView(
            status: IdentityStatus.empty,
            mailboxSettled: settled,
            waitedOut: waited,
            dismissed: dismissed,
          );
      expect(view(settled: false, waited: false), PeopleSetupView.hidden);
      expect(view(settled: true, waited: false), PeopleSetupView.name);
      expect(view(settled: false, waited: true), PeopleSetupView.name);
      expect(view(settled: true, waited: true, dismissed: true), PeopleSetupView.hidden);
    });

    test('a phone-to-phone link that is still syncing holds the names form back, like the web', () async {
      expect(stillSyncingPeerStates, {'connecting', 'handshaking', 'authorized', 'syncing'});
      PeopleSetupView view({required bool settling, required bool waited}) => peopleSetupView(
            status: IdentityStatus.empty,
            mailboxSettled: true,
            waitedOut: waited,
            dismissed: false,
            partnerSettling: settling,
          );
      expect(view(settling: true, waited: false), PeopleSetupView.hidden);
      expect(view(settling: true, waited: true), PeopleSetupView.name);
      expect(view(settling: false, waited: false), PeopleSetupView.name);

      final space = await openPeopleSpace();
      expect(partnerIsSettling(space.sync), isFalse);
      await space.close();
    });

    test('the mailbox counts as settled when it is off or has had its look', () async {
      final off = await openPeopleSpace();
      expect(mailboxIsSettled(off.sync), isTrue);
      await off.close();

      final worker = FakeMailboxWorker(token: mailboxToken);
      final on = await openPeopleSpace(worker: worker);
      expect(mailboxIsSettled(on.sync), isFalse);
      await on.vault.create(passphrase: passphrase, iterations: fastIterations);
      expect(mailboxIsSettled(on.sync), isFalse);
      await on.sync.syncNow();
      expect(on.sync.status.state, MailboxRunState.ok);
      expect(mailboxIsSettled(on.sync), isTrue);
      await on.close();
    });

    test('pronoun labels match the web', () {
      expect(pronouns.map((p) => pronounLabels[p]), ['she / her', 'he / him', 'they / them']);
    });
  });

  testWidgets('a fresh space asks for both names and saves them', (tester) async {
    calm(tester);
    final space = await real(tester, openPeopleSpace);
    await real(tester, () => space.vault.create(passphrase: passphrase, coupleNames: 'Us', iterations: fastIterations));
    await pumpOurSpace(tester, space);
    await untilFound(tester, find.byType(HomeShell));
    await untilFound(tester, find.text(PeopleSetupCopy.nameTitle));

    expect(find.text('ONE SMALL THING'), findsOneWidget);
    expect(find.text('So this place can use your names instead of saying “your partner” forever.'), findsOneWidget);
    expect(
      find.text(
        'Only do this on one phone. If the other phone already has your names, they will arrive here by themselves.',
      ),
      findsOneWidget,
    );
    expect(find.text('YOU'), findsOneWidget);
    expect(find.text('THEM'), findsOneWidget);
    expect(find.text('she / her'), findsNWidgets(2));
    expect(find.text('he / him'), findsNWidgets(2));
    expect(find.text('they / them'), findsNWidgets(2));
    expect(find.text('Already did this on the other phone'), findsOneWidget);
    expect(buttonLabelled(tester, 'That’s us 💕').isEnabled, isFalse);

    await type(tester, fieldWithHint('Your name'), 'Sam');
    expect(buttonLabelled(tester, 'That’s us 💕').isEnabled, isFalse);
    await type(tester, fieldWithHint('Their name'), '   ');
    expect(buttonLabelled(tester, 'That’s us 💕').isEnabled, isFalse);
    await type(tester, fieldWithHint('Their name'), 'Alex');
    expect(buttonLabelled(tester, 'That’s us 💕').isEnabled, isTrue);

    await press(tester, find.text('she / her').first);
    await press(tester, find.text('he / him').last);
    final selected = tester
        .widgetList<PronounChip>(find.byType(PronounChip))
        .where((chip) => chip.selected)
        .map((chip) => chip.label)
        .toList();
    expect(selected, ['she / her', 'he / him']);

    await press(tester, find.text('That’s us 💕'));
    await until(tester, () => recordedHaptics.contains(HapticKind.celebration) && !space.identity.busy);
    await tester.pump();

    expect(find.text(PeopleSetupCopy.nameTitle), findsNothing);
    expect(space.identity.me?.name, 'Sam');
    expect(space.identity.me?.pronoun, 'she');
    expect(space.identity.partner?.name, 'Alex');
    expect(space.identity.partner?.pronoun, 'he');
    expect(recordedHaptics.last, HapticKind.celebration);
  });

  testWidgets('a fresh phone that already did this elsewhere can wave the prompt away', (tester) async {
    calm(tester);
    final space = await real(tester, openPeopleSpace);
    await real(tester, () => space.vault.create(passphrase: passphrase, iterations: fastIterations));
    await pumpOurSpace(tester, space);
    await untilFound(tester, find.text(PeopleSetupCopy.dismiss));
    recordedHaptics.clear();

    await press(tester, find.text(PeopleSetupCopy.dismiss));
    expect(find.text(PeopleSetupCopy.nameTitle), findsNothing);
    expect(recordedHaptics, [HapticKind.tap]);
    expect(space.identity.status, IdentityStatus.empty);
  });

  testWidgets('waits for the mailbox before asking, then asks after 12 seconds', (tester) async {
    calm(tester);
    final worker = FakeMailboxWorker(token: mailboxToken);
    final space = await real(tester, () => openPeopleSpace(worker: worker));
    await real(tester, () => space.vault.create(passphrase: passphrase, iterations: fastIterations));
    await pumpOurSpace(tester, space);
    await untilFound(tester, find.byType(HomeShell));
    await until(tester, () => space.identity.status == IdentityStatus.empty);
    await tester.pump();

    expect(find.text(PeopleSetupCopy.nameTitle), findsNothing);
    await tester.pump(const Duration(seconds: 11));
    expect(find.text(PeopleSetupCopy.nameTitle), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(PeopleSetupCopy.nameTitle), findsOneWidget);
  });

  testWidgets('asks as soon as the mailbox has had its look', (tester) async {
    calm(tester);
    final worker = FakeMailboxWorker(token: mailboxToken);
    final space = await real(tester, () => openPeopleSpace(worker: worker));
    await real(tester, () => space.vault.create(passphrase: passphrase, iterations: fastIterations));
    await pumpOurSpace(tester, space);
    await untilFound(tester, find.byType(HomeShell));
    await until(tester, () => space.identity.status == IdentityStatus.empty);
    await tester.pump();
    expect(find.text(PeopleSetupCopy.nameTitle), findsNothing);

    await real(tester, () => space.sync.syncNow());
    await untilFound(tester, find.text(PeopleSetupCopy.nameTitle));
    await until(tester, () => !space.identity.busy);
  });

  testWidgets('names from the other phone arrive and she taps her own', (tester) async {
    calm(tester);
    final worker = FakeMailboxWorker(token: mailboxToken);
    final partner = await real(tester, () => openPeopleSpace(worker: worker));
    await real(tester, () async {
      await partner.vault.create(passphrase: passphrase, coupleNames: 'Alex & Sam', iterations: fastIterations);
      await partner.identity.createCouple(myName: 'Alex', myPronoun: 'he', partnerName: 'Sam', partnerPronoun: 'she');
      await partner.sync.syncNow();
    });

    final phone = await real(tester, () => openPeopleSpace(worker: worker));
    await real(
      tester,
      () => phone.vault.joinWithSalt(passphrase: passphrase, salt: partner.vault.salt!, iterations: fastIterations),
    );
    await pumpOurSpace(tester, phone);
    await untilFound(tester, find.byType(HomeShell));
    await until(tester, () => phone.identity.status == IdentityStatus.empty);
    await tester.pump();
    expect(find.text(PeopleSetupCopy.nameTitle), findsNothing);

    await real(tester, () => phone.sync.syncNow());
    await until(tester, () => phone.identity.status == IdentityStatus.unclaimed);
    await untilFound(tester, find.text(PeopleSetupCopy.claimTitle));

    expect(find.text('ALMOST THERE'), findsOneWidget);
    expect(
      find.text('Tap your own name. It is only so this phone knows whose answers are whose.'),
      findsOneWidget,
    );
    expect(
      find.text('Picked the wrong one? You can switch any time from the Pair & Sync Hub.'),
      findsOneWidget,
    );
    expect(find.text(PeopleSetupCopy.nameTitle), findsNothing);
    final names = phone.identity.everyone.map((p) => p.name).toList();
    expect(names.toSet(), {'Alex', 'Sam'});
    expect(buttonLabelled(tester, names[0]).variant, BouncyVariant.primary);
    expect(buttonLabelled(tester, names[1]).variant, BouncyVariant.lavender);

    recordedHaptics.clear();
    await press(tester, find.text('Sam'));
    await until(tester, () => recordedHaptics.contains(HapticKind.celebration) && !phone.identity.busy);
    await tester.pump();

    expect(phone.identity.me?.name, 'Sam');
    expect(phone.identity.partner?.name, 'Alex');
    expect(find.text(PeopleSetupCopy.claimTitle), findsNothing);
    expect(recordedHaptics, [HapticKind.tick, HapticKind.tap, HapticKind.celebration]);
  });

  testWidgets('a save that does not land shows the gentle retry line', (tester) async {
    final space = await real(tester, openPeopleSpace);
    final identity = ScriptedIdentity(space, scripted: IdentityStatus.empty);
    addTearDown(identity.dispose);
    await pumpAlone(tester, space, identity);

    expect(find.text(PeopleSetupCopy.nameTitle), findsOneWidget);
    await tester.enterText(fieldWithHint('Your name'), 'Sam');
    await tester.enterText(fieldWithHint('Their name'), 'Alex');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pump();

    expect(identity.calls, ['create Sam/they Alex/they']);
    expect(find.text('That did not save. Try again in a moment.'), findsOneWidget);
  });

  testWidgets('a claim that does not land says so, and a nameless person is "This one"', (tester) async {
    final space = await real(tester, openPeopleSpace);
    final identity = ScriptedIdentity(
      space,
      scripted: IdentityStatus.unclaimed,
      cast: [person('p-1', 'Alex'), person('p-2', '')],
    );
    addTearDown(identity.dispose);
    await pumpAlone(tester, space, identity);

    expect(find.text('This one'), findsOneWidget);
    await tester.tap(find.text('This one'));
    await tester.pump();
    expect(identity.calls, ['claim p-2']);
    expect(find.text('That did not save. Try again in a moment.'), findsOneWidget);

    identity.become(IdentityStatus.ready);
    await tester.pump();
    expect(find.text(PeopleSetupCopy.claimTitle), findsNothing);
  });
}
