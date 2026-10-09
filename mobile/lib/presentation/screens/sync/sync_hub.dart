import 'package:flutter/widgets.dart';

import '../../widgets/our_widgets.dart';

Future<void> showSyncHub(BuildContext context) {
  return showOurModal<void>(
    context: context,
    backdrop: OurBackdropTone.black50,
    entrance: OurModalEntrance.popSoft,
    builder: (_) => const SyncHub(),
  );
}

class SyncHub extends StatelessWidget {
  const SyncHub({super.key});

  @override
  Widget build(BuildContext context) {
    return OurModalCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Pair & Sync Hub', textAlign: TextAlign.center, style: Tw.base.bold.c(AppColors.slate800)),
          Text(
            'Your two phones, straight to each other',
            textAlign: TextAlign.center,
            style: Tw.xs.c(AppColors.slate400),
          ),
        ],
      ),
    );
  }
}
