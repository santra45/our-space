import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'screens/letters/letters_page.dart';
import 'screens/love/love_sheet.dart';
import 'screens/memories/memories_page.dart';
import 'screens/settings/settings_page.dart';
import 'screens/sky/sky_page.dart';
import 'screens/us/us_page.dart';
import 'sky/sky.dart';
import 'widgets/confetti_burst.dart';

enum SkyTab { sky, letters, memories, us }

extension SkyTabInfo on SkyTab {
  String get id => name;

  String get label {
    switch (this) {
      case SkyTab.sky:
        return 'Sky';
      case SkyTab.letters:
        return 'Letters';
      case SkyTab.memories:
        return 'Memories';
      case SkyTab.us:
        return 'Us';
    }
  }

  SkyIcons get icon {
    switch (this) {
      case SkyTab.sky:
        return SkyIcons.star;
      case SkyTab.letters:
        return SkyIcons.letter;
      case SkyTab.memories:
        return SkyIcons.photo;
      case SkyTab.us:
        return SkyIcons.us;
    }
  }

  SkyDockItem get dockItem => SkyDockItem(label: label, icon: icon);
}

typedef SkyTabBuilder = Widget Function(BuildContext context, SkyTab tab);

Widget skyTabPage(BuildContext context, SkyTab tab) {
  switch (tab) {
    case SkyTab.sky:
      return const OurSkyPage();
    case SkyTab.letters:
      return const LettersPage();
    case SkyTab.memories:
      return const MemoriesPage();
    case SkyTab.us:
      return const UsPage();
  }
}

Future<void> openSettings(BuildContext context) {
  return Navigator.of(context).push<void>(
    SkyPageRoute<void>(
      builder: (_) => const SettingsPage(),
      settings: const RouteSettings(name: SettingsPage.routeName),
    ),
  );
}

abstract final class ShellKeys {
  static const Key dock = ValueKey<String>('shell-dock');
  static const Key avatar = ValueKey<String>('shell-avatar');
  static const Key notices = ValueKey<String>('shell-notices');
  static const Key lockNow = ValueKey<String>('shell-lock-now');
  static const Key skyFollowsTime = ValueKey<String>('shell-sky-follows-time');
}

abstract final class ShellCopy {
  static const String settings = 'Settings';
  static const String openSettings = 'Open settings';
  static const String dismiss = 'Dismiss';
  static const String sendLove = 'Send love';
  static const String hereNow = 'here now';
  static const String justUs = 'Just the two of you';
  static String when(String lastSeen) {
    if (lastSeen == 'Just now' || lastSeen == 'Yesterday') return lastSeen.toLowerCase();
    if (lastSeen.endsWith(' ago')) return lastSeen;
    return 'on $lastSeen';
  }

  static String seen(String lastSeen) => 'seen ${when(lastSeen)}';
}

class ShellActions extends InheritedWidget {
  const ShellActions({super.key, this.onLock, required super.child});

  final VoidCallback? onLock;

  static ShellActions? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<ShellActions>();

  @override
  bool updateShouldNotify(ShellActions oldWidget) => oldWidget.onLock != onLock;
}

enum PresenceKind { here, seen, unknown }

@immutable
class PartnerPresence {
  const PartnerPresence.here({this.partnerName}) : kind = PresenceKind.here, lastSeen = null;

  const PartnerPresence.seen({this.partnerName, required String this.lastSeen}) : kind = PresenceKind.seen;

  const PartnerPresence.unknown({this.partnerName}) : kind = PresenceKind.unknown, lastSeen = null;

  final PresenceKind kind;
  final String? partnerName;
  final String? lastSeen;

  bool get isHere => kind == PresenceKind.here;

  bool get _named => partnerName != null && partnerName!.trim().isNotEmpty;

  String? get label {
    switch (kind) {
      case PresenceKind.here:
        return ShellCopy.hereNow;
      case PresenceKind.seen:
        return ShellCopy.seen(lastSeen!);
      case PresenceKind.unknown:
        return null;
    }
  }

