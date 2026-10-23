import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/engine.dart';
import '../../sky/sky.dart';
import '../../widgets/app_haptics.dart';
import '../../widgets/confetti_burst.dart';
import 'love_tally.dart';
import 'love_week.dart';
import 'widgets/love_counts.dart';
import 'widgets/love_heart.dart';

abstract final class LoveSheetCopy {
  static const String title = 'Send a little love';
  static const String send = 'Hold to send';
  static const String holding = 'Keep holding';
  static const String sending = 'On its way';
  static const String sent = 'Sent with love';
  static const String retry = 'Hold to try again';
  static const String hint = 'Press and hold the heart until it fills.';
  static const String failed = 'That one slipped away. Hold the heart to try again.';
  static const String locked = 'Unlock Our Space first, then send your love.';
  static const String sentThisWeek = 'sent this week';
  static const String sentYouLove = ' sent you love';
  static const String yesterday = 'Yesterday';

  static String forName(String name) => 'For $name';

  static String reaches(String name, PronounSet grammar) =>
      'It reaches $name right away, wherever ${grammar.subject} ${grammar.isVerb}.';

  static String sendTo(String name) => 'Send love to $name';

  static String fromName(String name) => 'from $name';

  static String arrived(String name) => '${lead(name)} has it now.';

  static String saved(String name) => '${lead(name)} will feel it the moment you two connect.';

  static String waiting(String name) => 'When $name sends love, it lands here.';

  static String latest(String name, String? when) =>
      when == null ? '${lead(name)} sent you love' : '${lead(name)} sent you love, $when';

  static String lead(String text) => text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

  static String when(DateTime at, DateTime now, String clock) {
    final day = DateTime(at.year, at.month, at.day);
    final today = DateTime(now.year, now.month, now.day);
    final days = (today.difference(day).inHours / 24).round();
    if (days <= 0) return clock;
    if (days == 1) return yesterday;
    return formatMonthDay(at);
  }
}

Future<void> showLoveSheet(BuildContext context) {
  return showSkySheet<void>(
    context: context,
    padding: const EdgeInsets.fromLTRB(SkySpace.xl, 0, SkySpace.xl, SkySpace.gutter),
    builder: (_) => const LoveSheet(),
  );
}

typedef LoveSender = Future<bool> Function();

enum LovePhase { ready, holding, sending, sent, failed }

enum LoveNoteTone { hint, love, error }

class LoveSheet extends StatefulWidget {
  const LoveSheet({super.key, this.send, this.clock});

  static const Duration cooldown = Duration(seconds: 1);
  static const Duration noteLife = Duration(seconds: 5);

  final LoveSender? send;
  final DateTime Function()? clock;

  @override
  State<LoveSheet> createState() => _LoveSheetState();
}

class _LoveSheetState extends State<LoveSheet> {
  late final OurSpace _space;
  late final VaultService _vault;
  final GlobalKey _heartKey = GlobalKey();

  StreamSubscription<void>? _watch;
  List<Map<String, Object?>>? _rows;
  LoveWeek? _week;
  int _firstDay = 0;
  bool _loading = false;
  bool _again = false;
  LovePhase _phase = LovePhase.ready;
  String? _note;
  LoveNoteTone _tone = LoveNoteTone.hint;
  Timer? _cooldown;
  Timer? _noteTimer;

  bool get _canHold => _phase != LovePhase.sending && _phase != LovePhase.sent;

