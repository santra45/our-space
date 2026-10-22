import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/engine.dart';
import '../../sky/sky.dart';
import '../../space_scope.dart';
import '../../widgets/app_haptics.dart';
import '../../widgets/confetti_burst.dart';
import '../polaroids/photo_compression.dart';
import '../polaroids/photo_picker.dart';
import 'memories_copy.dart';
import 'memory_marks.dart';
import 'memory_photos.dart';
import 'widgets/polaroid.dart';

Future<bool> showAddMemorySheet(BuildContext context) async {
  final added = await showSkySheet<bool>(context: context, builder: (_) => const AddMemorySheet());
  return added ?? false;
}

class AddMemorySheet extends StatefulWidget {
  const AddMemorySheet({super.key});

  static const double composerWidth = 264;

  @override
  State<AddMemorySheet> createState() => _AddMemorySheetState();
}

class _AddMemorySheetState extends State<AddMemorySheet> {
  final TextEditingController _caption = TextEditingController();
  final FocusNode _captionFocus = FocusNode();
  PickedPhoto? _picked;
  String _date = toLocalDateInput();
  bool _saving = false;
  bool _picking = false;
  bool _choosingDate = false;
  String _status = '';
  String _error = '';

  @override
  void dispose() {
    _caption.dispose();
    _captionFocus.dispose();
    super.dispose();
  }

  DateTime get _day => parseLocalDate(_date) ?? DateTime.now();

  Future<void> _pick(PhotoSource source) async {
    if (_saving || _picking) return;
    _picking = true;
    PickedPhoto? photo;
    try {
      photo = await MemoryPhotos.pick(source);
    } catch (_) {
      _picking = false;
      if (!mounted) return;
      setState(() => _error = source == PhotoSource.camera ? MemoriesCopy.cameraFailed : MemoriesCopy.galleryFailed);
      return;
    }
    _picking = false;
    if (photo == null || !mounted) return;
    AppHaptics.tap();
    setState(() {
      _error = '';
      _picked = photo;
    });
  }

  void _clearPhoto() {
    if (_saving) return;
    setState(() {
      _picked = null;
      _error = '';
    });
  }

  void _close() {
    if (_saving) return;
    Navigator.of(context).pop();
  }

  void _onCaptionChanged(String value) {
    if (_error == MemoriesCopy.fillCaption && value.isNotEmpty) {
      setState(() => _error = '');
    }
  }

