import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../sky/sky.dart';
import '../../../widgets/app_haptics.dart';

class LockFieldLabel extends StatelessWidget {
  const LockFieldLabel(this.text, {super.key, this.emphasis});

  final String text;
  final String? emphasis;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final style = SkyType.sans(11.5, weight: FontWeight.w600, height: 1.3).copyWith(color: t.muted);
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 7),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: text),
            if (emphasis != null)
              TextSpan(
                text: emphasis,
                style: SkyType.serif(13.5, weight: FontWeight.w500, height: 1.1).copyWith(color: t.text),
              ),
          ],
        ),
        style: style,
      ),
    );
  }
}

class LockFieldHelp extends StatelessWidget {
  const LockFieldHelp(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 4, top: 7),
      child: Text(text, style: SkyType.small.copyWith(color: context.sky.muted)),
    );
  }
}

class LockField extends StatefulWidget {
  const LockField({
    super.key,
    required this.controller,
    required this.hint,
    this.label,
    this.labelEmphasis,
    this.help,
    this.obscure = false,
    this.revealToggle = true,
    this.autofocus = false,
    this.autofillHints,
    this.textInputAction,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.autocorrect = true,
    this.onChanged,
    this.onSubmitted,
    this.leadingIcon,
    this.highlight = false,
    this.phrase = false,
    this.semanticLabel,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String hint;
  final String? label;
  final String? labelEmphasis;
  final String? help;
  final bool obscure;
  final bool revealToggle;
  final bool autofocus;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final bool autocorrect;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final SkyIcons? leadingIcon;
  final bool highlight;
  final bool phrase;
  final String? semanticLabel;
  final bool enabled;

  static const String show = 'Show';
  static const String hide = 'Hide';

  @override
  State<LockField> createState() => _LockFieldState();
}

class _LockFieldState extends State<LockField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final base = widget.phrase
        ? SkyType.sans(14, weight: FontWeight.w600, letterSpacing: 1.4, height: 1.4)
        : SkyType.bodyLarge;
    final textStyle = base.copyWith(color: t.text);
    final idle = widget.highlight ? t.rose : t.chipBorder;
    OutlineInputBorder border(Color color, [double width = 1]) => OutlineInputBorder(
      borderRadius: SkyRadii.all(SkyRadii.field),
      borderSide: BorderSide(color: color, width: width),
    );
    final showToggle = widget.obscure && widget.revealToggle;
    final field = TextField(
      controller: widget.controller,
      obscureText: widget.obscure && _hidden,
      enableSuggestions: !widget.obscure && widget.autocorrect,
      autocorrect: !widget.obscure && widget.autocorrect,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      textCapitalization: widget.obscure ? TextCapitalization.none : widget.textCapitalization,
      autofillHints: widget.autofillHints,
      autofocus: widget.autofocus,
      enabled: widget.enabled,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      maxLines: 1,
      cursorColor: t.roseDeep,
      style: textStyle,
      decoration: InputDecoration(
        hintText: widget.hint,
        hintStyle: SkyType.bodyLarge.copyWith(color: t.faint),
        hintMaxLines: 1,
        filled: true,
        fillColor: t.isNight ? const Color(0xD9110F33) : SkyTokens.white,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        prefixIcon: widget.leadingIcon == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(left: 14, right: 10),
                child: SkyIcon(widget.leadingIcon!, size: 18, color: t.muted),
              ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        suffixIcon: showToggle
            ? SkyPressable(
                onTap: () => setState(() => _hidden = !_hidden),
                semanticLabel: _hidden ? LockField.show : LockField.hide,
                excludeSemantics: true,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: SkyIcon(_hidden ? SkyIcons.eye : SkyIcons.eyeOff, size: 18, color: t.muted),
                ),
              )
            : null,
        suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        border: border(idle, widget.highlight ? 1.4 : 1),
        enabledBorder: border(idle, widget.highlight ? 1.4 : 1),
        focusedBorder: border(t.rose, 1.4),
        disabledBorder: border(t.hairline),
      ),
    );
    final labelled = Semantics(label: widget.semanticLabel ?? widget.label ?? widget.hint, child: field);
    if (widget.label == null && widget.help == null) return labelled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null) LockFieldLabel(widget.label!, emphasis: widget.labelEmphasis),
        labelled,
        if (widget.help != null) LockFieldHelp(widget.help!),
      ],
    );
  }
}

class LockDateField extends StatefulWidget {
  const LockDateField({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
    this.firstDate,
    this.lastDate,
  });

  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  final String label;
  final DateTime? firstDate;
  final DateTime? lastDate;

  static String format(DateTime date) => DateFormat('d MMMM y').format(date);

  @override
  State<LockDateField> createState() => _LockDateFieldState();
}

class _LockDateFieldState extends State<LockDateField> {
  bool _open = false;

  Future<void> _pick() async {
    if (_open) return;
    setState(() => _open = true);
    final now = DateTime.now();
    final first = widget.firstDate ?? DateTime(1970);
    final last = widget.lastDate ?? DateTime(now.year + 100);
    var initial = widget.value;
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      builder: (context, child) => SkyTheme(child: child ?? const SizedBox.shrink()),
    );
    if (!mounted) return;
    setState(() => _open = false);
    if (picked != null) {
      AppHaptics.tick();
      widget.onChanged(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final shown = LockDateField.format(widget.value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        LockFieldLabel(widget.label),
        SkyPressable(
          onTap: _pick,
          pressedScale: 0.98,
          semanticLabel: '${widget.label} $shown',
          excludeSemantics: true,
          child: AnimatedContainer(
            duration: skyMotionAllowed(context) ? SkyMotion.fast : Duration.zero,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: t.isNight ? const Color(0xD9110F33) : SkyTokens.white,
              borderRadius: SkyRadii.all(SkyRadii.field),
              border: Border.all(color: _open ? t.rose : t.chipBorder, width: _open ? 1.4 : 1),
            ),
            child: Row(
              children: [
                SkyIcon(SkyIcons.calendar, size: 18, color: t.muted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    shown,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SkyType.bodyLarge.copyWith(color: t.text),
                  ),
                ),
                SkyIcon(SkyIcons.chevron, size: 15, color: t.muted),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
