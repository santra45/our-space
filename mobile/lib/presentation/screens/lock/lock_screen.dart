import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/engine.dart';
import '../../files/vault_files.dart';
import '../../space_scope.dart';
import '../../widgets/our_widgets.dart';

enum LockMode { unlock, join, setup, restore }

LockMode? defaultLockMode(VaultCheckState state, {bool inviteHasSalt = false, bool installed = false}) {
  if (state == VaultCheckState.present) return LockMode.unlock;
  if (state != VaultCheckState.absent) return null;
  if (inviteHasSalt) return LockMode.join;
  return installed ? LockMode.join : LockMode.setup;
}

abstract final class LockCopy {
  static const String title = 'Our Space 💕';
  static const String tagline = 'A little corner just for the two of us';
  static const String checking = 'Finding your space…';
  static const String unreadableTitle = 'Something went wrong opening your space';
  static const String unreadableBody = 'Nothing was lost — try again.';
  static const String tryAgain = 'Try again';
  static const String footer = 'Locked with your passphrase. Only you two can open it.';
  static String unlockTooShort() => 'Passphrase must be at least $minPassphraseLength characters.';
  static String setupTooShort() =>
      'Please choose a memorable secret passphrase of at least $minPassphraseLength characters.';
  static String typeToConfirm() => 'Type $destroyConfirmationPhrase to confirm.';
  static const String restoreFallback = 'That did not finish. Please try again.';
  static const String notOurFile = 'That does not look like a file Our Space saved.';
  static const String couldNotOpenFile = 'We could not open that file. Check the passphrase and try again.';
  static const String missingIdentity =
      'That file opened, but it is missing the part we need to rebuild your space here. It was '
      'probably saved by an older version. You can still bring its things in from the Sync '
      'Hub once you are unlocked.';
  static String fileTooBig(int bytes) =>
      'That file is ${(bytes / (1024 * 1024)).round()}MB, over the ${(maxBackupFileBytes / (1024 * 1024)).round()}MB limit.';

  static const Map<String, String> restoreErrors = {
    'no_identity': 'This file is missing the part we need to rebuild your space here.',
    'bad_salt': 'This file looks damaged, so we left everything as it is.',
    'passphrase_too_short': 'The passphrase needs at least $minPassphraseLength characters.',
    'passphrase_mismatch':
        'That is not the passphrase this file was saved with. Nothing changed. It is the one you used '
            'to open Our Space back when you saved it — not always the same one that opened the file.',
    'unreadable': 'We could not read what is already on this phone, so we stopped instead of risking it. '
        'Please try again.',
    'same_vault': 'This file is from this very phone, so there is nothing to swap. Just unlock as usual, then '
        'use Bring in a copy in the Sync Hub to add its things back.',
    'needs_confirmation': 'Type the words above to replace what is on this phone.',
    'write_failed': 'That stopped partway. Nothing more was written.',
  };
}

class LockHeartBeat extends TwLoopingAnimation {
  const LockHeartBeat({super.key, required super.child, super.enabled}) : super(period: const Duration(seconds: 3));

  static double _keyframes(List<double> values, double t) {
    final segments = values.length - 1;
    final position = (t.clamp(0.0, 1.0)) * segments;
    final index = position.floor().clamp(0, segments - 1);
    final local = Curves.easeInOut.transform(position - index);
    return values[index] + (values[index + 1] - values[index]) * local;
  }

  static double scaleAt(double t) => _keyframes(const [1, 1.08, 1], t);

  static double rotationDegreesAt(double t) => _keyframes(const [0, -3, 3, 0], t);

  @override
  Widget buildFrame(BuildContext context, double t, Widget child) {
    return Transform.rotate(
      angle: rotationDegreesAt(t) * 3.141592653589793 / 180,
      child: Transform.scale(scale: scaleAt(t), child: child),
    );
  }
}

class LockScreenFrame extends StatefulWidget {
  const LockScreenFrame({super.key, required this.child});

  final Widget child;

  @override
  State<LockScreenFrame> createState() => _LockScreenFrameState();
}

class _LockScreenFrameState extends State<LockScreenFrame> with SingleTickerProviderStateMixin {
  static const Duration _entranceDuration = Duration(milliseconds: 500);
  static DateTime? _lastEntrance;

