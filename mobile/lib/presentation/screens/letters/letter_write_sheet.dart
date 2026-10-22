import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/engine.dart';
import '../../sky/sky.dart';
import '../../space_scope.dart';
import '../../widgets/app_haptics.dart';
import '../../widgets/confetti_burst.dart';
import 'letter_shelf.dart';
import 'letters_copy.dart';
import 'letters_keys.dart';
import 'widgets/ruled_paper.dart';
import 'widgets/wax_seal.dart';

Future<String?> showLetterWriter(BuildContext context) {
  return showSkySheet<String>(
    context: context,
    chrome: false,
    enableDrag: false,
    maxHeightFactor: 1,
    padding: EdgeInsets.zero,
    builder: (_) => const LetterWriteSheet(),
  );
}

class LetterWriteSheet extends StatefulWidget {
  const LetterWriteSheet({super.key});

  static const SkyScene scene = SkyScene(
    stars: 40,
    moon: Offset(330, 92),
    sun: false,
    clouds: [SkyCloud(320, 96, scale: 0.8, opacity: 0.8)],
  );

  @override
  State<LetterWriteSheet> createState() => _LetterWriteSheetState();
}

class _LetterWriteSheetState extends State<LetterWriteSheet> {
  late final OurSpace _space = context.space;
  late final LetterDraft _draft = LetterDraft.forKey(_space.vault.key);
  late final TextEditingController _title = TextEditingController(text: _draft.title);
  late final TextEditingController _content = TextEditingController(text: _draft.content);
  bool _saving = false;
  String _error = '';

  bool get _canSave => !_saving && _title.text.trim().isNotEmpty && _content.text.trim().isNotEmpty;

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  void _onTitle(String value) => setState(() => _draft.title = value);

  void _onContent(String value) => setState(() => _draft.content = value);

  void _usePrompt(String prompt) {
    _title.value = TextEditingValue(text: prompt, selection: TextSelection.collapsed(offset: prompt.length));
    setState(() => _draft.title = prompt);
  }

  Future<void> _pickDate() async {
    if (_saving) return;
    final today = startOfLocalDay(DateTime.now());
    final chosen = _draft.unlockDate == null ? null : parseLocalDate(_draft.unlockDate);
    final picked = await showDatePicker(
      context: context,
      initialDate: chosen != null && !chosen.isBefore(today) ? chosen : today,
      firstDate: today,
      lastDate: DateTime(today.year + 100),
      helpText: LettersCopy.pickDay,
    );
    if (picked == null || !mounted) return;
    setState(() => _draft.unlockDate = toLocalDateInput(picked));
  }

  void _setSealed(bool sealed) {
    if (sealed) {
      unawaited(_pickDate());
    } else {
      setState(() => _draft.unlockDate = null);
    }
  }

