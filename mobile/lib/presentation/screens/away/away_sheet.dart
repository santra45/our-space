import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/engine.dart';
import '../../route_requests.dart';
import '../../sky/sky.dart';
import '../../widgets/app_haptics.dart';
import '../settings/widgets/settings_row.dart';
import '../settings/widgets/sheet_parts.dart';

abstract final class AwayCopy {
  static const String partnerFallback = 'Your partner';
  static const String title = 'While you were away';
  static const String subtitle = 'The little things that came in from the other phone.';
  static const String empty = 'Nothing new yet. Whatever comes in next will wait for you here.';
  static const String markAllRead = 'Mark all as read';
  static const String clear = 'Clear the list';
  static const String bell = 'While you were away';
  static const String justNow = 'just now';
  static const String yesterday = 'yesterday';

  static String _who(String partner) {
    final name = partner.trim();
    return name.isEmpty ? partnerFallback : name;
  }

  static String line(AwayEntry entry, String partner) {
    final who = _who(partner);
    final n = entry.count;
    switch (entry.kind) {
      case AwayKind.letter:
        return n == 1 ? '$who left you a letter' : '$who left you $n letters';
      case AwayKind.opened:
        return '$who read your letter';
      case AwayKind.polaroid:
        return n == 1 ? '$who added a polaroid' : '$who added $n polaroids';
      case AwayKind.love:
        return n == 1 ? '$who sent you a little love' : '$who sent you a little love, $n times';
      case AwayKind.dream:
        return n == 1 ? '$who added a dream for you two' : '$who added $n dreams for you two';
      case AwayKind.done:
        return '$who ticked off one of your dreams';
      case AwayKind.answer:
        return "$who answered today's question";
      case AwayKind.countdown:
        return n == 1 ? '$who added something to count down to' : '$who added $n things to count down to';
    }
  }

  static String ago(int at, int now) {
    final seconds = ((now - at) / 1000).floor();
    if (seconds < 60) return justNow;
    final minutes = seconds ~/ 60;
    if (minutes < 60) return '$minutes min ago';
    final hours = minutes ~/ 60;
    if (hours < 24) return hours == 1 ? '1 hour ago' : '$hours hours ago';
    final days = hours ~/ 24;
    if (days == 1) return yesterday;
    return '$days days ago';
  }
}

String awayRoute(AwayEntry entry) {
  switch (entry.kind) {
    case AwayKind.letter:
    case AwayKind.opened:
      return ReminderRoutes.letter(entry.recordId);
    case AwayKind.polaroid:
      return ReminderRoutes.memory(entry.recordId);
    case AwayKind.love:
      return 'love';
    case AwayKind.dream:
    case AwayKind.done:
      return 'us/dreams';
    case AwayKind.answer:
      return ReminderRoutes.daily;
    case AwayKind.countdown:
      return ReminderRoutes.us;
  }
}

SkyIcons awayIcon(AwayKind kind) {
  switch (kind) {
    case AwayKind.letter:
    case AwayKind.opened:
      return SkyIcons.letter;
    case AwayKind.polaroid:
      return SkyIcons.photo;
    case AwayKind.love:
      return SkyIcons.heart;
    case AwayKind.dream:
    case AwayKind.done:
      return SkyIcons.sparkle;
    case AwayKind.answer:
      return SkyIcons.star;
    case AwayKind.countdown:
      return SkyIcons.calendar;
  }
}

SkyTone awayTone(AwayKind kind) {
  switch (kind) {
    case AwayKind.letter:
    case AwayKind.opened:
    case AwayKind.love:
      return SkyTone.rose;
    case AwayKind.polaroid:
    case AwayKind.countdown:
      return SkyTone.gold;
    case AwayKind.dream:
    case AwayKind.done:
    case AwayKind.answer:
      return SkyTone.lavender;
  }
}

Future<void> showAwaySheet(BuildContext context) {
  final feed = context.read<AwayFeed?>();
  final routes = context.read<RouteRequests?>();
  final identity = context.read<IdentityController?>();
  if (feed == null) return Future<void>.value();
  return showSkySheet<void>(
    context: context,
    builder: (_) => AwaySheet(feed: feed, routes: routes, partner: identity?.partnerName ?? ''),
  );
}

class AwaySheet extends StatelessWidget {
  const AwaySheet({super.key, required this.feed, required this.partner, this.routes, this.clock});

  static const Key listKey = ValueKey<String>('away-list');
  static const Key markAllKey = ValueKey<String>('away-mark-all');
  static const Key clearKey = ValueKey<String>('away-clear');

  final AwayFeed feed;
  final RouteRequests? routes;
  final String partner;
  final int Function()? clock;

  void _open(BuildContext context, AwayEntry entry) {
    AppHaptics.tap();
    feed.markRead(entry.id);
    Navigator.of(context).maybePop();
    routes?.open(awayRoute(entry));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.sky;
    return ListenableBuilder(
      listenable: feed,
      builder: (context, _) {
        final entries = feed.entries;
        final now = clock?.call() ?? DateTime.now().millisecondsSinceEpoch;
        return SheetScroll(
          children: [
            SheetHeader(
              title: AwayCopy.title,
              subtitle: AwayCopy.subtitle,
              icon: SkyIcons.bell,
              tone: SkyTone.rose,
              onClose: () => Navigator.of(context).maybePop(),
            ),
            if (entries.isEmpty)
              Text(AwayCopy.empty, style: SkyType.bodySmall.copyWith(color: t.muted, height: 1.45))
            else
              SkyListGroup(
                key: listKey,
                children: [
                  for (final entry in entries)
                    SettingsRow(
                      key: ValueKey<String>('away-${entry.id}'),
                      icon: awayIcon(entry.kind),
                      tone: awayTone(entry.kind),
                      title: AwayCopy.line(entry, partner),
                      subtitle: AwayCopy.ago(entry.at, now),
                      trailing: entry.read ? null : _UnreadDot(color: t.rose),
                      chevron: true,
                      onTap: () => _open(context, entry),
                    ),
                ],
              ),
            if (entries.isNotEmpty)
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: SkySpace.lg,
                children: [
                  TextAction(
                    key: markAllKey,
                    label: AwayCopy.markAllRead,
                    enabled: feed.unread > 0,
                    onTap: feed.markAllRead,
                  ),
                  TextAction(key: clearKey, label: AwayCopy.clear, color: t.muted, onTap: feed.clear),
                ],
              ),
          ],
        );
      },
    );
  }
}

class _UnreadDot extends StatelessWidget {
  const _UnreadDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
  }
}

class AwayBell extends StatelessWidget {
  const AwayBell({super.key});

  static const Key bellKey = ValueKey<String>('away-bell');

  @override
  Widget build(BuildContext context) {
    final feed = context.watch<AwayFeed?>();
    if (feed == null || feed.entries.isEmpty) return const SizedBox.shrink();
    final t = context.sky;
    final unread = feed.unread;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        SkyIconButton(
          key: bellKey,
          icon: SkyIcons.bell,
          semanticLabel: unread > 0 ? '${AwayCopy.bell}, $unread new' : AwayCopy.bell,
          tone: SkyIconButtonTone.ghost,
          size: 38,
          onPressed: () => unawaited(showAwaySheet(context)),
        ),
        if (unread > 0)
          Positioned(
            right: 4,
            top: 4,
            child: IgnorePointer(
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: t.rose,
                  shape: BoxShape.circle,
                  border: Border.all(color: t.page, width: 1.5),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
