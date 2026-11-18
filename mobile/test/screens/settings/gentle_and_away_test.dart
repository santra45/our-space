import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:our_space_mobile/core/engine.dart';
import 'package:our_space_mobile/presentation/route_requests.dart';
import 'package:our_space_mobile/presentation/screens/away/away_sheet.dart';
import 'package:our_space_mobile/presentation/screens/settings/settings_page.dart';
import 'package:our_space_mobile/presentation/screens/settings/widgets/gentle_reminders.dart';
import 'package:provider/provider.dart';

import '../../reminders_test.dart' show FakeReminders;
import '../../support/harness.dart' show openTestStore;
import '../../widgets/harness.dart' show pumpHost;
import '../sync/hub_harness.dart';

const int now = 1763460000000;

Map<String, Object?> entry(String id, AwayKind kind, String record, {int ago = 0, int count = 1, bool read = false}) => {
      'id': id,
      'k': kind.name,
      'r': record,
      'at': now - ago,
      'n': count,
      'read': read,
    };

Future<AwayFeed> feedWith(WidgetTester tester, List<Map<String, Object?>> entries) async {
  final VaultStore store = await real(tester, openTestStore);
  await real(tester, () => store.settings.setItem('our_space_away', jsonEncode(entries)));
  final feed = AwayFeed(store: store, key: () => null, myOwnerIds: () => const {}, myBurstId: () => '');
  addTearDown(feed.dispose);
  return feed;
}

void main() {
  testWidgets('her reminders sheet switches each kind on, asks for the time, and holds the read ring', (tester) async {
    calm(tester);
    final platform = FakeReminders();
    final space = await openUnlockedSpace(tester, reminders: platform);
    await openSettingsPage(tester, space);
    await untilFound(tester, find.byKey(SettingsPage.gentleKey));
    expect(find.descendant(of: find.byKey(SettingsPage.gentleKey), matching: find.text(GentleCopy.allOff)), findsOneWidget);

    await tapRow(tester, SettingsPage.gentleKey);
    await untilFound(tester, find.text(GentleCopy.title));
    expect(find.byKey(GentleRemindersSheet.timeKey), findsNothing);

    await press(tester, find.byKey(GentleRemindersSheet.toggleKey(ReminderKind.letters)));
    await until(tester, () => space.reminders.isOn(ReminderKind.letters) && platform.plans.isNotEmpty);

    await press(tester, find.byKey(GentleRemindersSheet.toggleKey(ReminderKind.question)));
    await until(tester, () => space.reminders.isOn(ReminderKind.question));
    await untilFound(tester, find.byKey(GentleRemindersSheet.timeKey));
    expect(platform.last.where((r) => r.route == ReminderRoutes.daily), isNotEmpty);

    expect(space.store.ringNotes.tellsOpened, isFalse);
    await press(tester, find.byKey(GentleRemindersSheet.readKey));
    await until(tester, () => space.store.ringNotes.tellsOpened);

    platform.allowed = false;
    await real(tester, space.reminders.refreshAllowed);
    await untilFound(tester, find.byKey(GentleRemindersSheet.blockedKey));
    await press(tester, find.byKey(GentleRemindersSheet.blockedKey));
    await until(tester, () => platform.asks == 1);

    await closeTopModal(tester);
    await untilFound(tester, find.text(GentleCopy.someOn(2)));

    await press(tester, find.byKey(SettingsPage.gentleKey));
    await untilFound(tester, find.text(GentleCopy.title));
    await press(tester, find.byKey(GentleRemindersSheet.toggleKey(ReminderKind.question)));
    await press(tester, find.byKey(GentleRemindersSheet.toggleKey(ReminderKind.letters)));
    await until(tester, () => space.reminders.enabled.isEmpty && platform.last.isEmpty);
    await real(tester, space.close);
  });

  testWidgets('the list says plainly what came in, opens the right place, and can be read or cleared', (tester) async {
    final feed = await feedWith(tester, [
      entry('e3', AwayKind.letter, 'let-1', ago: 30 * 1000),
      entry('e2', AwayKind.polaroid, 'mem-1', ago: 2 * 3600 * 1000, count: 3),
      entry('e1', AwayKind.answer, 'ans-1', ago: 26 * 3600 * 1000, read: true),
    ]);
    final routes = RouteRequests();
    addTearDown(routes.dispose);
    await pumpHost(tester, AwaySheet(feed: feed, routes: routes, partner: 'Sam', clock: () => now));

    expect(find.text('Sam left you a letter'), findsOneWidget);
    expect(find.text('Sam added 3 polaroids'), findsOneWidget);
    expect(find.text("Sam answered today's question"), findsOneWidget);
    expect(find.text(AwayCopy.justNow), findsOneWidget);
    expect(find.text('2 hours ago'), findsOneWidget);
    expect(find.text(AwayCopy.yesterday), findsOneWidget);
    expect(feed.unread, 2);

    await tester.tap(find.text('Sam left you a letter'));
    await tester.pump();
    expect(routes.pending, 'letters/let-1');
    expect(feed.unread, 1);

    await tester.tap(find.byKey(AwaySheet.markAllKey));
    await tester.pump();
    expect(feed.unread, 0);

    await tester.tap(find.byKey(AwaySheet.clearKey));
    await tester.pump();
    expect(feed.entries, isEmpty);
    expect(find.text(AwayCopy.empty), findsOneWidget);
  });

  test('every kind has its own line, falls back to a gentle name, and goes somewhere', () {
    const blank = '';
    for (final kind in AwayKind.values) {
      final one = AwayEntry(id: 'x', kind: kind, recordId: 'rec-1', at: now);
      expect(AwayCopy.line(one, 'Sam'), startsWith('Sam '));
      expect(AwayCopy.line(one, blank), startsWith('Your partner '));
      expect(awayRoute(one), isNotEmpty);
    }
    expect(AwayCopy.line(const AwayEntry(id: 'x', kind: AwayKind.love, recordId: 'b', at: now, count: 4), 'Sam'),
        'Sam sent you a little love, 4 times');
    expect(awayRoute(const AwayEntry(id: 'x', kind: AwayKind.polaroid, recordId: 'mem-9', at: now)), 'memories/mem-9');
    expect(awayRoute(const AwayEntry(id: 'x', kind: AwayKind.done, recordId: 'b-1', at: now)), 'us/dreams');
    expect(AwayCopy.ago(now - 5 * 60 * 1000, now), '5 min ago');
    expect(AwayCopy.ago(now - 3 * 24 * 3600 * 1000, now), '3 days ago');
  });

  testWidgets('the bell only shows when there is something, marks the unread, and opens the list', (tester) async {
    final empty = await feedWith(tester, const []);
    await pumpHost(tester, ChangeNotifierProvider<AwayFeed>.value(value: empty, child: const AwayBell()));
    expect(find.byKey(AwayBell.bellKey), findsNothing);

    final feed = await feedWith(tester, [entry('e1', AwayKind.love, 'burst-his', count: 2)]);
    await pumpHost(tester, ChangeNotifierProvider<AwayFeed>.value(value: feed, child: const AwayBell()));
    expect(find.byKey(AwayBell.bellKey), findsOneWidget);
    expect(find.bySemanticsLabel('${AwayCopy.bell}, 1 new'), findsOneWidget);

    await tester.tap(find.byKey(AwayBell.bellKey));
    await tester.pumpAndSettle();
    expect(find.text(AwayCopy.title), findsOneWidget);
    expect(find.text('Your partner sent you a little love, 2 times'), findsOneWidget);
  });
}
