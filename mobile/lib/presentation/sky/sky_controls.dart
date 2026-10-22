import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/app_haptics.dart';
import 'sky_icons.dart';
import 'sky_metrics.dart';
import 'sky_motion.dart';
import 'sky_tokens.dart';
import 'sky_type.dart';

enum SkyTone { rose, gold, lavender, muted }

extension SkyToneColors on SkyTone {
  Color foreground(SkyTokens t) {
    switch (this) {
      case SkyTone.rose:
        return t.rose;
      case SkyTone.gold:
        return t.gold;
      case SkyTone.lavender:
        return t.lavender;
      case SkyTone.muted:
        return t.muted;
    }
  }

  Color background(SkyTokens t) {
    switch (this) {
      case SkyTone.rose:
        return t.roseSoft;
      case SkyTone.gold:
        return t.goldSoft;
      case SkyTone.lavender:
        return t.lavenderSoft;
      case SkyTone.muted:
        return t.chip;
    }
  }
}

class SkyIconTile extends StatelessWidget {
  const SkyIconTile({
    super.key,
    required this.icon,
    this.tone = SkyTone.rose,
    this.size = SkySizes.rowIcon,
    this.iconSize,
  });

  final SkyIcons icon;
  final SkyTone tone;
  final double size;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: tone.background(t), borderRadius: SkyRadii.all(size * 11 / 36)),
      alignment: Alignment.center,
      child: SkyIcon(icon, size: iconSize ?? size * 19 / 36, color: tone.foreground(t)),
    );
  }
}

class SkySpinner extends StatelessWidget {
  const SkySpinner({super.key, this.size = 18, this.color, this.strokeWidth = 2});

  final double size;
  final Color? color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: strokeWidth,
        color: color ?? context.sky.gold,
        backgroundColor: const Color(0x00000000),
      ),
    );
  }
}

enum SkyButtonVariant { primary, ghost, gold, danger }

class SkyButton extends StatelessWidget {
  const SkyButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.leading,
    this.variant = SkyButtonVariant.primary,
    this.busy = false,
    this.busyLabel,
    this.expand = true,
    this.height = SkySizes.button,
    this.semanticLabel,
  });

  final String label;
  final VoidCallback? onPressed;
  final SkyIcons? icon;
  final Widget? leading;
  final SkyButtonVariant variant;
  final bool busy;
  final String? busyLabel;
  final bool expand;
  final double height;
  final String? semanticLabel;

  bool get enabled => onPressed != null && !busy;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    late final Color fg;
    BoxDecoration decoration;
    switch (variant) {
      case SkyButtonVariant.primary:
        fg = SkyTokens.white;
        decoration = BoxDecoration(
          gradient: t.primaryGradient,
          borderRadius: SkyRadii.all(SkyRadii.button),
          boxShadow: enabled ? t.primaryShadow : const [],
        );
      case SkyButtonVariant.ghost:
        fg = t.text;
        decoration = BoxDecoration(
          color: t.chip,
          borderRadius: SkyRadii.all(SkyRadii.button),
          border: Border.all(color: t.chipBorder),
        );
      case SkyButtonVariant.gold:
        fg = t.activeFg;
        decoration = BoxDecoration(color: t.activeBg, borderRadius: SkyRadii.all(SkyRadii.button));
      case SkyButtonVariant.danger:
        fg = t.rose;
        decoration = BoxDecoration(
          color: t.roseSoft,
          borderRadius: SkyRadii.all(SkyRadii.button),
          border: Border.all(color: t.roseBorder),
        );
    }
    final shown = busy ? (busyLabel ?? label) : label;
    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (busy)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: SkySpinner(size: 16, color: fg),
          )
        else if (leading != null)
          Padding(padding: const EdgeInsets.only(right: 8), child: leading)
        else if (icon != null)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: SkyIcon(icon!, size: 17, color: fg),
          ),
        Flexible(
          child: Text(
            shown,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: SkyType.button.copyWith(color: fg),
          ),
        ),
      ],
    );
    return SkyPressable(
      onTap: enabled ? onPressed : null,
      enabled: enabled,
      semanticLabel: semanticLabel ?? shown,
      excludeSemantics: true,
      child: AnimatedOpacity(
        opacity: onPressed == null ? 0.5 : 1,
        duration: SkyMotion.fast,
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: decoration,
          child: content,
        ),
      ),
    );
  }
}

