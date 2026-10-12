import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'screens/bucketlist/bucket_list.dart';
import 'screens/capsule/secret_capsule.dart';
import 'screens/love/love_tab.dart';
import 'screens/polaroids/polaroid_wall.dart';
import 'screens/roulette/date_roulette.dart';
import 'screens/sync/sync_hub.dart';
import 'theme/app_colors.dart';
import 'theme/app_motion.dart';
import 'theme/app_theme.dart';
import 'widgets/app_icons.dart';
import 'widgets/our_bottom_nav.dart';
import 'widgets/our_feedback.dart';
import 'widgets/our_header.dart';
import 'widgets/our_page.dart';
import 'widgets/tw_animations.dart';

enum AppTab { countdown, polaroids, roulette, capsule, bucketlist }

extension AppTabInfo on AppTab {
  String get id => name;

  String get label {
    switch (this) {
      case AppTab.countdown:
        return 'Love';
      case AppTab.polaroids:
        return 'Memories';
      case AppTab.roulette:
        return 'Dates';
      case AppTab.capsule:
        return 'Letters';
      case AppTab.bucketlist:
        return 'Bucket';
    }
  }

  OurNavItem get navItem {
    switch (this) {
      case AppTab.countdown:
        return OurNavItem(label: label, icon: AppIcons.heart);
      case AppTab.polaroids:
        return OurNavItem(label: label, icon: AppIcons.camera);
      case AppTab.roulette:
        return OurNavItem(label: label, icon: AppIcons.sparkles);
      case AppTab.capsule:
        return OurNavItem(label: label, icon: AppIcons.mail);
      case AppTab.bucketlist:
        return OurNavItem(label: label, icon: AppIcons.checkSquare);
    }
  }
}

typedef AppTabBuilder = Widget Function(BuildContext context, AppTab tab);

class ShellActions extends InheritedWidget {
  const ShellActions({super.key, this.onLock, this.onOpenSync, required super.child});

  final VoidCallback? onLock;
  final VoidCallback? onOpenSync;

  static ShellActions? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<ShellActions>();

  @override
  bool updateShouldNotify(ShellActions oldWidget) =>
      oldWidget.onLock != onLock || oldWidget.onOpenSync != onOpenSync;
}

Widget tabPage(BuildContext context, AppTab tab) {
  switch (tab) {
    case AppTab.countdown:
      return const LoveTab();
    case AppTab.polaroids:
      return const PolaroidWall();
    case AppTab.roulette:
      return const DateRoulette();
    case AppTab.capsule:
      return const SecretCapsule();
    case AppTab.bucketlist:
      return const BucketList();
  }
}

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    this.pageBuilder,
    this.header,
    this.onOpenSync,
    this.onLock,
    this.overlays = const [],
    this.initialTab = AppTab.countdown,
    this.onTabChanged,
    this.toastController,
    this.particles = true,
  });

  final AppTabBuilder? pageBuilder;
  final Widget? header;
  final VoidCallback? onOpenSync;
  final VoidCallback? onLock;
  final List<Widget> overlays;
  final AppTab initialTab;
  final ValueChanged<AppTab>? onTabChanged;
  final OurToastController? toastController;
  final bool particles;

  static const List<AppTab> tabs = AppTab.values;

  @override
  State<AppShell> createState() => AppShellState();
}

class AppShellState extends State<AppShell> {
  late AppTab _tab = widget.initialTab;
  double? _headerHeight;
  OurToastController? _ownToast;

  AppTab get tab => _tab;

  OurToastController get _toast => widget.toastController ?? (_ownToast ??= OurToastController());

  void selectTab(AppTab tab) {
    if (tab == _tab) return;
    setState(() => _tab = tab);
    widget.onTabChanged?.call(tab);
  }

  void _openSync() {
    final actions = ShellActions.maybeOf(context);
    final handler = widget.onOpenSync ?? actions?.onOpenSync;
    if (handler != null) {
      handler();
      return;
    }
    showSyncHub(context);
  }

  void _lock() {
    final handler = widget.onLock ?? ShellActions.maybeOf(context)?.onLock;
    handler?.call();
  }

