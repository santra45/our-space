import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/main.dart';
import 'package:our_space_mobile/presentation/app_shell.dart';
import 'package:our_space_mobile/presentation/home_shell.dart';
import 'package:our_space_mobile/presentation/sky/sky.dart';
import 'package:our_space_mobile/presentation/screens/polaroids/photo_compression.dart';
import 'package:our_space_mobile/presentation/screens/polaroids/photo_picker.dart';
import 'package:our_space_mobile/presentation/widgets/our_widgets.dart';

import '../../support/harness.dart';
import '../../widgets/harness.dart' show recordHaptics, usePhoneSize;

const String testPassphrase = 'correct horse battery staple 2026';

final Uint8List tinyWebp = base64Decode('UklGRhoAAABXRUJQVlA4TA0AAAAvAAAAEAcQERGIiP4HAA==');

Future<T> real<T>(WidgetTester tester, Future<T> Function() body) async => (await tester.runAsync(body)) as T;

Future<void> until(WidgetTester tester, bool Function() done, {int tries = 1500}) async {
  for (var i = 0; i < tries && !done(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(done(), isTrue);
}

Future<void> idle(WidgetTester tester, [int rounds = 10]) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> untilFound(WidgetTester tester, Finder finder) => until(tester, () => finder.evaluate().isNotEmpty);

Future<void> untilGone(WidgetTester tester, Finder finder) => until(tester, () => finder.evaluate().isEmpty);

void calm(WidgetTester tester) {
  recordHaptics();
  usePhoneSize(tester);
  tester.view.physicalSize = const Size(1290, 2796);
  tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
    disableAnimations: true,
    reduceMotion: true,
  );
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

Future<OurSpace> _open(String prefix) {
  final dir = Directory.systemTemp.createTempSync(prefix);
  return OurSpace.open(
    databaseFactory: testDatabaseFactory(),
    databasePath: '${dir.path}${Platform.pathSeparator}space.sqlite',
    useEnvironmentMailbox: false,
    autoSync: false,
  );
}

Future<OurSpace> openReadySpace() async {
  final space = await _open('our_space_memories_');
  await space.vault.create(passphrase: testPassphrase, coupleNames: 'Sam & Alex', iterations: 1000);
  await space.identity.createCouple(myName: 'Sam', myPronoun: 'he', partnerName: 'Alex', partnerPronoun: 'she');
  return space;
}

Future<OurSpace> openStrangerSpace() async {
  final space = await _open('our_space_stranger_');
  await space.vault.create(passphrase: 'a completely different passphrase', iterations: 1000);
  return space;
}

Future<void> openTab(WidgetTester tester, OurSpace space, String label) async {
  await tester.pumpWidget(OurSpaceApp(openSpace: () async => space));
  await tester.pump();
  await untilFound(tester, find.byType(HomeShell));
  await tester.tap(find.descendant(of: find.byKey(ShellKeys.dock), matching: find.text(label)));
  await tester.pump();
  await tester.pump();
}

Future<void> openUsSection(WidgetTester tester, OurSpace space, String section) async {
  await openTab(tester, space, 'Us');
  await tester.tap(find.widgetWithText(SkyChip, section));
  await tester.pump();
  await tester.pump();
}

Future<void> settleRoutes(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Finder fieldWithHint(String hint) => find.descendant(
      of: find.byWidgetPredicate((widget) => widget is OurTextField && widget.hint == hint),
      matching: find.byType(TextField),
    );

Finder semanticsLabelled(String label) =>
    find.byWidgetPredicate((widget) => widget is Semantics && widget.properties.label == label);

Future<void> reveal(WidgetTester tester, Finder finder) async {
  unawaited(Scrollable.ensureVisible(tester.element(finder), alignment: 0.5));
  await tester.pump();
}

Future<void> press(WidgetTester tester, Finder finder) async {
  await reveal(tester, finder);
  await tester.tap(finder);
  await tester.pump();
}

Future<void> typeInto(WidgetTester tester, Finder finder, String text) async {
  await reveal(tester, finder);
  await tester.enterText(finder, text);
  await tester.pump();
}

bool buttonEnabled(WidgetTester tester, String label) {
  final button = tester.widget<BouncyButton>(find.ancestor(of: find.text(label), matching: find.byType(BouncyButton)));
  return button.isEnabled;
}

Future<Uint8List> testPng(int width, int height, {Color color = const Color(0xFFFF85A3)}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()), Paint()..color = color);
  canvas.drawRect(Rect.fromLTWH(0, 0, width / 2, height / 2), Paint()..color = const Color(0xFF9A76FF));
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}

Future<Size> pngSize(Uint8List bytes) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  final descriptor = await ui.ImageDescriptor.encoded(buffer);
  final size = Size(descriptor.width.toDouble(), descriptor.height.toDouble());
  descriptor.dispose();
  buffer.dispose();
  return size;
}

class EncoderCall {
  EncoderCall(this.png, this.width, this.height, this.quality, this.format);

  final Uint8List png;
  final int width;
  final int height;
  final int quality;
  final PhotoFormat format;
}

class FakeEncoder {
  FakeEncoder({this.webp, this.jpeg});

  Uint8List? webp;
  Uint8List? jpeg;
  final List<EncoderCall> calls = [];

  Future<Uint8List?> call(
    Uint8List png, {
    required int width,
    required int height,
    required int quality,
    required PhotoFormat format,
  }) async {
    calls.add(EncoderCall(png, width, height, quality, format));
    return format == PhotoFormat.webp ? webp : jpeg;
  }
}

Uint8List fakeJpeg(int length) {
  final bytes = Uint8List(length < 12 ? 12 : length);
  bytes.setAll(0, const [0xFF, 0xD8, 0xFF, 0xE0, 0, 16, 0x4A, 0x46, 0x49, 0x46, 0, 1]);
  return bytes;
}

void useFakePhotos({required MemoryPhotoPicker picker, required FakeEncoder encoder}) {
  final systemPicker = MemoryPhotos.picker;
  final systemEncoder = PhotoCompressor.encoder;
  MemoryPhotos.picker = picker;
  PhotoCompressor.encoder = encoder.call;
  addTearDown(() {
    MemoryPhotos.picker = systemPicker;
    PhotoCompressor.encoder = systemEncoder;
  });
}
