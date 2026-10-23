import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/engine.dart';
import '../../app_shell.dart';
import '../../sky/sky.dart';
import '../../space_scope.dart';
import '../../widgets/app_haptics.dart';
import '../sync/add_phone_page.dart';
import '../sync/backup_dialogs.dart' show BackupCopy;
import '../sync/keep_a_copy.dart';
import '../sync/peer_link.dart';
import '../sync/quick_unlock_sheet.dart';
import '../sync/together_now.dart';
import 'settings_dates.dart';
import 'widgets/couple_header.dart';
import 'widgets/names_sheet.dart';
import 'widgets/reminders_row.dart';
import 'widgets/settings_row.dart';
import 'widgets/sheet_parts.dart';

abstract final class SettingsCopy {
  static const String title = 'Settings';
  static const String thisPhone = 'This phone';
  static const String skyFollows = 'Sky follows the time';
  static const String skyFollowsHint = 'Day sky by day, stars by night';
  static const String twoOfUs = 'The two of us';
  static const String names = 'Names';
  static const String togetherSince = 'Together since';
  static const String notSet = 'Not set yet';
  static const String pickDate = 'When did it all begin?';
  static const String saveDate = 'Save';
  static const String cancel = 'Cancel';
  static const String dateFailed = 'That date did not save. Please try again.';
  static const String addPhone = AddPhoneCopy.title;
  static const String addPhoneHint = 'A link or a code to scan';
  static const String keepCopy = BackupCopy.sectionTitle;
  static const String lockNow = 'Lock Our Space now';
  static const String lockedFooter = 'Locked with your passphrase. Only you two can open it.';
  static const String separator = ' · ';
  static String since(String date) => 'Together since $date';
  static String stars(int count) => count == 1 ? '1 star' : '$count stars';
  static String names2(String me, String partner) => '$me & $partner';
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  static const String routeName = '/settings';
  static const Key phonesKey = ValueKey<String>('settings-phones');
  static const Key touchKey = ValueKey<String>('settings-touch');
  static const Key remindersKey = ValueKey<String>('settings-reminders');
  static const Key namesKey = ValueKey<String>('settings-names');
  static const Key togetherKey = ValueKey<String>('settings-together');
  static const Key connectionKey = ValueKey<String>('settings-connection');
  static const Key saveCopyKey = ValueKey<String>('settings-save-copy');
  static const Key bringInKey = ValueKey<String>('settings-bring-in');

  static const SkyScene scene = SkyScene(
    stars: 50,
    moon: Offset(320, 120),
    sun: false,
    clouds: [SkyCloud(310, 110, scale: 0.9, opacity: 0.85), SkyCloud(60, 230, scale: 0.6, opacity: 0.5)],
  );

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const Duration _tick = Duration(seconds: 30);

  Timer? _clock;
  int _now = DateTime.now().millisecondsSinceEpoch;
  SettingsNote? _phoneNote;
  SettingsNote? _usNote;
  SettingsNote? _copyNote;
  bool _touchBusy = false;
  bool _copyBusy = false;
  int? _stars;
  String? _starsOwner;
  bool _starsQueued = false;

  @override
  void initState() {
    super.initState();
    unawaited(context.read<QuickUnlockService>().refresh());
    _clock = Timer.periodic(_tick, (_) {
      if (mounted) setState(() => _now = DateTime.now().millisecondsSinceEpoch);
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  void _queueStars(String? owner) {
    if (owner == _starsOwner || _starsQueued) return;
    _starsQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _starsQueued = false;
      if (mounted) unawaited(_loadStars());
    });
  }

  Future<void> _loadStars() async {
    final identity = context.read<IdentityController>();
    final space = context.space;
    final owner = identity.myOwnerId;
    if (owner == _starsOwner) return;
    _starsOwner = owner;
    if (owner == null) {
      setState(() => _stars = null);
      return;
    }
    try {
      final days = await space.dailyQuestion.listAnswered(
        space.vault.key,
        ownerId: owner,
        ownerIds: identity.myOwnerIds,
      );
      final lit = days.where((day) => day.theirs != null).length;
      if (mounted && _starsOwner == owner) setState(() => _stars = lit);
    } catch (_) {}
  }

  Future<void> _toggleTouch() async {
    if (_touchBusy) return;
    _touchBusy = true;
    final quick = context.read<QuickUnlockService>();
    setState(() => _phoneNote = null);
    try {
      if (quick.enrolled) {
        AppHaptics.tap();
        await quick.disable();
        if (mounted) setState(() => _phoneNote = const SettingsNote(TouchCopy.turnedOff));
        return;
      }
      final ok = await showQuickUnlockSetup(context);
      if (mounted && ok) setState(() => _phoneNote = const SettingsNote(TouchCopy.done));
    } finally {
      _touchBusy = false;
    }
  }

  Future<void> _pickTogetherSince() async {
    final vault = context.read<VaultService>();
    final saved = vault.config?.startDate ?? '';
    final today = startOfLocalDay(DateTime.now());
    final first = DateTime(1950);
    var initial = parseLocalDate(saved) ?? today;
    if (initial.isAfter(today)) initial = today;
    if (initial.isBefore(first)) initial = first;
    setState(() => _usNote = null);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: today,
      helpText: SettingsCopy.pickDate,
      confirmText: SettingsCopy.saveDate,
      cancelText: SettingsCopy.cancel,
      builder: (context, child) => SkyTheme(child: child ?? const SizedBox.shrink()),
    );
    if (picked == null || !mounted) return;
    final value = toLocalDateInput(picked);
    if (value == saved) return;
    final result = await vault.updateSettings(startDate: value);
    if (!mounted) return;
    if (!result.ok) {
      setState(() => _usNote = SettingsNote.error(result.error ?? SettingsCopy.dateFailed));
      return;
    }
    AppHaptics.celebration();
  }

