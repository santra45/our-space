import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/engine.dart';
import 'app_shell.dart';
import 'screens/lock/lock_screen.dart';
import 'space_scope.dart';
import 'sky/sky.dart';

class VaultGate extends StatefulWidget {
  const VaultGate({super.key, required this.shell, this.invite});

  final Widget shell;
  final Invite? invite;

  @override
  State<VaultGate> createState() => _VaultGateState();
}

class _VaultGateState extends State<VaultGate> {
  bool _wasUnlocked = false;

  void _closeRoutesAbove() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final navigator = Navigator.maybeOf(context);
      navigator?.popUntil((route) => route.isFirst);
    });
  }

  @override
  Widget build(BuildContext context) {
    final vault = context.watch<VaultService>();
    final unlocked = vault.isUnlocked;
    if (_wasUnlocked && !unlocked) _closeRoutesAbove();
    _wasUnlocked = unlocked;
    if (!unlocked) return LockScreen(invite: widget.invite);
    return ShellActions(onLock: vault.lock, child: widget.shell);
  }
}

class VaultWarningBanner extends StatelessWidget {
  const VaultWarningBanner({super.key});

  static const String dismissLabel = 'Dismiss';

  @override
  Widget build(BuildContext context) {
    final notices = context.watch<AppNotices>();
    final warning = notices.vaultWarning;
    final unlocked = context.watch<VaultService>().isUnlocked;
    final media = MediaQuery.of(context);
    final bottom = unlocked ? SkySizes.dockClearance(media.viewPadding.bottom) : SkySpace.lg + media.viewPadding.bottom;
    return Positioned(
      left: SkySpace.lg,
      right: SkySpace.lg,
      bottom: bottom,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 448),
          child: SkyTheme(
            child: AnimatedSwitcher(
              duration: skyMotionAllowed(context) ? SkyMotion.base : Duration.zero,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(animation),
                  child: child,
                ),
              ),
              child: warning == null
                  ? const SizedBox.shrink()
                  : Material(
                      key: ValueKey<String>(warning),
                      type: MaterialType.transparency,
                      child: SkyNotice(
                        text: warning,
                        tone: SkyNoticeTone.warning,
                        elevated: true,
                        onDismiss: notices.clearVaultWarning,
                        dismissLabel: dismissLabel,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
