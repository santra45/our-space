import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/core/engine/crypto/derived_ids.dart';

import 'support/fake_mailbox_worker.dart';
import 'support/harness.dart';

const String passphrase = 'correct horse battery staple 2026';
const String mailboxToken = 'test-token-for-the-mailbox';

class FakePush implements PushPlatform {
  FakePush({this.allowed = false, this.grantOnAsk = true, this.current = 'fid-0001'});

  bool allowed;
  bool grantOnAsk;
  String current;
  int asks = 0;
  int addressCalls = 0;

  final StreamController<String> _changes = StreamController<String>.broadcast();
  final StreamController<void> _rings = StreamController<void>.broadcast();

  @override
  Future<bool> isAllowed() async => allowed;

  @override
  Future<bool> requestPermission() async {
    asks++;
    allowed = grantOnAsk;
    return allowed;
  }

  @override
  Future<String?> address() async {
    addressCalls++;
    _changes.add(current);
    return current;
  }

  @override
  Stream<String> get addressChanges => _changes.stream;

  @override
  Stream<void> get rings => _rings.stream;

  void rotate(String next) {
    current = next;
    _changes.add(next);
  }

  void ring() => _rings.add(null);
}

Future<void> eventually(bool Function() done, {String? reason}) async {
  for (var i = 0; i < 250 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  expect(done(), isTrue, reason: reason);
}

Future<OurSpace> openPushSpace(FakeMailboxWorker worker, {PushPlatform? push}) {
  final dir = Directory.systemTemp.createTempSync('our_space_push_');
  return OurSpace.open(
    databaseFactory: testDatabaseFactory(),
    databasePath: '${dir.path}${Platform.pathSeparator}space.sqlite',
    useEnvironmentMailbox: false,
    mailboxConfig: MailboxConfig.resolve(
      url: 'https://mailbox.example.workers.dev',
      token: mailboxToken,
      origin: 'https://sameskytonight.vercel.app',
    ),
    httpClient: worker,
    autoSync: false,
    pushPlatform: push,
  );
}

Future<void> setUpCouple(OurSpace space) async {
  expect((await space.vault.create(passphrase: passphrase, coupleNames: 'Farhu & Qalbi', iterations: 1000)).ok, isTrue);
  expect(await space.identity.createCouple(myName: 'Farhan', partnerName: 'Qalbi'), isTrue);
}

int pushPuts(FakeMailboxWorker worker) => worker.calls.where((c) => c.startsWith('PUT ') && c.contains('/push/')).length;

void main() {
  late FakeMailboxWorker worker;
  late FakePush push;
  late OurSpace space;

  setUp(() async {
    worker = FakeMailboxWorker(token: mailboxToken);
    push = FakePush();
    space = await openPushSpace(worker, push: push);
  });

  tearDown(() => space.close());

  test('once she knows who she is, the phone asks once and leaves its address', () async {
    expect(worker.pushes, isEmpty);
    await setUpCouple(space);
    await eventually(() => worker.pushes.isNotEmpty, reason: 'registered');

    final mailboxId = deriveMailboxId(space.vault.requireKey());
    final key = worker.pushes.keys.single;
    expect(key.startsWith('push/$mailboxId/${space.identity.myOwnerId}/'), isTrue);
    expect(worker.pushes[key], 'fid-0001');
    expect(push.asks, 1);
    expect(space.store.settings.getItem(pushRegisteredKey), endsWith('|fid-0001'));

    final calls = push.addressCalls;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(push.addressCalls, calls, reason: 'its own echo must not start another round');
    expect(pushPuts(worker), 1);
  });

  test('ordinary changes do not register it again', () async {
    await setUpCouple(space);
    await eventually(() => worker.pushes.isNotEmpty);
    await space.identity.refresh();
    await space.push.check();
    expect(pushPuts(worker), 1);
  });

  test('a new address from Google replaces the old one', () async {
    await setUpCouple(space);
    await eventually(() => worker.pushes.isNotEmpty);
    push.rotate('fid-0002');
    await eventually(() => worker.pushes.values.single == 'fid-0002', reason: 'rotated');
    expect(pushPuts(worker), 2);
  });

  test('turning notifications off takes the address back, without asking again', () async {
    await setUpCouple(space);
    await eventually(() => worker.pushes.isNotEmpty);
    push.allowed = false;
    await space.push.check();
    expect(worker.pushes, isEmpty);
    expect(space.store.settings.getItem(pushRegisteredKey), isNull);
    expect(push.asks, 1);
  });

  test('a ring while the app is open simply syncs', () async {
    await setUpCouple(space);
    await eventually(() => worker.pushes.isNotEmpty);
    worker.calls.clear();
    push.ring();
    await eventually(() => worker.calls.any((c) => c.startsWith('GET ') && c.endsWith('/manifest')), reason: 'synced');
  });

  test('saying no at the first ask leaves nothing behind, and it never nags', () async {
    push.grantOnAsk = false;
    await setUpCouple(space);
    await eventually(() => push.asks == 1);
    await space.push.check();
    await space.push.check();
    expect(worker.pushes, isEmpty);
    expect(push.asks, 1);
  });

  test('without a push platform nothing is registered or asked', () async {
    final quiet = await openPushSpace(worker);
    await setUpCouple(quiet);
    await quiet.push.check();
    expect(quiet.push.available, isFalse);
    expect(worker.calls.where((c) => c.contains('/push/')), isEmpty);
    await quiet.close();
  });
}
