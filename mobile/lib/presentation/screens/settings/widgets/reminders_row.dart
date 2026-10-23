import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../../core/engine.dart';
import '../../../sky/sky.dart';
import '../../../widgets/app_haptics.dart';
import 'settings_row.dart';
import 'sheet_parts.dart';

abstract final class SystemSettings {
  static const MethodChannel channel = MethodChannel('our_space/system_settings');

  static Future<bool> Function() openNotifications = _openNotifications;

  static Future<bool> _openNotifications() async {
    try {
      return await channel.invokeMethod<bool>('notifications') ?? false;
    } catch (_) {
      return false;
    }
  }
}

abstract final class RemindersCopy {
  static const String title = 'Little reminders';
  static const String on = 'When something new is waiting';
  static const String off = 'Off for now. Tap to turn them on';
  static const String turnedOn = 'Little reminders are on. We will tap you when something new is waiting.';
  static const String openYourself =
      'We could not open your phone settings. Look for Our Space there to turn reminders on or off.';
}

class RemindersRow extends StatefulWidget {
  const RemindersRow({super.key, required this.push, this.onNote});

  final PushService push;
  final ValueChanged<SettingsNote?>? onNote;

  @override
  State<RemindersRow> createState() => _RemindersRowState();
}

class _RemindersRowState extends State<RemindersRow> with WidgetsBindingObserver {
  bool? _allowed;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final platform = widget.push.platform;
    if (platform == null) return;
    bool allowed;
    try {
      allowed = await platform.isAllowed();
    } catch (_) {
      allowed = false;
    }
    if (mounted && allowed != _allowed) setState(() => _allowed = allowed);
  }

  Future<void> _change() async {
    final platform = widget.push.platform;
    if (platform == null || _busy) return;
    _busy = true;
    widget.onNote?.call(null);
    try {
      if (_allowed != true) {
        var granted = false;
        try {
          granted = await platform.requestPermission();
        } catch (_) {}
        if (!mounted) return;
        if (granted) {
          setState(() => _allowed = true);
          AppHaptics.celebration();
          widget.onNote?.call(const SettingsNote(RemindersCopy.turnedOn));
          unawaited(widget.push.check());
          return;
        }
      }
      final opened = await SystemSettings.openNotifications();
      if (!mounted) return;
      if (!opened) widget.onNote?.call(const SettingsNote.info(RemindersCopy.openYourself));
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final allowed = _allowed == true;
    return SettingsRow(
      icon: SkyIcons.bell,
      tone: SkyTone.rose,
      title: RemindersCopy.title,
      subtitle: allowed ? RemindersCopy.on : RemindersCopy.off,
      onTap: _change,
      trailing: SkyToggle(value: allowed, semanticLabel: RemindersCopy.title, onChanged: (_) => _change()),
    );
  }
}
