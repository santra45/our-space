import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../../../core/engine.dart';
import '../../space_scope.dart';
import '../../widgets/our_widgets.dart';
import 'memories_copy.dart';

class PolaroidPhotoCache {
  PolaroidPhotoCache({this.capacity = 24});

  final int capacity;
  final LinkedHashMap<String, Uint8List> _entries = LinkedHashMap<String, Uint8List>();

  static String keyOf(MemoryRecord memory) => '${memory.id}|${memory.updatedAt}|${memory.mime ?? ''}';

  Uint8List? get(MemoryRecord memory) {
    final key = keyOf(memory);
    final hit = _entries.remove(key);
    if (hit != null) _entries[key] = hit;
    return hit;
  }

  void put(MemoryRecord memory, Uint8List bytes) {
    final key = keyOf(memory);
    _entries.remove(key);
    _entries[key] = bytes;
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
    }
  }

  void clear() => _entries.clear();
}

typedef PolaroidSelect = void Function(MemoryRecord memory, Uint8List photo);

class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child, this.pressedScale = 0.97});

  final Widget child;
  final double pressedScale;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> with SingleTickerProviderStateMixin {
  late final AnimationController _scale = AnimationController.unbounded(vsync: this, value: 1);

  void _to(double target) {
    if (!motionAllowed(context)) {
      _scale.value = 1;
      return;
    }
    _scale.animateWith(SpringSimulation(AppMotion.framerScaleSpring, _scale.value, target, _scale.velocity));
  }

  @override
  void dispose() {
    _scale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _to(widget.pressedScale),
      onPointerUp: (_) => _to(1),
      onPointerCancel: (_) => _to(1),
      child: AnimatedBuilder(
        animation: _scale,
        builder: (context, child) => Transform.scale(scale: _scale.value, child: child),
        child: widget.child,
      ),
    );
  }
}

class PolaroidCard extends StatefulWidget {
  const PolaroidCard({
    super.key,
    required this.memory,
    this.onSelect,
    this.photos,
    this.decodeWidth,
    this.decodeHeight,
  });

  final MemoryRecord memory;
  final PolaroidSelect? onSelect;
  final PolaroidPhotoCache? photos;
  final int? decodeWidth;
  final int? decodeHeight;

  static double rotationRadians(MemoryRecord memory) => memory.rotationDegrees * math.pi / 180;

  @override
  State<PolaroidCard> createState() => _PolaroidCardState();
}