enum SkyIconButtonTone { surface, rose, ghost }

class SkyIconButton extends StatelessWidget {
  const SkyIconButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    this.onPressed,
    this.tone = SkyIconButtonTone.surface,
    this.size = SkySizes.iconButton,
    this.iconSize,
    this.iconColor,
    this.square = false,
  });

  final SkyIcons icon;
  final String semanticLabel;
  final VoidCallback? onPressed;
  final SkyIconButtonTone tone;
  final double size;
  final double? iconSize;
  final Color? iconColor;
  final bool square;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final shape = square ? BoxShape.rectangle : BoxShape.circle;
    final radius = square ? SkyRadii.all(SkyRadii.button) : null;
    late final BoxDecoration decoration;
    late final Color fg;
    switch (tone) {
      case SkyIconButtonTone.surface:
        fg = t.text;
        decoration = BoxDecoration(
          shape: shape,
          borderRadius: radius,
          color: t.surface2,
          border: Border.all(color: t.hairline),
          boxShadow: t.softShadow,
        );
      case SkyIconButtonTone.rose:
        fg = SkyTokens.white;
        decoration = BoxDecoration(
          shape: shape,
          borderRadius: radius,
          gradient: t.roseOrbGradient,
          border: Border.all(color: const Color(0x4DFFFFFF)),
          boxShadow: const [BoxShadow(color: Color(0x66E24E79), offset: Offset(0, 8), blurRadius: 16.5)],
        );
      case SkyIconButtonTone.ghost:
        fg = t.text;
        decoration = BoxDecoration(
          shape: shape,
          borderRadius: radius,
          border: Border.all(color: t.hairline),
        );
    }
    return SkyPressable(
      onTap: onPressed,
      enabled: onPressed != null,
      semanticLabel: semanticLabel,
      excludeSemantics: true,
      child: AnimatedOpacity(
        opacity: onPressed == null ? 0.5 : 1,
        duration: SkyMotion.fast,
        child: Container(
          width: size,
          height: size,
          decoration: decoration,
          alignment: Alignment.center,
          child: SkyIcon(icon, size: iconSize ?? size * 20 / 42, color: iconColor ?? fg),
        ),
      ),
    );
  }
}

enum SkyChipTone { plain, on, rose }

class SkyChip extends StatelessWidget {
  const SkyChip({
    super.key,
    required this.label,
    this.icon,
    this.tone = SkyChipTone.plain,
    this.onTap,
    this.dense = false,
  });

