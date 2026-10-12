import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../widgets/our_widgets.dart';
import 'memories_copy.dart';

Future<void> showPolaroidPreview(
  BuildContext context, {
  required String memoryId,
  required Uint8List photo,
  required String caption,
  required ValueListenable<Set<String>> visibleIds,
}) {
  return showOurModal<void>(
    context: context,
    backdrop: OurBackdropTone.black80,
    entrance: OurModalEntrance.none,
    barrierDismissible: true,
    builder: (_) => PolaroidPreview(memoryId: memoryId, photo: photo, caption: caption, visibleIds: visibleIds),
  );
}

class PolaroidPreview extends StatefulWidget {
  const PolaroidPreview({
    super.key,
    required this.memoryId,
    required this.photo,
    required this.caption,
    required this.visibleIds,
  });

  final String memoryId;
  final Uint8List photo;
  final String caption;
  final ValueListenable<Set<String>> visibleIds;

  @override
  State<PolaroidPreview> createState() => _PolaroidPreviewState();
}

class _PolaroidPreviewState extends State<PolaroidPreview> {
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    widget.visibleIds.addListener(_onIds);
  }

  @override
  void dispose() {
    widget.visibleIds.removeListener(_onIds);
    super.dispose();
  }

  void _onIds() {
    if (_closing || widget.visibleIds.value.contains(widget.memoryId)) return;
    _closing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route != null && route.isCurrent) Navigator.of(context).pop();
    });
  }

  void _close() {
    if (_closing) return;
    _closing = true;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final maxCardWidth = math.min(media.size.width * 0.92, media.size.width - 32);
    final maxImageHeight = media.size.height * 0.7;

    final card = CssBox(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
      color: AppColors.white,
      borderRadius: AppRadii.all(AppRadii.x3l),
      shadows: AppShadows.x2l,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CssBox(
            color: AppColors.black.withValues(alpha: 0.05),
            borderRadius: AppRadii.all(AppRadii.x2l),
            clipContent: true,
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxImageHeight),
                child: Image.memory(
                  widget.photo,
                  gaplessPlayback: true,
                  semanticLabel: MemoriesCopy.fullPolaroid,
                  errorBuilder: (context, error, stack) => const SizedBox(width: 120, height: 120),
                ),
              ),
            ),
          ),
          if (widget.caption.isEmpty)
            const SizedBox(height: 12)
          else
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                widget.caption,
                textAlign: TextAlign.center,
                style: Tw.x2l.handwriting.c(AppColors.slate800),
              ),
            ),
        ],
      ),
    );

    return Material(
      type: MaterialType.transparency,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxCardWidth),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {},
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              IntrinsicWidth(child: card),
              Positioned(
                top: -12,
                right: -12,
                child: OurCloseButton(
                  onPressed: _close,
                  background: AppColors.white,
                  foreground: AppColors.slate700,
                  shadows: AppShadows.lg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
