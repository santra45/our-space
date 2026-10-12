import 'dart:async';

import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';

enum HapticKind { tick, tap, celebration, heartbeat }

typedef HapticHandler = void Function(HapticKind kind);

abstract final class AppHaptics {
  static HapticHandler handler = vibrateLikeWeb;

  static void tick() => handler(HapticKind.tick);
  static void tap() => handler(HapticKind.tap);
  static void celebration() => handler(HapticKind.celebration);
  static void heartbeat() => handler(HapticKind.heartbeat);

  static const Map<HapticKind, List<int>> webPatterns = {
    HapticKind.tick: [10],
    HapticKind.tap: [25],
    HapticKind.celebration: [20, 50, 20, 50, 40],
    HapticKind.heartbeat: [60, 120, 60],
  };

  static void vibrateLikeWeb(HapticKind kind) {
    unawaited(_vibrate(kind));
  }

  static Future<void> _vibrate(HapticKind kind) async {
    final pattern = webPatterns[kind]!;
    try {
      if (pattern.length == 1) {
        await Vibration.vibrate(duration: pattern.first);
      } else {
        await Vibration.vibrate(pattern: [0, ...pattern]);
      }
    } catch (_) {
      try {
        await (kind == HapticKind.tick ? HapticFeedback.selectionClick() : HapticFeedback.lightImpact());
      } catch (_) {}
    }
  }
}