  final String label;
  final SkyIcons? icon;
  final SkyChipTone tone;
  final VoidCallback? onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    late final Color bg;
    late final Color fg;
    late final Color border;
    switch (tone) {
      case SkyChipTone.plain:
        bg = t.chip;
        fg = t.text;
        border = t.chipBorder;
      case SkyChipTone.on:
        bg = t.activeBg;
        fg = t.activeFg;
        border = const Color(0x00000000);
      case SkyChipTone.rose:
        bg = t.roseSoft;
        fg = t.rose;
        border = t.roseBorder;
    }
    final style = (dense ? SkyType.sans(10.5, weight: FontWeight.w600, height: 1.2) : SkyType.chip).copyWith(color: fg);
    final chip = AnimatedContainer(
      duration: SkyMotion.quick,
      curve: SkyMotion.standard,
      padding: dense
          ? const EdgeInsets.symmetric(horizontal: 9, vertical: 4)
          : const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: SkyRadii.all(SkyRadii.pill),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[SkyIcon(icon!, size: dense ? 11 : 13, color: fg), const SizedBox(width: 6)],
          Flexible(
            child: Text(label, style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
    if (onTap == null) return Semantics(label: label, excludeSemantics: true, child: chip);
    return SkyPressable(
      onTap: onTap,
      semanticLabel: label,
      selected: tone == SkyChipTone.on,
      excludeSemantics: true,
      child: chip,
    );
  }
}

class SkyToggle extends StatelessWidget {
  const SkyToggle({super.key, required this.value, this.onChanged, this.semanticLabel});

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final motion = skyMotionAllowed(context);
    final duration = motion ? SkyMotion.slow : Duration.zero;
    return Semantics(
      toggled: value,
      enabled: onChanged != null,
      label: semanticLabel,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onChanged == null
            ? null
            : () {
                AppHaptics.tick();
                onChanged!(!value);
              },
        child: AnimatedContainer(
          duration: duration,
          curve: SkyMotion.standard,
          width: SkySizes.toggleWidth,
          height: SkySizes.toggleHeight,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            borderRadius: SkyRadii.all(SkyRadii.pill),
            color: value ? null : t.toggleOff,
            gradient: value ? t.toggleOnGradient : null,
          ),
          child: AnimatedAlign(
            duration: duration,
            curve: const SkySpringCurve(SkyMotion.popSpring, seconds: 0.45),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: SkySizes.toggleKnob,
              height: SkySizes.toggleKnob,
              decoration: const BoxDecoration(
                color: SkyTokens.white,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Color(0x40000000), offset: Offset(0, 2), blurRadius: 4.5)],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SkyProgressBar extends StatelessWidget {
  const SkyProgressBar({super.key, required this.value, this.height = SkySizes.progress, this.semanticLabel});

  final double value;
  final double height;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final target = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    return Semantics(
      label: semanticLabel,
      value: '${(target * 100).round()}%',
      child: Container(
        height: height,
        decoration: BoxDecoration(color: t.toggleOff, borderRadius: SkyRadii.all(height)),
        clipBehavior: Clip.antiAlias,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(end: target),
          duration: skyMotionAllowed(context) ? SkyMotion.slow : Duration.zero,
          curve: SkyMotion.standard,
          builder: (context, fraction, _) => Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: fraction,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: t.progressGradient, borderRadius: SkyRadii.all(height)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum SkyAvatarStyle { me, partner }

class SkyAvatar extends StatelessWidget {
  const SkyAvatar({
    super.key,
    required this.initial,
    this.style = SkyAvatarStyle.me,
    this.size = SkySizes.avatar,
    this.onTap,
    this.semanticLabel,
  });

  final String initial;
  final SkyAvatarStyle style;
  final double size;
  final VoidCallback? onTap;
  final String? semanticLabel;

  static String initialOf(String? name, {String fallback = 'Q'}) {
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) return fallback;
    return String.fromCharCodes(trimmed.runes.take(1)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final me = style == SkyAvatarStyle.me;
    late final BoxDecoration decoration;
    late final Color fg;
    if (t.isNight) {
      final ring = me ? const Color(0xBFFFD98A) : const Color(0xB3FF6B95);
      final glow = me ? const Color(0x40FFD98A) : const Color(0x40FF6B95);
      fg = me ? const Color(0xFFFFD98A) : const Color(0xFFFFB6CB);
      decoration = BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF181335),
        boxShadow: [
          BoxShadow(color: ring, spreadRadius: 1.5 * size / 42),
          BoxShadow(color: glow, blurRadius: 13.2 * size / 42),
        ],
      );
    } else {
      fg = SkyTokens.white;
      decoration = BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: me ? const [Color(0xFFFFB38A), Color(0xFFFF6B95)] : const [Color(0xFF8E8BFF), SkyTokens.indigo],
        ),
        boxShadow: [
          BoxShadow(color: SkyTokens.white, spreadRadius: 2 * size / 42),
          const BoxShadow(color: Color(0x2E2B2A6B), offset: Offset(0, 6), blurRadius: 13),
        ],
      );
    }
    final face = Container(
      width: size,
      height: size,
      decoration: decoration,
      alignment: Alignment.center,
      child: Text(
        initial,
        style: SkyType.serif(size * 18 / 42, height: 1).copyWith(color: fg),
        textAlign: TextAlign.center,
      ),
    );
    if (onTap == null) {
      return Semantics(label: semanticLabel ?? initial, excludeSemantics: true, child: face);
    }
    return SkyPressable(onTap: onTap, semanticLabel: semanticLabel ?? initial, excludeSemantics: true, child: face);
  }
}

enum SkyFieldStyle { filled, underline, paper }

class SkyTextField extends StatefulWidget {
  const SkyTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.hint,
    this.label,
    this.helper,
    this.errorText,
    this.style = SkyFieldStyle.filled,
    this.obscure = false,
    this.minLines,
    this.maxLines = 1,
    this.maxLength,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.sentences,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.enabled = true,
    this.leadingIcon,
    this.inputFormatters,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? hint;
  final String? label;
  final String? helper;
  final String? errorText;
  final SkyFieldStyle style;
  final bool obscure;
  final int? minLines;
  final int? maxLines;
  final int? maxLength;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final bool enabled;
  final SkyIcons? leadingIcon;
  final List<TextInputFormatter>? inputFormatters;

  @override
  State<SkyTextField> createState() => _SkyTextFieldState();
}

class _SkyTextFieldState extends State<SkyTextField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final underline = widget.style == SkyFieldStyle.underline;
    final paper = widget.style == SkyFieldStyle.paper;
    final ink = paper ? t.paperInk : t.text;
    final textStyle = underline
        ? SkyType.serif(24, height: 1.25).copyWith(color: ink)
        : paper
        ? SkyType.letter.copyWith(color: ink)
        : SkyType.bodyLarge.copyWith(color: ink);
    final hintColor = paper ? t.paperMuted : t.faint;
    InputBorder border(Color color, [double width = 1]) {
      if (underline) {
        return UnderlineInputBorder(borderSide: BorderSide(color: color, width: width));
      }
      if (paper) return InputBorder.none;
      return OutlineInputBorder(
        borderRadius: SkyRadii.all(SkyRadii.field),
        borderSide: BorderSide(color: color, width: width),
      );
    }

    final obscured = widget.obscure && _hidden;
    final field = TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      obscureText: obscured,
      enableSuggestions: !widget.obscure,
      autocorrect: !widget.obscure,
      minLines: widget.obscure ? 1 : widget.minLines,
      maxLines: widget.obscure ? 1 : widget.maxLines,
      maxLength: widget.maxLength,
      maxLengthEnforcement: MaxLengthEnforcement.enforced,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      textCapitalization: widget.obscure ? TextCapitalization.none : widget.textCapitalization,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      autofocus: widget.autofocus,
      enabled: widget.enabled,
      inputFormatters: widget.inputFormatters,
      cursorColor: t.roseDeep,
      style: textStyle,
      decoration: InputDecoration(
        hintText: widget.hint,
        hintStyle: textStyle.copyWith(color: hintColor),
        filled: !underline && !paper,
        fillColor: t.chip,
        isDense: true,
        counterText: '',
        errorText: widget.errorText,
        errorStyle: SkyType.small.copyWith(color: t.rose),
        contentPadding: underline
            ? const EdgeInsets.only(bottom: 8, top: 4)
            : paper
            ? EdgeInsets.zero
            : const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        prefixIcon: widget.leadingIcon == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(left: 12, right: 8),
                child: SkyIcon(widget.leadingIcon!, size: 18, color: t.muted),
              ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        suffixIcon: widget.obscure
            ? SkyPressable(
                onTap: () => setState(() => _hidden = !_hidden),
                semanticLabel: _hidden ? 'Show' : 'Hide',
                excludeSemantics: true,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: SkyIcon(_hidden ? SkyIcons.eye : SkyIcons.eyeOff, size: 18, color: t.muted),
                ),
              )
            : null,
        suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        border: border(underline ? t.hairline : t.chipBorder),
        enabledBorder: border(underline ? t.hairline : t.chipBorder),
        focusedBorder: border(t.rose, 1.4),
        errorBorder: border(t.roseBorder),
        focusedErrorBorder: border(t.rose, 1.4),
        disabledBorder: border(t.hairline),
      ),
    );
    if (widget.label == null && widget.helper == null) return field;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              if (widget.label != null)
                Expanded(
                  child: Text(
                    widget.label!,
                    style: SkyType.sans(11, weight: FontWeight.w600).copyWith(color: t.muted),
                  ),
                ),
              if (widget.label == null) const Spacer(),
              if (widget.helper != null) Text(widget.helper!, style: SkyType.caption.copyWith(color: t.faint)),
            ],
          ),
        ),
        field,
      ],
    );
  }
}
