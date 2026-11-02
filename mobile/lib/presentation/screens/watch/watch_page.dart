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

  final TextEditingController _link = TextEditingController();
  String? _error;
  bool _controls = true;
  bool _full = false;
  Timer? _hide;

  WatchRoom get _room => widget.room;

  @override
  void initState() {
    super.initState();
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

  @override
  void dispose() {
    _hide?.cancel();
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
      setState(() => _error = WatchCopy.linkInvalid);
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
        if (_full && _room.inRoom && player != null) return _fullScreen(player);
        return SkyScaffold(
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
                  children: _room.inRoom && player != null ? _watching(player) : _before(),
                ),
              ),
            ],
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
        child: _video(player),
      ),
      const SizedBox(height: SkySpace.md),
      _Controls(room: _room, player: player),
      const SizedBox(height: SkySpace.md),
      Text(
        _statusText() ?? '',
        key: WatchKeys.status,
        textAlign: TextAlign.center,
        style: context.skyText.body,
      ),
    ];
  }

  Widget _video(WatchPlayer player) {
    return ColoredBox(
      key: WatchKeys.video,
      color: const Color(0xFF000000),
      child: AspectRatio(
        aspectRatio: player.aspect > 0 ? player.aspect : 16 / 9,
        child: player.ready ? player.view() : const Center(child: SkySpinner(size: 26)),
      ),
    );
  }

  Widget _fullScreen(WatchPlayer player) {
    return Material(
      color: const Color(0xFF000000),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
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
            if (_controls)
              Align(
                alignment: Alignment.bottomCenter,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(SkySpace.md),
                    child: SkyCard(
                      padding: const EdgeInsets.symmetric(horizontal: SkySpace.md, vertical: SkySpace.xs),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _Controls(room: _room, player: player),
                          Text(
                            _statusText() ?? '',
                            key: WatchKeys.status,
                            textAlign: TextAlign.center,
                            style: context.skyText.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Controls extends StatefulWidget {
  const _Controls({required this.room, required this.player});

  final WatchRoom room;
  final WatchPlayer player;

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
    return Row(
      children: [
        SkyIconButton(
          key: WatchKeys.playPause,
          icon: room.playing ? SkyIcons.pause : SkyIcons.play,
          semanticLabel: room.playing ? WatchCopy.pause : WatchCopy.play,
          onPressed: canPlay ? room.togglePlay : null,
        ),
        const SizedBox(width: SkySpace.xs),
        Expanded(
          child: player.live || !canPlay
              ? Text(player.live && canPlay ? WatchCopy.live : '', style: context.skyText.bodySmall)
              : ValueListenableBuilder<int>(
                  valueListenable: room.positionMs,
                  builder: (context, position, _) {
                    final duration = player.durationMs;
                    final shown = _dragging ?? position.clamp(0, duration).toDouble();
                    return Row(
                      children: [
                        Text(WatchCopy.clock(shown.round()), style: context.skyText.bodySmall),
                        Expanded(
                          child: Semantics(
                            label: WatchCopy.seekLabel,
                            child: Slider(
                              key: WatchKeys.seek,
                              value: shown,
                              max: duration.toDouble(),
                              activeColor: t.rose,
                              onChanged: (value) => setState(() => _dragging = value),
                              onChangeEnd: (value) {
                                setState(() => _dragging = null);
                                room.seek(value.round());
                              },
                            ),
                          ),
                        ),
                        Text(WatchCopy.clock(duration), style: context.skyText.bodySmall),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }
}