  late final AnimationController _entrance = AnimationController(vsync: this, duration: _entranceDuration);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!motionAllowed(context)) {
      _entrance.value = 1;
      _started = true;
      return;
    }
    if (_started) return;
    _started = true;
    final now = DateTime.now();
    final last = _lastEntrance;
    final elapsed = last == null ? _entranceDuration : now.difference(last);
    if (elapsed < _entranceDuration) {
      _entrance.value = elapsed.inMicroseconds / _entranceDuration.inMicroseconds;
    } else {
      _lastEntrance = now;
    }
    _entrance.forward();
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final header = Column(
      children: [
        LockHeartBeat(
          child: CssBox(
            width: 80,
            height: 80,
            gradient: AppGradients.lockHeart,
            border: Border.all(color: AppColors.white, width: 4),
            borderRadius: AppRadii.all(AppRadii.full),
            shadows: AppShadows.tinted(AppShadows.lg, AppColors.blush200.withValues(alpha: 0.5)),
            child: const Center(
              child: LucideIcon(AppIcons.heart, size: 40, color: AppColors.blush500, fill: AppColors.blush400),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(LockCopy.title, textAlign: TextAlign.center, style: Tw.x3l.extrabold.trackingTight.c(AppColors.slate800)),
        const SizedBox(height: 4),
        Text(LockCopy.tagline, textAlign: TextAlign.center, style: Tw.sm.medium.c(AppColors.slate500)),
      ],
    );

    final card = GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          widget.child,
          const SizedBox(height: 20),
          CssBox(
            padding: const EdgeInsets.only(top: 16),
            border: Border(top: BorderSide(color: AppColors.blush100.withValues(alpha: 0.8))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const LucideIcon(AppIcons.shieldCheck, size: 16, color: AppColors.emerald500),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(LockCopy.footer, textAlign: TextAlign.center, style: Tw.px11.c(AppColors.slate400)),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return OurScaffold(
      body: OurCenteredPage(
        child: AnimatedBuilder(
          animation: _entrance,
          builder: (context, child) {
            final t = Curves.easeOut.transform(_entrance.value);
            return Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, 20 * (1 - t)),
                child: Transform.scale(scale: 0.95 + 0.05 * t, child: child),
              ),
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [header, const SizedBox(height: 24), card],
          ),
        ),
      ),
    );
  }
}

class LockCheckingBody extends StatelessWidget {
  const LockCheckingBody({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const OurSpinner(),
          const SizedBox(height: 12),
          Text(LockCopy.checking, textAlign: TextAlign.center, style: Tw.xs.medium.c(AppColors.slate500)),
        ],
      ),
    );
  }
}

class LockUnreadableBody extends StatelessWidget {
  const LockUnreadableBody({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const LucideIcon(AppIcons.shieldAlert, size: 32, color: AppColors.amber500),
          const SizedBox(height: 12),
          Text(LockCopy.unreadableTitle, textAlign: TextAlign.center, style: Tw.sm.bold.c(AppColors.slate700)),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              LockCopy.unreadableBody,
              textAlign: TextAlign.center,
              style: Tw.px11.relaxed.c(AppColors.slate600),
            ),
          ),
          const SizedBox(height: 12),
          _SlateButton(
            label: LockCopy.tryAgain,
            icon: AppIcons.refreshCw,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            onPressed: () {
              AppHaptics.tap();
              onRetry();
            },
          ),
        ],
      ),
    );
  }
}

class LockScreenBoot extends StatelessWidget {
  const LockScreenBoot({super.key, this.failed = false, this.onRetry});

  final bool failed;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return LockScreenFrame(
      child: failed ? LockUnreadableBody(onRetry: onRetry ?? () {}) : const LockCheckingBody(),
    );
  }
}

class _SlateButton extends StatelessWidget {
  const _SlateButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.padding = const EdgeInsets.symmetric(vertical: 8),
    this.expand = false,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onPressed;
  final LucideIconData? icon;
  final EdgeInsets padding;
  final bool expand;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final box = CssBox(
      padding: padding,
      color: AppColors.slate800,
      borderRadius: AppRadii.all(AppRadii.xl),
      opacity: enabled ? 1 : 0.5,
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            LucideIcon(icon!, size: 14, color: AppColors.white),
            const SizedBox(width: 6),
          ],
          Text(label, style: Tw.xs.bold.c(AppColors.white)),
        ],
      ),
    );
    return Semantics(
      button: true,
      enabled: enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onPressed : null,
        child: expand ? SizedBox(width: double.infinity, child: box) : box,
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner(this.text, {this.centered = true});

  final String text;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    return OurNotice(
      tone: NoticeTone.error,
      message: text,
      centered: centered,
      showIcon: false,
      radius: AppRadii.xl,
      textStyle: centered ? Tw.xs.medium.c(AppColors.rose600) : Tw.px11.medium.relaxed.c(AppColors.rose600),
    );
  }
}

class _SmallNotice extends StatelessWidget {
  const _SmallNotice({required this.tone, required this.icon, this.text, this.child});

  final NoticeTone tone;
  final LucideIconData icon;
  final String? text;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final palette = NoticePalette.of(tone);
    return OurNotice(
      tone: tone,
      icon: icon,
      message: text,
      padding: const EdgeInsets.all(10),
      radius: AppRadii.xl,
      textStyle: Tw.px11.c(palette.text),
      child: child,
    );
  }
}

TextStyle get _strong => const TextStyle(fontWeight: FontWeight.w700);

class LockDangerGate extends StatelessWidget {
  const LockDangerGate({
    super.key,
    required this.headline,
    required this.confirmController,
    required this.isConfirmed,
    required this.backupController,
    required this.onBackupChanged,
    required this.onSaveCopy,
    required this.backupBusy,
    required this.backupDone,
    required this.backupError,
    required this.onConfirmChanged,
  });

