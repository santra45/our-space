import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../../../core/engine.dart';
import '../../../sky/sky.dart';
import '../sky_sheet_layout.dart';
import 'sky_drawn.dart';
import 'sky_patch_art.dart';
import 'sky_patch_session.dart';
import 'sky_together_copy.dart';
import 'sky_together_layer.dart';

class SkyNameLimit extends TextInputFormatter {
  const SkyNameLimit();

  static String fit(String text) {
    if (text.runes.length <= skyDrawingMaxName) return text;
    final out = StringBuffer();
    var runes = 0;
    for (final cluster in text.characters) {
      final size = cluster.runes.length;
      if (runes + size > skyDrawingMaxName) break;
      out.write(cluster);
      runes += size;
    }
    return out.toString();
  }

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = fit(newValue.text);
    if (text == newValue.text) return newValue;
    final selection = newValue.selection;
    return TextEditingValue(
      text: text,
      selection: selection.isValid
          ? selection.copyWith(
              baseOffset: math.min(selection.baseOffset, text.length),
              extentOffset: math.min(selection.extentOffset, text.length),
            )
          : TextSelection.collapsed(offset: text.length),
    );
  }
}

class SkyPatchStill extends StatelessWidget {
  const SkyPatchStill({super.key, required this.drawing, this.me, this.owners = false, this.night, this.faint = 1});

  final SkyDrawing drawing;
  final String? me;
  final bool owners;
  final bool? night;
  final double faint;

