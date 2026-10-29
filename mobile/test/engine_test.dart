import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/core/engine/crypto/base64.dart';
import 'package:our_space_mobile/core/engine/crypto/derived_ids.dart';
import 'package:our_space_mobile/core/engine/crypto/js_compat.dart';

import 'support/fake_mailbox_worker.dart';
import 'support/harness.dart';

const String passphrase = 'correct horse battery staple 2026';

Future<OurSpace> openSpace({MailboxConfig? mailbox, FakeMailboxWorker? worker}) async {
  final dir = Directory.systemTemp.createTempSync('our_space_engine_');
  return OurSpace.open(
    databaseFactory: testDatabaseFactory(),
    databasePath: '${dir.path}${Platform.pathSeparator}space.sqlite',
    mailboxConfig: mailbox,
    useEnvironmentMailbox: false,
    httpClient: worker,
    autoSync: false,
  );
}

Future<T> firstWhere<T>(Stream<T> stream, bool Function(T) test) =>
    stream.firstWhere(test).timeout(const Duration(seconds: 10));

class GatedMailboxWorker extends FakeMailboxWorker {
  GatedMailboxWorker({required super.token});

  Completer<void>? gate;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final waiting = gate;
    if (waiting != null) await waiting.future;
    return super.send(request);
  }
}