  String get sentence {
    switch (kind) {
      case PresenceKind.here:
        return _named ? '$partnerName is here now' : 'You are both here';
      case PresenceKind.seen:
        return _named
            ? '$partnerName was here ${ShellCopy.when(lastSeen!)}'
            : 'Here together ${ShellCopy.when(lastSeen!)}';
      case PresenceKind.unknown:
        return ShellCopy.justUs;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is PartnerPresence && other.kind == kind && other.partnerName == partnerName && other.lastSeen == lastSeen;

  @override
  int get hashCode => Object.hash(kind, partnerName, lastSeen);
}

@immutable
class ShellStatus {
  const ShellStatus({this.errorText, this.onDismissError, this.warningText});

  final String? errorText;
  final VoidCallback? onDismissError;
  final String? warningText;

  bool get isEmpty => errorText == null && warningText == null;
}

class SkyShellScope extends InheritedWidget {
  const SkyShellScope({
    super.key,
    required this.tab,
    required this.activeTab,
    required this.selectTab,
    required this.openSettings,
    required this.openLove,
    required this.lock,
    required this.presence,
    this.myName,
    this.partnerName,
    required super.child,
  });

  final SkyTab tab;
  final ValueListenable<SkyTab> activeTab;
  final ValueChanged<SkyTab> selectTab;
  final VoidCallback openSettings;
  final VoidCallback openLove;
  final VoidCallback lock;
  final PartnerPresence presence;
  final String? myName;
  final String? partnerName;

  static SkyShellScope? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<SkyShellScope>();

  static ValueListenable<SkyTab>? activeTabOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<SkyShellScope>()?.activeTab;

  static SkyShellScope of(BuildContext context) {
    final scope = maybeOf(context);
    assert(scope != null, 'No SkyShellScope above this context.');
    return scope!;
  }

  @override
  bool updateShouldNotify(SkyShellScope oldWidget) =>
      oldWidget.activeTab != activeTab ||
      oldWidget.presence != presence ||
      oldWidget.myName != myName ||
      oldWidget.partnerName != partnerName ||
      oldWidget.selectTab != selectTab ||
      oldWidget.openSettings != openSettings ||
      oldWidget.openLove != openLove ||
      oldWidget.lock != lock;
}

class ShellAvatar extends StatelessWidget {
  const ShellAvatar({super.key, this.size = SkySizes.avatar});

  final double size;

  @override
  Widget build(BuildContext context) {
    final scope = SkyShellScope.maybeOf(context);
    return SkyAvatar(
      key: ShellKeys.avatar,
      initial: SkyAvatar.initialOf(scope?.myName, fallback: 'O'),
      size: size,
      semanticLabel: ShellCopy.settings,
      onTap: () {
        if (scope != null) {
          scope.openSettings();
        } else {
          unawaited(openSettings(context));
        }
      },
    );
  }
}

class SkyShell extends StatefulWidget {
  const SkyShell({
    super.key,
    this.pageBuilder,
    this.initialTab = SkyTab.sky,
    this.onTabChanged,
    this.onOpenSettings,
    this.onOpenLove,
    this.onLock,
    this.toastController,
    this.presence = const PartnerPresence.unknown(),
    this.status = const ShellStatus(),
    this.myName,
    this.partnerName,
    this.overlays = const [],
  });

  final SkyTabBuilder? pageBuilder;
  final SkyTab initialTab;
  final ValueChanged<SkyTab>? onTabChanged;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onOpenLove;
  final VoidCallback? onLock;
  final SkyToastController? toastController;
  final PartnerPresence presence;
  final ShellStatus status;
  final String? myName;
  final String? partnerName;
  final List<Widget> overlays;

  static const List<SkyTab> tabs = SkyTab.values;

  static bool warmTabs = true;

  static const List<SkyTab> warmOrder = [SkyTab.letters, SkyTab.us, SkyTab.memories];

  @override
  State<SkyShell> createState() => SkyShellState();
}

class SkyShellState extends State<SkyShell> with SingleTickerProviderStateMixin {
  late SkyTab _tab = widget.initialTab;
  SkyTab? _leaving;
  late final Set<SkyTab> _visited = {widget.initialTab};
  late final ValueNotifier<SkyTab> _active = ValueNotifier<SkyTab>(widget.initialTab);
  late final AnimationController _swap = AnimationController(vsync: this, duration: SkyMotion.tabSwap, value: 1)
    ..addStatusListener(_onSwap);
  late final Animation<double> _fadeIn = CurvedAnimation(parent: _swap, curve: SkyMotion.standard);
  late final Animation<double> _fadeOut = ReverseAnimation(_fadeIn);
  Timer? _warm;
  bool _calm = true;
  SkyToastController? _ownToast;

  SkyTab get tab => _tab;

  SkyToastController get _toast => widget.toastController ?? (_ownToast ??= SkyToastController());

  @override
  void initState() {
    super.initState();
    if (!SkyShell.warmTabs) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _warmLater(SkyMotion.tabWarmDelay));
  }

  bool get _busy => _swap.isAnimating || ConfettiBurst.activeController != null;

  void _warmLater(Duration delay) {
    _warm?.cancel();
    _warm = Timer(delay, () {
      if (!mounted) return;
      if (_busy) {
        _calm = false;
        _warmLater(SkyMotion.tabWarmRetry);
        return;
      }
      if (!_calm) {
        _calm = true;
        _warmLater(SkyMotion.tabWarmRetry);
        return;
      }
      for (final next in SkyShell.warmOrder) {
        if (_visited.contains(next)) continue;
        setState(() => _visited.add(next));
        _warmLater(SkyMotion.tabWarmStep);
        return;
      }
    });
  }

  void _onSwap(AnimationStatus status) {
    if (status == AnimationStatus.completed && _leaving != null && mounted) {
      setState(() => _leaving = null);
    }
  }

  void selectTab(SkyTab tab) {
    if (tab == _tab) return;
    final motion = skyMotionAllowed(context);
    setState(() {
      _leaving = motion ? _tab : null;
      _tab = tab;
      _visited.add(tab);
    });
    _active.value = tab;
    if (motion) {
      _swap.forward(from: 0);
    } else {
      _swap.value = 1;
    }
    widget.onTabChanged?.call(tab);
  }

  void _openSettings() {
    final handler = widget.onOpenSettings;
    if (handler != null) {
      handler();
      return;
    }
    unawaited(openSettings(context));
  }

  void _openLove() {
    final handler = widget.onOpenLove;
    if (handler != null) {
      handler();
      return;
    }
    unawaited(showLoveSheet(context));
  }

  void _lock() {
    final handler = widget.onLock ?? ShellActions.maybeOf(context)?.onLock;
    handler?.call();
  }

  @override
  void dispose() {
    _warm?.cancel();
    _swap.dispose();
    _active.dispose();
    _ownToast?.dispose();
    super.dispose();
  }

  Widget _pages(BuildContext context) {
    final builder = widget.pageBuilder ?? skyTabPage;
    return Stack(
      fit: StackFit.expand,
      children: [
        for (final tab in SkyShell.tabs)
          if (_visited.contains(tab))
            _TabLayer(
              key: ValueKey<SkyTab>(tab),
              live: tab == _tab,
              shown: tab == _tab || tab == _leaving,
              opacity: tab == _tab ? _fadeIn : _fadeOut,
              child: Builder(builder: (context) => builder(context, tab)),
            ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.sky;
    final media = MediaQuery.of(context);
    final safeBottom = media.viewPadding.bottom;
    final clearance = SkySizes.dockClearance(safeBottom);
    return SkyTheme(
      child: AnnotatedRegion(
        value: tokens.statusBar,
        child: Material(
          color: tokens.page,
          child: SkyToastScope(
            controller: _toast,
            child: SkyShellScope(
              tab: _tab,
              activeTab: _active,
              selectTab: selectTab,
              openSettings: _openSettings,
              openLove: _openLove,
              lock: _lock,
              presence: widget.presence,
              myName: widget.myName,
              partnerName: widget.partnerName,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MediaQuery(
                    data: media.copyWith(padding: media.padding.copyWith(bottom: clearance)),
                    child: _pages(context),
                  ),
                  Positioned(
                    left: SkySizes.dockSide,
                    right: SkySizes.dockSide,
                    bottom: SkySizes.dockOffset(safeBottom),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: SkyDock(
                          key: ShellKeys.dock,
                          items: [for (final t in SkyShell.tabs) t.dockItem],
                          selectedIndex: SkyShell.tabs.indexOf(_tab),
                          onSelect: (i) => selectTab(SkyShell.tabs[i]),
                          onLove: _openLove,
                          loveLabel: ShellCopy.sendLove,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: ShellNotices(
                      key: ShellKeys.notices,
                      status: widget.status,
                      toast: _toast,
                      onOpenSettings: _openSettings,
                    ),
                  ),
                  ...widget.overlays,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabLayer extends StatelessWidget {
  const _TabLayer({super.key, required this.live, required this.shown, required this.opacity, required this.child});

  final bool live;
  final bool shown;
  final Animation<double> opacity;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Offstage(
      offstage: !shown,
      child: TickerMode(
        enabled: live,
        child: IgnorePointer(
          ignoring: !live,
          child: ExcludeSemantics(
            excluding: !live,
            child: FadeTransition(
              opacity: opacity,
              child: RepaintBoundary(child: child),
            ),
          ),
        ),
      ),
    );
  }
}

class ShellNotices extends StatelessWidget {
  const ShellNotices({super.key, required this.status, required this.toast, this.onOpenSettings});

  final ShellStatus status;
  final SkyToastController toast;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.viewPaddingOf(context).top + SkySpace.sm;
    final motion = skyMotionAllowed(context);
    final error = status.errorText;
    final warning = error == null ? status.warningText : null;
    return Padding(
      padding: EdgeInsets.fromLTRB(SkySpace.lg, top, SkySpace.lg, 0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 448),
          child: _Grow(
            motion: motion,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: SkySpace.sm),
                    child: SkyEntrance(
                      key: ValueKey<String>('shell-error-$error'),
                      offset: const Offset(0, -10),
                      child: SkyNotice(
                        text: skyCalmText(error),
                        tone: SkyNoticeTone.error,
                        elevated: true,
                        actionLabel: onOpenSettings == null ? null : ShellCopy.openSettings,
                        onAction: onOpenSettings,
                        onDismiss: status.onDismissError,
                        dismissLabel: ShellCopy.dismiss,
                      ),
                    ),
                  ),
                if (warning != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: SkySpace.sm),
                    child: SkyEntrance(
                      key: ValueKey<String>('shell-warning-$warning'),
                      offset: const Offset(0, -10),
                      child: SkyNotice(text: skyCalmText(warning), tone: SkyNoticeTone.warning, elevated: true),
                    ),
                  ),
                SkyToastHost(controller: toast),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Grow extends StatelessWidget {
  const _Grow({required this.motion, required this.child});

  final bool motion;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!motion) return child;
    return AnimatedSize(
      duration: SkyMotion.base,
      curve: SkyMotion.standard,
      alignment: Alignment.topCenter,
      child: child,
    );
  }
}
