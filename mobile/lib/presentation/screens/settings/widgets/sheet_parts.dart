import 'package:flutter/material.dart';

import '../../../sky/sky.dart';

abstract final class SheetCopy {
  static const String close = 'Close';
  static const String cancel = 'Cancel';
}

class SheetHeader extends StatelessWidget {
  const SheetHeader({super.key, required this.title, this.subtitle, this.icon, this.tone = SkyTone.gold, this.onClose});

  final String title;
  final String? subtitle;
  final SkyIcons? icon;
  final SkyTone tone;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[
          SkyIconTile(icon: icon!, tone: tone, size: 42, iconSize: 21),
          const SizedBox(width: SkySpace.md),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: SkyType.serif(24, weight: FontWeight.w500, height: 1.2).copyWith(color: t.title),
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: SkySpace.xs),
                Text(subtitle!, style: SkyType.bodySmall.copyWith(color: t.muted, height: 1.45)),
              ],
            ],
          ),
        ),
        if (onClose != null) ...[
          const SizedBox(width: SkySpace.sm),
          SkyIconButton(
            icon: SkyIcons.close,
            semanticLabel: SheetCopy.close,
            tone: SkyIconButtonTone.ghost,
            size: 36,
            onPressed: onClose,
          ),
        ],
      ],
    );
  }
}

class TextAction extends StatelessWidget {
  const TextAction({
    super.key,
    required this.label,
    required this.onTap,
    this.color,
    this.icon,
    this.underline = false,
    this.small = false,
    this.enabled = true,
  });

  final String label;
  final VoidCallback? onTap;
  final Color? color;
  final SkyIcons? icon;
  final bool underline;
  final bool small;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final tint = color ?? t.rose;
    final active = enabled && onTap != null;
    var style = SkyType.sans(small ? 11.5 : 12.5, weight: FontWeight.w700).copyWith(color: tint);
    if (underline) style = style.copyWith(decoration: TextDecoration.underline, decorationColor: tint);
    return SkyPressable(
      onTap: active ? onTap : null,
      enabled: active,
      semanticLabel: label,
      excludeSemantics: true,
      child: AnimatedOpacity(
        opacity: active ? 1 : 0.45,
        duration: SkyMotion.fast,
        child: SkyTapTarget(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[SkyIcon(icon!, size: small ? 12 : 14, color: tint), const SizedBox(width: 5)],
              Flexible(child: Text(label, style: style)),
            ],
          ),
        ),
      ),
    );
  }
}

class SheetScroll extends StatelessWidget {
  const SheetScroll({super.key, required this.children, this.spacing = SkySpace.lg});

  final List<Widget> children;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(height: spacing),
            SkyEntrance(index: i, child: children[i]),
          ],
        ],
      ),
    );
  }
}

class GrowIn extends StatelessWidget {
  const GrowIn({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!skyMotionAllowed(context)) return child;
    return AnimatedSize(
      duration: SkyMotion.base,
      curve: SkyMotion.standard,
      alignment: Alignment.topCenter,
      child: child,
    );
  }
}

@immutable
class SettingsNote {
  const SettingsNote(this.text, {this.tone = SkyNoticeTone.love, this.actionLabel, this.onAction});

  const SettingsNote.error(this.text, {this.actionLabel, this.onAction}) : tone = SkyNoticeTone.error;

  const SettingsNote.warning(this.text, {this.actionLabel, this.onAction}) : tone = SkyNoticeTone.warning;

  const SettingsNote.info(this.text, {this.actionLabel, this.onAction}) : tone = SkyNoticeTone.info;

  final String text;
  final SkyNoticeTone tone;
  final String? actionLabel;
  final VoidCallback? onAction;
}

class SettingsNotes extends StatelessWidget {
  const SettingsNotes({super.key, required this.notes, this.onDismiss, this.top = SkySpace.md});

  final List<SettingsNote> notes;
  final ValueChanged<SettingsNote>? onDismiss;
  final double top;

  @override
  Widget build(BuildContext context) {
    return GrowIn(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final note in notes)
            Padding(
              key: ValueKey<String>('note-${note.tone.name}-${note.text}'),
              padding: EdgeInsets.only(top: top),
              child: SkyEntrance(
                offset: const Offset(0, -8),
                duration: SkyMotion.base,
                child: SkyNotice(
                  text: skyCalmText(note.text),
                  tone: note.tone,
                  actionLabel: note.actionLabel,
                  onAction: note.onAction,
                  onDismiss: onDismiss == null ? null : () => onDismiss!(note),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
