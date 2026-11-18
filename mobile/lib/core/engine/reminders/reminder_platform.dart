import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

@immutable
class PlannedReminder {
  const PlannedReminder({required this.id, required this.at, required this.title, this.body = '', this.route = ''});

  final String id;
  final int at;
  final String title;
  final String body;
  final String route;

  Map<String, Object?> toArguments() => {'id': id, 'at': at, 'title': title, 'body': body, 'route': route};

  @override
  bool operator ==(Object other) =>
      other is PlannedReminder &&
      other.id == id &&
      other.at == at &&
      other.title == title &&
      other.body == body &&
      other.route == route;

  @override
  int get hashCode => Object.hash(id, at, title, body, route);

  @override
  String toString() => 'PlannedReminder($id at $at: $title)';
}

abstract class ReminderPlatform {
  Future<int> plan(List<PlannedReminder> reminders);

  Future<bool> canNotify();

  Future<void> askPermission();

  Future<String?> takeRoute();

  Stream<String> get opened;
}

class MethodChannelReminders implements ReminderPlatform {
  MethodChannelReminders() {
    channel.setMethodCallHandler(_onCall);
  }

  static const MethodChannel channel = MethodChannel('our_space/reminders');

  final StreamController<String> _opened = StreamController<String>.broadcast();

  Future<Object?> _onCall(MethodCall call) async {
    if (call.method == 'open') {
      final route = call.arguments;
      if (route is String && route.isNotEmpty) _opened.add(route);
    }
    return null;
  }

  @override
  Stream<String> get opened => _opened.stream;

  @override
  Future<int> plan(List<PlannedReminder> reminders) async {
    try {
      return await channel.invokeMethod<int>('plan', [for (final r in reminders) r.toArguments()]) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  @override
  Future<bool> canNotify() async {
    try {
      return await channel.invokeMethod<bool>('canNotify') ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> askPermission() async {
    try {
      await channel.invokeMethod<Object?>('askPermission');
    } catch (_) {}
  }

  @override
  Future<String?> takeRoute() async {
    try {
      final route = await channel.invokeMethod<String>('takeRoute');
      return route == null || route.isEmpty ? null : route;
    } catch (_) {
      return null;
    }
  }
}
