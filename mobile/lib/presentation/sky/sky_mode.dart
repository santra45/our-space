import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../core/engine/storage/local_settings.dart';
import 'sky_tokens.dart';

typedef SkyClock = DateTime Function();

class SkyModeController extends ChangeNotifier {
  SkyModeController({LocalSettings? settings, SkyClock? clock, this.schedule = true})
    : _settings = settings ?? LocalSettings.memory(),
      _clock = clock ?? DateTime.now {
    _followsTime = _settings.getItem(followsTimeKey) != '0';
    _mode = _resolve();
    _armTimer();
  }

  static const String followsTimeKey = 'skyFollowsTime';
  static const int dayStartHour = 6;
  static const int nightStartHour = 18;

  final LocalSettings _settings;
  final SkyClock _clock;
  final bool schedule;
  late bool _followsTime;
  late SkyMode _mode;
  Timer? _timer;
  bool _disposed = false;

  bool get followsTime => _followsTime;
  SkyMode get mode => _mode;
  bool get isNight => _mode == SkyMode.night;
  SkyTokens get tokens => SkyTokens.of(_mode);

  static SkyMode modeAt(DateTime time) {
    final hour = time.hour;
    return hour >= dayStartHour && hour < nightStartHour ? SkyMode.day : SkyMode.night;
  }

  static DateTime nextChangeAfter(DateTime time) {
    final today = DateTime(time.year, time.month, time.day);
    final dayStart = today.add(const Duration(hours: dayStartHour));
    final nightStart = today.add(const Duration(hours: nightStartHour));
    if (time.isBefore(dayStart)) return dayStart;
    if (time.isBefore(nightStart)) return nightStart;
    return DateTime(time.year, time.month, time.day + 1, dayStartHour);
  }

  SkyMode _resolve() => _followsTime ? modeAt(_clock()) : SkyMode.night;

  Future<void> setFollowsTime(bool value) async {
    if (_disposed) return;
    if (value != _followsTime) {
      _followsTime = value;
      refresh(force: true);
    }
    await _settings.setItem(followsTimeKey, value ? '1' : '0');
  }

  void refresh({bool force = false}) {
    if (_disposed) return;
    final next = _resolve();
    final changed = next != _mode;
    _mode = next;
    _armTimer();
    if (changed || force) notifyListeners();
  }

  void _armTimer() {
    _timer?.cancel();
    _timer = null;
    if (!schedule || !_followsTime || _disposed) return;
    final now = _clock();
    final wait = nextChangeAfter(now).difference(now) + const Duration(seconds: 1);
    _timer = Timer(wait, refresh);
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}

class SkyModeScope extends StatefulWidget {
  const SkyModeScope({super.key, required this.controller, required this.child});

  final SkyModeController controller;
  final Widget child;

  static SkyModeController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SkyModeInherited>()?.notifier;

  static SkyModeController of(BuildContext context) {
    final controller = maybeOf(context);
    assert(controller != null, 'No SkyModeScope above this context.');
    return controller!;
  }

  @override
  State<SkyModeScope> createState() => _SkyModeScopeState();
}

class _SkyModeScopeState extends State<SkyModeScope> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) widget.controller.refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _SkyModeInherited(notifier: widget.controller, child: widget.child);
}

class _SkyModeInherited extends InheritedNotifier<SkyModeController> {
  const _SkyModeInherited({required super.notifier, required super.child});
}
