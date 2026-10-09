import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_metrics.dart';
import '../theme/app_shadows.dart';
import '../theme/app_typography.dart';
import 'app_haptics.dart';
import 'app_icons.dart';
import 'css_box.dart';
import 'lucide_icon.dart';
import 'our_modal.dart';

@immutable
class OurFieldStyle {
  const OurFieldStyle({
    required this.fill,
    required this.border,
    required this.ring,
    required this.radius,
    required this.padding,
    required this.textStyle,
    required this.hintStyle,
    this.borderWidth = 1,
  });

  final Color fill;
  final Color border;
  final Color ring;
  final double radius;
  final EdgeInsets padding;
  final TextStyle textStyle;
  final TextStyle hintStyle;
  final double borderWidth;

  static final OurFieldStyle lock = OurFieldStyle(
    fill: AppColors.white.withValues(alpha: 0.7),
    border: AppColors.blush200,
    ring: AppColors.blush400,
    radius: AppRadii.x2l,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    textStyle: Tw.sm.c(AppColors.slate800),
    hintStyle: Tw.sm.c(AppColors.slate400),
  );

  static final OurFieldStyle lockCompact = lock.copyWith(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
  );

  static final OurFieldStyle form = OurFieldStyle(
    fill: AppColors.white,
    border: AppColors.blush200,
    ring: AppColors.blush400,
    radius: AppRadii.xl,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    textStyle: Tw.xs.c(AppColors.slate800),
    hintStyle: Tw.xs.c(AppColors.placeholder),
  );

  static final OurFieldStyle soft = OurFieldStyle(
    fill: AppColors.white,
    border: AppColors.lavender200,
    ring: AppColors.lavender300,
    radius: AppRadii.x2l,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    textStyle: Tw.sm.c(AppColors.slate800),
    hintStyle: Tw.sm.c(AppColors.slate400),
  );

  static final OurFieldStyle muted = OurFieldStyle(
    fill: AppColors.slate50,
    border: AppColors.slate200,
    ring: AppColors.blush400,
    radius: AppRadii.xl,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    textStyle: Tw.sm.c(AppColors.slate800),
    hintStyle: Tw.sm.c(AppColors.placeholder),
  );

  OurFieldStyle copyWith({
    Color? fill,
    Color? border,
    Color? ring,
    double? radius,
    EdgeInsets? padding,
    TextStyle? textStyle,
    TextStyle? hintStyle,
    double? borderWidth,
  }) {
    return OurFieldStyle(
      fill: fill ?? this.fill,
      border: border ?? this.border,
      ring: ring ?? this.ring,
      radius: radius ?? this.radius,
      padding: padding ?? this.padding,
      textStyle: textStyle ?? this.textStyle,
      hintStyle: hintStyle ?? this.hintStyle,
      borderWidth: borderWidth ?? this.borderWidth,
    );
  }
}

class OurFieldFrame extends StatelessWidget {
  const OurFieldFrame({
    super.key,
    required this.style,
    required this.focused,
    required this.child,
    this.extraPadding = EdgeInsets.zero,
    this.enabled = true,
  });

  final OurFieldStyle style;
  final bool focused;
  final Widget child;
  final EdgeInsets extraPadding;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        CssBox(
          padding: style.padding + extraPadding,
          color: style.fill,
          border: Border.all(color: style.border, width: style.borderWidth),
          borderRadius: AppRadii.all(style.radius),
          opacity: enabled ? 1 : 0.5,
          child: child,
        ),
        if (focused)
          Positioned(
            left: -2,
            top: -2,
            right: -2,
            bottom: -2,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: style.ring, width: 2),
                  borderRadius: AppRadii.all(style.radius + 2),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class OurTextField extends StatefulWidget {
  const OurTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.style,
    this.hint,
    this.leadingIcon,
    this.obscure = false,
    this.showObscureToggle = true,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.autofocus = false,
    this.enabled = true,
    this.readOnly = false,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.textAlign = TextAlign.start,
    this.autofillHints,
    this.semanticLabel,
    this.iconTop = 14,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final OurFieldStyle? style;
  final String? hint;
  final LucideIconData? leadingIcon;
  final bool obscure;
  final bool showObscureToggle;
  final int? maxLines;
  final int? minLines;
  final int? maxLength;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final bool autofocus;
  final bool enabled;
  final bool readOnly;
  final bool autocorrect;
  final bool enableSuggestions;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;
  final TextAlign textAlign;
  final Iterable<String>? autofillHints;
  final String? semanticLabel;
  final double iconTop;

  @override
  State<OurTextField> createState() => _OurTextFieldState();
}

class _OurTextFieldState extends State<OurTextField> {
  FocusNode? _ownFocus;
  bool _revealed = false;

  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(covariant OurTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      (oldWidget.focusNode ?? _ownFocus)?.removeListener(_onFocus);
      _focus.addListener(_onFocus);
    }
  }

