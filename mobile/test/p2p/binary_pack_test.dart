import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine/crypto/js_compat.dart';
import 'package:our_space_mobile/core/engine/p2p/binary_pack.dart';
import 'package:our_space_mobile/core/engine/p2p/peer_framing.dart';

import 'support/fixtures.dart';

Object? untag(Object? value) {
  if (value is List) return value.map(untag).toList();
  if (value is Map) {
    if (value.containsKey(r'$undefined')) return null;
    if (value.containsKey(r'$bytes')) return Uint8List.fromList(base64.decode(value[r'$bytes'] as String));
    if (value.containsKey(r'$number')) {
      return switch (value[r'$number']) {
        'NaN' => double.nan,
        'Infinity' => double.infinity,
        '-Infinity' => double.negativeInfinity,
        _ => -0.0,
      };
    }
    final map = value[r'$map'] as Map;
    return {for (final entry in map.entries) entry.key as String: untag(entry.value)};
  }
  return value;
}

bool sameValue(Object? a, Object? b) {
  if (a is Uint8List && b is Uint8List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
  if (a is num && b is num) {
    if (a.isNaN && b.isNaN) return true;
    return a == b;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!sameValue(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !sameValue(a[key], b[key])) return false;
    }
    return true;
  }
  return a == b;
}

Uint8List seededBytes(String seed, int length) {
  final out = Uint8List(length);
  var block = sha256.convert(utf8.encode(seed)).bytes;
  var offset = 0;
  while (offset < length) {
    for (var i = 0; i < block.length && offset < length; i++) {
      out[offset++] = block[i];
    }
    block = sha256.convert(block).bytes;
  }
  return out;
}

Object? generated(Map<String, Object?> spec) {
  final count = spec['count'] as int;
  return switch (spec[r'$gen']) {
    'repeat' => (spec['char'] as String) * count,
    'seq' => [for (var i = 0; i < count; i++) i % (spec['mod'] as int)],
    'bytes' => seededBytes(spec['seed'] as String, count),
    'keys' => {for (var i = 0; i < count; i++) 'k$i': i.isEven},
    _ => throw StateError('unknown generator'),
  };
}

String hex(List<int> bytes) => hexOf(bytes);

Uint8List fromHex(String text) =>
    Uint8List.fromList([for (var i = 0; i < text.length; i += 2) int.parse(text.substring(i, i + 2), radix: 16)]);

void main() {
  final vectors = readP2pFixture('binary_pack_vectors.json');

  group('BinaryPack matches peerjs-js-binarypack 2.1.0 byte for byte', () {
    final packed = (vectors['packed'] as List).cast<Map<String, Object?>>();
    for (final vector in packed) {
      final value = untag(vector['value']);
      final label = jsonEncode(vector['value']);
      test('pack ${label.length > 60 ? '${label.substring(0, 60)}…' : label}', () {
        if (vector['error'] == true) {
          expect(() => binaryPack(value), throwsA(isA<BinaryPackError>()));
          return;
        }
        expect(hex(binaryPack(value)), vector['hex']);
        expect(sameValue(binaryUnpack(fromHex(vector['hex'] as String)), untag(vector['unpacked'])), isTrue);
      });
    }

    test('large strings, arrays, maps and bytes use the 16 and 32 bit headers', () {
      for (final vector in (vectors['large'] as List).cast<Map<String, Object?>>()) {
        final value = generated((vector['spec'] as Map).cast<String, Object?>());
        final bytes = binaryPack(value);
        expect(bytes.length, vector['length']);
        expect(hex(bytes.sublist(0, 16)), vector['prefix']);
        expect(sha256.convert(bytes).toString(), vector['sha256']);
        expect(sameValue(binaryUnpack(bytes), value), isTrue);
      }
    });

    test('unpacks every type tag the way the web does', () {
      for (final vector in (vectors['unpacked'] as List).cast<Map<String, Object?>>()) {
        final input = fromHex(vector['hex'] as String);
        if (vector['error'] == true) {
          expect(() => binaryUnpack(input), throwsA(anything), reason: vector['hex'] as String);
          continue;
        }
        expect(sameValue(binaryUnpack(input), untag(vector['value'])), isTrue, reason: vector['hex'] as String);
      }
    });
  });

  group('chunking matches the PeerJS BinaryPack data connection', () {
    final chunking = (vectors['chunking'] as Map).cast<String, Object?>();
    final message = Uint8List.fromList(base64.decode(chunking['message'] as String));
    final frames = (chunking['frames'] as List).cast<String>();

    test('splits at the same 16300 byte MTU into identical frames', () {
      expect(chunking['mtu'], chunkedMtu);
      final framing = PeerFraming();
      final ours = framing.chunk(message).map(binaryPack).map(base64.encode).toList();
      expect(ours, frames);
    });

    test('encode sends small messages whole and large ones chunked', () {
      final framing = PeerFraming();
      final small = framing.encode({'protocol': 'SWEETHEART_V2', 'payload': {'ciphertext': 'abc', 'iv': 'def'}});
      expect(small, hasLength(1));
      final decoded = binaryUnpack(message);
      final large = PeerFraming().encode(decoded);
      expect(large.map(base64.encode).toList(), frames);
    });

    test('reassembles web chunks, in any order, back into the message', () {
      final framing = PeerFraming();
      final shuffled = [...frames.reversed];
      PeerFrameResult? last;
      for (final frame in shuffled) {
        last = framing.decode(Uint8List.fromList(base64.decode(frame)));
      }
      expect(last!.kind, PeerFrameKind.message);
      expect(sameValue(last.data, binaryUnpack(message)), isTrue);
    });

    test('a close request from the other side is recognised', () {
      final framing = PeerFraming();
      final result = framing.decode(binaryPack({
        '__peerData': {'type': 'close'},
      }));
      expect(result.kind, PeerFrameKind.close);
    });
  });

  test('the capture tool that made these vectors is kept with them', () {
    expect(File('test/p2p/tool/capture_web_peer.mjs').existsSync(), isTrue);
  });
}
