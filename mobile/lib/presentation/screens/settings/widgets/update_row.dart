import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/engine.dart';
import '../../../sky/sky.dart';
import 'settings_row.dart';

abstract final class UpdateCopy {
  static const String partnerFallback = 'your partner';
  static const String tapToGet = 'Tap to get it. Keep Our Space open on both phones while it comes over.';
  static const String openBoth = 'Open Our Space on both phones and it can come over.';
  static const String checking = 'Almost there, making sure it all arrived';
  static const String ready = 'Ready. Tap to put it on this phone.';
  static const String allow = 'Let Our Space add its updates, then come back here.';
  static const String opening = 'Opening the update';
  static const String failed = 'That did not arrive right. Tap to try again.';

  static String title(String partner) => 'A newer Our Space from ${_who(partner)}';

  static String coming(int percent) => 'Coming over, $percent%. Keep Our Space open.';

  static String paused(int percent) => 'Paused at $percent%. It carries on when you are both in Our Space.';

  static String arrived(String partner) =>
      '${_cap(_who(partner))} has a newer Our Space for you. It is waiting in Settings.';

  static String sharingTitle(String partner) => 'Sending ${_who(partner)} the newer Our Space';

  static String shared(int percent) => '$percent% there. Keep Our Space open.';

  static String _who(String partner) {
    final name = partner.trim();
    return name.isEmpty ? partnerFallback : name;
  }

  static String _cap(String text) => text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);
}

int updatePercent(double fraction) => (fraction.clamp(0.0, 1.0) * 100).floor();

class UpdateRow extends StatelessWidget {
  const UpdateRow({super.key, required this.link, required this.partner});

  final AppUpdateLink link;
  final String partner;

  @override
  Widget build(BuildContext context) {
    final stage = link.stage;
    if (stage == AppUpdateStage.none) {
      if (!link.sharing) return const SizedBox.shrink();
      return SettingsRow(
        icon: SkyIcons.upload,
        tone: SkyTone.lavender,
        title: UpdateCopy.sharingTitle(partner),
        subtitle: UpdateCopy.shared(updatePercent(link.shareProgress)),
        chevron: false,
      );
    }
    final percent = updatePercent(link.progress);
    final (String subtitle, VoidCallback? onTap) = switch (stage) {
      AppUpdateStage.available => (
          link.linked ? UpdateCopy.tapToGet : UpdateCopy.openBoth,
          () => unawaited(link.fetch()),
        ),
      AppUpdateStage.fetching => (
          link.checking
              ? UpdateCopy.checking
              : link.linked
                  ? UpdateCopy.coming(percent)
                  : percent == 0
                      ? UpdateCopy.openBoth
                      : UpdateCopy.paused(percent),
          null,
        ),
      AppUpdateStage.ready => (UpdateCopy.ready, () => unawaited(link.install())),
      AppUpdateStage.needsPermission => (UpdateCopy.allow, () => unawaited(link.install())),
      AppUpdateStage.installing => (UpdateCopy.opening, null),
      AppUpdateStage.failed => (UpdateCopy.failed, () => unawaited(link.fetch())),
      AppUpdateStage.none => ('', null),
    };
    return SettingsRow(
      icon: SkyIcons.download,
      tone: SkyTone.gold,
      title: UpdateCopy.title(partner),
      subtitle: subtitle,
      onTap: onTap,
      chevron: onTap != null,
    );
  }
}
