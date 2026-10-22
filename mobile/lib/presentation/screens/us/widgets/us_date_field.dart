import 'package:flutter/material.dart';

import '../../../../core/engine.dart';
import '../../../sky/sky.dart';
import '../us_copy.dart';

class UsDateField extends StatefulWidget {
  const UsDateField({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.helpText,
    this.firstDate,
    this.lastDate,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String? label;
  final String? helpText;
  final DateTime? firstDate;
  final DateTime? lastDate;

  @override
  State<UsDateField> createState() => _UsDateFieldState();
}

class _UsDateFieldState extends State<UsDateField> {
  bool _open = false;

  DateTime get _date => parseLocalDate(widget.value) ?? DateTime.now();

  Future<void> _pick() async {
    if (_open) return;
    setState(() => _open = true);
    final now = DateTime.now();
    final first = widget.firstDate ?? DateTime(1970);
    final last = widget.lastDate ?? DateTime(now.year + 100);
    var initial = _date;
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      helpText: widget.helpText,
    );
    if (!mounted) return;
    setState(() => _open = false);
    if (picked != null) widget.onChanged(toLocalDateInput(picked));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final shown = UsDates.full(_date);
    final field = SkyPressable(
      onTap: _pick,
      pressedScale: 0.98,
      semanticLabel: '${widget.label ?? UsCopy.dateLabel}, $shown',
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: skyMotionAllowed(context) ? SkyMotion.fast : Duration.zero,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: t.chip,
          borderRadius: SkyRadii.all(SkyRadii.field),
          border: Border.all(color: _open ? t.rose : t.chipBorder, width: _open ? 1.4 : 1),
        ),
        child: Row(
          children: [
            SkyIcon(SkyIcons.calendar, size: 18, color: t.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(shown, style: SkyType.bodyLarge.copyWith(color: t.text, height: 1.3)),
            ),
            SkyIcon(SkyIcons.chevron, size: 15, color: t.faint),
          ],
        ),
      ),
    );
    if (widget.label == null) return field;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(widget.label!, style: SkyType.sans(11, weight: FontWeight.w600).copyWith(color: t.muted)),
        ),
        field,
      ],
    );
  }
}
