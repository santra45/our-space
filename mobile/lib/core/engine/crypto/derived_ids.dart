import 'dart:typed_data';

import 'aes_gcm.dart';
import 'js_compat.dart';
import 'pbkdf2.dart';

const String mailboxIdContext = 'our-space/mailbox/id/v1';
const List<String> personSlotContexts = ['our-space/people/slot/a/v1', 'our-space/people/slot/b/v1'];
const String questionShuffleContext = 'our-space/daily-question/order/v1';

Uint8List zeroIvDigest(VaultKey key, String context) {
  final sealed = aesGcmSeal(key, Uint8List(12), utf8Bytes(context));
  return sha256Bytes(sealed);
}

String deriveMailboxId(VaultKey key) => hexOf(zeroIvDigest(key, mailboxIdContext));

List<String> derivePersonSlots(VaultKey key) => [
      for (final context in personSlotContexts) hexOf(zeroIvDigest(key, context).sublist(0, 12)),
    ];

Uint8List deriveQuestionSeed(VaultKey key) => zeroIvDigest(key, questionShuffleContext);