void main() {
  final fixture = readFixture('web_sealed.json');

  group('vault service', () {
    test('create, lock, unlock and the web error copy', () async {
      final space = await openSpace();
      expect(space.vault.state, VaultCheckState.absent);
      expect(space.vault.isInitialized, isFalse);

      final short = await space.vault.create(passphrase: 'too short');
      expect(short.ok, isFalse);
      expect(short.error, 'Passphrase must be at least 16 characters long.');

      final nothing = await space.vault.unlock(passphrase);
      expect(nothing.error, 'There is nothing here yet. Start your space, or join your partner’s.');

      final created = await space.vault.create(
        passphrase: passphrase,
        coupleNames: '  Sam & Alex  ',
        startDate: '2021-06-14',
      );
      expect(created.ok, isTrue);
      expect(space.vault.isUnlocked, isTrue);
      expect(space.vault.config!.coupleNames, 'Sam & Alex');
      expect(space.vault.config!.startDate, '2021-06-14');
      expect(space.vault.isInitialized, isTrue);

      space.vault.lock();
      expect(space.vault.isUnlocked, isFalse);
      expect(space.vault.config, isNull);
      expect(() => space.vault.requireKey(), throwsA(isA<StoreError>()));

      final wrong = await space.vault.unlock('this is not the passphrase at all');
      expect(wrong.error, 'Incorrect passphrase! Please double-check and try again.');

      final again = await space.vault.unlock('  $passphrase  ');
      expect(again.ok, isTrue);
      expect(space.vault.config!.coupleNames, 'Sam & Alex');

      final replace = await space.vault.create(passphrase: passphrase);
      expect(replace.ok, isFalse);
      expect(replace.code, 'needs_confirmation');
      expect(
        replace.error,
        'There is already a space on this phone. Replacing it would make everything in it impossible to open again, so we need you to confirm.',
      );

      final settings = await space.vault.updateSettings(startDate: '2020-02-02');
      expect(settings.ok, isTrue);
      expect(space.vault.config!.startDate, '2020-02-02');
      expect(space.vault.config!.coupleNames, 'Sam & Alex');
      space.vault.lock();
      await space.vault.unlock(passphrase);
      expect(space.vault.config!.startDate, '2020-02-02');

      await space.close();
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('joining from a web invite link verifies the passphrase with its canary', () async {
      final invites = asStringMap(fixture['invites'])!;
      final built = (invites['built'] as List).cast<Map>();
      final withProof = parseInvite(built[1]['url'])!;
      final withoutProof = parseInvite(built[0]['url'])!;
      expect(withProof.canary, isNotNull);

      final space = await openSpace();
      final mismatch = await space.vault.joinFromInvite(
        passphrase: 'definitely the wrong passphrase',
        invite: withProof,
      );
      expect(mismatch.ok, isFalse);
      expect(
        mismatch.error,
        'That passphrase does not match your partner’s. Check it together, character for character, and try again.',
      );

      final joined = await space.vault.joinFromInvite(passphrase: fixture['passphrase'] as String, invite: withProof);
      expect(joined.ok, isTrue);
      expect(joined.warning, isNull);
      expect(bufferToBase64(space.vault.requireKey().rawBytes), fixture['keyBits']);
      expect(space.vault.config!.coupleNames, 'Sam + Alex = us/2');
      expect(space.vault.salt, fixture['salt']);
      final meta = (await space.store.getVaultMeta())!;
      expect(meta['updatedAt'], 0);

      final second = await openSpace();
      final unverified = await second.vault.joinFromInvite(
        passphrase: fixture['passphrase'] as String,
        invite: withoutProof,
      );
      expect(unverified.ok, isTrue);
      expect(
        unverified.warning,
        'Paired! We will know your passphrases match the moment your phones connect — if they do not, we will tell you instead of syncing.',
      );
      expect(bufferToBase64(second.vault.requireKey().rawBytes), fixture['keyBits']);

      final bad = await second.vault.joinFromInvite(passphrase: fixture['passphrase'] as String, invite: null);
      expect(bad.error, 'Please paste your partner’s invite link — the one they sent you, or the QR code you scanned.');

      await space.close();
      await second.close();
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('repositories', () {
    late OurSpace space;

    setUpAll(() async {
      space = await openSpace();
      await space.vault.create(passphrase: passphrase, startDate: '2021-06-14');
    });

    tearDownAll(() async {
      await space.close();
    });

    test('streams re-emit on writes and go empty when locked', () async {
      final stream = space.milestones.watch();
      final emitted = <TableSnapshot<MilestoneRecord>>[];
      final sub = stream.listen(emitted.add);
      await firstWhere(space.milestones.watch(), (s) => s.unlocked);
      await space.milestones.add(title: 'First date', date: '2021-06-14');
      await space.milestones.add(title: 'Moved in', date: '2024-01-01');
      final latest = await firstWhere(space.milestones.watch(), (s) => s.items.length == 2);
      expect(latest.items.first.title, 'Moved in');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(emitted.any((s) => s.items.length == 2), isTrue);

      final first = latest.items.last;
      await space.milestones.update(first, title: 'Our first date', date: '2021-06-15');
      await space.milestones.delete(latest.items.first.id);
      final after = await space.milestones.list();
      expect(after.map((m) => m.title).toList(), ['Our first date']);

      final locked = firstWhere(space.milestones.watch().skip(1), (s) => !s.unlocked);
      space.vault.lock();
      final snapshot = await locked;
      expect(snapshot.items, isEmpty);
      expect((await space.vault.unlock(passphrase)).ok, isTrue);
      expect((await space.milestones.list()).length, 1);
      await sub.cancel();
    });

    test('photos are sealed, listed without bytes, and open on demand', () async {
      final photo = utf8.encode('a pretend photo, compressed already' * 100);
      final row = await space.memories.add(photo: photo, mime: 'image/jpeg', date: '2026-02-14', caption: '  ');
      expect(row['imageBlob'], isNotNull);
      final items = await space.memories.list();
      expect(items.single.caption, 'Precious moment 💕');
      expect(items.single.hasPhoto, isTrue);
      expect(items.single.mime, 'image/jpeg');
      expect(await space.memories.loadPhoto(items.single.id), photo);
      expect(PhotoTooLargeError(10 * 1024 * 1024).message, contains('over the 9MB limit'));
    });

    test('letters seal future dates, open past ones and refuse to open early', () async {
      await space.letters.writeLetter(title: 'Now', content: 'open me now');
      await space.letters.writeLetter(title: 'Later', content: 'not yet', unlockDate: '2099-12-31');
      await space.letters.writeLetter(title: 'Past', content: 'sealed then opened', unlockDate: '2020-01-01');
      final letters = await space.letters.list();
      expect(letters.length, 3);
      final later = letters.firstWhere((l) => l.title == 'Later');
      expect(later.isSealed, isTrue);
      expect(later.content, isNull);
      expect(later.isLocked, isTrue);
      final opening = space.letters.open(later);
      expect(opening.isOpen, isFalse);
      expect(opening.tone, LetterNoticeTone.lock);
      expect(opening.notice, startsWith('"Later" is sealed until Dec 31, 2099 - '));
      expect(opening.notice, endsWith('💕 We will not open it early.'));

      final past = letters.firstWhere((l) => l.title == 'Past');
      expect(space.letters.open(past).content, 'sealed then opened');
      final now = letters.firstWhere((l) => l.title == 'Now');
      expect(space.letters.open(now).content, 'open me now');

      await space.letters.markOpened(now.id);
      final reopened = (await space.letters.list()).firstWhere((l) => l.id == now.id);
      expect(reopened.isOpened, isTrue);
      expect(reopened.openedAt, isNotNull);
    });

    test('a plain letter with a future date is sealed by the upgrade pass', () async {
      final key = space.vault.requireKey();
      await space.store.putEncrypted(lettersTable, {
        'id': 'let-legacy',
        'title': 'Legacy',
        'unlockDate': '2099-01-01',
        'content': 'written before sealing existed',
        'createdAt': 1,
        'updatedAt': 2,
        'deleted': false,
      }, key);
      final sealed = await space.letters.upgradePendingLocks(await space.letters.list());
      expect(sealed, 1);
      final plain = (await space.store.getDecrypted(lettersTable, 'let-legacy', key))!;
      expect(plain.containsKey('content'), isFalse);
      expect(plain['sealedContent'], isA<Map>());
    });

    test('the bucket list seeds once and orders like the web', () async {
      expect(await space.bucketList.seedDefaultsIfEmpty(), isTrue);
      expect(await space.bucketList.seedDefaultsIfEmpty(), isFalse);
      var items = await space.bucketList.list();
      expect(items.length, 6);
      expect(items.first.id, 'bkt-default-1');
      await space.bucketList.toggleComplete(items.first);
      await space.bucketList.add(text: '  See the northern lights  ', category: 'Travel');
      items = await space.bucketList.list();
      expect(items.last.id, 'bkt-default-1');
      expect(items.last.completed, isTrue);
      expect(items.any((i) => i.text == 'See the northern lights'), isTrue);
      await space.bucketList.edit(items.last, text: 'Sunrise again', category: 'Romance');
      expect((await space.bucketList.list()).last.text, 'Sunrise again');
    });

    test('roulette state and love bursts', () async {
      expect(await space.roulette.current(), isNull);
      await space.roulette.persist(ideaId: 'd5', category: 'food', revealed: true);
      final state = (await space.roulette.current())!;
      expect(state.ideaId, 'd5');
      expect(findDateIdea(defaultDateIdeas, state.ideaId)!.title, 'Homemade Pasta Cooking Battle');
      expect(dateIdeasIn(defaultDateIdeas, 'food').length, 3);

      expect(await space.sync.sendLoveBurst(), isTrue);
      expect(space.sync.lastNotice, 'Saved 💕 your partner will see it the moment you two connect.');
    });

    test('date ideas start with the ten built in ones and take our own', () async {
      await space.roulette.persist(ideaId: 'd5', category: 'food', revealed: true);
      var snapshot = await space.dateIdeas.load();
      expect(snapshot.items.map((idea) => idea.id), defaultDateIdeas.map((idea) => idea.id));
      expect(snapshot.unreadable, 0);
      expect(await space.store.countLive(dateIdeasTable), 1);

      await space.dateIdeas.add(title: '  Cook the same dinner on a call  ', desc: ' Two kitchens ', category: 'food');
      snapshot = await space.dateIdeas.load();
      final ours = snapshot.items.last;
      expect(snapshot.items, hasLength(11));
      expect(ours.id, startsWith('date-'));
      expect(ours.title, 'Cook the same dinner on a call');
      expect(ours.desc, 'Two kitchens');
      expect(ours.category, 'food');
      expect(dateIdeasIn([for (final idea in snapshot.items) idea.idea], 'food'), hasLength(4));

      final third = snapshot.items[2];
      await space.dateIdeas.edit(third, title: 'Blind taste test, chai edition', desc: '', category: 'budget');
      snapshot = await space.dateIdeas.load();
      expect(snapshot.items[2].id, 'd3');
      expect(snapshot.items[2].title, 'Blind taste test, chai edition');
      expect(snapshot.items[2].category, 'budget');
      expect(snapshot.items, hasLength(11));

      expect(await space.dateIdeas.edit(ours, title: '   ', desc: 'x', category: 'food'), isNull);
      expect(await space.dateIdeas.remove(rouletteStateId), isNull);
      expect((await space.roulette.current())?.ideaId, 'd5');
    });

    test('removing a date idea keeps it gone, built in or our own', () async {
      await space.dateIdeas.add(title: 'Paint each other badly', desc: '', category: 'athome');
      var items = await space.dateIdeas.list();
      final ours = items.last;
      final before = items.length;

      await space.dateIdeas.remove('d1');
      await space.dateIdeas.remove('d3');
      await space.dateIdeas.remove(ours.id);
      items = await space.dateIdeas.list();
      expect(items.map((idea) => idea.id), isNot(contains('d1')));
      expect(items.map((idea) => idea.id), isNot(contains('d3')));
      expect(items.map((idea) => idea.id), isNot(contains(ours.id)));
      expect(items, hasLength(before - 3));
      expect(items.first.id, 'd2');

      final tombstone = await space.store.getRow(dateIdeasTable, 'd1');
      expect(tombstone?['deleted'], isTrue);
      expect((await space.store.getRow(dateIdeasTable, ours.id))?['deleted'], isTrue);
    });

    test('date idea text is trimmed and kept to a sane length', () async {
      await space.dateIdeas.add(title: 'a' * 500, desc: 'b' * 2000, category: 'outdoor');
      final ours = (await space.dateIdeas.list()).last;
      expect(ours.title.length, dateIdeaTitleLimit * 4);
      expect(ours.desc.length, dateIdeaDescLimit * 4);
      expect(await space.dateIdeas.add(title: '  ', desc: 'nothing', category: 'outdoor'), isNull);
    });

    test('backups export and re-import cleanly', () async {
      final file = await space.backup.exportBackup(passphrase);
      final container = space.backup.parseBackupFile(file.contents);
      final preview = await space.backup.previewImport(container, passphrase);
      expect(preview.relation, 'same');
      expect(preview.plan.totals.stale + preview.plan.totals.invalid, greaterThan(0));
      expect(await space.backup.applyImport(preview), startsWith('Added 0 things.'));
      await expectLater(space.backup.exportBackup('not the vault passphrase!'), throwsA(isA<BackupFailure>()));
      expect(() => space.backup.parseBackupFile('not json'), throwsA(isA<BackupFailure>()));
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('presence', () {
    test('unlocking the space marks me active again without waiting for something to be written', () async {
      var nowMs = 1760000000000;
      final dir = Directory.systemTemp.createTempSync('our_space_presence_');
      final space = await OurSpace.open(
        databaseFactory: testDatabaseFactory(),
        databasePath: '${dir.path}${Platform.pathSeparator}space.sqlite',
        useEnvironmentMailbox: false,
        autoSync: false,
        now: () => nowMs,
      );
      expect((await space.vault.create(passphrase: passphrase)).ok, isTrue);
      expect(await space.identity.createCouple(myName: 'Farhan', partnerName: 'Qalbi'), isTrue);
      final before = space.identity.me!.lastActiveAt;
      expect(before, isNotNull);

      space.vault.lock();
      nowMs += 10 * 60 * 1000;
      expect((await space.vault.unlock(passphrase)).ok, isTrue);
      for (var i = 0; i < 100 && space.identity.me?.lastActiveAt != nowMs; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(space.identity.me!.lastActiveAt, nowMs);
      await space.close();
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('mailbox status', () {
    test('a mailbox the phone cannot get into shows as failed, not ok', () async {
      final worker = FakeMailboxWorker(token: 'the-token-the-worker-knows');
      final space = await openSpace(
        mailbox: MailboxConfig.resolve(
          url: 'https://mailbox.example.workers.dev',
          token: 'a-token-that-was-rotated',
          origin: 'https://sameskytonight.vercel.app',
        ),
        worker: worker,
      );
      expect((await space.vault.create(passphrase: passphrase)).ok, isTrue);

      final status = await space.sync.syncNow();
      expect(status.state, MailboxRunState.failed);
      expect(status.failure, 'unauthorized');
      await space.close();
    });

    test('a sync asked for while one is running runs right after it, instead of being dropped', () async {
      const token = 'the-token-the-worker-knows';
      final worker = GatedMailboxWorker(token: token);
      final space = await openSpace(
        mailbox: MailboxConfig.resolve(
          url: 'https://mailbox.example.workers.dev',
          token: token,
          origin: 'https://sameskytonight.vercel.app',
        ),
        worker: worker,
      );
      expect((await space.vault.create(passphrase: passphrase)).ok, isTrue);

      worker.gate = Completer<void>();
      final running = space.sync.syncNow('first');
      final asked = await space.sync.syncNow('local-write');
      expect(asked.state, MailboxRunState.syncing);

      final gate = worker.gate!;
      worker.gate = null;
      gate.complete();
      final done = await running;
      expect(done.state, MailboxRunState.ok);
      expect(done.reason, 'local-write');
      expect(worker.calls.where((c) => c.endsWith('/manifest')).length, 4);
      await space.close();
    });
  });

  group('end to end with the web mailbox', () {
    test('a phone joins from the web invite, collects, claims a person and publishes back', () async {
      final box = asStringMap(fixture['mailbox'])!;
      final config = asStringMap(box['config'])!;
      final worker = FakeMailboxWorker.fromKvDump(asStringMap(box['kv'])!, token: config['token'] as String);
      final space = await openSpace(
        mailbox: MailboxConfig.resolve(
          url: config['url'] as String,
          token: config['token'] as String,
          origin: box['origin'] as String,
        ),
        worker: worker,
      );
      final built = (asStringMap(fixture['invites'])!['built'] as List).cast<Map>();
      final joined = await space.vault.joinFromInvite(
        passphrase: fixture['passphrase'] as String,
        invite: parseInvite(built[1]['url']),
      );
      expect(joined.ok, isTrue);

      final status = await space.sync.syncNow();
      expect(status.state, MailboxRunState.ok);
      expect(status.applied, greaterThan(10));
      expect(space.sync.lastNotice, contains('new things from'));

      await space.identity.refresh();
      expect(space.identity.status, IdentityStatus.unclaimed);
      expect(space.identity.everyone.map((p) => p.name).toList()..sort(), ['Alex', 'Sam']);

      final slots = derivePersonSlots(space.vault.requireKey());
      expect(await space.identity.claimPerson(slots[1]), isTrue);
      expect(space.identity.status, IdentityStatus.ready);
      expect(space.identity.me!.name, 'Alex');
      expect(space.identity.partnerName, 'Sam');
      expect(space.identity.partnerPossessive, "Sam's");

      final memories = await space.memories.list();
      expect(memories.length, 2);
      expect(await space.memories.loadPhoto('mem-interop-1'), base64ToBuffer(asStringMap(fixture['blob'])!['plain']));
      final letters = await space.letters.list();
      expect(
        space.letters.open(letters.firstWhere((l) => l.id == 'let-interop-past')).content,
        'This one was sealed until 2020.',
      );
      final question = space.dailyQuestion.questionForDay(space.vault.requireKey(), 1760000000000);
      expect(question.question.id, isNotEmpty);

      worker.calls.clear();
      final back = await space.sync.syncNow();
      expect(back.state, MailboxRunState.ok);
      expect(back.uploaded, greaterThan(0));
      final mailboxId = deriveMailboxId(space.vault.requireKey());
      expect(worker.calls.last, 'PUT /m/$mailboxId/${slots[1]}/manifest');
      expect(worker.kvDump().containsKey('$mailboxId/${slots[1]}/manifest'), isTrue);

      final bursts = await space.sync.checkLoveBursts();
      expect(bursts, 0);
      await space.close();
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