  Future<void> _seal() async {
    if (!_canSave) return;
    final letters = _space.letters;
    final settings = _space.store.settings;
    final notices = context.read<AppNotices>();
    final partner = context.read<IdentityController>().partnerName;
    FocusScope.of(context).unfocus();
    setState(() {
      _error = '';
      _saving = true;
    });
    AppHaptics.tap();
    try {
      final row = await letters.writeLetter(title: _title.text, content: _content.text, unlockDate: _draft.unlockDate);
      final id = row?['id'];
      if (id is String) {
        try {
          await LettersWrittenHere.remember(settings, id);
        } catch (_) {}
      }
      if (!mounted) return;
      AppHaptics.celebration();
      fireHeartConfetti(context);
      _draft.clear();
      notices.showToast(LettersCopy.sealedToast(partner));
      Navigator.of(context).pop(id is String ? id : null);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = LettersCopy.saveFailed);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final top = MediaQuery.viewPaddingOf(context).top;
    final partner = context.watch<IdentityController>().partnerName;
    return SizedBox.expand(
      child: SkyScaffold(
        scene: LetterWriteSheet.scene,
        skyHeight: 300,
        fadeSky: false,
        body: Stack(
          children: [
            Positioned(top: top + 2, left: SkySpace.gutter, right: SkySpace.gutter, child: _topBar(t)),
            Positioned(
              top: top + 68,
              left: 0,
              right: 0,
              bottom: 0,
              child: SkySheet(
                showGrab: false,
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(SkySpace.gutter, 2, SkySpace.gutter, SkySpace.md),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: SkySizes.maxContentWidth),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SkyEntrance(index: 1, child: _prompts()),
                                const SizedBox(height: SkySpace.lg),
                                SkyEntrance(index: 2, child: _titleField()),
                                const SizedBox(height: 14),
                                SkyEntrance(index: 3, child: _paper(t, partner)),
                                const SizedBox(height: 14),
                                SkyEntrance(index: 4, child: _sealRow(t)),
                                if (_draft.unlockDate != null) ...[
                                  const SizedBox(height: 10),
                                  SkyEntrance(
                                    key: const ValueKey<String>('letter-seal-note'),
                                    offset: const Offset(0, -6),
                                    child: Text(LettersCopy.sealNote, style: SkyType.caption.copyWith(color: t.faint)),
                                  ),
                                ],
                                if (_error.isNotEmpty) ...[
                                  const SizedBox(height: SkySpace.md),
                                  SkyEntrance(
                                    key: ValueKey<String>(_error),
                                    child: Text(
                                      _error,
                                      textAlign: TextAlign.center,
                                      style: SkyType.sans(12, weight: FontWeight.w600).copyWith(color: t.rose),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(SkySpace.gutter, SkySpace.xs, SkySpace.gutter, SkySpace.lg),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: SkySizes.maxContentWidth),
                          child: SkyButton(
                            key: LettersKeys.sealButton,
                            label: LettersCopy.seal,
                            busy: _saving,
                            busyLabel: LettersCopy.sealing,
                            leading: const _WaxDot(),
                            onPressed: _canSave ? _seal : null,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topBar(SkyTokens t) {
    final side = SkyType.sans(14, weight: FontWeight.w600);
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: SkyPressable(
                key: LettersKeys.cancel,
                onTap: () => Navigator.of(context).maybePop(),
                semanticLabel: LettersCopy.cancel,
                excludeSemantics: true,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: SkySpace.sm),
                  child: Text(LettersCopy.cancel, style: side.copyWith(color: t.muted)),
                ),
              ),
            ),
          ),
          Semantics(
            header: true,
            child: Text(LettersCopy.newLetter, style: SkyType.serif(19, height: 1.2).copyWith(color: t.title)),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: AnimatedOpacity(
                key: LettersKeys.saved,
                opacity: _draft.isEmpty ? 0 : 1,
                duration: skyMotionAllowed(context) ? SkyMotion.quick : Duration.zero,
                child: Text(LettersCopy.saved, style: side.copyWith(color: t.faint)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _prompts() {
    final current = _title.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SkyLabel(LettersCopy.startWithFeeling, icon: SkyIcons.sparkle, tone: SkyTone.rose),
        const SizedBox(height: 10),
        Wrap(
          spacing: SkySpace.sm,
          runSpacing: SkySpace.sm,
          children: [
            for (final prompt in LettersCopy.prompts)
              PromptChip(label: prompt, selected: current == prompt, onTap: () => _usePrompt(prompt)),
          ],
        ),
      ],
    );
  }

  Widget _titleField() {
    return SkyTextField(
      key: LettersKeys.titleField,
      controller: _title,
      style: SkyFieldStyle.underline,
      label: LettersCopy.titleLabel,
      helper: LettersCopy.titleHelper,
      hint: LettersCopy.titleHint,
      maxLength: LettersCopy.titleMaxLength,
      textInputAction: TextInputAction.next,
      onChanged: _onTitle,
    );
  }

  Widget _paper(SkyTokens t, String partner) {
    final ink = SkyType.serif(16, italic: false, height: 30 / 16).copyWith(color: t.paperInk);
    const none = InputBorder.none;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.paper,
        borderRadius: SkyRadii.all(SkyRadii.paper),
        boxShadow: t.softShadow,
      ),
      child: ClipRRect(
        borderRadius: SkyRadii.all(SkyRadii.paper),
        child: CustomPaint(
          painter: const RuledLinesPainter(color: LetterInk.writeLine, spacing: 30, offset: 43),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 230),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 34),
                  child: TextField(
                    key: LettersKeys.bodyField,
                    controller: _content,
                    minLines: 6,
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                    textCapitalization: TextCapitalization.sentences,
                    style: ink,
                    cursorColor: t.roseDeep,
                    cursorHeight: 20,
                    cursorWidth: 2,
                    onChanged: _onContent,
                    decoration: InputDecoration(
                      isCollapsed: true,
                      filled: false,
                      contentPadding: EdgeInsets.zero,
                      hintText: LettersCopy.bodyHint,
                      hintStyle: ink.copyWith(color: t.paperMuted),
                      border: none,
                      enabledBorder: none,
                      focusedBorder: none,
                      disabledBorder: none,
                      errorBorder: none,
                      focusedErrorBorder: none,
                    ),
                  ),
                ),
                Positioned(
                  right: 14,
                  bottom: 10,
                  child: Text(
                    LettersCopy.forOnly(partner),
                    style: SkyType.sans(10.5).copyWith(color: t.paperMuted),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sealRow(SkyTokens t) {
    final date = _draft.unlockDate;
    final sealed = date != null;
    final subtitle = sealed ? LettersCopy.sealOn(date, DateTime.now(), night: t.isNight) : LettersCopy.sealOff;
    return SkyPressable(
      key: LettersKeys.sealRow,
      onTap: _pickDate,
      pressedScale: 0.98,
      semanticLabel: '${LettersCopy.sealUntil}, $subtitle',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: SkySpace.md),
        decoration: BoxDecoration(
          color: t.chip,
          borderRadius: SkyRadii.all(SkyRadii.tile),
          border: Border.all(color: t.chipBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: t.roseSoft, borderRadius: SkyRadii.all(12)),
              alignment: Alignment.center,
              child: SkyIcon(SkyIcons.moon, size: 20, color: t.gold),
            ),
            const SizedBox(width: SkySpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    LettersCopy.sealUntil,
                    style: SkyType.sans(13.5, weight: FontWeight.w700, height: 1.3).copyWith(color: t.text),
                  ),
                  const SizedBox(height: SkySpace.xxs),
                  Text(subtitle, style: SkyType.small.copyWith(color: t.muted)),
                ],
              ),
            ),
            const SizedBox(width: SkySpace.sm),
            SkyToggle(
              key: LettersKeys.sealToggle,
              value: sealed,
              onChanged: _saving ? null : _setSealed,
              semanticLabel: LettersCopy.sealUntil,
            ),
          ],
        ),
      ),
    );
  }
}

class PromptChip extends StatelessWidget {
  const PromptChip({super.key, required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final fg = selected ? t.activeFg : t.text;
    return SkyPressable(
      onTap: onTap,
      semanticLabel: label,
      selected: selected,
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: skyMotionAllowed(context) ? SkyMotion.quick : Duration.zero,
        curve: SkyMotion.standard,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? t.activeBg : t.chip,
          borderRadius: SkyRadii.all(SkyRadii.pill),
          border: Border.all(color: selected ? const Color(0x00000000) : t.chipBorder),
        ),
        child: Text(label, style: SkyType.sans(11.5, weight: FontWeight.w600, height: 1.2).copyWith(color: fg)),
      ),
    );
  }
}

class _WaxDot extends StatelessWidget {
  const _WaxDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: Alignment(-0.3, -0.4),
          radius: 0.955,
          colors: [LetterInk.waxLight, LetterInk.waxBlush],
          stops: [0, 0.7],
        ),
      ),
      child: SkyIcon(SkyIcons.heart, size: 14, color: context.sky.roseDeep),
    );
  }
}
