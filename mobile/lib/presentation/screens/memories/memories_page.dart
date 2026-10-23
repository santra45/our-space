import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/engine.dart';
import '../../app_shell.dart';
import '../../sky/sky.dart';
import '../../space_scope.dart';
import 'add_memory_sheet.dart';
import 'memories_copy.dart';
import 'memory_marks.dart';
import 'memory_photos.dart';
import 'memory_viewer.dart';
import 'widgets/memory_wall.dart';
import 'widgets/polaroid.dart';
import 'widgets/polaroid_tile.dart';

typedef MemoriesWatcher = Stream<TableSnapshot<MemoryRecord>> Function(MemoriesRepository memories);

Stream<TableSnapshot<MemoryRecord>> watchMemories(MemoriesRepository memories) => memories.watch();

class MemoriesPage extends StatefulWidget {
  const MemoriesPage({super.key});

  static const Key addKey = ValueKey<String>('memories-add');

  static MemoriesWatcher watcher = watchMemories;

  @override
  State<MemoriesPage> createState() => _MemoriesPageState();
}

class _MemoriesPageState extends State<MemoriesPage> {
  StreamSubscription<TableSnapshot<MemoryRecord>>? _subscription;
  final ValueNotifier<Set<String>> _visibleIds = ValueNotifier<Set<String>>(<String>{});
  final MemoryPhotoCache _photos = MemoryPhotoCache();
  final ScrollController _scroll = ScrollController();
  late final MemoryMarks _marks;
  List<MemoryRecord> _items = const [];
  List<MemoryMonth> _months = const [];
  Map<String, int> _order = const {};
  int _unreadable = 0;
  String _error = '';
  bool _ready = false;
  bool _locked = false;
  bool _knowsPartner = true;
  String _partnerName = '';
  final Set<String> _fresh = <String>{};
  final Set<String> _entered = <String>{};
  ValueListenable<SkyTab>? _activeTab;

  bool get _onScreen => _activeTab == null || _activeTab!.value == SkyTab.memories;

  @override
  void initState() {
    super.initState();
    _marks = MemoryMarks.of(context.space.store.settings);
    _marks.addListener(_onMarks);
    _listen();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active = SkyShellScope.activeTabOf(context);
    if (identical(active, _activeTab)) return;
    _activeTab?.removeListener(_onActiveTab);
    _activeTab = active?..addListener(_onActiveTab);
  }

