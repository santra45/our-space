import 'package:flutter/material.dart';

import '../../../core/engine.dart';
import '../../space_scope.dart';
import '../../widgets/our_widgets.dart';
import 'memories_copy.dart';
import 'photo_compression.dart';
import 'photo_picker.dart';

Future<void> showAddMemoryModal(BuildContext context) {
  return showOurModal<void>(
    context: context,
    backdrop: OurBackdropTone.slate40,
    entrance: OurModalEntrance.pop,
    builder: (_) => const AddMemoryModal(),
  );
}

class AddMemoryModal extends StatefulWidget {
  const AddMemoryModal({super.key});

  @override
  State<AddMemoryModal> createState() => _AddMemoryModalState();
}

class _AddMemoryModalState extends State<AddMemoryModal> {
  final TextEditingController _caption = TextEditingController();
  final FocusNode _captionFocus = FocusNode();
  PickedPhoto? _picked;
  String _date = toLocalDateInput();
  bool _saving = false;
  bool _picking = false;
  String _status = '';
  String _error = '';

  @override
  void dispose() {
    _caption.dispose();
    _captionFocus.dispose();
    super.dispose();
  }

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

    setState(() {
      _error = '';
      _saving = true;
      _status = MemoriesCopy.gettingReady;
    });
    AppHaptics.tap();

    String? failure;
    try {
      final photo = await compressPhoto(picked.bytes);
      if (!mounted) return;
      setState(() => _status = MemoriesCopy.tuckingAway);
      await space.memories.add(
        photo: photo.bytes,
        mime: photo.mime,
        date: _date,
        caption: _caption.text,
        onSealed: () {
          if (mounted) setState(() => _status = MemoriesCopy.savingScrapbook);
        },
      );
      if (!mounted) return;
      AppHaptics.celebration();
      fireHeartConfetti(context);
      Navigator.of(context).pop();
      return;
    } on PhotoTooLargeError catch (e) {
      failure = e.message;
    } on PhotoCompressionError catch (e) {
      failure = MemoriesCopy.saveFailedWith(e.message);
    } on RepositoryError catch (e) {
      failure = MemoriesCopy.saveFailedWith(e.message);
    } catch (_) {
      failure = MemoriesCopy.saveFailed;
    }
    if (!mounted) return;
    setState(() {
      _error = failure ?? '';
      _saving = false;
      _status = '';
    });
  }

  Widget _photoPanel() {
    final picked = _picked;
    if (picked != null) {
      final ratio = MediaQuery.devicePixelRatioOf(context);
      final width = (modalMaxWidth(context) * ratio).round();
      return AspectRatio(
        aspectRatio: 4 / 5,
        child: CssBox(
          color: AppColors.slate100,
          border: Border.all(color: AppColors.blush200, width: 2),
          borderRadius: AppRadii.all(AppRadii.x2l),
          clipContent: true,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image(
                image: ResizeImage(
                  MemoryImage(picked.bytes),
                  width: width,
                  height: (width * 5 / 4).round(),
                  policy: ResizeImagePolicy.fit,
                  allowUpscaling: false,
                ),
                fit: BoxFit.contain,
                gaplessPlayback: true,
                semanticLabel: MemoriesCopy.previewAlt,
                errorBuilder: (context, error, stack) => const SizedBox.shrink(),
              ),
              Positioned(
                right: 12,
                bottom: 12,
                child: Semantics(
                  container: true,
                  button: true,
                  enabled: !_saving,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _saving ? null : _clearPhoto,
                    child: Opacity(
                      opacity: _saving ? 0.4 : 1,
                      child: CssBox(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        color: AppColors.black.withValues(alpha: 0.6),
                        backdropBlur: 4,
                        borderRadius: AppRadii.all(AppRadii.xl),
                        child: Text(MemoriesCopy.changePhoto, style: Tw.xs.semibold.c(AppColors.white)),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return CssBox(
      padding: const EdgeInsets.all(24),
      color: AppColors.blush50.withValues(alpha: 0.5),
      dashedBorder: const BorderSide(color: AppColors.blush200, width: 2),
      borderRadius: AppRadii.all(AppRadii.x2l),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            MemoriesCopy.captureOrChoose,
            textAlign: TextAlign.center,
            style: Tw.xs.semibold.c(AppColors.slate600),
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              BouncyButton(
                onPressed: () => _pick(PhotoSource.camera),
                icon: AppIcons.camera,
                label: MemoriesCopy.camera,
                small: true,
              ),
              BouncyButton(
                onPressed: () => _pick(PhotoSource.gallery),
                icon: AppIcons.image,
                label: MemoriesCopy.gallery,
                variant: BouncyVariant.secondary,
                small: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sans = Theme.of(context).textTheme.bodyMedium;
    final captionStyle = OurFieldStyle.form.copyWith(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      textStyle: Tw.lg.handwriting.c(AppColors.slate800),
      hintStyle: Tw.xs.c(AppColors.slate300).copyWith(
        fontFamily: sans?.fontFamily,
        fontFamilyFallback: sans?.fontFamilyFallback,
      ),
    );

    return PopScope(
      canPop: !_saving,
      child: OurModalCard(
        onClose: _close,
        closeEnabled: !_saving,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const OurModalHeader(
              title: MemoriesCopy.modalTitle,
              subtitle: MemoriesCopy.modalSubtitle,
              icon: AppIcons.sparkles,
            ),
            ...spaced([
              _photoPanel(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const OurFieldLabel(MemoriesCopy.captionLabel),
                  OurTextField(
                    controller: _caption,
                    focusNode: _captionFocus,
                    style: captionStyle,
                    hint: MemoriesCopy.captionHint,
                    maxLength: MemoriesCopy.captionMaxLength,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: _onCaptionChanged,
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const OurFieldLabel(MemoriesCopy.dateLabel),
                  OurDateField(
                    value: parseLocalDate(_date),
                    semanticLabel: MemoriesCopy.dateLabel,
                    onChanged: (picked) => setState(() => _date = toLocalDateInput(picked)),
                  ),
                ],
              ),
              if (_error.isNotEmpty)
                OurNotice(
                  tone: NoticeTone.error,
                  message: _error,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  radius: AppRadii.xl,
                  textStyle: Tw.px11.relaxed,
                ),
              BouncyButton(
                onPressed: _save,
                enabled: !_saving && _picked != null,
                expand: true,
                label: _saving
                    ? (_status.isEmpty ? MemoriesCopy.developingPolaroid : _status)
                    : MemoriesCopy.pinIt,
              ),
            ], 16),
          ],
        ),
      ),
    );
  }
}
