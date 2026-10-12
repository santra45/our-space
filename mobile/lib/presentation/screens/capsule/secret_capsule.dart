import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/engine.dart';
import '../../space_scope.dart';
import '../../widgets/our_widgets.dart';
import 'capsule_copy.dart';
import 'letter_envelope.dart';
import 'spring_entrance.dart';
import 'write_letter_card.dart';

@immutable
class CapsuleNotice {
  const CapsuleNotice(this.text, this.tone);

  final String text;
  final LetterNoticeTone tone;
}

class SecretCapsule extends StatefulWidget {
  const SecretCapsule({super.key});

  static const Duration lockTick = Duration(seconds: 30);
  static const Duration noticeTtl = Duration(milliseconds: 7000);

  @override
  State<SecretCapsule> createState() => _SecretCapsuleState();
}

class _SecretCapsuleState extends State<SecretCapsule> {
  final LetterDraft _draft = LetterDraft();
  late final DateTime _today = startOfLocalDay(DateTime.now());
  late final LettersRepository _letters = context.space.letters;
  StreamSubscription<TableSnapshot<LetterRecord>>? _subscription;
  TableSnapshot<LetterRecord>? _snapshot;
  CapsuleNotice? _notice;
  Timer? _noticeTimer;
  Timer? _lockTimer;
  String? _openingId;
  int _now = DateTime.now().millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    _subscription = _letters.watch().listen(_onSnapshot, onError: (Object error) {});
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _noticeTimer?.cancel();
    _lockTimer?.cancel();
    super.dispose();
  }

  void _onSnapshot(TableSnapshot<LetterRecord> snapshot) {
    if (!mounted) return;
    setState(() {
      _snapshot = snapshot;
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
      _lockTimer = Timer.periodic(SecretCapsule.lockTick, (timer) {
        if (!mounted) return;
        setState(() => _now = DateTime.now().millisecondsSinceEpoch);
        _syncLockTimer();
      });
    } else if (!pending && _lockTimer != null) {
      _lockTimer!.cancel();
      _lockTimer = null;
    }
  }

  void _showNotice(CapsuleNotice? notice) {
    _noticeTimer?.cancel();
    _noticeTimer = notice == null ? null : Timer(SecretCapsule.noticeTtl, () => _showNotice(null));
    if (mounted) setState(() => _notice = notice);
  }

  Future<void> _openLetter(LetterRecord letter) async {
    if (_openingId != null) return;
    AppHaptics.tap();
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
      _showNotice(CapsuleNotice(opening.notice ?? '', opening.tone ?? LetterNoticeTone.lock));
      return;
    }
    await showOurModal<void>(
      context: context,
      backdrop: OurBackdropTone.black60,
      entrance: OurModalEntrance.none,
      barrierDismissible: true,
      builder: (envelopeContext) => LetterEnvelope(
        letter: letter,
        content: opening.content ?? '',
        onClose: () => Navigator.of(envelopeContext).pop(),
        onOpened: () => unawaited(_letters.markOpened(letter.id).catchError((Object error) => null)),
        onDelete: () async {
          final asked = await _deleteLetter(letter.id);
          if (asked && envelopeContext.mounted) Navigator.of(envelopeContext).pop();
        },
      ),
    );
  }

  Future<bool> _deleteLetter(String id) async {
    final possessive = context.read<IdentityController>().partnerPossessive;
    final confirmed = await showOurConfirm(context, message: CapsuleCopy.deleteQuestion(possessive));
    if (!confirmed) return false;
    AppHaptics.tap();
    try {
      await _letters.delete(id);
    } catch (_) {
      _showNotice(const CapsuleNotice(CapsuleCopy.deleteFailed, LetterNoticeTone.error));
    }
    return true;
  }

  void _openWriteModal({required bool fromHeader}) {
    if (fromHeader) {
      AppHaptics.tap();
      _draft.saveError = '';
    }
    showOurModal<void>(
      context: context,
      backdrop: OurBackdropTone.black50,
      entrance: OurModalEntrance.none,
      builder: (modalContext) => SpringEntrance(
        spec: EntranceSpec.writeModal,
        child: WriteLetterCard(draft: _draft, minDate: _today),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final identity = context.watch<IdentityController>();
    final snapshot = _snapshot;
    final letters = snapshot?.items ?? const <LetterRecord>[];
    final unreadable = snapshot?.unreadable ?? 0;

    return OurPage(
      children: [
        OurSectionHeader(
          title: CapsuleCopy.title,
          subtitle: CapsuleCopy.subtitle,
          trailing: BouncyButton(
            label: CapsuleCopy.writeLetter,
            icon: AppIcons.plus,
            small: true,
            pill: true,
            onPressed: () => _openWriteModal(fromHeader: true),
          ),
        ),
        if (_notice != null) _noticeBanner(_notice!),
        if (unreadable > 0)
          OurNotice(
            tone: NoticeTone.warning,
            icon: AppIcons.shieldAlert,
            iconSize: 14,
            iconColor: AppColors.amber800,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            textStyle: Tw.px11.relaxed,
            message: CapsuleCopy.hiddenLetters(unreadable),
          ),
        if (snapshot == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 64),
            child: Text(CapsuleCopy.loading, textAlign: TextAlign.center, style: Tw.xs.c(AppColors.slate400)),
          )
        else if (letters.isEmpty)
          OurEmptyState(
            icon: AppIcons.mail,
            title: CapsuleCopy.emptyTitle,
            message: CapsuleCopy.emptyMessage(identity.partnerName),
            action: BouncyButton(
              label: CapsuleCopy.writeFirst,
              small: true,
              pill: true,
              onPressed: () => _openWriteModal(fromHeader: false),
            ),
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: spaced([for (final letter in letters) _letterCard(letter)], 12),
          ),
      ],
    );
  }

  Widget _noticeBanner(CapsuleNotice notice) {
    final error = notice.tone == LetterNoticeTone.error;
    return OurNotice(
      key: const ValueKey('capsule-notice'),
      tone: error ? NoticeTone.error : NoticeTone.info,
      icon: error ? AppIcons.shieldAlert : AppIcons.lock,
      iconSize: 14,
      iconColor: error ? AppColors.rose700 : AppColors.slate600,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      textStyle: Tw.px11.relaxed,
      message: notice.text,
      onDismiss: () => _showNotice(null),
    );
  }

  Widget _letterCard(LetterRecord letter) {
    final locked = _isLocked(letter);
    final lockDate = letter.lockDate;
    return GlassCard(
      key: ValueKey(letter.id),
      opacity: locked ? 0.8 : 1,
      onTap: () => _openLetter(letter),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                children: [
                  OurIconCircle(
                    icon: locked ? AppIcons.lock : (letter.isOpened ? AppIcons.mailOpen : AppIcons.mail),
                    size: 40,
                    iconSize: 20,
                    radius: AppRadii.x2l,
                    background: locked ? AppColors.slate200 : AppColors.blush100,
                    foreground: locked ? AppColors.slate500 : AppColors.blush600,
                    shadows: AppShadows.sm,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          letter.title,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: Tw.sm.bold.c(AppColors.slate800),
                        ),
                        Text(
                          CapsuleCopy.writtenLine(letter, isLocked: locked),
                          style: Tw.px11.c(AppColors.slate400),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (locked && lockDate != null)
            OurPill.slate(label: formatTimeRemaining(lockDate, now: _now), icon: AppIcons.clock)
          else
            Text(
              _openingId == letter.id ? CapsuleCopy.unsealing : CapsuleCopy.readLetter,
              style: Tw.xs.semibold.c(AppColors.blush600),
            ),
          const SizedBox(width: 12),
          OurIconButton(
            icon: AppIcons.trash2,
            size: 32,
            iconSize: 16,
            radius: AppRadii.xl,
            haptic: false,
            semanticLabel: 'Delete love letter',
            onPressed: () => _deleteLetter(letter.id),
          ),
        ],
      ),
    );
  }
}
