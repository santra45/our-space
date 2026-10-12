import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_image_compress/flutter_image_compress.dart';

const String preferredImageMime = 'image/webp';
const String fallbackImageMime = 'image/jpeg';

const int maxPhotoSide = 1440;
const double photoQuality = 0.85;

enum PhotoFormat { webp, jpeg }

typedef PhotoEncoder = Future<Uint8List?> Function(
  Uint8List png, {
  required int width,
  required int height,
  required int quality,
  required PhotoFormat format,
});

class PhotoCompressionError implements Exception {
  PhotoCompressionError(this.message);

  final String message;

  @override
  String toString() => message;
}

class PhotoSize {
  const PhotoSize(this.width, this.height);

  final int width;
  final int height;

  @override
  bool operator ==(Object other) => other is PhotoSize && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => '${width}x$height';
}

class CompressedPhoto {
  const CompressedPhoto({
    required this.bytes,
    required this.mime,
    required this.width,
    required this.height,
    required this.originalBytes,
  });

  final Uint8List bytes;
  final String mime;
  final int width;
  final int height;
  final int originalBytes;
}

int _jsRound(double value) => (value + 0.5).floor();

PhotoSize calculatePhotoSize(int sourceWidth, int sourceHeight, int maxWidth, int maxHeight) {
  var width = sourceWidth;
  var height = sourceHeight;
  if (width > maxWidth) {
    height = _jsRound(height * maxWidth / width);
    width = maxWidth;
  }
  if (height > maxHeight) {
    width = _jsRound(width * maxHeight / height);
    height = maxHeight;
  }
  return PhotoSize(width < 1 ? 1 : width, height < 1 ? 1 : height);
}

String? sniffImageMime(Uint8List? bytes) {
  if (bytes == null || bytes.length < 12) return null;
  if (bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
      bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50) {
    return 'image/webp';
  }
  if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) return 'image/jpeg';
  if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) return 'image/png';
  return null;
}

Future<Uint8List?> encodeWithPlatform(
  Uint8List png, {
  required int width,
  required int height,
  required int quality,
  required PhotoFormat format,
}) async {
  try {
    final out = await FlutterImageCompress.compressWithList(
      png,
      minWidth: width,
      minHeight: height,
      quality: quality,
      format: format == PhotoFormat.webp ? CompressFormat.webp : CompressFormat.jpeg,
      autoCorrectionAngle: false,
      keepExif: false,
    );
    return out.isEmpty ? null : out;
  } catch (_) {
    return null;
  }
}

abstract final class PhotoCompressor {
  static PhotoEncoder encoder = encodeWithPlatform;
}

Future<Uint8List> _drawAt(ui.ImageDescriptor descriptor, PhotoSize size) async {
  final codec = await descriptor.instantiateCodec(targetWidth: size.width, targetHeight: size.height);
  try {
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('no pixels');
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      image.dispose();
    }
  } finally {
    codec.dispose();
  }
}

Future<Uint8List?> _encode(PhotoEncoder encoder, Uint8List png, PhotoSize size, int quality, PhotoFormat format) async {
  try {
    return await encoder(png, width: size.width, height: size.height, quality: quality, format: format);
  } catch (_) {
    return null;
  }
}

Future<CompressedPhoto> compressPhoto(
  Uint8List? bytes, {
  int maxWidth = maxPhotoSide,
  int maxHeight = maxPhotoSide,
  double quality = photoQuality,
  PhotoEncoder? encoder,
}) async {
  if (bytes == null) throw PhotoCompressionError('No photo was selected.');
  if (bytes.isEmpty) throw PhotoCompressionError('That file is empty.');

  ui.ImmutableBuffer buffer;
  ui.ImageDescriptor descriptor;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  } catch (_) {
    throw PhotoCompressionError('That file could not be opened.');
  }
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
  } catch (_) {
    buffer.dispose();
    throw PhotoCompressionError('That file is not an image this phone can open.');
  }

  PhotoSize size;
  Uint8List png;
  try {
    final sourceWidth = descriptor.width;
    final sourceHeight = descriptor.height;
    if (sourceWidth <= 0 || sourceHeight <= 0) {
      throw PhotoCompressionError('That file could not be read as a photo.');
    }
    size = calculatePhotoSize(sourceWidth, sourceHeight, maxWidth, maxHeight);
    try {
      png = await _drawAt(descriptor, size);
    } catch (_) {
      throw PhotoCompressionError('That file is not an image this phone can open.');
    }
  } finally {
    descriptor.dispose();
    buffer.dispose();
  }

  final encode = encoder ?? PhotoCompressor.encoder;
  final level = (quality * 100).round().clamp(0, 100);
  var blob = await _encode(encode, png, size, level, PhotoFormat.webp);
  var type = sniffImageMime(blob);
  if (blob == null || blob.isEmpty || type != preferredImageMime) {
    final jpeg = await _encode(encode, png, size, level, PhotoFormat.jpeg);
    if (jpeg != null && jpeg.isNotEmpty && (blob == null || blob.isEmpty || jpeg.length < blob.length)) {
      blob = jpeg;
      type = sniffImageMime(jpeg);
    }
  }

  if (blob == null || blob.isEmpty) {
    throw PhotoCompressionError('This phone could not re-encode the photo. Try a different image.');
  }

  return CompressedPhoto(
    bytes: blob,
    mime: type ?? fallbackImageMime,
    width: size.width,
    height: size.height,
    originalBytes: bytes.length,
  );
}
