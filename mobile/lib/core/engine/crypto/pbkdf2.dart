import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;

const List<int> _roundConstants = [
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
];

const List<int> _initialState = [
  0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
];

final Uint32List _k = Uint32List.fromList(_roundConstants);

const int _mask = 0xFFFFFFFF;

int _rotr(int x, int n) => ((x >> n) | (x << (32 - n))) & _mask;

void _compress(Uint32List state, Uint32List w) {
  for (var t = 16; t < 64; t++) {
    final w15 = w[t - 15];
    final w2 = w[t - 2];
    final s0 = _rotr(w15, 7) ^ _rotr(w15, 18) ^ (w15 >> 3);
    final s1 = _rotr(w2, 17) ^ _rotr(w2, 19) ^ (w2 >> 10);
    w[t] = (w[t - 16] + s0 + w[t - 7] + s1) & _mask;
  }
  var a = state[0];
  var b = state[1];
  var c = state[2];
  var d = state[3];
  var e = state[4];
  var f = state[5];
  var g = state[6];
  var h = state[7];
  for (var t = 0; t < 64; t++) {
    final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
    final ch = (e & f) ^ ((~e & _mask) & g);
    final temp1 = (h + s1 + ch + _k[t] + w[t]) & _mask;
    final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
    final maj = (a & b) ^ (a & c) ^ (b & c);
    final temp2 = (s0 + maj) & _mask;
    h = g;
    g = f;
    f = e;
    e = (d + temp1) & _mask;
    d = c;
    c = b;
    b = a;
    a = (temp1 + temp2) & _mask;
  }
  state[0] = (state[0] + a) & _mask;
  state[1] = (state[1] + b) & _mask;
  state[2] = (state[2] + c) & _mask;
  state[3] = (state[3] + d) & _mask;
  state[4] = (state[4] + e) & _mask;
  state[5] = (state[5] + f) & _mask;
  state[6] = (state[6] + g) & _mask;
  state[7] = (state[7] + h) & _mask;
}

Uint32List _padStateFor(List<int> key, int pad) {
  final w = Uint32List(64);
  for (var i = 0; i < 16; i++) {
    var word = 0;
    for (var j = 0; j < 4; j++) {
      final index = i * 4 + j;
      final byte = index < key.length ? key[index] : 0;
      word = (word << 8) | (byte ^ pad);
    }
    w[i] = word;
  }
  final state = Uint32List.fromList(_initialState);
  _compress(state, w);
  return state;
}

void _hashDigestBlock(Uint32List startState, Uint32List digestWords, Uint32List outState, Uint32List w) {
  for (var i = 0; i < 8; i++) {
    outState[i] = startState[i];
    w[i] = digestWords[i];
  }
  w[8] = 0x80000000;
  for (var i = 9; i < 15; i++) {
    w[i] = 0;
  }
  w[15] = (64 + 32) * 8;
  _compress(outState, w);
}

Uint8List pbkdf2HmacSha256(List<int> password, List<int> salt, int iterations, int length) {
  if (iterations < 1) throw ArgumentError('iterations must be at least 1');
  if (length < 1) throw ArgumentError('length must be at least 1');
  final key = password.length > 64 ? hash.sha256.convert(password).bytes : password;
  final innerStart = _padStateFor(key, 0x36);
  final outerStart = _padStateFor(key, 0x5c);
  final hmac = hash.Hmac(hash.sha256, key);

  final out = Uint8List(length);
  final blocks = (length + 31) ~/ 32;
  final w = Uint32List(64);
  final inner = Uint32List(8);
  final u = Uint32List(8);
  final t = Uint32List(8);

  for (var block = 1; block <= blocks; block++) {
    final first = BytesBuilder(copy: false)
      ..add(salt)
      ..add([(block >> 24) & 0xFF, (block >> 16) & 0xFF, (block >> 8) & 0xFF, block & 0xFF]);
    final u1 = hmac.convert(first.takeBytes()).bytes;
    for (var i = 0; i < 8; i++) {
      final word = (u1[i * 4] << 24) | (u1[i * 4 + 1] << 16) | (u1[i * 4 + 2] << 8) | u1[i * 4 + 3];
      u[i] = word;
      t[i] = word;
    }
    for (var iteration = 1; iteration < iterations; iteration++) {
      _hashDigestBlock(innerStart, u, inner, w);
      _hashDigestBlock(outerStart, inner, u, w);
      for (var i = 0; i < 8; i++) {
        t[i] ^= u[i];
      }
    }
    final offset = (block - 1) * 32;
    for (var i = 0; i < 32 && offset + i < length; i++) {
      final word = t[i >> 2];
      out[offset + i] = (word >> (24 - 8 * (i & 3))) & 0xFF;
    }
  }
  return out;
}

Future<Uint8List> pbkdf2HmacSha256Async(
  List<int> password,
  List<int> salt,
  int iterations,
  int length,
) async {
  if (iterations <= 20000) {
    return pbkdf2HmacSha256(password, salt, iterations, length);
  }
  final passwordCopy = Uint8List.fromList(password);
  final saltCopy = Uint8List.fromList(salt);
  return Isolate.run(() => pbkdf2HmacSha256(passwordCopy, saltCopy, iterations, length));
}

Uint8List hmacSha256(List<int> key, List<int> data) =>
    Uint8List.fromList(hash.Hmac(hash.sha256, key).convert(data).bytes);

Uint8List sha256Bytes(List<int> data) => Uint8List.fromList(hash.sha256.convert(data).bytes);

Uint8List hkdfSha256({
  required List<int> ikm,
  required List<int> salt,
  required List<int> info,
  required int length,
}) {
  final prk = hmacSha256(salt.isEmpty ? Uint8List(32) : salt, ikm);
  final out = BytesBuilder(copy: false);
  var previous = Uint8List(0);
  var counter = 1;
  var produced = 0;
  while (produced < length) {
    final input = BytesBuilder(copy: false)
      ..add(previous)
      ..add(info)
      ..addByte(counter);
    previous = hmacSha256(prk, input.takeBytes());
    out.add(previous);
    produced += previous.length;
    counter++;
  }
  return Uint8List.sublistView(out.takeBytes(), 0, length);
}
