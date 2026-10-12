import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

const int saltLengthBytes = 16;
const int ivLengthBytes = 12;

final Random _secureRandom = Random.secure();

class Base64FormatError implements Exception {
  Base64FormatError(this.message);
  final String message;
  @override
  String toString() => message;
}

Uint8List randomBytes(int length) {
  final out = Uint8List(length);
  for (var i = 0; i < length; i++) {
    out[i] = _secureRandom.nextInt(256);
  }
  return out;
}

String bufferToBase64(List<int> bytes) => base64.encode(bytes);

String toUrlSafeBase64(String value) =>
    value.replaceAll('+', '-').replaceAll('/', '_').replaceAll(RegExp(r'=+$'), '');

String generateSecureNonce([int byteLength = 16]) => bufferToBase64(randomBytes(byteLength));

String generateUrlSafeNonce([int byteLength = 16]) => toUrlSafeBase64(generateSecureNonce(byteLength));

String generateSalt() => bufferToBase64(randomBytes(saltLengthBytes));

String randomUuidV4() {
  final bytes = randomBytes(16);
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}';
}

const String _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

final Int16List _decodeTable = () {
  final table = Int16List(128)..fillRange(0, 128, -1);
  for (var i = 0; i < _alphabet.length; i++) {
    table[_alphabet.codeUnitAt(i)] = i;
  }
  return table;
}();

bool _isAsciiWhitespace(int c) => c == 0x09 || c == 0x0A || c == 0x0C || c == 0x0D || c == 0x20;

Uint8List forgivingBase64Decode(String input) {
  final cleaned = StringBuffer();
  for (var i = 0; i < input.length; i++) {
    final c = input.codeUnitAt(i);
    if (_isAsciiWhitespace(c)) continue;
    cleaned.writeCharCode(c);
  }
  var data = cleaned.toString();
  if (data.length % 4 == 0) {
    if (data.endsWith('==')) {
      data = data.substring(0, data.length - 2);
    } else if (data.endsWith('=')) {
      data = data.substring(0, data.length - 1);
    }
  }
  if (data.length % 4 == 1) {
    throw Base64FormatError('The string to be decoded is not correctly encoded.');
  }
  final out = BytesBuilder(copy: false);
  var buffer = 0;
  var bits = 0;
  final chunk = <int>[];
  for (var i = 0; i < data.length; i++) {
    final c = data.codeUnitAt(i);
    final value = c < 128 ? _decodeTable[c] : -1;
    if (value < 0) {
      throw Base64FormatError('The string to be decoded is not correctly encoded.');
    }
    buffer = (buffer << 6) | value;
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      chunk.add((buffer >> bits) & 0xFF);
      buffer &= (1 << bits) - 1;
    }
    if (chunk.length >= 4096) {
      out.add(Uint8List.fromList(chunk));
      chunk.clear();
    }
  }
  if (chunk.isNotEmpty) out.add(Uint8List.fromList(chunk));
  return out.takeBytes();
}

Uint8List base64ToBuffer(Object? value) {
  if (value is! String) {
    throw Base64FormatError('base64ToBuffer: expected a string');
  }
  var normalized = value.replaceAll('-', '+').replaceAll('_', '/');
  final remainder = normalized.length % 4;
  if (remainder == 1) {
    throw Base64FormatError('base64ToBuffer: malformed base64 input');
  }
  if (remainder > 0) {
    normalized += '=' * (4 - remainder);
  }
  return forgivingBase64Decode(normalized);
}

final RegExp _base64Shape = RegExp(r'^[A-Za-z0-9+/\-_]+={0,2}$');

bool isValidBase64(Object? value, [int? byteLength]) {
  if (value is! String || value.isEmpty) return false;
  if (!_base64Shape.hasMatch(value)) return false;
  try {
    final bytes = base64ToBuffer(value);
    if (byteLength != null && bytes.length != byteLength) return false;
    return true;
  } catch (_) {
    return false;
  }
}

bool isValidSalt(Object? value) => isValidBase64(value, saltLengthBytes);
