import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../core/engine.dart';
import 'route_requests.dart';
import 'screens/away/away_sheet.dart' show AwayCopy;
import 'screens/settings/widgets/update_row.dart' show UpdateCopy;
import 'screens/sync/notice_copy.dart';
import 'screens/sync/peer_link.dart';
import 'sky/sky.dart';

class AppNotices extends ChangeNotifier {
  AppNotices({
    required this.vault,
    required this.sync,
    this.away,
    this.warningTtl = const Duration(milliseconds: 7000),
  }) : toast = SkyToastController() {
    _notices = sync.notices.listen(_onNotice);
    _bursts = sync.loveBurstArrivals.listen(_onBursts);
    _wasUnlocked = vault.isUnlocked;
    vault.addListener(_onVault);
    _updates = sync.peer?.appUpdate;
    _updates?.addListener(_onUpdate);
    _arrivals = away?.arrivals.listen(_onArrival);
  }

  static const Duration _pairWindow = Duration(seconds: 3);
  static final RegExp _generic = RegExp(r'^(Synced [0-9]+|[0-9]+ new thing)');

  final VaultService vault;
  final SyncService sync;
  final AwayFeed? away;
  final Duration warningTtl;
  final SkyToastController toast;

  late final StreamSubscription<SyncNotice> _notices;
  late final StreamSubscription<int> _bursts;
  late bool _wasUnlocked;
  Timer? _warningTimer;
  String? _syncWarning;
  String? _vaultWarning;
  int _pendingCelebrations = 0;
  bool _disposed = false;
  AppUpdateLink? _updates;
  int? _toldAboutUpdate;
  StreamSubscription<AwayEntry>? _arrivals;
  DateTime? _lastSpecific;

  String? get syncWarning => _syncWarning;
  String? get vaultWarning => _vaultWarning;
  int get pendingCelebrations => _pendingCelebrations;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  void _onArrival(AwayEntry entry) {
    if (!vault.isUnlocked) return;
    _lastSpecific = DateTime.now();
    toast.show(AwayCopy.line(entry, sync.identity.partnerName));
  }

  bool get _justToldSpecific {
    final last = _lastSpecific;
    return last != null && DateTime.now().difference(last) < _pairWindow;
  }

  void _onNotice(SyncNotice notice) {
    if (!vault.isUnlocked) return;
    if (notice.kind == SyncNoticeKind.notice && _justToldSpecific && _generic.hasMatch(notice.text.trim())) return;
    final text = NoticeCopy.warm(notice.text, partner: sync.identity.partnerName);
    if (text.isEmpty) return;
    if (notice.kind == SyncNoticeKind.warning) {
      _warningTimer?.cancel();
      _syncWarning = text;
      _warningTimer = Timer(warningTtl, clearSyncWarning);
      notifyListeners();
      return;
    }
    toast.show(text);
  }

  void _onUpdate() {
    final updates = _updates;
    if (updates == null || updates.stage != AppUpdateStage.available || !vault.isUnlocked) return;
    final code = updates.partnerCode;
    if (code == null || code == _toldAboutUpdate) return;
    _toldAboutUpdate = code;
    toast.show(UpdateCopy.arrived(sync.identity.partnerName));
  }

  void _onBursts(int total) {
    if (total <= 0 || !vault.isUnlocked) return;
    _pendingCelebrations++;
    notifyListeners();
  }

  void _onVault() {
    final unlocked = vault.isUnlocked;
    if (_wasUnlocked && !unlocked) {
      _warningTimer?.cancel();
      _syncWarning = null;
      _vaultWarning = null;
      _pendingCelebrations = 0;
      notifyListeners();
    }
    _wasUnlocked = unlocked;
  }

  void showToast(String message) => toast.show(message);

  void clearSyncWarning() {
    _warningTimer?.cancel();
    _warningTimer = null;
    if (_syncWarning == null) return;
    _syncWarning = null;
    notifyListeners();
  }

  void showVaultWarning(String message) {
    _vaultWarning = message;
    notifyListeners();
  }