  SettingsNote _noteFor(CopyOutcome outcome) =>
      outcome.failed ? SettingsNote.error(outcome.text) : SettingsNote(outcome.text);

  Future<void> _saveCopy() async {
    if (_copyBusy) return;
    _copyBusy = true;
    setState(() => _copyNote = null);
    try {
      final outcome = await saveACopy(context);
      if (mounted && outcome != null) setState(() => _copyNote = _noteFor(outcome));
    } finally {
      _copyBusy = false;
    }
  }

  Future<void> _bringInCopy() async {
    if (_copyBusy) return;
    _copyBusy = true;
    try {
      final outcome = await bringInACopy(
        context,
        onPicked: () {
          if (mounted) setState(() => _copyNote = null);
        },
      );
      if (mounted && outcome != null) setState(() => _copyNote = _noteFor(outcome));
    } finally {
      _copyBusy = false;
    }
  }

  Widget _section({required String label, required List<Widget> rows, List<Widget> below = const []}) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SkyListGroup(label: label, children: rows),
        ...below,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    final space = context.space;
    final vault = context.watch<VaultService>();
    final identity = context.watch<IdentityController>();
    final quick = context.watch<QuickUnlockService>();
    final notices = context.watch<AppNotices>();
    final peer = context.watch<PeerLink?>();
    final link = peer?.state ?? PeerLinkView.offline;
    final sky = SkyModeScope.maybeOf(context);
    _queueStars(identity.myOwnerId);

    final couple = vault.config?.coupleNames.trim() ?? '';
    final startText = vault.config?.startDate ?? '';
    final start = startText.isEmpty ? null : parseLocalDate(startText);
    final me = identity.me;
    final partner = identity.partner;
    final ready = identity.status == IdentityStatus.ready && me != null;
    final myName = me?.name.trim() ?? '';
    final partnerName = partner?.name.trim() ?? '';
    final peopleTitle = myName.isNotEmpty && partnerName.isNotEmpty ? SettingsCopy.names2(myName, partnerName) : null;
    final title = peopleTitle ?? (couple.isEmpty ? null : couple);
    final subtitle = [
      if (start != null) SettingsCopy.since(settingsLongDate(start)),
      if ((_stars ?? 0) > 0) SettingsCopy.stars(_stars!),
    ].join(SettingsCopy.separator);
    final namesValue = !ready
        ? null
        : partner == null
        ? (myName.isEmpty ? NamesCopy.noNameYet : myName)
        : SettingsCopy.names2(
            myName.isEmpty ? NamesCopy.noNameYet : myName,
            partnerName.isEmpty ? NamesCopy.noNameYet : partnerName,
          );
    final savedAt = lastCopySavedAt(space);
    final warning = link.error == null ? notices.syncWarning : null;

    final thisPhone = <Widget>[
      if (quick.available)
        SettingsRow(
          key: SettingsPage.touchKey,
          icon: SkyIcons.finger,
          tone: SkyTone.gold,
          title: TouchCopy.title,
          subtitle: quick.enrolled ? TouchCopy.onBody : TouchCopy.offBody,
          onTap: _toggleTouch,
          trailing: SkyToggle(value: quick.enrolled, semanticLabel: TouchCopy.title, onChanged: (_) => _toggleTouch()),
        ),
      if (space.push.available)
        RemindersRow(
          key: SettingsPage.remindersKey,
          push: space.push,
          onNote: (note) {
            if (mounted) setState(() => _phoneNote = note);
          },
        ),
      if (sky != null)
        ListenableBuilder(
          key: const ValueKey<String>('settings-sky'),
          listenable: sky,
          builder: (context, _) => SettingsRow(
            icon: SkyIcons.moon,
            tone: SkyTone.lavender,
            title: SettingsCopy.skyFollows,
            subtitle: SettingsCopy.skyFollowsHint,
            onTap: () => sky.setFollowsTime(!sky.followsTime),
            trailing: SkyToggle(
              key: ShellKeys.skyFollowsTime,
              value: sky.followsTime,
              semanticLabel: SettingsCopy.skyFollows,
              onChanged: (value) => sky.setFollowsTime(value),
            ),
          ),
        ),
    ];

