import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/engine.dart';
import '../../sky/sky.dart';
import '../../space_scope.dart';
import '../../widgets/app_haptics.dart';
import 'letter_options.dart';
import 'letter_read_page.dart';
import 'letter_shelf.dart';
import 'letter_write_sheet.dart';
import 'letters_copy.dart';
import 'letters_keys.dart';
import 'widgets/capsule_card.dart';
import 'widgets/letter_feature_card.dart';
import 'widgets/letter_row.dart';
import 'widgets/letter_segments.dart';

@immutable
class LetterNotice {
  const LetterNotice(this.text, this.tone);

  final String text;
  final LetterNoticeTone tone;
}

class LettersPage extends StatefulWidget {
  const LettersPage({super.key});

  static const Duration lockTick = Duration(seconds: 30);
  static const Duration noticeTtl = Duration(milliseconds: 7000);
  static const int openedPreview = 3;

  static const SkyScene scene = SkyScene(
    stars: 50,
    moon: Offset(236, 104),
    sun: false,
    clouds: [SkyCloud(310, 110, scale: 0.9, opacity: 0.85), SkyCloud(60, 220, scale: 0.6, opacity: 0.5)],
  );

  static const SkyShootingStar arrival = SkyShootingStar(
    from: Offset(128, 10),
    control: Offset(172, 20),
    to: Offset(214, 42),
    angle: 18,
  );

  @override
  State<LettersPage> createState() => _LettersPageState();
}

class _LettersPageState extends State<LettersPage> {
  late final OurSpace _space = context.space;
  late final LettersRepository _letters = _space.letters;
  late Set<String> _mine = LettersWrittenHere.read(_space.store.settings);
  StreamSubscription<TableSnapshot<LetterRecord>>? _subscription;
  TableSnapshot<LetterRecord>? _snapshot;
  bool _failed = false;
  LetterNotice? _notice;
  Timer? _noticeTimer;
  Timer? _lockTimer;
  String? _openingId;
  int _now = DateTime.now().millisecondsSinceEpoch;
  LetterSegment _segment = LetterSegment.waiting;
  bool _segmentBack = false;

  @override
  void initState() {
    super.initState();
    _watch();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _noticeTimer?.cancel();
    _lockTimer?.cancel();
    super.dispose();
  }

  void _watch() {
    unawaited(_subscription?.cancel());
    _subscription = _letters.watch().listen(_onSnapshot, onError: _onError);
  }

  void _retry() {
    setState(() => _failed = false);
    _watch();
  }

  void _onError(Object error) {
    if (!mounted || _snapshot != null) return;
    setState(() => _failed = true);
  }

  void _onSnapshot(TableSnapshot<LetterRecord> snapshot) {
    if (!mounted) return;
    setState(() {
      _snapshot = snapshot;
      _failed = false;
      _now = DateTime.now().millisecondsSinceEpoch;
    });
    _syncLockTimer();
    if (snapshot.unlocked && snapshot.items.isNotEmpty) {
      unawaited(_letters.upgradePendingLocks(snapshot.items).catchError((Object error) => 0));
    }
  }

  bool _isLocked(LetterRecord letter) => letter.isLockedAt(_now);

  void _syncLockTimer() {
    final pending = (_snapshot?.items ?? const <LetterRecord>[]).any(_isLocked);
    if (pending && _lockTimer == null) {
      _lockTimer = Timer.periodic(LettersPage.lockTick, (timer) {
        if (!mounted) return;
        setState(() => _now = DateTime.now().millisecondsSinceEpoch);
        _syncLockTimer();
      });
    } else if (!pending && _lockTimer != null) {
      _lockTimer!.cancel();
      _lockTimer = null;
    }
  }

  void _showNotice(LetterNotice? notice) {
    _noticeTimer?.cancel();
    _noticeTimer = notice == null ? null : Timer(LettersPage.noticeTtl, () => _showNotice(null));
    if (mounted) setState(() => _notice = notice);
  }

  void _select(LetterSegment segment) {
    if (segment == _segment) return;
    setState(() {
      _segmentBack = segment.index < _segment.index;
      _segment = segment;
    });
  }

