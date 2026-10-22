import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/engine.dart';
import '../../app_shell.dart';
import '../../legacy_area.dart';
import '../../sky/sky.dart';
import '../bucketlist/bucket_list.dart';
import '../countdown/constellation.dart';
import '../countdown/live_love_counter.dart';
import '../countdown/together_date_sheet.dart';
import '../countdown/together_hero.dart';
import '../countdown/upcoming_milestones.dart';
import '../roulette/date_roulette.dart';
import 'us_copy.dart';
import 'us_keys.dart';

enum UsSection { story, dreams, dates }

extension UsSectionInfo on UsSection {
  String get label {
    switch (this) {
      case UsSection.story:
        return UsCopy.story;
      case UsSection.dreams:
        return UsCopy.dreams;
      case UsSection.dates:
        return UsCopy.dates;
    }
  }
}

class UsPage extends StatefulWidget {
  const UsPage({super.key, this.initialSection = UsSection.story, this.clock});

  final UsSection initialSection;
  final LoveClock? clock;

  @override
  State<UsPage> createState() => _UsPageState();
}

class _UsPageState extends State<UsPage> {
  late UsSection _section = widget.initialSection;
  late final LiveLoveCounter _counter = LiveLoveCounter(clock: widget.clock);
  bool _back = false;

  @override
  void dispose() {
    _counter.dispose();
    super.dispose();
  }

  void _select(UsSection section) {
    if (section == _section) return;
    setState(() {
      _back = section.index < _section.index;
      _section = section;
    });
  }

  String _startDate(BuildContext context) {
    final configured = context.watch<VaultService>().config?.startDate ?? '';
    if (configured.isNotEmpty) return configured;
    return toLocalDateInput(DateTime.fromMillisecondsSinceEpoch(_counter.now()));
  }

  void _changeDay(String startDate) {
    unawaited(showTogetherDateSheet(context, startDate: startDate));
  }

  Widget _story(String startDate) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(SkySpace.gutter, 0, SkySpace.gutter, SkyScrollScaffold.bottomInsetOf(context)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TogetherHero(key: UsKeys.hero, counter: _counter, onTap: () => _changeDay(startDate)),
          const SizedBox(height: SkySpace.md),
          ListenableBuilder(
            listenable: _counter,
            builder: (context, _) => UpcomingRow(
              key: UsKeys.upcoming,
              items: upcomingMilestones(startDate, DateTime.fromMillisecondsSinceEpoch(_counter.now())),
            ),
          ),
          const SizedBox(height: SkySpace.sectionGap - UpcomingRow.shadowRoom),
          OurConstellation(
            key: UsKeys.constellation,
            counter: _counter,
            startDate: startDate,
            onChangeDay: () => _changeDay(startDate),
          ),
        ],
      ),
    );
  }

  Widget _content(String startDate) {
    switch (_section) {
      case UsSection.story:
        return _story(startDate);
      case UsSection.dreams:
        return const LegacyArea(child: BucketList());
      case UsSection.dates:
        return const LegacyArea(child: DateRoulette());
    }
  }

  @override
  Widget build(BuildContext context) {
    final startDate = _startDate(context);
    _counter.track(startDate);
    final now = DateTime.fromMillisecondsSinceEpoch(_counter.now());
    final start = parseLocalDate(startDate) ?? now;
    return SkyScaffold(
      scene: SkyScene.page,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SkyEntrance(
            child: SkyTopBar(
              kicker: UsCopy.since(start, now),
              title: UsCopy.title,
              trailing: const ShellAvatar(),
            ),
          ),
          const SizedBox(height: SkySpace.lg),
          SkyEntrance(
            index: 1,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: SkySpace.gutter),
              child: Row(
                children: [
                  for (final section in UsSection.values) ...[
                    if (section.index > 0) const SizedBox(width: SkySpace.sm),
                    SkyChip(
                      label: section.label,
                      tone: section == _section ? SkyChipTone.on : SkyChipTone.plain,
                      onTap: () => _select(section),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: SkySpace.md),
          Expanded(
            child: SkyEntrance(
              index: 2,
              child: SkySharedAxisSwitcher(
                reverse: _back,
                expand: true,
                child: KeyedSubtree(key: ValueKey<UsSection>(_section), child: _content(startDate)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