    final twoOfUs = <Widget>[
      if (ready)
        SettingsRow(
          key: SettingsPage.namesKey,
          icon: SkyIcons.pen,
          tone: SkyTone.rose,
          title: SettingsCopy.names,
          value: namesValue,
          onTap: () => unawaited(showNamesSheet(context)),
        ),
      SettingsRow(
        key: SettingsPage.togetherKey,
        icon: SkyIcons.calendar,
        tone: SkyTone.gold,
        title: SettingsCopy.togetherSince,
        value: start == null ? SettingsCopy.notSet : settingsShortDate(start),
        onTap: () => unawaited(_pickTogetherSince()),
      ),
      SettingsRow(
        key: SettingsPage.phonesKey,
        icon: SkyIcons.phone,
        tone: SkyTone.lavender,
        title: SettingsCopy.addPhone,
        subtitle: SettingsCopy.addPhoneHint,
        onTap: () => unawaited(openAddPhone(context)),
      ),
      SettingsRow(
        key: SettingsPage.connectionKey,
        icon: SkyIcons.us,
        tone: SkyTone.rose,
        title: TogetherNowCopy.title,
        subtitle: togetherSentence(link, now: _now),
        chevron: true,
        trailing: StatusDot(state: togetherStateOf(link)),
        onTap: () => unawaited(showTogetherNowSheet(context)),
      ),
    ];

    final keepCopy = <Widget>[
      SettingsRow(
        key: SettingsPage.saveCopyKey,
        icon: SkyIcons.download,
        tone: SkyTone.gold,
        title: BackupCopy.saveCopy,
        subtitle: savedAt == null
            ? BackupCopy.saveHint
            : BackupCopy.lastSaved(settingsDayMonth(DateTime.fromMillisecondsSinceEpoch(savedAt))),
        onTap: () => unawaited(_saveCopy()),
      ),
      SettingsRow(
        key: SettingsPage.bringInKey,
        icon: SkyIcons.upload,
        tone: SkyTone.lavender,
        title: BackupCopy.bringInCopy,
        subtitle: BackupCopy.bringInHint,
        onTap: () => unawaited(_bringInCopy()),
      ),
    ];

    return SkyScrollScaffold(
      scene: SettingsPage.scene,
      topBar: const SkyTopBar(title: SettingsCopy.title, compact: true, leading: SkyBackButton()),
      padding: const EdgeInsets.fromLTRB(SkySpace.gutter, SkySpace.gutter, SkySpace.gutter, 0),
      spacing: SkySpace.xl,
      children: [
        CoupleHeader(
          myInitial: me != null ? SkyAvatar.initialOf(identity.myName) : SkyAvatar.initialOf(couple, fallback: 'O'),
          partnerInitial: partner != null ? SkyAvatar.initialOf(identity.partnerName) : null,
          title: title,
          subtitle: subtitle,
        ),
        _section(
          label: SettingsCopy.thisPhone,
          rows: thisPhone,
          below: [
            SettingsNotes(
              notes: [if (_phoneNote != null) _phoneNote!],
              onDismiss: (_) => setState(() => _phoneNote = null),
            ),
          ],
        ),
        _section(
          label: SettingsCopy.twoOfUs,
          rows: twoOfUs,
          below: [
            SettingsNotes(notes: [if (_usNote != null) _usNote!], onDismiss: (_) => setState(() => _usNote = null)),
            TogetherNowAlerts(
              link: link,
              peer: peer,
              warning: warning,
              partnerName: identity.partnerName,
              showSyncing: false,
              gap: SkySpace.md,
            ),
          ],
        ),
        _section(
          label: SettingsCopy.keepCopy,
          rows: keepCopy,
          below: [
            SettingsNotes(
              notes: [if (_copyNote != null) _copyNote!],
              onDismiss: (_) => setState(() => _copyNote = null),
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 2),
            SkyButton(
              key: ShellKeys.lockNow,
              label: SettingsCopy.lockNow,
              icon: SkyIcons.lock,
              variant: SkyButtonVariant.ghost,
              onPressed: vault.lock,
            ),
            const SizedBox(height: SkySpace.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SkyIcon(SkyIcons.lock, size: 12, color: t.faint),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    SettingsCopy.lockedFooter,
                    textAlign: TextAlign.center,
                    style: SkyType.caption.copyWith(color: t.faint),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