  final String headline;
  final TextEditingController confirmController;
  final bool isConfirmed;
  final TextEditingController backupController;
  final ValueChanged<String> onBackupChanged;
  final VoidCallback onSaveCopy;
  final bool backupBusy;
  final bool backupDone;
  final String? backupError;
  final ValueChanged<String> onConfirmChanged;

  @override
  Widget build(BuildContext context) {
    final body = Tw.px11.relaxed.c(AppColors.rose700);
    final confirmStyle = OurFieldStyle(
      fill: AppColors.white,
      border: isConfirmed ? AppColors.rose400 : AppColors.slate200,
      ring: isConfirmed ? AppColors.rose400 : AppColors.slate400,
      radius: AppRadii.xl,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      textStyle: Tw.xs.mono.trackingWide.c(AppColors.slate800),
      hintStyle: Tw.xs.mono.trackingWide.c(AppColors.placeholder),
    );
    final backupStyle = OurFieldStyle(
      fill: AppColors.white,
      border: AppColors.slate200,
      ring: AppColors.slate400,
      radius: AppRadii.xl,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      textStyle: Tw.xs.c(AppColors.slate800),
      hintStyle: Tw.xs.c(AppColors.slate400),
    );

    return CssBox(
      padding: const EdgeInsets.all(14),
      color: AppColors.rose50,
      border: Border.all(color: AppColors.rose300, width: 2),
      borderRadius: AppRadii.all(AppRadii.x2l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: LucideIcon(AppIcons.shieldAlert, size: 20, color: AppColors.rose600),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'This erases everything on this phone'.toUpperCase(),
                      style: Tw.xs.extrabold.trackingWide.c(AppColors.rose800),
                    ),
                    const SizedBox(height: 4),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: '$headline Every photo, letter, milestone and wish saved here '),
                          TextSpan(text: 'can never be opened again', style: _strong),
                          const TextSpan(
                            text:
                                ', and all of it is erased from this phone. There is no undo — not by us, not by anyone.',
                          ),
                        ],
                      ),
                      style: body,
                    ),
                    const SizedBox(height: 6),
                    Text.rich(
                      TextSpan(
                        children: [
                          const TextSpan(text: 'If you have only forgotten the passphrase, '),
                          TextSpan(text: 'please stop here', style: _strong),
                          const TextSpan(
                            text:
                                '. Nothing on this screen can bring it back, and your partner\'s phone may still have everything.',
                          ),
                        ],
                      ),
                      style: body,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          CssBox(
            padding: const EdgeInsets.all(10),
            color: AppColors.white.withValues(alpha: 0.7),
            border: Border.all(color: AppColors.rose200),
            borderRadius: AppRadii.all(AppRadii.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const LucideIcon(AppIcons.download, size: 14, color: AppColors.slate500),
                    const SizedBox(width: 6),
                    Text('Save a copy first', style: Tw.px11.bold.c(AppColors.slate700)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'This saves everything on this phone into one file. To open it later you will need the '
                  'passphrase you type below, and the one you open Our Space with today.',
                  style: Tw.px10.relaxed.c(AppColors.slate500),
                ),
                const SizedBox(height: 8),
                OurTextField(
                  controller: backupController,
                  style: backupStyle,
                  obscure: true,
                  showObscureToggle: false,
                  hint: 'Passphrase for this file (at least $minPassphraseLength)',
                  autofillHints: const [AutofillHints.newPassword],
                  onChanged: onBackupChanged,
                  semanticLabel: 'Passphrase for this file',
                ),
                const SizedBox(height: 8),
                _SlateButton(
                  label: backupBusy ? 'Saving…' : 'Save a copy',
                  expand: true,
                  enabled: !backupBusy,
                  onPressed: onSaveCopy,
                ),
                if (backupDone) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const LucideIcon(AppIcons.checkCircle2, size: 12, color: AppColors.emerald700),
                      const SizedBox(width: 4),
                      Flexible(
                          child: Text(BackupMessages.rescueSaved, style: Tw.px10.semibold.c(AppColors.emerald700))),
                    ],
                  ),
                ],
                if (backupError != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const LucideIcon(AppIcons.alertTriangle, size: 12, color: AppColors.rose600),
                      const SizedBox(width: 4),
                      Flexible(child: Text(backupError!, style: Tw.px10.semibold.c(AppColors.rose600))),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Type '),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: CssBox(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      color: AppColors.rose100,
                      borderRadius: AppRadii.all(AppRadii.base),
                      child: Text(destroyConfirmationPhrase, style: Tw.px11.bold.mono.c(AppColors.rose800)),
                    ),
                  ),
                  const TextSpan(text: ' to continue'),
                ],
              ),
              style: Tw.px11.bold.c(AppColors.rose800),
            ),
          ),
          OurTextField(
            controller: confirmController,
            style: confirmStyle,
            hint: destroyConfirmationPhrase,
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: onConfirmChanged,
            semanticLabel: 'Type $destroyConfirmationPhrase to continue',
          ),
        ],
      ),
    );
  }
}

class LockScreen extends StatefulWidget {
  const LockScreen({super.key, this.invite, this.installed = false});

