import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/engine.dart';
import '../../sky/sky.dart';
import '../../space_scope.dart';
import '../../widgets/app_haptics.dart';
import 'memories_copy.dart';
import 'memory_photos.dart';
import 'widgets/polaroid.dart';

class MemoryRemoval {
  const MemoryRemoval._(this.removed, this.error);

  const MemoryRemoval.failed(String message) : this._(false, message);

  static const MemoryRemoval cancelled = MemoryRemoval._(false, null);
  static const MemoryRemoval done = MemoryRemoval._(true, null);

  final bool removed;
  final String? error;

  bool get isCancelled => !removed && error == null;
}

Future<MemoryRemoval> confirmAndRemoveMemory(BuildContext context, MemoryRecord memory) async {
  final memories = context.space.memories;
  final confirmed = await showSkyConfirm(
    context,
    title: MemoriesCopy.removeTitle,
    message: MemoriesCopy.removeMessage,
    confirmLabel: MemoriesCopy.removeConfirm,
    cancelLabel: MemoriesCopy.removeCancel,
    destructive: true,
    icon: SkyIcons.trash,
  );
  if (!confirmed) return MemoryRemoval.cancelled;
  AppHaptics.tap();
  try {
    final tombstone = await memories.delete(memory.id);
    if (tombstone == null) return const MemoryRemoval.failed(MemoriesCopy.alreadyRemoved);
    return MemoryRemoval.done;
  } on RepositoryError catch (e) {
    return MemoryRemoval.failed(MemoriesCopy.removeFailedWith(e.message));
  } catch (_) {
    return const MemoryRemoval.failed(MemoriesCopy.removeFailed);
  }
}

Color _viewerScrim(SkyTokens t) => t.isNight ? const Color(0xE6060516) : const Color(0xD91E1B3A);

Future<void> showMemoryViewer(
  BuildContext context, {
  required MemoryRecord memory,
  required ValueListenable<Set<String>> visibleIds,
  Uint8List? photo,
  String note = MemoriesCopy.noImage,
  String meta = '',
}) {
  final tokens = context.sky;
  return showGeneralDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    barrierLabel: MemoriesCopy.close,
    barrierColor: _viewerScrim(tokens),
    transitionDuration: SkyMotion.medium,
    pageBuilder: (dialogContext, animation, secondary) => SkyTheme(
      child: MemoryViewer(memory: memory, visibleIds: visibleIds, photo: photo, note: note, meta: meta),
    ),
    transitionBuilder: (dialogContext, animation, secondary, child) {
      final fade = CurvedAnimation(parent: animation, curve: SkyMotion.gentle, reverseCurve: Curves.easeIn);
      if (!skyMotionAllowed(dialogContext)) return FadeTransition(opacity: fade, child: child);
      final pop = CurvedAnimation(
        parent: animation,
        curve: const SkySpringCurve(SkyMotion.popSpring, seconds: 0.36),
        reverseCurve: Curves.easeIn,
      );
      return FadeTransition(
        opacity: fade,
        child: ScaleTransition(scale: Tween<double>(begin: 0.92, end: 1).animate(pop), child: child),
      );
    },
  );
}

class MemoryViewer extends StatefulWidget {
  const MemoryViewer({
    super.key,
    required this.memory,
    required this.visibleIds,
    this.photo,
    this.note = MemoriesCopy.noImage,
    this.meta = '',
  });

  final MemoryRecord memory;
  final ValueListenable<Set<String>> visibleIds;
  final Uint8List? photo;
  final String note;
  final String meta;

  @override
  State<MemoryViewer> createState() => _MemoryViewerState();
}

class _MemoryViewerState extends State<MemoryViewer> {
  bool _popped = false;
  bool _gone = false;
  bool _removing = false;
  String _error = '';

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
    if (_popped || widget.visibleIds.value.contains(widget.memory.id)) return;
    _gone = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _popped) return;
      final route = ModalRoute.of(context);
      if (route == null || route.isCurrent) _pop();
    });
  }

  void _pop() {
    if (_popped || !mounted) return;
    _popped = true;
    Navigator.of(context).pop();
  }

  Future<void> _remove() async {
    if (_removing) return;
    setState(() {
      _removing = true;
      _error = '';
    });
    final result = await confirmAndRemoveMemory(context, widget.memory);
    if (!mounted) return;
    if (result.removed || _gone) {
      _pop();
      return;
    }
    setState(() {
      _removing = false;
      _error = result.error ?? '';
    });
  }

  Widget _photo(double maxHeight) {
    final photo = widget.photo;
    if (photo == null) {
      return AspectRatio(aspectRatio: 4 / 5, child: PolaroidNoPhoto(text: widget.note));
    }
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight, minHeight: 120),
      child: ColoredBox(
        color: PolaroidColors.bed,
        child: Image.memory(
          photo,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          semanticLabel: MemoriesCopy.wholePhoto,
          errorBuilder: (context, error, stack) =>
              const AspectRatio(aspectRatio: 4 / 5, child: PolaroidNoPhoto(text: MemoriesCopy.noImage)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final width = math.min(media.size.width - 40, 440.0);
    final caption = calmCaption(widget.memory.caption);
    final paper = PolaroidPaper(
      photo: _photo(media.size.height * 0.56),
      captionText: caption,
      captionSize: 26,
      captionMaxLines: null,
      meta: widget.meta,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 2),
      radius: 8,
      photoRadius: 4,
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _pop,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(SkySpace.lg, SkySpace.sm, SkySpace.lg, SkySpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  SkyIconButton(icon: SkyIcons.close, semanticLabel: MemoriesCopy.close, onPressed: _pop),
                  const Spacer(),
                  SkyIconButton(
                    icon: SkyIcons.trash,
                    semanticLabel: MemoriesCopy.removeLabel,
                    iconColor: context.sky.rose,
                    onPressed: _removing ? null : _remove,
                  ),
                ],
              ),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(vertical: SkySpace.lg),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {},
                      child: SizedBox(width: width, child: paper),
                    ),
                  ),
                ),
              ),
              if (_error.isNotEmpty)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: SkyNotice(
                    text: _error,
                    tone: SkyNoticeTone.error,
                    elevated: true,
                    onDismiss: () => setState(() => _error = ''),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
