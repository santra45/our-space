import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/presentation/screens/polaroids/memories_copy.dart';
import 'package:our_space_mobile/presentation/screens/polaroids/photo_compression.dart';
import 'package:our_space_mobile/presentation/screens/polaroids/photo_picker.dart';
import 'package:our_space_mobile/presentation/screens/polaroids/polaroid_card.dart';
import 'package:our_space_mobile/presentation/screens/polaroids/polaroid_preview.dart';
import 'package:our_space_mobile/presentation/widgets/our_widgets.dart';

import '../../widgets/harness.dart' show recordedHaptics;
import 'memories_harness.dart';

Finder cardPhoto() => find.descendant(of: find.byType(PolaroidCard), matching: find.byType(Image));

Future<MemoryRecord> addMemory(
  WidgetTester tester,
  OurSpace space, {
  required String caption,
  required String date,
  Uint8List? photo,
}) async {
  await real(tester, () => space.memories.add(photo: photo ?? tinyWebp, mime: 'image/webp', date: date, caption: caption));
  final all = await real(tester, () => space.memories.list());
  final stored = caption.trim().isEmpty ? 'Precious moment 💕' : caption.trim();
  return all.firstWhere((memory) => memory.caption == stored);
}

void main() {
  group('copy', () {
    test('counts polaroids like the web', () {
      expect(MemoriesCopy.preserved(0), '0 polaroids preserved');
      expect(MemoriesCopy.preserved(1), '1 polaroid preserved');
      expect(MemoriesCopy.preserved(3), '3 polaroids preserved');
      expect(
        MemoriesCopy.hidden(1),
        '1 polaroid could not be opened with your passphrase, so it is hidden for now.',
      );
      expect(
        MemoriesCopy.hidden(2),
        '2 polaroids could not be opened with your passphrase, so they are hidden for now.',
      );
    });

    test('photo cache keeps the newest few', () {
      final cache = PolaroidPhotoCache(capacity: 2);
      MemoryRecord memory(String id) => MemoryRecord({'id': id, 'updatedAt': 1}, hasPhoto: true);
      cache.put(memory('a'), Uint8List(1));
      cache.put(memory('b'), Uint8List(2));
      expect(cache.get(memory('a')), isNotNull);
      cache.put(memory('c'), Uint8List(3));
      expect(cache.get(memory('b')), isNull);
      expect(cache.get(memory('a')), isNotNull);
      expect(cache.get(memory('c')), isNotNull);
      expect(cache.get(MemoryRecord({'id': 'a', 'updatedAt': 2}, hasPhoto: true)), isNull);
    });
  });

  testWidgets('shows the empty scrapbook with the partner name', (tester) async {
    calm(tester);
    final space = await real(tester, openReadySpace);
    await openTab(tester, space, 'Memories');

    await untilFound(tester, find.text('No Polaroids Yet'));
    expect(find.text('Our Scrapbook'), findsOneWidget);
    expect(find.text('0 polaroids preserved'), findsOneWidget);
    expect(find.text('Snap Memory'), findsOneWidget);
    expect(
      find.text('Add your first photo together! It will be saved safely here and shared with Alex.'),
      findsOneWidget,
    );
    expect(find.text('Create First Polaroid 💕'), findsOneWidget);

    await press(tester, find.text('Create First Polaroid 💕'));
    await settleRoutes(tester);
    expect(find.text('Add New Polaroid'), findsOneWidget);
    expect(find.text('Kept just between you two'), findsOneWidget);
    expect(find.text('Capture or choose a photo together'), findsOneWidget);
    expect(find.text('Polaroid Caption'), findsOneWidget);
    expect(find.text('Date Taken'), findsOneWidget);
    expect(buttonEnabled(tester, 'Pin it up 💕'), isFalse);

    await tester.tap(find.byType(OurCloseButton));
    await settleRoutes(tester);
    expect(find.text('Add New Polaroid'), findsNothing);
  });

  testWidgets('pins a gallery photo with a caption and date, views it and deletes it', (tester) async {
    calm(tester);
    final space = await real(tester, openReadySpace);
    final source = await real(tester, () => testPng(2880, 720));
    final sources = <PhotoSource>[];
    final encoder = FakeEncoder(webp: tinyWebp, jpeg: fakeJpeg(64));
    useFakePhotos(
      picker: (from) async {
        sources.add(from);
        return PickedPhoto(bytes: source, name: 'picnic.png');
      },
      encoder: encoder,
    );

    await openTab(tester, space, 'Memories');
    await untilFound(tester, find.text('No Polaroids Yet'));

    await press(tester, find.text('Snap Memory'));
    await settleRoutes(tester);
    expect(recordedHaptics, contains(HapticKind.tap));

    await press(tester, find.text('Gallery'));
    await untilFound(tester, find.text('Change Photo'));
    expect(sources, [PhotoSource.gallery]);
    expect(find.text('Capture or choose a photo together'), findsNothing);
    expect(buttonEnabled(tester, 'Pin it up 💕'), isTrue);

    await press(tester, find.text('Pin it up 💕'));
    expect(find.text('Please fill out this field.'), findsOneWidget);
    expect(await real(tester, () => space.memories.list()), isEmpty);

    await typeInto(tester, fieldWithHint('Write a sweet note or memory...'), '  Our first picnic  ');
    expect(find.text('Please fill out this field.'), findsNothing);

    final now = DateTime.now();
    final picked = DateTime(now.year, now.month, 15);
    await press(tester, find.byType(OurDateField));
    await settleRoutes(tester);
    await tester.tap(find.text('15'));
    await tester.pump();
    await tester.tap(find.text('OK'));
    await settleRoutes(tester);
    expect(find.text(formatInputDate(picked)), findsOneWidget);

    recordedHaptics.clear();
    await press(tester, find.text('Pin it up 💕'));
    await untilGone(tester, find.text('Add New Polaroid'));
    expect(recordedHaptics, containsAllInOrder([HapticKind.tap, HapticKind.celebration]));

    final saved = await real(tester, () => space.memories.list());
    expect(saved, hasLength(1));
    final memory = saved.single;
    expect(memory.caption, 'Our first picnic');
    expect(memory.mime, 'image/webp');
    expect(memory.date, toLocalDateInput(picked));
    expect(await real(tester, () => space.memories.loadPhoto(memory.id)), tinyWebp);
    expect(encoder.calls.first.format, PhotoFormat.webp);
    expect(encoder.calls.first.width, 1440);
    expect(encoder.calls.first.height, 360);
    expect(encoder.calls.first.quality, 85);

    await untilFound(tester, find.text('1 polaroid preserved'));
    expect(find.text('Our first picnic'), findsOneWidget);
    expect(find.text(formatDatePretty(toLocalDateInput(picked))), findsOneWidget);
    await untilFound(tester, cardPhoto());

    final tilt = tester.widget<Transform>(
      find.descendant(of: find.byType(PolaroidCard), matching: find.byType(Transform)).at(1),
    );
    final angle = math.atan2(tilt.transform.entry(1, 0), tilt.transform.entry(0, 0));
    expect(angle, closeTo(memory.rotationDegrees * math.pi / 180, 1e-9));

    await press(tester, cardPhoto());
    await settleRoutes(tester);
    expect(find.byType(PolaroidPreview), findsOneWidget);
    expect(find.descendant(of: find.byType(PolaroidPreview), matching: find.text('Our first picnic')), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(PolaroidPreview), matching: find.byType(OurCloseButton)));
    await settleRoutes(tester);
    expect(find.byType(PolaroidPreview), findsNothing);

    await press(tester, semanticsLabelled('Delete memory'));
    await settleRoutes(tester);
    expect(find.text('Delete this precious memory? This cannot be undone.'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settleRoutes(tester);
    expect(await real(tester, () => space.memories.list()), hasLength(1));

    await press(tester, semanticsLabelled('Delete memory'));
    await settleRoutes(tester);
    await tester.tap(find.text('OK'));
    await settleRoutes(tester);
    await untilFound(tester, find.text('No Polaroids Yet'));
    expect(await real(tester, () => space.memories.list()), isEmpty);
  });

  testWidgets('takes a camera photo and falls back to jpeg', (tester) async {
    calm(tester);
    final space = await real(tester, openReadySpace);
    final source = await real(tester, () => testPng(400, 300));
    final sources = <PhotoSource>[];
    final jpeg = fakeJpeg(64);
    useFakePhotos(
      picker: (from) async {
        sources.add(from);
        return PickedPhoto(bytes: source);
      },
      encoder: FakeEncoder(webp: null, jpeg: jpeg),
    );

    await openTab(tester, space, 'Memories');
    await untilFound(tester, find.text('No Polaroids Yet'));
    await press(tester, find.text('Snap Memory'));
    await settleRoutes(tester);
    await press(tester, find.text('Camera'));
    await untilFound(tester, find.text('Change Photo'));
    expect(sources, [PhotoSource.camera]);

    await press(tester, find.text('Change Photo'));
    expect(find.text('Capture or choose a photo together'), findsOneWidget);
    await press(tester, find.text('Camera'));
    await untilFound(tester, find.text('Change Photo'));

    await typeInto(tester, fieldWithHint('Write a sweet note or memory...'), 'Sunset');
    await press(tester, find.text('Pin it up 💕'));
    await untilGone(tester, find.text('Add New Polaroid'));
    final saved = await real(tester, () => space.memories.list());
    expect(saved.single.mime, 'image/jpeg');
    expect(saved.single.date, toLocalDateInput());
    expect(await real(tester, () => space.memories.loadPhoto(saved.single.id)), jpeg);
  });

  testWidgets('keeps the sheet open with a sweet error when a photo cannot be used', (tester) async {
    calm(tester);
    final space = await real(tester, openReadySpace);
    var fail = true;
    useFakePhotos(
      picker: (from) async {
        if (fail) throw PhotoPickFailure(from);
        return PickedPhoto(bytes: Uint8List.fromList(List<int>.generate(80, (i) => i)));
      },
      encoder: FakeEncoder(webp: tinyWebp),
    );

    await openTab(tester, space, 'Memories');
    await untilFound(tester, find.text('No Polaroids Yet'));
    await press(tester, find.text('Snap Memory'));
    await settleRoutes(tester);

    await press(tester, find.text('Camera'));
    await untilFound(tester, find.text('We could not open your camera just now. Please try again.'));
    await press(tester, find.text('Gallery'));
    await untilFound(tester, find.text('We could not open your photos just now. Please try again.'));

    fail = false;
    await press(tester, find.text('Gallery'));
    await untilFound(tester, find.text('Change Photo'));
    expect(find.text('We could not open your photos just now. Please try again.'), findsNothing);

    await typeInto(tester, fieldWithHint('Write a sweet note or memory...'), 'Blurry one');
    await press(tester, find.text('Pin it up 💕'));
    await untilFound(
      tester,
      find.text('Could not save this memory: That file is not an image this phone can open.'),
    );
    expect(find.text('Add New Polaroid'), findsOneWidget);
    expect(buttonEnabled(tester, 'Pin it up 💕'), isTrue);
    expect(await real(tester, () => space.memories.list()), isEmpty);
  });

  testWidgets('lays polaroids out newest first and hides ones from another passphrase', (tester) async {
    calm(tester);
    final space = await real(tester, openReadySpace);
    final stranger = await real(tester, openStrangerSpace);
    final row = await real(
      tester,
      () => stranger.memories.add(photo: tinyWebp, mime: 'image/webp', date: '2024-01-01', caption: 'Not ours'),
    );
    await real(tester, () => space.store.putRow(memoriesTable, row));
    await addMemory(tester, space, caption: 'Beach day', date: '2023-07-04');
    await addMemory(tester, space, caption: 'Snow walk', date: '2024-12-20');
    await addMemory(tester, space, caption: '', date: '2022-02-14');

    await openTab(tester, space, 'Memories');
    await untilFound(tester, find.text('3 polaroids preserved'));
    expect(
      find.text('1 polaroid could not be opened with your passphrase, so it is hidden for now.'),
      findsOneWidget,
    );
    expect(find.text('Not ours'), findsNothing);
    expect(find.text('A special moment'), findsNothing);

    final captions = tester
        .widgetList<PolaroidCard>(find.byType(PolaroidCard))
        .map((card) => card.memory.caption)
        .toList();
    expect(captions, ['Snow walk', 'Beach day', 'Precious moment 💕']);
    expect(find.text('Dec 20, 2024'), findsOneWidget);
    expect(find.text('Jul 4, 2023'), findsOneWidget);
    expect(find.text('Feb 14, 2022'), findsOneWidget);

    final snow = tester.getRect(find.widgetWithText(PolaroidCard, 'Snow walk'));
    final beach = tester.getRect(find.widgetWithText(PolaroidCard, 'Beach day'));
    final third = tester.getRect(find.widgetWithText(PolaroidCard, 'Precious moment 💕'));
    expect(beach.center.dx, greaterThan(snow.center.dx));
    expect(third.center.dy, greaterThan(snow.center.dy));
    expect(third.center.dx, closeTo(snow.center.dx, 4));
  });

  testWidgets('closes the big view when that polaroid is removed elsewhere', (tester) async {
    calm(tester);
    final space = await real(tester, openReadySpace);
    final memory = await addMemory(tester, space, caption: 'Rooftop', date: '2024-05-01');

    await openTab(tester, space, 'Memories');
    await untilFound(tester, cardPhoto());
    await press(tester, cardPhoto());
    await settleRoutes(tester);
    expect(find.byType(PolaroidPreview), findsOneWidget);

    await real(tester, () => space.memories.delete(memory.id));
    await untilGone(tester, find.byType(PolaroidPreview));
    await untilFound(tester, find.text('No Polaroids Yet'));
  });

  testWidgets('shows a gentle note on a polaroid whose photo will not open', (tester) async {
    calm(tester);
    final space = await real(tester, openReadySpace);
    await addMemory(tester, space, caption: 'Odd one', date: '2024-05-01');
    final row = (await real(tester, () => space.store.allRows(memoriesTable))).single;
    final broken = Map<String, Object?>.from(row);
    final blob = Uint8List.fromList(row['imageBlob'] as Uint8List);
    blob[blob.length - 1] ^= 0xFF;
    broken['imageBlob'] = blob;
    await real(tester, () => space.store.putRow(memoriesTable, broken));

    await openTab(tester, space, 'Memories');
    await untilFound(tester, find.text('This photo could not be unlocked.'));
    expect(find.text('Odd one'), findsOneWidget);
    expect(cardPhoto(), findsNothing);
  });
}
