import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../core/engine.dart';
import '../screens/daily/daily_question_model.dart';
import '../screens/sky/sky_constellations.dart';
import '../sky/sky_mode.dart';
import 'sky_widget_host.dart';
import 'sky_widget_state.dart';

typedef SkyWidgetShow = Future<void> Function(SkyWidgetState state);

class SkyWidgetSync {
  SkyWidgetSync({required this.space, required this.sky, required this.show});

  final OurSpace space;
  final SkyModeController sky;
  final SkyWidgetShow show;

  DailyQuestionModel? _daily;
  VaultKey? _key;
  SkyWidgetState? _known;
  SkyWidgetState? _wanted;
  SkyWidgetState? _shown;
  Future<void>? _sending;
  bool _started = false;
  bool _closed = false;

  SkyWidgetState? get shown => _shown;

  Future<void> settled() async {
    while (true) {
      final sending = _sending;
      if (sending == null) return;
      await sending;
    }
  }

  void start() {
    if (_started || _closed) return;
    _started = true;
    space.vault.addListener(_onSpace);
    space.identity.addListener(_onSpace);
    sky.addListener(_refresh);
    _onSpace();
  }

  void _onSpace() {
    if (_closed) return;
    final vault = space.vault;
    final key = vault.key;
    if (!identical(key, _key)) {
      _key = key;
      _daily
        ?..removeListener(_refresh)
        ..dispose();
      _daily = key == null ? null : (DailyQuestionModel(space)..addListener(_refresh));
    }
    _daily?.bindTo(vault: vault, identity: space.identity);
    _refresh();
  }

  SkyWidgetState? _desired() {
    final night = sky.isNight;
    if (space.vault.isInitialized == false) return SkyWidgetState.empty(night: night);
    final daily = _daily;
    if (daily != null && daily.visible) {
      final series = ConstellationSeries.fromAnswered(daily.nights, today: daily.todayKey ?? dayKey());
      return SkyWidgetState.forSeries(series, night: night);
    }
    return _known?.inMode(night: night);
  }

  void _refresh() {
    if (_closed) return;
    final next = _desired();
    if (next == null) return;
    _known = next;
    _wanted = next;
    if (_sending == null && next != _shown) _sending = _send();
  }

  Future<void> _send() async {
    try {
      while (!_closed) {
        final next = _wanted;
        if (next == null || next == _shown) break;
        try {
          await show(next);
          _shown = next;
        } catch (_) {
          if (identical(_wanted, next)) break;
        }
      }
    } finally {
      _sending = null;
    }
  }

  void dispose() {
    if (_closed) return;
    _closed = true;
    if (_started) {
      space.vault.removeListener(_onSpace);
      space.identity.removeListener(_onSpace);
      sky.removeListener(_refresh);
    }
    _daily
      ?..removeListener(_refresh)
      ..dispose();
    _daily = null;
  }
}

class SkyWidgetLink extends StatefulWidget {
  const SkyWidgetLink({super.key, required this.space, required this.sky, this.publisher, required this.child});

  final OurSpace space;
  final SkyModeController sky;
  final SkyWidgetPublisher? publisher;
  final Widget child;

  @override
  State<SkyWidgetLink> createState() => _SkyWidgetLinkState();
}

class _SkyWidgetLinkState extends State<SkyWidgetLink> {
  SkyWidgetSync? _sync;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void didUpdateWidget(covariant SkyWidgetLink oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.space, widget.space) ||
        !identical(oldWidget.sky, widget.sky) ||
        !identical(oldWidget.publisher, widget.publisher)) {
      _sync?.dispose();
      _connect();
    }
  }

  void _connect() {
    final publisher = widget.publisher;
    _sync = publisher == null
        ? null
        : (SkyWidgetSync(space: widget.space, sky: widget.sky, show: publisher.publish)..start());
  }

  @override
  void dispose() {
    _sync?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
