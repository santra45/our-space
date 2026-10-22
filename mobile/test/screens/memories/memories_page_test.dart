import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/presentation/app_shell.dart';
import 'package:our_space_mobile/presentation/screens/memories/add_memory_sheet.dart';
import 'package:our_space_mobile/presentation/screens/memories/memories_copy.dart';
import 'package:our_space_mobile/presentation/screens/memories/memory_viewer.dart';
import 'package:our_space_mobile/presentation/screens/memories/widgets/polaroid_tile.dart';
import 'package:our_space_mobile/presentation/screens/polaroids/photo_compression.dart';
import 'package:our_space_mobile/presentation/screens/polaroids/photo_picker.dart';
import 'package:our_space_mobile/presentation/sky/sky.dart';
import 'package:our_space_mobile/presentation/widgets/app_haptics.dart';

import '../../widgets/harness.dart' show recordedHaptics;
import '../polaroids/memories_harness.dart';
import 'memories_kit.dart';

void main() {
  test('saving walks through its gentle steps, the last one once the photo is sealed', () async {
    expect(MemoriesCopy.gettingReady, 'Getting it ready...');
    expect(MemoriesCopy.tuckingAway, 'Tucking it away safely...');
    expect(MemoriesCopy.savingWall, 'Pinning it to your wall...');
    final space = await openReadySpace();
    final steps = <String>[];
    await space.memories.add(
      photo: tinyWebp,
      mime: 'image/webp',
      date: '2024-02-14',
      caption: 'Steps',
      onSealed: () => steps.add('sealed'),
    );
    steps.add('saved');
    expect(steps, ['sealed', 'saved']);
    expect((await space.memories.list()).single.caption, 'Steps');
    while (space.identity.status == IdentityStatus.loading) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    await space.close();
  });

  testWidgets('shows a warm empty wall with the partner name and opens the add sheet', (tester) async {
    calm(tester);
    final space = await real(tester, openReadySpace);
    await openTab(tester, space, 'Memories');

    await untilFound(tester, find.text(MemoriesCopy.emptyTitle));
    expect(find.text('Memories'), findsWidgets);
    expect(find.text('KEPT, JUST US'), findsOneWidget);
    expect(find.text('Pin a photo of the two of you. It stays right here, just for you and Alex.'), findsOneWidget);
    expect(find.text('Pin your first memory'), findsOneWidget);
    expect(find.textContaining('💕'), findsNothing);

    await press(tester, find.text('Pin your first memory'));
    await settleRoutes(tester);
    expect(find.byType(AddMemorySheet), findsOneWidget);
    expect(find.text('A new memory'), findsOneWidget);
    expect(find.text('KEPT JUST BETWEEN YOU TWO'), findsOneWidget);
    expect(find.text('Capture or choose a photo together'), findsOneWidget);
    expect(find.text('Take a photo'), findsOneWidget);
    expect(find.text('Choose a photo'), findsOneWidget);
    expect(find.text('Date taken'), findsOneWidget);
    expect(find.text(MemoriesCopy.fullDay(DateTime.now())), findsOneWidget);
    expect(skyButtonEnabled(tester, 'Pin it to our wall'), isFalse);

    await tester.tap(inSheet(semanticsLabelled('Close')));
    await settleRoutes(tester);
    expect(find.byType(AddMemorySheet), findsNothing);

    await press(tester, addButton());
    await settleRoutes(tester);
    expect(find.byType(AddMemorySheet), findsOneWidget);
  });

  testWidgets('pins a gallery photo with a caption and date, views it and removes it', (tester) async {
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
    await untilFound(tester, find.text(MemoriesCopy.emptyTitle));

    recordedHaptics.clear();
    await press(tester, addButton());
    await settleRoutes(tester);
    expect(recordedHaptics, contains(HapticKind.tick));

    await press(tester, find.text('Choose a photo'));
    await untilFound(tester, find.text('Change photo'));
    expect(sources, [PhotoSource.gallery]);
    expect(find.text('Capture or choose a photo together'), findsNothing);
    expect(skyButtonEnabled(tester, 'Pin it to our wall'), isTrue);

    await press(tester, find.text('Pin it to our wall'));
    expect(find.text('Write a little caption first.'), findsOneWidget);
    expect(await real(tester, () => space.memories.list()), isEmpty);

    await typeInto(tester, captionField(), '  Our first picnic  ');
    expect(find.text('Write a little caption first.'), findsNothing);

    final now = DateTime.now();
    final picked = DateTime(now.year, now.month, 15);
    await press(tester, find.text('Date taken'));
    await settleRoutes(tester);
    await tester.tap(find.text('15'));
    await tester.pump();
    await tester.tap(find.text('OK'));
    await settleRoutes(tester);
    expect(find.text(MemoriesCopy.fullDay(picked)), findsOneWidget);
    expect(find.text('${MemoriesCopy.fullDay(picked)} · by you'), findsOneWidget);

    recordedHaptics.clear();
    await press(tester, find.text('Pin it to our wall'));
    await untilGone(tester, find.byType(AddMemorySheet));
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

    await untilFound(tester, find.text('1 KEPT, JUST US'));
    expect(find.text(MemoriesCopy.month(picked).toUpperCase()), findsOneWidget);
    expect(find.text('Our first picnic'), findsOneWidget);
    expect(find.text('${MemoriesCopy.day(picked)} · by you'), findsOneWidget);
    expect(find.text('New'), findsNothing);
    await untilFound(tester, tilePhotos());
    expect(tileTilt(tester, 'Our first picnic'), closeTo(PolaroidTile.tiltOf(memory), 1e-9));

    await press(tester, tilePhotos());
    await settleRoutes(tester);
    expect(find.byType(MemoryViewer), findsOneWidget);
    expect(inViewer(find.text('Our first picnic')), findsOneWidget);
    expect(inViewer(find.text('${MemoriesCopy.fullDay(picked)} · by you')), findsOneWidget);
    await tester.tap(inViewer(semanticsLabelled('Close')));
    await settleRoutes(tester);
    expect(find.byType(MemoryViewer), findsNothing);

    await press(tester, tilePhotos());
    await settleRoutes(tester);
    await tester.tap(inViewer(semanticsLabelled('Remove this memory')));
    await settleRoutes(tester);
    expect(find.text('Remove this memory?'), findsOneWidget);
    expect(find.text('It will be gone for both of you. This cannot be undone.'), findsOneWidget);
    await tester.tap(find.text('Keep it'));
    await settleRoutes(tester);
    expect(find.byType(MemoryViewer), findsOneWidget);
    expect(await real(tester, () => space.memories.list()), hasLength(1));

    await tester.tap(inViewer(semanticsLabelled('Remove this memory')));
    await settleRoutes(tester);
    await tester.tap(find.text('Remove it'));
    await settleRoutes(tester);
    await untilGone(tester, find.byType(MemoryViewer));
    await untilFound(tester, find.text(MemoriesCopy.emptyTitle));
    expect(await real(tester, () => space.memories.list()), isEmpty);
  });

  testWidgets('takes a camera photo, swaps it, and falls back to jpeg', (tester) async {
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
    await untilFound(tester, find.text(MemoriesCopy.emptyTitle));
    await press(tester, addButton());
    await settleRoutes(tester);
    await press(tester, find.text('Take a photo'));
    await untilFound(tester, find.text('Change photo'));
    expect(sources, [PhotoSource.camera]);

    await press(tester, find.text('Change photo'));
    await untilFound(tester, find.text('Capture or choose a photo together'));
    expect(skyButtonEnabled(tester, 'Pin it to our wall'), isFalse);
    await press(tester, find.text('Take a photo'));
    await untilFound(tester, find.text('Change photo'));

    await typeInto(tester, captionField(), 'Sunset');
    await press(tester, find.text('Pin it to our wall'));
    await untilGone(tester, find.byType(AddMemorySheet));
    final saved = await real(tester, () => space.memories.list());
    expect(saved.single.mime, 'image/jpeg');
    expect(saved.single.date, toLocalDateInput());
    expect(await real(tester, () => space.memories.loadPhoto(saved.single.id)), jpeg);
  });

  testWidgets('keeps the sheet open with a sweet error when a photo cannot be used', (tester) async {
    calm(tester);
    final space = await real(tester, openReadySpace);
    var fail = true;
    final encoder = FakeEncoder(webp: tinyWebp);
    useFakePhotos(
      picker: (from) async {
        if (fail) throw PhotoPickFailure(from);
        return PickedPhoto(bytes: Uint8List.fromList(List<int>.generate(80, (i) => i)));
      },
      encoder: encoder,
    );

    await openTab(tester, space, 'Memories');
    await untilFound(tester, find.text(MemoriesCopy.emptyTitle));
    await press(tester, addButton());
    await settleRoutes(tester);

    await press(tester, find.text('Take a photo'));
    await untilFound(tester, find.text('We could not open your camera just now. Please try again.'));
    await press(tester, find.text('Choose a photo'));
    await untilFound(tester, find.text('We could not open your photos just now. Please try again.'));

    fail = false;
    await press(tester, find.text('Choose a photo'));
    await untilFound(tester, find.text('Change photo'));
    expect(find.text('We could not open your photos just now. Please try again.'), findsNothing);

    await typeInto(tester, captionField(), 'Blurry one');
    await press(tester, find.text('Pin it to our wall'));
    await untilFound(
      tester,
      find.text('This memory could not be kept: That file is not an image this phone can open.'),
    );
    expect(find.byType(AddMemorySheet), findsOneWidget);
    expect(skyButtonEnabled(tester, 'Pin it to our wall'), isTrue);
    expect(await real(tester, () => space.memories.list()), isEmpty);
  });

  testWidgets('says so warmly when a photo is still too big to keep', (tester) async {
    calm(tester);
    final space = await real(tester, openReadySpace);
    final source = await real(tester, () => testPng(64, 64));
    useFakePhotos(
      picker: (from) async => PickedPhoto(bytes: source),
      encoder: FakeEncoder(webp: null, jpeg: fakeJpeg(maxImageBlobBytes + 1024)),
    );

    await openTab(tester, space, 'Memories');
    await untilFound(tester, find.text(MemoriesCopy.emptyTitle));
    await press(tester, addButton());
    await settleRoutes(tester);
    await press(tester, find.text('Choose a photo'));
    await untilFound(tester, find.text('Change photo'));
    await typeInto(tester, captionField(), 'Too much sky');
    await press(tester, find.text('Pin it to our wall'));
    await untilFound(tester, find.text(MemoriesCopy.tooLarge));
    expect(find.byType(AddMemorySheet), findsOneWidget);
    expect(await real(tester, () => space.memories.list()), isEmpty);
  });

  testWidgets('lays memories out newest first by month and hides ones from another passphrase', (tester) async {
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
    await addMemory(tester, space, caption: 'Cocoa', date: '2024-12-02');
    await addMemory(tester, space, caption: '', date: '2022-02-14');

    await openTab(tester, space, 'Memories');
    await untilFound(tester, find.text('4 KEPT, JUST US'));
    expect(
      find.text('1 memory could not be opened with your passphrase, so it is hidden for now.'),
      findsOneWidget,
    );
    expect(find.text('Not ours'), findsNothing);

    expect(find.text('DECEMBER 2024'), findsOneWidget);
    expect(find.text('20 Dec'), findsOneWidget);
    expect(find.text('2 Dec'), findsOneWidget);
    final snow = tester.getRect(tileFor('Snow walk'));
    final cocoa = tester.getRect(tileFor('Cocoa'));
    expect(cocoa.center.dx, greaterThan(snow.center.dx));
    expect(cocoa.top, closeTo(snow.top, 2));

    await scrollWallTo(tester, find.text('JULY 2023'));
    await scrollWallTo(tester, tileFor('Beach day'));
    expect(find.text('4 Jul'), findsOneWidget);
    expect(tester.getRect(tileFor('Beach day')).top, greaterThan(tester.getRect(find.text('JULY 2023')).bottom));

    await scrollWallTo(tester, find.text('FEBRUARY 2022'));
    await scrollWallTo(tester, find.text('Precious moment'));
    expect(find.text('14 Feb'), findsOneWidget);
    expect(find.text(MemoriesCopy.specialMoment), findsNothing);
    expect(find.textContaining('💕'), findsNothing);
    expect(find.textContaining('by '), findsNothing);
  });

  testWidgets('marks what Alex adds as new, says who added it, and forgets once seen', (tester) async {
    calm(tester);
    final space = await real(tester, openReadySpace);
    await addMemory(tester, space, caption: 'Old one', date: '2024-05-01');
    final today = DateTime.now();

    await openTab(tester, space, 'Memories');
    await untilFound(tester, find.text('Old one'));
    expect(find.text('1 May'), findsOneWidget);
    expect(find.text('New'), findsNothing);

    await addMemoryLive(tester, space, caption: 'From Alex', date: toLocalDateInput(today));
    await untilFound(tester, find.text('From Alex'));
    expect(find.text('New'), findsOneWidget);
    expect(find.text('${MemoriesCopy.day(today)} · by Alex'), findsOneWidget);
    expect(find.text('1 May'), findsOneWidget);

    await untilFound(tester, find.descendant(of: tileFor('From Alex'), matching: find.byType(Image)));
    await press(tester, find.descendant(of: tileFor('From Alex'), matching: find.byType(Image)));
    await settleRoutes(tester);
    expect(inViewer(find.text('${MemoriesCopy.fullDay(today)} · by Alex')), findsOneWidget);
    await tester.tap(inViewer(semanticsLabelled('Close')));
    await settleRoutes(tester);
    await untilGone(tester, find.text('New'));

    await addMemoryLive(tester, space, caption: 'Another hello', date: toLocalDateInput(today));
    await untilFound(tester, find.text('Another hello'));
    expect(find.text('New'), findsOneWidget);

    await tester.tap(find.descendant(of: find.byKey(ShellKeys.dock), matching: find.text('Letters')));
    await idle(tester);
    await tester.tap(find.descendant(of: find.byKey(ShellKeys.dock), matching: find.text('Memories')));
    await untilFound(tester, find.text('Another hello'));
    await idle(tester);
    expect(find.text('New'), findsNothing);
    expect(find.text('${MemoriesCopy.day(today)} · by Alex'), findsNWidgets(2));
  });

  testWidgets('closes the big view when that memory is removed elsewhere', (tester) async {
    calm(tester);
    final space = await real(tester, openReadySpace);
    final memory = await addMemory(tester, space, caption: 'Rooftop', date: '2024-05-01');

    await openTab(tester, space, 'Memories');
    await untilFound(tester, tilePhotos());
    await press(tester, tilePhotos());
    await settleRoutes(tester);
    expect(find.byType(MemoryViewer), findsOneWidget);

    await live(tester, () => space.memories.delete(memory.id));
    await untilGone(tester, find.byType(MemoryViewer));
    await untilFound(tester, find.text(MemoriesCopy.emptyTitle));
  });

  testWidgets('shows a gentle note on a memory whose photo will not open and lets it go on a long press', (
    tester,
  ) async {
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
    expect(tilePhotos(), findsNothing);

    await press(tester, tileFor('Odd one'));
    await settleRoutes(tester);
    expect(inViewer(find.text('This photo could not be unlocked.')), findsOneWidget);
    await tester.tap(inViewer(semanticsLabelled('Close')));
    await settleRoutes(tester);

    await tester.longPress(tileFor('Odd one'));
    await settleRoutes(tester);
    expect(find.text('Remove this memory?'), findsOneWidget);
    await tester.tap(find.text('Remove it'));
    await settleRoutes(tester);
    await untilFound(tester, find.text(MemoriesCopy.emptyTitle));
    expect(await real(tester, () => space.memories.list()), isEmpty);
  });

  testWidgets('offers a retry when the wall cannot open and rests quietly while locked', (tester) async {
    calm(tester);
    final space = await real(tester, openReadySpace);
    await addMemory(tester, space, caption: 'Kept safe', date: '2024-05-01');
    final locked = StreamController<TableSnapshot<MemoryRecord>>();
    addTearDown(locked.close);
    var calls = 0;
    useWatcher((memories) {
      calls++;
      if (calls == 1) return Stream<TableSnapshot<MemoryRecord>>.error(StateError('closed'));
      if (calls == 2) return locked.stream;
      return memories.watch();
    });

    await openTab(tester, space, 'Memories');
    await untilFound(tester, find.text(MemoriesCopy.wallError));
    expect(find.text(MemoriesCopy.emptyTitle), findsNothing);
    expect(find.text('Pin your first memory'), findsNothing);

    await press(tester, find.text('Try again'));
    expect(find.text(MemoriesCopy.wallError), findsNothing);
    locked.add(const TableSnapshot<MemoryRecord>(items: [], unreadable: 0, unlocked: false));
    await untilFound(tester, find.text(MemoriesCopy.lockedTitle));
    expect(find.text(MemoriesCopy.lockedMessage), findsOneWidget);
    expect(find.text(MemoriesCopy.emptyTitle), findsNothing);
    expect(tester.widget<SkyIconButton>(addButton()).onPressed, isNull);

    await tester.tap(find.descendant(of: find.byKey(ShellKeys.dock), matching: find.text('Letters')));
    await idle(tester);
    await tester.tap(find.descendant(of: find.byKey(ShellKeys.dock), matching: find.text('Memories')));
    await untilFound(tester, find.text('Kept safe'));
    expect(calls, 3);
  });
}