  void _onFocus() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _ownFocus?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style ?? OurFieldStyle.form;
    final hasToggle = widget.obscure && widget.showObscureToggle;
    final iconTop = widget.iconTop;
    final leadingPad = widget.leadingIcon != null ? 40 - style.padding.left : 0.0;
    final trailingPad = hasToggle ? 44 - style.padding.right : 0.0;

    final field = TextField(
      controller: widget.controller,
      focusNode: _focus,
      style: style.textStyle,
      strutStyle: StrutStyle.fromTextStyle(style.textStyle, forceStrutHeight: true),
      decoration: InputDecoration.collapsed(hintText: widget.hint, hintStyle: style.hintStyle),
      obscureText: widget.obscure && !_revealed,
      maxLines: widget.obscure ? 1 : widget.maxLines,
      minLines: widget.obscure ? null : widget.minLines,
      inputFormatters: widget.maxLength == null ? null : [LengthLimitingTextInputFormatter(widget.maxLength)],
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      textCapitalization: widget.textCapitalization,
      autofocus: widget.autofocus,
      enabled: widget.enabled,
      readOnly: widget.readOnly,
      autocorrect: widget.obscure ? false : widget.autocorrect,
      enableSuggestions: widget.obscure ? false : widget.enableSuggestions,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      onTap: widget.onTap,
      textAlign: widget.textAlign,
      autofillHints: widget.autofillHints,
      cursorColor: AppColors.slate800,
      cursorWidth: 1.5,
    );

    return Semantics(
      label: widget.semanticLabel,
      textField: true,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          OurFieldFrame(
            style: style,
            focused: _focus.hasFocus,
            enabled: widget.enabled,
            extraPadding: EdgeInsets.only(left: leadingPad, right: trailingPad),
            child: field,
          ),
          if (widget.leadingIcon != null)
            Positioned(
              left: 14,
              top: iconTop,
              child: IgnorePointer(child: LucideIcon(widget.leadingIcon!, size: 16, color: AppColors.slate400)),
            ),
          if (hasToggle)
            Positioned(
              right: 14,
              top: iconTop,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _revealed = !_revealed),
                child: Semantics(
                  button: true,
                  label: _revealed ? 'Hide passphrase' : 'Show passphrase',
                  child: LucideIcon(_revealed ? AppIcons.eyeOff : AppIcons.eye, size: 16, color: AppColors.slate400),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String formatInputDate(DateTime date) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(date.month)}/${two(date.day)}/${date.year.toString().padLeft(4, '0')}';
}

class OurDateField extends StatefulWidget {
  const OurDateField({
    super.key,
    required this.value,
    required this.onChanged,
    this.firstDate,
    this.lastDate,
    this.style,
    this.hint = 'mm/dd/yyyy',
    this.enabled = true,
    this.semanticLabel,
  });

  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final OurFieldStyle? style;
  final String hint;
  final bool enabled;
  final String? semanticLabel;

  @override
  State<OurDateField> createState() => _OurDateFieldState();
}

class _OurDateFieldState extends State<OurDateField> {
  bool _open = false;

  Future<void> _pick() async {
    if (!widget.enabled || _open) return;
    AppHaptics.tick();
    setState(() => _open = true);
    final now = DateTime.now();
    final first = widget.firstDate ?? DateTime(1970);
    final last = widget.lastDate ?? DateTime(now.year + 100);
    var initial = widget.value ?? now;
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    final picked = await showDatePicker(context: context, initialDate: initial, firstDate: first, lastDate: last);
    if (!mounted) return;
    setState(() => _open = false);
    if (picked != null) widget.onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style ?? OurFieldStyle.form;
    final text = widget.value == null ? widget.hint : formatInputDate(widget.value!);
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      value: widget.value == null ? null : formatInputDate(widget.value!),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _pick,
        child: OurFieldFrame(
          style: style,
          focused: _open,
          enabled: widget.enabled,
          child: Text(
            text,
            maxLines: 1,
            style: widget.value == null ? style.hintStyle : style.textStyle,
          ),
        ),
      ),
    );
  }
}

@immutable
class OurOption<T> {
  const OurOption(this.value, this.label);

  final T value;
  final String label;
}

class OurSelectField<T> extends StatefulWidget {
  const OurSelectField({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.style,
    this.enabled = true,
    this.semanticLabel,
  });

  final T value;
  final List<OurOption<T>> options;
  final ValueChanged<T> onChanged;
  final OurFieldStyle? style;
  final bool enabled;
  final String? semanticLabel;

  @override
  State<OurSelectField<T>> createState() => _OurSelectFieldState<T>();
}

class _OurSelectFieldState<T> extends State<OurSelectField<T>> {
  bool _open = false;

