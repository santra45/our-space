import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/presentation/screens/memories/add_memory_sheet.dart';
import 'package:our_space_mobile/presentation/screens/memories/memories_page.dart';
import 'package:our_space_mobile/presentation/screens/memories/memory_viewer.dart';
import 'package:our_space_mobile/presentation/screens/memories/widgets/polaroid.dart';
import 'package:our_space_mobile/presentation/screens/memories/widgets/polaroid_tile.dart';
import 'package:our_space_mobile/presentation/sky/sky.dart';

import '../polaroids/memories_harness.dart';

Finder captionField() => find.descendant(of: find.byType(AddMemorySheet), matching: find.byType(TextField));

Finder inSheet(Finder finder) => find.descendant(of: find.byType(AddMemorySheet), matching: finder);

Finder inViewer(Finder finder) => find.descendant(of: find.byType(MemoryViewer), matching: finder);

Finder tileFor(String caption) => find.widgetWithText(PolaroidTile, caption);

Finder tilePhotos() => find.descendant(of: find.byType(PolaroidTile), matching: find.byType(Image));

Finder wallScrollable() => find.descendant(of: find.byType(MemoriesPage), matching: find.byType(Scrollable)).first;

Finder addButton() => find.byKey(MemoriesPage.addKey);

bool skyButtonEnabled(WidgetTester tester, String label) =>
    tester.widget<SkyButton>(find.widgetWithText(SkyButton, label)).enabled;

double tileTilt(WidgetTester tester, String caption) {
  final tilt = tester.widget<Transform>(
    find.descendant(
      of: tileFor(caption),
      matching: find.byWidgetPredicate((widget) => widget is Transform && widget.child is PolaroidPaper),
    ),
  );
  return math.atan2(tilt.transform.entry(1, 0), tilt.transform.entry(0, 0));
}

Future<MemoryRecord> addMemory(
  WidgetTester tester,
  OurSpace space, {
  required String caption,
  required String date,
  Uint8List? photo,
}) async {
  await real(tester, () => space.memories.add(photo: photo ?? tinyWebp, mime: 'image/webp', date: date, caption: caption));
  final all = await real(tester, () => space.memories.list());
  final stored = caption.trim().isEmpty ? defaultMemoryCaption : caption.trim();
  return all.firstWhere((memory) => memory.caption == stored);
}

Future<T> live<T>(WidgetTester tester, Future<T> Function() body) async {
  T? value;
  Object? failure;
  var done = false;
  body().then(
    (result) {
      value = result;
      done = true;
    },
    onError: (Object error) {
      failure = error;
      done = true;
    },
  );
  await until(tester, () => done);
  if (failure != null) throw failure!;
  return value as T;
}

Future<void> addMemoryLive(
  WidgetTester tester,
  OurSpace space, {
  required String caption,
  required String date,
}) async {
  await live(tester, () => space.memories.add(photo: tinyWebp, mime: 'image/webp', date: date, caption: caption));
}

Future<void> scrollWallTo(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(finder, 240, scrollable: wallScrollable());
  }
  await reveal(tester, finder);
}

void useWatcher(MemoriesWatcher watcher) {
  final original = MemoriesPage.watcher;
  MemoriesPage.watcher = watcher;
  addTearDown(() => MemoriesPage.watcher = original);
}
