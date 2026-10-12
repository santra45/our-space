import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/engine.dart';
import '../../space_scope.dart';
import '../../widgets/our_widgets.dart';
import 'add_memory_modal.dart';
import 'memories_copy.dart';
import 'polaroid_card.dart';
import 'polaroid_preview.dart';

class PolaroidWall extends StatefulWidget {
  const PolaroidWall({super.key});

  static const double gridGap = 16;
  static const double gridTop = 8;

  @override
  State<PolaroidWall> createState() => _PolaroidWallState();
}

class _PolaroidWallState extends State<PolaroidWall> {
  StreamSubscription<TableSnapshot<MemoryRecord>>? _subscription;
  final ValueNotifier<Set<String>> _visibleIds = ValueNotifier<Set<String>>(<String>{});
  final PolaroidPhotoCache _photos = PolaroidPhotoCache();
  List<MemoryRecord> _items = const [];
  int _unreadable = 0;
  String _error = '';
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _subscription = context.space.memories.watch().listen(_onSnapshot, onError: _onError);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _visibleIds.dispose();
    _photos.clear();
    super.dispose();
  }

  void _onSnapshot(TableSnapshot<MemoryRecord> snapshot) {
    if (!mounted) return;
    final items = snapshot.unlocked ? snapshot.items : const <MemoryRecord>[];
    if (!snapshot.unlocked) _photos.clear();
    setState(() {
      _items = items;
      _unreadable = snapshot.unlocked ? snapshot.unreadable : 0;
      _error = '';
      _ready = true;
    });
    _visibleIds.value = {for (final item in items) item.id};
  }

  void _onError(Object error, StackTrace stack) {
    if (!mounted) return;
    setState(() {
      _items = const [];
      _unreadable = 0;
      _error = MemoriesCopy.wallError;
      _ready = true;
    });
    _visibleIds.value = <String>{};
  }

  void _openAdd() {
    showAddMemoryModal(context);
  }

  void _select(MemoryRecord memory, Uint8List photo) {
    showPolaroidPreview(
      context,
      memoryId: memory.id,
      photo: photo,
      caption: memory.caption,
      visibleIds: _visibleIds,
    );
  }

  Widget _header(bool loading) {
    return OurSectionHeader(
      title: MemoriesCopy.title,
      subtitle: loading ? MemoriesCopy.opening : MemoriesCopy.preserved(_items.length),
      trailing: BouncyButton(
        onPressed: () {
          AppHaptics.tap();
          _openAdd();
        },
        icon: AppIcons.plus,
        label: MemoriesCopy.snapMemory,
        small: true,
        pill: true,
      ),
    );
  }

  Widget _notice() {
    return OurNotice(
      tone: NoticeTone.warning,
      message: _error.isNotEmpty ? _error : MemoriesCopy.hidden(_unreadable),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      textStyle: Tw.px11.relaxed,
    );
  }

  Widget _skeletons() {
    return const Padding(
      padding: EdgeInsets.only(top: PolaroidWall.gridTop),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: OurSkeleton(aspectRatio: 3 / 4, radius: AppRadii.x2l)),
          SizedBox(width: PolaroidWall.gridGap),
          Expanded(child: OurSkeleton(aspectRatio: 3 / 4, radius: AppRadii.x2l)),
        ],
      ),
    );
  }

  Widget _empty(String partnerName) {
    return OurEmptyState(
      icon: AppIcons.camera,
      title: MemoriesCopy.emptyTitle,
      message: MemoriesCopy.emptyMessage(partnerName),
      action: BouncyButton(
        onPressed: _openAdd,
        label: MemoriesCopy.createFirst,
        small: true,
        pill: true,
      ),
    );
  }

  Widget _row(int index, int decodeWidth, int decodeHeight) {
    final first = _items[index * 2];
    final second = index * 2 + 1 < _items.length ? _items[index * 2 + 1] : null;
    Widget cell(MemoryRecord memory) => Expanded(
          key: ValueKey<String>(memory.id),
          child: PolaroidCard(
            memory: memory,
            onSelect: _select,
            photos: _photos,
            decodeWidth: decodeWidth,
            decodeHeight: decodeHeight,
          ),
        );
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          cell(first),
          const SizedBox(width: PolaroidWall.gridGap),
          if (second == null) const Expanded(child: SizedBox.shrink()) else cell(second),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final partnerName = context.select<IdentityController, String>((identity) => identity.partnerName);
    final loading = !_ready;
    final ratio = MediaQuery.devicePixelRatioOf(context);

    final leading = <Widget>[
      _header(loading),
      if (_error.isNotEmpty || _unreadable > 0) _notice(),
      if (loading) _skeletons() else if (_items.isEmpty) _empty(partnerName),
    ];
    final rows = loading ? 0 : (_items.length + 1) ~/ 2;

    return LayoutBuilder(
      builder: (context, constraints) {
        final padding = OurPage.paddingOf(context);
        final contentWidth = math.max(
          0.0,
          math.min(constraints.maxWidth - padding.horizontal, AppLayout.maxWidthMd),
        );
        final side = (constraints.maxWidth - contentWidth) / 2;
        final columnWidth = math.max(0.0, (contentWidth - PolaroidWall.gridGap) / 2);
        final photoWidth = math.max(1.0, columnWidth - 28);
        final decodeWidth = (photoWidth * ratio * 2).round();
        final decodeHeight = (photoWidth * 1.25 * ratio * 2).round();

        return CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(side, padding.top, side, padding.bottom),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index < leading.length) {
                      return Padding(
                        padding: EdgeInsets.only(top: index == 0 ? 0 : 16),
                        child: leading[index],
                      );
                    }
                    final row = index - leading.length;
                    return Padding(
                      padding: EdgeInsets.only(top: row == 0 ? 16 + PolaroidWall.gridTop : PolaroidWall.gridGap),
                      child: _row(row, decodeWidth, decodeHeight),
                    );
                  },
                  childCount: leading.length + rows,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