  DateTime _now() => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _space = context.read<OurSpace>();
    _vault = context.read<VaultService>();
    _watch = _space.store.watchTable(loveBurstsTable).listen((_) => unawaited(_reload()));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _firstDay = MaterialLocalizations.of(context).firstDayOfWeekIndex;
  }

  @override
  void dispose() {
    unawaited(_watch?.cancel());
    _cooldown?.cancel();
    _noteTimer?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    if (_loading) {
      _again = true;
      return;
    }
    _loading = true;
    try {
      do {
        _again = false;
        final key = _vault.key;
        if (key == null) return;
        final List<Map<String, Object?>> rows;
        try {
          rows = await _space.store.listDecrypted(loveBurstsTable, key);
        } catch (_) {
          return;
        }
        if (!mounted) return;
        final week = _countWeek(rows);
        setState(() {
          _rows = rows;
          _week = week;
        });
      } while (_again && mounted);
    } finally {
      _loading = false;
    }
  }

  LoveWeek _countWeek(List<Map<String, Object?>> rows) {
    final identity = context.read<IdentityController>();
    final tally = LoveTally.fromRows(
      rows,
      ownRecordId: _space.loveBursts.ownBurstRecordId,
      myOwnerIds: identity.myOwnerIds,
    );
    final settings = _space.store.settings;
    final stored = settings.getItem(LoveWeek.storageKey);
    final week = LoveWeek.track(
      LoveWeek.decode(stored),
      tally.mine,
      now: _now(),
      firstDay: _firstDay,
    );
    final encoded = week.encode();
    if (encoded != stored) unawaited(settings.setItem(LoveWeek.storageKey, encoded).catchError((Object _) {}));
    return week;
  }

  void _say(String text, LoveNoteTone tone) {
    _noteTimer?.cancel();
    setState(() {
      _note = text;
      _tone = tone;
    });
    _noteTimer = Timer(LoveSheet.noteLife, () {
      if (mounted) setState(() => _note = null);
    });
  }

  void _quiet() {
    _noteTimer?.cancel();
    _noteTimer = null;
    _note = null;
  }

  void _onHoldStart() {
    setState(() {
      _phase = LovePhase.holding;
      _quiet();
    });
  }

  void _onHoldCancel() {
    setState(() => _phase = LovePhase.ready);
  }

  void _onHint() {
    _phase = LovePhase.ready;
    _say(LoveSheetCopy.hint, LoveNoteTone.hint);
  }

  void _celebrate() {
    final t = context.sky;
    final screen = MediaQuery.sizeOf(context);
    var originX = 0.5;
    var originY = 0.6;
    final box = _heartKey.currentContext?.findRenderObject();
    if (box is RenderBox && box.hasSize && screen.width > 0 && screen.height > 0) {
      final center = box.localToGlobal(Offset(box.size.width / 2, LoveHeart.box / 2));
      originX = (center.dx / screen.width).clamp(0.0, 1.0);
      originY = (center.dy / screen.height).clamp(0.0, 1.0);
    }
    ConfettiBurst.fire(context, [
      ConfettiOptions(
        particleCount: 44,
        spread: 84,
        startVelocity: 36,
        originX: originX,
        originY: originY,
        shapes: const [ConfettiShape.heart, ConfettiShape.circle],
        colors: [t.rose, SkyTokens.roseLight, t.roseDeep, t.gold, t.lavender],
        scalar: 1.15,
      ),
    ]);
  }

  Future<void> _send() async {
    if (!_canHold) return;
    final sync = context.read<SyncService>();
    final identity = context.read<IdentityController>();
    final unlocked = _vault.isUnlocked;
    AppHaptics.celebration();
    _celebrate();
    _cooldown?.cancel();
    setState(() {
      _phase = LovePhase.sending;
      _quiet();
    });
    var ok = false;
    try {
      ok = await (widget.send ?? sync.sendLoveBurst)();
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    final name = identity.partnerName;
    _phase = ok ? LovePhase.sent : LovePhase.failed;
    if (ok) {
      _say(sync.peerAuthorized ? LoveSheetCopy.arrived(name) : LoveSheetCopy.saved(name), LoveNoteTone.love);
      _cooldown = Timer(LoveSheet.cooldown, () {
        if (mounted && _phase == LovePhase.sent) setState(() => _phase = LovePhase.ready);
      });
    } else {
      _say(unlocked ? LoveSheetCopy.failed : LoveSheetCopy.locked, LoveNoteTone.error);
    }
  }

  String get _holdLabel {
    switch (_phase) {
      case LovePhase.ready:
        return LoveSheetCopy.send;
      case LovePhase.holding:
        return LoveSheetCopy.holding;
      case LovePhase.sending:
        return LoveSheetCopy.sending;
      case LovePhase.sent:
        return LoveSheetCopy.sent;
      case LovePhase.failed:
        return LoveSheetCopy.retry;
    }
  }

  Widget _subtitle(SkyTokens t, String fallback, bool motion) {
    final note = _note;
    final error = note != null && _tone == LoveNoteTone.error;
    final color = note == null
        ? t.muted
        : _tone == LoveNoteTone.hint
            ? t.text
            : t.rose;
    final text = note ?? fallback;
    final line = Text.rich(
      TextSpan(
        children: [
          if (error)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: SkyIcon(SkyIcons.alert, size: 14, color: t.rose),
              ),
            ),
          TextSpan(text: text),
        ],
      ),
      key: ValueKey<String>('love-note-$text'),
      textAlign: TextAlign.center,
      style: SkyType.sans(13, height: 1.45).copyWith(color: color),
    );
    return Semantics(
      liveRegion: true,
      container: true,
      child: AnimatedSwitcher(
        duration: motion ? SkyMotion.quick : Duration.zero,
        switchInCurve: SkyMotion.standard,
        child: line,
      ),
    );
  }

  Widget _latest(SkyTokens t, IdentityController identity, LoveTally? tally) {
    final name = identity.partnerName;
    final initial = identity.partner == null ? null : SkyAvatar.initialOf(name);
    if (tally == null) return const SizedBox(height: LoveNote.height);
    final at = tally.lastReceivedAt;
    if (!tally.hasReceived) {
      return LoveNote(
        key: const ValueKey<String>('love-latest-none'),
        leading: LoveMark(initial: initial),
        text: LoveSheetCopy.waiting(name),
        quiet: true,
      );
    }
    String? when;
    if (at != null) {
      final date = DateTime.fromMillisecondsSinceEpoch(at);
      final clock = MaterialLocalizations.of(context).formatTimeOfDay(
        TimeOfDay.fromDateTime(date),
        alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
      );
      when = LoveSheetCopy.when(date, _now(), clock);
    }
    return SkyEntrance(
      key: ValueKey<String>('love-latest-$at-${tally.received}'),
      child: LoveNote(
        leading: LoveMark(initial: initial),
        strong: LoveSheetCopy.lead(name),
        text: LoveSheetCopy.sentYouLove,
        trailing: when,
        semanticLabel: LoveSheetCopy.latest(name, when),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final motion = skyMotionAllowed(context);
    final identity = context.watch<IdentityController>();
    final name = identity.partnerName;
    final rows = _rows;
    final tally = rows == null
        ? null
        : LoveTally.fromRows(
            rows,
            ownRecordId: _space.loveBursts.ownBurstRecordId,
            myOwnerIds: identity.myOwnerIds,
          );
    final holdLabel = _holdLabel;
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      clipBehavior: Clip.none,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SkyEntrance(
            child: SkyLabel(LoveSheetCopy.forName(name), icon: SkyIcons.heart, tone: SkyTone.rose, center: true),
          ),
          const SizedBox(height: 6),
          SkyEntrance(
            index: 1,
            child: Semantics(
              header: true,
              child: Text(
                LoveSheetCopy.title,
                textAlign: TextAlign.center,
                style: SkyType.serif(30, weight: FontWeight.w500, height: 1.2).copyWith(color: t.text),
              ),
            ),
          ),
          const SizedBox(height: 6),
          SkyEntrance(
            index: 2,
            child: _subtitle(t, LoveSheetCopy.reaches(name, identity.partnerGrammar), motion),
          ),
          const SizedBox(height: SkySpace.sm),
          SkyEntrance(
            index: 3,
            offset: Offset.zero,
            child: Center(
              child: LoveHeart(
                key: _heartKey,
                semanticLabel: LoveSheetCopy.sendTo(name),
                semanticHint: LoveSheetCopy.send,
                enabled: _canHold,
                onHoldStart: _onHoldStart,
                onHoldCancel: _onHoldCancel,
                onHint: _onHint,
                onSend: () => unawaited(_send()),
              ),
            ),
          ),
          SkyEntrance(
            index: 4,
            child: Semantics(
              liveRegion: true,
              child: AnimatedSwitcher(
                duration: motion ? SkyMotion.quick : Duration.zero,
                switchInCurve: SkyMotion.standard,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.92, end: 1).animate(animation),
                    child: child,
                  ),
                ),
                child: Text(
                  holdLabel.toUpperCase(),
                  key: ValueKey<String>('love-hold-$holdLabel'),
                  textAlign: TextAlign.center,
                  style: SkyType.hold.copyWith(color: t.rose),
                ),
              ),
            ),
          ),
          const SizedBox(height: SkySpace.xl),
          SkyEntrance(
            index: 5,
            child: LoveCounts(
              sent: _week?.count,
              received: tally?.received,
              sentLabel: LoveSheetCopy.sentThisWeek,
              receivedLabel: LoveSheetCopy.fromName(name),
            ),
          ),
          const SizedBox(height: 20),
          SkyEntrance(index: 6, child: _latest(t, identity, tally)),
        ],
      ),
    );
  }
}
