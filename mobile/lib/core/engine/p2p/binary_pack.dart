import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

class BinaryPackError implements Exception {
  BinaryPackError(this.message);
  final String message;
  @override
  String toString() => message;
}

const double _two32 = 4294967296.0;

Uint8List binaryPack(Object? value) {
  final packer = _Packer();
  packer.pack(value);
  return packer.takeBytes();
}

Object? binaryUnpack(List<int> data) => _Unpacker(data is Uint8List ? data : Uint8List.fromList(data)).unpack();

int _toInt32(num value) {
  if (value is int) return value.toSigned(32);
  if (!value.isFinite) return 0;
  final truncated = value.truncateToDouble();
  final modulo = truncated % _two32;
  final asInt = modulo.toInt();
  return asInt.toSigned(32);
}

int _toUint32(num value) => _toInt32(value) & 0xffffffff;

class _Packer {
  final BytesBuilder _out = BytesBuilder(copy: false);
  final List<int> _pieces = <int>[];

  void _append(num byte) => _pieces.add(_toInt32(byte) & 0xff);

  void _flush() {
    if (_pieces.isEmpty) return;
    _out.add(Uint8List.fromList(_pieces));
    _pieces.clear();
  }

  void _appendBuffer(List<int> bytes) {
    _flush();
    _out.add(bytes is Uint8List ? bytes : Uint8List.fromList(bytes));
  }

  Uint8List takeBytes() {
    _flush();
    return _out.takeBytes();
  }

  void pack(Object? value) {
    if (value is String) {
      _packString(value);
    } else if (value is num) {
      if (value is int || (value.isFinite && value.floorToDouble() == value) || value.isInfinite) {
        _packInteger(value);
      } else {
        _packDouble(value.toDouble());
      }
    } else if (value is bool) {
      _append(value ? 0xc3 : 0xc2);
    } else if (value == null) {
      _append(0xc0);
    } else if (value is Uint8List) {
      _packBin(value);
    } else if (value is ByteBuffer) {
      _packBin(value.asUint8List());
    } else if (value is TypedData) {
      _packBin(value.buffer.asUint8List(value.offsetInBytes, value.lengthInBytes));
    } else if (value is List) {
      _packArray(value);
    } else if (value is Map) {
      _packObject(value);
    } else {
      throw BinaryPackError('Type "${value.runtimeType}" not yet supported');
    }
    _flush();
  }

  void _packBin(Uint8List blob) {
    final length = blob.length;
    if (length <= 0x0f) {
      _append(0xa0 + length);
    } else if (length <= 0xffff) {
      _append(0xda);
      _packUint16(length);
    } else if (length <= 0xffffffff) {
      _append(0xdb);
      _packUint32(length);
    } else {
      throw BinaryPackError('Invalid length');
    }
    _appendBuffer(blob);
  }

  void _packString(String value) {
    final encoded = utf8.encode(value);
    final length = encoded.length;
    if (length <= 0x0f) {
      _append(0xb0 + length);
    } else if (length <= 0xffff) {
      _append(0xd8);
      _packUint16(length);
    } else if (length <= 0xffffffff) {
      _append(0xd9);
      _packUint32(length);
    } else {
      throw BinaryPackError('Invalid length');
    }
    _appendBuffer(encoded);
  }

  void _packArray(List<Object?> list) {
    final length = list.length;
    if (length <= 0x0f) {
      _append(0x90 + length);
    } else if (length <= 0xffff) {
      _append(0xdc);
      _packUint16(length);
    } else if (length <= 0xffffffff) {
      _append(0xdd);
      _packUint32(length);
    } else {
      throw BinaryPackError('Invalid length');
    }
    for (final item in list) {
      pack(item);
    }
  }

  void _packObject(Map<Object?, Object?> map) {
    final length = map.length;
    if (length <= 0x0f) {
      _append(0x80 + length);
    } else if (length <= 0xffff) {
      _append(0xde);
      _packUint16(length);
    } else if (length <= 0xffffffff) {
      _append(0xdf);
      _packUint32(length);
    } else {
      throw BinaryPackError('Invalid length');
    }
    map.forEach((key, entry) {
      pack(jsPropertyKey(key));
      pack(entry);
    });
  }

  void _packInteger(num value) {
    if (value >= -0x20 && value <= 0x7f) {
      _append(value);
    } else if (value >= 0x00 && value <= 0xff) {
      _append(0xcc);
      _append(value);
    } else if (value >= -0x80 && value <= 0x7f) {
      _append(0xd0);
      _append(value);
    } else if (value >= 0x0000 && value <= 0xffff) {
      _append(0xcd);
      _packUint16(value);
    } else if (value >= -0x8000 && value <= 0x7fff) {
      _append(0xd1);
      _append((_toInt32(value) & 0xff00) >> 8);
      _append(value);
    } else if (value >= 0x00000000 && value <= 0xffffffff) {
      _append(0xce);
      _packUint32(value);
    } else if (value >= -0x80000000 && value <= 0x7fffffff) {
      _append(0xd2);
      _packInt32(value);
    } else if (value >= -9223372036854775808.0 && value <= 9223372036854775808.0) {
      _append(0xd3);
      _packInt64(value);
    } else if (value >= 0 && value <= 18446744073709551616.0) {
      _append(0xcf);
      _packUint64(value);
    } else {
      throw BinaryPackError('Invalid integer');
    }
  }

