import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../core/engine.dart';
import '../../../sky/sky.dart';
import '../../../space_scope.dart';
import '../memories_copy.dart';
import '../memory_photos.dart';
import 'polaroid.dart';

typedef PolaroidOpen = void Function(MemoryRecord memory, Uint8List? photo, String note);

class PolaroidTile extends StatefulWidget {
  const PolaroidTile({
    super.key,
    required this.memory,
    this.meta = '',
    this.isNew = false,
    this.photos,
    this.onOpen,
    this.onRemove,
  });

  final MemoryRecord memory;
  final String meta;
  final bool isNew;
  final MemoryPhotoCache? photos;
  final PolaroidOpen? onOpen;
  final ValueChanged<MemoryRecord>? onRemove;

  static double tiltOf(MemoryRecord memory) => memory.rotationDegrees * math.pi / 180;

  @override
  State<PolaroidTile> createState() => _PolaroidTileState();
}

class _PolaroidTileState extends State<PolaroidTile> {
  Uint8List? _photo;
  bool _loading = true;
  String _error = '';
  int _token = 0;

  @override
  void initState() {
    super.initState();
    _start(widget.memory);
  }

  @override
  void didUpdateWidget(covariant PolaroidTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    final before = oldWidget.memory;
    final after = widget.memory;
    if (before.id != after.id || before.updatedAt != after.updatedAt || before.mime != after.mime) {
      _start(after);
    }
  }

  void _start(MemoryRecord memory) {
    final cached = widget.photos?.get(memory);
    if (cached != null) {
      _token++;
      _photo = cached;
      _loading = false;
      _error = '';
    } else if (!memory.hasPhoto) {
      _token++;
      _photo = null;
      _loading = false;
      _error = '';
    } else {
      _loading = true;
      _error = '';
      _load();
    }
  }

  Future<void> _load() async {
    final token = ++_token;
    final memory = widget.memory;
    final memories = context.space.memories;
    Uint8List? bytes;
    var error = '';
    try {
      bytes = await memories.loadPhoto(memory.id);
      if (bytes != null) widget.photos?.put(memory, bytes);
    } on RepositoryError catch (e) {
      error = e.message;
    } catch (_) {
      error = MemoriesCopy.photoLocked;
    }
    if (!mounted || token != _token) return;
    setState(() {
      _photo = error.isEmpty ? bytes : null;
      _error = error;
      _loading = false;
    });
  }

  void _open() {
    if (_loading) return;
    widget.onOpen?.call(widget.memory, _photo, _error.isEmpty ? MemoriesCopy.noImage : _error);
  }

  Widget _photoArea(String caption) {
    if (_loading) return const PolaroidDeveloping();
    final photo = _photo;
    if (photo == null) return PolaroidNoPhoto(text: _error.isEmpty ? MemoriesCopy.noImage : _error);
    return LayoutBuilder(
      builder: (context, constraints) {
        final ratio = MediaQuery.devicePixelRatioOf(context);
        final width = math.max(1, (constraints.maxWidth * ratio * 2).round());
        final height = math.max(1, (constraints.maxHeight * ratio * 2).round());
        return PolaroidImage(
          image: ResizeImage(
            MemoryImage(photo),
            width: width,
            height: height,
            policy: ResizeImagePolicy.fit,
            allowUpscaling: false,
          ),
          semanticLabel: caption,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final memory = widget.memory;
    final caption = calmCaption(memory.caption);
    final motion = skyMotionAllowed(context);
    final badge = AnimatedSwitcher(
      duration: motion ? SkyMotion.quick : Duration.zero,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(scale: Tween<double>(begin: 0.6, end: 1).animate(animation), child: child),
      ),
      child: widget.isNew ? const PolaroidNewBadge() : const SizedBox.shrink(),
    );
    final paper = PolaroidPaper(
      photo: AspectRatio(
        aspectRatio: 1 / PolaroidLook.ratioOf(memory.id),
        child: _photoArea(caption),
      ),
      captionText: caption,
      meta: widget.meta,
      pin: PolaroidLook.pinOf(memory.id),
      badge: badge,
    );
    final label = MemoriesCopy.meta([caption, widget.meta, if (widget.isNew) MemoriesCopy.newBadge]);
    return SkyPressable(
      onTap: widget.onOpen == null ? null : _open,
      onLongPress: widget.onRemove == null ? null : () => widget.onRemove!(memory),
      pressedScale: 0.97,
      semanticLabel: label,
      child: Transform.rotate(angle: PolaroidTile.tiltOf(memory), child: paper),
    );
  }
}
