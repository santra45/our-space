import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_gradients.dart';
import '../theme/app_metrics.dart';
import '../theme/app_shadows.dart';
import '../theme/app_theme.dart';
import '../theme/app_typography.dart';
import 'app_haptics.dart';
import 'app_icons.dart';
import 'css_box.dart';
import 'lucide_icon.dart';
import 'our_feedback.dart';
import 'our_modal.dart';
import 'tw_animations.dart';

enum SyncPillState { error, direct, relayed, connected, checking, pairing, idle }

enum DotMotion { none, pulse, ping }

@immutable
class SyncPillStyle {
  const SyncPillStyle({
    required this.label,
    required this.background,
    required this.foreground,
    required this.border,
    required this.dot,
    required this.dotMotion,
    required this.icon,
  });

  final String label;
  final Color background;
  final Color foreground;
  final Color border;
  final Color dot;
  final DotMotion dotMotion;
  final LucideIconData icon;

  static SyncPillStyle of(SyncPillState state) {
    switch (state) {
      case SyncPillState.error:
        return const SyncPillStyle(
          label: 'Sync hiccup',
          background: AppColors.rose100,
          foreground: AppColors.rose700,
          border: AppColors.rose200,
          dot: AppColors.rose500,
          dotMotion: DotMotion.none,
          icon: AppIcons.alertTriangle,
        );
      case SyncPillState.direct:
        return const SyncPillStyle(
          label: 'Phone to phone ⚡',
          background: AppColors.emerald100,
          foreground: AppColors.emerald700,
          border: AppColors.emerald200,
          dot: AppColors.emerald500,
          dotMotion: DotMotion.pulse,
          icon: AppIcons.zap,
        );
      case SyncPillState.relayed:
        return const SyncPillStyle(
          label: 'Via a helper 🛡️',
          background: AppColors.indigo100,
          foreground: AppColors.indigo700,
          border: AppColors.indigo200,
          dot: AppColors.indigo500,
          dotMotion: DotMotion.pulse,
          icon: AppIcons.wifi,
        );
      case SyncPillState.connected:
        return const SyncPillStyle(
          label: 'Connected 💕',
          background: AppColors.emerald100,
          foreground: AppColors.emerald700,
          border: AppColors.emerald200,
          dot: AppColors.emerald500,
          dotMotion: DotMotion.pulse,
          icon: AppIcons.helpCircle,
        );
      case SyncPillState.checking:
        return const SyncPillStyle(
          label: 'Checking…',
          background: AppColors.amber100,
          foreground: AppColors.amber700,
          border: AppColors.amber200,
          dot: AppColors.amber500,
          dotMotion: DotMotion.ping,
          icon: AppIcons.shieldAlert,
        );
      case SyncPillState.pairing:
        return const SyncPillStyle(
          label: 'Pairing...',
          background: AppColors.amber100,
          foreground: AppColors.amber700,
          border: AppColors.amber200,
          dot: AppColors.amber500,
          dotMotion: DotMotion.ping,
          icon: AppIcons.refreshCw,
        );
      case SyncPillState.idle:
        return SyncPillStyle(
          label: 'Tap to Pair',
          background: AppColors.white.withValues(alpha: 0.8),
          foreground: AppColors.blush600,
          border: AppColors.blush200,
          dot: AppColors.blush400,
          dotMotion: DotMotion.none,
          icon: AppIcons.share2,
        );
    }
  }
}

enum HeaderPresenceKind { activeNow, lastSeen, justForUs }

@immutable
class HeaderPresence {
  const HeaderPresence.activeNow({this.partnerName}) : kind = HeaderPresenceKind.activeNow, lastSeen = null;

  const HeaderPresence.lastSeen({this.partnerName, required String this.lastSeen})
    : kind = HeaderPresenceKind.lastSeen;

  const HeaderPresence.justForUs() : kind = HeaderPresenceKind.justForUs, partnerName = null, lastSeen = null;

  final HeaderPresenceKind kind;
  final String? partnerName;
  final String? lastSeen;

  bool get _hasName => partnerName != null && partnerName!.trim().isNotEmpty;

  String get text {
    switch (kind) {
      case HeaderPresenceKind.activeNow:
        return _hasName ? '$partnerName active now 💕' : 'Active together 💕';
      case HeaderPresenceKind.lastSeen:
        return _hasName ? '$partnerName • $lastSeen' : 'Active $lastSeen';
      case HeaderPresenceKind.justForUs:
        return 'Just for us 💕';
    }
  }
}