  void _packUint16(num value) {
    _append(_toInt32(value) >> 8);
    _append(value);
  }

  void _packUint32(num value) {
    final n = _toUint32(value);
    _append((n >> 24) & 0xff);
    _append((n >> 16) & 0xff);
    _append((n >> 8) & 0xff);
    _append(n & 0xff);
  }

  void _packInt32(num value) {
    final n = _toUint32(value);
    _append((n >> 24) & 0xff);
    _append((n >> 16) & 0xff);
    _append((n >> 8) & 0xff);
    _append(n & 0xff);
  }

  void _packWords(num high, num low) {
    final h = _toUint32(high);
    final l = _toUint32(low);
    _append((h >> 24) & 0xff);
    _append((h >> 16) & 0xff);
    _append((h >> 8) & 0xff);
    _append(h & 0xff);
    _append((l >> 24) & 0xff);
    _append((l >> 16) & 0xff);
    _append((l >> 8) & 0xff);
    _append(l & 0xff);
  }

  void _packInt64(num value) {
    if (value is int) {
      _packWords(value >> 32, value & 0xffffffff);
      return;
    }
    final high = (value / _two32).floorToDouble();
    final low = value.toDouble().remainder(_two32);
    _packWords(high, low);
  }

  void _packUint64(num value) {
    final high = value / _two32;
    final low = value.toDouble().remainder(_two32);
    _packWords(high, low);
  }

  void _packDouble(double input) {
    var number = input;
    var sign = 0;
    if (number < 0) {
      sign = 1;
      number = -number;
    }
    final expValue = (math.log(number) / math.ln2).floorToDouble();
    final frac0 = number / math.pow(2, expValue) - 1;
    final frac1 = (frac0 * math.pow(2, 52)).floorToDouble();
    final h32 = (sign << 31) | (_toInt32(expValue + 1023) << 20) | (_toInt32(frac1 / _two32) & 0x0fffff);
    final l32 = frac1.remainder(_two32);
    _append(0xcb);
    _packInt32(h32);
    _packInt32(l32);
  }
}

String jsPropertyKey(Object? key) {
  if (key is String) return key;
  if (key == null) return 'null';
  if (key is bool) return key ? 'true' : 'false';
  if (key is num) return jsNumberToString(key);
  if (key is Uint8List || key is ByteBuffer) return '[object ArrayBuffer]';
  if (key is List) return key.map((item) => item == null ? '' : jsPropertyKey(item)).join(',');
  if (key is Map) return '[object Object]';
  return key.toString();
}

String jsNumberToString(num value) {
  if (value is int) return value.toString();
  if (value.isNaN) return 'NaN';
  if (value.isInfinite) return value > 0 ? 'Infinity' : '-Infinity';
  if (value == value.truncateToDouble() && value.abs() < 1e21) {
    return value.toStringAsFixed(0) == '-0' ? '0' : value.toStringAsFixed(0);
  }
  return value.toString();
}

num _jsNumber(double value) {
  if (value.isFinite && value == value.truncateToDouble() && value.abs() <= 9007199254740991) {
    return value.toInt();
  }
  return value;
}

class _Unpacker {
  _Unpacker(this._data) : _length = _data.length;

  final Uint8List _data;
  final int _length;
  int _index = 0;

