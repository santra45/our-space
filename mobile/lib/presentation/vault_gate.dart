import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/engine.dart';
import 'app_shell.dart';
import 'screens/lock/lock_screen.dart';
import 'space_scope.dart';
import 'widgets/our_widgets.dart';

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

  @override
  Widget build(BuildContext context) {
    final notices = context.watch<AppNotices>();
    final warning = notices.vaultWarning;
    if (warning == null) return const SizedBox.shrink();
    final media = MediaQuery.of(context);
    return Positioned(
      left: 16,
      right: 16,
      bottom: 16 + media.viewPadding.bottom,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppLayout.maxWidthMd),
          child: Material(
            type: MaterialType.transparency,
            child: Semantics(
              liveRegion: true,
              child: CssBox(
                padding: const EdgeInsets.all(12),
                color: AppColors.amber50,
                border: Border.all(color: AppColors.amber200),
                borderRadius: AppRadii.all(AppRadii.x2l),
                shadows: AppShadows.tinted(AppShadows.lg, AppColors.amber200.withValues(alpha: 0.4)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: LucideIcon(AppIcons.alertTriangle, size: 16, color: AppColors.amber500),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(warning, style: Tw.px11.relaxed.medium.c(AppColors.amber900)),
                    ),
                    const SizedBox(width: 10),
                    Semantics(
                      button: true,
                      label: 'Dismiss',
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: notices.clearVaultWarning,
                        child: const LucideIcon(AppIcons.x, size: 14, color: AppColors.amber500),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
