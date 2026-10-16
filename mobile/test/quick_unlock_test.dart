import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';

import 'support/fake_quick_unlock.dart';
import 'support/harness.dart';

const String passphrase = 'correct horse battery staple 2026';

Future<OurSpace> openSpaceWith(QuickUnlockPlatform platform) {
  final dir = Directory.systemTemp.createTempSync('our_space_quick_unlock_');
  return OurSpace.open(
    databaseFactory: testDatabaseFactory(),
    databasePath: '${dir.path}${Platform.pathSeparator}space.sqlite',
    useEnvironmentMailbox: false,
    autoSync: false,
    quickUnlockPlatform: platform,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeQuickUnlock fake;
  late OurSpace space;

  setUp(() async {
    fake = FakeQuickUnlock();
    space = await openSpaceWith(fake);
    final created = await space.vault.create(
      passphrase: passphrase,
      coupleNames: 'Farhu & Qalbi',
      startDate: '2026-09-25',
      iterations: 2000,
    );
    expect(created.ok, isTrue);
    await space.quickUnlock.refresh();
  });

  tearDown(() => space.close());

  test('with no native side present it reports unsupported instead of crashing', () async {
    expect(await const MethodChannelQuickUnlock().availability(), QuickUnlockAvailability.unsupported);
  });

  test('a phone without a fingerprint or face set up does not offer it', () async {
    fake.state = QuickUnlockAvailability.noneEnrolled;
    await space.quickUnlock.refresh();
    expect(space.quickUnlock.available, isFalse);
    expect(space.quickUnlock.offered, isFalse);
  });

  test('turning it on needs the right passphrase, and the key is never stored in the clear', () async {
    expect(space.quickUnlock.available, isTrue);
    expect(space.quickUnlock.enrolled, isFalse);

    final wrong = await space.quickUnlock.enable('this is not the passphrase at all');
    expect(wrong.ok, isFalse);
    expect(wrong.code, 'wrong-passphrase');
    expect(fake.calls, isNot(contains('seal')));

    final on = await space.quickUnlock.enable(passphrase);
    expect(on.ok, isTrue);
    expect(space.quickUnlock.enrolled, isTrue);
    expect(space.quickUnlock.offered, isTrue);

    final stored = space.store.settings.getItem(quickUnlockSettingsKey)!;
    expect(stored.contains(base64.encode(space.vault.requireKey().rawBytes)), isFalse);
    expect(stored.contains(passphrase), isFalse);
    expect(stored.contains(space.vault.salt!), isTrue);
  });

  test('backing out of the setup prompt saves nothing', () async {
    fake.failNext = 'cancelled';
    final result = await space.quickUnlock.enable(passphrase);
    expect(result.code, 'cancelled');
    expect(space.quickUnlock.enrolled, isFalse);
    expect(space.store.settings.getItem(quickUnlockSettingsKey), isNull);
  });

  test('a touch opens the space with the same key and settings', () async {
    final key = space.vault.requireKey().rawBytes;
    expect((await space.quickUnlock.enable(passphrase)).ok, isTrue);
    space.vault.lock();
    expect(space.vault.isUnlocked, isFalse);

    final result = await space.quickUnlock.unlock();
    expect(result.ok, isTrue);
    expect(space.vault.isUnlocked, isTrue);
    expect(space.vault.requireKey().rawBytes, key);
    expect(space.vault.config!.coupleNames, 'Farhu & Qalbi');
    expect(space.vault.config!.startDate, '2026-09-25');
    expect(space.vault.kdfIterations, 2000);
  });

  test('backing out of the unlock prompt changes nothing', () async {
    await space.quickUnlock.enable(passphrase);
    space.vault.lock();
    fake.failNext = 'cancelled';
    final result = await space.quickUnlock.unlock();
    expect(result.code, 'cancelled');
    expect(space.vault.isUnlocked, isFalse);
    expect(space.quickUnlock.enrolled, isTrue);
  });

  test('too many tries keeps it set up and points at the passphrase', () async {
    await space.quickUnlock.enable(passphrase);
    space.vault.lock();
    fake.failNext = 'lockout';
    final result = await space.quickUnlock.unlock();
    expect(result.error, QuickUnlockCopy.didNotWork);
    expect(space.vault.isUnlocked, isFalse);
    expect(space.quickUnlock.enrolled, isTrue);
  });

  test('new fingerprints on the phone mean setting it up again', () async {
    await space.quickUnlock.enable(passphrase);
    space.vault.lock();
    fake.failNext = 'stale';
    final result = await space.quickUnlock.unlock();
    expect(result.error, QuickUnlockCopy.needsSetupAgain);
    expect(space.vault.isUnlocked, isFalse);
    expect(space.quickUnlock.enrolled, isFalse);
    expect(fake.calls.last, 'forget');
    expect(space.store.settings.getItem(quickUnlockSettingsKey), isNull);
  });

  test('a key that does not open this space is thrown away, never adopted', () async {
    await space.quickUnlock.enable(passphrase);
    space.vault.lock();
    fake.openAs = Uint8List(32);
    final result = await space.quickUnlock.unlock();
    expect(result.error, QuickUnlockCopy.needsSetupForNow);
    expect(space.vault.isUnlocked, isFalse);
    expect(space.quickUnlock.enrolled, isFalse);
    expect(fake.holdsKey, isFalse);
  });

  test('a setup saved for another space is not offered, and is cleared when tried', () async {
    await space.quickUnlock.enable(passphrase);
    final record = QuickUnlockRecord.parse(space.store.settings.getItem(quickUnlockSettingsKey))!;
    await space.store.settings.setItem(
      quickUnlockSettingsKey,
      jsonEncode({...record.toJson(), 'vaultSalt': 'c29tZW9uZSBlbHNlcyBzYWx0'}),
    );
    expect(space.quickUnlock.enrolled, isFalse);

    space.vault.lock();
    final result = await space.quickUnlock.unlock();
    expect(result.code, 'stale');
    expect(space.vault.isUnlocked, isFalse);
    expect(space.store.settings.getItem(quickUnlockSettingsKey), isNull);
  });

  test('turning it off forgets the saved key here and on the phone', () async {
    await space.quickUnlock.enable(passphrase);
    await space.quickUnlock.disable();
    expect(space.quickUnlock.enrolled, isFalse);
    expect(fake.holdsKey, isFalse);
    expect(space.store.settings.getItem(quickUnlockSettingsKey), isNull);
  });
}
