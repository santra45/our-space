import 'package:flutter/material.dart';

import '../../app_shell.dart';
import '../../legacy_area.dart';
import '../../sky/sky.dart';
import '../../widgets/our_page.dart';
import '../bucketlist/bucket_list.dart';
import '../countdown/milestone_tracker.dart';
import '../roulette/date_roulette.dart';

enum UsSection { story, dreams, dates }

extension UsSectionInfo on UsSection {
  String get label {
    switch (this) {
      case UsSection.story:
        return 'Our story';
      case UsSection.dreams:
        return 'Dreams';
      case UsSection.dates:
        return 'Date night';
    }
  }
}

class UsPage extends StatefulWidget {
  const UsPage({super.key, this.initialSection = UsSection.story});

  final UsSection initialSection;

  @override
  State<UsPage> createState() => _UsPageState();
}

class _UsPageState extends State<UsPage> {
  late UsSection _section = widget.initialSection;
  bool _back = false;

  void _select(UsSection section) {
    if (section == _section) return;
    setState(() {
      _back = section.index < _section.index;
      _section = section;
    });
  }

  Widget _content() {
    switch (_section) {
      case UsSection.story:
        return const OurPage(spacing: 0, children: [MilestoneTracker()]);
      case UsSection.dreams:
        return const BucketList();
      case UsSection.dates:
        return const DateRoulette();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SkyScaffold(
      scene: SkyScene.page,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SkyEntrance(
            child: SkyTopBar(kicker: 'The two of us', title: 'Us', trailing: ShellAvatar()),
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
              child: LegacyArea(
                child: SkySharedAxisSwitcher(
                  reverse: _back,
                  expand: true,
                  child: KeyedSubtree(key: ValueKey<UsSection>(_section), child: _content()),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
