import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/presentation/screens/polaroids/photo_compression.dart';

import 'memories_harness.dart';

Matcher failsWith(String message) =>
    throwsA(isA<PhotoCompressionError>().having((error) => error.message, 'message', message));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('calculatePhotoSize', () {
    test('keeps the longest side at 1440 like the web canvas', () {
      expect(calculatePhotoSize(4000, 3000, 1440, 1440), const PhotoSize(1440, 1080));
      expect(calculatePhotoSize(3000, 4000, 1440, 1440), const PhotoSize(1080, 1440));
      expect(calculatePhotoSize(2880, 720, 1440, 1440), const PhotoSize(1440, 360));
      expect(calculatePhotoSize(720, 2880, 1440, 1440), const PhotoSize(360, 1440));
    });

    test('never enlarges a small photo', () {
      expect(calculatePhotoSize(800, 600, 1440, 1440), const PhotoSize(800, 600));
      expect(calculatePhotoSize(1440, 1440, 1440, 1440), const PhotoSize(1440, 1440));
    });

    test('rounds halves up and never drops below one pixel', () {
      expect(calculatePhotoSize(2880, 1441, 1440, 1440), const PhotoSize(1440, 721));
      expect(calculatePhotoSize(2000, 1999, 1440, 1440), const PhotoSize(1440, 1439));
      expect(calculatePhotoSize(1, 5000, 1440, 1440), const PhotoSize(1, 1440));
      expect(calculatePhotoSize(5000, 1, 1440, 1440), const PhotoSize(1440, 1));
    });

    test('runs the width pass before the height pass', () {
      expect(calculatePhotoSize(3000, 2500, 1440, 1000), const PhotoSize(1200, 1000));
    });
  });

  group('sniffImageMime', () {
    test('tells webp, jpeg and png apart', () {
      expect(sniffImageMime(tinyWebp), 'image/webp');
      expect(sniffImageMime(fakeJpeg(64)), 'image/jpeg');
      expect(sniffImageMime(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 13, 10, 26, 10, 0, 0, 0, 13])), 'image/png');
      expect(sniffImageMime(Uint8List(4)), isNull);
      expect(sniffImageMime(null), isNull);
    });
  });

  group('compressPhoto', () {
    test('shrinks to 1440 and asks for webp at quality 85', () async {
      final source = await testPng(2880, 720);
      final encoder = FakeEncoder(webp: tinyWebp, jpeg: fakeJpeg(8));
      final photo = await compressPhoto(source, encoder: encoder.call);

      expect(photo.mime, 'image/webp');
      expect(photo.bytes, tinyWebp);
      expect(photo.width, 1440);
      expect(photo.height, 360);
      expect(photo.originalBytes, source.length);
      expect(encoder.calls, hasLength(1));
      final call = encoder.calls.single;
      expect(call.format, PhotoFormat.webp);
      expect(call.quality, 85);
      expect(call.width, 1440);
      expect(call.height, 360);
      expect(await pngSize(call.png), const Size(1440, 360));
    });

    test('keeps a small photo at its own size', () async {
      final source = await testPng(640, 480);
      final encoder = FakeEncoder(webp: tinyWebp);
      final photo = await compressPhoto(source, encoder: encoder.call);
      expect(photo.width, 640);
      expect(photo.height, 480);
      expect(await pngSize(encoder.calls.single.png), const Size(640, 480));
    });

    test('falls back to jpeg when webp is not available', () async {
      final source = await testPng(300, 200);
      final jpeg = fakeJpeg(40);
      final encoder = FakeEncoder(webp: null, jpeg: jpeg);
      final photo = await compressPhoto(source, encoder: encoder.call);
      expect(photo.mime, 'image/jpeg');
      expect(photo.bytes, jpeg);
      expect(encoder.calls.map((call) => call.format), [PhotoFormat.webp, PhotoFormat.jpeg]);
    });

    test('keeps a smaller non-webp result over a bigger jpeg, like the web', () async {
      final source = await testPng(300, 200);
      final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 13, 10, 26, 10, 0, 0, 0, 13, 1, 2]);
      final encoder = FakeEncoder(webp: png, jpeg: fakeJpeg(400));
      final photo = await compressPhoto(source, encoder: encoder.call);
      expect(photo.mime, 'image/png');
      expect(photo.bytes, png);
    });

    test('says so gently when nothing could be made', () async {
      final source = await testPng(300, 200);
      await expectLater(
        compressPhoto(source, encoder: FakeEncoder().call),
        failsWith('This phone could not re-encode the photo. Try a different image.'),
      );
    });

    test('treats a throwing encoder like a missing format', () async {
      final source = await testPng(300, 200);
      Future<Uint8List?> broken(
        Uint8List png, {
        required int width,
        required int height,
        required int quality,
        required PhotoFormat format,
      }) async {
        if (format == PhotoFormat.webp) throw StateError('no webp here');
        return fakeJpeg(20);
      }

      final photo = await compressPhoto(source, encoder: broken);
      expect(photo.mime, 'image/jpeg');
    });

    test('refuses empty and unreadable files with the web wording', () async {
      await expectLater(compressPhoto(null, encoder: FakeEncoder().call), failsWith('No photo was selected.'));
      await expectLater(compressPhoto(Uint8List(0), encoder: FakeEncoder().call), failsWith('That file is empty.'));
      await expectLater(
        compressPhoto(Uint8List.fromList(List<int>.generate(64, (i) => i)), encoder: FakeEncoder().call),
        failsWith('That file is not an image this phone can open.'),
      );
    });
  });
}
