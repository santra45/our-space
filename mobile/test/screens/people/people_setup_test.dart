import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/presentation/home_shell.dart';
import 'package:our_space_mobile/presentation/screens/people/people_setup.dart';
import 'package:our_space_mobile/presentation/screens/people/who_is_who.dart';
import 'package:our_space_mobile/presentation/screens/people/widgets/couple_orbs.dart';
import 'package:our_space_mobile/presentation/screens/people/widgets/person_choice.dart';
import 'package:our_space_mobile/presentation/sky/sky.dart';
import 'package:our_space_mobile/presentation/widgets/app_haptics.dart';

import '../../support/fake_mailbox_worker.dart';
import '../../widgets/harness.dart' show recordHaptics, recordedHaptics;
import 'people_harness.dart';

class ScriptedIdentity extends IdentityController {
  ScriptedIdentity(OurSpace space, {required this.scripted, this.cast = const []})
      : super(store: space.store, vault: space.vault, people: space.peopleService, repair: space.repair);

  IdentityStatus scripted;
  Completer<bool>? pending;
  bool working = false;

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
  bool get busy => working;

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
    final wait = pending;
    if (wait == null) return false;
    working = true;
    notifyListeners();
    final ok = await wait.future;
    working = false;
    notifyListeners();
    return ok;
  }
}

Person person(String id, String name, {String pronoun = 'they'}) => Person(
      personId: id,
      name: name,
      pronoun: pronoun,
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
  await tester.pump(const Duration(milliseconds: 600));
}

