import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/engine/storage/local_settings.dart';
import '../../sky/sky.dart';
import '../daily/daily_answer_card.dart';
import '../daily/daily_copy.dart';
import '../daily/daily_question_sheet.dart';
import 'sky_constellations.dart';

enum StarNightResult { everyDay }

abstract final class StarNightKeys {
  static const Key sheet = ValueKey<String>('star-night-sheet');
  static const Key everyDay = ValueKey<String>('star-night-every-day');
  static const Key mine = ValueKey<String>('star-night-mine');
  static const Key theirs = ValueKey<String>('star-night-theirs');
}

abstract final class StarNightCopy {
  static const String relive = 'Tap a star to relive that night';

  static String date(StarNight night) {
    final date = night.date;
    return date == null ? night.day : DateFormat('EEEE d MMMM', 'en_US').format(date);
  }

  static String title(StarNight night) =>
      night.date == null ? 'Night ${night.number}' : 'Night ${night.number} · ${date(night)}';

  static String constellation(StarNight night) =>
      '${ConstellationChapter.titleOf(night.constellation)} · ${night.shape.title}';
}

abstract final class StarNightTip {
  static const String settingsKey = 'skyReliveTipSeen';

  static bool seen(LocalSettings settings) => settings.getItem(settingsKey) == '1';

  static Future<void> remember(LocalSettings settings) => settings.setItem(settingsKey, '1');
}

Future<StarNightResult?> showStarNightSheet(
  BuildContext context, {
  required StarNight night,
  required String partnerName,
  String? myName,
}) {
  return showSkySheet<StarNightResult>(
    context: context,
    settings: const RouteSettings(name: StarNightSheet.routeName),
    builder: (_) => StarNightSheet(night: night, partnerName: partnerName, myName: myName),
  );
}

class StarNightSheet extends StatelessWidget {
  const StarNightSheet({super.key, required this.night, required this.partnerName, this.myName});

  static const String routeName = '/sky/night';

  final StarNight night;
  final String partnerName;
  final String? myName;

  void _close(BuildContext context, [StarNightResult? result]) {
    if (ModalRoute.of(context)?.isCurrent ?? false) Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final question = night.question;
    final mine = night.mine;
    final theirs = night.theirs;
    return Stack(
      key: StarNightKeys.sheet,
      clipBehavior: Clip.none,
      children: [
        SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 40, top: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SkyLabel(StarNightCopy.title(night), icon: SkyIcons.star, tone: SkyTone.rose),
                    const SizedBox(height: 8),
                    Semantics(
                      header: true,
                      child: Text(
                        question == null ? DailyCopy.fromBackThen : DailyCopy.quoted(question.text),
                        style: SkyType.serif(22, height: 1.25).copyWith(color: t.text),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(StarNightCopy.constellation(night), style: SkyType.caption.copyWith(color: t.muted)),
                  ],
                ),
              ),
              const SizedBox(height: SkySpace.lg),
              ...skyStaggered([
                if (mine != null)
                  DailyAnswerCard(
                    key: StarNightKeys.mine,
                    name: DailyCopy.you,
                    initial: SkyAvatar.initialOf(myName, fallback: 'Y'),
                    text: mine.text,
                  ),
                if (theirs != null)
                  Padding(
                    padding: EdgeInsets.only(top: mine != null ? 10 : 0),
                    child: DailyAnswerCard(
                      key: StarNightKeys.theirs,
                      name: capitalized(partnerName),
                      initial: SkyAvatar.initialOf(partnerName),
                      text: theirs.text,
                      partner: true,
                    ),
                  ),
              ]),
              DailySheetLink(
                key: StarNightKeys.everyDay,
                label: DailyCopy.everyDay,
                icon: SkyIcons.calendar,
                onTap: () => _close(context, StarNightResult.everyDay),
              ),
            ],
          ),
        ),
        Positioned(
          top: -4,
          right: -4,
          child: SkyIconButton(
            icon: SkyIcons.close,
            semanticLabel: DailyCopy.close,
            tone: SkyIconButtonTone.ghost,
            size: 36,
            iconSize: 16,
            onPressed: () => _close(context),
          ),
        ),
      ],
    );
  }
}