  Future<void> _open(LetterRecord letter) async {
    if (_openingId != null) return;
    _showNotice(null);
    if (letter.isSealed && !_isLocked(letter)) {
      setState(() => _openingId = letter.id);
      await Future<void>.delayed(Duration.zero);
      if (!mounted) return;
    }
    LetterOpening opening;
    try {
      opening = _letters.open(letter);
    } catch (_) {
      if (mounted) setState(() => _openingId = null);
      return;
    }
    if (!mounted) return;
    setState(() {
      _openingId = null;
      _now = DateTime.now().millisecondsSinceEpoch;
    });
    _syncLockTimer();
    if (!opening.isOpen) {
      _showNotice(LetterNotice(skyCalmText(opening.notice ?? ''), opening.tone ?? LetterNoticeTone.lock));
      return;
    }
    final mine = _mine.contains(letter.id);
    final first = !mine && !letter.isOpened;
    if (first) unawaited(_letters.markOpened(letter.id).catchError((Object error) => null));
    await skyPush<void>(
      context,
      (_) => LetterReadPage(
        letter: letter,
        content: opening.content ?? '',
        mine: mine,
        firstOpening: first,
        onDelete: () => _delete(letter),
        onWriteBack: () => unawaited(_write()),
      ),
    );
  }

  Future<bool> _delete(LetterRecord letter) async {
    final possessive = context.read<IdentityController>().partnerPossessive;
    final confirmed = await showSkyConfirm(
      context,
      title: LettersCopy.deleteTitle,
      message: LettersCopy.deleteMessage(possessive),
      confirmLabel: LettersCopy.deleteConfirm,
      cancelLabel: LettersCopy.deleteCancel,
      destructive: true,
      icon: SkyIcons.trash,
    );
    if (!confirmed) return false;
    AppHaptics.tap();
    try {
      await _letters.delete(letter.id);
    } catch (_) {
      _showNotice(const LetterNotice(LettersCopy.deleteFailed, LetterNoticeTone.error));
    }
    return true;
  }

  Future<void> _options(LetterRecord letter) async {
    final locked = _isLocked(letter);
    final action = await showLetterOptions(
      context,
      title: letter.title,
      subtitle: locked
          ? LettersCopy.opens(letter.lockDate, letter.lockBoundary, _now, night: context.sky.isNight)
          : LettersCopy.sealedWhen(letter.writtenAt, DateTime.now()),
      primary: LetterOptionsAction.open,
      primaryLabel: locked ? LettersCopy.tryToOpen : LettersCopy.readIt,
    );
    if (!mounted || action == null) return;
    switch (action) {
      case LetterOptionsAction.open:
        await _open(letter);
      case LetterOptionsAction.delete:
        await _delete(letter);
      case LetterOptionsAction.write:
        await _write();
    }
  }

  Future<void> _write() async {
    final id = await showLetterWriter(context);
    if (!mounted || id == null) return;
    setState(() {
      _mine = {..._mine, id};
      _segmentBack = LetterSegment.sent.index < _segment.index;
      _segment = LetterSegment.sent;
    });
  }

  double _progress(LetterRecord letter) {
    final boundary = letter.lockBoundary;
    final start = letter.writtenAt;
    if (boundary == null || boundary <= start) return 0;
    return ((_now - start) / (boundary - start)).clamp(0.0, 1.0);
  }

  SkyScene _scene(LetterShelf shelf) {
    final feature = shelf.feature;
    if (feature == null) return LettersPage.scene;
    final today = LettersCopy.daysBetween(DateTime.fromMillisecondsSinceEpoch(feature.writtenAt), DateTime.now()) <= 0;
    return today ? LettersPage.scene.copyWith(shootingStar: LettersPage.arrival) : LettersPage.scene;
  }

  @override
  Widget build(BuildContext context) {
    final identity = context.watch<IdentityController>();
    final snapshot = _snapshot;
    final letters = snapshot?.items ?? const <LetterRecord>[];
    final shelf = LetterShelf.sort(letters, mine: _mine, now: _now);
    return SkyScrollScaffold(
      scene: _scene(shelf),
      spacing: 0,
      topBar: SkyTopBar(
        kicker: LettersCopy.kicker,
        title: LettersCopy.title,
        trailing: SkyIconButton(
          key: LettersKeys.write,
          icon: SkyIcons.pen,
          tone: SkyIconButtonTone.rose,
          semanticLabel: LettersCopy.write,
          onPressed: () => unawaited(_write()),
        ),
      ),
      children: [
        _header(shelf, letters.isNotEmpty, snapshot?.unreadable ?? 0),
        _body(shelf, letters, identity.partnerName),
      ],
    );
  }