  final Invite? invite;
  final bool installed;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final TextEditingController _passphrase = TextEditingController();
  final TextEditingController _coupleNames = TextEditingController();
  final TextEditingController _inviteInput = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  final TextEditingController _backupPassphrase = TextEditingController();
  final TextEditingController _restoreFilePassphrase = TextEditingController();
  final TextEditingController _restoreVaultPassphrase = TextEditingController();

  DateTime _startDate = startOfLocalDay(DateTime.now());
  LockMode _mode = LockMode.unlock;
  bool _modeTouched = false;
  bool _loading = false;
  String? _error;

  bool _backupBusy = false;
  bool _backupDone = false;
  String? _backupError;

  String _restoreFileName = '';
  Map<String, Object?>? _restoreContainer;
  Object? _restoreTables;
  Map<String, Object?>? _restoreIdentity;
  bool _restoreBusy = false;
  String? _restoreError;

  @override
  void dispose() {
    _passphrase.dispose();
    _coupleNames.dispose();
    _inviteInput.dispose();
    _confirm.dispose();
    _backupPassphrase.dispose();
    _restoreFilePassphrase.dispose();
    _restoreVaultPassphrase.dispose();
    super.dispose();
  }

  VaultService get _vault => context.read<VaultService>();

  Invite? get _linkInvite => widget.invite;

  bool get _isConfirmed => _confirm.text.trim().toUpperCase() == destroyConfirmationPhrase;

  String? get _destroyToken => _isConfirmed ? destroyConfirmationPhrase : null;

  String? get _pendingJoinSalt {
    final linked = _linkInvite;
    if (linked != null && linked.salt != null) return linked.salt;
    if (_inviteInput.text.trim().isEmpty) return null;
    return parseInvite(_inviteInput.text)?.salt;
  }

  void _celebrate() {
    AppHaptics.celebration();
    if (mounted) fireHeartConfetti(context);
  }

  void _resetRestore() {
    _restoreFileName = '';
    _restoreContainer = null;
    _restoreFilePassphrase.clear();
    _restoreTables = null;
    _restoreIdentity = null;
    _restoreVaultPassphrase.clear();
    _restoreError = null;
    _confirm.clear();
  }

  void _switchMode(LockMode next) {
    AppHaptics.tap();
    setState(() {
      _modeTouched = true;
      _mode = next;
      _error = null;
      _confirm.clear();
      _backupDone = false;
      _backupError = null;
      if (next != LockMode.restore) _resetRestore();
    });
  }

  Future<void> _saveRescueCopy() async {
    setState(() {
      _backupError = null;
      _backupDone = false;
    });
    if (normalizePassphrase(_backupPassphrase.text).length < minPassphraseLength) {
      setState(() => _backupError = BackupMessages.rescueTooShort());
      return;
    }
    setState(() => _backupBusy = true);
    final backup = context.space.backup;
    try {
      final file = await backup.exportRescueBackup(_backupPassphrase.text);
      final saved = await VaultFiles.save(file);
      if (!mounted) return;
      setState(() => _backupDone = saved);
    } on BackupFailure catch (failure) {
      if (mounted) setState(() => _backupError = failure.message);
    } catch (_) {
      if (mounted) setState(() => _backupError = BackupMessages.couldNotSave);
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  Future<void> _handleUnlock() async {
    setState(() => _error = null);
    if (normalizePassphrase(_passphrase.text).length < minPassphraseLength) {
      setState(() => _error = LockCopy.unlockTooShort());
      return;
    }
    setState(() => _loading = true);
    AppHaptics.tap();
    final result = await _vault.unlock(_passphrase.text);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (!result.ok) _error = result.error;
    });
    if (result.ok) {
      _passphrase.clear();
      _celebrate();
    }
  }

