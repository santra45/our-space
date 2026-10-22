import 'dart:collection';
import 'dart:typed_data';

import '../../../core/engine.dart';
import 'memories_copy.dart';

class MemoryPhotoCache {
  MemoryPhotoCache({this.capacity = 24});

  final int capacity;
  final LinkedHashMap<String, Uint8List> _entries = LinkedHashMap<String, Uint8List>();

  static String keyOf(MemoryRecord memory) => '${memory.id}|${memory.updatedAt}|${memory.mime ?? ''}';

  Uint8List? get(MemoryRecord memory) {
    final key = keyOf(memory);
    final hit = _entries.remove(key);
    if (hit != null) _entries[key] = hit;
    return hit;
  }

  void put(MemoryRecord memory, Uint8List bytes) {
    final key = keyOf(memory);
    _entries.remove(key);
    _entries[key] = bytes;
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
    }
  }

  void clear() => _entries.clear();
}

const String _pictographPattern = r'[\p{Extended_Pictographic}\u{1F3FB}-\u{1F3FF}\u{FE0F}\u{200D}\u{20E3}]+';
final RegExp _pictographs = RegExp(_pictographPattern, unicode: true);
final RegExp _spaces = RegExp(r'\s+');

String calmCaption(String caption) {
  final cleaned = caption.replaceAll(_pictographs, ' ').replaceAll(_spaces, ' ').trim();
  return cleaned.isEmpty ? MemoriesCopy.specialMoment : cleaned;
}

DateTime? memoryDay(MemoryRecord memory) {
  final date = memory.date;
  if (date == null || date.isEmpty) return null;
  return parseLocalDate(date);
}

int memoryHash(String id) {
  var hash = 0;
  for (final unit in id.codeUnits) {
    hash += unit;
  }
  return hash;
}

enum PolaroidPin { tape, pin }

abstract final class PolaroidLook {
  static const List<double> ratios = [1.49, 1.10, 1.30];

  static double ratioOf(String id) => ratios[(memoryHash(id) ~/ 5) % ratios.length];

  static PolaroidPin pinOf(String id) => (memoryHash(id) ~/ 3).isEven ? PolaroidPin.tape : PolaroidPin.pin;
}