class _PolaroidCardState extends State<PolaroidCard> {
  Uint8List? _photo;
  bool _loading = true;
  String _error = '';
  bool _deleting = false;
  bool _deletePressed = false;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    final cached = widget.photos?.get(widget.memory);
    if (cached != null) {
      _photo = cached;
      _loading = false;
    } else if (!widget.memory.hasPhoto) {
      _loading = false;
    } else {
      _load();
    }
  }

  @override
  void didUpdateWidget(covariant PolaroidCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final before = oldWidget.memory;
    final after = widget.memory;
    if (before.id != after.id || before.updatedAt != after.updatedAt || before.mime != after.mime) {
      final cached = widget.photos?.get(after);
      if (cached != null) {
        _token++;
        _photo = cached;
        _loading = false;
        _error = '';
      } else if (!after.hasPhoto) {
        _token++;
        _photo = null;
        _loading = false;
      } else {
        _loading = true;
        _error = '';
        _load();
      }
    }
  }

  Future<void> _load() async {
    final token = ++_token;
    final memory = widget.memory;
    final memories = context.space.memories;
    Uint8List? bytes;
    String error = '';
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

  Future<void> _delete() async {
    if (_deleting) return;
    final confirmed = await showOurConfirm(context, message: MemoriesCopy.deleteConfirm);
    if (!confirmed || !mounted) return;
    AppHaptics.tap();
    setState(() {
      _deleting = true;
      _error = '';
    });
    try {
      final tombstone = await context.space.memories.delete(widget.memory.id);
      if (!mounted) return;
      if (tombstone == null) {
        setState(() {
          _deleting = false;
          _error = MemoriesCopy.alreadyRemoved;
        });
      }
    } on RepositoryError catch (e) {
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _error = MemoriesCopy.deleteFailedWith(e.message);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _error = MemoriesCopy.deleteFailed;
      });
    }
  }

  void _select() {
    AppHaptics.tap();
    final photo = _photo;
    if (widget.onSelect != null && photo != null) widget.onSelect!(widget.memory, photo);
  }

  Widget _placeholder(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LucideIcon(AppIcons.imageOff, size: 20, color: AppColors.slate300),
            const SizedBox(height: 6),
            Text(text, textAlign: TextAlign.center, style: Tw.px10.tight.c(AppColors.slate400)),
          ],
        ),
      ),
    );
  }

  Widget _photoArea(String caption) {
    final Widget content;
    if (_loading) {
      content = const Center(child: OurPulseText(MemoriesCopy.developing));
    } else if (_photo != null) {
      final provider = MemoryImage(_photo!);
      final ImageProvider<Object> image;
      if (widget.decodeWidth != null && widget.decodeHeight != null) {
        image = ResizeImage(
          provider,
          width: widget.decodeWidth,
          height: widget.decodeHeight,
          policy: ResizeImagePolicy.fit,
          allowUpscaling: false,
        );
      } else {
        image = provider;
      }
      content = Image(
        image: image,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        gaplessPlayback: true,
        semanticLabel: caption.isEmpty ? MemoriesCopy.photoAlt : caption,
        errorBuilder: (context, error, stack) => _placeholder(MemoriesCopy.noImage),
      );
    } else {
      content = _placeholder(_error.isEmpty ? MemoriesCopy.noImage : _error);
    }

    return AspectRatio(
      aspectRatio: 4 / 5,
      child: CssBox(
        color: AppColors.blush50,
        border: Border.all(color: AppColors.slate100.withValues(alpha: 0.8)),
        borderRadius: AppRadii.all(AppRadii.xl),
        clipContent: true,
        child: Stack(
          fit: StackFit.expand,
          children: [
            content,
            Positioned(top: 8, right: 8, child: _deleteButton()),
          ],
        ),
      ),
    );
  }

  Widget _deleteButton() {
    final enabled = !_deleting;
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: MemoriesCopy.deleteLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _deletePressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _deletePressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _deletePressed = false) : null,
        onTap: enabled ? _delete : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: CssBox(
            width: 28,
            height: 28,
            color: _deletePressed ? AppColors.rose500 : AppColors.black.withValues(alpha: 0.4),
            backdropBlur: 4,
            borderRadius: AppRadii.all(AppRadii.full),
            child: const Center(child: LucideIcon(AppIcons.trash2, size: 14, color: AppColors.white)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final memory = widget.memory;
    final caption = memory.caption;

    final card = CssBox(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
      color: AppColors.white,
      border: Border.all(color: AppColors.slate100),
      borderRadius: AppRadii.all(AppRadii.x2l),
      shadows: AppShadows.polaroid,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _photoArea(caption),
          if (_error.isNotEmpty && _photo != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Semantics(
                liveRegion: true,
                child: Text(_error, textAlign: TextAlign.center, style: Tw.px10.tight.c(AppColors.rose600)),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 12, left: 4, right: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  caption.isEmpty ? MemoriesCopy.specialMoment : caption,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Tw.xl.handwriting.tight.c(AppColors.slate800),
                ),
                const SizedBox(height: 2),
                Text(
                  formatDatePretty(memory.date),
                  textAlign: TextAlign.center,
                  style: Tw.px10.mono.c(AppColors.slate400),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return PressScale(
      child: Transform.rotate(
        angle: PolaroidCard.rotationRadians(memory),
        child: Semantics(
          button: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _select,
            child: Stack(
              fit: StackFit.passthrough,
              clipBehavior: Clip.none,
              children: [
                card,
                const Positioned(top: -11, left: 0, right: 0, child: Center(child: WashiTape())),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