  void _onActiveTab() {
    if (!mounted) return;
    if (_onScreen) {
      if (_locked || _error.isNotEmpty) {
        _listen();
        return;
      }
      setState(_noteFresh);
    } else if (_fresh.isNotEmpty) {
      setState(_fresh.clear);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _activeTab?.removeListener(_onActiveTab);
    _marks.removeListener(_onMarks);
    _visibleIds.dispose();
    _scroll.dispose();
    _photos.clear();
    super.dispose();
  }

  void _listen() {
    unawaited(_subscription?.cancel());
    _subscription = MemoriesPage.watcher(context.space.memories).listen(_onSnapshot, onError: _onError);
  }

  void _retry() {
    setState(() {
      _error = '';
      _ready = false;
    });
    _listen();
  }

  void _onSnapshot(TableSnapshot<MemoryRecord> snapshot) {
    if (!mounted) return;
    final unlocked = snapshot.unlocked;
    final items = unlocked ? snapshot.items : const <MemoryRecord>[];
    if (!unlocked) _photos.clear();
    if (unlocked) _marks.start();
    setState(() {
      _items = items;
      _months = groupMemoriesByMonth(items);
      _order = {for (var i = 0; i < items.length; i++) items[i].id: i};
      _unreadable = unlocked ? snapshot.unreadable : 0;
      _error = '';
      _ready = true;
      _locked = !unlocked;
      _noteFresh();
    });
    _visibleIds.value = {for (final item in items) item.id};
  }

  void _onError(Object error, StackTrace stack) {
    if (!mounted) return;
    setState(() {
      _items = const [];
      _months = const [];
      _order = const {};
      _unreadable = 0;
      _error = MemoriesCopy.wallError;
      _ready = true;
      _locked = false;
    });
    _visibleIds.value = <String>{};
  }

  void _onMarks() {
    if (!mounted) return;
    setState(_noteFresh);
  }

  void _noteFresh() {
    _fresh.retainWhere(_order.containsKey);
    if (!_onScreen) return;
    final arrivals = [
      for (final memory in _items)
        if (_marks.isNew(memory.id)) memory.id,
    ];
    if (arrivals.isEmpty) return;
    _fresh.addAll(arrivals);
    _marks.markSeen(arrivals);
  }

  String _metaFor(MemoryRecord memory, {bool full = false}) {
    final day = memoryDay(memory);
    final date = day == null ? null : (full ? MemoriesCopy.fullDay(day) : MemoriesCopy.day(day));
    final author = switch (_marks.authorOf(memory.id, knowsPartner: _knowsPartner)) {
      MemoryAuthor.me => MemoriesCopy.byYou,
      MemoryAuthor.partner => _partnerName.isEmpty ? null : MemoriesCopy.byPartner(_partnerName),
      MemoryAuthor.unknown => null,
    };
    return MemoriesCopy.meta([date, author]);
  }

  Future<void> _openAdd() async {
    final added = await showAddMemorySheet(context);
    if (!added || !mounted || !_scroll.hasClients || _scroll.offset <= 0) return;
    if (skyMotionAllowed(context)) {
      await _scroll.animateTo(0, duration: SkyMotion.slow, curve: SkyMotion.standard);
    } else {
      _scroll.jumpTo(0);
    }
  }

  void _open(MemoryRecord memory, Uint8List? photo, String note) {
    if (_fresh.remove(memory.id)) setState(() {});
    unawaited(
      showMemoryViewer(
        context,
        memory: memory,
        visibleIds: _visibleIds,
        photo: photo,
        note: note,
        meta: _metaFor(memory, full: true),
      ),
    );
  }

  Future<void> _remove(MemoryRecord memory) async {
    final result = await confirmAndRemoveMemory(context, memory);
    if (!mounted) return;
    final error = result.error;
    if (error != null) SkyToast.show(context, error);
  }

  Widget _tile(BuildContext context, MemoryRecord memory) {
    final first = _entered.add(memory.id);
    final order = _order[memory.id] ?? 0;
    return SkyEntrance(
      key: ValueKey<String>('enter-${memory.id}'),
      index: first && order < 8 ? order + 2 : 0,
      duration: first ? SkyMotion.medium : Duration.zero,
      offset: const Offset(0, 18),
      child: PolaroidTile(
        key: ValueKey<String>(memory.id),
        memory: memory,
        meta: _metaFor(memory),
        isNew: _fresh.contains(memory.id),
        photos: _photos,
        onOpen: _open,
        onRemove: _remove,
      ),
    );
  }

  Widget _topBar() {
    final kicker = !_ready
        ? MemoriesCopy.opening
        : (_locked ? MemoriesCopy.kickerEmpty : MemoriesCopy.kicker(_items.length));
    return SkyEntrance(
      child: SkyTopBar(
        kicker: kicker,
        title: MemoriesCopy.title,
        trailing: SkyIconButton(
          key: MemoriesPage.addKey,
          icon: SkyIcons.camera,
          tone: SkyIconButtonTone.rose,
          semanticLabel: MemoriesCopy.addLabel,
          onPressed: _locked ? null : _openAdd,
        ),
      ),
    );
  }

  Widget? _notice() {
    if (_error.isNotEmpty) {
      return SkyNotice(
        text: _error,
        tone: SkyNoticeTone.error,
        actionLabel: MemoriesCopy.retry,
        onAction: _retry,
      );
    }
    if (_unreadable > 0) {
      return SkyNotice(text: MemoriesCopy.hidden(_unreadable), tone: SkyNoticeTone.warning, icon: SkyIcons.lock);
    }
    return null;
  }

  List<Widget> _body(double contentWidth) {
    if (!_ready) return const [SliverToBoxAdapter(child: _DevelopingWall())];
    if (_locked) {
      return const [
        SliverToBoxAdapter(
          child: SkyEntrance(
            index: 1,
            child: Padding(
              padding: EdgeInsets.only(top: SkySpace.xxl),
              child: SkyEmptyState(
                icon: SkyIcons.lock,
                title: MemoriesCopy.lockedTitle,
                message: MemoriesCopy.lockedMessage,
              ),
            ),
          ),
        ),
      ];
    }
    if (_error.isNotEmpty) return const [];
    if (_items.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: SkyEntrance(index: 1, child: _EmptyWall(partnerName: _partnerName, onAdd: _openAdd)),
        ),
      ];
    }
    return memoryWallSlivers(months: _months, contentWidth: contentWidth, tileBuilder: _tile);
  }

  @override
  Widget build(BuildContext context) {
    _partnerName = context.select<IdentityController, String>((identity) => identity.partnerName);
    _knowsPartner = context.select<IdentityController, bool>((identity) => (identity.me?.deviceIds.length ?? 0) <= 1);
    final notice = _notice();
    return SkyScaffold(
      showSky: false,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final content = math.min(width, SkySizes.maxContentWidth);
          final side = math.max(0.0, (width - content) / 2);
          final bottom = SkyScrollScaffold.bottomInsetOf(context);
          return Stack(
            fit: StackFit.expand,
            children: [
              _ParallaxSky(controller: _scroll),
              CustomScrollView(
                controller: _scroll,
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(side, 0, side, bottom),
                    sliver: SliverMainAxisGroup(
                      slivers: [
                        SliverToBoxAdapter(child: _topBar()),
                        if (notice != null)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(SkySpace.gutter, SkySpace.lg, SkySpace.gutter, 0),
                              child: SkyEntrance(index: 1, child: notice),
                            ),
                          ),
                        ..._body(content),
                      ],
                    ),
                  ),
                ],
              ),
              _TopScrim(controller: _scroll),
            ],
          );
        },
      ),
    );
  }
}

