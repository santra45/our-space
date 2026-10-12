import 'dart:typed_data';

import 'binary_pack.dart';

const int chunkedMtu = 16300;

class PeerFrameResult {
  const PeerFrameResult._(this.kind, this.data);

  const PeerFrameResult.partial() : this._(PeerFrameKind.partial, null);

  const PeerFrameResult.close() : this._(PeerFrameKind.close, null);

  const PeerFrameResult.message(Object? data) : this._(PeerFrameKind.message, data);

  final PeerFrameKind kind;
  final Object? data;
}

enum PeerFrameKind { message, partial, close }

class _ChunkEntry {
  _ChunkEntry(this.total);
  final Object? total;
  final Map<int, Uint8List> parts = <int, Uint8List>{};
  int count = 0;
}

class PeerFraming {
  int _dataCount = 1;
  final Map<String, _ChunkEntry> _chunks = <String, _ChunkEntry>{};

  List<Uint8List> encode(Object? data) {
    final blob = binaryPack(data);
    if (blob.length <= chunkedMtu) return [blob];
    return [for (final chunk in chunk(blob)) binaryPack(chunk)];
  }

  List<Map<String, Object?>> chunk(Uint8List blob) {
    final chunks = <Map<String, Object?>>[];
    final size = blob.length;
    final total = (size / chunkedMtu).ceil();
    var index = 0;
    var start = 0;
    while (start < size) {
      final end = start + chunkedMtu < size ? start + chunkedMtu : size;
      chunks.add({
        '__peerData': _dataCount,
        'n': index,
        'data': Uint8List.fromList(Uint8List.sublistView(blob, start, end)),
        'total': total,
      });
      start = end;
      index++;
    }
    _dataCount++;
    return chunks;
  }

  PeerFrameResult decode(Uint8List frame) {
    final data = binaryUnpack(frame);
    final peerData = data is Map ? data['__peerData'] : null;
    if (_truthy(peerData)) {
      if (peerData is Map && peerData['type'] == 'close') {
        return const PeerFrameResult.close();
      }
      return _handleChunk(data as Map, peerData);
    }
    return PeerFrameResult.message(data);
  }

  PeerFrameResult _handleChunk(Map<Object?, Object?> data, Object? peerData) {
    final id = jsPropertyKey(peerData);
    final entry = _chunks[id] ?? _ChunkEntry(data['total']);
    final n = data['n'];
    final part = data['data'];
    final index = n is num ? n.toInt() : -1;
    entry.parts[index] = part is Uint8List ? part : Uint8List(0);
    entry.count++;
    _chunks[id] = entry;
    final total = entry.total;
    if (total is num && total == entry.count) {
      _chunks.remove(id);
      final keys = entry.parts.keys.where((k) => k >= 0).toList()..sort();
      final builder = BytesBuilder(copy: false);
      for (final key in keys) {
        builder.add(entry.parts[key]!);
      }
      return decode(builder.takeBytes());
    }
    return const PeerFrameResult.partial();
  }

  void reset() => _chunks.clear();
}

bool _truthy(Object? value) {
  if (value == null || value == false) return false;
  if (value is num) return value != 0 && !value.isNaN;
  if (value is String) return value.isNotEmpty;
  return true;
}