class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.color, this.size = 8, this.motion = DotMotion.none});

  final Color color;
  final double size;
  final DotMotion motion;

  @override
  Widget build(BuildContext context) {
    final dot = SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    );
    switch (motion) {
      case DotMotion.none:
        return dot;
      case DotMotion.pulse:
        return TwPulse(child: dot);
      case DotMotion.ping:
        return TwPing(child: dot);
    }
  }
}

class SyncStatusPill extends StatelessWidget {
  const SyncStatusPill({super.key, required this.state, this.onTap});

  final SyncPillState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final style = SyncPillStyle.of(state);
    return Semantics(
      button: true,
      label: style.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap == null
            ? null
            : () {
                AppHaptics.tick();
                onTap!();
              },
        child: CssBox(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          color: style.background,
          border: Border.all(color: style.border),
          borderRadius: AppRadii.all(AppRadii.full),
          shadows: AppShadows.sm,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              StatusDot(color: style.dot, motion: style.dotMotion),
              const SizedBox(width: 6),
              LucideIcon(style.icon, size: 14, color: style.foreground),
            ],
          ),
        ),
      ),
    );
  }
}

class HeaderLogo extends StatelessWidget {
  const HeaderLogo({super.key});

  @override
  Widget build(BuildContext context) {
    return CssBox(
      width: 32,
      height: 32,
      gradient: AppGradients.headerLogo,
      borderRadius: AppRadii.all(AppRadii.full),
      shadows: AppShadows.tinted(AppShadows.sm, AppColors.blush300.withValues(alpha: 0.5)),
      child: const Center(child: LucideIcon(AppIcons.heart, size: 16, color: AppColors.white, fill: AppColors.white)),
    );
  }
}

class HeaderLockButton extends StatelessWidget {
  const HeaderLockButton({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Lock Our Space',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap == null
            ? null
            : () {
                AppHaptics.tick();
                onTap!();
              },
        child: CssBox(
          width: 32,
          height: 32,
          color: AppColors.white.withValues(alpha: 0.8),
          border: Border.all(color: AppColors.blush200),
          borderRadius: AppRadii.all(AppRadii.full),
          shadows: AppShadows.sm,
          child: const Center(child: LucideIcon(AppIcons.lock, size: 14, color: AppColors.slate500)),
        ),
      ),
    );
  }
}

class HeaderSyncErrorBanner extends StatelessWidget {
  const HeaderSyncErrorBanner({super.key, required this.text, this.onOpenHub, this.onDismiss});

  final String text;
  final VoidCallback? onOpenHub;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return CssBox(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: AppColors.rose50,
      border: Border.all(color: AppColors.rose200),
      borderRadius: AppRadii.all(AppRadii.x2l),
      shadows: AppShadows.sm,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: LucideIcon(AppIcons.alertTriangle, size: 14, color: AppColors.rose500),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text, style: Tw.px11.bold.tight.c(AppColors.rose700)),
                const SizedBox(height: 4),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onOpenHub == null
                      ? null
                      : () {
                          AppHaptics.tick();
                          onOpenHub!();
                        },
                  child: Text('Open the Pair & Sync hub', style: Tw.px10.bold.underline.c(AppColors.rose600)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Semantics(
            button: true,
            label: 'Dismiss',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onDismiss == null
                  ? null
                  : () {
                      AppHaptics.tick();
                      onDismiss!();
                    },
              child: CssBox(
                width: 20,
                height: 20,
                color: AppColors.rose100,
                borderRadius: AppRadii.all(AppRadii.full),
                child: const Center(child: LucideIcon(AppIcons.x, size: 12, color: AppColors.rose600)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class HeaderSyncWarningBanner extends StatelessWidget {
  const HeaderSyncWarningBanner({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return CssBox(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: AppColors.amber50,
      border: Border.all(color: AppColors.amber200),
      borderRadius: AppRadii.all(AppRadii.x2l),
      shadows: AppShadows.sm,
      child: Text(text, textAlign: TextAlign.center, style: Tw.px11.semibold.c(AppColors.amber700)),
    );
  }
}

class OurHeader extends StatelessWidget {
  const OurHeader({
    super.key,
    this.title,
    this.presence = const HeaderPresence.justForUs(),
    this.syncState = SyncPillState.idle,
    this.onOpenSync,
    this.onLock,
    this.syncErrorText,
    this.onDismissSyncError,
    this.syncWarningText,
    this.notice,
  });

  final String? title;
  final HeaderPresence presence;
  final SyncPillState syncState;
  final VoidCallback? onOpenSync;
  final VoidCallback? onLock;
  final String? syncErrorText;
  final VoidCallback? onDismissSyncError;
  final String? syncWarningText;
  final String? notice;

  static final Color background = AppColors.blush50.withValues(alpha: 0.7);
  static final Color borderColor = AppColors.blush100.withValues(alpha: 0.5);
  static const double backdropBlur = 12;

  Widget _presenceLine() {
    switch (presence.kind) {
      case HeaderPresenceKind.activeNow:
        return Row(
          children: [
            const StatusDot(color: AppColors.emerald500, size: 6, motion: DotMotion.pulse),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                presence.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Tw.px10.medium.tight.c(AppColors.emerald600),
              ),
            ),
          ],
        );
      case HeaderPresenceKind.lastSeen:
        return Row(
          children: [
            const StatusDot(color: AppColors.slate400, size: 6),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                presence.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Tw.px10.medium.tight.c(AppColors.slate500),
              ),
            ),
          ],
        );
      case HeaderPresenceKind.justForUs:
        return Text(presence.text, style: Tw.px10.medium.tight.c(AppColors.slate500));
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = OurToastScope.maybeOf(context);
    final statusBar = MediaQuery.viewPaddingOf(context).top;
    final effectiveTitle = (title == null || title!.trim().isEmpty) ? 'Our Space' : title!;

    Widget body(String? toast) {
      final shownNotice = notice ?? toast;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: AppLayout.headerRowHeight,
            child: Row(
              children: [
                const HeaderLogo(),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        effectiveTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Tw.sm.bold.tight.c(AppColors.slate800),
                      ),
                      _presenceLine(),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SyncStatusPill(state: syncState, onTap: onOpenSync),
                const SizedBox(width: 8),
                HeaderLockButton(onTap: onLock),
              ],
            ),
          ),
          if (syncErrorText != null) ...[
            const SizedBox(height: 8),
            HeaderSyncErrorBanner(text: syncErrorText!, onOpenHub: onOpenSync, onDismiss: onDismissSyncError),
          ],
          if (syncErrorText == null && syncWarningText != null) ...[
            const SizedBox(height: 8),
            HeaderSyncWarningBanner(text: syncWarningText!),
          ],
          if (shownNotice != null) ...[
            const SizedBox(height: 8),
            OurNoticePill(message: shownNotice),
          ],
        ],
      );
    }

