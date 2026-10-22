import 'package:flutter/widgets.dart';

abstract final class LettersKeys {
  static const Key write = ValueKey<String>('letters-write');
  static const Key notice = ValueKey<String>('letters-notice');
  static const Key hidden = ValueKey<String>('letters-hidden');
  static const Key feature = ValueKey<String>('letters-feature');
  static const Key empty = ValueKey<String>('letters-empty');
  static const Key cancel = ValueKey<String>('letter-cancel');
  static const Key saved = ValueKey<String>('letter-saved');
  static const Key titleField = ValueKey<String>('letter-title-field');
  static const Key bodyField = ValueKey<String>('letter-body-field');
  static const Key sealRow = ValueKey<String>('letter-seal-row');
  static const Key sealToggle = ValueKey<String>('letter-seal-toggle');
  static const Key sealButton = ValueKey<String>('letter-seal-button');
  static const Key paper = ValueKey<String>('letter-paper');
  static const Key more = ValueKey<String>('letter-more');
  static const Key love = ValueKey<String>('letter-love');
  static const Key writeBack = ValueKey<String>('letter-write-back');
}
