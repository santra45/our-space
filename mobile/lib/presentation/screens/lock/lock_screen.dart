import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/engine.dart';
import '../../files/vault_files.dart';
import '../../sky/sky.dart';
import '../../space_scope.dart';
import '../../widgets/app_haptics.dart';
import '../../widgets/confetti_burst.dart';
import 'lock_copy.dart';
import 'widgets/lock_danger_gate.dart';
import 'widgets/lock_fields.dart';
import 'widgets/lock_parts.dart';
import 'widgets/lock_sky.dart';
import 'widgets/lock_touch.dart';

export 'lock_copy.dart';
export 'widgets/lock_danger_gate.dart';
export 'widgets/lock_fields.dart';
export 'widgets/lock_parts.dart';
export 'widgets/lock_sky.dart';
export 'widgets/lock_touch.dart';

enum LockMode { unlock, join, setup, restore }

enum LockView { checking, unreadable, touch, passphrase, setup, join, restore }

LockMode? defaultLockMode(VaultCheckState state, {bool inviteHasSalt = false, bool installed = false}) {
  if (state == VaultCheckState.present) return LockMode.unlock;
  if (state != VaultCheckState.absent) return null;
  if (inviteHasSalt) return LockMode.join;
  return installed ? LockMode.join : LockMode.setup;
}

const double _actionArea = LockMetrics.touchBlock - 36 - 14;
const double _linkGap = 6;
const double _linkFooterSpace = 28;

class LockCheckingView extends StatelessWidget {
  const LockCheckingView({super.key, required this.metrics});