  Object? unpack() {
    final type = _unpackUint8();
    if (type < 0x80) return type;
    if ((type ^ 0xe0) < 0x20) return (type ^ 0xe0) - 0x20;

    var size = type ^ 0xa0;
    if (size <= 0x0f) return _unpackRaw(size);
    size = type ^ 0xb0;
    if (size <= 0x0f) return _unpackString(size);
    size = type ^ 0x90;
    if (size <= 0x0f) return _unpackArray(size);
    size = type ^ 0x80;
    if (size <= 0x0f) return _unpackMap(size);

    switch (type) {
      case 0xc0:
      case 0xc1:
        return null;
      case 0xc2:
        return false;
      case 0xc3:
        return true;
      case 0xca:
        return _jsNumber(_unpackFloat());
      case 0xcb:
        return _jsNumber(_unpackDouble());
      case 0xcc:
        return _unpackUint8();
      case 0xcd:
        return _unpackUint16();
      case 0xce:
        return _unpackUint32();
      case 0xcf:
        return _jsNumber(_unpackUint64());
      case 0xd0:
        final value = _unpackUint8();
        return value < 0x80 ? value : value - 256;
      case 0xd1:
        final value = _unpackUint16();
        return value < 0x8000 ? value : value - 65536;
      case 0xd2:
        final value = _unpackUint32();
        return value < 0x80000000 ? value : value - 4294967296;
      case 0xd3:
        final value = _unpackUint64();
        return _jsNumber(value < 9223372036854775808.0 ? value : value - 18446744073709551616.0);
      case 0xd4:
      case 0xd5:
      case 0xd6:
      case 0xd7:
        return null;
      case 0xd8:
        return _unpackString(_unpackUint16());
      case 0xd9:
        return _unpackString(_unpackUint32());
      case 0xda:
        return _unpackRaw(_unpackUint16());
      case 0xdb:
        return _unpackRaw(_unpackUint32());
      case 0xdc:
        return _unpackArray(_unpackUint16());
      case 0xdd:
        return _unpackArray(_unpackUint32());
      case 0xde:
        return _unpackMap(_unpackUint16());
      case 0xdf:
        return _unpackMap(_unpackUint32());
    }
    return null;
  }

  int _unpackUint8() {
    final byte = _index < _length ? _data[_index] : 0;
    _index++;
    return byte;
  }

  Uint8List _read(int length) {
    final start = _index;
    if (start + length <= _length) {
      return Uint8List.sublistView(_data, start, start + length);
    }
    throw BinaryPackError('BinaryPackFailure: read index out of range');
  }

  int _unpackUint16() {
    final bytes = _read(2);
    _index += 2;
    return bytes[0] * 256 + bytes[1];
  }

  int _unpackUint32() {
    final bytes = _read(4);
    _index += 4;
    return ((bytes[0] * 256 + bytes[1]) * 256 + bytes[2]) * 256 + bytes[3];
  }

  double _unpackUint64() {
    final bytes = _read(8);
    _index += 8;
    var value = 0.0;
    for (final byte in bytes) {
      value = value * 256 + byte;
    }
    return value;
  }

  Uint8List _unpackRaw(int size) {
    if (_length < _index + size) {
      throw BinaryPackError('BinaryPackFailure: index is out of range $_index $size $_length');
    }
    final out = Uint8List.fromList(Uint8List.sublistView(_data, _index, _index + size));
    _index += size;
    return out;
  }

  String _unpackString(int size) {
    final bytes = _read(size);
    int at(int i) => i < bytes.length ? bytes[i] : 0;
    final out = StringBuffer();
    var i = 0;
    while (i < size) {
      final c = bytes[i];
      int code;
      if (c < 0xa0) {
        code = c;
        i++;
      } else if ((c ^ 0xc0) < 0x20) {
        code = ((c & 0x1f) << 6) | (at(i + 1) & 0x3f);
        i += 2;
      } else if ((c ^ 0xe0) < 0x10) {
        code = ((c & 0x0f) << 12) | ((at(i + 1) & 0x3f) << 6) | (at(i + 2) & 0x3f);
        i += 3;
      } else {
        code = ((c & 0x07) << 18) | ((at(i + 1) & 0x3f) << 12) | ((at(i + 2) & 0x3f) << 6) | (at(i + 3) & 0x3f);
        i += 4;
      }
      if (code > 0x10ffff) {
        throw BinaryPackError('Invalid code point $code');
      }
      out.writeCharCode(code);
    }
    _index += size;
    return out.toString();
  }

  List<Object?> _unpackArray(int size) {
    final out = List<Object?>.filled(size, null);
    for (var i = 0; i < size; i++) {
      out[i] = unpack();
    }
    return out;
  }

  Map<String, Object?> _unpackMap(int size) {
    final out = <String, Object?>{};
    for (var i = 0; i < size; i++) {
      final key = jsPropertyKey(unpack());
      out[key] = unpack();
    }
    return out;
  }

  double _unpackFloat() {
    final uint32 = _unpackUint32();
    final negative = uint32 >= 0x80000000;
    final exp = ((uint32 >> 23) & 0xff) - 127;
    final fraction = (uint32 & 0x7fffff) | 0x800000;
    return (negative ? -1 : 1) * fraction * math.pow(2, exp - 23).toDouble();
  }

  double _unpackDouble() {
    final h32 = _unpackUint32();
    final l32 = _unpackUint32();
    final negative = h32 >= 0x80000000;
    final exp = ((h32 >> 20) & 0x7ff) - 1023;
    final hfrac = (h32 & 0xfffff) | 0x100000;
    final frac = hfrac * math.pow(2, exp - 20).toDouble() + l32 * math.pow(2, exp - 52).toDouble();
    return (negative ? -1 : 1) * frac;
  }
}
