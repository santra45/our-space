import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../sky/sky.dart';

abstract final class SettingsFieldCopy {
  static const String show = 'Show passphrase';
  static const String hide = 'Hide passphrase';
}

class SettingsField extends StatelessWidget {
  const SettingsField({
    super.key,
    required this.controller,
    required this.hint,
    this.obscured = false,
    this.onToggleReveal,
    this.autofocus = false,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.autofillHints,
    this.maxLength,
    this.enabled = true,
    this.leadingIcon,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hint;
  final bool obscured;
  final VoidCallback? onToggleReveal;
  final bool autofocus;
  final bool autocorrect;
  final bool enableSuggestions;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final Iterable<String>? autofillHints;
  final int? maxLength;
  final bool enabled;
  final SkyIcons? leadingIcon;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final textStyle = SkyType.bodyLarge.copyWith(color: t.text);
    OutlineInputBorder border(Color color, [double width = 1]) => OutlineInputBorder(
      borderRadius: SkyRadii.all(SkyRadii.field),
      borderSide: BorderSide(color: color, width: width),
    );
    final toggle = onToggleReveal;
    return TextField(
      controller: controller,
      obscureText: obscured,
      autofocus: autofocus,
      autocorrect: autocorrect && !obscured,
      enableSuggestions: enableSuggestions && !obscured,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      textCapitalization: textCapitalization,
      autofillHints: autofillHints,
      maxLength: maxLength,
      maxLengthEnforcement: MaxLengthEnforcement.enforced,
      enabled: enabled,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      cursorColor: t.roseDeep,
      style: textStyle,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: textStyle.copyWith(color: t.faint),
        filled: true,
        fillColor: t.chip,
        isDense: true,
        counterText: '',
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        prefixIcon: leadingIcon == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(left: 12, right: 8),
                child: SkyIcon(leadingIcon!, size: 18, color: t.muted),
              ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        suffixIcon: toggle == null
            ? null
            : SkyPressable(
                onTap: toggle,
                semanticLabel: obscured ? SettingsFieldCopy.show : SettingsFieldCopy.hide,
                excludeSemantics: true,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: SkyIcon(obscured ? SkyIcons.eye : SkyIcons.eyeOff, size: 18, color: t.muted),
                ),
              ),
        suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        border: border(t.chipBorder),
        enabledBorder: border(t.chipBorder),
        focusedBorder: border(t.rose, 1.4),
        disabledBorder: border(t.hairline),
      ),
    );
  }
}