  final LockMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    return LockOpenView(
      metrics: metrics,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: _actionArea),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SkySpinner(size: 30, strokeWidth: 2.2),
              const SizedBox(height: 16),
              Text(
                LockCopy.checking,
                textAlign: TextAlign.center,
                style: SkyType.sans(13, weight: FontWeight.w500).copyWith(color: t.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class LockUnreadableView extends StatelessWidget {
  const LockUnreadableView({super.key, required this.metrics, required this.onRetry});

  final LockMetrics metrics;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    return LockOpenView(
      metrics: metrics,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: _actionArea),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SkyIconTile(icon: SkyIcons.alert, tone: SkyTone.rose, size: 46, iconSize: 22),
              const SizedBox(height: 14),
              Text(
                LockCopy.unreadableTitle,
                textAlign: TextAlign.center,
                style: SkyType.serif(21, weight: FontWeight.w500, height: 1.2).copyWith(color: t.title),
              ),
              const SizedBox(height: 8),
              Text(
                LockCopy.unreadableBody,
                textAlign: TextAlign.center,
                style: SkyType.bodySmall.copyWith(color: t.muted),
              ),
              const SizedBox(height: 18),
              SkyButton(
                label: LockCopy.tryAgain,
                icon: SkyIcons.refresh,
                variant: SkyButtonVariant.ghost,
                expand: false,
                height: SkySizes.buttonCompact,
                onPressed: onRetry,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class LockScreenBoot extends StatelessWidget {
  const LockScreenBoot({super.key, this.failed = false, this.onRetry});

  final bool failed;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return LockSkyFrame(
      viewKey: failed ? LockView.unreadable : LockView.checking,
      builder: (context, metrics) =>
          failed ? LockUnreadableView(metrics: metrics, onRetry: onRetry ?? () {}) : LockCheckingView(metrics: metrics),
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
  static const double _segmentedExtent = 46 + 4 + SkySpace.lg;

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
  bool _showPassphraseForm = false;
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

  LockView? _lastView;
  bool _reverse = false;

  @override
  void initState() {
    super.initState();
    unawaited(context.read<QuickUnlockService>().refresh());
  }

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

  void _showPassphrase(bool show) {
    setState(() {
      _showPassphraseForm = show;
      _error = null;
    });
  }

  Future<void> _openMoreWays() async {
    final way = await showSkySheet<LockWay>(context: context, builder: (_) => const LockMoreSheet());
    if (!mounted || way == null) return;
    switch (way) {
      case LockWay.join:
        _switchMode(LockMode.join);
      case LockWay.restore:
        _switchMode(LockMode.restore);
      case LockWay.startOver:
        _switchMode(LockMode.setup);
    }
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
    final vault = _vault;
    final peer = context.space.peer;
    final linked = _linkInvite;
    final result = await vault.unlock(_passphrase.text);
    if (result.ok && linked != null && (linked.salt == null || linked.salt == vault.salt)) {
      peer.acceptInvite(linked);
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (!result.ok) _error = LockCopy.warm(result.error ?? '');
    });
    if (result.ok) {
      _passphrase.clear();
      _celebrate();
    }
  }

  Future<void> _handleQuickUnlock() async {
    setState(() {
      _error = null;
      _loading = true;
    });
    AppHaptics.tap();
    final vault = _vault;
    final peer = context.space.peer;
    final linked = _linkInvite;
    final result = await context.read<QuickUnlockService>().unlock();
    if (result.ok && linked != null && (linked.salt == null || linked.salt == vault.salt)) {
      peer.acceptInvite(linked);
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (!result.ok && result.code != 'cancelled') _error = LockCopy.warm(result.error ?? '');
    });
    if (result.ok) _celebrate();
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
      if (!result.ok) _error = LockCopy.warm(result.error ?? '');
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
      setState(() => _error = LockCopy.pasteInvite);
      return;
    }
    if (joinReplacesVault && !_isConfirmed) {
      setState(() => _error = VaultMessages.typeToConfirm());
      return;
    }
    setState(() => _loading = true);
    AppHaptics.tap();
    final notices = context.read<AppNotices>();
    final peer = context.space.peer;
    final result = await _vault.joinFromInvite(
      passphrase: _passphrase.text,
      invite: invite,
      confirmDestroy: _destroyToken,
    );
    if (result.ok) peer.acceptInvite(invite);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (!result.ok) _error = LockCopy.warm(result.error ?? '');
    });
    if (result.ok) {
      final warning = result.warning;
      if (warning != null) notices.showVaultWarning(LockCopy.warm(warning));
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
    final result = await _vault.restoreFromBackup(tables, _restoreVaultPassphrase.text, confirmDestroy: _destroyToken);
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

  LockView _viewFor(VaultCheckState state, LockMode mode, bool touch) {
    if (state == VaultCheckState.checking) return LockView.checking;
    if (state == VaultCheckState.unreadable) return LockView.unreadable;
    switch (mode) {
      case LockMode.unlock:
        return touch ? LockView.touch : LockView.passphrase;
      case LockMode.setup:
        return LockView.setup;
      case LockMode.join:
        return LockView.join;
      case LockMode.restore:
        return LockView.restore;
    }
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

  Widget _errorNote(String text) => SkyEntrance(
    child: LockNote(text: text, tone: LockNoteTone.error),
  );

  List<Widget> _inviteNotes({required bool inviteIsForAnotherVault}) {
    final linked = _linkInvite;
    return [
      if (linked != null && !inviteIsForAnotherVault) ...[
        const LockNote(text: LockCopy.inviteHere, tone: LockNoteTone.love, icon: SkyIcons.link),
        const SizedBox(height: SkySpace.xl),
      ],
      if (inviteIsForAnotherVault) ...[
        const LockNote(
          tone: LockNoteTone.warning,
          spans: [
            TextSpan(text: LockCopy.inviteElsewhereLead),
            TextSpan(text: LockCopy.inviteElsewhereStrong, style: lockStrong),
            TextSpan(text: LockCopy.inviteElsewhereRest),
          ],
        ),
        const SizedBox(height: SkySpace.xl),
      ],
    ];
  }

  Widget _touchView(LockMetrics metrics, {required bool inviteIsForAnotherVault}) {
    return LockOpenView(
      metrics: metrics,
      footerSpace: _linkFooterSpace,
      children: [
        ..._inviteNotes(inviteIsForAnotherVault: inviteIsForAnotherVault),
        LockTouchButton(
          label: LockCopy.quickButton,
          busyLabel: LockCopy.opening,
          busy: _loading,
          onTap: _handleQuickUnlock,
        ),
        if (_error != null) ...[const SizedBox(height: SkySpace.md), SkyEntrance(child: LockInlineError(_error!))],
        const SizedBox(height: _linkGap),
        LockLink(label: LockCopy.usePassphrase, onTap: () => _showPassphrase(true)),
      ],
    );
  }

  Widget _passphraseView(LockMetrics metrics, {required bool inviteIsForAnotherVault, required bool touchOffered}) {
    final t = context.sky;
    final ready = _passphrase.text.trim().isNotEmpty;
    return LockOpenView(
      metrics: metrics,
      footerSpace: _linkFooterSpace,
      children: [
        ..._inviteNotes(inviteIsForAnotherVault: inviteIsForAnotherVault),
        Text(
          LockCopy.unlockIntro,
          textAlign: TextAlign.center,
          style: SkyType.sans(13.5, height: 1.5).copyWith(color: t.muted),
        ),
        const SizedBox(height: SkySpace.lg),
        LockField(
          controller: _passphrase,
          hint: LockCopy.unlockHint,
          obscure: true,
          autofocus: true,
          leadingIcon: SkyIcons.lock,
          textInputAction: TextInputAction.go,
          autofillHints: const [AutofillHints.password],
          onChanged: (_) => setState(() => _error = null),
          onSubmitted: (_) {
            if (!_loading) _handleUnlock();
          },
        ),
        if (_error != null) ...[const SizedBox(height: SkySpace.md), _errorNote(_error!)],
        const SizedBox(height: SkySpace.md),
        SkyButton(
          label: LockCopy.unlockButton,
          busyLabel: LockCopy.opening,
          busy: _loading,
          icon: SkyIcons.heart,
          onPressed: ready ? _handleUnlock : null,
        ),
        const SizedBox(height: _linkGap),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: SkySpace.xl,
          children: [
            if (touchOffered)
              LockLink(label: LockCopy.useTouch, icon: SkyIcons.finger, onTap: () => _showPassphrase(false)),
            LockLink(label: LockCopy.moreWays, icon: SkyIcons.dots, onTap: _openMoreWays),
          ],
        ),
      ],
    );
  }

  Widget _setupForm({required bool hasVault}) {
    return LockPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const LockPanelHeader(icon: SkyIcons.sparkle, title: LockCopy.setupTitle, intro: LockCopy.setupIntro),
          const SizedBox(height: SkySpace.xl),
          if (!hasVault) ...[
            LockNote(
              tone: LockNoteTone.warning,
              title: LockCopy.freshTitle,
              text: LockCopy.freshBody,
              actionLabel: LockCopy.freshAction,
              onAction: () => _switchMode(LockMode.join),
            ),
            const SizedBox(height: SkySpace.lg),
          ],
          if (hasVault) ...[_dangerGate(LockCopy.startOverDanger), const SizedBox(height: SkySpace.lg)],
          LockField(
            controller: _coupleNames,
            label: LockCopy.namesLabel,
            hint: LockCopy.namesHint,
            textCapitalization: TextCapitalization.words,
            leadingIcon: SkyIcons.us,
          ),
          const SizedBox(height: SkySpace.lg),
          LockDateField(
            value: _startDate,
            label: LockCopy.startLabel,
            onChanged: (picked) => setState(() => _startDate = startOfLocalDay(picked)),
          ),
          const SizedBox(height: SkySpace.lg),
          LockField(
            controller: _passphrase,
            label: LockCopy.sharedPassphraseLabel,
            hint: LockCopy.setupHint,
            help: LockCopy.setupHelp,
            obscure: true,
            leadingIcon: SkyIcons.lock,
            textInputAction: TextInputAction.go,
            autofillHints: const [AutofillHints.newPassword],
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) {
              if (!_loading) _handleSetup(hasVault);
            },
          ),
          if (_error != null) ...[const SizedBox(height: 14), _errorNote(_error!)],
          const SizedBox(height: SkySpace.xl),
          SkyButton(
            label: hasVault ? LockCopy.replaceButton : LockCopy.createButton,
            busyLabel: LockCopy.creating,
            busy: _loading,
            icon: hasVault ? SkyIcons.refresh : SkyIcons.sparkle,
            variant: hasVault ? SkyButtonVariant.danger : SkyButtonVariant.primary,
            onPressed: _passphrase.text.trim().isNotEmpty && !(hasVault && !_isConfirmed)
                ? () => _handleSetup(hasVault)
                : null,
          ),
          if (hasVault) ...[
            const SizedBox(height: SkySpace.xs),
            LockLink(label: LockCopy.goBack, onTap: () => _switchMode(LockMode.unlock)),
          ],
        ],
      ),
    );
  }

  Widget _joinForm({required bool hasVault, required bool joinReplacesVault, required String? pendingSalt}) {
    final linked = _linkInvite;
    final linkedSalt = linked != null && linked.salt != null;
    final ready = _passphrase.text.trim().isNotEmpty && !(joinReplacesVault && !_isConfirmed);
    return LockPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LockPanelHeader(
            icon: SkyIcons.us,
            tone: SkyTone.lavender,
            title: LockCopy.joinTitle,
            intro: linked != null ? LockCopy.joinInvited : LockCopy.joinIntro,
          ),
          const SizedBox(height: SkySpace.xl),
          if (!linkedSalt) ...[
            LockField(
              controller: _inviteInput,
              label: LockCopy.inviteLabel,
              hint: LockCopy.inviteHint,
              help: LockCopy.inviteHelp,
              leadingIcon: SkyIcons.link,
              keyboardType: TextInputType.url,
              autocorrect: false,
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: SkySpace.lg),
          ],
          if (pendingSalt != null && !joinReplacesVault && hasVault) ...[
            const LockNote(text: LockCopy.inviteSameSpace, tone: LockNoteTone.safe),
            const SizedBox(height: SkySpace.lg),
          ],
          if (pendingSalt != null && !hasVault) ...[
            const SkyEntrance(
              child: LockNote(text: LockCopy.inviteFound, tone: LockNoteTone.love),
            ),
            const SizedBox(height: SkySpace.lg),
          ],
          if (joinReplacesVault) ...[_dangerGate(LockCopy.joinDanger), const SizedBox(height: SkySpace.lg)],
          LockField(
            controller: _passphrase,
            label: LockCopy.sharedPassphraseLabel,
            hint: LockCopy.joinHint,
            help: LockCopy.joinHelp,
            obscure: true,
            autofocus: !joinReplacesVault,
            leadingIcon: SkyIcons.lock,
            textInputAction: TextInputAction.go,
            autofillHints: const [AutofillHints.password],
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) {
              if (!_loading) _handleJoin(joinReplacesVault);
            },
          ),
          if (_error != null) ...[const SizedBox(height: 14), _errorNote(_error!)],
          const SizedBox(height: SkySpace.xl),
          SkyButton(
            label: LockCopy.joinButton,
            busyLabel: LockCopy.joining,
            busy: _loading,
            icon: SkyIcons.heart,
            variant: joinReplacesVault ? SkyButtonVariant.danger : SkyButtonVariant.primary,
            onPressed: ready ? () => _handleJoin(joinReplacesVault) : null,
          ),
          if (hasVault) ...[
            const SizedBox(height: SkySpace.xs),
            LockLink(label: LockCopy.goBack, onTap: () => _switchMode(LockMode.unlock)),
          ],
        ],
      ),
    );
  }

  Widget _restoreForm({required bool hasVault, required bool restoreReplacesVault}) {
    final opened = _restoreTables != null && _restoreIdentity != null;
    return LockPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const LockPanelHeader(icon: SkyIcons.box, title: LockCopy.restoreTitle, intro: LockCopy.restoreIntro),
          const SizedBox(height: SkySpace.xl),
          LockFileTile(
            label: _restoreFileName.isEmpty ? LockCopy.chooseFile : _restoreFileName,
            chosen: _restoreFileName.isNotEmpty,
            onTap: _restoreBusy ? null : _pickRestoreFile,
          ),
          if (_restoreContainer != null && _restoreTables == null) ...[
            const SizedBox(height: SkySpace.lg),
            LockField(
              controller: _restoreFilePassphrase,
              label: LockCopy.filePassphraseLabel,
              labelEmphasis: LockCopy.filePassphraseEmphasis,
              hint: LockCopy.filePassphraseHint,
              obscure: true,
              revealToggle: false,
              autofocus: true,
              onChanged: (_) => setState(() => _restoreError = null),
              onSubmitted: (_) {
                if (!_restoreBusy && _restoreFilePassphrase.text.trim().isNotEmpty) _openRestoreContainer();
              },
            ),
            const SizedBox(height: SkySpace.md),
            SkyButton(
              label: LockCopy.openFile,
              busyLabel: LockCopy.opening,
              busy: _restoreBusy,
              icon: SkyIcons.lock,
              variant: SkyButtonVariant.gold,
              onPressed: _restoreFilePassphrase.text.trim().isNotEmpty ? _openRestoreContainer : null,
            ),
          ],
          if (opened) ...[
            const SizedBox(height: SkySpace.lg),
            const SkyEntrance(
              child: LockNote(
                tone: LockNoteTone.safe,
                spans: [
                  TextSpan(text: LockCopy.fileOpenedLead),
                  TextSpan(text: LockCopy.fileOpenedStrong, style: lockStrong),
                  TextSpan(text: LockCopy.fileOpenedRest),
                ],
              ),
            ),
            if (restoreReplacesVault) ...[const SizedBox(height: SkySpace.md), _dangerGate(LockCopy.restoreDanger)],
            if (!hasVault) ...[
              const SizedBox(height: SkySpace.md),
              const LockNote(text: LockCopy.nothingToReplace, tone: LockNoteTone.info),
            ],
            const SizedBox(height: SkySpace.lg),
            LockField(
              controller: _restoreVaultPassphrase,
              label: LockCopy.thenPassphraseLabel,
              labelEmphasis: LockCopy.thenPassphraseEmphasis,
              hint: LockCopy.thenPassphraseHint,
              help: LockCopy.thenPassphraseHelp,
              obscure: true,
              revealToggle: false,
              onChanged: (_) => setState(() => _restoreError = null),
            ),
            if (_restoreError != null) ...[const SizedBox(height: SkySpace.md), _errorNote(_restoreError!)],
            const SizedBox(height: SkySpace.xl),
            SkyButton(
              label: LockCopy.restoreButton,
              busyLabel: LockCopy.restoring,
              busy: _restoreBusy,
              icon: SkyIcons.heart,
              variant: restoreReplacesVault ? SkyButtonVariant.danger : SkyButtonVariant.primary,
              onPressed: _restoreVaultPassphrase.text.trim().isNotEmpty && !(restoreReplacesVault && !_isConfirmed)
                  ? () => _restoreVault(restoreReplacesVault)
                  : null,
            ),
          ],
          if (_restoreError != null && _restoreTables == null) ...[
            const SizedBox(height: 14),
            _errorNote(_restoreError!),
          ],
          const SizedBox(height: SkySpace.xs),
          LockLink(label: LockCopy.cancel, onTap: () => _switchMode(hasVault ? LockMode.unlock : LockMode.setup)),
        ],
      ),
    );
  }

  Widget _formView(LockMetrics metrics, Widget panel, {required bool restoreLink}) {
    return LockFormView(
      metrics: metrics,
      children: [
        panel,
        if (restoreLink) ...[
          const SizedBox(height: SkySpace.sm),
          LockLink(label: LockCopy.moreRestore, icon: SkyIcons.box, onTap: () => _switchMode(LockMode.restore)),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final vault = context.watch<VaultService>();
    final quick = context.watch<QuickUnlockService>();
    final state = vault.state;
    final hasVault = state == VaultCheckState.present;
    final mode = _effectiveMode(state);
    final linked = _linkInvite;
    final pendingSalt = _pendingJoinSalt;
    final joinReplacesVault = hasVault && pendingSalt != vault.salt;
    final restoreIdentitySalt = _restoreIdentity?['salt'];
    final restoreReplacesVault = hasVault && _restoreIdentity != null && restoreIdentitySalt != vault.salt;
    final inviteIsForAnotherVault = hasVault && linked != null && linked.salt != null && linked.salt != vault.salt;
    final touchOffered = quick.offered;
    final view = _viewFor(state, mode, touchOffered && !_showPassphraseForm);
    final last = _lastView;
    if (last != null && last != view) _reverse = view.index < last.index;
    _lastView = view;
    final segmented = state == VaultCheckState.absent && (mode == LockMode.setup || mode == LockMode.join);

    return AutofillGroup(
      child: LockSkyFrame(
        viewKey: view,
        reverse: _reverse,
        heartVisible:
            view.index <= LockView.passphrase.index && !(linked != null && view.index >= LockView.touch.index),
        header: segmented
            ? LockSegmented<LockMode>(
                segments: const [
                  LockSegment(value: LockMode.setup, label: LockCopy.segmentStart, icon: SkyIcons.sparkle),
                  LockSegment(value: LockMode.join, label: LockCopy.segmentJoin, icon: SkyIcons.us),
                ],
                selected: mode,
                onChanged: _switchMode,
              )
            : null,
        headerExtent: segmented ? _segmentedExtent : 0,
        builder: (context, metrics) {
          switch (view) {
            case LockView.checking:
              return LockCheckingView(metrics: metrics);
            case LockView.unreadable:
              return LockUnreadableView(metrics: metrics, onRetry: vault.check);
            case LockView.touch:
              return _touchView(metrics, inviteIsForAnotherVault: inviteIsForAnotherVault);
            case LockView.passphrase:
              return _passphraseView(
                metrics,
                inviteIsForAnotherVault: inviteIsForAnotherVault,
                touchOffered: touchOffered,
              );
            case LockView.setup:
              return _formView(metrics, _setupForm(hasVault: hasVault), restoreLink: true);
            case LockView.join:
              return _formView(
                metrics,
                _joinForm(hasVault: hasVault, joinReplacesVault: joinReplacesVault, pendingSalt: pendingSalt),
                restoreLink: true,
              );
            case LockView.restore:
              return _formView(
                metrics,
                _restoreForm(hasVault: hasVault, restoreReplacesVault: restoreReplacesVault),
                restoreLink: false,
              );
          }
        },
      ),
    );
  }
}