  void _onHeaderSize(Size size) {
    if (_headerHeight == size.height) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _headerHeight != size.height) setState(() => _headerHeight = size.height);
    });
  }

  @override
  void dispose() {
    _ownToast?.dispose();
    super.dispose();
  }

  Widget _page(BuildContext context, AppTab tab) => (widget.pageBuilder ?? tabPage)(context, tab);

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final headerHeight = _headerHeight ?? (media.viewPadding.top + 57);
    final header = widget.header ?? OurHeader(onOpenSync: _openSync, onLock: _lock);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.systemOverlay,
      child: Scaffold(
        backgroundColor: AppColors.blush50,
        resizeToAvoidBottomInset: false,
        body: OurToastScope(
          controller: _toast,
          child: OurBackdrop(
            particles: widget.particles,
            scrollToken: _tab,
            child: Stack(
              fit: StackFit.expand,
              children: [
                MediaQuery(
                  data: media.copyWith(
                    padding: media.padding.copyWith(top: headerHeight, bottom: media.viewPadding.bottom),
                  ),
                  child: TabSwitcher(tab: _tab, builder: _page),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SizeReporter(onSize: _onHeaderSize, child: header),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: OurBottomNav(
                    items: [for (final t in AppShell.tabs) t.navItem],
                    selectedIndex: AppShell.tabs.indexOf(_tab),
                    onSelect: (i) => selectTab(AppShell.tabs[i]),
                  ),
                ),
                ...widget.overlays,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class TabSwitcher extends StatefulWidget {
  const TabSwitcher({super.key, required this.tab, required this.builder});

  final AppTab tab;
  final AppTabBuilder builder;

  @override
  State<TabSwitcher> createState() => _TabSwitcherState();
}

enum _Phase { idle, exiting, entering }

class _TabSwitcherState extends State<TabSwitcher> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: AppMotion.tabSwitch)
    ..addStatusListener(_onStatus);
  late AppTab _shown = widget.tab;
  _Phase _phase = _Phase.idle;

  @override
  void didUpdateWidget(covariant TabSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.tab == _shown && _phase == _Phase.idle) return;
    if (!motionAllowed(context)) {
      _controller.stop();
      _phase = _Phase.idle;
      _shown = widget.tab;
      return;
    }
    if (_phase != _Phase.exiting && widget.tab != _shown) {
      _phase = _Phase.exiting;
      _controller.forward(from: 0);
    }
  }

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    if (_phase == _Phase.exiting) {
      setState(() {
        _shown = widget.tab;
        _phase = _Phase.entering;
      });
      _controller.forward(from: 0);
    } else if (_phase == _Phase.entering) {
      if (widget.tab != _shown) {
        setState(() => _phase = _Phase.exiting);
        _controller.forward(from: 0);
      } else {
        setState(() => _phase = _Phase.idle);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final page = KeyedSubtree(key: ValueKey<AppTab>(_shown), child: Builder(builder: (c) => widget.builder(c, _shown)));
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = AppMotion.tabCurve.transform(_controller.value);
        double opacity = 1;
        double dy = 0;
        if (_phase == _Phase.exiting) {
          opacity = 1 - t;
          dy = -AppMotion.tabOffset * t;
        } else if (_phase == _Phase.entering) {
          opacity = t;
          dy = AppMotion.tabOffset * (1 - t);
        }
        return IgnorePointer(
          ignoring: _phase == _Phase.exiting,
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Transform.translate(offset: Offset(0, dy), child: child),
          ),
        );
      },
      child: page,
    );
  }
}

class SizeReporter extends SingleChildRenderObjectWidget {
  const SizeReporter({super.key, required this.onSize, super.child});

  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderSizeReporter(onSize);

  @override
  void updateRenderObject(BuildContext context, RenderSizeReporter renderObject) {
    renderObject.onSize = onSize;
  }
}

class RenderSizeReporter extends RenderProxyBox {
  RenderSizeReporter(this.onSize);

  ValueChanged<Size> onSize;
  Size? _last;

  @override
  void performLayout() {
    super.performLayout();
    if (_last != size) {
      _last = size;
      onSize(size);
    }
  }
}
