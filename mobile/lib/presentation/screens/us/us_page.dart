import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/engine.dart';
import '../../app_shell.dart';
import '../../sky/sky.dart';
import '../bucketlist/dreams_section.dart';
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

  static const double skyHeight = 380;

  static const SkyScene scene = SkyScene(
    stars: 50,
    moon: Offset(200, 104),
    sun: false,
    clouds: [SkyCloud(300, 110, scale: 0.9, opacity: 0.85), SkyCloud(60, 230, scale: 0.6, opacity: 0.5)],
  );

  final UsSection initialSection;
  final LoveClock? clock;

  @override
  State<UsPage> createState() => _UsPageState();
}

class _UsPageState extends State<UsPage> {
  late final LiveLoveCounter _counter = LiveLoveCounter(clock: widget.clock);
  final ScrollController _scroll = ScrollController();
  final Map<UsSection, GlobalKey> _anchors = {for (final section in UsSection.values) section: GlobalKey()};
  UsSection? _pending;
  bool _revealQueued = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialSection != UsSection.story) {
      _pending = widget.initialSection;
      _queueReveal();
    }
  }

  @override
  void dispose() {
    _counter.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _queueReveal() {
    if (_revealQueued || _pending == null) return;
    _revealQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _revealQueued = false;
      final section = _pending;
      final target = section == null ? null : _anchors[section]?.currentContext;
      if (!mounted || target == null) return;
      unawaited(Scrollable.ensureVisible(target, alignment: 0, duration: Duration.zero));
    });
  }

  bool _onLayout(SizeChangedLayoutNotification notification) {
    _queueReveal();
    return false;
  }

  bool _onScroll(ScrollStartNotification notification) {
    if (notification.dragDetails != null) _pending = null;
    return false;
  }

  String _startDate(BuildContext context) {
    final configured = context.watch<VaultService>().config?.startDate ?? '';
    if (configured.isNotEmpty) return configured;
    return toLocalDateInput(DateTime.fromMillisecondsSinceEpoch(_counter.now()));
  }

  void _changeDay(String startDate) {
    unawaited(showTogetherDateSheet(context, startDate: startDate));
  }

  Widget _anchored(UsSection section, Widget child) => KeyedSubtree(key: _anchors[section], child: child);

  @override
  Widget build(BuildContext context) {
    final startDate = _startDate(context);
    _counter.track(startDate);
    final now = DateTime.fromMillisecondsSinceEpoch(_counter.now());
    final start = parseLocalDate(startDate) ?? now;
    return NotificationListener<ScrollStartNotification>(
      onNotification: _onScroll,
      child: NotificationListener<SizeChangedLayoutNotification>(
        onNotification: _onLayout,
        child: SkyScrollScaffold(
          controller: _scroll,
          scene: UsPage.scene,
          skyHeight: UsPage.skyHeight,
          padding: const EdgeInsets.fromLTRB(SkySpace.gutter, SkySpace.gutter, SkySpace.gutter, 0),
          spacing: 0,
          topBar: SkyTopBar(
            kicker: UsCopy.kicker,
            title: UsCopy.title,
            trailing: const Padding(padding: EdgeInsets.only(top: 6), child: ShellAvatar()),
          ),
          children: [
            _anchored(
              UsSection.story,
              TogetherHero(key: UsKeys.hero, counter: _counter, since: start, onTap: () => _changeDay(startDate)),
            ),
            Padding(
              padding: const EdgeInsets.only(top: SkySpace.md),
              child: ListenableBuilder(
                listenable: _counter,
                builder: (context, _) => UpcomingRow(
                  key: UsKeys.upcoming,
                  items: upcomingMilestones(startDate, DateTime.fromMillisecondsSinceEpoch(_counter.now())),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: SkySpace.sectionGap - UpcomingRow.shadowRoom),
              child: SizeChangedLayoutNotifier(
                child: OurConstellation(
                  key: UsKeys.constellation,
                  counter: _counter,
                  startDate: startDate,
                  onChangeDay: () => _changeDay(startDate),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: SkySpace.sectionGap),
              child: _anchored(UsSection.dreams, const SizeChangedLayoutNotifier(child: DreamsSection(key: UsKeys.dreams))),
            ),
            Padding(
              padding: const EdgeInsets.only(top: SkySpace.sectionGap),
              child: _anchored(UsSection.dates, const DateRoulette(key: UsKeys.dateNight)),
            ),
          ],
        ),
      ),
    );
  }
}