  static SkyPatchPicture pictureOf(
    SkyDrawing drawing, {
    required bool night,
    String? me,
    bool owners = false,
    double faint = 1,
  }) {
    final stars = drawing.visibleStars;
    final units = {for (final s in stars) s.id: Offset(s.x, s.y)};
    return SkyPatchPicture(
      night: night,
      owners: owners,
      faint: faint,
      stars: [
        for (var i = 0; i < stars.length; i++)
          SkyPatchStar(id: stars[i].id, unit: units[stars[i].id]!, index: i, mine: stars[i].by == me),
      ],
      lines: [
        for (final l in drawing.visibleLines)
          if (units[l.a] != null && units[l.b] != null) SkyPatchLine(a: units[l.a]!, b: units[l.b]!),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final k = SkyPageFrame.scaleOf(MediaQuery.sizeOf(context).width);
    final sketch = SkyDrawnSketch.of(drawing);
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _StillPainter(
            picture: pictureOf(drawing, night: night ?? t.isNight, me: me, owners: owners, faint: faint),
            sketch: sketch,
            k: k,
            sigma: t.glowSigma,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _StillPainter extends CustomPainter {
  const _StillPainter({required this.picture, required this.sketch, required this.k, required this.sigma});

  final SkyPatchPicture picture;
  final SkyDrawnSketch sketch;
  final double k;
  final double sigma;

  @override
  void paint(Canvas canvas, Size size) {
    if (sketch.isEmpty) return;
    final frame = SkyDrawnArt.unitFrame(SkyDrawnArt.frameOf(Offset.zero & size, sketch));
    SkyPatchArt.paint(canvas, frame, picture, k: k, sigma: sigma);
  }

  @override
  bool shouldRepaint(_StillPainter oldDelegate) =>
      oldDelegate.picture != picture || oldDelegate.k != k || oldDelegate.sigma != sigma;
}

class SkyPatchNaming extends StatefulWidget {
  const SkyPatchNaming({
    super.key,
    required this.session,
    required this.partner,
    this.me,
    this.dayNumber,
  });

  static const Duration idle = Duration(milliseconds: 1200);
  static const double stillRoom = 120;

  final SkyPatchSession session;
  final String partner;
  final String? me;
  final int? dayNumber;

  @override
  State<SkyPatchNaming> createState() => _SkyPatchNamingState();
}

class _SkyPatchNamingState extends State<SkyPatchNaming> {
  late final TextEditingController _field = TextEditingController(text: widget.session.name);
  final FocusNode _focus = FocusNode();
  Timer? _idle;
  String? _announced;
  bool _fresh = false;
  late bool _typer;
  late int _changedAt;

  SkyPatchSession get session => widget.session;

  @override
  void initState() {
    super.initState();
    _typer = session.typer;
    _changedAt = session.nameChangedAt;
    session.addListener(_onSession);
  }

  @override
  void dispose() {
    session.removeListener(_onSession);
    _idle?.cancel();
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onSession() {
    if (!mounted) return;
    if (session.typer != _typer) {
      _typer = session.typer;
      if (_typer) {
        _field.value = TextEditingValue(
          text: session.name,
          selection: TextSelection.collapsed(offset: session.name.length),
        );
      } else {
        _focus.unfocus();
      }
    }
    if (session.nameChangedAt != _changedAt) {
      _changedAt = session.nameChangedAt;
      _fresh = true;
      _idle?.cancel();
      _idle = Timer(SkyPatchNaming.idle, () {
        if (!mounted) return;
        setState(() => _fresh = false);
        _announce();
      });
    }
    setState(() {});
  }

  void _announce() {
    if (session.typer || session.step != SkyPatchStep.naming) return;
    final name = cleanSkyName(session.name);
    if (name.isEmpty || name == _announced) return;
    _announced = name;
    unawaited(SemanticsService.sendAnnouncement(View.of(context), name, TextDirection.ltr));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final step = session.step;
    final saved = step == SkyPatchStep.saved;
    final saving = step == SkyPatchStep.saving;
    final name = saved ? (session.savedName ?? session.name) : session.name;
    final motion = skyMotionAllowed(context);
    final sheet = saved
        ? const SizedBox.shrink()
        : session.typer
        ? _typerSheet(context)
        : _viewerSheet(context, saving: saving);
    return CustomMultiChildLayout(
      delegate: _NamingLayout(),
      children: [
        LayoutId(
          id: _NamingSlot.top,
          child: SkyTopBar(
            compact: true,
            leading: ExcludeSemantics(
              excluding: saved || saving,
              child: IgnorePointer(
                ignoring: saved || saving,
                child: Opacity(
                  opacity: saved || saving ? 0.45 : 1,
                  child: SkyBackButton(semanticLabel: SkyTogetherCopy.backToDrawing, onPressed: session.backToDrawing),
                ),
              ),
            ),
            kicker: SkyTogetherCopy.nameKicker(night: t.isNight, dayNumber: widget.dayNumber),
            title: SkyTogetherCopy.nameTitle,
            trailing: SkyAvatar(initial: SkyAvatar.initialOf(widget.me, fallback: 'O')),
          ),
        ),
        LayoutId(
          id: _NamingSlot.middle,
          child: LayoutBuilder(
            builder: (context, box) {
              final caret = !saved && !saving && (session.typer || _fresh);
              final line = MediaQuery.textScalerOf(context).scale(_SkyName.size) * _SkyName.height;
              final roomy = box.maxHeight >= SkyPatchNaming.stillRoom + 16 + line * 2 + 28 + 16;
              if (!roomy) {
                return ClipRect(
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: SizedBox(
                        width: box.maxWidth,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: SkySpace.gutter, vertical: 8),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _SkyName(key: SkyTogetherKeys.skyName, text: name, caret: caret, motion: motion, maxLines: 1),
                              if (saved) _SavedNote(motion: motion),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }
              return Column(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(56, 20, 56, 0),
                      child: SkyPatchStill(drawing: session.drawing, me: session.me),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: SkySpace.gutter),
                    child: _SkyName(key: SkyTogetherKeys.skyName, text: name, caret: caret, motion: motion),
                  ),
                  if (saved) _SavedNote(motion: motion) else const SizedBox(height: 28),
                  const SizedBox(height: 16),
                ],
              );
            },
          ),
        ),
        LayoutId(id: _NamingSlot.sheet, child: sheet),
      ],
    );
  }

  Widget _typerSheet(BuildContext context) {
    final t = context.sky;
    final waiting = !_fresh && cleanSkyName(session.name).isNotEmpty;
    return SkySheet(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(SkyTogetherCopy.nameLabel, style: SkyType.sans(11, weight: FontWeight.w600).copyWith(color: t.muted)),
          const SizedBox(height: 4),
          SkyTextField(
            key: SkyTogetherKeys.name,
            controller: _field,
            focusNode: _focus,
            hint: SkyTogetherCopy.nameHint,
            style: SkyFieldStyle.underline,
            inputFormatters: const [SkyNameLimit()],
            autofocus: true,
            textInputAction: TextInputAction.done,
            onChanged: session.type,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const _RoseDot(),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  waiting ? SkyTogetherCopy.waitingYes(widget.partner) : SkyTogetherCopy.seesIt(widget.partner),
                  style: SkyType.sans(12).copyWith(color: t.muted),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _viewerSheet(BuildContext context, {required bool saving}) {
    final t = context.sky;
    final name = session.name;
    return SkySheet(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SkyAvatar(initial: SkyAvatar.initialOf(widget.partner), style: SkyAvatarStyle.partner, size: 26),
              const SizedBox(width: 8),
              Flexible(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: widget.partner,
                        style: SkyType.sans(12.5, weight: FontWeight.w600).copyWith(color: t.text),
                      ),
                      TextSpan(text: SkyTogetherCopy.isNamingIt, style: SkyType.sans(12.5).copyWith(color: t.muted)),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_fresh) ...[const SizedBox(width: 8), _TypingDots(motion: skyMotionAllowed(context))],
            ],
          ),
          const SizedBox(height: 12),
          CustomPaint(
            painter: _DashedUnderline(color: t.faint),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                name.isEmpty ? ' ' : name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: SkyType.serif(30, weight: FontWeight.w500, height: 1.2).copyWith(color: t.text),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(SkyTogetherCopy.sayYes, style: SkyType.sans(12).copyWith(color: t.muted)),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: SkyButton(
                  key: SkyTogetherKeys.changeIt,
                  label: SkyTogetherCopy.changeIt,
                  variant: SkyButtonVariant.ghost,
                  leading: SkyIcon(SkyIcons.pen, size: 16, color: t.text),
                  onPressed: saving ? null : session.changeIt,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: SkyButton(
                  key: SkyTogetherKeys.agree,
                  label: SkyTogetherCopy.yes,
                  icon: SkyIcons.check,
                  busy: saving,
                  onPressed: session.canAgree ? () => unawaited(session.agree()) : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _NamingSlot { top, middle, sheet }

class _NamingLayout extends MultiChildLayoutDelegate {
  _NamingLayout();

  @override
  void performLayout(Size size) {
    final wide = BoxConstraints(minWidth: size.width, maxWidth: size.width, maxHeight: size.height);
    final top = layoutChild(_NamingSlot.top, wide);
    final sheet = layoutChild(_NamingSlot.sheet, wide);
    final room = math.max(0.0, size.height - top.height - sheet.height);
    layoutChild(_NamingSlot.middle, BoxConstraints.tight(Size(size.width, room)));
    positionChild(_NamingSlot.top, Offset.zero);
    positionChild(_NamingSlot.middle, Offset(0, top.height));
    positionChild(_NamingSlot.sheet, Offset(0, size.height - sheet.height));
  }

  @override
  bool shouldRelayout(_NamingLayout oldDelegate) => false;
}

class _SkyName extends StatefulWidget {
  const _SkyName({super.key, required this.text, required this.caret, required this.motion, this.maxLines = 2});

  static const double size = 24;
  static const double height = 1.25;

  final String text;
  final bool caret;
  final bool motion;
  final int maxLines;

  @override
  State<_SkyName> createState() => _SkyNameState();
}

class _SkyNameState extends State<_SkyName> {
  static const Duration _period = Duration(milliseconds: 500);

  Timer? _blink;
  bool _on = true;
  bool _ticking = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ticking = TickerMode.valuesOf(context).enabled;
    _sync();
  }

  @override
  void didUpdateWidget(covariant _SkyName oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final run = widget.caret && widget.motion && _ticking;
    if (run && _blink == null) {
      _blink = Timer.periodic(_period, (_) {
        if (mounted) setState(() => _on = !_on);
      });
    } else if (!run && _blink != null) {
      _blink!.cancel();
      _blink = null;
      _on = true;
    }
  }

  @override
  void dispose() {
    _blink?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final style = SkyType.serif(_SkyName.size, weight: FontWeight.w500, height: _SkyName.height).copyWith(
      color: t.label,
      shadows: [Shadow(color: t.nameShadow, blurRadius: 8)],
    );
    final caret = Opacity(
      opacity: _on ? 1 : 0,
      child: Container(
        width: 2,
        height: 22,
        margin: const EdgeInsets.only(left: 2),
        decoration: BoxDecoration(
          color: t.rose,
          borderRadius: SkyRadii.all(1),
          boxShadow: [BoxShadow(color: t.rose, blurRadius: 8)],
        ),
      ),
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            widget.text,
            textAlign: TextAlign.center,
            maxLines: widget.maxLines,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
        if (widget.caret) caret,
      ],
    );
  }
}

class _SavedNote extends StatefulWidget {
  const _SavedNote({required this.motion});

  final bool motion;

  @override
  State<_SavedNote> createState() => _SavedNoteState();
}

class _SavedNoteState extends State<_SavedNote> with SingleTickerProviderStateMixin {
  late final AnimationController _run = AnimationController(
    vsync: this,
    duration: widget.motion ? const Duration(milliseconds: 900) : SkyMotion.fast,
  )..forward();

  @override
  void dispose() {
    _run.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    return SizedBox(
      height: 28,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          if (widget.motion)
            Positioned(
              left: 0,
              right: 0,
              top: -40,
              height: 80,
              child: IgnorePointer(
                child: CustomPaint(painter: _Sparkles(progress: _run, color: t.sparkle)),
              ),
            ),
          FadeTransition(
            opacity: CurvedAnimation(parent: _run, curve: const Interval(0, 1 / 3, curve: Curves.easeOut)),
            child: Text(
              SkyTogetherCopy.saved,
              style: SkyType.sans(12.5, weight: FontWeight.w600).copyWith(color: t.tipText),
            ),
          ),
        ],
      ),
    );
  }
}

class _Sparkles extends CustomPainter {
  _Sparkles({required this.progress, required this.color}) : super(repaint: progress);

  final Animation<double> progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    if (t >= 1) return;
    final c = size.center(Offset.zero);
    final reach = Curves.easeOutCubic.transform(t);
    for (var i = 0; i < 12; i++) {
      final a = i / 12 * math.pi * 2 + 0.3;
      final r = 24 + 70 * reach * (i.isEven ? 1 : 0.7);
      final p = c + Offset(math.cos(a) * r, math.sin(a) * r * 0.45);
      canvas.drawCircle(p, i.isEven ? 1.6 : 1.1, Paint()..color = color.withValues(alpha: 0.9 * (1 - t)));
    }
  }

  @override
  bool shouldRepaint(_Sparkles oldDelegate) => oldDelegate.progress != progress || oldDelegate.color != color;
}

class _TypingDots extends StatefulWidget {
  const _TypingDots({required this.motion});

  final bool motion;

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _cycle = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void initState() {
    super.initState();
    if (widget.motion) _cycle.repeat();
  }

  @override
  void dispose() {
    _cycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rose = context.sky.rose;
    const levels = [1.0, 0.6, 0.3];
    return AnimatedBuilder(
      animation: _cycle,
      builder: (context, _) {
        final shift = widget.motion ? (_cycle.value * 3).floor() % 3 : 0;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++)
              Container(
                width: 4,
                height: 4,
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: rose.withValues(alpha: levels[(i + shift) % 3]),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _RoseDot extends StatelessWidget {
  const _RoseDot();

  @override
  Widget build(BuildContext context) {
    final rose = context.sky.rose;
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: rose,
        boxShadow: [BoxShadow(color: rose, blurRadius: 8)],
      ),
    );
  }
}

class _DashedUnderline extends CustomPainter {
  const _DashedUnderline({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    SkyPatchArt.dashed(canvas, Offset(0, size.height - 0.5), Offset(size.width, size.height - 0.5), paint, 4, 3);
  }

  @override
  bool shouldRepaint(_DashedUnderline oldDelegate) => oldDelegate.color != color;
}