class _ParallaxSky extends StatelessWidget {
  const _ParallaxSky({required this.controller});

  final ScrollController controller;

  static const double height = SkySizes.skyHeight;

  @override
  Widget build(BuildContext context) {
    final factor = skyMotionAllowed(context) ? 0.6 : 1.0;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: height,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, child) {
          final offset = controller.hasClients ? controller.offset : 0.0;
          final shift = math.min(height, math.max(0.0, offset) * factor);
          return TickerMode(
            enabled: shift < height,
            child: Transform.translate(offset: Offset(0, -shift), child: child),
          );
        },
        child: const SkyBackdrop(scene: SkyScene.page, fade: true),
      ),
    );
  }
}

class _TopScrim extends StatelessWidget {
  const _TopScrim({required this.controller});

  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    final page = context.sky.page;
    final top = MediaQuery.viewPaddingOf(context).top;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: top + SkySpace.md,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, child) {
            final offset = controller.hasClients ? controller.offset : 0.0;
            final opacity = (offset / 48).clamp(0.0, 1.0);
            if (opacity <= 0) return const SizedBox.shrink();
            return Opacity(opacity: opacity, child: child);
          },
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [page.withValues(alpha: 0.94), page.withValues(alpha: 0)],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DevelopingWall extends StatelessWidget {
  const _DevelopingWall();

  @override
  Widget build(BuildContext context) {
    Widget blank(double ratio, double degrees, PolaroidPin pin) {
      return Transform.rotate(
        angle: degrees * math.pi / 180,
        child: PolaroidPaper(
          photo: AspectRatio(aspectRatio: 1 / ratio, child: const PolaroidDeveloping()),
          captionText: '',
          pin: pin,
        ),
      );
    }

    return Semantics(
      label: MemoriesCopy.opening,
      container: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          MemoryWallMetrics.side,
          SkySpace.xxl + MemoryWallMetrics.top,
          MemoryWallMetrics.side,
          0,
        ),
        child: SkyEntrance(
          index: 1,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: blank(1.30, -1.6, PolaroidPin.tape)),
              const SizedBox(width: MemoryWallMetrics.gap),
              Expanded(child: blank(1.10, 1.8, PolaroidPin.pin)),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyWall extends StatelessWidget {
  const _EmptyWall({required this.partnerName, required this.onAdd});

  final String partnerName;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    return Padding(
      padding: const EdgeInsets.fromLTRB(SkySpace.gutter + 8, SkySpace.sectionGap + 14, SkySpace.gutter + 8, 0),
      child: Column(
        children: [
          Transform.rotate(
            angle: -3 * math.pi / 180,
            child: SizedBox(
              width: 172,
              child: PolaroidPaper(
                pin: PolaroidPin.tape,
                photo: AspectRatio(
                  aspectRatio: 4 / 5,
                  child: CustomPaint(
                    painter: const PolaroidDashedFrame(),
                    child: ColoredBox(
                      color: PolaroidColors.bed.withValues(alpha: 0.6),
                      child: Center(
                        child: SkyPulse(
                          minScale: 0.92,
                          maxScale: 1.06,
                          child: SkyIcon(SkyIcons.camera, size: 28, color: t.roseDeep.withValues(alpha: 0.75)),
                        ),
                      ),
                    ),
                  ),
                ),
                captionText: MemoriesCopy.emptyCaption,
                meta: MemoriesCopy.day(DateTime.now()),
              ),
            ),
          ),
          const SizedBox(height: SkySpace.xxl + 4),
          Semantics(
            header: true,
            child: Text(
              MemoriesCopy.emptyTitle,
              textAlign: TextAlign.center,
              style: SkyType.headline.copyWith(color: t.text),
            ),
          ),
          const SizedBox(height: SkySpace.sm),
          Text(
            MemoriesCopy.emptyMessage(partnerName),
            textAlign: TextAlign.center,
            style: SkyType.bodySmall.copyWith(color: t.muted),
          ),
          const SizedBox(height: SkySpace.xl),
          SkyButton(
            label: MemoriesCopy.createFirst,
            icon: SkyIcons.camera,
            expand: false,
            onPressed: onAdd,
          ),
        ],
      ),
    );
  }
}
