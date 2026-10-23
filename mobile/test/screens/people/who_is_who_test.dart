import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/presentation/screens/people/who_is_who.dart';
import 'package:our_space_mobile/presentation/screens/sync/sync_hub.dart';
import 'package:our_space_mobile/presentation/sky/sky.dart';
import 'package:our_space_mobile/presentation/widgets/app_haptics.dart';
import 'package:provider/provider.dart';

import '../../widgets/harness.dart' show recordHaptics, recordedHaptics;
import '../sync/hub_harness.dart' hide fieldWithHint;

Finder fieldWithHint(String hint) => find.descendant(
      of: find.byWidgetPredicate((widget) => widget is SkyTextField && widget.hint == hint),
      matching: find.byType(TextField),
    );

Finder semanticsLabelled(String label) =>
    find.byWidgetPredicate((widget) => widget is Semantics && widget.properties.label == label);

Future<void> pumpWhoIsWho(WidgetTester tester, OurSpace space) async {
  await tester.pumpWidget(
    spaceApp(space, home: const SingleChildScrollView(padding: EdgeInsets.all(16), child: WhoIsWho())),
  );
  await tester.pump();
  await settleIdentity(tester, space);
}

Person someone(String id, String name, {String pronoun = 'they', int updatedAt = 1}) => Person(
      personId: id,
      name: name,
      pronoun: pronoun,
      deviceIds: const [],
      lastActiveAt: null,
      createdAt: 1,
      updatedAt: updatedAt,
    );

class CastIdentity extends IdentityController {
  CastIdentity(OurSpace space, this.cast)
      : super(store: space.store, vault: space.vault, people: space.peopleService, repair: space.repair);

  final List<Person> cast;
  int swaps = 0;

  @override
  IdentityStatus get status => IdentityStatus.ready;

  @override
  Person? get me => cast.first;

  @override
  Person? get partner => cast.length > 1 ? cast[1] : null;

  @override
  List<Person> get everyone => cast;

  @override
  bool get busy => false;

  @override
  Future<bool> swapUsBack() async {
    swaps++;
    return false;
  }
}

Future<void> pumpCast(WidgetTester tester, OurSpace space, IdentityController identity) async {
  await tester.pumpWidget(MaterialApp(
    home: ChangeNotifierProvider<IdentityController>.value(
      value: identity,
      child: const Scaffold(body: SingleChildScrollView(padding: EdgeInsets.all(16), child: WhoIsWho())),
    ),
  ));
  await tester.pump();
}