  Widget _header(LetterShelf shelf, bool any, int unreadable) {
    final notice = _notice;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (any) LetterSegments(selected: _segment, counts: shelf.countOf, onSelect: _select),
        if (notice != null)
          Padding(
            key: const ValueKey<String>('letters-notice-slot'),
            padding: const EdgeInsets.only(top: SkySpace.md),
            child: SkyEntrance(
              key: ValueKey<String>('letters-notice-${notice.text}'),
              offset: const Offset(0, -8),
              child: SkyNotice(
                key: LettersKeys.notice,
                text: notice.text,
                tone: notice.tone == LetterNoticeTone.error ? SkyNoticeTone.error : SkyNoticeTone.info,
                icon: notice.tone == LetterNoticeTone.error ? SkyIcons.alert : SkyIcons.lock,
                onDismiss: () => _showNotice(null),
                dismissLabel: LettersCopy.dismiss,
              ),
            ),
          ),
        if (unreadable > 0)
          Padding(
            key: const ValueKey<String>('letters-hidden-slot'),
            padding: const EdgeInsets.only(top: SkySpace.md),
            child: SkyNotice(
              key: LettersKeys.hidden,
              text: LettersCopy.hiddenLetters(unreadable),
              tone: SkyNoticeTone.warning,
              icon: SkyIcons.lock,
            ),
          ),
      ],
    );
  }

  Widget _body(LetterShelf shelf, List<LetterRecord> letters, String partner) {
    final t = context.sky;
    if (_failed) {
      return Padding(
        padding: const EdgeInsets.only(top: SkySpace.xl),
        child: SkyErrorState(onRetry: _retry),
      );
    }
    if (_snapshot == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 64),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SkySpinner(size: 22),
            const SizedBox(height: SkySpace.md),
            Text(LettersCopy.loading, textAlign: TextAlign.center, style: SkyType.bodySmall.copyWith(color: t.muted)),
          ],
        ),
      );
    }
    if (letters.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: SkySpace.md),
        child: SkyEmptyState(
          key: LettersKeys.empty,
          icon: SkyIcons.letter,
          tone: SkyTone.rose,
          title: LettersCopy.emptyTitle,
          message: LettersCopy.emptyMessage(partner),
          actionLabel: LettersCopy.writeFirst,
          onAction: () => unawaited(_write()),
        ),
      );
    }
    final List<Widget> view;
    switch (_segment) {
      case LetterSegment.waiting:
        view = _waiting(shelf, partner);
      case LetterSegment.opened:
        view = _opened(shelf, partner);
      case LetterSegment.sent:
        view = _sent(shelf, partner);
    }
    return Padding(
      padding: const EdgeInsets.only(top: SkySpace.lg),
      child: SkySharedAxisSwitcher(
        reverse: _segmentBack,
        child: Column(
          key: ValueKey<LetterSegment>(_segment),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: view,
        ),
      ),
    );
  }

  List<Widget> _waiting(LetterShelf shelf, String partner) {
    final t = context.sky;
    final now = DateTime.now();
    final blocks = <Widget>[];
    var index = 0;
    Widget enter(Key key, Widget child) => SkyEntrance(key: key, index: index++, child: child);

    if (shelf.waitingCount == 0) {
      blocks.add(
        enter(
          const ValueKey<String>('nothing-waiting'),
          const SkyEmptyState(
            icon: SkyIcons.sparkle,
            title: LettersCopy.nothingWaitingTitle,
            message: LettersCopy.nothingWaitingMessage,
          ),
        ),
      );
    }
    final feature = shelf.feature;
    if (feature != null) {
      blocks.add(
        enter(
          ValueKey<String>('feature-${feature.id}'),
          LetterFeatureCard(
            key: LettersKeys.feature,
            label: LettersCopy.newLabel(feature.writtenAt, now, night: t.isNight),
            title: feature.title,
            meta: LettersCopy.from(partner, LettersCopy.lowerFirst(LettersCopy.sealedWhen(feature.writtenAt, now))),
            busy: _openingId == feature.id,
            onBreak: () => unawaited(_open(feature)),
            onLongPress: () => unawaited(_options(feature)),
          ),
        ),
      );
    }
    final rest = shelf.waiting.skip(1).toList();
    if (rest.isNotEmpty) {
      blocks.add(const SizedBox(height: 20));
      blocks.add(enter(const ValueKey<String>('also-waiting'), const SkyLabel(LettersCopy.alsoWaiting)));
      for (final letter in rest) {
        blocks.add(
          enter(
            ValueKey<String>('waiting-${letter.id}'),
            _row(letter, '${LettersCopy.sealedWhen(letter.writtenAt, now)} · ${LettersCopy.readyToOpen}', sealed: true),
          ),
        );
      }
    }
    for (final letter in shelf.capsules) {
      blocks.add(const SizedBox(height: SkySpace.md));
      blocks.add(enter(ValueKey<String>('capsule-${letter.id}'), _capsule(letter, LettersCopy.capsuleFrom(partner))));
    }
    if (shelf.opened.isNotEmpty) {
      final seeAll = shelf.opened.length > LettersPage.openedPreview;
      blocks.add(SizedBox(height: seeAll ? 10 : 20));
      blocks.add(
        enter(
          const ValueKey<String>('opened-together'),
          Row(
            children: [
              const Expanded(child: SkyLabel(LettersCopy.openedTogether)),
              if (seeAll)
                SkyPressable(
                  onTap: () => _select(LetterSegment.opened),
                  semanticLabel: LettersCopy.seeAll,
                  excludeSemantics: true,
                  child: SkyTapTarget(
                    minWidth: SkySizes.minTap,
                    child: Text(
                      LettersCopy.seeAll,
                      style: SkyType.sans(12, weight: FontWeight.w600).copyWith(color: t.rose),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
      for (final letter in shelf.opened.take(LettersPage.openedPreview)) {
        blocks.add(enter(ValueKey<String>('opened-${letter.id}'), _row(letter, _openedLine(letter, now, partner))));
      }
    }
    return blocks;
  }

  List<Widget> _opened(LetterShelf shelf, String partner) {
    final now = DateTime.now();
    if (shelf.opened.isEmpty) {
      return const [
        SkyEntrance(
          child: SkyEmptyState(
            icon: SkyIcons.letter,
            tone: SkyTone.lavender,
            title: LettersCopy.noneOpenedTitle,
            message: LettersCopy.noneOpenedMessage,
          ),
        ),
      ];
    }
    var index = 0;
    return [
      for (final letter in shelf.opened)
        SkyEntrance(
          key: ValueKey<String>('opened-${letter.id}'),
          index: index++,
          child: _row(letter, _openedLine(letter, now, partner)),
        ),
    ];
  }

  List<Widget> _sent(LetterShelf shelf, String partner) {
    final now = DateTime.now();
    if (shelf.sent.isEmpty) {
      return [
        SkyEntrance(
          child: SkyEmptyState(
            icon: SkyIcons.pen,
            tone: SkyTone.rose,
            title: LettersCopy.noneSentTitle,
            message: LettersCopy.noneSentMessage(partner),
            actionLabel: LettersCopy.write,
            onAction: () => unawaited(_write()),
          ),
        ),
      ];
    }
    final blocks = <Widget>[];
    var index = 0;
    final capsules = [for (final letter in shelf.sent) if (_isLocked(letter)) letter];
    final rest = [for (final letter in shelf.sent) if (!_isLocked(letter)) letter];
    for (final letter in capsules) {
      if (blocks.isNotEmpty) blocks.add(const SizedBox(height: SkySpace.md));
      blocks.add(
        SkyEntrance(
          key: ValueKey<String>('sent-capsule-${letter.id}'),
          index: index++,
          child: _capsule(letter, LettersCopy.capsuleFor(partner)),
        ),
      );
    }
    if (capsules.isNotEmpty && rest.isNotEmpty) blocks.add(const SizedBox(height: SkySpace.sm));
    for (final letter in rest) {
      final sealed = LettersCopy.sealedWhen(letter.writtenAt, now);
      final state = letter.isOpened
          ? LettersCopy.lowerFirst(LettersCopy.openedWhen(letter.openedAt, now))
          : LettersCopy.waitingFor(partner);
      blocks.add(
        SkyEntrance(
          key: ValueKey<String>('sent-${letter.id}'),
          index: index++,
          child: _row(letter, '$sealed · $state', sealed: !letter.isOpened),
        ),
      );
    }
    return blocks;
  }

  String _openedLine(LetterRecord letter, DateTime now, String partner) {
    final written = LettersCopy.shortDate(DateTime.fromMillisecondsSinceEpoch(letter.writtenAt), now);
    if (_mine.contains(letter.id)) return '${LettersCopy.fromYou} · $written';
    return LettersCopy.from(partner, written);
  }

  Widget _row(LetterRecord letter, String subtitle, {bool sealed = false}) {
    return LetterRow(
      title: letter.title,
      subtitle: subtitle,
      sealed: sealed,
      busy: _openingId == letter.id,
      onTap: () => unawaited(_open(letter)),
      onLongPress: () => unawaited(_options(letter)),
    );
  }

  Widget _capsule(LetterRecord letter, String subtitle) {
    return CapsuleCard(
      title: letter.title,
      subtitle: subtitle,
      opens: LettersCopy.opens(letter.lockDate, letter.lockBoundary, _now, night: context.sky.isNight),
      progress: _progress(letter),
      onTap: () => unawaited(_open(letter)),
      onMore: () => unawaited(_options(letter)),
    );
  }
}
