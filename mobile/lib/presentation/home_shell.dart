import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../core/engine.dart';
import 'app_shell.dart';
import 'screens/people/people_setup.dart';
import 'screens/sync/sync_hub.dart';
import 'space_scope.dart';
import 'widgets/our_widgets.dart';

HeaderPresence headerPresenceFor(IdentityController identity, {int? now}) {
  final seen = formatLastSeen(identity.partnerLastActive, now: now);
  if (seen == null) return const HeaderPresence.justForUs();
  return HeaderPresence.lastSeen(partnerName: identity.partnerName, lastSeen: seen);
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.pageBuilder, this.particles = true});

  final AppTabBuilder? pageBuilder;
  final bool particles;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const Duration _presenceTick = Duration(seconds: 30);

  Timer? _clock;
  int _now = DateTime.now().millisecondsSinceEpoch;
  AppNotices? _notices;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(_presenceTick, (_) {
      if (mounted) setState(() => _now = DateTime.now().millisecondsSinceEpoch);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final notices = context.read<AppNotices>();
    if (!identical(notices, _notices)) {
      _notices?.removeListener(_onNotices);
      _notices = notices..addListener(_onNotices);
      _onNotices();
    }
  }

  void _onNotices() {
    if ((_notices?.pendingCelebrations ?? 0) <= 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if ((_notices?.takeCelebrations() ?? 0) <= 0) return;
      AppHaptics.celebration();
      fireCelebrationBurst(context);
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _notices?.removeListener(_onNotices);
    super.dispose();
  }

  void _openSync() => unawaited(showSyncHub(context));

  @override
  Widget build(BuildContext context) {
    final vault = context.watch<VaultService>();
    final identity = context.watch<IdentityController>();
    final notices = context.watch<AppNotices>();

    return AppShell(
      header: OurHeader(
        title: vault.config?.coupleNames,
        presence: headerPresenceFor(identity, now: _now),
        syncState: SyncPillState.idle,
        onOpenSync: _openSync,
        onLock: vault.lock,
        syncWarningText: notices.syncWarning,
      ),
      pageBuilder: widget.pageBuilder ?? tabPage,
      toastController: notices.toast,
      onOpenSync: _openSync,
      onLock: vault.lock,
      particles: widget.particles,
      overlays: const [PeopleSetup()],
    );
  }
}
