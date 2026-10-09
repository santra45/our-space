import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../core/engine.dart';
import 'theme/app_motion.dart';
import 'widgets/our_feedback.dart';

class AppNotices extends ChangeNotifier {
  AppNotices({required this.vault, required this.sync, this.warningTtl = const Duration(milliseconds: 7000)})
      : toast = OurToastController(ttl: AppMotion.toast) {
    _notices = sync.notices.listen(_onNotice);
    _bursts = sync.loveBurstArrivals.listen(_onBursts);
    _wasUnlocked = vault.isUnlocked;
    vault.addListener(_onVault);
  }

  final VaultService vault;
  final SyncService sync;
  final Duration warningTtl;
  final OurToastController toast;

  late final StreamSubscription<SyncNotice> _notices;
  late final StreamSubscription<int> _bursts;
  late bool _wasUnlocked;
  Timer? _warningTimer;
  String? _syncWarning;
  String? _vaultWarning;
  int _pendingCelebrations = 0;
  bool _disposed = false;

  String? get syncWarning => _syncWarning;
  String? get vaultWarning => _vaultWarning;
  int get pendingCelebrations => _pendingCelebrations;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  void _onNotice(SyncNotice notice) {
    if (!vault.isUnlocked) return;
    if (notice.kind == SyncNoticeKind.warning) {
      _warningTimer?.cancel();
      _syncWarning = notice.text;
      _warningTimer = Timer(warningTtl, clearSyncWarning);
      notifyListeners();
      return;
    }
    toast.show(notice.text);
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
  late AppNotices _notices = AppNotices(vault: widget.space.vault, sync: widget.space.sync);

  @override
  void didUpdateWidget(covariant SpaceScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.space, widget.space)) {
      _notices.dispose();
      _notices = AppNotices(vault: widget.space.vault, sync: widget.space.sync);
    }
  }

  @override
  void dispose() {
    _notices.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final space = widget.space;
    return MultiProvider(
      providers: [
        Provider<OurSpace>.value(value: space),
        ChangeNotifierProvider<VaultService>.value(value: space.vault),
        ChangeNotifierProvider<IdentityController>.value(value: space.identity),
        ChangeNotifierProvider<SyncService>.value(value: space.sync),
        ChangeNotifierProvider<AppNotices>.value(value: _notices),
      ],
      child: SpaceLifecycle(sync: space.sync, child: widget.child),
    );
  }
}

extension SpaceContext on BuildContext {
  OurSpace get space => read<OurSpace>();
}

class SpaceLifecycle extends StatefulWidget {
  const SpaceLifecycle({super.key, required this.sync, required this.child});

  final SyncService sync;
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