    final content = controller == null
        ? body(null)
        : ListenableBuilder(listenable: controller, builder: (context, _) => body(controller.message));

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (statusBar > 0) SizedBox(height: statusBar, child: const ColoredBox(color: AppTheme.statusBarTint)),
        CssBox(
          padding: const EdgeInsets.fromLTRB(16, AppLayout.headerMinTopPadding, 16, AppLayout.headerBottomPadding),
          color: background,
          border: Border(bottom: BorderSide(color: borderColor)),
          backdropBlur: backdropBlur,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: AppLayout.maxWidthMd),
              child: content,
            ),
          ),
        ),
      ],
    );
  }
}

Future<bool> showConnectDeviceDialog(BuildContext context, {required String peerId, required bool fromLink}) async {
  final result = await showOurModal<bool>(
    context: context,
    backdrop: OurBackdropTone.black60,
    entrance: OurModalEntrance.none,
    builder: (dialogContext) => OurModalCard(
      showClose: false,
      borderColor: AppColors.blush100,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CssBox(
                width: 36,
                height: 36,
                color: AppColors.amber100,
                borderRadius: AppRadii.all(AppRadii.full),
                child: const Center(child: LucideIcon(AppIcons.shieldAlert, size: 16, color: AppColors.amber600)),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text('Connect to this device?', style: Tw.base.bold.c(AppColors.slate800))),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            fromLink
                ? 'A link is asking to connect to the phone below.'
                : 'There is a saved phone here we have not connected to before.',
            style: Tw.xs.relaxed.c(AppColors.slate600),
          ),
          const SizedBox(height: 8),
          CssBox(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: AppColors.slate50,
            border: Border.all(color: AppColors.slate200),
            borderRadius: AppRadii.all(AppRadii.xl),
            child: Text(peerId, style: Tw.xs.mono.bold.c(AppColors.slate700)),
          ),
          const SizedBox(height: 12),
          CssBox(
            padding: const EdgeInsets.all(12),
            color: AppColors.amber50,
            border: Border.all(color: AppColors.amber200),
            borderRadius: AppRadii.all(AppRadii.x2l),
            child: Text(
              'Only connect if you know who sent you this link.',
              style: Tw.px11.relaxed.c(AppColors.amber800),
            ),
          ),
          const SizedBox(height: 16),
          OurDialogActions(
            cancelLabel: 'Not now',
            confirmLabel: 'Connect',
            onCancel: () => Navigator.of(dialogContext).pop(false),
            onConfirm: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    ),
  );
  return result ?? false;
}
