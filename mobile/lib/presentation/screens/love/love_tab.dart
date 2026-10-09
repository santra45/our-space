import 'package:flutter/widgets.dart';

import '../../widgets/our_widgets.dart';
import '../countdown/milestone_tracker.dart';
import '../daily/daily_question_card.dart';

class LoveTab extends StatelessWidget {
  const LoveTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const OurPage(children: [DailyQuestionCard(), MilestoneTracker()]);
  }
}
