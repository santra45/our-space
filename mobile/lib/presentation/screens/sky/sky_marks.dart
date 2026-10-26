import 'package:flutter/widgets.dart';

import '../../sky/sky.dart';

class SkyPresenceRing extends StatelessWidget {
  const SkyPresenceRing({super.key});

  static const double size = 56;

  @override
  Widget build(BuildContext context) {
    final ring = SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: SkyTokens.presence.withValues(alpha: 0.3), width: 0.8),
        ),
        child: Center(
          child: SizedBox.square(
            dimension: 40,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: SkyTokens.presence.withValues(alpha: 0.75), width: 1.2),
              ),
            ),
          ),
        ),
      ),
    );
    return IgnorePointer(
      child: skyMotionAllowed(context) ? SkyPulse(minScale: 0.94, maxScale: 1.06, child: ring) : ring,
    );
  }
}