  Future<void> _handleSetup(bool hasVault) async {
    setState(() => _error = null);
    if (normalizePassphrase(_passphrase.text).length < minPassphraseLength) {
      setState(() => _error = LockCopy.setupTooShort());
      return;
    }
    if (hasVault && !_isConfirmed) {
      setState(() => _error = VaultMessages.typeToConfirm());
      return;
    }
    setState(() => _loading = true);
    AppHaptics.tap();
    final names = _coupleNames.text.trim();
    final result = await _vault.create(
      passphrase: _passphrase.text,
      coupleNames: names.isEmpty ? 'Us' : names,
      startDate: toLocalDateInput(_startDate),
      confirmDestroy: _destroyToken,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (!result.ok) _error = result.error;
    });
    if (result.ok) {
      _passphrase.clear();
      _confirm.clear();
      _celebrate();
    }
  }

  Future<void> _handleJoin(bool joinReplacesVault) async {
    setState(() => _error = null);
    if (normalizePassphrase(_passphrase.text).length < minPassphraseLength) {
      setState(() => _error = LockCopy.unlockTooShort());
      return;
    }
    final linked = _linkInvite;
    final invite = linked != null && linked.salt != null ? linked : parseInvite(_inviteInput.text);
    if (invite == null || invite.salt == null) {
      setState(() => _error = VaultMessages.pasteInvite);
      return;
    }
    if (joinReplacesVault && !_isConfirmed) {
      setState(() => _error = VaultMessages.typeToConfirm());
      return;
    }
    setState(() => _loading = true);
    AppHaptics.tap();
    final notices = context.read<AppNotices>();
    final result = await _vault.joinFromInvite(
      passphrase: _passphrase.text,
      invite: invite,
      confirmDestroy: _destroyToken,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (!result.ok) _error = result.error;
    });
    if (result.ok) {
      final warning = result.warning;
      if (warning != null) notices.showVaultWarning(warning);
      _passphrase.clear();
      _confirm.clear();
      _celebrate();
    }
  }

  Future<void> _pickRestoreFile() async {
    final picked = await VaultFiles.pick();
    if (!mounted || picked == null) return;
    setState(_resetRestore);
    if (picked.tooBig) {
      setState(() => _restoreError = LockCopy.fileTooBig(picked.size));
      return;
    }
    final text = picked.readText();
    if (text == null) {
      setState(() => _restoreError = LockCopy.notOurFile);
      return;
    }
    try {
      final container = context.space.backup.parseBackupFile(text);
      setState(() {
        _restoreFileName = picked.name;
        _restoreContainer = container;
      });
    } catch (_) {
      setState(() => _restoreError = LockCopy.notOurFile);
    }
  }

  Future<void> _openRestoreContainer() async {
    final container = _restoreContainer;
    setState(() => _restoreError = null);
    if (container == null) return;
    setState(() => _restoreBusy = true);
    final backup = context.space.backup;
    try {
      final decrypted = await backup.openContainer(container, _restoreFilePassphrase.text);
      if (!mounted) return;
      final tables = decrypted['tables'];
      final identity = readBackupVaultIdentity(tables);
      if (identity == null) {
        setState(() => _restoreError = LockCopy.missingIdentity);
        return;
      }
      setState(() {
        _restoreTables = tables;
        _restoreIdentity = identity;
        _restoreVaultPassphrase.text = _restoreFilePassphrase.text;
      });
    } catch (_) {
      if (mounted) setState(() => _restoreError = LockCopy.couldNotOpenFile);
    } finally {
      if (mounted) setState(() => _restoreBusy = false);
    }
  }

  Future<void> _restoreVault(bool restoreReplacesVault) async {
    setState(() => _restoreError = null);
    final tables = _restoreTables;
    if (tables == null) return;
    if (restoreReplacesVault && !_isConfirmed) {
      setState(() => _restoreError = LockCopy.typeToConfirm());
      return;
    }
    setState(() => _restoreBusy = true);
    AppHaptics.tap();
    final result = await _vault.restoreFromBackup(
      tables,
      _restoreVaultPassphrase.text,
      confirmDestroy: _destroyToken,
    );
    if (!mounted) return;
    setState(() => _restoreBusy = false);
    if (result.ok) {
      setState(_resetRestore);
      _celebrate();
      return;
    }
    setState(() => _restoreError = LockCopy.restoreErrors[result.code] ?? LockCopy.restoreFallback);
  }

  LockMode _effectiveMode(VaultCheckState state) {
    if (!_modeTouched) {
      final linked = _linkInvite;
      final next = defaultLockMode(
        state,
        inviteHasSalt: linked != null && linked.salt != null,
        installed: widget.installed,
      );
      if (next != null) _mode = next;
    }
    return _mode;
  }

  Widget _passphraseField({
    required String hint,
    required VoidCallback onSubmit,
    OurFieldStyle? style,
    bool autofocus = false,
  }) {
    return OurTextField(
      controller: _passphrase,
      style: style ?? OurFieldStyle.lock,
      leadingIcon: AppIcons.keyRound,
      obscure: true,
      hint: hint,
      autofocus: autofocus,
      textInputAction: TextInputAction.go,
      autofillHints: const [AutofillHints.password],
      onChanged: (_) => setState(() => _error = null),
      onSubmitted: (_) => onSubmit(),
      semanticLabel: hint,
    );
  }

  Widget _dangerGate(String headline) {
    return LockDangerGate(
      headline: headline,
      confirmController: _confirm,
      isConfirmed: _isConfirmed,
      backupController: _backupPassphrase,
      onBackupChanged: (_) => setState(() {
        _backupError = null;
        _backupDone = false;
      }),
      onSaveCopy: _saveRescueCopy,
      backupBusy: _backupBusy,
      backupDone: _backupDone,
      backupError: _backupError,
      onConfirmChanged: (_) => setState(() {}),
    );
  }

  Widget _modeIntro({required Widget pill, required String text, bool relaxed = false}) {
    return Column(
      children: [
        pill,
        const SizedBox(height: 8),
        Text(
          text,
          textAlign: TextAlign.center,
          style: (relaxed ? Tw.xs.relaxed : Tw.xs).c(AppColors.slate500),
        ),
      ],
    );
  }

  Widget _link(String text, VoidCallback onTap, {Color color = AppColors.slate500, bool medium = false}) {
    return OurTextLink(text: text, onTap: onTap, color: color, style: medium ? Tw.xs.medium : Tw.xs);
  }

  Widget _unlockForm(bool inviteIsForAnotherVault) {
    final linked = _linkInvite;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: spaced([
        _modeIntro(
          pill: OurPill.blush(label: 'Locked', icon: AppIcons.lock),
          text: 'Enter the passphrase you two share to open your memories and notes.',
        ),
        if (linked != null && !inviteIsForAnotherVault)
          const _SmallNotice(
            tone: NoticeTone.indigo,
            icon: AppIcons.link2,
            text: 'Your partner\'s invite is here. Unlock, and we\'ll offer to connect to their phone.',
          ),
        if (inviteIsForAnotherVault)
          _SmallNotice(
            tone: NoticeTone.warning,
            icon: AppIcons.alertTriangle,
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'That invite is for a '),
                  TextSpan(text: 'different space', style: _strong),
                  const TextSpan(
                    text:
                        ', not this one. Unlocking here is safe — the link is ignored. Joining it would replace everything on this phone.',
                  ),
                ],
              ),
              style: Tw.px11.c(AppColors.amber900),
            ),
          ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const OurFieldLabel('Secret Passphrase'),
            _passphraseField(
              hint: 'Enter your secret passphrase (min $minPassphraseLength chars)...',
              autofocus: true,
              onSubmit: _loading ? () {} : _handleUnlock,
            ),
          ],
        ),
        if (_error != null) _ErrorBanner(_error!),
        BouncyButton(
          onPressed: _handleUnlock,
          enabled: !_loading && _passphrase.text.trim().isNotEmpty,
          expand: true,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          label: _loading ? 'Opening…' : 'Unlock Our Space 💕',
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _link(
                'Joining partner\'s space with an invite link?',
                () => _switchMode(LockMode.join),
                color: AppColors.indigo600,
                medium: true,
              ),
              const SizedBox(height: 6),
              _link(
                'Start over with a brand new space (erases this one)',
                () => _switchMode(LockMode.setup),
                color: AppColors.slate400,
              ),
            ],
          ),
        ),
      ], 16),
    );
  }

  Widget _joinForm({required bool hasVault, required bool joinReplacesVault, required String? pendingSalt}) {
    final linked = _linkInvite;
    final linkedSalt = linked != null && linked.salt != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: spaced([
        _modeIntro(
          pill: OurPill.indigo(label: 'Join Partner\'s Space 💕', icon: AppIcons.userCheck),
          text: linked != null ? 'Your partner invited you! 💕' : 'Use your partner’s invite link to join their space.',
        ),
        if (!linkedSalt)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const OurFieldLabel('Partner\'s Invite Link or Code'),
              OurTextField(
                controller: _inviteInput,
                style: OurFieldStyle.lockCompact.copyWith(
                  ring: AppColors.indigo400,
                  textStyle: Tw.xs.c(AppColors.slate800),
                  hintStyle: Tw.xs.c(AppColors.slate400),
                ),
                leadingIcon: AppIcons.link2,
                iconTop: 12,
                hint: 'Paste link (e.g. https://...#connect=...)',
                keyboardType: TextInputType.url,
                autocorrect: false,
                enableSuggestions: false,
                onChanged: (_) => setState(() => _error = null),
                semanticLabel: 'Partner\'s Invite Link or Code',
              ),
              const OurFieldHint(
                'Ask your partner to tap "Share Pairing Link" in their Sync Hub, then paste it here.',
              ),
            ],
          ),
        if (pendingSalt != null && !joinReplacesVault && hasVault)
          const _SmallNotice(
            tone: NoticeTone.success,
            icon: AppIcons.shieldCheck,
            text: 'This invite is for the space you already have here. Pairing again is safe — nothing gets erased.',
          ),
        if (pendingSalt != null && !hasVault)
          const _SmallNotice(
            tone: NoticeTone.success,
            icon: AppIcons.shieldCheck,
            text: 'Found your partner\'s invite! Enter the passphrase you both chose.',
          ),
        if (joinReplacesVault) _dangerGate('Joining this invite moves this phone over to your partner’s space.'),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const OurFieldLabel('Shared Secret Passphrase'),
            _passphraseField(
              hint: 'Enter the secret phrase you both agreed on...',
              style: OurFieldStyle.lock.copyWith(ring: AppColors.indigo400),
              autofocus: !joinReplacesVault,
              onSubmit: _loading ? () {} : () => _handleJoin(joinReplacesVault),
            ),
            const OurFieldHint('It has to match theirs exactly, letter for letter.'),
          ],
        ),
        if (_error != null) _ErrorBanner(_error!),
        BouncyButton(
          onPressed: () => _handleJoin(joinReplacesVault),
          enabled: !_loading && _passphrase.text.trim().isNotEmpty && !(joinReplacesVault && !_isConfirmed),
          expand: true,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shadows: AppShadows.tinted(AppShadows.md, AppColors.indigo300.withValues(alpha: 0.4)),
          label: _loading ? 'Pairing…' : 'Pair & Enter Our Space 💕',
        ),
        if (hasVault)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: _link('Cancel and return to unlock', () => _switchMode(LockMode.unlock)),
          ),
      ], 16),
    );
  }

  Widget _setupForm({required bool hasVault}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: spaced([
        _modeIntro(
          pill: OurPill.lavender(label: 'Setup Your Private Space', icon: AppIcons.sparkles),
          text: 'Choose a passphrase only the two of you know. It is the only thing that opens your space.',
        ),
        if (!hasVault)
          OurNotice(
            tone: NoticeTone.warning,
            showIcon: false,
            radius: AppRadii.xl,
            textStyle: Tw.px11.relaxed.c(AppColors.amber900),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('This makes a brand-new, empty space.', style: Tw.px11.relaxed.bold.c(AppColors.amber900)),
                const SizedBox(height: 4),
                const Text(
                  'If your partner already set one up, don\'t make a second one. Join theirs with their invite '
                  'link, and you\'ll both see the same things.',
                ),
                const SizedBox(height: 8),
                OurTextLink(
                  text: 'Join your partner\'s space instead',
                  onTap: () => _switchMode(LockMode.join),
                  color: AppColors.indigo600,
                  style: Tw.px11.bold,
                  textAlign: TextAlign.start,
                ),
              ],
            ),
          ),
        if (hasVault) _dangerGate('Starting a new space gives this phone a brand new lock.'),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const OurFieldLabel('Your Nicknames / Couple Name'),
            OurTextField(
              controller: _coupleNames,
              style: OurFieldStyle.lockCompact,
              hint: 'e.g. Romeo & Juliet',
              textCapitalization: TextCapitalization.words,
              semanticLabel: 'Your Nicknames / Couple Name',
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const OurFieldLabel('When Did Your Story Begin?'),
            OurDateField(
              value: _startDate,
              style: OurFieldStyle.lockCompact,
              onChanged: (picked) => setState(() => _startDate = startOfLocalDay(picked)),
              semanticLabel: 'When Did Your Story Begin?',
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const OurFieldLabel('Shared Secret Passphrase'),
            _passphraseField(
              hint: 'Create a shared secret phrase (min $minPassphraseLength chars)...',
              style: OurFieldStyle.lockCompact,
              onSubmit: _loading ? () {} : () => _handleSetup(hasVault),
            ),
            const OurFieldHint(
              'At least $minPassphraseLength characters — a little sentence only you two would know works best. '
              'It is never saved anywhere, so if you both forget it, everything here is gone.',
            ),
          ],
        ),
        if (_error != null) _ErrorBanner(_error!),
        BouncyButton(
          onPressed: () => _handleSetup(hasVault),
          enabled: !_loading && _passphrase.text.trim().isNotEmpty && !(hasVault && !_isConfirmed),
          expand: true,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          label: _loading
              ? 'Setting things up…'
              : hasVault
                  ? 'Erase & Start Fresh'
                  : 'Create a New Space 💕',
        ),
        if (hasVault)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: _link('Cancel and return to unlock', () => _switchMode(LockMode.unlock)),
          ),
      ], 16),
    );
  }

  Widget _italicLabel(String before, String italic) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: before),
            TextSpan(text: italic, style: const TextStyle(fontStyle: FontStyle.italic)),
          ],
        ),
        style: Tw.xs.semibold.c(AppColors.slate600),
      ),
    );
  }

  Widget _restoreForm({required bool hasVault, required bool restoreReplacesVault}) {
    final restoreStyle = OurFieldStyle.lockCompact.copyWith(ring: AppColors.amber400);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: spaced([
        _modeIntro(
          pill: OurPill.amber(label: 'Bring back a saved copy', icon: AppIcons.lifeBuoy),
          text: 'Rebuilds your space on this phone from a file you saved earlier, so everything inside opens again.',
          relaxed: true,
        ),
        Semantics(
          button: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _restoreBusy ? null : _pickRestoreFile,
            child: CssBox(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              dashedBorder: const BorderSide(color: AppColors.slate300, width: 2),
              borderRadius: AppRadii.all(AppRadii.x2l),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const LucideIcon(AppIcons.upload, size: 16, color: AppColors.slate400),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      _restoreFileName.isEmpty ? 'Choose the file you saved' : _restoreFileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Tw.xs.semibold.c(AppColors.slate600),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_restoreContainer != null && _restoreTables == null)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _italicLabel('Passphrase that opens this ', 'file'),
              const SizedBox(height: 4),
              OurTextField(
                controller: _restoreFilePassphrase,
                style: restoreStyle,
                obscure: true,
                showObscureToggle: false,
                hint: 'Passphrase for this file',
                autofocus: true,
                onChanged: (_) => setState(() => _restoreError = null),
                onSubmitted: (_) {
                  if (!_restoreBusy && _restoreFilePassphrase.text.trim().isNotEmpty) _openRestoreContainer();
                },
                semanticLabel: 'Passphrase for this file',
              ),
              const SizedBox(height: 8),
              BouncyButton(
                onPressed: _openRestoreContainer,
                enabled: !_restoreBusy && _restoreFilePassphrase.text.trim().isNotEmpty,
                expand: true,
                label: _restoreBusy ? 'Opening…' : 'Open this file',
              ),
            ],
          ),
        if (_restoreTables != null && _restoreIdentity != null)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: spaced([
              _SmallNotice(
                tone: NoticeTone.success,
                icon: AppIcons.shieldCheck,
                child: Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(text: 'File opened! Now the passphrase you used '),
                      TextSpan(text: 'back then', style: _strong),
                      const TextSpan(text: ' will bring everything inside back.'),
                    ],
                  ),
                  style: Tw.px11.c(AppColors.emerald800),
                ),
              ),
              if (restoreReplacesVault)
                _dangerGate('Bringing this file back moves this phone over to the space inside it.'),
              if (!hasVault)
                OurNotice(
                  tone: NoticeTone.info,
                  showIcon: false,
                  padding: const EdgeInsets.all(10),
                  radius: AppRadii.xl,
                  textStyle: Tw.px11.relaxed.c(AppColors.slate600),
                  message: 'There is nothing here to replace. Anything left over from an older space on this phone is '
                      'tidied away first — it cannot be opened any more anyway.',
                ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _italicLabel('The passphrase you used ', 'back then'),
                  OurTextField(
                    controller: _restoreVaultPassphrase,
                    style: restoreStyle,
                    obscure: true,
                    showObscureToggle: false,
                    hint: 'The passphrase you used to unlock the app back then',
                    onChanged: (_) => setState(() => _restoreError = null),
                    semanticLabel: 'The passphrase you used back then',
                  ),
                  const OurFieldHint(
                    'Usually the same as the file passphrase, so we have filled it in. We check it before '
                    'anything is written, so a wrong guess costs you nothing.',
                  ),
                ],
              ),
              if (_restoreError != null) _ErrorBanner(_restoreError!, centered: false),
              BouncyButton(
                onPressed: () => _restoreVault(restoreReplacesVault),
                enabled: !_restoreBusy &&
                    _restoreVaultPassphrase.text.trim().isNotEmpty &&
                    !(restoreReplacesVault && !_isConfirmed),
                expand: true,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                shadows: AppShadows.tinted(AppShadows.md, AppColors.amber300.withValues(alpha: 0.4)),
                label: _restoreBusy ? 'Bringing it back…' : 'Bring everything back',
              ),
            ], 12),
          ),
        if (_restoreError != null && _restoreTables == null) _ErrorBanner(_restoreError!, centered: false),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: _link('Cancel', () => _switchMode(hasVault ? LockMode.unlock : LockMode.setup)),
        ),
      ], 16),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vault = context.watch<VaultService>();
    final state = vault.state;
    final hasVault = state == VaultCheckState.present;
    final canRenderForms = hasVault || state == VaultCheckState.absent;
    final mode = _effectiveMode(state);
    final linked = _linkInvite;
    final pendingSalt = _pendingJoinSalt;
    final joinReplacesVault = hasVault && pendingSalt != vault.salt;
    final restoreIdentitySalt = _restoreIdentity?['salt'];
    final restoreReplacesVault = hasVault && _restoreIdentity != null && restoreIdentitySalt != vault.salt;
    final inviteIsForAnotherVault = hasVault && linked != null && linked.salt != null && linked.salt != vault.salt;

    final children = <Widget>[
      if (state == VaultCheckState.checking) const LockCheckingBody(),
      if (state == VaultCheckState.unreadable) LockUnreadableBody(onRetry: vault.check),
      if (state == VaultCheckState.absent && mode != LockMode.restore) ...[
        OurSegmented<LockMode>(
          segments: const [
            OurSegment(
              value: LockMode.setup,
              label: 'Create New Space',
              icon: AppIcons.sparkles,
              iconColor: AppColors.blush500,
            ),
            OurSegment(
              value: LockMode.join,
              label: 'Join Partner\'s Space',
              icon: AppIcons.users,
              iconColor: AppColors.indigo500,
            ),
          ],
          selected: mode,
          onChanged: _switchMode,
        ),
        const SizedBox(height: 20),
      ],
      if (canRenderForms && mode == LockMode.unlock) _unlockForm(inviteIsForAnotherVault),
      if (canRenderForms && mode == LockMode.join)
        _joinForm(hasVault: hasVault, joinReplacesVault: joinReplacesVault, pendingSalt: pendingSalt),
      if (canRenderForms && mode == LockMode.setup) _setupForm(hasVault: hasVault),
      if (canRenderForms && mode == LockMode.restore)
        _restoreForm(hasVault: hasVault, restoreReplacesVault: restoreReplacesVault),
      if (canRenderForms && mode != LockMode.restore)
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Center(
            child: OurTextLink(
              text: 'Bring back a copy you saved',
              icon: AppIcons.lifeBuoy,
              onTap: () => _switchMode(LockMode.restore),
              color: AppColors.amber700,
              style: Tw.xs.medium,
            ),
          ),
        ),
    ];

    return LockScreenFrame(
      child: AutofillGroup(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      ),
    );
  }
}
