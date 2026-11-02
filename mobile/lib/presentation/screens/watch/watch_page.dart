import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../sky/sky.dart';
import 'watch_copy.dart';
import 'watch_player.dart';
import 'watch_room.dart';

abstract final class WatchKeys {
  static const Key entry = ValueKey<String>('watch-entry');
  static const Key invite = ValueKey<String>('watch-invite');
  static const Key linkField = ValueKey<String>('watch-link-field');
  static const Key paste = ValueKey<String>('watch-paste');
  static const Key start = ValueKey<String>('watch-start');
  static const Key join = ValueKey<String>('watch-join');
  static const Key video = ValueKey<String>('watch-video');
  static const Key playPause = ValueKey<String>('watch-play-pause');
  static const Key seek = ValueKey<String>('watch-seek');
  static const Key status = ValueKey<String>('watch-status');
  static const Key audio = ValueKey<String>('watch-audio');
  static const Key subtitles = ValueKey<String>('watch-subtitles');
  static const Key subtitlesOff = ValueKey<String>('watch-subtitles-off');
  static const Key cues = ValueKey<String>('watch-cues');
  static const Key fullscreen = ValueKey<String>('watch-fullscreen');
  static const Key pill = ValueKey<String>('watch-pill');
  static const Key skip = ValueKey<String>('watch-skip');
  static const Key waiting = ValueKey<String>('watch-waiting');

  static Key track(String id) => ValueKey<String>('watch-track-$id');
}

abstract final class WatchScreen {
  static const MethodChannel channel = MethodChannel('our_space/system_settings');

  static Future<void> Function(bool on) keepOn = _keepOn;

  static Future<void> _keepOn(bool on) async {
    try {
      await channel.invokeMethod<void>('keepScreenOn', on);
    } catch (_) {}
  }
}

class WatchScope extends InheritedWidget {
  const WatchScope({super.key, required this.room, required super.child});

  final WatchRoom? room;

  static WatchRoom? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<WatchScope>()?.room;

  @override
  bool updateShouldNotify(WatchScope oldWidget) => !identical(oldWidget.room, room);
}

Future<void> openWatchPage(BuildContext context, {required WatchRoom room, required String partner, bool join = false}) {
  return skyPush<void>(
    context,
    (_) => WatchPage(room: room, partner: partner, joinOnOpen: join),
    settings: const RouteSettings(name: WatchPage.routeName),
  );
}

class WatchEntry extends StatelessWidget {
  const WatchEntry({super.key = WatchKeys.entry, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SkyListGroup(
      children: [
        SkyListRow(
          title: WatchCopy.title,
          subtitle: WatchCopy.entryHint,
          icon: SkyIcons.film,
          tone: SkyTone.rose,
          chevron: true,
          onTap: onTap,
        ),
      ],
    );
  }
}

class WatchInvite extends StatelessWidget {
  const WatchInvite({super.key, required this.room, required this.partner});

  final WatchRoom room;
  final String partner;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: room,
      builder: (context, _) {
        if (!room.invited) return const SizedBox.shrink();
        return Align(
          alignment: Alignment.topCenter,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(SkySpace.gutter),
              child: SkyNotice(
                key: WatchKeys.invite,
                text: WatchCopy.invited(partner),
                icon: SkyIcons.film,
                elevated: true,
                actionLabel: WatchCopy.joinLabel,
                onAction: () => unawaited(openWatchPage(context, room: room, partner: partner, join: true)),
                onDismiss: room.decline,
                dismissLabel: WatchCopy.notNow,
              ),
            ),
          ),
        );
      },
    );
  }
}

class WatchPage extends StatefulWidget {
  const WatchPage({super.key, required this.room, required this.partner, this.joinOnOpen = false});

  static const String routeName = '/watch';

  final WatchRoom room;
  final String partner;
  final bool joinOnOpen;

  @override
  State<WatchPage> createState() => _WatchPageState();
}

class _WatchPageState extends State<WatchPage> {
  static const Duration _controlsFor = Duration(seconds: 4);
  static const Duration _noticeFor = Duration(seconds: 3);
  static const Duration _skipFor = Duration(milliseconds: 700);
  static const Color _black = Color(0xFF000000);

  final TextEditingController _link = TextEditingController();
  String? _error;
  bool _controls = true;
  bool _full = false;
  bool _asking = false;
  bool _wasPlaying = false;
  int _noticeSeen = 0;
  String? _notice;
  String? _skipped;
  Offset _lastTap = Offset.zero;
  double _tapWidth = 0;
  Timer? _hide;
  Timer? _noticeHide;
  Timer? _skipHide;

