import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/engine.dart';
import '../../app_shell.dart';
import '../../sky/sky.dart';
import '../sync/sync_hub.dart';

abstract final class SettingsCopy {
  static const String title = 'Settings';
  static const String thisPhone = 'This phone';
  static const String skyFollows = 'Sky follows the time';
  static const String skyFollowsHint = 'Day sky by day, stars by night';
  static const String lockNow = 'Lock Our Space now';
  static const String lockedFooter = 'Locked with your passphrase. Only you two can open it.';
  static const String twoOfUs = 'The two of us';
  static const String phones = 'Phones and copies';
  static const String phonesHint = 'Add another phone, or keep a copy safe';
  static String since(String date) => 'Together since $date';
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  static const String routeName = '/settings';
  static const Key phonesKey = ValueKey<String>('settings-phones');

  @override
  Widget build(BuildContext context) {
    final vault = context.watch<VaultService>();
    final identity = context.watch<IdentityController>();
    final sky = SkyModeScope.maybeOf(context);
    final t = context.sky;
    final couple = vault.config?.coupleNames.trim() ?? '';
    final start = vault.config?.startDate ?? '';
    final me = identity.me != null ? identity.myName : (couple.isEmpty ? null : couple);
    final partner = identity.partner != null ? identity.partnerName : null;
    return SkyScrollScaffold(
      topBar: const SkyTopBar(title: SettingsCopy.title, compact: true, leading: SkyBackButton()),
      children: [
        Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SkyAvatar(initial: SkyAvatar.initialOf(me, fallback: 'O'), size: 72),
                if (partner != null) ...[
                  const SizedBox(width: 4),
                  SkyAvatar(initial: SkyAvatar.initialOf(partner), size: 72, style: SkyAvatarStyle.partner),
                ],
              ],
            ),
            if (couple.isNotEmpty) ...[
              const SizedBox(height: SkySpace.md),
              Text(
                couple,
                textAlign: TextAlign.center,
                style: SkyType.headline.copyWith(color: t.title),
              ),
            ],
            if (start.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                SettingsCopy.since(formatDatePretty(start)),
                textAlign: TextAlign.center,
                style: SkyType.sans(12.5).copyWith(color: t.muted),
              ),
            ],
          ],
        ),
        if (sky != null)
          SkyListGroup(
            label: SettingsCopy.thisPhone,
            children: [
              ListenableBuilder(
                listenable: sky,
                builder: (context, _) => SkyListRow(
                  icon: SkyIcons.moon,
                  tone: SkyTone.lavender,
                  title: SettingsCopy.skyFollows,
                  subtitle: SettingsCopy.skyFollowsHint,
                  trailing: SkyToggle(
                    key: ShellKeys.skyFollowsTime,
                    value: sky.followsTime,
                    semanticLabel: SettingsCopy.skyFollows,
                    onChanged: (value) => sky.setFollowsTime(value),
                  ),
                ),
              ),
            ],
          ),
        SkyListGroup(
          label: SettingsCopy.twoOfUs,
          children: [
            SkyListRow(
              key: SettingsPage.phonesKey,
              icon: SkyIcons.phone,
              tone: SkyTone.lavender,
              title: SettingsCopy.phones,
              subtitle: SettingsCopy.phonesHint,
              onTap: () => unawaited(showSyncHub(context)),
            ),
          ],
        ),
        SkyButton(
          key: ShellKeys.lockNow,
          label: SettingsCopy.lockNow,
          icon: SkyIcons.lock,
          variant: SkyButtonVariant.ghost,
          onPressed: vault.lock,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SkyIcon(SkyIcons.lock, size: 12, color: t.faint),
            const SizedBox(width: 6),
            Flexible(
              child: Text(SettingsCopy.lockedFooter, style: SkyType.caption.copyWith(color: t.faint)),
            ),
          ],
        ),
      ],
    );
  }
}
