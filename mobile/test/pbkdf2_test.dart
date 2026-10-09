import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine/crypto/js_compat.dart';
import 'package:our_space_mobile/core/engine/crypto/pbkdf2.dart';

void main() {
  test('PBKDF2-HMAC-SHA256 matches the published vectors', () {
    final password = utf8.encode('password');
    final salt = utf8.encode('salt');
    expect(
      hexOf(pbkdf2HmacSha256(password, salt, 1, 32)),
      '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b',
    );
    expect(
      hexOf(pbkdf2HmacSha256(password, salt, 2, 32)),
      'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43',
    );
    expect(
      hexOf(pbkdf2HmacSha256(password, salt, 4096, 32)),
      'c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a',
    );
    expect(
      hexOf(pbkdf2HmacSha256(
        utf8.encode('passwordPASSWORDpassword'),
        utf8.encode('saltSALTsaltSALTsaltSALTsaltSALTsalt'),
        4096,
        40,
      )),
      '348c89dbcbd32b2f32d814b8116e84cf2b17347ebc1800181c4e2a1fb8dd53e1c635518c7dac47e9',
    );
  });

  test('a long password is hashed down first, as HMAC requires', () {
    final password = utf8.encode('x' * 100);
    final salt = utf8.encode('salt');
    expect(pbkdf2HmacSha256(password, salt, 3, 32).length, 32);
  });

  test('600,000 iterations finish in reasonable time', () async {
    final watch = Stopwatch()..start();
    final out = await pbkdf2HmacSha256Async(utf8.encode('a long enough passphrase'), utf8.encode('salt'), 600000, 32);
    watch.stop();
    expect(out.length, 32);
    expect(watch.elapsed.inSeconds, lessThan(30));
  });

  test('HKDF-SHA256 matches RFC 5869 case 1', () {
    final ikm = List<int>.filled(22, 0x0b);
    final salt = List<int>.generate(13, (i) => i);
    final info = List<int>.generate(10, (i) => 0xf0 + i);
    expect(
      hexOf(hkdfSha256(ikm: ikm, salt: salt, info: info, length: 42)),
      '3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865',
    );
  });
}