  Future<void> _pickDate() async {
    if (_saving || _choosingDate) return;
    _choosingDate = true;
    final now = DateTime.now();
    final first = DateTime(1970);
    final last = DateTime(now.year + 100);
    var initial = _day;
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      helpText: MemoriesCopy.dateLabel.toUpperCase(),
    );
    _choosingDate = false;
    if (!mounted || picked == null) return;
    setState(() => _date = toLocalDateInput(picked));
  }

  Future<void> _save() async {
    final picked = _picked;
    if (_saving || picked == null) return;
    if (_caption.text.isEmpty) {
      _captionFocus.requestFocus();
      setState(() => _error = MemoriesCopy.fillCaption);
      return;
    }

    final space = context.space;
    if (space.vault.key == null) {
      setState(() => _error = MemoriesCopy.lockedTryAgain);
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _error = '';
      _saving = true;
      _status = MemoriesCopy.gettingReady;
    });
    AppHaptics.tap();

    final marks = MemoryMarks.of(space.store.settings);
    marks.beginAdd();
    String? addedId;
    String? failure;
    try {
      final photo = await compressPhoto(picked.bytes);
      if (!mounted) return;
      setState(() => _status = MemoriesCopy.tuckingAway);
      final row = await space.memories.add(
        photo: photo.bytes,
        mime: photo.mime,
        date: _date,
        caption: _caption.text,
        onSealed: () {
          if (mounted) setState(() => _status = MemoriesCopy.savingWall);
        },
      );
      final id = row['id'];
      if (id is String) addedId = id;
      if (!mounted) return;
      AppHaptics.celebration();
      fireHeartConfetti(context);
      Navigator.of(context).pop(true);
      return;
    } on PhotoTooLargeError {
      failure = MemoriesCopy.tooLarge;
    } on PhotoCompressionError catch (e) {
      failure = MemoriesCopy.saveFailedWith(e.message);
    } on RepositoryError catch (e) {
      failure = MemoriesCopy.saveFailedWith(e.message);
    } catch (_) {
      failure = MemoriesCopy.saveFailed;
    } finally {
      marks.endAdd(addedId);
    }
    if (!mounted) return;
    setState(() {
      _error = failure ?? '';
      _saving = false;
      _status = '';
    });
  }

  Widget _header(SkyTokens t) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SkyLabel(MemoriesCopy.sheetKicker, icon: SkyIcons.sparkle, tone: SkyTone.rose),
              const SizedBox(height: 6),
              Semantics(
                header: true,
                child: Text(MemoriesCopy.sheetTitle, style: SkyType.title.copyWith(color: t.title)),
              ),
            ],
          ),
        ),
        const SizedBox(width: SkySpace.md),
        SkyIconButton(
          icon: SkyIcons.close,
          tone: SkyIconButtonTone.ghost,
          size: 38,
          semanticLabel: MemoriesCopy.close,
          onPressed: _saving ? null : _close,
        ),
      ],
    );
  }

  Widget _chooser() {
    return CustomPaint(
      painter: const PolaroidDashedFrame(),
      child: ColoredBox(
        color: PolaroidColors.bed.withValues(alpha: 0.6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: SkyIcon(SkyIcons.camera, size: 26, color: PolaroidColors.faded)),
              const SizedBox(height: 10),
              Text(
                MemoriesCopy.captureOrChoose,
                textAlign: TextAlign.center,
                style: SkyType.sans(12, weight: FontWeight.w600, height: 1.35).copyWith(color: PolaroidColors.ink),
              ),
              const SizedBox(height: 14),
              _PaperButton(
                label: MemoriesCopy.camera,
                icon: SkyIcons.camera,
                strong: true,
                onTap: () => _pick(PhotoSource.camera),
              ),
              const SizedBox(height: 8),
              _PaperButton(
                label: MemoriesCopy.gallery,
                icon: SkyIcons.photo,
                onTap: () => _pick(PhotoSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _preview(PickedPhoto picked) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final ratio = MediaQuery.devicePixelRatioOf(context);
        final width = math.max(1, (constraints.maxWidth * ratio * 2).round());
        final height = math.max(1, (constraints.maxHeight * ratio * 2).round());
        return Stack(
          fit: StackFit.expand,
          children: [
            PolaroidImage(
              image: ResizeImage(
                MemoryImage(picked.bytes),
                width: width,
                height: height,
                policy: ResizeImagePolicy.fit,
                allowUpscaling: false,
              ),
              semanticLabel: MemoriesCopy.previewAlt,
            ),
            Positioned(
              right: 10,
              bottom: 10,
              child: SkyPressable(
                onTap: _saving ? null : _clearPhoto,
                enabled: !_saving,
                semanticLabel: MemoriesCopy.changePhoto,
                excludeSemantics: true,
                child: AnimatedOpacity(
                  opacity: _saving ? 0.4 : 1,
                  duration: SkyMotion.fast,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0x99141238),
                      borderRadius: SkyRadii.all(SkyRadii.pill),
                      border: Border.all(color: const Color(0x33FFFFFF)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SkyIcon(SkyIcons.refresh, size: 13, color: SkyTokens.white),
                        const SizedBox(width: 6),
                        Text(
                          MemoriesCopy.changePhoto,
                          style: SkyType.sans(11.5, weight: FontWeight.w600).copyWith(color: SkyTokens.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _captionField() {
    final style = polaroidCaptionStyle(22);
    final field = TextField(
      controller: _caption,
      focusNode: _captionFocus,
      enabled: !_saving,
      minLines: 1,
      maxLines: 3,
      maxLength: MemoriesCopy.captionMaxLength,
      buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
      textCapitalization: TextCapitalization.sentences,
      onChanged: _onCaptionChanged,
      cursorColor: context.sky.roseDeep,
      style: style,
      decoration: const InputDecoration(
        isCollapsed: true,
        filled: false,
        contentPadding: EdgeInsets.symmetric(vertical: 3),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        focusedErrorBorder: InputBorder.none,
      ),
    );
    return Semantics(
      label: MemoriesCopy.captionLabel,
      hint: MemoriesCopy.captionHint,
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: _caption,
        builder: (context, value, child) => Stack(
          children: [
            if (value.text.isEmpty)
              IgnorePointer(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text(
                    MemoriesCopy.captionHint,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: style.copyWith(color: PolaroidColors.faded),
                  ),
                ),
              ),
            child!,
          ],
        ),
        child: field,
      ),
    );
  }

  Widget _composer() {
    final picked = _picked;
    final motion = skyMotionAllowed(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AddMemorySheet.composerWidth),
        child: PolaroidPaper(
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 0),
          pin: PolaroidPin.tape,
          photo: AspectRatio(
            aspectRatio: 4 / 5,
            child: AnimatedSwitcher(
              duration: motion ? SkyMotion.base : Duration.zero,
              switchInCurve: SkyMotion.gentle,
              switchOutCurve: Curves.easeIn,
              child: picked == null
                  ? KeyedSubtree(key: const ValueKey<String>('memory-chooser'), child: _chooser())
                  : KeyedSubtree(key: ValueKey<int>(identityHashCode(picked)), child: _preview(picked)),
            ),
          ),
          caption: _captionField(),
          meta: MemoriesCopy.meta([MemoriesCopy.fullDay(_day), MemoriesCopy.byYou]),
        ),
      ),
    );
  }

  Widget _dateRow(SkyTokens t) {
    final value = MemoriesCopy.fullDay(_day);
    return SkyPressable(
      onTap: _saving ? null : _pickDate,
      enabled: !_saving,
      pressedScale: 0.98,
      semanticLabel: '${MemoriesCopy.dateLabel}, $value',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: t.chip,
          borderRadius: SkyRadii.all(SkyRadii.tile),
          border: Border.all(color: t.chipBorder),
        ),
        child: Row(
          children: [
            const SkyIconTile(icon: SkyIcons.calendar, tone: SkyTone.gold, size: 40, iconSize: 20),
            const SizedBox(width: SkySpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(MemoriesCopy.dateLabel, style: SkyType.sans(13.5, weight: FontWeight.w600).copyWith(color: t.text)),
                  const SizedBox(height: 2),
                  Text(value, style: SkyType.small.copyWith(color: t.muted)),
                ],
              ),
            ),
            SkyIcon(SkyIcons.chevron, size: 15, color: t.muted),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final motion = skyMotionAllowed(context);
    return PopScope(
      canPop: !_saving,
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(t),
            const SizedBox(height: SkySpace.xl),
            _composer(),
            const SizedBox(height: SkySpace.xl),
            _dateRow(t),
            AnimatedSwitcher(
              duration: motion ? SkyMotion.quick : Duration.zero,
              child: _error.isEmpty
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      key: ValueKey<String>(_error),
                      padding: const EdgeInsets.only(top: SkySpace.md),
                      child: SkyNotice(text: _error, tone: SkyNoticeTone.error),
                    ),
            ),
            const SizedBox(height: SkySpace.lg),
            SkyButton(
              label: MemoriesCopy.pinIt,
              icon: SkyIcons.heart,
              busy: _saving,
              busyLabel: _status.isEmpty ? MemoriesCopy.pinning : _status,
              onPressed: _picked == null ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}

class _PaperButton extends StatelessWidget {
  const _PaperButton({required this.label, required this.icon, required this.onTap, this.strong = false});

  final String label;
  final SkyIcons icon;
  final VoidCallback onTap;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final fg = strong ? SkyTokens.white : PolaroidColors.ink;
    return SkyPressable(
      onTap: onTap,
      semanticLabel: label,
      excludeSemantics: true,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          gradient: strong ? t.roseOrbGradient : null,
          color: strong ? null : SkyTokens.white,
          borderRadius: SkyRadii.all(SkyRadii.pill),
          border: Border.all(color: strong ? const Color(0x4DFFFFFF) : const Color(0x1F2A2440)),
          boxShadow: strong ? const [BoxShadow(color: Color(0x4DE24E79), offset: Offset(0, 5), blurRadius: 10)] : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SkyIcon(icon, size: 16, color: strong ? SkyTokens.white : t.roseDeep),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SkyType.sans(12.5, weight: FontWeight.w700).copyWith(color: fg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