  Future<void> _choose() async {
    if (!widget.enabled || _open) return;
    AppHaptics.tick();
    setState(() => _open = true);
    final chosen = await showOurModal<OurOption<T>>(
      context: context,
      backdrop: OurBackdropTone.black50,
      entrance: OurModalEntrance.popSoft,
      barrierDismissible: true,
      builder: (dialogContext) => OurModalCard(
        showClose: false,
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in widget.options)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(dialogContext).pop(option),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          option.label,
                          style: option.value == widget.value
                              ? Tw.sm.bold.c(AppColors.blush600)
                              : Tw.sm.medium.c(AppColors.slate700),
                        ),
                      ),
                      if (option.value == widget.value)
                        const LucideIcon(AppIcons.check, size: 16, color: AppColors.blush500),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _open = false);
    if (chosen != null && chosen.value != widget.value) widget.onChanged(chosen.value);
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style ?? OurFieldStyle.form;
    final selected = widget.options.where((o) => o.value == widget.value);
    final label = selected.isEmpty ? '' : selected.first.label;
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      value: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _choose,
        child: OurFieldFrame(
          style: style,
          focused: _open,
          enabled: widget.enabled,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: style.textStyle)),
              const SizedBox(width: 8),
              CustomPaint(size: const Size(8, 5), painter: _ChevronPainter(style.textStyle.color ?? AppColors.slate800)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChevronPainter extends CustomPainter {
  const _ChevronPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_ChevronPainter oldDelegate) => oldDelegate.color != color;
}

@immutable
class OurSegment<T> {
  const OurSegment({required this.value, required this.label, this.icon, this.iconColor});

  final T value;
  final String label;
  final LucideIconData? icon;
  final Color? iconColor;
}

class OurSegmented<T> extends StatelessWidget {
  const OurSegmented({super.key, required this.segments, required this.selected, required this.onChanged});

  final List<OurSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return CssBox(
      padding: const EdgeInsets.all(4),
      color: AppColors.slate100.withValues(alpha: 0.8),
      borderRadius: AppRadii.all(AppRadii.x2l),
      child: Row(
        children: [
          for (final segment in segments)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  AppHaptics.tick();
                  onChanged(segment.value);
                },
                child: Semantics(
                  button: true,
                  selected: segment.value == selected,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: segment.value == selected ? AppColors.white : AppColors.transparent,
                      borderRadius: AppRadii.all(AppRadii.xl),
                      boxShadow: segment.value == selected ? AppShadows.sm : const [],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (segment.icon != null) ...[
                          LucideIcon(segment.icon!, size: 14, color: segment.iconColor ?? AppColors.slate500),
                          const SizedBox(width: 6),
                        ],
                        Flexible(
                          child: Text(
                            segment.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Tw.xs.bold.c(segment.value == selected ? AppColors.slate800 : AppColors.slate500),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

enum OurChipTone { blush, lavender }

class OurChip extends StatelessWidget {
  const OurChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.tone = OurChipTone.blush,
    this.expand = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final LucideIconData? icon;
  final OurChipTone tone;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final blush = tone == OurChipTone.blush;
    final background = blush
        ? (selected ? AppColors.blush500 : AppColors.white.withValues(alpha: 0.8))
        : (selected ? AppColors.lavender500 : AppColors.lavender50);
    final foreground = selected ? AppColors.white : (blush ? AppColors.slate600 : AppColors.lavender600);
    final text = blush ? Tw.xs.semibold : Tw.px11.bold;
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: CssBox(
          padding: blush ? const EdgeInsets.symmetric(horizontal: 12, vertical: 6) : const EdgeInsets.symmetric(vertical: 6),
          color: background,
          border: blush && !selected ? Border.all(color: AppColors.blush100) : null,
          borderRadius: AppRadii.all(blush ? AppRadii.full : AppRadii.xl),
          shadows: blush && selected ? AppShadows.tinted(AppShadows.sm, AppColors.blush300) : const [],
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                LucideIcon(icon!, size: 12, color: foreground),
                const SizedBox(width: 4),
              ],
              Text(label, style: text.c(foreground)),
            ],
          ),
        ),
      ),
    );
  }
}

class OurFieldLabel extends StatelessWidget {
  const OurFieldLabel(this.text, {super.key, this.caps = false, this.color});

  final String text;
  final bool caps;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final style = caps
        ? Tw.px11.bold.trackingWide.c(color ?? AppColors.slate500)
        : Tw.xs.semibold.c(color ?? AppColors.slate600);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(caps ? text.toUpperCase() : text, style: style),
    );
  }
}

class OurFieldHint extends StatelessWidget {
  const OurFieldHint(this.text, {super.key, this.small = false});

  final String text;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: small ? 2 : 4),
      child: Text(text, style: (small ? Tw.px10 : Tw.px11).relaxed.c(AppColors.slate400)),
    );
  }
}
