import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';

class HapticsService {
  HapticsService._();
  static final HapticsService instance = HapticsService._();

  bool _hasCustomVibrator = false;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    try {
      _hasCustomVibrator = await Vibration.hasCustomVibrationsSupport();
    } catch (_) {
      _hasCustomVibrator = false;
    }
    _initialized = true;
  }

  Future<void> tick() async {
    try {
      await HapticFeedback.selectionClick();
    } catch (_) {}
  }

  Future<void> tap() async {
    try {
      await HapticFeedback.lightImpact();
    } catch (_) {}
  }

  Future<void> heartbeat() async {
    try {
      await init();
      if (_hasCustomVibrator) {
        await Vibration.vibrate(
          pattern: [0, 60, 120, 60],
          intensities: [0, 180, 0, 255],
        );
      } else {
        await HapticFeedback.mediumImpact();
        await Future.delayed(const Duration(milliseconds: 140));
        await HapticFeedback.heavyImpact();
      }
    } catch (_) {
      HapticFeedback.mediumImpact();
    }
  }

  Future<void> celebration() async {
    try {
      await init();
      if (_hasCustomVibrator) {
        await Vibration.vibrate(
          pattern: [0, 20, 50, 20, 50, 40],
          intensities: [0, 128, 0, 180, 0, 255],
        );
      } else {
        await HapticFeedback.heavyImpact();
        await Future.delayed(const Duration(milliseconds: 60));
        await HapticFeedback.heavyImpact();
      }
    } catch (_) {
      HapticFeedback.heavyImpact();
    }
  }
}
