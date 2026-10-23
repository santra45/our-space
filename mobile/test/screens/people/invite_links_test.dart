import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/core/engine/p2p/peer_hub.dart' show pairedPartnerKey;
import 'package:our_space_mobile/presentation/deep_links.dart';
import 'package:our_space_mobile/presentation/home_shell.dart';
import 'package:our_space_mobile/presentation/screens/lock/lock_screen.dart';
import 'package:our_space_mobile/presentation/sky/sky.dart';

import '../lock/lock_harness.dart' show lockField;
import 'people_harness.dart';

const String webOrigin = 'https://sameskytonight.vercel.app';
const String sampleSalt = 'AAECAwQFBgcICQoLDA0ODw==';
const String pasteHint = LockCopy.inviteHint;
const String invitedLine = LockCopy.joinInvited;
const String foundLine = LockCopy.inviteFound;
const String hereLine = LockCopy.inviteHere;

String inviteFor(String? salt, {String peerId = 'love-abc123xyz', String? names}) =>
    buildInviteUrl(peerId, salt, baseUrl: '$webOrigin/', coupleNames: names, startDate: '2021-06-14');

void main() {
  group('reading invite links', () {
    test('the links open on the deployed site, as the web builds them', () {
      expect(inviteLinkHost, 'sameskytonight.vercel.app');
      final link = inviteFor(sampleSalt, names: 'Sam & Alex');
      expect(link, startsWith('$webOrigin/#connect=love-abc123xyz&salt='));

      final invite = inviteFromLink(link)!;
      expect(invite.partnerPeerId, 'love-abc123xyz');
      expect(invite.salt, sampleSalt);
      expect(invite.coupleNames, 'Sam & Alex');
      expect(invite.startDate, '2021-06-14');
      expect(invite.canJoin, isTrue);
    });

    test('anything that is not one of our invite links is left alone', () {
      expect(inviteFromLink(null), isNull);
      expect(inviteFromLink(''), isNull);
      expect(inviteFromLink('$webOrigin/'), isNull);
      expect(inviteFromLink('$webOrigin/#'), isNull);
      expect(inviteFromLink('https://example.com/#connect=love-abc123xyz&salt=$sampleSalt'), isNull);
      expect(inviteFromLink('http://sameskytonight.vercel.app/#connect=love-abc123xyz'), isNull);
      expect(inviteFromLink('love-abc123xyz'), isNull);
      expect(inviteFromLink('$webOrigin/#connect=love-abc123xyz')?.canJoin, isFalse);
    });

    test('the inbox keeps the newest invite and counts each one', () async {
      final links = StreamController<String>();
      final inbox = InviteInbox(links.stream);
      var heard = 0;
      inbox.addListener(() => heard++);

      links.add('$webOrigin/');
      links.add(inviteFor(sampleSalt));
      links.add(inviteFor(null, peerId: 'love-second-one'));
      await pumpEventQueue();

      expect(heard, 2);
      expect(inbox.arrivals, 2);
      expect(inbox.pending?.partnerPeerId, 'love-second-one');
      inbox.consume();
      expect(inbox.pending, isNull);
      expect(inbox.arrivals, 2);
      expect(inbox.deliver('not a link'), isFalse);

      await links.close();
      inbox.dispose();
    });

    test('the phone claims the same address the web shares', () {
      final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(manifest, contains('android:scheme="https" android:host="$inviteLinkHost"'));
      expect(manifest, contains('android.intent.action.VIEW'));
      expect(manifest, contains('android.intent.category.BROWSABLE'));
      expect(manifest, contains('<meta-data android:name="flutter_deeplinking_enabled" android:value="false" />'));
    });
  });

  testWidgets('a cold start from an invite link opens straight into joining', (tester) async {
    calm(tester);
    final partner = await real(tester, openPeopleSpace);
    await real(tester, () => partner.vault.create(passphrase: passphrase, coupleNames: 'Sam & Alex'));
    final link = partner.vault.buildInviteLink(baseUrl: '$webOrigin/')!;

    final launch = StreamController<String>();
    final inbox = InviteInbox(launch.stream);
    final phone = await real(tester, openPeopleSpace);
    await pumpOurSpace(tester, phone, inbox: inbox);
    await untilFound(tester, find.text(LockCopy.setupTitle));

    launch.add(link);
    await tester.pump();
    await tester.pump();

    expect(find.text(LockCopy.joinTitle), findsOneWidget);
    expect(find.text(invitedLine), findsOneWidget);
    expect(find.text(foundLine), findsOneWidget);
    expect(lockField(pasteHint), findsNothing);

    await type(tester, lockField(LockCopy.joinHint), passphrase);
    await press(tester, find.text(LockCopy.joinButton));
    await until(tester, () => phone.vault.isUnlocked);
    await untilFound(tester, find.byType(HomeShell));
    expect(phone.vault.salt, partner.vault.salt);
    expect(phone.vault.config?.coupleNames, 'Sam & Alex');
    expect(inbox.pending, isNull);
    expect(phone.store.settings.getItem(pairedPartnerKey), partner.device.peerId);

    phone.vault.lock();
    await tester.pump();
    await tester.pump();
    expect(find.text('Locked'), findsOneWidget);
    expect(find.text(hereLine), findsNothing);
    await launch.close();
  });

  testWidgets('a link that was already waiting when the app opened is used', (tester) async {
    calm(tester);
    final inbox = InviteInbox()..deliver(inviteFor(sampleSalt));
    final phone = await real(tester, openPeopleSpace);
    await pumpOurSpace(tester, phone, inbox: inbox);
    await untilFound(tester, find.text(invitedLine));
    expect(find.text(foundLine), findsOneWidget);
    expect(lockField(pasteHint), findsNothing);
  });

  testWidgets('a link that arrives while the lock screen is open switches it to joining', (tester) async {
    calm(tester);
    final inbox = InviteInbox();
    final phone = await real(tester, openPeopleSpace);
    await pumpOurSpace(tester, phone, inbox: inbox);
    await untilFound(tester, find.text(LockCopy.setupTitle));

    await press(tester, find.text(LockCopy.segmentJoin));
    await press(tester, find.text(LockCopy.segmentStart));
    await type(tester, lockField(LockCopy.namesHint), 'Half typed');
    expect(find.text(LockCopy.setupTitle), findsOneWidget);

    expect(inbox.deliver(inviteFor(sampleSalt)), isTrue);
    await tester.pump();
    await tester.pump();

    expect(find.text(LockCopy.setupTitle), findsNothing);
    expect(find.text(invitedLine), findsOneWidget);
    expect(find.text(foundLine), findsOneWidget);
    expect(lockField(pasteHint), findsNothing);
  });

  testWidgets('a link that arrives while unlocked closes everything and shows the lock screen', (tester) async {
    calm(tester);
    final inbox = InviteInbox();
    final space = await real(tester, openPeopleSpace);
    await real(tester, () async {
      await space.vault.create(passphrase: passphrase, coupleNames: 'Us two', iterations: fastIterations);
      await space.identity.createCouple(myName: 'Sam', partnerName: 'Alex');
    });
    await pumpOurSpace(tester, space, inbox: inbox);
    await untilFound(tester, find.byType(HomeShell));

    expect(inbox.deliver('$webOrigin/'), isFalse);
    await tester.pump();
    expect(space.vault.isUnlocked, isTrue);

    unawaited(showSkySheet<void>(
      context: tester.element(find.byType(HomeShell)),
      builder: (_) => const Text('A little sheet'),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('A little sheet'), findsOneWidget);

    expect(inbox.deliver(inviteFor('EBESExQVFhcYGRobHB0eHw==')), isTrue);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(space.vault.isUnlocked, isFalse);
    expect(find.text('A little sheet'), findsNothing);
    expect(find.byType(LockScreen), findsOneWidget);
    expect(find.text('Locked'), findsOneWidget);
    expect(find.textContaining(LockCopy.inviteElsewhereLead, findRichText: true), findsOneWidget);
    expect(find.text(hereLine), findsNothing);

    await type(tester, lockField(LockCopy.unlockHint), passphrase);
    await press(tester, find.text(LockCopy.unlockButton));
    await until(tester, () => space.vault.isUnlocked);
    await untilFound(tester, find.byType(HomeShell));
    expect(space.vault.salt, isNot('EBESExQVFhcYGRobHB0eHw=='));
    expect(space.store.settings.getItem(pairedPartnerKey), isNull);

    space.vault.lock();
    await tester.pump();
    await tester.pump();
    expect(find.text('Locked'), findsOneWidget);
    expect(find.textContaining(LockCopy.inviteElsewhereLead, findRichText: true), findsNothing);
  });

  testWidgets('an invite for this same space just says it is here', (tester) async {
    calm(tester);
    final inbox = InviteInbox();
    final space = await real(tester, openPeopleSpace);
    await real(tester, () => space.vault.create(passphrase: passphrase, iterations: fastIterations));
    await settleIdentity(tester, space);
    space.vault.lock();
    await pumpOurSpace(tester, space, inbox: inbox);
    await untilFound(tester, find.text('Locked'));

    inbox.deliver(inviteFor(space.vault.salt));
    await tester.pump();
    await tester.pump();
    expect(find.text('Locked'), findsOneWidget);
    expect(find.text(hereLine), findsOneWidget);

    await type(tester, lockField(LockCopy.unlockHint), passphrase);
    await press(tester, find.text(LockCopy.unlockButton));
    await until(tester, () => space.vault.isUnlocked);
    await untilFound(tester, find.byType(HomeShell));
    expect(space.store.settings.getItem(pairedPartnerKey), 'love-abc123xyz');
    await until(tester, () => space.identity.status != IdentityStatus.loading);
    await settleIdentity(tester, space);
  });
}
