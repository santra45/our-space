import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/core/engine/crypto/base64.dart';
import 'package:our_space_mobile/core/engine/crypto/kdf.dart';
import 'package:our_space_mobile/core/engine/storage/vault_store.dart';
import 'package:our_space_mobile/core/engine/sync/away_feed.dart' show awayFeedLimit;

import 'support/fake_mailbox_worker.dart';
import 'support/harness.dart';

const String token = 'test-token-for-the-mailbox';
const String hisBox = 'his-person-mailbox';
const String herBox = 'her-person-mailbox';

Mailbox mailboxFor(VaultStore store, FakeMailboxWorker worker) => Mailbox(
      store: store,
      config: MailboxConfig.resolve(
        url: 'https://mailbox.example.workers.dev',
        token: token,
        origin: 'https://sameskytonight.vercel.app',
      ),
      client: worker,
    );

Future<void> drain() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  late VaultKey key;
  late VaultStore his;
  late VaultStore her;
  late FakeMailboxWorker worker;
  late AwayFeed feed;
  var clock = 1760000000000;

  setUp(() async {
    key = await deriveKeyFromPassphrase('my-super-secret-couple-passphrase-2026', generateSalt(), iterations: 2000);
    his = await openTestStore();
    her = await openTestStore();
    worker = FakeMailboxWorker(token: token);
    feed = AwayFeed(store: her, key: () => key, myOwnerIds: () => {herBox}, myBurstId: () => 'burst-her');
  });

  tearDown(() async {
    feed.dispose();
    await his.close();
    await her.close();
  });

  Future<void> hisWrites(String table, Map<String, Object?> fields) =>
      his.putEncrypted(table, {...fields, 'updatedAt': clock += 1000}, key);

  Future<void> arrivesOverTheLink(String table, String id) async {
    final row = await his.getRow(table, id);
    await her.commitIncomingRows([IncomingRow(table, row!)]);
    await drain();
  }

  Future<void> arrivesByMailbox({bool fromPartner = true}) async {
    expect((await mailboxFor(his, worker).publish(key: key, ownerId: hisBox)).ok, isTrue);
    await mailboxFor(her, worker).collect(key: key, partnerId: hisBox, fromPartner: fromPartner);
    await drain();
  }

  test('a letter from the other phone shows up by name, but not one collected from her own slot', () async {
    await hisWrites(lettersTable, {'id': 'let-own', 'title': 'Mine', 'content': 'from me'});
    await arrivesByMailbox(fromPartner: false);
    expect(feed.entries, isEmpty);

    await hisWrites(lettersTable, {'id': 'let-his', 'title': 'Hello', 'content': 'from him'});
    await arrivesByMailbox();
    expect(feed.entries, hasLength(1));
    final entry = feed.entries.single;
    expect(entry.kind, AwayKind.letter);
    expect(entry.recordId, 'let-his');
    expect(entry.read, isFalse);
    expect(feed.unread, 1);
  });

  test('her letter being read shows up only on the phone that wrote it', () async {
    await her.putEncrypted(lettersTable, {'id': 'let-hers', 'title': 'For you', 'content': 'x', 'updatedAt': clock += 1000}, key);
    final row = await her.getRow(lettersTable, 'let-hers');
    await his.commitIncomingRows([IncomingRow(lettersTable, row!)]);
    final opened = await his.getDecrypted(lettersTable, 'let-hers', key);
    await hisWrites(lettersTable, {...opened!, 'isOpened': true, 'openedAt': clock});

    await arrivesOverTheLink(lettersTable, 'let-hers');
    expect(feed.entries, isEmpty);

    await her.putEncrypted(lettersTable, {'id': 'let-two', 'title': 'Again', 'content': 'y', 'updatedAt': clock += 1000}, key);
    await her.settings.setItem('lettersWrittenHere', '["let-hers","let-two"]');
    final second = await her.getRow(lettersTable, 'let-two');
    await his.commitIncomingRows([IncomingRow(lettersTable, second!)]);
    final read = await his.getDecrypted(lettersTable, 'let-two', key);
    await hisWrites(lettersTable, {...read!, 'isOpened': true, 'openedAt': clock});
    await arrivesOverTheLink(lettersTable, 'let-two');
    expect(feed.entries.single.kind, AwayKind.opened);
    expect(feed.entries.single.recordId, 'let-two');
  });

  test('polaroids that come in together share one line until she has seen it', () async {
    await hisWrites(memoriesTable, {'id': 'mem-1', 'date': '2026-11-10', 'caption': 'Titanic'});
    await arrivesOverTheLink(memoriesTable, 'mem-1');
    await hisWrites(memoriesTable, {'id': 'mem-2', 'date': '2026-11-11', 'caption': 'After'});
    await arrivesOverTheLink(memoriesTable, 'mem-2');
    expect(feed.entries, hasLength(1));
    expect(feed.entries.single.kind, AwayKind.polaroid);
    expect(feed.entries.single.count, 2);
    expect(feed.entries.single.recordId, 'mem-1');

    feed.markRead(feed.entries.single.id);
    expect(feed.unread, 0);
    await hisWrites(memoriesTable, {'id': 'mem-3', 'date': '2026-11-12', 'caption': 'Later'});
    await arrivesOverTheLink(memoriesTable, 'mem-3');
    expect(feed.entries, hasLength(2));
    expect(feed.entries.first.count, 1);

    final edited = await his.getDecrypted(memoriesTable, 'mem-3', key);
    await hisWrites(memoriesTable, {...edited!, 'caption': 'Changed my mind'});
    await arrivesOverTheLink(memoriesTable, 'mem-3');
    expect(feed.entries, hasLength(2));
  });

  test('a new dream and a dream ticked off are told apart, and plain edits or removals say nothing', () async {
    await hisWrites(bucketListTable, {'id': 'b-1', 'text': 'See the sea', 'completed': false});
    await arrivesOverTheLink(bucketListTable, 'b-1');
    expect(feed.entries.single.kind, AwayKind.dream);

    final first = await his.getDecrypted(bucketListTable, 'b-1', key);
    await hisWrites(bucketListTable, {...first!, 'text': 'See the sea together'});
    await arrivesOverTheLink(bucketListTable, 'b-1');
    expect(feed.entries, hasLength(1));

    final second = await his.getDecrypted(bucketListTable, 'b-1', key);
    await hisWrites(bucketListTable, {...second!, 'completed': true, 'completedAt': clock});
    await arrivesOverTheLink(bucketListTable, 'b-1');
    expect(feed.entries.first.kind, AwayKind.done);

    await his.softDelete(bucketListTable, 'b-1', key);
    await arrivesOverTheLink(bucketListTable, 'b-1');
    expect(feed.entries, hasLength(2));
  });

  test("his answer to today's question shows once, and her own never does", () async {
    final today = dayKey(her.now());
    await hisWrites(dailyAnswersTable, {
      'id': 'ans-his',
      'ownerId': hisBox,
      'month': today.substring(0, 7),
      'answers': {
        today: {'questionId': 'q1', 'text': 'You', 'answeredAt': clock},
      },
    });
    await arrivesOverTheLink(dailyAnswersTable, 'ans-his');
    expect(feed.entries.single.kind, AwayKind.answer);

    final again = await his.getDecrypted(dailyAnswersTable, 'ans-his', key);
    await hisWrites(dailyAnswersTable, {...again!, 'note': 'touched'});
    await arrivesOverTheLink(dailyAnswersTable, 'ans-his');
    expect(feed.entries, hasLength(1));

    await hisWrites(dailyAnswersTable, {
      'id': 'ans-hers',
      'ownerId': herBox,
      'month': today.substring(0, 7),
      'answers': {
        today: {'questionId': 'q1', 'text': 'Me', 'answeredAt': clock},
      },
    });
    await arrivesOverTheLink(dailyAnswersTable, 'ans-hers');
    expect(feed.entries, hasLength(1));
  });

  test('love counts only what was added, never her own, and countdowns get their own line', () async {
    await hisWrites(loveBurstsTable, {'id': 'burst-his', 'count': 1, 'lastSentAt': clock});
    await arrivesOverTheLink(loveBurstsTable, 'burst-his');
    await hisWrites(loveBurstsTable, {'id': 'burst-his', 'count': 3, 'lastSentAt': clock});
    await arrivesOverTheLink(loveBurstsTable, 'burst-his');
    expect(feed.entries.single.kind, AwayKind.love);
    expect(feed.entries.single.count, 3);

    await hisWrites(loveBurstsTable, {'id': 'burst-her', 'count': 9, 'lastSentAt': clock});
    await arrivesOverTheLink(loveBurstsTable, 'burst-her');
    expect(feed.entries, hasLength(1));

    await hisWrites(milestonesTable, {'id': 'ms-1', 'title': 'Flight', 'date': '2026-12-20'});
    await arrivesOverTheLink(milestonesTable, 'ms-1');
    expect(feed.entries.first.kind, AwayKind.countdown);
  });

  test('the list survives a restart, can be marked read or cleared, and never grows past its limit', () async {
    final heard = <AwayEntry>[];
    final sub = feed.arrivals.listen(heard.add);
    for (var i = 0; i < awayFeedLimit + 5; i++) {
      await hisWrites(i.isEven ? lettersTable : bucketListTable, {
        'id': 'row-$i',
        'title': 't',
        'content': 'c',
        'text': 't',
        'completed': false,
      });
      await arrivesOverTheLink(i.isEven ? lettersTable : bucketListTable, 'row-$i');
      if (feed.entries.isNotEmpty) feed.markRead(feed.entries.first.id);
    }
    await sub.cancel();
    expect(heard, hasLength(awayFeedLimit + 5));
    expect(feed.entries, hasLength(awayFeedLimit));

    final reopened = AwayFeed(store: her, key: () => key, myOwnerIds: () => {herBox}, myBurstId: () => 'burst-her');
    expect(reopened.entries.map((e) => e.id), feed.entries.map((e) => e.id));
    expect(reopened.unread, 0);

    await hisWrites(lettersTable, {'id': 'row-last', 'title': 't', 'content': 'c'});
    await arrivesOverTheLink(lettersTable, 'row-last');
    expect(feed.unread, 1);
    feed.markAllRead();
    expect(feed.unread, 0);
    feed.clear();
    expect(feed.entries, isEmpty);
    reopened.dispose();
    final empty = AwayFeed(store: her, key: () => key, myOwnerIds: () => {herBox}, myBurstId: () => 'burst-her');
    expect(empty.entries, isEmpty);
    empty.dispose();
  });

  test('nothing is read while the vault is locked', () async {
    final locked = AwayFeed(store: her, key: () => null, myOwnerIds: () => {herBox}, myBurstId: () => 'burst-her');
    feed.dispose();
    feed = locked;
    await hisWrites(lettersTable, {'id': 'let-x', 'title': 'Hi', 'content': 'there'});
    await arrivesOverTheLink(lettersTable, 'let-x');
    expect(locked.entries, isEmpty);
  });

  group('the ring word', () {
    test('the manifest carries the most telling kind, falls back to the plain ring, and is kept when the PUT fails', () async {
      await hisWrites(lettersTable, {'id': 'let-1', 'title': 'a', 'content': 'b'});
      his.ringNotes.note('love');
      his.ringNotes.note('letter');
      his.ringNotes.note('nonsense');
      expect((await mailboxFor(his, worker).publish(key: key, ownerId: hisBox)).ok, isTrue);
      expect(worker.manifestRings, ['$hisBox/letter']);
      expect(worker.calls.last, endsWith('/manifest'));
      expect(his.ringNotes.next, isNull);

      await hisWrites(lettersTable, {'id': 'let-2', 'title': 'a', 'content': 'b'});
      expect((await mailboxFor(his, worker).publish(key: key, ownerId: hisBox)).ok, isTrue);
      expect(worker.manifestRings.last, '$hisBox/mailbox');

      await hisWrites(lettersTable, {'id': 'let-3', 'title': 'a', 'content': 'b'});
      his.ringNotes.note('dream');
      worker.offline = true;
      expect((await mailboxFor(his, worker).publish(key: key, ownerId: hisBox)).ok, isFalse);
      expect(his.ringNotes.next, 'dream');
      worker.offline = false;
      expect((await mailboxFor(his, worker).publish(key: key, ownerId: hisBox)).ok, isTrue);
      expect(worker.manifestRings.last, '$hisBox/dream');
    });

    test('a read letter rings only when she has said yes to it', () async {
      final notes = RingNotes(her.settings);
      notes.note('opened');
      expect(notes.next, isNull);
      await notes.setTellsOpened(true);
      expect(notes.tellsOpened, isTrue);
      notes.note('opened');
      notes.note('love');
      expect(notes.next, 'opened');
      expect(notes.take(), {'opened', 'love'});
      expect(notes.next, isNull);
      await notes.setTellsOpened(false);
      expect(her.settings.getItem('our_space_ring_opened'), isNull);
    });
  });

  test('each place that writes something for the other phone leaves its ring word', () async {
    final dir = Directory.systemTemp.createTempSync('our_space_ring_');
    final space = await OurSpace.open(
      databaseFactory: testDatabaseFactory(),
      databasePath: '${dir.path}${Platform.pathSeparator}space.sqlite',
      useEnvironmentMailbox: false,
      autoSync: false,
      peerToPeer: false,
    );
    expect(
      (await space.vault.create(passphrase: 'correct horse battery staple 2026', coupleNames: 'Sam & Alex', iterations: 1000)).ok,
      isTrue,
    );
    final rings = space.store.ringNotes;

    final letter = await space.letters.writeLetter(title: 'Hi', content: 'Hello');
    expect(rings.take(), {'letter'});
    await space.letters.markOpened(letter!['id'] as String);
    expect(rings.take(), isEmpty);
    await rings.setTellsOpened(true);
    final other = await space.letters.writeLetter(title: 'Hi', content: 'Again');
    rings.take();
    await space.letters.markOpened(other!['id'] as String);
    expect(rings.take(), {'opened'});

    await space.bucketList.add(text: 'See the sea', category: 'travel');
    expect(rings.take(), {'dream'});
    final dream = (await space.bucketList.list()).single;
    await space.bucketList.toggleComplete(dream);
    expect(rings.take(), {'done'});
    final done = (await space.bucketList.list()).single;
    await space.bucketList.toggleComplete(done);
    expect(rings.take(), isEmpty);

    await space.loveBursts.sendLoveBurst(space.vault.key);
    expect(rings.take(), {'love'});

    await space.dailyQuestion.saveAnswer(space.vault.key, ownerId: 'owner-sam1', questionId: 'q1', text: 'You');
    expect(rings.take(), {'answer'});

    await space.close();
  });
}
