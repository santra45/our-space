import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/presentation/screens/sky/together/sky_patch_naming.dart';

TextEditingValue typed(String text) =>
    TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));

void main() {
  group('the name field', () {
    const family = '\u{1F468}‍\u{1F469}‍\u{1F467}‍\u{1F466}';
    const limit = SkyNameLimit();

    test('keeps what was typed when it fits, so the partner sees and keeps the very same name', () {
      final text = 'Our $family night under the big bright';
      expect(text.runes.length, lessThanOrEqualTo(skyDrawingMaxName));
      final out = limit.formatEditUpdate(TextEditingValue.empty, typed(text));
      expect(out.text, text);
      expect(cleanSkyName(out.text), text);
    });

    test('stops at forty characters on a whole emoji, never through the middle of one', () {
      final text = 'Our $family night under the big bright sky';
      expect(text.runes.length, greaterThan(skyDrawingMaxName));
      final out = limit.formatEditUpdate(TextEditingValue.empty, typed(text));
      expect(out.text.runes.length, lessThanOrEqualTo(skyDrawingMaxName));
      expect(text.startsWith(out.text), isTrue);
      expect(cleanSkyName(out.text), out.text.trim());
      expect(out.selection.extentOffset, out.text.length);

      final full = '${'a' * 36}$family';
      final cut = limit.formatEditUpdate(TextEditingValue.empty, typed(full));
      expect(cut.text, 'a' * 36);
      expect(skyHasLoneSurrogate(cut.text), isFalse);
    });
  });
}
