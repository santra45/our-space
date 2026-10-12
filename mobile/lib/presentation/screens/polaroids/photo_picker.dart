import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

enum PhotoSource { camera, gallery }

class PickedPhoto {
  const PickedPhoto({required this.bytes, this.name = ''});

  final Uint8List bytes;
  final String name;
}

class PhotoPickFailure implements Exception {
  PhotoPickFailure(this.source);

  final PhotoSource source;
}

typedef MemoryPhotoPicker = Future<PickedPhoto?> Function(PhotoSource source);

Future<PickedPhoto?> pickWithImagePicker(PhotoSource source) async {
  XFile? file;
  try {
    file = await ImagePicker().pickImage(
      source: source == PhotoSource.camera ? ImageSource.camera : ImageSource.gallery,
      preferredCameraDevice: CameraDevice.rear,
      requestFullMetadata: false,
    );
  } catch (_) {
    throw PhotoPickFailure(source);
  }
  if (file == null) return null;
  try {
    return PickedPhoto(bytes: await file.readAsBytes(), name: file.name);
  } catch (_) {
    throw PhotoPickFailure(source);
  }
}

abstract final class MemoryPhotos {
  static MemoryPhotoPicker picker = pickWithImagePicker;

  static Future<PickedPhoto?> pick(PhotoSource source) => picker(source);
}
