import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine/storage/local_settings.dart';
import 'package:our_space_mobile/presentation/screens/memories/memory_marks.dart';

String idAt(int millis, [String nonce = 'abc-_9']) => 'mem-${millis.toRadixString(36)}-$nonce';

void main() {
  group('createdAt', () {
    test('reads the moment hidden in a memory id', () {
      expect(MemoryMarks.createdAt(idAt(1729000000000)), 1729000000000);
      expect(MemoryMarks.createdAt(idAt(1729000000000, 'a-b-c')), 1729000000000);
      expect(MemoryMarks.createdAt('mem--abc'), isNull);
      expect(MemoryMarks.createdAt('memory-1'), isNull);
      expect(MemoryMarks.createdAt('mem-zz!-abc'), isNull);
      expect(MemoryMarks.createdAt(''), isNull);
    });
  });

  group('MemoryMarks', () {
    late int now;
    late LocalSettings settings;

    MemoryMarks marks() => MemoryMarks(settings, now: () => now);

    setUp(() {
      now = 1000000;
      settings = LocalSettings.memory();
    });

    test('treats everything before it started watching as history', () {
      final m = marks();
      final older = idAt(999000);
      expect(m.tracking, isFalse);
      expect(m.isNew(older), isFalse);
      expect(m.authorOf(older), MemoryAuthor.unknown);

      m.start();
      expect(m.tracking, isTrue);
      expect(m.since, 1000000);
      expect(m.isNew(older), isFalse);
      expect(m.authorOf(older), MemoryAuthor.unknown);
      expect(m.authorOf('legacy-id'), MemoryAuthor.unknown);

      now = 2000000;
      m.start();
      expect(m.since, 1000000);
    });

    test('memories that arrive later are from the partner and new until seen', () {
      final m = marks()..start();
      final arrival = idAt(1500000);
      expect(m.isNew(arrival), isTrue);
      expect(m.authorOf(arrival), MemoryAuthor.partner);
      expect(m.authorOf(arrival, knowsPartner: false), MemoryAuthor.unknown);

      m.markSeen([arrival]);
      expect(m.isNew(arrival), isFalse);
      expect(m.authorOf(arrival), MemoryAuthor.partner);
    });

    test('what this phone pins is mine and never new, even while it is still being saved', () {
      final m = marks()..start();
      var notified = 0;
      m.addListener(() => notified++);
      now = 3000000;
      m.beginAdd();
      expect(m.adding, isTrue);
      final mine = idAt(3000100);
      final theirsBefore = idAt(2000000);
      expect(m.isNew(mine), isFalse);
      expect(m.authorOf(mine), MemoryAuthor.unknown);
      expect(m.isNew(theirsBefore), isTrue);

      m.endAdd(mine);
      expect(m.adding, isFalse);
      expect(notified, 1);
      expect(m.authorOf(mine), MemoryAuthor.me);
      expect(m.isNew(mine), isFalse);

      m.beginAdd();
      final lateArrival = idAt(3500000);
      expect(m.isNew(lateArrival), isFalse);
      m.endAdd(null);
      expect(notified, 2);
      expect(m.isNew(lateArrival), isTrue);
      expect(m.authorOf(lateArrival), MemoryAuthor.partner);
    });

    test('remembers across restarts and keeps the lists small', () {
      final first = MemoryMarks(settings, now: () => now, capacity: 3)..start();
      final mine = idAt(1100000);
      first.beginAdd();
      first.endAdd(mine);
      first.markSeen([idAt(1200000), idAt(1300000), idAt(1400000)]);

      final stored = jsonDecode(settings.getItem(MemoryMarks.storageKey)!) as Map<String, Object?>;
      expect(stored['since'], 1000000);
      expect(stored['mine'], [mine]);
      expect(stored['seen'], [idAt(1200000), idAt(1300000), idAt(1400000)]);

      final again = MemoryMarks(settings, now: () => 9999999);
      expect(again.since, 1000000);
      expect(again.authorOf(mine), MemoryAuthor.me);
      expect(again.isNew(idAt(1300000)), isFalse);
      expect(again.isNew(idAt(1100000)), isFalse);
      expect(again.isNew(idAt(1600000)), isTrue);
    });

    test('starts fresh when what it stored cannot be read', () async {
      await settings.setItem(MemoryMarks.storageKey, '{not json');
      final m = marks();
      expect(m.tracking, isFalse);
      await settings.setItem(MemoryMarks.storageKey, jsonEncode([1, 2]));
      expect(marks().tracking, isFalse);
    });

    test('shares one set of marks per phone', () {
      expect(identical(MemoryMarks.of(settings), MemoryMarks.of(settings)), isTrue);
      expect(identical(MemoryMarks.of(settings), MemoryMarks.of(LocalSettings.memory())), isFalse);
    });
  });
}
