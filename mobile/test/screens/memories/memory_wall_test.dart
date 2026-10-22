import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/presentation/screens/memories/memories_copy.dart';
import 'package:our_space_mobile/presentation/screens/memories/memory_photos.dart';
import 'package:our_space_mobile/presentation/screens/memories/widgets/memory_wall.dart';

MemoryRecord memory(String id, {String? date, String caption = 'A caption', int updatedAt = 1}) =>
    MemoryRecord({'id': id, 'date': date, 'caption': caption, 'updatedAt': updatedAt}, hasPhoto: true);

void main() {
  group('copy', () {
    test('counts what is kept and what is hidden', () {
      expect(MemoriesCopy.kicker(0), 'Kept, just us');
      expect(MemoriesCopy.kicker(1), '1 kept, just us');
      expect(MemoriesCopy.kicker(14), '14 kept, just us');
      expect(
        MemoriesCopy.hidden(1),
        '1 memory could not be opened with your passphrase, so it is hidden for now.',
      );
      expect(
        MemoriesCopy.hidden(2),
        '2 memories could not be opened with your passphrase, so they are hidden for now.',
      );
    });

    test('writes dates the way the wall shows them', () {
      final now = DateTime(2026, 10, 22);
      expect(MemoriesCopy.month(DateTime(2026, 10), now: now), 'October');
      expect(MemoriesCopy.month(DateTime(2024, 12), now: now), 'December 2024');
      expect(MemoriesCopy.day(DateTime(2026, 10, 21)), '21 Oct');
      expect(MemoriesCopy.fullDay(DateTime(2026, 3, 2)), '2 Mar 2026');
      expect(MemoriesCopy.meta(['21 Oct', 'by Farhu']), '21 Oct · by Farhu');
      expect(MemoriesCopy.meta(['21 Oct', null, '']), '21 Oct');
      expect(MemoriesCopy.meta([null]), '');
      expect(monthLabelOf(null), 'Some day');
    });

    test('never speaks in technical words or emoji', () {
      final copy = [
        MemoriesCopy.title,
        MemoriesCopy.opening,
        MemoriesCopy.wallError,
        MemoriesCopy.lockedTitle,
        MemoriesCopy.lockedMessage,
        MemoriesCopy.emptyTitle,
        MemoriesCopy.emptyMessage('Alex'),
        MemoriesCopy.createFirst,
        MemoriesCopy.hidden(2),
        MemoriesCopy.photoLocked,
        MemoriesCopy.removeTitle,
        MemoriesCopy.removeMessage,
        MemoriesCopy.removeFailed,
        MemoriesCopy.alreadyRemoved,
        MemoriesCopy.sheetKicker,
        MemoriesCopy.sheetTitle,
        MemoriesCopy.captureOrChoose,
        MemoriesCopy.captionHint,
        MemoriesCopy.pinIt,
        MemoriesCopy.gettingReady,
        MemoriesCopy.tuckingAway,
        MemoriesCopy.savingWall,
        MemoriesCopy.fillCaption,
        MemoriesCopy.lockedTryAgain,
        MemoriesCopy.saveFailed,
        MemoriesCopy.tooLarge,
        MemoriesCopy.cameraFailed,
        MemoriesCopy.galleryFailed,
      ];
      final banned = RegExp(
        r'\b(sync|device|pair|server|upload|download|data|peer|relay|mailbox|encrypt\w*|key)\b',
        caseSensitive: false,
      );
      for (final line in copy) {
        expect(banned.hasMatch(line), isFalse, reason: line);
        expect(calmCaption(line), line.isEmpty ? MemoriesCopy.specialMoment : line, reason: line);
      }
    });
  });

  group('captions', () {
    test('shows captions calmly without emoji', () {
      expect(calmCaption(defaultMemoryCaption), 'Precious moment');
      expect(calmCaption('Beach 🌊 day'), 'Beach day');
      expect(calmCaption('  sunrise  '), 'sunrise');
      expect(calmCaption('💕💕'), MemoriesCopy.specialMoment);
      expect(calmCaption(''), MemoriesCopy.specialMoment);
    });
  });

  group('photo cache', () {
    test('keeps the newest few', () {
      final cache = MemoryPhotoCache(capacity: 2);
      MemoryRecord at(String id, [int updatedAt = 1]) => MemoryRecord({'id': id, 'updatedAt': updatedAt}, hasPhoto: true);
      cache.put(at('a'), Uint8List(1));
      cache.put(at('b'), Uint8List(2));
      expect(cache.get(at('a')), isNotNull);
      cache.put(at('c'), Uint8List(3));
      expect(cache.get(at('b')), isNull);
      expect(cache.get(at('a')), isNotNull);
      expect(cache.get(at('c')), isNotNull);
      expect(cache.get(at('a', 2)), isNull);
      cache.clear();
      expect(cache.get(at('a')), isNull);
    });
  });

  group('wall layout', () {
    test('groups memories by month in the order they come, undated last', () {
      final months = groupMemoriesByMonth([
        memory('a', date: '2024-12-20'),
        memory('b', date: '2024-12-02'),
        memory('c', date: '2024-07-04'),
        memory('d', date: '2023-07-09'),
        memory('e'),
        memory('f', date: ''),
      ]);
      expect(months.map((m) => m.month), [DateTime(2024, 12), DateTime(2024, 7), DateTime(2023, 7), null]);
      expect(months.map((m) => m.items.map((i) => i.id).join()), ['ab', 'c', 'd', 'ef']);
      expect(groupMemoriesByMonth(const []), isEmpty);
    });

    test('fills the shorter column so the wall stays even', () {
      final items = [for (var i = 0; i < 9; i++) memory('mem-$i-x$i', caption: 'caption number $i')];
      final columns = splitIntoColumns(items, 172);
      expect(columns.left.first.id, items[0].id);
      expect(columns.right.first.id, items[1].id);
      expect(columns.left.length + columns.right.length, items.length);
      double height(List<MemoryRecord> column) =>
          column.fold<double>(0, (sum, m) => sum + estimatePolaroidHeight(m, 172));
      final tallest = items.map((m) => estimatePolaroidHeight(m, 172)).reduce((a, b) => a > b ? a : b);
      expect((height(columns.left) - height(columns.right)).abs(), lessThanOrEqualTo(tallest));
      final single = splitIntoColumns([items.first], 172);
      expect(single.left, hasLength(1));
      expect(single.right, isEmpty);
    });

    test('gives each polaroid a steady shape and fastening', () {
      for (final id in ['mem-a-1', 'mem-b-2', 'mem-c-3', 'mem-d-4']) {
        expect(PolaroidLook.ratios, contains(PolaroidLook.ratioOf(id)));
        expect(PolaroidLook.ratioOf(id), PolaroidLook.ratioOf(id));
        expect(PolaroidLook.pinOf(id), PolaroidLook.pinOf(id));
      }
      final looks = {for (var i = 0; i < 20; i++) PolaroidLook.pinOf('mem-$i-z')};
      expect(looks, containsAll(PolaroidPin.values));
      final shapes = {for (var i = 0; i < 40; i++) PolaroidLook.ratioOf('mem-$i-z')};
      expect(shapes, containsAll(PolaroidLook.ratios));
      expect(MemoryWallMetrics.columnWidth(390), 172);
    });

    test('reads the day a memory was taken', () {
      expect(memoryDay(memory('a', date: '2024-02-14')), DateTime(2024, 2, 14));
      expect(memoryDay(memory('a')), isNull);
      expect(memoryDay(memory('a', date: 'soon')), isNull);
    });
  });
}