Finder sheetSlide() => find.descendant(of: find.byType(PeopleSetupFrame), matching: find.byType(SlideTransition));

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
      expect(pronounLabelFor('xe'), 'they / them');
      expect(pronounLabelFor(null), 'they / them');
    });

    test('the together-since line reads like the rest of the sky', () {
      final now = DateTime(2026, 10, 23);
      expect(togetherSinceLabel('2026-09-25', now: now), '25 September');
      expect(togetherSinceLabel('2021-06-14', now: now), '14 June 2021');
      expect(togetherSinceLabel(null, now: now), isNull);
      expect(togetherSinceLabel('', now: now), isNull);
      expect(togetherSinceLabel('not a date', now: now), isNull);
      expect(PeopleSetupCopy.together('25 September'), 'Together since 25 September');
    });

    test('the copy stays warm: no emoji and no technical words', () {
      final me = person('p-1', 'Sam', pronoun: 'she');
      final blank = person('p-2', '');
      final copy = <String>[
        PeopleSetupCopy.claimEyebrow,
        PeopleSetupCopy.claimTitle,
        PeopleSetupCopy.claimBody,
        PeopleSetupCopy.claimFallbackName,
        PeopleSetupCopy.claimFooter,
        PeopleSetupCopy.nameEyebrow,
        PeopleSetupCopy.nameTitle,
        PeopleSetupCopy.nameBody,
        PeopleSetupCopy.nameWarning,
        PeopleSetupCopy.youLabel,
        PeopleSetupCopy.youHint,
        PeopleSetupCopy.themLabel,
        PeopleSetupCopy.themHint,
        PeopleSetupCopy.save,
        PeopleSetupCopy.saving,
        PeopleSetupCopy.dismiss,
        PeopleSetupCopy.failed,
        PeopleSetupCopy.together('25 September'),
        WhoIsWhoCopy.title,
        WhoIsWhoCopy.sheetLabel,
        WhoIsWhoCopy.sheetBody,
        WhoIsWhoCopy.thisPhone,
        WhoIsWhoCopy.noNameYet,
        WhoIsWhoCopy.imThisOne,
        WhoIsWhoCopy.yourName,
        WhoIsWhoCopy.theirName,
        WhoIsWhoCopy.save,
        WhoIsWhoCopy.cancel,
        WhoIsWhoCopy.swappedLink,
        WhoIsWhoCopy.swapTitle,
        WhoIsWhoCopy.swapAction,
        WhoIsWhoCopy.swapped,
        WhoIsWhoCopy.swapFailed,
        WhoIsWhoCopy.tooMany,
        WhoIsWhoCopy.sealed,
        WhoIsWhoCopy.editLabel(me),
        WhoIsWhoCopy.claimTitle(me),
        WhoIsWhoCopy.claimBody(blank),
        WhoIsWhoCopy.claimConfirm(me),
        WhoIsWhoCopy.swapBody(me, blank, 'Sun, Oct 4, 5:10 PM'),
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
    final since = togetherSinceLabel(space.vault.config?.startDate);
    expect(since, isNotNull);
    expect(find.text(PeopleSetupCopy.together(since!)), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
    expect(find.text('Them'), findsOneWidget);
    expect(find.text('she / her'), findsNWidgets(2));
    expect(find.text('he / him'), findsNWidgets(2));
    expect(find.text('they / them'), findsNWidgets(2));
    expect(find.text('Already did this on the other phone'), findsOneWidget);
    expect(buttonLabelled(tester, 'That’s us').enabled, isFalse);
    expect(sheetSlide(), findsNothing);

    await type(tester, fieldWithHint('Your name'), 'Sam');
    expect(buttonLabelled(tester, 'That’s us').enabled, isFalse);
    expect(find.descendant(of: find.byType(CoupleOrbs), matching: find.text('S')), findsOneWidget);
    await type(tester, fieldWithHint('Their name'), '   ');
    expect(buttonLabelled(tester, 'That’s us').enabled, isFalse);
    await type(tester, fieldWithHint('Their name'), 'Alex');
    expect(buttonLabelled(tester, 'That’s us').enabled, isTrue);
    expect(find.descendant(of: find.byType(CoupleOrbs), matching: find.text('A')), findsOneWidget);

    await press(tester, find.text('she / her').first);
    await press(tester, find.text('he / him').last);
    final selected = tester
        .widgetList<PronounChip>(find.byType(PronounChip))
        .where((chip) => chip.selected)
        .map((chip) => chip.label)
        .toList();
    expect(selected, ['she / her', 'he / him']);

    await press(tester, find.text('That’s us'));
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
    expect(find.text('Picked the wrong one? You can switch any time from Settings.'), findsOneWidget);
    expect(find.text(PeopleSetupCopy.nameTitle), findsNothing);
    final names = phone.identity.everyone.map((p) => p.name).toList();
    expect(names.toSet(), {'Alex', 'Sam'});
    PersonChoice choice(String name) =>
        tester.widget<PersonChoice>(find.ancestor(of: find.text(name), matching: find.byType(PersonChoice)));
    expect(choice(names[0]).style, SkyAvatarStyle.me);
    expect(choice(names[1]).style, SkyAvatarStyle.partner);
    expect(choice('Sam').detail, 'she / her');
    expect(choice('Alex').detail, 'he / him');
    expect(semanticsLabelled('Sam'), findsOneWidget);

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
    expect(find.textContaining('Together since'), findsNothing);
    await tester.enterText(fieldWithHint('Your name'), 'Sam');
    await tester.enterText(fieldWithHint('Their name'), 'Alex');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pump();

    expect(identity.calls, ['create Sam/they Alex/they']);
    expect(find.text('That did not save. Try again in a moment.'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 600));
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
    expect(tester.widget<PersonChoice>(find.byKey(const ValueKey('p-2'))).initial, '');
    await tester.tap(find.text('This one'));
    await tester.pump();
    expect(identity.calls, ['claim p-2']);
    expect(find.text('That did not save. Try again in a moment.'), findsOneWidget);

    identity.become(IdentityStatus.ready);
    await tester.pump();
    expect(find.text(PeopleSetupCopy.claimTitle), findsOneWidget);
    expect(
      tester.widget<IgnorePointer>(
        find.descendant(of: find.byType(PeopleSetupFrame), matching: find.byType(IgnorePointer)).first,
      ).ignoring,
      isTrue,
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(PeopleSetupCopy.claimTitle), findsNothing);
    expect(find.byType(PeopleSetupFrame), findsOneWidget);
    expect(find.byType(SkySheet), findsNothing);
  });

  testWidgets('the claim being saved spins while the others wait their turn', (tester) async {
    final space = await real(tester, openPeopleSpace);
    final identity = ScriptedIdentity(
      space,
      scripted: IdentityStatus.unclaimed,
      cast: [person('p-1', 'Alex', pronoun: 'he'), person('p-2', 'Sam', pronoun: 'she')],
    )..pending = Completer<bool>();
    addTearDown(identity.dispose);
    await pumpAlone(tester, space, identity);
    expect(sheetSlide(), findsWidgets);

    await tester.tap(find.text('Alex'));
    await tester.pump();
    PersonChoice choice(String id) => tester.widget<PersonChoice>(find.byKey(ValueKey(id)));
    expect(choice('p-1').busy, isTrue);
    expect(choice('p-1').enabled, isFalse);
    expect(choice('p-2').busy, isFalse);
    expect(choice('p-2').enabled, isFalse);
    expect(find.descendant(of: find.byKey(const ValueKey('p-1')), matching: find.byType(SkySpinner)), findsOneWidget);

    await tester.tap(find.text('Sam'), warnIfMissed: false);
    await tester.pump();
    expect(identity.calls, ['claim p-1']);

    identity.pending!.complete(true);
    await tester.pump();
    await tester.pump();
    expect(choice('p-1').busy, isFalse);
    expect(find.byType(SkySpinner), findsNothing);
    expect(find.text(PeopleSetupCopy.failed), findsNothing);
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('with motion on, the sheet springs up from the bottom over a scrim', (tester) async {
    final space = await real(tester, openPeopleSpace);
    final identity = ScriptedIdentity(space, scripted: IdentityStatus.empty);
    addTearDown(identity.dispose);
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
    final start = tester.getTopLeft(find.byType(SkySheet)).dy;
    await tester.pump(const Duration(milliseconds: 150));
    final middle = tester.getTopLeft(find.byType(SkySheet)).dy;
    await tester.pump(const Duration(milliseconds: 600));
    final end = tester.getTopLeft(find.byType(SkySheet)).dy;
    expect(start, greaterThan(middle));
    expect(middle, greaterThan(end));
    expect(tester.getBottomLeft(find.byType(SkySheet)).dy, tester.view.physicalSize.height / tester.view.devicePixelRatio);
  });

  testWidgets('the who-is-who sheet opens from anywhere with the names inside', (tester) async {
    final space = await real(tester, openPeopleSpace);
    await real(tester, () => space.vault.create(passphrase: passphrase, iterations: fastIterations));
    await real(tester, () => space.identity.createCouple(myName: 'Qalbi', partnerName: 'Farhu'));
    await settleIdentity(tester, space);
    await tester.pumpWidget(MaterialApp(
      builder: (context, navigator) =>
          ChangeNotifierProvider<IdentityController>.value(value: space.identity, child: navigator!),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(onPressed: () => showWhoIsWhoSheet(context), child: const Text('open')),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(SkySheet), findsOneWidget);
    expect(find.text(WhoIsWhoCopy.title), findsOneWidget);
    expect(find.text('THE TWO OF US'), findsOneWidget);
    expect(find.text('WHO IS WHO'), findsNothing);
    expect(find.text('Qalbi'), findsOneWidget);
    expect(find.text('Farhu'), findsOneWidget);
    expect(find.byType(SkyCard), findsNothing);
  });
}
