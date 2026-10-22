import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_shell.dart';
import '../../legacy_area.dart';
import '../../sky/sky.dart';
import '../../widgets/our_page.dart';
import '../daily/daily_question_card.dart';

class OurSkyPage extends StatelessWidget {
  const OurSkyPage({super.key});

  static const double skyHeight = 400;

  @override
  Widget build(BuildContext context) {
    final scope = SkyShellScope.maybeOf(context);
    final presence = scope?.presence ?? const PartnerPresence.unknown();
    final night = context.sky.isNight;
    final weekday = DateFormat('EEEE').format(DateTime.now());
    final myName = scope?.myName;
    final partnerName = scope?.partnerName;
    final scene = SkyScene(
      moon: const Offset(306, 120),
      sunAt: const Offset(40, 360),
      heart: HeartConstellation(center: const Offset(195, 236), scale: 5.2, presence: presence.isHere),
      clouds: const [SkyCloud(318, 140, scale: 0.9, opacity: 0.85), SkyCloud(52, 230, scale: 0.65, opacity: 0.6)],
    );
    return SkyScaffold(
      scene: scene,
      skyHeight: skyHeight,
      anchors: [
        if (myName != null && myName.trim().isNotEmpty)
          SkyAnchor(at: const SkyPoint.qalbi(), offset: const Offset(0, 16), child: SkyNameLabel(myName)),
        if (partnerName != null && partnerName.trim().isNotEmpty)
          SkyAnchor(
            at: const SkyPoint.farhu(),
            offset: const Offset(-10, 26),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SkyNameLabel(partnerName),
                if (presence.label != null) SkyHereChip(label: presence.label!, pulse: presence.isHere),
              ],
            ),
          ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SkyEntrance(
            child: SkyTopBar(
              kicker: night ? 'Tonight · $weekday' : 'Today · $weekday',
              title: night ? 'Our sky, tonight' : 'Our sky, today',
              trailing: const ShellAvatar(),
            ),
          ),
          const SizedBox(height: 236),
          const Expanded(
            child: SkyEntrance(
              index: 2,
              child: LegacyArea(child: OurPage(spacing: 0, children: [DailyQuestionCard()])),
            ),
          ),
        ],
      ),
    );
  }
}