  WatchRoom get _room => widget.room;

  @override
  void initState() {
    super.initState();
    _noticeSeen = _room.noticeCount;
    _wasPlaying = _room.playing;
    _room.addListener(_onRoom);
    unawaited(WatchScreen.keepOn(true));
    unawaited(
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]),
    );
    if (widget.joinOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _room.join();
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final full = MediaQuery.orientationOf(context) == Orientation.landscape;
    if (full == _full) return;
    _full = full;
    unawaited(SystemChrome.setEnabledSystemUIMode(full ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge));
    if (full) {
      _controls = true;
      _armHide();
    }
  }

  void _onRoom() {
    if (!mounted) return;
    final playing = _room.playing;
    if (playing && !_wasPlaying && _full) _armHide();
    _wasPlaying = playing;
    if (_room.noticeCount == _noticeSeen) return;
    _noticeSeen = _room.noticeCount;
    final text = _noticeText(_room.notice);
    if (text == null) return;
    setState(() => _notice = text);
    _noticeHide?.cancel();
    _noticeHide = Timer(_noticeFor, () {
      if (mounted) setState(() => _notice = null);
    });
  }

  String? _noticeText(WatchNotice? notice) => switch (notice) {
    WatchNotice.paused => WatchCopy.paused(widget.partner),
    WatchNotice.played => WatchCopy.played(widget.partner),
    WatchNotice.moved => WatchCopy.moved(widget.partner),
    WatchNotice.joined => WatchCopy.joined(widget.partner),
    WatchNotice.left => WatchCopy.left(widget.partner),
    null => null,
  };

  void _toggleFull() {
    unawaited(
      SystemChrome.setPreferredOrientations(
        _full ? const [DeviceOrientation.portraitUp] : const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight],
      ),
    );
  }

  void _skip(double width) {
    if (width <= 0) return;
    final ahead = _lastTap.dx >= width / 2;
    _room.skip(ahead ? WatchRoom.skipMs : -WatchRoom.skipMs);
    setState(() => _skipped = ahead ? WatchCopy.skipAhead : WatchCopy.skipBack);
    _skipHide?.cancel();
    _skipHide = Timer(_skipFor, () {
      if (mounted) setState(() => _skipped = null);
    });
  }

  Future<void> _onBack() async {
    if (_full) {
      _toggleFull();
      return;
    }
    if (_asking) return;
    _asking = true;
    final leave = await showSkyConfirm(
      context,
      title: WatchCopy.leaveTitle,
      message: _room.partnerIn ? WatchCopy.leaveWith(widget.partner) : WatchCopy.leaveAlone,
      confirmLabel: WatchCopy.leaveYes,
      cancelLabel: WatchCopy.leaveStay,
      icon: SkyIcons.film,
    );
    _asking = false;
    if (leave && mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _room.removeListener(_onRoom);
    _hide?.cancel();
    _noticeHide?.cancel();
    _skipHide?.cancel();
    _link.dispose();
    final room = _room;
    scheduleMicrotask(room.leave);
    unawaited(WatchScreen.keepOn(false));
    unawaited(SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]));
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  void _armHide() {
    _hide?.cancel();
    _hide = Timer(_controlsFor, () {
      if (mounted && _full && _room.playing) setState(() => _controls = false);
    });
  }

  void _showControls() {
    setState(() => _controls = true);
    _armHide();
  }

  void _start() {
    if (_room.start(_link.text)) {
      if (_error != null) setState(() => _error = null);
      FocusScope.of(context).unfocus();
    } else {
      final secure = _link.text.trim().toLowerCase().startsWith('https://');
      setState(() => _error = secure ? WatchCopy.linkBroken : WatchCopy.linkInvalid);
    }
  }

  Future<void> _paste() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim() ?? '';
    if (!mounted) return;
    if (text.isEmpty) {
      setState(() => _error = WatchCopy.pasteEmpty);
      return;
    }
    _link.text = text;
    setState(() => _error = null);
  }

  String? _statusText() {
    final player = _room.player;
    if (player != null && player.failed) return WatchCopy.wontPlay;
    if (player != null && !player.ready) return WatchCopy.loading;
    if (player != null && player.buffering && _room.held) return WatchCopy.catchingUpMine;
    if (_room.partnerFailed) return WatchCopy.partnerCantPlay(widget.partner);
    if (_room.partnerWaiting) return WatchCopy.catchingUp(widget.partner);
    return _room.partnerIn ? WatchCopy.withPartner(widget.partner) : WatchCopy.waitingFor(widget.partner);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _room,
      builder: (context, _) {
        final player = _room.player;
        final watching = _room.inRoom && player != null;
        return PopScope<void>(
          canPop: !_room.inRoom,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) unawaited(_onBack());
          },
          child: _full && watching
              ? _fullScreen(player)
              : SkyScaffold(
                  body: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SkyTopBar(
                        kicker: WatchCopy.kicker,
                        title: WatchCopy.title,
                        leading: const SkyBackButton(semanticLabel: WatchCopy.back),
                      ),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(SkySpace.gutter, SkySpace.md, SkySpace.gutter, SkySpace.gutter),
                          children: watching ? _watching(player) : _before(),
                        ),
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }

  List<Widget> _before() {
    return [
      if (_room.offered) ...[
        SkyCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _room.invited ? WatchCopy.invited(widget.partner) : WatchCopy.stillWatching(widget.partner),
                style: context.skyText.body,
              ),
              const SizedBox(height: SkySpace.md),
              SkyButton(key: WatchKeys.join, label: WatchCopy.joinLabel, icon: SkyIcons.film, onPressed: _room.join),
            ],
          ),
        ),
        const SizedBox(height: SkySpace.lg),
      ],
      SkyTextField(
        key: WatchKeys.linkField,
        controller: _link,
        label: WatchCopy.linkLabel,
        hint: WatchCopy.linkHint,
        keyboardType: TextInputType.url,
        textCapitalization: TextCapitalization.none,
        textInputAction: TextInputAction.go,
        leadingIcon: SkyIcons.link,
        onSubmitted: (_) => _start(),
      ),
      const SizedBox(height: SkySpace.xs),
      Semantics(
        liveRegion: _error != null,
        child: Text(
          _error ?? WatchCopy.linkHelp,
          style: context.skyText.bodySmall.copyWith(color: _error == null ? context.sky.faint : context.sky.rose),
        ),
      ),
      const SizedBox(height: SkySpace.md),
      SkyButton(
        key: WatchKeys.paste,
        label: WatchCopy.paste,
        icon: SkyIcons.copy,
        variant: SkyButtonVariant.ghost,
        onPressed: () => unawaited(_paste()),
      ),
      const SizedBox(height: SkySpace.sm),
      SkyButton(key: WatchKeys.start, label: WatchCopy.start, icon: SkyIcons.play, onPressed: _start),
    ];
  }

  List<Widget> _watching(WatchPlayer player) {
    return [
      ClipRRect(
        borderRadius: SkyRadii.all(SkyRadii.card),
        child: LayoutBuilder(
          builder: (context, box) => _gestures(width: box.maxWidth, child: _video(player)),
        ),
      ),
      const SizedBox(height: SkySpace.md),
      _Controls(room: _room, player: player, full: false, onFull: _toggleFull),
      const SizedBox(height: SkySpace.md),
      Text(
        _statusText() ?? '',
        key: WatchKeys.status,
        textAlign: TextAlign.center,
        style: context.skyText.body,
      ),
    ];
  }

  Widget _gestures({required double width, required Widget child, VoidCallback? onTap}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onDoubleTapDown: (details) {
        _lastTap = details.localPosition;
        _tapWidth = width;
      },
      onDoubleTap: () => _skip(_tapWidth),
      child: child,
    );
  }

  Widget _video(WatchPlayer player) {
    final held = _room.held ? _statusText() : null;
    final pill = _notice ?? held;
    final skipped = _skipped;
    final lift = _full && _controls ? 96.0 : 0.0;
    return ColoredBox(
      key: WatchKeys.video,
      color: _black,
      child: AspectRatio(
        aspectRatio: player.aspect > 0 ? player.aspect : 16 / 9,
        child: player.ready
            ? Stack(
                fit: StackFit.expand,
                children: [
                  player.view(),
                  if (player.cues.isNotEmpty) _Cues(lines: player.cues, lift: lift),
                  if (player.buffering || _room.held)
                    const IgnorePointer(
                      child: Center(
                        key: WatchKeys.waiting,
                        child: SkySpinner(size: 30, color: SkyTokens.white),
                      ),
                    ),
                  if (pill != null)
                    Align(
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(top: SkySpace.md),
                        child: _Pill(key: WatchKeys.pill, text: pill),
                      ),
                    ),
                  if (skipped != null)
                    Align(
                      alignment: skipped == WatchCopy.skipAhead ? Alignment.centerRight : Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: SkySpace.xl),
                        child: _Pill(key: WatchKeys.skip, text: skipped),
                      ),
                    ),
                ],
              )
            : const Center(child: SkySpinner(size: 26, color: SkyTokens.white)),
      ),
    );
  }

  Widget _fade(Alignment from, Alignment to, Widget child) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: from,
          end: to,
          colors: [_black.withValues(alpha: 0.82), _black.withValues(alpha: 0)],
        ),
      ),
      child: SafeArea(child: child),
    );
  }

  Widget _fullScreen(WatchPlayer player) {
    return Material(
      color: _black,
      child: LayoutBuilder(
        builder: (context, box) => _gestures(
          width: box.maxWidth,
          onTap: () {
            if (_controls) {
              _hide?.cancel();
              setState(() => _controls = false);
            } else {
              _showControls();
            }
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(child: _video(player)),
              if (_controls) ...[
                Align(
                  alignment: Alignment.topCenter,
                  child: _fade(
                    Alignment.topCenter,
                    Alignment.bottomCenter,
                    Padding(
                      padding: const EdgeInsets.fromLTRB(SkySpace.md, SkySpace.xs, SkySpace.md, SkySpace.xl),
                      child: Row(
                        children: [
                          SkyIconButton(
                            icon: SkyIcons.back,
                            tone: SkyIconButtonTone.ghost,
                            iconColor: SkyTokens.white,
                            semanticLabel: WatchCopy.fullscreenExit,
                            onPressed: _toggleFull,
                          ),
                          const SizedBox(width: SkySpace.sm),
                          Expanded(
                            child: Text(
                              _statusText() ?? '',
                              key: WatchKeys.status,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.skyText.bodySmall.copyWith(color: SkyTokens.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: _fade(
                    Alignment.bottomCenter,
                    Alignment.topCenter,
                    Padding(
                      padding: const EdgeInsets.fromLTRB(SkySpace.lg, SkySpace.xl, SkySpace.lg, SkySpace.xs),
                      child: _Controls(room: _room, player: player, full: true, onFull: _toggleFull),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Semantics(
        liveRegion: true,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: SkySpace.md, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xB3000000),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            text,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: context.skyText.bodySmall.copyWith(color: SkyTokens.white, decoration: TextDecoration.none),
          ),
        ),
      ),
    );
  }
}

class _Controls extends StatefulWidget {
  const _Controls({required this.room, required this.player, required this.full, required this.onFull});

  final WatchRoom room;
  final WatchPlayer player;
  final bool full;
  final VoidCallback onFull;

  @override
  State<_Controls> createState() => _ControlsState();
}

class _ControlsState extends State<_Controls> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final player = widget.player;
    final t = context.sky;
    final canPlay = player.ready;
    final full = widget.full;
    final small = full ? context.skyText.bodySmall.copyWith(color: SkyTokens.white) : context.skyText.bodySmall;
    final tone = full ? SkyIconButtonTone.ghost : SkyIconButtonTone.surface;
    final iconColor = full ? SkyTokens.white : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (canPlay && player.live)
          Text(WatchCopy.live, style: small)
        else if (canPlay)
          ValueListenableBuilder<int>(
            valueListenable: room.positionMs,
            builder: (context, position, _) {
              final duration = player.durationMs;
              final shown = _dragging ?? position.clamp(0, duration).toDouble();
              return Row(
                children: [
                  Text(WatchCopy.clock(shown.round()), style: small),
                  Expanded(
                    child: Semantics(
                      label: WatchCopy.seekLabel,
                      child: Slider(
                        key: WatchKeys.seek,
                        value: shown,
                        max: duration.toDouble(),
                        activeColor: t.rose,
                        inactiveColor: full ? SkyTokens.white.withValues(alpha: 0.28) : null,
                        onChanged: (value) => setState(() => _dragging = value),
                        onChangeEnd: (value) {
                          setState(() => _dragging = null);
                          room.seek(value.round());
                        },
                      ),
                    ),
                  ),
                  Text(WatchCopy.clock(duration), style: small),
                ],
              );
            },
          ),
        Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: player.audioTracks.length > 1
                    ? SkyIconButton(
                        key: WatchKeys.audio,
                        icon: SkyIcons.audio,
                        tone: tone,
                        iconColor: iconColor,
                        semanticLabel: WatchCopy.audio,
                        onPressed: () => unawaited(_pickAudio(context, player)),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
            const SizedBox(width: SkySpace.md),
            SkyIconButton(
              key: WatchKeys.playPause,
              icon: room.playing ? SkyIcons.pause : SkyIcons.play,
              tone: tone,
              iconColor: iconColor,
              semanticLabel: room.playing ? WatchCopy.pause : WatchCopy.play,
              onPressed: canPlay ? room.togglePlay : null,
            ),
            const SizedBox(width: SkySpace.md),
            Expanded(
              child: Row(
                children: [
                  if (player.subtitleTracks.isNotEmpty) ...[
                    SkyIconButton(
                      key: WatchKeys.subtitles,
                      icon: SkyIcons.subtitles,
                      tone: tone,
                      iconColor: iconColor,
                      semanticLabel: WatchCopy.subtitles,
                      onPressed: () => unawaited(_pickSubtitle(context, player)),
                    ),
                    const SizedBox(width: SkySpace.md),
                  ],
                  SkyIconButton(
                    key: WatchKeys.fullscreen,
                    icon: full ? SkyIcons.fullscreenExit : SkyIcons.fullscreen,
                    tone: tone,
                    iconColor: iconColor,
                    semanticLabel: full ? WatchCopy.fullscreenExit : WatchCopy.fullscreen,
                    onPressed: widget.onFull,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

Future<void> _pickAudio(BuildContext context, WatchPlayer player) {
  return showSkySheet<void>(
    context: context,
    builder: (sheet) => _TrackSheet(
      title: WatchCopy.audio,
      tracks: player.audioTracks,
      onPick: (track) => unawaited(player.selectAudio(track.id)),
    ),
  );
}

Future<void> _pickSubtitle(BuildContext context, WatchPlayer player) {
  return showSkySheet<void>(
    context: context,
    builder: (sheet) => _TrackSheet(
      title: WatchCopy.subtitles,
      tracks: player.subtitleTracks,
      onPick: (track) => unawaited(player.selectSubtitle(track.id)),
      onOff: () => unawaited(player.selectSubtitle(null)),
    ),
  );
}

class _TrackSheet extends StatelessWidget {
  const _TrackSheet({required this.title, required this.tracks, required this.onPick, this.onOff});

  final String title;
  final List<WatchTrack> tracks;
  final ValueChanged<WatchTrack> onPick;
  final VoidCallback? onOff;

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    Widget? tick(bool on) => on ? SkyIcon(SkyIcons.check, size: 18, color: t.rose) : null;
    void close(VoidCallback action) {
      action();
      Navigator.of(context).pop();
    }

    final off = onOff;
    final rows = <Widget>[
      if (off != null)
        SkyListRow(
          key: WatchKeys.subtitlesOff,
          title: WatchCopy.subtitlesOff,
          trailing: tick(!tracks.any((track) => track.selected)),
          chevron: false,
          onTap: () => close(off),
        ),
      for (final (index, track) in tracks.indexed)
        SkyListRow(
          key: WatchKeys.track(track.id),
          title: track.label ?? WatchCopy.track(index + 1),
          value: track.detail,
          trailing: tick(track.selected),
          chevron: false,
          onTap: () => close(() => onPick(track)),
        ),
    ];
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: context.skyText.title),
          const SizedBox(height: SkySpace.md),
          SkyListGroup(children: rows),
        ],
      ),
    );
  }
}

class _Cues extends StatelessWidget {
  const _Cues({required this.lines, this.lift = 0});

  final List<String> lines;
  final double lift;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, box) {
          final size = (box.maxWidth * 0.04).clamp(13.0, 26.0);
          return Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.fromLTRB(box.maxWidth * 0.05, 0, box.maxWidth * 0.05, box.maxHeight * 0.05 + lift),
              child: Text(
                lines.join('\n'),
                key: WatchKeys.cues,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: const Color(0xFFFFFFFF),
                  fontSize: size,
                  height: 1.25,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.none,
                  shadows: const [
                    Shadow(color: Color(0xE6000000), blurRadius: 4),
                    Shadow(color: Color(0xCC000000), offset: Offset(0, 1), blurRadius: 2),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
