import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../../core/engine.dart';
import '../../widgets/our_widgets.dart';
import 'live_love_counter.dart';
import 'milestone_list_card.dart';
import 'together_card.dart';
import 'upcoming_milestones.dart';

class MilestoneTracker extends StatefulWidget {
  const MilestoneTracker({super.key, this.clock});

  final LoveClock? clock;

  @override
  State<MilestoneTracker> createState() => _MilestoneTrackerState();
}

class _MilestoneTrackerState extends State<MilestoneTracker> {
  late final LiveLoveCounter _counter = LiveLoveCounter(clock: widget.clock);

  @override
  void dispose() {
    _counter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final configured = context.watch<VaultService>().config?.startDate ?? '';
    final startDate = configured.isNotEmpty
        ? configured
        : toLocalDateInput(DateTime.fromMillisecondsSinceEpoch(_counter.now()));
    _counter.track(startDate);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: spaced([
        ListenableBuilder(
          listenable: _counter,
          builder: (context, _) {
            final milestones = calculateNextMilestone(
              startDate,
              DateTime.fromMillisecondsSinceEpoch(_counter.now()),
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: spaced([
                TogetherCard(startDate: startDate, duration: _counter.value),
                if (milestones != null) UpcomingMilestones(milestones: milestones),
              ], 20),
            );
          },
        ),
        const MilestoneListCard(),
      ], 20),
    );
  }
}