void main() {
  setUp(recordHaptics);

  test('copy matches the web, with its fallbacks for missing names', () {
    const sam = Person(
      personId: 'person-aaaaaaaa',
      name: 'Sam',
      pronoun: 'she',
      deviceIds: [],
      lastActiveAt: null,
      createdAt: 1,
      updatedAt: 2,
    );
    const blank = Person(
      personId: 'person-bbbbbbbb',
      name: '',
      pronoun: 'xe',
      deviceIds: [],
      lastActiveAt: null,
      createdAt: 1,
      updatedAt: 3,
    );
    expect(WhoIsWhoCopy.pronounLabel('she'), 'she / her');
    expect(WhoIsWhoCopy.pronounLabel('he'), 'he / him');
    expect(WhoIsWhoCopy.pronounLabel('xe'), 'they / them');
    expect(WhoIsWhoCopy.pronounLabel(null), 'they / them');
    expect(WhoIsWhoCopy.claimTitle(sam), 'Make this phone Sam?');
    expect(WhoIsWhoCopy.claimTitle(blank), 'Make this phone the other one?');
    expect(WhoIsWhoCopy.claimConfirm(sam), 'Yes, I\'m Sam');
    expect(WhoIsWhoCopy.claimConfirm(blank), 'Yes, I\'m this one');
    expect(
      WhoIsWhoCopy.claimBody(blank),
      'Answers already written on this phone stay with you. If your names just look swapped, use “Swap us back” below instead.',
    );
    expect(WhoIsWhoCopy.editLabel(blank), 'Edit this person');
    expect(
      WhoIsWhoCopy.swapBody(blank, blank, null),
      'You and your partner trade places, along with which phone is whose. Do this on one phone only. The other one follows by itself the next time the two of you catch up.',
    );
    expect(
      WhoIsWhoCopy.swapBody(sam, blank, 'Sun, Oct 4, 5:10 PM'),
      'Sam and your partner trade places, along with which phone is whose. Answers written since Sun, Oct 4, 5:10 PM move with them. Do this on one phone only. The other one follows by itself the next time the two of you catch up.',
    );
    expect(WhoIsWhoCopy.swapped, 'Swapped back. Your answers are where they belong again.');
    expect(tradedPlacesAt([sam, blank]), 3);
    expect(tradedPlacesAt([sam]), isNull);
  });

  testWidgets('formats the swap moment like the web does in English', (tester) async {
    late String formatted;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        formatted = formatSwapMoment(context, DateTime(2026, 10, 4, 17, 10).millisecondsSinceEpoch);
        return const SizedBox.shrink();
      }),
    ));
    expect(formatted, 'Sun, Oct 4, 5:10 PM');
  });

  testWidgets('stays hidden until both of you are set up', (tester) async {
    calm(tester);
    final space = await openUnlockedSpace(tester);
    await pumpWhoIsWho(tester, space);
    expect(space.identity.status, IdentityStatus.empty);
    expect(find.text('WHO IS WHO'), findsNothing);
    expect(find.byType(SkyCard), findsNothing);
  });

  testWidgets('renames someone and changes their pronoun', (tester) async {
    calm(tester);
    final space = await openUnlockedSpace(tester);
    await real(
      tester,
      () => space.identity.createCouple(myName: 'Sam', myPronoun: 'she', partnerName: 'Alex', partnerPronoun: 'he'),
    );
    await pumpWhoIsWho(tester, space);
    await untilFound(tester, find.text('WHO IS WHO'));

    expect(find.byType(SkyCard), findsOneWidget);
    expect(find.text('Sam'), findsOneWidget);
    expect(find.text('Alex'), findsOneWidget);
    expect(find.text(WhoIsWhoCopy.thisPhone), findsOneWidget);
    expect(find.text('she / her'), findsOneWidget);
    expect(find.text('he / him'), findsOneWidget);
    expect(find.text(WhoIsWhoCopy.imThisOne), findsOneWidget);
    expect(find.text(WhoIsWhoCopy.swappedLink), findsOneWidget);
    expect(find.text(WhoIsWhoCopy.sealed), findsOneWidget);
    final avatars = tester.widgetList<SkyAvatar>(find.byType(SkyAvatar)).toList();
    expect(avatars.map((a) => a.initial), ['S', 'A']);
    expect(avatars.map((a) => a.style), [SkyAvatarStyle.me, SkyAvatarStyle.partner]);

    await press(tester, semanticsLabelled('Edit Alex'));
    expect(recordedHaptics, contains(HapticKind.tap));
    final field = fieldWithHint(WhoIsWhoCopy.theirName);
    expect(field, findsOneWidget);
    expect(tester.widget<TextField>(field).controller!.text, 'Alex');
    await type(tester, field, '   ');
    expect(tester.widget<SkyButton>(find.widgetWithText(SkyButton, WhoIsWhoCopy.save)).enabled, isFalse);
    await press(tester, find.text(WhoIsWhoCopy.save));
    expect(fieldWithHint(WhoIsWhoCopy.theirName), findsOneWidget);

    await type(tester, field, 'Alexa');
    await press(tester, find.text('they / them'));
    await press(tester, find.text(WhoIsWhoCopy.save));
    await until(tester, () => space.identity.partner?.name == 'Alexa');
    await until(tester, () => !space.identity.busy && fieldWithHint(WhoIsWhoCopy.theirName).evaluate().isEmpty);
    await settle(tester);
    expect(fieldWithHint(WhoIsWhoCopy.theirName), findsNothing);
    expect(find.text('Alexa'), findsOneWidget);
    expect(space.identity.partner!.pronoun, 'they');
    expect(find.text('they / them'), findsOneWidget);

    await press(tester, semanticsLabelled('Edit Sam'));
    expect(fieldWithHint(WhoIsWhoCopy.yourName), findsOneWidget);
    await type(tester, fieldWithHint(WhoIsWhoCopy.yourName), 'Samantha');
    await press(tester, find.text(WhoIsWhoCopy.cancel));
    expect(fieldWithHint(WhoIsWhoCopy.yourName), findsNothing);
    expect(space.identity.me!.name, 'Sam');
  });

  testWidgets('"I\'m this one" asks first, then moves this phone', (tester) async {
    calm(tester);
    final space = await openUnlockedSpace(tester);
    await real(tester, () => space.identity.createCouple(myName: 'Sam', partnerName: 'Alex'));
    await pumpWhoIsWho(tester, space);
    await untilFound(tester, find.text('WHO IS WHO'));
    final sam = space.identity.me!.personId;
    final alex = space.identity.partner!.personId;

    await press(tester, find.text(WhoIsWhoCopy.imThisOne));
    expect(find.text('Make this phone Alex?'), findsOneWidget);
    expect(
      find.text(
        'Answers already written on this phone stay with Sam. If your names just look swapped, use “Swap us back” below instead.',
      ),
      findsOneWidget,
    );
    await press(tester, find.text(WhoIsWhoCopy.cancel));
    expect(find.text('Make this phone Alex?'), findsNothing);
    expect(space.identity.me!.personId, sam);

    await press(tester, find.text(WhoIsWhoCopy.imThisOne));
    await press(tester, find.text('Yes, I\'m Alex'));
    await until(tester, () => space.identity.me?.personId == alex);
    await until(tester, () => !space.identity.busy);
    await settle(tester);
    expect(find.text('Make this phone Alex?'), findsNothing);
    expect(space.identity.partner!.personId, sam);
    final chip = find.text(WhoIsWhoCopy.thisPhone);
    final alexRow = find.ancestor(of: find.text('Alex'), matching: find.byKey(ValueKey('row-$alex')));
    expect(find.descendant(of: alexRow, matching: chip), findsOneWidget);
    expect(find.text('Make this phone Sam?'), findsNothing);
  });

  testWidgets('"Swap us back" trades the two places and says so', (tester) async {
    calm(tester);
    final space = await openUnlockedSpace(tester);
    await real(tester, () => space.identity.createCouple(myName: 'Sam', partnerName: 'Alex'));
    await pumpWhoIsWho(tester, space);
    await untilFound(tester, find.text('WHO IS WHO'));
    final before = space.identity.me!.personId;

    await press(tester, find.text(WhoIsWhoCopy.imThisOne));
    expect(find.text('Make this phone Alex?'), findsOneWidget);
    await press(tester, find.text(WhoIsWhoCopy.swappedLink));
    expect(find.text('Make this phone Alex?'), findsNothing);
    expect(find.text(WhoIsWhoCopy.swappedLink), findsNothing);
    expect(find.text(WhoIsWhoCopy.swapTitle), findsOneWidget);
    expect(
      find.textContaining('Sam and Alex trade places, along with which phone is whose. Answers written since '),
      findsOneWidget,
    );
    await press(tester, find.text(WhoIsWhoCopy.cancel));
    expect(find.text(WhoIsWhoCopy.swapTitle), findsNothing);

    await press(tester, find.text(WhoIsWhoCopy.swappedLink));
    recordedHaptics.clear();
    await press(tester, find.text(WhoIsWhoCopy.swapAction));
    await untilFound(tester, find.text(WhoIsWhoCopy.swapped));
    await until(tester, () => !space.identity.busy);
    await settle(tester);
    expect(recordedHaptics, [HapticKind.tick, HapticKind.tap, HapticKind.celebration]);
    expect(find.text(WhoIsWhoCopy.swapTitle), findsNothing);
    expect(
      tester.widget<SkyNotice>(find.ancestor(of: find.text(WhoIsWhoCopy.swapped), matching: find.byType(SkyNotice))).tone,
      SkyNoticeTone.love,
    );
    expect(space.identity.me!.personId, isNot(before));
    expect(space.identity.me!.name, 'Sam');
    expect(space.identity.partner!.personId, before);
    expect(space.identity.partner!.name, 'Alex');

    await press(tester, find.text(WhoIsWhoCopy.swappedLink));
    expect(find.text(WhoIsWhoCopy.swapped), findsNothing);
  });

  testWidgets('a swap that does not work says nothing changed', (tester) async {
    calm(tester);
    final space = await real(tester, openHubSpace);
    final identity = CastIdentity(space, [someone('p-1', 'Sam'), someone('p-2', 'Alex')]);
    addTearDown(identity.dispose);
    await pumpCast(tester, space, identity);

    await press(tester, find.text(WhoIsWhoCopy.swappedLink));
    await press(tester, find.text(WhoIsWhoCopy.swapAction));
    expect(identity.swaps, 1);
    expect(find.text(WhoIsWhoCopy.swapFailed), findsOneWidget);
    expect(
      tester
          .widget<SkyNotice>(find.ancestor(of: find.text(WhoIsWhoCopy.swapFailed), matching: find.byType(SkyNotice)))
          .tone,
      SkyNoticeTone.error,
    );
    expect(find.text(WhoIsWhoCopy.swapTitle), findsOneWidget);
  });

  testWidgets('a crowded space warns instead of offering a swap, and a blank name says so', (tester) async {
    calm(tester);
    final space = await real(tester, openHubSpace);
    final identity = CastIdentity(space, [someone('p-1', ''), someone('p-2', 'Alex'), someone('p-3', 'Kai')]);
    addTearDown(identity.dispose);
    await pumpCast(tester, space, identity);

    expect(find.text(WhoIsWhoCopy.noNameYet), findsOneWidget);
    expect(find.text(WhoIsWhoCopy.tooMany), findsOneWidget);
    expect(find.text(WhoIsWhoCopy.sealed), findsNothing);
    expect(find.text(WhoIsWhoCopy.swappedLink), findsNothing);
    expect(semanticsLabelled('Edit this person'), findsOneWidget);
  });

  testWidgets('sits inside the hub between the mailbox and the QR', (tester) async {
    calm(tester);
    final space = await openUnlockedSpace(tester);
    await real(tester, () => space.identity.createCouple(myName: 'Sam', partnerName: 'Alex'));
    await openHub(tester, space);
    await untilFound(tester, find.text('WHO IS WHO'));
    final whoTop = tester.getTopLeft(find.text('WHO IS WHO')).dy;
    expect(whoTop, greaterThan(tester.getTopLeft(find.text(SyncHubCopy.lastConnected)).dy));
    expect(whoTop, lessThan(tester.getTopLeft(find.text(SyncHubCopy.qrTitle.toUpperCase())).dy));
  });
}