  void clearVaultWarning() {
    if (_vaultWarning == null) return;
    _vaultWarning = null;
    notifyListeners();
  }

  int takeCelebrations() {
    final pending = _pendingCelebrations;
    _pendingCelebrations = 0;
    return pending;
  }

  @override
  void dispose() {
    _disposed = true;
    _warningTimer?.cancel();
    vault.removeListener(_onVault);
    _updates?.removeListener(_onUpdate);
    unawaited(_arrivals?.cancel());
    unawaited(_notices.cancel());
    unawaited(_bursts.cancel());
    toast.dispose();
    super.dispose();
  }
}

class SpaceScope extends StatefulWidget {
  const SpaceScope({super.key, required this.space, required this.child});

  final OurSpace space;
  final Widget child;

  @override
  State<SpaceScope> createState() => _SpaceScopeState();
}

class _SpaceScopeState extends State<SpaceScope> {
  late AppNotices _notices = _noticesFor(widget.space);
  late PeerLink _peer = HubPeerLink(widget.space.peer);
  final RouteRequests _routes = RouteRequests();
  StreamSubscription<String>? _reminderTaps;

  static AppNotices _noticesFor(OurSpace space) =>
      AppNotices(vault: space.vault, sync: space.sync, away: space.awayFeed);

  @override
  void initState() {
    super.initState();
    _listenForReminderTaps(widget.space);
  }

  void _listenForReminderTaps(OurSpace space) {
    unawaited(_reminderTaps?.cancel());
    final platform = space.reminders.platform;
    if (platform == null) return;
    _reminderTaps = platform.opened.listen(_routes.open);
    unawaited(platform.takeRoute().then((route) {
      if (route != null && mounted) _routes.open(route);
    }));
  }

  @override
  void didUpdateWidget(covariant SpaceScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.space, widget.space)) {
      _notices.dispose();
      _notices = _noticesFor(widget.space);
      _peer.dispose();
      _peer = HubPeerLink(widget.space.peer);
      _listenForReminderTaps(widget.space);
    }
  }

  @override
  void dispose() {
    unawaited(_reminderTaps?.cancel());
    _notices.dispose();
    _peer.dispose();
    _routes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final space = widget.space;
    return MultiProvider(
      providers: [
        Provider<OurSpace>.value(value: space),
        ChangeNotifierProvider<VaultService>.value(value: space.vault),
        ChangeNotifierProvider<QuickUnlockService>.value(value: space.quickUnlock),
        ChangeNotifierProvider<IdentityController>.value(value: space.identity),
        ChangeNotifierProvider<SyncService>.value(value: space.sync),
        ChangeNotifierProvider<AppNotices>.value(value: _notices),
        ChangeNotifierProvider<PeerLink>.value(value: _peer),
        ChangeNotifierProvider<AwayFeed>.value(value: space.awayFeed),
        ChangeNotifierProvider<ReminderService>.value(value: space.reminders),
        ChangeNotifierProvider<RouteRequests>.value(value: _routes),
      ],
      child: SpaceLifecycle(sync: space.sync, push: space.push, reminders: space.reminders, child: widget.child),
    );
  }
}

extension SpaceContext on BuildContext {
  OurSpace get space => read<OurSpace>();
}

class SpaceLifecycle extends StatefulWidget {
  const SpaceLifecycle({super.key, required this.sync, this.push, this.reminders, required this.child});

  final SyncService sync;
  final PushService? push;
  final ReminderService? reminders;
  final Widget child;

  @override
  State<SpaceLifecycle> createState() => _SpaceLifecycleState();
}

class _SpaceLifecycleState extends State<SpaceLifecycle> with WidgetsBindingObserver {
  bool _inBackground = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (_inBackground) {
          _inBackground = false;
          widget.sync.onForeground();
          unawaited(widget.push?.check());
          widget.reminders?.onForeground();
        }
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        if (!_inBackground) {
          _inBackground = true;
          widget.sync.onBackground();
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
